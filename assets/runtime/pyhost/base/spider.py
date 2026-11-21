# -*- coding: utf-8 -*-
"""TVBox / CatVod Python 源的基类。

流传在网上的 Python 源几乎都是这个形状：

    from base.spider import Spider

    class Spider(Spider):
        def init(self, extend=""): ...
        def homeContent(self, filter): ...
        def categoryContent(self, tid, pg, filter, extend): ...
        def detailContent(self, ids): ...
        def searchContent(self, key, quick, pg="1"): ...
        def playerContent(self, flag, id, vipFlags): ...

它们同时会调用这套基类给的小工具：`fetch/post/html/regStr/cleanText/
getProxyUrl/getCache/setCache`。所以这些口子必须和那份契约一模一样，源才能
一行不改地跑起来 —— 本文件是**按契约重写的实现**，不是搬运原版代码。

返回值的形状也是契约的一部分：`homeContent` 给
`{"class": [{"type_id","type_name"}], "filters": {...}}`，
搜索/分类给 `{"list": [vod...], "page": n, "pagecount": n}`，
详情给 `{"list": [vod]}`，播放给 `{"parse","url","header","jx"}`。
"""

import json
import re
import urllib.parse

import requests

from base.local_proxy import Proxy

# 站点证书过期是常态；关掉这条噪音日志，行为不变（verify 仍由调用方决定）。
requests.packages.urllib3.disable_warnings()

_EMOJI = re.compile(
    '[\U0001F600-\U0001F64F\U0001F300-\U0001F5FF\U0001F680-\U0001F6FF\U0001F1E0-\U0001F1FF]'
)
_TAGS = re.compile('<.*?>')
_VIDEO_EXT = re.compile(
    r'\.(m3u8|mp4|mkv|flv|ts|mov|avi|webm|mpd)(?:\?|$)', re.I
)


class Spider(object):
    """空的源。子类只重写自己用得上的方法。"""

    extend = ''

    # --- 生命周期 ---------------------------------------------------------

    def init(self, extend=""):
        pass

    def destroy(self):
        pass

    def getName(self):
        return ''

    def getDependence(self):
        return []

    def action(self, action):
        pass

    # --- 五个主入口（子类重写） -------------------------------------------

    def homeContent(self, filter):
        pass

    def homeVideoContent(self):
        pass

    def categoryContent(self, tid, pg, filter, extend):
        pass

    def detailContent(self, ids):
        pass

    def searchContent(self, key, quick, pg="1"):
        pass

    def playerContent(self, flag, id, vipFlags):
        pass

    def liveContent(self, url):
        pass

    def localProxy(self, param):
        pass

    # --- HTTP -------------------------------------------------------------

    def fetch(self, url, params=None, cookies=None, headers=None, timeout=5,
              verify=True, stream=False, allow_redirects=True):
        rsp = requests.get(url, params=params, cookies=cookies, headers=headers,
                           timeout=timeout, verify=verify, stream=stream,
                           allow_redirects=allow_redirects)
        rsp.encoding = 'utf-8'
        return rsp

    def post(self, url, params=None, data=None, json=None, cookies=None,
             headers=None, timeout=5, verify=True, stream=False,
             allow_redirects=True):
        rsp = requests.post(url, params=params, data=data, json=json,
                            cookies=cookies, headers=headers, timeout=timeout,
                            verify=verify, stream=stream,
                            allow_redirects=allow_redirects)
        rsp.encoding = 'utf-8'
        return rsp

    def get(self, url, **kwargs):
        """老源把 get() 当 fetch() 的别名用。"""
        return self.fetch(url, **kwargs)

    def head(self, url, **kwargs):
        return requests.head(url, **kwargs)

    def request(self, method, url, **kwargs):
        rsp = requests.request(method, url, **kwargs)
        rsp.encoding = 'utf-8'
        return rsp

    def getJson(self, url, **kwargs):
        try:
            return self.fetch(url, **kwargs).json()
        except Exception:
            return {}

    def postJson(self, url, data=None, headers=None, **kwargs):
        try:
            return self.post(url, json=data, headers=headers, **kwargs).json()
        except Exception:
            return {}

    # --- 解析小工具 -------------------------------------------------------

    def html(self, content):
        from lxml import etree
        return etree.HTML(content)

    def regStr(self, reg, src, group=1):
        m = re.search(reg, src or '')
        return m.group(group) if m else ''

    def removeHtmlTags(self, src):
        return _TAGS.sub('', src or '')

    def cleanText(self, src):
        return _EMOJI.sub('', src or '')

    def str2json(self, text):
        return json.loads(text)

    def json2str(self, value):
        return json.dumps(value, ensure_ascii=False)

    def isVideoFormat(self, url):
        return bool(_VIDEO_EXT.search(str(url or '')))

    def manualVideoCheck(self):
        return False

    def log(self, msg):
        if isinstance(msg, (dict, list)):
            print(json.dumps(msg, ensure_ascii=False))
        else:
            print(msg)

    # --- 本机代理与缓存（走应用侧的 HTTP 服务） ---------------------------

    def getProxyUrl(self, local=True):
        key = getattr(self, '_site_key', '')
        suffix = '&siteKey=' + urllib.parse.quote(key) if key else ''
        return '%s?do=py%s' % (Proxy.getUrl(local), suffix)

    def _cache(self, query, data=None, method='get'):
        url = 'http://127.0.0.1:%d/cache?%s' % (Proxy.getPort(), query)
        if method == 'post':
            return self.post(url, data=data, timeout=5)
        return self.fetch(url, timeout=5)

    def getCache(self, key):
        value = self._cache('do=get&key=' + urllib.parse.quote(str(key), safe='')).text
        if not value:
            return None
        if (value.startswith('{') and value.endswith('}')) or (
                value.startswith('[') and value.endswith(']')):
            try:
                value = json.loads(value)
            except ValueError:
                return value
            if isinstance(value, dict):
                expires = value.get('expiresAt')
                if expires is None:
                    return value
                if expires >= int(__import__('time').time()):
                    return value
                self.delCache(key)
                return None
        return value

    def setCache(self, key, value):
        if isinstance(value, (int, float)):
            value = str(value)
        if isinstance(value, (dict, list)):
            value = json.dumps(value, ensure_ascii=False)
        rsp = self._cache('do=set&key=' + urllib.parse.quote(str(key), safe=''),
                          data={'value': value or ''}, method='post')
        return 'succeed' if rsp.status_code == 200 else 'failed'

    def delCache(self, key):
        rsp = self._cache('do=del&key=' + urllib.parse.quote(str(key), safe=''))
        return 'succeed' if rsp.status_code == 200 else 'failed'

    # --- 依赖（PyramidStore 的下载钩子） ----------------------------------

    def download(self, path, url):
        rsp = self.fetch(url, timeout=30, stream=True)
        with open(path, 'wb') as out:
            for chunk in rsp.iter_content(1024 * 64):
                if chunk:
                    out.write(chunk)
        return ''

    def loadModule(self, name):
        import py_host
        return py_host.host.load_dependence(name)

    def loadSpider(self, name):
        return self.loadModule(name).Spider()
