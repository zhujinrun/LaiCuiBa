'use strict';
// LaiCuiBa 的组件（Widget）宿主。
//
// 兼容 CapyPlayer / Forward 的公开组件格式：脚本顶层必须 `var WidgetMetadata = {...}`，
// modules[].functionName 指向全局 async function，函数返回 MediaItem[]。
// 协议跟 cat_host.js / js_site_host.js 一样：一行 JSON 进、一行 JSON 出，
// 标准输出只给协议，组件自己的 console 全部去 stderr 并记进返回包。
//
// 组件跑在 vm 上下文里，但没有进程级隔离：它仍能按脚本自己的意图访问网络，
// 所以只应安装来源可信的组件（原版同一句警告）。

const fs = require('fs');
const path = require('path');
const vm = require('vm');
const http = require('http');
const https = require('https');
const tls = require('tls');
const readline = require('readline');

function reply(payload) {
  try {
    fs.writeSync(1, JSON.stringify(payload) + '\n');
  } catch (_) {
    // 父进程已经关闭管道，别再刷。
  }
}

function pretty(value) {
  if (typeof value === 'string') return value;
  try {
    return JSON.stringify(value);
  } catch (_) {
    return String(value);
  }
}

const SENSITIVE = /(token|authorization|cookie|password|secret|apikey)/i;
const logs = [];
function logLine(prefix, args) {
  const text = args
    .map((a) => {
      let s = pretty(a);
      if (SENSITIVE.test(s)) s = s.replace(/(:\s*)[^,\s}]+/g, '$1***');
      return s.replace(/([?&][^=\s]+=)[^&\s]+/g, '$1***');
    })
    .join(' ')
    .slice(0, 2000);
  const line = prefix + ' ' + text;
  logs.push(line);
  if (logs.length > 200) logs.shift();
  fs.writeSync(2, line + '\n');
}

// ---------------------------------------------------------------------------
// Widget.http —— 基本的 HTTP 客户端，带可选 HTTP(S) 代理。
// ---------------------------------------------------------------------------

let proxyUrl = process.env.LCB_WIDGET_PROXY || '';

function proxyAuth(headers, target) {
  const out = Object.assign({}, headers || {});
  if (target.username || target.password) {
    const raw = decodeURIComponent(target.username) + ':' + decodeURIComponent(target.password);
    out['Proxy-Authorization'] = 'Basic ' + Buffer.from(raw).toString('base64');
  }
  return out;
}

function collect(resolve, reject) {
  return (res) => {
    const chunks = [];
    res.on('data', (chunk) => chunks.push(chunk));
    res.on('end', () => {
      const body = Buffer.concat(chunks).toString('utf8');
      let data = body;
      const ct = String((res.headers && res.headers['content-type']) || '');
      if (ct.indexOf('json') >= 0) {
        try {
          data = JSON.parse(body);
        } catch (_) {
          /* 留原文给组件自己解析 */
        }
      }
      const headers = {};
      for (const key of Object.keys(res.headers || {})) {
        const value = res.headers[key];
        headers[key] = Array.isArray(value) ? value : [String(value)];
      }
      resolve({ ok: res.statusCode >= 200 && res.statusCode < 300, status: res.statusCode || 0, data, headers });
    });
    res.on('error', reject);
  };
}

function send(u, method, headers, body, resolve, reject) {
  const target = proxyUrl ? new URL(proxyUrl) : null;
  if (!target || u.protocol === 'http:') {
    const mod = u.protocol === 'https:' ? https : http;
    const options = target
      ? {
          host: target.hostname,
          port: Number(target.port) || (target.protocol === 'https:' ? 443 : 80),
          method,
          path: u.toString(),
          headers: proxyAuth(headers, target),
        }
      : {
          hostname: u.hostname,
          port: u.port || undefined,
          method,
          path: u.pathname + u.search,
          headers,
        };
    const req = mod.request(options, collect(resolve, reject));
    req.on('error', reject);
    if (body != null) req.write(body);
    req.end();
    return;
  }

  // HTTPS through an HTTP proxy: CONNECT first, then TLS over that socket.
  const tunnel = http.request(
    {
      host: target.hostname,
      port: Number(target.port) || 80,
      method: 'CONNECT',
      path: u.hostname + ':' + (u.port || 443),
      headers: proxyAuth({}, target),
    },
  );
  tunnel.on('error', reject);
  tunnel.on('connect', (res, socket) => {
    if (res.statusCode !== 200) {
      reject(new Error('组件代理 CONNECT ' + res.statusCode));
      return;
    }
    const secured = tls.connect({ socket, servername: u.hostname }, () => {
      const req = https.request(
        {
          hostname: u.hostname,
          port: u.port || 443,
          method,
          path: u.pathname + u.search,
          headers,
          createConnection: () => secured,
          agent: false,
        },
        collect(resolve, reject),
      );
      req.on('error', reject);
      if (body != null) req.write(body);
      req.end();
    });
    secured.on('error', reject);
  });
  tunnel.end();
}

