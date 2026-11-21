# -*- coding: utf-8 -*-
"""夹具 TVBox 源：不联网，只证明宿主把调用送到了正确的地方。

它和网上流传的 Python 源写同一个形状 —— `from base.spider import Spider`、
重写那几个 `*Content`、返回 TVBox 的原始字典 —— 所以宿主、`base/spider.py`
和 Dart 侧解析都能被离线、可重复地验证。

`playerContent` 里带 `proxy` 字段：那个地址是**应用侧**的 `/proxy`，端口由宿主
在启动时下发，所以断言它等于下发的端口，就同时验证了 port 握手。
"""

from base.spider import Spider as BaseSpider

VODS = [
    {
        'vod_id': '1001',
        'vod_name': '夹具电影',
        'vod_pic': 'http://example.invalid/movie.jpg',
        'vod_remarks': 'HD',
        'vod_year': '2026',
    },
    {
        'vod_id': '1002',
        'vod_name': '夹具短剧',
        'vod_pic': 'http://example.invalid/short.jpg',
        'vod_remarks': '更新至2集',
        'vod_year': '2025',
    },
]


class Spider(BaseSpider):

    def init(self, extend=""):
        self.extend = extend

    def homeContent(self, filter):
        return {
            'class': [
                {'type_id': '1', 'type_name': '电影'},
                {'type_id': '2', 'type_name': '剧集'},
            ],
            'filters': {
                '1': [{
                    'key': 'area',
                    'name': '地区',
                    'value': [{'n': '全部', 'v': ''}, {'n': '内地', 'v': '内地'}],
                }],
            },
        }

    def categoryContent(self, tid, pg, filter, extend):
        return {
            'list': [dict(v) for v in VODS],
            'page': int(pg),
            'pagecount': 5,
            'limit': 20,
            'total': 10,
        }

    def detailContent(self, ids):
        vod_id = ids[0] if ids else ''
        # 查不到的 id 回空列表：Dart 侧该把它当成「源说没有」，不是崩溃。
        if vod_id == 'missing':
            return {'list': []}
        return {
            'list': [{
                'vod_id': vod_id,
                'vod_name': '夹具电影',
                'vod_pic': 'http://example.invalid/movie.jpg',
                'vod_year': '2026',
                'vod_area': '内地',
                'vod_remarks': 'HD',
                'vod_actor': '张三,李四',
                'vod_content': '这是夹具源，不联网。',
                # TVBox 的两级分隔：$$$ 分线路，$ 分集名与地址。
                'vod_play_from': '线路一$$$线路二',
                'vod_play_url': (
                    '第1集$http://example.invalid/1.m3u8'
                    '#第2集$http://example.invalid/2.m3u8'
                    '$$$第1集$http://example.invalid/a.m3u8'
                ),
            }],
        }

    def searchContent(self, key, quick, pg="1"):
        # 把关键词写回结果，测试就能证明它真的到过 Python 侧。
        items = [dict(v) for v in VODS]
        items[0]['vod_name'] = '搜索:%s' % key
        items[0]['vod_remarks'] = '严格:%s' % ('开' if quick else '关')
        return {'list': items, 'page': int(pg), 'pagecount': 1}

    def playerContent(self, flag, id, vipFlags):
        # `jx:` 前缀模拟「这条链接要浏览器解析」：TVBox 里 parse=1。
        if id.startswith('jx:'):
            return {'parse': 1, 'url': id[3:], 'header': {}}
        return {
            'parse': 0,
            'url': id,
            'header': {'User-Agent': 'LcbFixture'},
            'proxy': self.getProxyUrl(),
        }

    def localProxy(self, param):
        return [200, 'text/plain; charset=utf-8', 'proxy:' + str(param.get('do', ''))]
