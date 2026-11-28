'use strict';

// 最小可验证猫源 —— LaiCuiBa 自研测试夹具。
//
// 它只做一件事：把宿主约定的 catvod 协议实现出来，让宿主（cat_host.js）的
// /load -> /spider/<key>/<type>/<action> -> /unload 全链路能端到端跑通，
// 从而在不依赖任何真实商业源的前提下验证宿主本身。
//
// 协议要点（与宿主实现对照）：
//   1. 宿主在 Worker 里注入 globalThis.catServerFactory(handle) -> http.Server；
//      本文件拿到 server 后自己 listen(0)，宿主在 'listening' 时把端口回传。
//   2. 宿主注入 globalThis.catDartServerPort() 让源能问到 bridge 端口（可选）。
//   3. 所有业务接口形如 POST /spider/<key>/<type>/<action>，body 为 JSON。
//      <key> 是站点 key（不含 nodejs_ 前缀），<type> 是站点类型，
//      <action> 取 init / home / category / detail / search / play。
//
// 真实的猫源内部常用 fastify 起服务；宿主并不关心源用什么框架——只要它
// 调 catServerFactory 拿到 server 并 listen。这里用 node 原生 http 实现，
// 是为了让夹具零依赖（node.exe 是裸的，没有 node_modules）。

const CATALOG = [
  {
    vod_id: 101,
    vod_name: '夹具片甲',
    vod_pic: '',
    vod_remarks: 'HD',
    vod_year: '2026',
    vod_area: '中国大陆',
    type_name: '电影',
    vod_actor: '演员甲/演员乙',
    vod_content: '这是夹具里的第一部影片，用来验证详情与播放。',
    vod_play_from: '夹具线路',
    vod_play_url: '正片$https://example.test/fixture/a.m3u8',
  },
  {
    vod_id: 102,
    vod_name: '夹具片乙',
    vod_pic: '',
    vod_remarks: '更新至2集',
    vod_year: '2025',
    vod_area: '中国大陆',
    type_name: '电视剧',
    vod_actor: '演员丙',
    vod_content: '这是夹具里的第二部影片，带两集。',
    vod_play_from: '夹具线路',
    vod_play_url:
      '第1集$https://example.test/fixture/b1.m3u8#第2集$https://example.test/fixture/b2.m3u8',
  },
];

function json(res, body, code = 200) {
  res.writeHead(code, { 'content-type': 'application/json; charset=utf-8' });
  res.end(JSON.stringify(body));
}

function readBody(req) {
  return new Promise((resolve) => {
    let text = '';
    req.setEncoding('utf8');
    req.on('data', (chunk) => {
      text += chunk;
      if (text.length > 1048576) req.destroy();
    });
    req.on('end', () => {
      try {
        resolve(text ? JSON.parse(text) : {});
      } catch {
        resolve({});
      }
    });
  });
}

function byId(id) {
  return CATALOG.find((v) => String(v.vod_id) === String(id));
}

// 宿主约定的入口：宿主 require 本文件后调用 start(config)。
async function start(config) {
  if (typeof globalThis.catServerFactory !== 'function') {
    throw new Error('宿主没有注入 catServerFactory');
  }

  const server = globalThis.catServerFactory(async (req, res) => {
    if (req.method !== 'POST') return json(res, { error: 'method' }, 405);

    // /spider/<key>/<type>/<action>
    const parts = (req.url || '').split('?')[0].split('/').filter(Boolean);
    if (parts[0] !== 'spider' || parts.length < 4) {
      return json(res, { error: 'not found' }, 404);
    }
    const [, key, type, action] = parts;
    if (key !== 'fixture' && key !== 'fixture-many') {
      return json(res, { error: 'unknown site' }, 404);
    }
    const many = key === 'fixture-many';

    const body = await readBody(req);

    switch (action) {
      case 'init':
        // 源可以在这里校验 token / 配置；夹具直接返回可用。
        return json(res, { ok: true, type, site: key });

      case 'home':
        return json(res, {
          class: many
            ? [
                { type_id: '1', type_name: '电影' },
                { type_id: '2', type_name: '剧集' },
                { type_id: '3', type_name: '综艺' },
                { type_id: '4', type_name: '动漫' },
                { type_id: '63', type_name: '短剧' },
                { type_id: '64', type_name: 'AI漫剧' },
                { type_id: '62', type_name: '少儿' },
              ]
            : [
                { type_id: '1', type_name: '电影' },
                { type_id: '2', type_name: '电视剧' },
              ],
          filters: {},
        });

      case 'category': {
        // 真实的猫源读 `{id, page}`。TVBox 的 `{tid, pg}` 不会被拒，而是静默
        // 返回空列表 —— 夹具照抄这个行为，字段名写错时测试才会红。
        const wanted = String(body.id ?? '');
        const list = many
          ? CATALOG
          : wanted === '2'
            ? CATALOG.filter((v) => v.type_name === '电视剧')
            : wanted === '1'
              ? CATALOG.filter((v) => v.type_name === '电影')
              : [];
        return json(res, {
          page: 1,
          pagecount: 1,
          total: list.length,
          list,
        });
      }

      case 'detail': {
        const one = byId(body.id);
        return json(res, { list: one ? [one] : [] });
      }

      case 'search': {
        const wd = String(body.wd ?? '').trim();
        const list = wd
          ? CATALOG.filter((v) => v.vod_name.includes(wd))
          : CATALOG.slice();
        return json(res, { page: 1, pagecount: 1, total: list.length, list });
      }

      case 'play': {
        const one = byId(body.id);
        if (!one) return json(res, { error: 'no such vod' }, 404);
        // 夹具的“线路”就是一个 URL；nid 选集。
        const urls = String(one.vod_play_url)
          .split('#')
          .map((ep) => ep.split('$')[1])
          .filter(Boolean);
        const nid = Number(body.nid ?? 0);
        const url = urls[Math.max(0, Math.min(nid, urls.length - 1))];
        return json(res, { url, parse: 0 });
      }

      default:
        return json(res, { error: 'unknown action' }, 404);
    }
  });

  // 夹具也顺带验证 catDartServerPort 确实被注入（没有就为 0）。
  if (config && config.expectBridge === true) {
    const port =
      typeof globalThis.catDartServerPort === 'function'
        ? globalThis.catDartServerPort()
        : 0;
    if (!port) throw new Error('宿主没有注入可用的 catDartServerPort');
  }

  server.listen(0, '127.0.0.1');
}

module.exports = { start };
