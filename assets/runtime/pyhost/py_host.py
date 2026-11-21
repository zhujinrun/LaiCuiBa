# -*- coding: utf-8 -*-
"""LaiCuiBa 的 Python 源宿主。

一行 JSON 进、一行 JSON 出（stdin/stdout）。每个请求一个线程，慢源不会挡住
下一个请求；标准输出只留给协议，源自己 print 的东西全部改到标准错误 —— 源里
随手一句 print 把协议冲掉，是这类宿主最容易踩的坑。

请求：
    {"id":1,"op":"ping"}
    {"id":2,"op":"port","port":38111}
    {"id":3,"op":"call","key":"...","path":"D:/src/main.py","ext":"",
     "method":"home","args":"[true]"}
    {"id":4,"op":"proxy","params":"{\"do\":\"py\"}"}
    {"id":5,"op":"release","key":"..."}
    {"id":6,"op":"sites","path":"D:/src/main.py"}

应答：{"id":n,"ok":true,"result":...} / {"id":n,"ok":false,"error":"Type: msg"}

`call` 的 result 是**字符串**：源返回的 dict/list 在这里就序列化好，Dart 侧拿到
的正是 TVBox 的原始响应体，解析口径和猫源一致。
"""

import base64
import importlib.util
import inspect
import json
import os
import sys
import threading
import traceback

HERE = os.path.dirname(os.path.abspath(__file__))
# 源里写 `from base.spider import Spider`，靠的就是这一行。
if HERE not in sys.path:
    sys.path.insert(0, HERE)

_out = sys.stdout.buffer
sys.stdout = sys.stderr  # 协议专用 stdout，源的东西全去 stderr


def _crawler_shim():
    """让 `from com.github.catvod.crawler import Spider` 落到 Python 基类上。

    有些源优先继承「宿主自带」的 Java 爬虫基类，导入失败才退回自己的基类。
    安卓上 Chaquopy 真能导入那个 Java 类，接着 Python 类去继承 Java 类会直接
    失败；桌面宿主没有这个类，不垫一层的话源连加载都过不去。
    """
    import types

    def make(name):
        module = types.ModuleType(name)

        def __getattr__(attr):
            if attr == 'Spider':
                from base.spider import Spider
                return Spider
            raise AttributeError(attr)

        module.__getattr__ = __getattr__
        return module

    for name in ('com', 'com.github', 'com.github.catvod',
                 'com.github.catvod.crawler'):
        sys.modules.setdefault(name, make(name))


_crawler_shim()

import base.local_proxy as local_proxy  # noqa: E402


def _text(value):
    if value is None:
        return ''
    if isinstance(value, (bytes, bytearray)):
        return bytes(value).decode('utf-8', 'replace')
    if isinstance(value, str):
        return value
    return json.dumps(value, ensure_ascii=False, default=str)


def _invoke(fn, *args):
    """按源的参数个数裁剪实参：老源常少写一个参数，多传会 TypeError。"""
    try:
        count = len(inspect.signature(fn).parameters)
    except (TypeError, ValueError):
        count = len(args)
    return fn(*args[:count])


def _platform(ext):
    """聚合源选中的子平台，从 `{"__aggregatePlatform": "..."}` 里取。

    不是 JSON 对象的 ext（普通源常见的空串或随意字符串）一律视为没有平台，
    免得把普通源的 `init` 参数当成聚合指令。
    """
    if isinstance(ext, str) and ext.lstrip().startswith('{'):
        try:
            ext = json.loads(ext)
        except Exception:
            return ''
    if not isinstance(ext, dict):
        return ''
    return str(ext.get('__aggregatePlatform') or '')


def _normalise_sites(raw):
    """把源里 `SITES` 的几种写法统一成 [{key, name, ext?}]。

    见过的写法：list of dict（TVBox 站点条目）、dict（key → 名字或条目）、
    list of str。其余形状一律当「没有 SITES」——宁可少展开一个源，
    也不要凭猜测把一坨键名画成站点。
    """
    out = []
    if isinstance(raw, dict):
        for key, value in raw.items():
            entry = {'key': str(key), 'name': str(key)}
            if isinstance(value, dict):
                for field in ('name', 'title', 'ext'):
                    if value.get(field) not in (None, ''):
                        entry[field] = value[field]
            elif isinstance(value, str) and value:
                entry['name'] = value
            out.append(entry)
        return out
    if not isinstance(raw, (list, tuple)):
        return []
    for item in raw:
        if isinstance(item, str) and item:
            out.append({'key': item, 'name': item})
        elif isinstance(item, dict):
            key = item.get('key') or item.get('id')
            if not key:
                continue
            entry = {'key': str(key), 'name': str(item.get('name') or key)}
            if item.get('ext') not in (None, ''):
                entry['ext'] = item['ext']
            out.append(entry)
    return out


