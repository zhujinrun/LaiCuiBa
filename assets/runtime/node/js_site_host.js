'use strict';
// LaiCuiBa 的 TVBox(js) 源宿主。
//
// 与猫源宿主 (cat_host.js) 不是一回事：猫源是 catvod 的 `start(config)` 模块，
// 这个宿主跑的是 TVBox 生态里 `api` 以 `.js` 结尾的站点 —— 它们由一套**同步**
// 的全局函数写成：
//
//     function init(cfg) { ... }
//     function homeContent(filter) { var html = req(HOST); ... }
//     function categoryContent(tid, pg, filter, ext) { ... }
//     function detailContent(ids) { ... }
//     function searchContent(key, quick, pg) { ... }
//     function playerContent(flag, id, vipFlags) { ... }
//
// 安卓上这些函数跑在 QuickJS 里，`req` / `pdfh` / `pdfa` 由宿主注入。这里把
// 同一套注入实现出来，Node 就变成一个 TVBox js 运行时。
//
// 协议与 py_host.py 完全一致（一行 JSON 进、一行 JSON 出），所以 Dart 侧只需要
// 一个宿主实现就能同时驱动 Python 和 js：
//
//     {"id":1,"op":"ping"}
//     {"id":2,"op":"port","port":38111}
//     {"id":3,"op":"call","key":"...","path":"D:/src/main.js","ext":"",
//      "method":"home","args":"[true]"}
//     {"id":4,"op":"proxy","params":"{\"do\":\"js\"}"}
//     {"id":5,"op":"release","key":"..."}
//     {"id":6,"op":"sites","path":"D:/src/main.js"}
//
// 两条硬约束：
//   * 标准输出只给协议（用 fs.writeSync 直写 fd 1），源的 print/console 全去
//     标准错误 —— 源里一句 console.log 把协议冲掉是这类宿主最常见的翻车方式；
//   * `req` 必须**同步**返回，因为源全是同步写法。Node 没有同步 HTTP，这里用
//     一个常驻 worker 做请求、主线程 Atomics.wait 等结果（见 SyncHttp）。

const fs = require('fs');
const path = require('path');
const vm = require('vm');
const crypto = require('crypto');
const readline = require('readline');
const { Worker } = require('worker_threads');

// ---------------------------------------------------------------------------
// 协议
// ---------------------------------------------------------------------------

let writeFailed = false;

function reply(payload) {
  const line = JSON.stringify(payload) + '\n';
  try {
    fs.writeSync(1, line);
  } catch (e) {
    // 父进程已经退出（管道断了）：别再刷屏，让进程自己结束。
    writeFailed = true;
  }
}

function logToStderr(...args) {
  try {
    fs.writeSync(2, args.map((a) => (typeof a === 'string' ? a : pretty(a))).join(' ') + '\n');
  } catch (e) {
    /* stderr 也断了 */
  }
}

function pretty(value) {
  if (value instanceof Error) return value.stack || value.message;
  try {
    return JSON.stringify(value);
  } catch (e) {
    return String(value);
  }
}

// ---------------------------------------------------------------------------
// 同步 HTTP：主线程等着，worker 干活
// ---------------------------------------------------------------------------
//
// 共享内存布局（Int32 头部 + 数据区）：
//   flag[0] 请求待处理 0/1     flag[1] 完成 0/1      flag[2] 请求长度
//   flag[3] 响应头长度         flag[4] 响应体长度    flag[5] HTTP 状态码
//   flag[6] generation        flag[7] 退出 0/1
//   DATA[0 ..) 请求 JSON / 响应头 JSON；DATA[BODY_OFF ..) 响应体

const HEAD_OFF = 32;
const BODY_OFF = 8192;
const DATA_BYTES = 16 * 1024 * 1024;
const MAX_RESPONSE = DATA_BYTES - BODY_OFF;

