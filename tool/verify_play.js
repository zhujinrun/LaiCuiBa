// 一次性验证脚本：真实豆儿猫源 search → detail → play 链路。
// 用法: node tool/verify_play.js
// 不依赖 Flutter，直接起 cat_host.js 宿主，加载真实源，打印每一步的真实返回。
'use strict';

const http = require('http');
const https = require('https');
const { spawn } = require('child_process');
const path = require('path');
const fs = require('fs');

const ROOT = path.resolve(__dirname, '..');
const NODE = path.join(ROOT, 'assets', 'runtime', 'node', 'node.exe');
const HOST = path.join(ROOT, 'assets', 'runtime', 'node', 'cat_host.js');
const TOKEN = 'verify-' + Date.now().toString(16);
const MD5_URL =
  'https://gh-proxy.com/raw.githubusercontent.com/Darklessing/catvod/refs/heads/main/douer/index.js.md5';
const SITE_KEY = 'jianpian'; // spider 注册 key（不带 nodejs_ 前缀）
const SITE_TYPE = '3';

// ---- 小工具 ----
function post(port, pathname, body, headers) {
  return new Promise((resolve, reject) => {
    const data = JSON.stringify(body || {});
    const req = http.request({
      host: '127.0.0.1',
      port,
      path: pathname,
      method: 'POST',
      headers: Object.assign(
        { 'content-type': 'application/json' },
        headers || {},
      ),
    }, (res) => {
      let text = '';
      res.setEncoding('utf8');
      res.on('data', (c) => (text += c));
      res.on('end', () => {
        try { resolve(JSON.parse(text)); } catch { resolve(text); }
      });
    });
    req.on('error', reject);
    req.write(data);
    req.end();
  });
}

function getText(url) {
  return new Promise((resolve, reject) => {
    const mod = url.startsWith('https:') ? https : http;
    mod.get(url, (res) => {
      let text = '';
      res.setEncoding('utf8');
      res.on('data', (c) => (text += c));
      res.on('end', () => resolve({ status: res.statusCode, text }));
    }).on('error', reject);
  });
}

function sleep(ms) { return new Promise((r) => setTimeout(r, ms)); }

async function freePort() {
  return new Promise((resolve) => {
    const s = http.createServer();
    s.listen(0, '127.0.0.1', () => {
      const p = s.address().port;
      s.close(() => resolve(p));
    });
  });
}