class Host(object):
    def __init__(self):
        self.port = 0
        self._spiders = {}
        self._locks = {}
        self._recent = None
        self._guard = threading.Lock()

    # --- 模块与实例 -------------------------------------------------------

    def instance(self, key, path, ext):
        spider = self._spiders.get(key)
        if spider is not None:
            return spider
        with self._guard:
            init_lock = self._locks.setdefault(key, threading.Lock())
        # 每个源一把初始化锁：不同源可以同时 init（init 通常要联网）。
        with init_lock:
            spider = self._spiders.get(key)
            if spider is not None:
                return spider
            module = self._load(key, path)
            cls = getattr(module, 'Spider', None)
            # T4 规范允许源只导出模块级函数。
            spider = cls() if cls is not None else module
            try:
                spider._site_key = key
            except Exception:
                pass
            # 记住这个文件是不是聚合源：它声明了 SITES 却拿不到平台时，
            # 报一句能看懂的话，比回一屏空白强。
            try:
                spider._declares_sites = bool(getattr(module, 'SITES', None))
            except Exception:
                pass
            init = getattr(spider, 'init', None)
            if init is not None:
                _invoke(init, ext or '')
            self._spiders[key] = spider
            self._recent = key
            return spider

    def sites(self, path):
        """列出一个文件把自己展开成哪些站点（聚合源的 `SITES`）。

        只加载模块、不创建实例、不 `init`：这一步是「这个文件认识哪些平台」，
        不是「去抓一次数据」。文件没有 `SITES` 就返回空列表，调用方据此知道
        它是个单站点源。
        """
        module = self._load('probe|%s' % path, path)
        return _normalise_sites(getattr(module, 'SITES', None))

    def _load(self, key, path):
        path = os.path.abspath(path)
        if not os.path.isfile(path):
            raise IOError('源文件不存在: %s' % path)
        name = 'pysrc_%s' % abs(hash(key))
        folder = os.path.dirname(path)
        # 源可能 import 同目录的兄弟模块。
        if folder not in sys.path:
            sys.path.insert(0, folder)
        spec = importlib.util.spec_from_file_location(name, path)
        module = importlib.util.module_from_spec(spec)
        sys.modules[name] = module
        spec.loader.exec_module(module)
        return module

    def load_dependence(self, name):
        """PyramidStore 的依赖钩子：只认宿主目录旁 `deps/<name>.py`。"""
        path = os.path.join(HERE, 'deps', '%s.py' % name)
        if not os.path.isfile(path):
            raise IOError('没有这个依赖: %s（宿主不会自动下载）' % name)
        return self._load('dep|' + name, path)

    # --- 调用 -------------------------------------------------------------

    def call(self, key, path, ext, method, args_json):
        spider = self.instance(key, path, ext)
        args = json.loads(args_json) if args_json else []

        def arg(index, default=None):
            return args[index] if index < len(args) and args[index] is not None \
                else default

        def fn(*names):
            for n in names:
                found = getattr(spider, n, None)
                if found is not None:
                    return found
            raise AttributeError('源没有实现 %s' % names[0])

        # 聚合源：配置里一个 main.py 展开成多个平台，ext 带上
        # `__aggregatePlatform`。标准调用转给选中的子平台，列表再用源自己的
        # `wrap` 包一层（它会把 id 改成 `平台@@id`，详情和播放才能路由回来）。
        platform = _platform(ext)
        if not platform and getattr(spider, '_declares_sites', False):
            raise ValueError('这是聚合源，要先选平台（ext 缺少 __aggregatePlatform）')
        if platform:
            if not hasattr(spider, 'call') or not hasattr(spider, 'wrap'):
                raise AttributeError('该 Python 源不支持平台展开')
            if method == 'home':
                home = spider.site_home(platform) if hasattr(spider, 'site_home') else {}
                home = home if isinstance(home, dict) else {}
                return _text({'class': home.get('class', []),
                              'filters': home.get('filters', {})})
            if method in ('homeVideo', 'category', 'search'):
                if method == 'homeVideo':
                    data = spider.call(platform, 'homeVideoContent')
                elif method == 'category':
                    data = spider.call(platform, 'categoryContent',
                                       str(arg(0, '')), str(arg(1, '1')),
                                       bool(arg(2, True)), arg(3, {}) or {})
                else:
                    data = spider.call(platform, 'searchContent', arg(0, ''),
                                       bool(arg(1, False)), str(arg(2, '1')))
                data = dict(data) if isinstance(data, dict) else {}
                data['list'] = spider.wrap(platform, data.get('list', []))
                return _text(data)
            # detail / player / localProxy 直接用 wrap 过的 `平台@@id`，
            # 聚合器自己会路由，所以落到下面的标准分发。

        if method == 'init':
            return ''
        if method == 'home':
            return _text(_invoke(fn('homeContent', 'getHomeContent'),
                                 bool(arg(0, True))))
        if method == 'homeVideo':
            return _text(_invoke(fn('homeVideoContent', 'getHomeVideoContent')))
        if method == 'category':
            return _text(_invoke(fn('categoryContent', 'getCategoryContent'),
                                 str(arg(0, '')), str(arg(1, '1')),
                                 bool(arg(2, True)), arg(3, {}) or {}))
        if method == 'detail':
            return _text(_invoke(fn('detailContent', 'getDetailContent'),
                                 [arg(0, '')]))
        if method == 'search':
            return _text(_invoke(fn('searchContent', 'getSearchContent'),
                                 arg(0, ''), bool(arg(1, False)),
                                 str(arg(2, '1'))))
        if method == 'player':
            return _text(_invoke(fn('playerContent', 'getPlayerContent'),
                                 arg(0, ''), arg(1, ''), arg(2, []) or []))
        if method == 'live':
            return _text(_invoke(fn('liveContent'), arg(0, '')))
        if method == 'download':
            return _text(_invoke(fn('download'), str(arg(0, '')),
                                 str(arg(1, ''))))
        if method == 'isVideoFormat':
            return _text(bool(spider.isVideoFormat(str(arg(0, '')))))
        if method == 'manualVideoCheck':
            return _text(bool(spider.manualVideoCheck()))
        if method == 'getName':
            return _text(spider.getName())
        if method == 'getDependence':
            return _text(spider.getDependence())
        if method == 'action':
            return _text(spider.action(arg(0, '')))
        raise ValueError('unknown method %s' % method)

    def proxy(self, params_json):
        params = json.loads(params_json or '{}')
        key = params.get('siteKey') or self._recent
        if not key or key not in self._spiders:
            raise LookupError('没有可用的源实例')
        result = self._spiders[key].localProxy(params)
        if not isinstance(result, (list, tuple)) or len(result) < 3:
            raise ValueError('localProxy 应返回 [状态码, 类型, 内容]')
        status = int(result[0])
        mime = str(result[1] or 'text/plain')
        body = result[2] or b''
        if isinstance(body, str):
            body = body.encode('utf-8')
        headers = result[3] if len(result) > 3 else '{}'
        if not isinstance(headers, str):
            headers = json.dumps(headers or {}, default=str)
        return {
            'status': status,
            'mime': mime,
            'body': base64.b64encode(bytes(body)).decode('ascii'),
            'headers': headers,
        }

    def release(self, key):
        with self._guard:
            spider = self._spiders.pop(key, None)
            self._locks.pop(key, None)
            if self._recent == key:
                self._recent = None
        destroy = getattr(spider, 'destroy', None)
        if destroy is not None:
            try:
                destroy()
            except Exception:
                traceback.print_exc()