function request(method, url, options) {
  const opts = options || {};
  return new Promise((resolve, reject) => {
    let u;
    try {
      u = new URL(url);
    } catch (error) {
      reject(error);
      return;
    }
    if (opts.params && typeof opts.params === 'object') {
      for (const key of Object.keys(opts.params)) {
        const value = opts.params[key];
        if (value !== undefined && value !== null) u.searchParams.set(key, String(value));
      }
    }
    const headers = Object.assign({}, opts.headers || {});
    let body = null;
    if (opts.data !== undefined && opts.data !== null) {
      body = typeof opts.data === 'string' ? opts.data : JSON.stringify(opts.data);
      if (!headers['Content-Type'] && !headers['content-type']) {
        headers['Content-Type'] = 'application/json';
      }
      headers['Content-Length'] = Buffer.byteLength(body);
    }
    const timer = setTimeout(() => reject(new Error('组件网络超时')), Number(opts.timeout) || 30000);
    send(u, (method || 'GET').toUpperCase(), headers, body, (value) => {
      clearTimeout(timer);
      resolve(value);
    }, (error) => {
      clearTimeout(timer);
      reject(error);
    });
  });
}

let domLib = null;
try {
  domLib = require(path.join(__dirname, 'linkedom.js'));
} catch (_) {
  /* DOM API 不可用时，用到它的组件会明确失败 */
}
const documents = new Map();
let documentId = 0;

const Widget = {
  http: {
    get: (url, options) => request('GET', url, options),
    post: (url, body, options) => request('POST', url, Object.assign({}, options || {}, { data: body })),
    request: (options) => request(options.method || 'GET', options.url, options),
  },
  storage: {
    values: new Map(),
    get(key, fallback) {
      return this.values.has(String(key)) ? this.values.get(String(key)) : fallback;
    },
    async getAsync(key, fallback) {
      return this.get(key, fallback);
    },
    set(key, value) {
      this.values.set(String(key), value);
    },
    remove(key) {
      this.values.delete(String(key));
    },
  },
  dom: {
    parse(html) {
      if (!domLib) throw new Error('组件 DOM 解析库不存在');
      const id = 'doc-' + ++documentId;
      documents.set(id, domLib.parseHTML(String(html)));
      return id;
    },
    select(id, selector) {
      const doc = documents.get(id);
      return doc ? Array.from(doc.document.querySelectorAll(String(selector))) : [];
    },
    text(node) {
      return node && node.textContent ? node.textContent.trim() : '';
    },
    attr(node, name) {
      return node && node.getAttribute ? node.getAttribute(String(name)) : null;
    },
    remove(id) {
      documents.delete(id);
    },
  },
};

// ---------------------------------------------------------------------------
// 脚本加载与元数据
// ---------------------------------------------------------------------------

const cached = new Map();
const FUNCTION_NAME = /^[A-Za-z_$][A-Za-z0-9_$]*(\.[A-Za-z_$][A-Za-z0-9_$]*)*$/;

function loadScript(scriptPath) {
  const file = path.resolve(String(scriptPath));
  if (cached.has(file)) return cached.get(file);
  if (!fs.existsSync(file)) throw new Error('组件脚本不存在：' + file);
  if (fs.statSync(file).size > 8 * 1024 * 1024) throw new Error('组件文件过大');
  const code = fs.readFileSync(file, 'utf8');
  const context = vm.createContext({
    Widget,
    URL,
    URLSearchParams,
    TextEncoder,
    TextDecoder,
    Buffer,
    console: {
      log: (...args) => logLine('[组件]', args),
      info: (...args) => logLine('[组件]', args),
      warn: (...args) => logLine('[组件警告]', args),
      error: (...args) => logLine('[组件错误]', args),
    },
    setTimeout,
    clearTimeout,
    setInterval,
    clearInterval,
    fetch: async (url, options) => {
      const opts = options || {};
      const resp = await request(opts.method || 'GET', String(url), {
        headers: opts.headers,
        params: opts.params,
        timeout: opts.timeout,
        data: opts.body,
      });
      return {
        ok: resp.ok,
        status: resp.status,
        json: async () => (typeof resp.data === 'string' ? JSON.parse(resp.data) : resp.data),
        text: async () => pretty(resp.data),
      };
    },
  });
  vm.runInContext(code, context, { filename: file, timeout: 10000 });
  const entry = { context, file };
  cached.set(file, entry);
  return entry;
}

