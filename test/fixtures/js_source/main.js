// 夹具：一个最普通的 TVBox(js) 源。
//
// 刻意用**真实 HTTP**（测试里由 Dart 起一个本地服务）而不是把数据写死在代码里：
// 这样跑通一次，就同时证明了宿主的同步 `req`、`pdfh`/`pdfa` 选择器和五个入口
// 都在真的工作，而不是在背答案。
//
// 站的地址由 `init(ext)` 传进来（TVBox 的 ext 就是这个用处）。

var config = { base: '' };

function init(ext) {
  config.base = String(ext || '');
}

function homeContent(filter) {
  var html = req(config.base + '/home').content;
  var classes = [];
  var items = pdfa(html, 'ul.nav&&li');
  for (var i = 0; i < items.length; i++) {
    classes.push({
      type_id: pdfh(items[i], 'a&&data-id'),
      type_name: pdfh(items[i], 'a&&Text').trim(),
    });
  }
  return { class: classes };
}

function categoryContent(tid, pg, filter, ext) {
  var html = req(config.base + '/list?tid=' + tid + '&pg=' + pg).content;
  var items = pdfa(html, 'div.item');
  var list = [];
  for (var i = 0; i < items.length; i++) {
    list.push({
      vod_id: pdfh(items[i], 'a&&data-id'),
      vod_name: pdfh(items[i], 'a&&Text').trim(),
      vod_pic: pdfh(items[i], 'img&&data-original'),
      vod_remarks: pdfh(items[i], 'span.remark&&Text').trim(),
    });
  }
  return { list: list, page: Number(pg), pagecount: 1, total: list.length, limit: 20 };
}

function searchContent(key, quick, pg) {
  if (key === 'boom') throw new Error('夹具故意炸');
  var html = req(config.base + '/search?wd=' + encodeURIComponent(key)).content;
  var items = pdfa(html, 'div.item');
  var list = [];
  for (var i = 0; i < items.length; i++) {
    list.push({
      vod_id: pdfh(items[i], 'a&&data-id'),
      vod_name: pdfh(items[i], 'a&&Text').trim(),
    });
  }
  return { list: list, page: 1, pagecount: 1, total: list.length };
}

function detailContent(ids) {
  var id = String(ids[0]);
  var html = req(config.base + '/detail?id=' + id).content;
  var eps = pdfa(html, 'ul.eps&&li');
  var play = [];
  for (var i = 0; i < eps.length; i++) {
    play.push('第' + (i + 1) + '集$' + pdfh(eps[i], 'a&&data-url'));
  }
  return {
    list: [
      {
        vod_id: id,
        vod_name: pdfh(html, 'h1&&Text').trim(),
        vod_pic: pdfh(html, 'img.poster&&src'),
        vod_content: pdfh(html, 'p.desc&&Text').trim(),
        vod_play_from: '线路一$$$线路二',
        vod_play_url: play.join('#') + '$$$' + play.join('#'),
      },
    ],
  };
}

function playerContent(flag, id, vipFlags) {
  return {
    parse: 0,
    url: config.base + '/media/' + id + '.m3u8',
    header: { Referer: config.base + '/', 'User-Agent': 'LaiCuiBa-fixture' },
  };
}

function localProxy(params) {
  return [200, 'text/plain', 'proxied:' + params.url];
}