host = Host()

_write_lock = threading.Lock()


def _reply(payload):
    data = (json.dumps(payload, ensure_ascii=False) + '\n').encode('utf-8')
    with _write_lock:
        _out.write(data)
        _out.flush()


def _handle(request):
    try:
        op = request.get('op')
        if op == 'call':
            result = host.call(request['key'], request['path'],
                               request.get('ext', ''), request['method'],
                               request.get('args', '[]'))
        elif op == 'proxy':
            result = host.proxy(request.get('params', '{}'))
        elif op == 'sites':
            result = host.sites(request['path'])
        elif op == 'port':
            host.port = int(request['port'])
            local_proxy.Proxy.set_port(host.port)
            result = ''
        elif op == 'release':
            host.release(request['key'])
            result = ''
        elif op == 'ping':
            result = sys.version.split()[0]
        else:
            raise ValueError('unknown op %s' % op)
        _reply({'id': request.get('id'), 'ok': True, 'result': result})
    except BaseException as error:  # noqa: B902 源里什么异常都可能抛
        _reply({'id': request.get('id'), 'ok': False,
                'error': '%s: %s' % (type(error).__name__, error)})


def main():
    for line in sys.stdin.buffer:
        line = line.strip()
        if not line:
            continue
        try:
            request = json.loads(line.decode('utf-8'))
        except Exception:
            continue
        threading.Thread(target=_handle, args=(request,), daemon=True).start()


if __name__ == '__main__':
    main()
