# -*- coding: utf-8 -*-
"""本机代理的地址，端口由宿主在启动时写入。

Python 源里 `self.getProxyUrl()` 返回的就是这个地址；应用侧的 HTTP 服务在
`/proxy` 上把它转回 `localProxy()`。
"""


class Proxy(object):
    port = 0

    @classmethod
    def set_port(cls, port):
        cls.port = int(port)

    @classmethod
    def get_port(cls):
        return cls.port

    @classmethod
    def get_url(cls, local=True):
        return 'http://127.0.0.1:%d/proxy' % cls.port

    # 流传的源按原版写法叫 getPort/getUrl，别名保留。
    @classmethod
    def getPort(cls):
        return cls.get_port()

    @classmethod
    def getUrl(cls, local=True):
        return cls.get_url(local)
