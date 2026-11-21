# -*- coding: utf-8 -*-
"""夹具聚合源：一个文件声明多个平台，靠 ext 里的 `__aggregatePlatform` 选。

它照着原版宿主 `runner.py` 的契约写：`SITES` 说明自己有哪些平台，
`site_home` / `call` / `wrap` 把标准调用转给选中的那一个。`wrap` 把 id 改写成
`平台@@原 id`，详情与播放再带着这个 id 回来 —— 宿主不需要认识平台内部。
"""

from base.spider import Spider as BaseSpider

SITES = [
    {'key': 'alpha', 'name': '甲平台'},
    {'key': 'beta', 'name': '乙平台', 'ext': {'note': 'beta'}},
]


def _vod(platform, vid, name):
    return {
        'vod_id': '%s@@%s' % (platform, vid),
        'vod_name': name,
        'vod_pic': 'http://example.invalid/%s.jpg' % vid,
        'vod_remarks': 'HD',
    }


class Spider(BaseSpider):

    def init(self, extend=""):
        self.extend = extend

    # --- 聚合器自己的接口 -------------------------------------------------

    def site_home(self, platform):
        return {
            'class': [{'type_id': platform + '-1', 'type_name': platform + '分区'}],
            'filters': {},
        }

    def call(self, platform, method, *args):
        if method == 'homeVideoContent':
            return {'list': [_vod(platform, 'rec', platform + '推荐')]}
        if method == 'categoryContent':
            tid, pg, _filter, _extend = args
            return {
                'list': [_vod(platform, 'cat', platform + '分类片')],
                'page': int(pg),
                'pagecount': 2,
                'total': 2,
            }
        if method == 'searchContent':
            keyword, _quick, _pg = args
            return {'list': [_vod(platform, 'hit', keyword)]}
        raise AttributeError('聚合器没有转发 ' + method)

    def wrap(self, platform, items):
        out = []
        for item in items:
            copy = dict(item)
            # id 已经是 `平台@@id`；缺了前缀的平台补上，这样详情一定能路由回来。
            mark = str(copy.get('vod_id', ''))
            if '@@' not in mark:
                copy['vod_id'] = platform + '@@' + mark
            out.append(copy)
        return out

    # --- 标准 TVBox 接口（detail/player 走这里） ---------------------------

    def detailContent(self, ids):
        vid = str(ids[0])
        platform = vid.split('@@', 1)[0]
        return {
            'list': [{
                'vod_id': vid,
                'vod_name': platform + '详情',
                'vod_play_from': '线路一',
                'vod_play_url': '第1集$' + vid,
            }],
        }

    def playerContent(self, flag, id, vipFlags):
        platform = str(id).split('@@', 1)[0]
        return {
            'parse': 0,
            'url': 'http://example.invalid/%s/%s.m3u8' % (platform, id),
            'header': {'Referer': 'http://example.invalid/'},
        }
