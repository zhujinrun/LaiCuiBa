// LaiCuiBa 猫源宿主（按原版协议重写，不含原版源码）。
//
// 职责：进程内为每个猫源起一个 worker_threads Worker，把宿主注入的
// catServerFactory / catDartServerPort 交给源，源起 fastify 服务后把端口回传。
// Flutter 通过一个带口令的控制端口管理源的生命周期。
//
// 启动参数（位置参数，顺序固定）：
//   node cat_host.js <控制端口> <口令> <临时目录> [stdin] [消息端口]
//   - 控制端口：Flutter 调 /ping /load /unload 的端口，绑定 127.0.0.1。
//   - 口令：控制接口的 x-token 头，不匹配一律 403。
//   - 临时目录：源的 TMPDIR，每个源的数据/库写在它自己的目录下。
//   - stdin（可选）：传 "stdin" 时，标准输入断开即退出（桌面端跟随应用退出）。
//   - 消息端口：源 messageToDart 转发回 Flutter 的端口（手机端无，传 0）。
//
// 控制接口（均为 POST，带 x-token 头）：
//   /ping    -> { ok:true, node: process.version }
//   /load    -> { port }         body: { id, dir }  dir 是源 bundle 目录
//   /unload  -> { ok:true }      body: { id }

'use strict';

const http = require('http');
const path = require('path');
const { Worker } = require('worker_threads');

const [controlPort, token, tmpDir, watch, messagePort] = process.argv.slice(2);
if (tmpDir) process.env.TMPDIR = tmpDir;
if (watch === 'stdin') {
  process.stdin
    .on('end', () => process.exit(0))
    .on('error', () => process.exit(0))
    .resume();
}
process.on('uncaughtException', (e) => console.error('host uncaught', (e && e.stack) || e));
process.on('unhandledRejection', (e) => console.error('host rejection', (e && e.stack) || e));

// 跑在 Worker 里的代码。每个源一个 Worker，避免源之间争抢 globalThis。
const workerCode = String.raw`
const { parentPort, workerData } = require('worker_threads');
const http = require('http');
const path = require('path');
const fs = require('fs');

fs.mkdirSync(process.env.NODE_PATH, { recursive: true });

// 源用这个工厂起自己的 HTTP 服务；返回的 server 必须由源自己 listen。
globalThis.catServerFactory = (handle) => {
  const server = http.createServer((req, res) => handle(req, res));
  server.on('listening', () => parentPort.postMessage({ port: server.address().port }));
  return server;
};

// 源想主动通知 Flutter（toast / 打开网页）时，POST 到本 bridge，
// bridge 再转发到宿主应用的消息端口。只放行白名单动作。
const bridge = http.createServer((req, res) => {
  if (req.method !== 'POST' || req.url !== '/msg' || req.headers.origin) {
    res.writeHead(403); res.end(); return;
  }
  let text = '';
  req.setEncoding('utf8');
  req.on('data', (c) => { text += c; if (text.length > 1048576) req.destroy(); });
  req.on('end', () => {
    let event;
    try { event = JSON.parse(text); } catch { res.writeHead(400); res.end(); return; }
    res.setHeader('content-type', 'application/json');
    if (!['toast', 'openInternalWebview'].includes(event.action)) { res.end('null'); return; }
    const out = http.request({
      host: '127.0.0.1', port: workerData.messagePort, path: '/msg', method: 'POST',
      headers: { 'content-type': 'application/json', 'x-token': workerData.token },
    }, (reply) => { reply.resume(); res.end('null'); });
    out.on('error', () => res.end('null'));
    out.setTimeout(4000, () => out.destroy());
    out.end(JSON.stringify({ ...event, id: workerData.id }));
  });
});
globalThis.catDartServerPort = () => bridge.address()?.port || 0;

bridge.listen(0, '127.0.0.1', () => {
  try {
    const configFile = path.join(workerData.dir, 'index.config.js');
    const loaded = fs.existsSync(configFile) ? require(configFile) : {};
    const source = require(path.join(workerData.dir, 'index.js'));
    if (typeof source.start !== 'function') throw new Error('index.js 没有导出 start()，不是猫源');
    Promise.resolve(source.start(loaded.default || loaded)).catch((e) =>
      parentPort.postMessage({ error: String((e && e.message) || e) }));
  } catch (e) {
    parentPort.postMessage({ error: String((e && e.message) || e) });
  }
});
`;

const sources = new Map();

function load(id, dir) {
  const running = sources.get(id);
  if (running) return running.ready;
  const worker = new Worker(workerCode, {
    eval: true,
    workerData: { dir, id, messagePort: Number(messagePort) || 0, token },
    env: Object.assign({}, process.env, { NODE_PATH: path.join(dir, 'data') }),
  });
  const ready = new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('源启动超时')), 60000);
    worker.on('message', (m) => {
      if (!m || (!m.port && !m.error)) return;
      clearTimeout(timer);
      m.port ? resolve(m.port) : reject(new Error(m.error));
    });
    worker.once('error', (e) => { clearTimeout(timer); reject(e); });
    worker.once('exit', (code) => {
      clearTimeout(timer);
      if (sources.get(id) && sources.get(id).worker === worker) sources.delete(id);
      reject(new Error('源已退出（' + code + '）'));
    });
  });
  ready.catch(() => {
    if (sources.get(id) && sources.get(id).worker === worker) sources.delete(id);
    worker.terminate();
  });
  sources.set(id, { worker, ready });
  return ready;
}

http.createServer((req, res) => {
  const send = (code, body) => {
    res.writeHead(code, { 'content-type': 'application/json' });
    res.end(JSON.stringify(body));
  };
  if (req.headers['x-token'] !== token) return send(403, { error: 'forbidden' });
  if (req.url === '/ping') return send(200, { ok: true, node: process.version });
  let text = '';
  req.setEncoding('utf8');
  req.on('data', (c) => { text += c; });
  req.on('end', async () => {
    try {
      const body = text ? JSON.parse(text) : {};
      if (req.url === '/load') return send(200, { port: await load(String(body.id), String(body.dir)) });
      if (req.url === '/unload') {
        const running = sources.get(String(body.id));
        sources.delete(String(body.id));
        if (running) await running.worker.terminate();
        return send(200, { ok: true });
      }
      send(404, { error: 'not found' });
    } catch (e) {
      send(500, { error: String((e && e.message) || e) });
    }
  });
}).listen(Number(controlPort), '127.0.0.1', () => console.log('cat host ready on ' + controlPort));
