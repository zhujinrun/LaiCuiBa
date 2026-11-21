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
            init = getattr(spider, 'init', None)
            if init is not None:
                _invoke(init, ext or '')
            self._spiders[key] = spider
            self._recent = key
            return spider

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