function normalizeMeta(raw) {
  if (!raw || typeof raw !== 'object') throw new Error('WidgetMetadata 不是对象');
  const title = String(raw.title || raw.name || '').trim();
  if (!title) throw new Error('组件标题不能为空');
  const modules = (Array.isArray(raw.modules) ? raw.modules : [])
    .filter((module) => module && typeof module === 'object' && FUNCTION_NAME.test(String(module.functionName || '')))
    .map((module) => ({
      id: String(module.id || module.functionName),
      title: String(module.title || module.name || module.functionName),
      type: String(module.type || (module.type === 'category' ? 'category' : 'media_list')),
      functionName: String(module.functionName),
      cacheDuration: Number(module.cacheDuration) || 0,
      timeoutSeconds: Number(module.timeoutSeconds || module.timeoutMs / 1000 || module.timeout || 30),
      description: String(module.description || ''),
      params: Array.isArray(module.params) ? module.params : [],
    }));
  if (modules.length === 0) throw new Error('No supported modules found');
  return {
    id: String(raw.id || '').replace(/[^A-Za-z0-9._-]/g, '_'),
    title,
    description: String(raw.description || ''),
    version: String(raw.version || '1.0.0'),
    author: String(raw.author || ''),
    site: String(raw.site || ''),
    icon: String(raw.icon || raw.iconUrl || ''),
    modules,
  };
}

function metadata(scriptPath) {
  const entry = loadScript(scriptPath);
  if (!Object.prototype.hasOwnProperty.call(entry.context, 'WidgetMetadata')) {
    throw new Error('WidgetMetadata not found in script');
  }
  const meta = normalizeMeta(entry.context.WidgetMetadata);
  if (!meta.id) meta.id = require('crypto').createHash('md5').update(entry.file).digest('hex').slice(0, 12);
  return meta;
}

function single(raw, key, fallbacks) {
  for (const name of [key].concat(fallbacks)) {
    const value = raw[name];
    if (value !== undefined && value !== null && value !== '') return value;
  }
  return null;
}

async function callData(scriptPath, functionName, params) {
  const entry = loadScript(scriptPath);
  if (!FUNCTION_NAME.test(String(functionName || ''))) {
    throw new Error('Data source function not found: ' + functionName);
  }
  let fn = entry.context;
  for (const part of String(functionName).split('.')) {
    fn = fn ? fn[part] : undefined;
  }
  if (typeof fn !== 'function') {
    throw new Error('Data source function not found: ' + functionName);
  }
  const answer = await fn.call(entry.context, params || {});
  if (!Array.isArray(answer)) throw new Error('Data source must return an array');
  const items = answer.filter((item) => item && typeof item === 'object').map((item, index) => {
    const poster = single(item, 'posterUrl', ['poster_url', 'poster', 'posterPath']);
    const backdrop = single(item, 'backdropUrl', ['backdrop_url', 'backdrop', 'coverUrl', 'backdropPath']);
    const video = single(item, 'videoUrl', ['video_url']);
    return {
      id: String(single(item, 'id', ['mediaId']) || ('item_' + index)),
      title: String(single(item, 'title', ['name']) || ''),
      image: poster || backdrop || '',
      backdrop: backdrop || '',
      description: String(single(item, 'description', ['overview']) || ''),
      rating: item.rating == null ? null : Number(item.rating),
      year: single(item, 'year', ['releaseDate', 'release_date', 'date']),
      mediaType: String(single(item, 'mediaType', ['media_type']) || ''),
      type: String(item.type || ''),
      link: single(item, 'link', []),
      videoUrl: video,
    };
  });
  return { items, logs: logs.slice(-40) };
}


function urlOf(item, fallbacks) {
  for (const key of ['videoUrl'].concat(fallbacks || [])) {
    if (item && item[key]) return String(item[key]);
  }
  return '';
}

