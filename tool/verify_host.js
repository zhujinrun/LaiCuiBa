'use strict';

// 猫源宿主端到端自检（不依赖任何真实商业源）。
//
// 用 test/fixtures/cat_source 这个自研最小猫源，验证 cat_host.js 的完整
// 生命周期：/ping -> /load -> /spider/<key>/<type>/<action> -> /unload，
// 以及 x-token 校验、未知站点、卸载后端口关闭这些边界。
//
// 跑法（必须用工程内自带的 node.exe，版本与原版对齐）：
//   ./assets/runtime/node/node.exe tool/verify_host.js
//
// 退出码 0 = 全通过，1 = 有断言失败。

const { spawn } = require('child_process');
const http = require('http');
const net = require('net');
const path = require('path');
const fs = require('fs');
const os = require('os');

const ROOT = path.resolve(__dirname, '..');
const NODE = path.join(ROOT, 'assets', 'runtime', 'node', 'node.exe');
const HOST = path.join(ROOT, 'assets', 'runtime', 'node', 'cat_host.js');
const FIXTURE = path.join(ROOT, 'test', 'fixtures', 'cat_source');
const TOKEN = 'verify-' + Date.now().toString(16);
const SITE = 'fixture';
const TYPE = 'fixture';

let failures = 0;
function check(ok, label, detail) {
  if (ok) {
    console.log('  PASS  ' + label);
  } else {
    failures++;
    console.log('  FAIL  ' + label + (detail === undefined ? '' : '  <- ' + detail));
  }
}

function freePort() {
  return new Promise((resolve, reject) => {
    const srv = net.createServer();
    srv.on('error', reject);
    srv.listen(0, '127.0.0.1', () => {
      const port = srv.address().port;
      srv.close(() => resolve(port));
    });
  });
}

function post(port, urlPath, body, { token, timeout = 15000 } = {}) {
  return new Promise((resolve) => {
    const payload = JSON.stringify(body || {});
    const req = http.request(
      {
        host: '127.0.0.1',
        port,
        path: urlPath,
        method: 'POST',
        timeout,
        headers: {
          'content-type': 'application/json',
          'content-length': Buffer.byteLength(payload),
          ...(token ? { 'x-token': token } : {}),
        },
      },
      (res) => {
        let text = '';
        res.setEncoding('utf8');
        res.on('data', (c) => (text += c));
        res.on('end', () => {
          let json = null;
          try {
            json = text ? JSON.parse(text) : null;
          } catch {
            /* leave null */
          }
          resolve({ status: res.statusCode, json, text });
        });
      },
    );
    req.on('timeout', () => req.destroy(new Error('timeout')));
    req.on('error', (e) => resolve({ status: 0, json: null, text: String(e) }));
    req.end(payload);
  });
}

function canConnect(port) {
  return new Promise((resolve) => {
    const socket = net.connect({ host: '127.0.0.1', port }, () => {
      socket.destroy();
      resolve(true);
    });
    socket.on('error', () => resolve(false));
    socket.setTimeout(1000, () => {
      socket.destroy();
      resolve(false);
    });
  });
}

async function waitPing(port, deadlineMs) {
  const until = Date.now() + deadlineMs;
  while (Date.now() < until) {
    const r = await post(port, '/ping', {}, { token: TOKEN, timeout: 2000 });
    if (r.status === 200 && r.json && r.json.ok === true) return r.json;
    await new Promise((r2) => setTimeout(r2, 120));
  }
  return null;
}