const HTTP_WORKER = String.raw`
const http = require('http');
const https = require('https');
const zlib = require('zlib');
const { parentPort, workerData } = require('worker_threads');

const sab = workerData.sab;
const flag = new Int32Array(sab, 0, 8);
const data = new Uint8Array(sab, ${HEAD_OFF});
const body = new Uint8Array(sab, ${BODY_OFF});
const encoder = new TextEncoder();
const decoder = new TextDecoder();

function finish(gen, status, headers, payload) {
  const head = encoder.encode(JSON.stringify({ headers }));
  if (head.length > ${BODY_OFF - HEAD_OFF - 16}) {
    Atomics.store(flag, 5, 599);
    Atomics.store(flag, 3, 0);
    Atomics.store(flag, 4, 0);
  } else {
    data.set(head, 0);
    Atomics.store(flag, 3, head.length);
    Atomics.store(flag, 5, status | 0);
    Atomics.store(flag, 4, payload.length);
  }
  Atomics.store(flag, 6, gen);
  Atomics.store(flag, 1, 1);
  Atomics.notify(flag, 1);
}

function fail(gen, message) {
  const head = encoder.encode(JSON.stringify({ error: String(message) }));
  data.set(head.subarray(0, Math.min(head.length, ${BODY_OFF - HEAD_OFF - 16})), 0);
  Atomics.store(flag, 3, Math.min(head.length, ${BODY_OFF - HEAD_OFF - 16}));
  Atomics.store(flag, 4, 0);
  Atomics.store(flag, 5, 599);
  Atomics.store(flag, 6, gen);
  Atomics.store(flag, 1, 1);
  Atomics.notify(flag, 1);
}

function request(req) {
  const gen = req.gen;
  let url;
  try {
    url = new URL(req.url);
  } catch (e) {
    return fail(gen, '网址不合法: ' + req.url);
  }
  const lib = url.protocol === 'https:' ? https : http;
  const options = {
    method: (req.method || 'GET').toUpperCase(),
    headers: req.headers || {},
    timeout: Math.max(1000, Math.min(Number(req.timeout) || 20000, 60000)),
  };
  let done = false;
  const r = lib.request(url, options, (res) => {
    const status = res.statusCode || 0;
    // 跟随重定向：安卓版 req 默认跟随，源常常直接写不带 http 的短链。
    if (status >= 300 && status < 400 && res.headers.location && (req.redirect || 0) < 5) {
      done = true;
      res.resume();
      const next = new URL(res.headers.location, url).toString();
      return request({ ...req, url: next, redirect: (req.redirect || 0) + 1 });
    }
    const encoding = String(res.headers['content-encoding'] || '').toLowerCase();
    let stream = res;
    if (encoding === 'gzip') stream = res.pipe(zlib.createGunzip());
    else if (encoding === 'deflate') stream = res.pipe(zlib.createInflate());
    else if (encoding === 'br') stream = res.pipe(zlib.createBrotliDecompress());

    const chunks = [];
    let size = 0;
    stream.on('data', (chunk) => {
      size += chunk.length;
      if (size > ${MAX_RESPONSE}) {
        r.destroy(new Error('响应超过 ${Math.round(MAX_RESPONSE / 1048576)}MB'));
        return;
      }
      chunks.push(chunk);
    });
    stream.on('end', () => {
      if (done) return;
      done = true;
      const payload = Buffer.concat(chunks);
      const copy = payload.subarray(0, Math.min(payload.length, ${MAX_RESPONSE}));
      body.set(copy, 0);
      finish(gen, status, res.headers, copy);
    });
    stream.on('error', (e) => {
      if (done) return;
      done = true;
      fail(gen, e && e.message ? e.message : String(e));
    });
  });
  r.on('timeout', () => r.destroy(new Error('请求超时')));
  r.on('error', (e) => {
    if (done) return;
    done = true;
    fail(gen, e && e.message ? e.message : String(e));
  });
  if (req.body !== undefined && req.body !== null && req.body !== '') r.write(req.body);
  r.end();
}

// 主循环：等请求 -> 取走 -> 发 HTTP（异步）-> 回调里回填并通知 -> 再等。
function loop() {
  const state = Atomics.load(flag, 0);
  if (state === 0) {
    Atomics.wait(flag, 0, 0, 500);
    return setImmediate(loop);
  }
  if (Atomics.load(flag, 7) === 1 || state === 4) return process.exit(0);
  if (state !== 1) {
    Atomics.wait(flag, 0, state, 50);
    return setImmediate(loop);
  }
  Atomics.store(flag, 0, 0);
  const len = Atomics.load(flag, 2);
  let req;
  try {
    req = JSON.parse(decoder.decode(data.subarray(0, len)));
  } catch (e) {
    return setImmediate(loop);
  }
  try {
    request(req);
  } catch (e) {
    fail(req.gen, e && e.message ? e.message : String(e));
  }
  setImmediate(loop);
}

loop();
`;