async function callDetail(scriptPath, link) {
  const entry = loadScript(scriptPath);
  const fn = entry.context.loadDetail;
  if (typeof fn !== 'function') throw new Error('loadDetail function not found');
  const answer = await fn.call(entry.context, link);
  if (!answer) return { detail: null, logs: logs.slice(-40) };

  let raw = answer;
  if (Array.isArray(raw)) {
    if (raw.length && (raw[0].seasons || raw[0].episodes || raw[0].episodeItems)) {
      raw = raw[0];
    } else {
      raw = { playSources: raw };
    }
  }

  const lines = [];
  const direct = urlOf(raw, ['video_url', 'url']);
  if (direct) lines.push({ name: '组件', url: direct });
  for (const source of (raw.playSources || raw.play_sources || [])) {
    const url = urlOf(source, ['video_url', 'url', 'path', 'link']);
    if (url) lines.push({ name: String(source.title || source.name || source.label || '线路'), url });
  }

  const seasons = [];
  const allEpisodes = [];
  for (const season of (raw.seasons || [])) {
    const episodes = [];
    for (const episode of (season.episodes || season.episodeItems || season.episode_items || [])) {
      const labels = [];
      if (season.seasonNumber || season.season_number) labels.push('S' + (season.seasonNumber || season.season_number));
      if (episode.episodeNumber || episode.episode_number) labels.push('E' + (episode.episodeNumber || episode.episode_number));
      const label = labels.join('') || String(episode.title || '剧集');
      const url = urlOf(episode, ['video_url']);
      if (url) episodes.push({ label, url });
      const sources = (episode.playSources || episode.play_sources || []).map((s) => ({
        name: String(s.title || s.name || '线路'),
        url: urlOf(s, ['video_url', 'url', 'path', 'link']),
      })).filter((s) => s.url);
      for (const source of sources) episodes.push({ label: label + ' · ' + source.name, url: source.url });
    }
    if (episodes.length) seasons.push({ number: Number(season.seasonNumber || season.season_number || 0), episodes });
  }
  for (const episode of (raw.episodeItems || raw.episodes || [])) {
    const label = 'E' + String(episode.episodeNumber || episode.episode_number || '');
    const url = urlOf(episode, ['video_url']);
    if (url) allEpisodes.push({ label, url });
    for (const source of (episode.playSources || episode.play_sources || [])) {
      const sourceUrl = urlOf(source, ['video_url', 'url', 'path', 'link']);
      if (sourceUrl) allEpisodes.push({ label: label + ' · ' + String(source.title || source.name || '线路'), url: sourceUrl });
    }
  }

  const tags = (Array.isArray(raw.tags) ? raw.tags : [])
    .map((tag) => String(tag && tag.name ? tag.name : tag).trim())
    .filter((tag) => tag.length);
  const cast = [];
  const credits = raw.credits || {};
  for (const person of (credits.cast || raw.cast || raw.actors || [])) {
    if (person && person.name) cast.push(String(person.name));
  }

  return {
    detail: {
      title: String(raw.title || raw.name || ''),
      mediaType: String(raw.mediaType || raw.media_type || ''),
      lines,
      seasons,
      episodes: allEpisodes,
      tags,
      cast,
    },
    logs: logs.slice(-40),
  };
}

readline.createInterface({ input: process.stdin, crlfDelay: Infinity }).on('line', async (line) => {
  let request;
  try {
    request = JSON.parse(line);
  } catch (_) {
    return;
  }
  try {
    let result;
    if (request.op === 'ping') {
      result = 'widget-1';
    } else if (request.op === 'call') {
      const args = JSON.parse(request.args || '[]');
      if (request.method === 'proxy') {
        proxyUrl = String(args[0] || '');
        result = 'ok';
      } else if (request.method === 'meta') {
        result = JSON.stringify(metadata(args[0]));
      } else if (request.method === 'data') {
        result = JSON.stringify(await callData(args[0], args[1], args[2] || {}));
      } else if (request.method === 'detail') {
        result = JSON.stringify(await callDetail(args[0], String(args[1] || '')));
      } else {
        throw new Error('未知的组件操作：' + request.method);
      }
    } else {
      throw new Error('未知的协议操作：' + request.op);
    }
    reply({ id: request.id, ok: true, result });
  } catch (error) {
    reply({ id: request.id, ok: false, error: error && error.message ? error.message : String(error) });
  }
});