async function main() {
  console.log('== 豆儿猫源 play 链路验证 ==\n');
  if (!fs.existsSync(NODE)) { console.error('缺少 node.exe:', NODE); process.exit(1); }
  if (!fs.existsSync(HOST)) { console.error('缺少 cat_host.js:', HOST); process.exit(1); }

  const controlPort = await freePort();
  const tmpDir = fs.mkdtempSync(path.join(require('os').tmpdir(), 'lcb-verify-'));

  console.log('[1] 起 cat_host.js 宿主，控制端口', controlPort);
  const child = spawn(NODE, [HOST, String(controlPort), TOKEN, tmpDir, 'stdin', '0'], {
    stdio: ['pipe', 'inherit', 'inherit'],
  });
  child.stdin.resume();

  // 等 /ping
  for (let i = 0; i < 60; i++) {
    try {
      const ping = await post(controlPort, '/ping', {}, { 'x-token': TOKEN });
      if (ping && ping.ok) break;
    } catch {}
    await sleep(300);
  }

  console.log('[2] 下载豆儿猫源 bundle（首次会拉 ~9MB index.js）');
  const md5 = await getText(MD5_URL);
  console.log('    md5 文件返回:', md5.status, (md5.text || '').trim());
  // 去 .md5 后就是 index.js 本身；config 是同目录的 index.config.js。
  const base = MD5_URL.replace(/\.md5$/, '');
  const js = await getText(base);
  console.log('    index.js 状态:', js.status, '长度', (js.text || '').length);

  // 把 bundle 落到临时目录（index.js + index.config.js）
  const bundleDir = path.join(tmpDir, 'douer');
  fs.mkdirSync(bundleDir, { recursive: true });
  fs.writeFileSync(path.join(bundleDir, 'index.js'), js.text || '');
  try {
    const cfg = await getText(base.replace(/index\.js$/, 'index.config.js'));
    if (cfg.status === 200) fs.writeFileSync(path.join(bundleDir, 'index.config.js'), cfg.text || '');
  } catch {}

  console.log('[3] /load 加载源');
  const loaded = await post(controlPort, '/load', { id: 'douer', dir: bundleDir }, { 'x-token': TOKEN });
  console.log('    返回:', JSON.stringify(loaded));
  const spiderPort = loaded.port;
  if (!spiderPort) { console.error('加载失败，无端口'); process.exit(1); }

  console.log('\n[4] search {wd:"尚公主"}');
  const search = await post(spiderPort, `/spider/${SITE_KEY}/${SITE_TYPE}/search`, { wd: '尚公主' });
  const list = search.list || [];
  console.log('    总数', search.total, '返回', list.length, '条');
  if (list.length) console.log('    首条:', JSON.stringify(list[0]).slice(0, 300));
  const first = list[0];
  const vodId = first && first.vod_id;

  if (!vodId) { console.error('搜索无结果，无法继续'); process.exit(1); }

  console.log('\n[5] detail {id:"' + vodId + '"}');
  const detail = await post(spiderPort, `/spider/${SITE_KEY}/${SITE_TYPE}/detail`, { id: String(vodId) });
  const dlist = detail.list || [];
  const dvod = dlist[0] || {};
  console.log('    vod_id:', dvod.vod_id);
  console.log('    vod_name:', dvod.vod_name);
  console.log('    vod_play_from:', (dvod.vod_play_from || '').slice(0, 200));
  console.log('    vod_play_url 前 300:', (dvod.vod_play_url || '').slice(0, 300));
  console.log('    vod_play_url 长度:', (dvod.vod_play_url || '').length);

  console.log('\n[6] play {id, flag, nid}');
  const flag = 'LZ线路';
  const play = await post(spiderPort, `/spider/${SITE_KEY}/${SITE_TYPE}/play`, {
    id: String(vodId),
    flag,
    nid: 1,
  });
  console.log('    返回:', JSON.stringify(play).slice(0, 400));

  // 提取可播 URL：优先 detail 里已经给全的 vod_play_url（豆儿猫源就是这样），
  // play 返回 parse:1 时反而不是直接地址。
  let url = play && play.url;
  if (url && /^https?:/.test(url)) {
    console.log('    play 直接返回地址:', url);
  } else if (dvod.vod_play_url) {
    // 取第一条线路的第一个可播 URL
    const firstBlock = dvod.vod_play_url.split('$$$')[0];
    const firstEp = firstBlock.split('#')[0];
    url = firstEp.split('$')[1];
    console.log('    play 返回 parse 标记，改用 detail 的 vod_play_url 首条:', url);
  }

  if (url && /^https?:/.test(url)) {
    console.log('\n[7] 探活播放 URL（HEAD）');
    try {
      const head = await new Promise((resolve) => {
        const u = new URL(url);
        const mod = u.protocol === 'https:' ? https : http;
        const req = mod.request({ method: 'HEAD', hostname: u.hostname, port: u.port || (u.protocol === 'https:' ? 443 : 80), path: u.pathname + u.search, timeout: 8000, headers: { 'user-agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)' } }, (res) => {
          resolve({ status: res.statusCode, headers: res.headers });
          res.resume();
        });
        req.on('error', (e) => resolve({ status: -1, err: e.message }));
        req.on('timeout', () => { req.destroy(); resolve({ status: -1, err: 'timeout' }); });
        req.end();
      });
      console.log('    HTTP', head.status, 'content-type', (head.headers && head.headers['content-type']) || '', head.err ? '错误:' + head.err : '');
      console.log('    播放 URL:', url);
    } catch (e) {
      console.log('    探活异常:', e.message);
      console.log('    播放 URL:', url);
    }
  } else {
    console.log('\n[7] 无可播 URL（play 与 detail 均未给地址）');
  }

  // 清理
  child.stdin.end();
  child.kill();
  try { fs.rmSync(tmpDir, { recursive: true, force: true }); } catch {}
  console.log('\n== 完成 ==');
}

main().catch((e) => { console.error('验证异常:', e); process.exit(1); });