async function main() {
  console.log('猫源宿主自检');
  console.log('  node    : ' + NODE);
  console.log('  host    : ' + HOST);
  console.log('  fixture : ' + FIXTURE);

  for (const f of [NODE, HOST, path.join(FIXTURE, 'index.js')]) {
    if (!fs.existsSync(f)) {
      console.log('  FATAL   缺少文件：' + f);
      process.exit(1);
    }
  }

  const controlPort = await freePort();
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'lcb-verify-'));
  // 把夹具复制到临时目录再加载：宿主会把源的库写进 bundle 的 data/ 下，
  // 用副本就不会往仓库里写东西；后面的“bundle 更新”用例也改这份副本。
  const workDir = path.join(tmpDir, 'bundle');
  fs.mkdirSync(workDir, { recursive: true });
  for (const name of ['index.js', 'index.config.js']) {
    fs.copyFileSync(path.join(FIXTURE, name), path.join(workDir, name));
  }
  // 不传 stdin 参数：自检进程自己管生命周期，不跟随 stdin。
  const child = spawn(
    NODE,
    [HOST, String(controlPort), TOKEN, tmpDir, '', '0'],
    { stdio: ['ignore', 'pipe', 'pipe'] },
  );
  child.stdout.on('data', () => {});
  child.stderr.on('data', (d) => console.log('  [host] ' + String(d).trim()));

  let exitCode = 1;
  try {
    const ping = await waitPing(controlPort, 12000);
    check(!!ping, '宿主启动并响应 /ping', ping ? undefined : '12s 内没有 ping 通');
    if (!ping) throw new Error('host did not start');
    check(/^v\d+\./.test(ping.node || ''), '报告 node 版本：' + ping.node);

    const wrong = await post(controlPort, '/ping', {}, { token: 'nope' });
    check(wrong.status === 403, '错误 x-token 被拒（403）', 'got ' + wrong.status);

    const loaded = await post(controlPort, '/load', { id: SITE, dir: workDir }, { token: TOKEN });
    let sourcePort = loaded.json && loaded.json.port;
    check(loaded.status === 200 && typeof sourcePort === 'number', '/load 回传源端口', JSON.stringify(loaded.json));
    if (typeof sourcePort !== 'number') throw new Error('no source port');
    check(await canConnect(sourcePort), '源端口可连接');

    const base = '/spider/' + SITE + '/' + TYPE + '/';

    const init = await post(sourcePort, base + 'init', {});
    check(init.status === 200 && init.json && init.json.ok === true, 'init 返回 ok');

    const home = await post(sourcePort, base + 'home', {});
    const classes = (home.json && home.json.class) || [];
    check(Array.isArray(classes) && classes.length === 2, 'home 返回 2 个分类', JSON.stringify(classes));

    const search = await post(sourcePort, base + 'search', { wd: '夹具' });
    const hits = (search.json && search.json.list) || [];
    check(hits.length === 2, 'search 命中 2 条', 'got ' + hits.length);
    const first = hits.find((v) => String(v.vod_id) === '101') || {};
    check(first.vod_name === '夹具片甲', 'search 带出片名', first.vod_name);

    const detail = await post(sourcePort, base + 'detail', { id: 101 });
    const dlist = (detail.json && detail.json.list) || [];
    check(dlist.length === 1 && dlist[0].vod_name === '夹具片甲', 'detail 按 id 返回记录');

    const play0 = await post(sourcePort, base + 'play', { id: 102, nid: 0 });
    check(play0.json && play0.json.url && play0.json.url.endsWith('/b1.m3u8'), 'play nid=0 取第 1 集', play0.json && play0.json.url);
    const play1 = await post(sourcePort, base + 'play', { id: 102, nid: 1 });
    check(play1.json && play1.json.url && play1.json.url.endsWith('/b2.m3u8'), 'play nid=1 取第 2 集', play1.json && play1.json.url);

    const unknown = await post(sourcePort, '/spider/nope/' + TYPE + '/home', {});
    check(unknown.status === 404, '未知站点返回 404', 'got ' + unknown.status);

    // bundle 被重新下载覆盖后，宿主必须重起 Worker 跑新代码，而不是继续
    // 用 require 缓存里的旧模块。这里改一处片名来模拟订阅更新。
    const jsPath = path.join(workDir, 'index.js');
    const before = fs.readFileSync(jsPath, 'utf8');
    fs.writeFileSync(jsPath, before.replace('夹具片甲', '夹具片甲二版'));
    await new Promise((r) => setTimeout(r, 60)); // 让 mtime 明确变化
    const reloaded = await post(controlPort, '/load', { id: SITE, dir: workDir }, { token: TOKEN });
    const newPort = reloaded.json && reloaded.json.port;
    check(typeof newPort === 'number', 'bundle 更新后 / 重载成功', JSON.stringify(reloaded.json));
    if (typeof newPort === 'number') {
      sourcePort = newPort;
      const after = await post(sourcePort, base + 'detail', { id: 101 });
      const name = after.json && after.json.list && after.json.list[0] && after.json.list[0].vod_name;
      check(name === '夹具片甲二版', '重载后跑的是新代码', name);
    }

    const unloaded = await post(controlPort, '/unload', { id: SITE }, { token: TOKEN });
    check(unloaded.status === 200, '/unload 返回 200', 'got ' + unloaded.status);
    // 终止 Worker 后源端口应当不再接受连接。
    const alive = await canConnect(sourcePort);
    check(!alive, '卸载后源端口已关闭');

    console.log(failures === 0 ? '\n全部通过' : '\n失败 ' + failures + ' 项');
    exitCode = failures === 0 ? 0 : 1;
  } catch (e) {
    console.log('  FATAL   ' + ((e && e.message) || e));
    exitCode = 1;
  } finally {
    child.kill();
    await new Promise((r) => setTimeout(r, 300));
    try {
      fs.rmSync(tmpDir, { recursive: true, force: true });
    } catch {
      /* best effort */
    }
  }
  process.exit(exitCode);
}

main();