class SyncHttp {
  constructor() {
    this.sab = new SharedArrayBuffer(HEAD_OFF + DATA_BYTES);
    this.flag = new Int32Array(this.sab, 0, 8);
    this.data = new Uint8Array(this.sab, HEAD_OFF);
    this.body = new Uint8Array(this.sab, BODY_OFF);
    this.encoder = new TextEncoder();
    this.decoder = new TextDecoder();
    this.generation = 0;
    this.worker = new Worker(HTTP_WORKER, {
      eval: true,
      workerData: { sab: this.sab },
    });
    this.worker.on('error', (e) => logToStderr('[sync http]', e));
    this.worker.unref();
  }

  /// 同步发一个请求，返回 { code, headers, content, buffer }。
  request(spec) {
    const gen = ++this.generation;
    const payload = this.encoder.encode(
      JSON.stringify({
        gen,
        url: spec.url,
        method: spec.method,
        headers: spec.headers,
        body: spec.body,
        timeout: spec.timeout,
        redirect: 0,
      })
    );
    const room = BODY_OFF - HEAD_OFF - 16;
    if (payload.length > room) throw new Error('请求头过大');

    Atomics.store(this.flag, 1, 0);
    Atomics.store(this.flag, 2, payload.length);
    this.data.set(payload, 0);
    Atomics.store(this.flag, 0, 1);
    Atomics.notify(this.flag, 0);

    const timeout = Math.max(1000, Math.min(Number(spec.timeout) || 20000, 60000));
    const waited = Atomics.wait(this.flag, 1, 0, timeout + 500);
    if (waited !== 'ok') {
      // 超时。此时 worker 可能还在跑，它回来后会往这块内存里写结果；先把它
      // 等完再交还，否则下一次请求会把上一个请求的结果当成自己的。
      Atomics.wait(this.flag, 1, 0, 2000);
      Atomics.store(this.flag, 1, 0);
      throw new Error('请求超时');
    }
    // 迟到的应答（上一个请求的结果）不能当成自己的。
    const got = Atomics.load(this.flag, 6);
    const status = Atomics.load(this.flag, 5);
    const headLen = Atomics.load(this.flag, 3);
    const bodyLen = Atomics.load(this.flag, 4);
    if (got !== gen) throw new Error('请求超时');
    if (status === 599) {
      let message = '请求失败';
      try {
        message = JSON.parse(this.decoder.decode(this.data.subarray(0, headLen))).error || message;
      } catch (e) {
        /* 保持默认 */
      }
      throw new Error(message);
    }
    let headers = {};
    try {
      headers = JSON.parse(this.decoder.decode(this.data.subarray(0, headLen))).headers || {};
    } catch (e) {
      headers = {};
    }
    const content = this.decoder.decode(this.body.subarray(0, bodyLen));
    let buffer;
    if (spec.buffer) {
      buffer = Buffer.from(this.body.subarray(0, bodyLen)).toString('base64');
    }
    return { code: status, headers, content, buffer };
  }

  stop() {
    Atomics.store(this.flag, 7, 1);
    Atomics.store(this.flag, 0, 4);
    Atomics.notify(this.flag, 0);
    this.worker.terminate().catch(() => {});
  }
}

let syncHttp = null;

function httpClient() {
  if (!syncHttp) syncHttp = new SyncHttp();
  return syncHttp;
}

// ---------------------------------------------------------------------------
// HTML 选择器（pdfh / pdfa）
// ---------------------------------------------------------------------------

const { parseHTML } = require('./linkedom.js');

const HTML_TAGS = new Set([
  'a', 'abbr', 'article', 'aside', 'b', 'blockquote', 'body', 'br', 'button',
  'dd', 'div', 'dl', 'dt', 'em', 'figure', 'footer', 'form', 'h1', 'h2', 'h3',
  'h4', 'h5', 'h6', 'head', 'header', 'hr', 'html', 'i', 'iframe', 'img',
  'input', 'label', 'li', 'main', 'nav', 'ol', 'option', 'p', 'picture', 'pre',
  'script', 'section', 'select', 'small', 'source', 'span', 'strong', 'style',
  'table', 'tbody', 'td', 'textarea', 'th', 'thead', 'tr', 'ul', 'video',
]);

function toDocument(html) {
  if (html && typeof html === 'object' && typeof html.querySelectorAll === 'function') {
    return html;
  }
  if (html && typeof html === 'object' && html.document) return html.document;
  return parseHTML(String(html === undefined || html === null ? '' : html)).document;
}

/// `div.item:eq(0)` -> 先选 `div.item` 再按序号取。
function applySelector(node, selector) {
  const match = /^(.*?):eq\((-?\d+)\)$/.exec(selector);
  if (match) {
    const all = [...node.querySelectorAll(match[1] || '*')];
    let index = Number(match[2]);
    if (index < 0) index += all.length;
    const one = all[index];
    return one ? [one] : [];
  }
  const lt = /^(.*?):lt\((\d+)\)$/.exec(selector);
  if (lt) return [...node.querySelectorAll(lt[1] || '*')].slice(0, Number(lt[2]));
  const gt = /^(.*?):gt\((\d+)\)$/.exec(selector);
  if (gt) return [...node.querySelectorAll(gt[1] || '*')].slice(Number(gt[2]) + 1);
  try {
    return [...node.querySelectorAll(selector)];
  } catch (e) {
    return [];
  }
}

/// 最后一段是属性还是选择器：`a` 是标签，`href` 是属性，`div.x` 是选择器。
///
/// 判据先看 CSS 特征（`.` `#` `[` 空格 `>` `:`），再看是不是已知标签名，
/// 都不像才当属性 —— 反过来「像标识符就是属性」会把 `div.item` 吃成属性。
function looksLikeAttribute(segment) {
  if (/^(Text|Html|HTML|Tag|text|html|tag)$/i.test(segment)) return true;
  if (segment.startsWith('!')) return true;
  if (/[.#\[\]\s>+~:]/.test(segment)) return false;
  if (HTML_TAGS.has(segment.toLowerCase())) return false;
  return /^[A-Za-z_][-A-Za-z0-9_]*$/.test(segment);
}

function readAttribute(element, attribute) {
  const name = attribute.toLowerCase();
  if (name === 'text') return element.textContent || '';
  if (name === 'html') return element.innerHTML || '';
  if (name === 'tag') return element.tagName || '';
  if (name === '!text') return (element.textContent || '').replace(/\s+/g, ' ').trim();
  if (name === '!html') return (element.innerHTML || '').replace(/\s+/g, ' ').trim();
  const value = element.getAttribute(attribute);
  return value === null || value === undefined ? '' : String(value);
}

function absolute(value, base) {
  if (!base || !value) return value;
  try {
    return new URL(value, base).toString();
  } catch (e) {
    return value;
  }
}

/// 沿规则链走到底，返回元素列表（最后一段是属性时返回字符串列表）。
function walk(html, rule, base) {
  const doc = toDocument(html);
  const segments = String(rule || '')
    .split('&&')
    .map((part) => part.trim())
    .filter(Boolean);
  if (!segments.length) return { nodes: [], values: null, attribute: null };

  let nodes = [doc];
  for (let i = 0; i < segments.length; i++) {
    const segment = segments[i];
    const last = i === segments.length - 1;
    if (last && looksLikeAttribute(segment) && i > 0) {
      const values = [];
      for (const node of nodes) {
        const text = readAttribute(node, segment);
        values.push(segment.toLowerCase() === 'href' || segment.toLowerCase() === 'src'
          ? absolute(text, base)
          : text);
      }
      return { nodes: [], values, attribute: segment };
    }
    const next = [];
    for (const node of nodes) {
      const found = applySelector(node, segment);
      for (const element of found) next.push(element);
    }
    nodes = next;
    if (!nodes.length) return { nodes: [], values: null, attribute: null };
  }
  return { nodes, values: null, attribute: null };
}

function pdfh(html, rule, base) {
  const result = walk(html, rule, base);
  if (result.values) return result.values[0] === undefined ? '' : result.values[0];
  const first = result.nodes[0];
  return first ? (first.outerHTML || first.textContent || '') : '';
}

function pdfa(html, rule, base) {
  const result = walk(html, rule, base);
  if (result.values) return result.values;
  return result.nodes.map((node) => node.outerHTML || node.textContent || '');
}

function pdfH(html, rule, base) {
  return pdfh(html, rule, base);
}

function pdfA(html, rule, base) {
  return pdfa(html, rule, base);
}

/// `pd` 返回元素对象（安卓版给的是可继续查询的节点）。
function pd(html, rule) {
  return walk(html, rule).nodes;
}

// ---------------------------------------------------------------------------
// 源模块加载
// ---------------------------------------------------------------------------

/// 源在文件顶层定义的入口。TVBox 的 QuickJS 引擎就是直接在全局上找这些名字。
const ENTRY_NAMES = [
  'init', 'homeContent', 'homeVideoContent', 'categoryContent', 'detailContent',
  'searchContent', 'playerContent', 'liveContent', 'localProxy', 'action',
  'getName', 'isVideoFormat', 'manualVideoCheck', 'destroy', 'SITES', 'rule',
];

/// 在源文件末尾补一段导出探针：`var` 会挂到 context 的全局上，但 `const`/`let`
/// 不会，只有用 `typeof` 在同一个作用域里取一次才稳。
const PROBE = '\n;globalThis.__lcbExports = {' +
  ENTRY_NAMES.map((name) => `${name}: (typeof ${name} !== 'undefined' ? ${name} : undefined)`).join(',') +
  '};\n';

const _modules = new Map();
const _instances = new Map();
/// 最近一次创建/使用的实例。`/proxy` 的 query 里不一定带 siteKey，py_host.py
/// 用一个「最近的源」兜底，这里保持同一个口径。
let _recentKey = '';

function loadModule(file) {
  const absolutePath = path.resolve(file);
  const cached = _modules.get(absolutePath);
  if (cached) return cached;
  if (!fs.existsSync(absolutePath)) throw new Error('源文件不存在: ' + absolutePath);

  let code = fs.readFileSync(absolutePath, 'utf8').replace(/^\uFEFF/, '');
  // 少量源写成 ESM。Node 的 vm 只认 CJS，把 `export default` 换掉即可。
  code = code.replace(/export\s+default\s+/g, 'module.exports = ');

  const module = { exports: {} };
  const sandbox = {
    module,
    exports: module.exports,
    require: makeRequire(path.dirname(absolutePath)),
    console: {
      log: logToStderr,
      info: logToStderr,
      warn: logToStderr,
      error: logToStderr,
      debug: logToStderr,
    },
    print: logToStderr,
    Buffer,
    URL,
    URLSearchParams,
    TextEncoder,
    TextDecoder,
    setTimeout,
    clearTimeout,
    setInterval,
    clearInterval,
    setImmediate,
    queueMicrotask,
    crypto,
    atob: (value) => Buffer.from(String(value), 'base64').toString('binary'),
    btoa: (value) => Buffer.from(String(value), 'binary').toString('base64'),
    ...injectedGlobals(),
  };
  sandbox.global = sandbox;
  sandbox.globalThis = sandbox;

  const context = vm.createContext(sandbox);
  vm.runInContext(code + PROBE, context, {
    filename: absolutePath,
    timeout: 30000,
  });

  const exported = sandbox.__lcbExports || {};
  const fromModule = module.exports && (module.exports.default || module.exports);
  const record = { file: absolutePath, context, exported, fromModule };
  _modules.set(absolutePath, record);
  return record;
}

/// 源的 `require`：放行 Node 内置模块与同目录文件，别让它去 require 我们的宿主。
function makeRequire(dir) {
  const builtin = new Set([
    'http', 'https', 'url', 'crypto', 'zlib', 'fs', 'path', 'querystring',
    'util', 'stream', 'events', 'buffer', 'string_decoder', 'net', 'tls',
  ]);
  return function localRequire(name) {
    if (builtin.has(name)) return require(name);
    if (String(name).startsWith('.')) return require(path.resolve(dir, name));
    throw new Error('源不能 require ' + name);
  };
}

/// 宿主状态：`/proxy` 的端口与当前站点，源的 `getProxyUrl()` 靠它拼地址。
const hostState = { port: 0, siteKey: '' };

/// TVBox 注入的全局。`req` 在这里被实现成同步函数，源的写法才能原样跑。
function injectedGlobals() {
  return {
    req: function req(url, options) {
      return requestSync(url, options);
    },
    joinUrl: function joinUrl() {
      const parts = [...arguments]
        .filter((part) => part !== undefined && part !== null && part !== '')
        .map((part) => String(part));
      if (!parts.length) return '';
      // 源里 joinUrl 的用法就是「基址 + 相对路径」，逐段去掉重复的斜杠即可；
      // 用 URL 解析会在相对基址上抛错，也会把 `../` 吃掉得莫名其妙。
      return parts.reduce((base, part) => {
        if (!base) return part;
        return base.replace(/\/+$/, '') + '/' + part.replace(/^\/+/, '');
      }, '');
    },
    base64Encode: (value) => Buffer.from(String(value), 'utf8').toString('base64'),
    base64Decode: (value) => Buffer.from(String(value), 'base64').toString('utf8'),
    md5: (value) => crypto.createHash('md5').update(String(value), 'utf8').digest('hex'),
    md5X: (value) => crypto.createHash('md5').update(String(value), 'utf8').digest('hex'),
    pdfh,
    pdfa,
    pdfH,
    pdfA,
    pd,
    local: globalLocal,
    // 源把海报/播放列表拼成 `getProxyUrl('&url=...')`，交回宿主去换 referer、
    // 解混淆。地址指向应用自己的 /proxy，参数原样保留。
    getProxyUrl: function getProxyUrl(extra) {
      if (!hostState.port) return '';
      const tail = extra === undefined || extra === null ? '' : String(extra);
      const join = tail && !tail.startsWith('&') && !tail.startsWith('?') ? '&' + tail : tail;
      return (
        'http://127.0.0.1:' +
        hostState.port +
        '/proxy?siteKey=' +
        encodeURIComponent(hostState.siteKey) +
        '&do=js' +
        join
      );
    },
    // TVBox 的 setCache/getCache 是宿主缓存，不是 local 那种永久键值。
    setCache: (key, value) => {
      cacheStore.set(String(key), String(value));
      return true;
    },
    getCache: (key) => (cacheStore.has(String(key)) ? cacheStore.get(String(key)) : ''),
    delCache: (key) => {
      cacheStore.delete(String(key));
      return true;
    },
  };
}

const cacheStore = new Map();

/// `local`：TVBox 给的键值存储。这里落在宿主旁边的 `js-local.json`，
/// 同一次运行内是内存，进程退出前写盘。
const LOCAL_FILE = path.join(process.env.LCB_JS_DATA || path.dirname(process.argv[1] || '.'), 'js-local.json');
const localData = (() => {
  try {
    return JSON.parse(fs.readFileSync(LOCAL_FILE, 'utf8')) || {};
  } catch (e) {
    return {};
  }
})();
let localDirty = false;

const globalLocal = {
  get(key) {
    return Object.prototype.hasOwnProperty.call(localData, key) ? localData[key] : '';
  },
  set(key, value) {
    localData[key] = value;
    localDirty = true;
    return true;
  },
  delete(key) {
    delete localData[key];
    localDirty = true;
    return true;
  },
};

function flushLocal() {
  if (!localDirty) return;
  try {
    fs.writeFileSync(LOCAL_FILE, JSON.stringify(localData));
    localDirty = false;
  } catch (e) {
    /* 落盘失败不影响这次运行 */
  }
}

/// 一次同步请求，返回 TVBox `req` 的形状：{ code, headers, content }。
function requestSync(url, options) {
  let opts = options;
  if (typeof opts === 'string') {
    try {
      opts = JSON.parse(opts);
    } catch (e) {
      opts = {};
    }
  }
  if (!opts || typeof opts !== 'object') opts = {};
  let body = opts.body;
  if (body !== undefined && body !== null && typeof body !== 'string' && !Buffer.isBuffer(body)) {
    body = JSON.stringify(body);
  }
  const spec = {
    url: String(url || ''),
    method: opts.method || 'GET',
    headers: normalizeHeaders(opts.headers),
    body,
    timeout: opts.timeout || opts.timeOut,
    buffer: Boolean(opts.buffer),
  };
  if (!spec.url) throw new Error('req 缺少网址');
  const answer = httpClient().request(spec);
  return {
    code: answer.code,
    status: answer.code,
    headers: answer.headers,
    content: answer.content,
    buffer: answer.buffer,
  };
}

function normalizeHeaders(raw) {
  const out = {};
  if (!raw) return out;
  if (typeof raw === 'string') {
    for (const line of raw.split(/\r?\n/)) {
      const index = line.indexOf(':');
      if (index > 0) out[line.slice(0, index).trim()] = line.slice(index + 1).trim();
    }
    return out;
  }
  for (const key of Object.keys(raw)) {
    if (raw[key] !== undefined && raw[key] !== null) out[key] = String(raw[key]);
  }
  return out;
}

function entryOf(record, name) {
  const direct = record.exported[name];
  if (direct !== undefined) return direct;
  const fallback = record.fromModule;
  if (fallback && typeof fallback === 'object' && fallback[name] !== undefined) {
    return fallback[name];
  }
  if (name === 'homeContent' && fallback && fallback.homeContent) return fallback.homeContent;
  return undefined;
}

/// 源可能是 `function init(){}` 的散函数，也可能是 `module.exports = {...}`；
/// 后者统一搬到一个对象上，调用方只看得到「有这个方法」。
function instance(key, file, ext) {
  const cached = _instances.get(key);
  if (cached && cached.file === path.resolve(file)) return cached;
  const record = loadModule(file);
  const target = {};
  for (const name of ENTRY_NAMES) {
    const value = entryOf(record, name);
    if (value !== undefined) target[name] = value;
  }
  target.__file = record.file;
  target.__context = record.context;
  // `getProxyUrl()` 拼的是 /proxy?siteKey=…，所以实例一建好就把站点名交给宿主。
  hostState.siteKey = key;
  // 每个源一把「初始化过没有」的标记，而不是重跑 init —— 有的源在 init 里登录。
  if (typeof target.init === 'function' && !target.__inited) {
    const started = target.init(ext || '');
    target.__inited = true;
    // 同步源写法的 init 不该返回 Promise；真返回了就说明它用了异步 API，
    // 这里等不了（调用链是同步的），但要留一行日志，别静默丢错误。
    if (started && typeof started.then === 'function') {
      started.catch((e) => logToStderr('[init]', e));
    }
  }
  _instances.set(key, target);
  _recentKey = key;
  return target;
}

// ---------------------------------------------------------------------------
// 调用分发（方法名与 py_host.py 保持一致）
// ---------------------------------------------------------------------------

function textOf(value) {
  if (value === undefined || value === null) return '';
  if (typeof value === 'string') return value;
  if (Buffer.isBuffer(value)) return value.toString('utf8');
  try {
    return JSON.stringify(value);
  } catch (e) {
    return String(value);
  }
}

function argAt(args, index, fallback) {
  return args[index] === undefined || args[index] === null ? fallback : args[index];
}

async function call(key, file, ext, method, args) {
  const spider = instance(key, file, ext);
  const need = (name) => {
    const found = spider[name];
    if (typeof found !== 'function') throw new Error('源没有实现 ' + name);
    return found;
  };

  switch (method) {
    case 'init':
      return '';
    case 'home':
      return textOf(await need('homeContent')(argAt(args, 0, true)));
    case 'homeVideo':
      return textOf(await need('homeVideoContent')());
    case 'category':
      return textOf(
        await need('categoryContent')(
          String(argAt(args, 0, '')),
          String(argAt(args, 1, '1')),
          Boolean(argAt(args, 2, true)),
          argAt(args, 3, {}) || {}
        )
      );
    case 'detail':
      return textOf(await need('detailContent')([String(argAt(args, 0, ''))]));
    case 'search':
      return textOf(
        await need('searchContent')(
          argAt(args, 0, ''),
          Boolean(argAt(args, 1, false)),
          String(argAt(args, 2, '1'))
        )
      );
    case 'player':
      return textOf(
        await need('playerContent')(
          argAt(args, 0, ''),
          argAt(args, 1, ''),
          argAt(args, 2, []) || []
        )
      );
    case 'live':
      return textOf(await need('liveContent')(argAt(args, 0, '')));
    case 'getName':
      return textOf(need('getName')());
    case 'isVideoFormat':
      return textOf(Boolean(need('isVideoFormat')(String(argAt(args, 0, '')))));
    case 'manualVideoCheck':
      return textOf(Boolean(need('manualVideoCheck')()));
    case 'action':
      return textOf(await need('action')(argAt(args, 0, '')));
    default:
      throw new Error('unknown method ' + method);
  }
}

function normaliseSites(raw) {
  const out = [];
  if (!raw) return out;
  if (Array.isArray(raw)) {
    for (const item of raw) {
      if (typeof item === 'string' && item) out.push({ key: item, name: item });
      else if (item && typeof item === 'object') {
        const key = item.key || item.id;
        if (!key) continue;
        const entry = { key: String(key), name: String(item.name || key) };
        if (item.ext !== undefined && item.ext !== '') entry.ext = item.ext;
        out.push(entry);
      }
    }
    return out;
  }
  if (typeof raw === 'object') {
    for (const key of Object.keys(raw)) {
      const value = raw[key];
      const entry = { key: String(key), name: String(key) };
      if (typeof value === 'string' && value) entry.name = value;
      else if (value && typeof value === 'object') {
        if (value.name) entry.name = String(value.name);
        if (value.ext !== undefined && value.ext !== '') entry.ext = value.ext;
      }
      out.push(entry);
    }
  }
  return out;
}

function sites(file) {
  const record = loadModule(file);
  return normaliseSites(record.exported.SITES);
}

function proxy(key, params) {
  const wanted = key || (params && params.siteKey) || _recentKey;
  const spider = _instances.get(wanted);
  if (!spider) throw new Error('没有可用的源实例');
  if (typeof spider.localProxy !== 'function') {
    throw new Error('这个 js 源没有实现 localProxy');
  }
  const result = spider.localProxy(params);
  if (!Array.isArray(result) || result.length < 3) {
    throw new Error('localProxy 应返回 [状态码, 类型, 内容]');
  }
  const headers = result[3] === undefined ? '{}' : textOf(result[3]);
  const body = result[2];
  return {
    status: Number(result[0]) || 200,
    mime: String(result[1] || 'text/plain'),
    body: Buffer.isBuffer(body) ? body.toString('base64') : Buffer.from(String(body || ''), 'utf8').toString('base64'),
    headers,
  };
}

function release(key) {
  const spider = _instances.get(key);
  _instances.delete(key);
  if (spider && typeof spider.destroy === 'function') {
    try {
      spider.destroy();
    } catch (e) {
      logToStderr('[destroy]', e);
    }
  }
}

// ---------------------------------------------------------------------------
// 请求循环：串行（同步 req 会把事件循环占住，并发没有意义）
// ---------------------------------------------------------------------------

let queue = Promise.resolve();

function handle(request) {
  const op = request.op;
  if (op === 'ping') return Promise.resolve(process.version);
  if (op === 'port') {
    hostState.port = Number(request.port) || 0;
    return Promise.resolve('');
  }
  if (op === 'call') {
    return call(
      request.key,
      request.path,
      request.ext || '',
      request.method,
      JSON.parse(request.args || '[]')
    );
  }
  if (op === 'sites') return Promise.resolve(sites(request.path));
  if (op === 'proxy') return Promise.resolve(proxy(request.key || '', JSON.parse(request.params || '{}')));
  if (op === 'release') {
    release(request.key);
    return Promise.resolve('');
  }
  return Promise.reject(new Error('unknown op ' + op));
}

function onLine(line) {
  const trimmed = line.trim();
  if (!trimmed) return;
  let request;
  try {
    request = JSON.parse(trimmed);
  } catch (e) {
    return;
  }
  queue = queue.then(async () => {
    try {
      const result = await handle(request);
      reply({ id: request.id, ok: true, result });
    } catch (e) {
      reply({
        id: request.id,
        ok: false,
        error: (e && e.name ? e.name : 'Error') + ': ' + (e && e.message ? e.message : String(e)),
      });
    }
  });
  if (writeFailed) process.exit(0);
}

if (process.env.LCB_JS_DATA) fs.mkdirSync(process.env.LCB_JS_DATA, { recursive: true });

const rl = readline.createInterface({ input: process.stdin, crlfDelay: Infinity });
rl.on('line', onLine);
rl.on('close', () => {
  flushLocal();
  if (syncHttp) syncHttp.stop();
  process.exit(0);
});
process.on('uncaughtException', (e) => logToStderr('[uncaught]', e));
process.on('unhandledRejection', (e) => logToStderr('[rejection]', e));
process.on('exit', flushLocal);
