# -*- coding: utf-8 -*-
"""故意写坏的源：用来确认宿主把源里的异常原样带回 Dart 侧。"""

from base.spider import Spider as BaseSpider


class Spider(BaseSpider):

    def homeContent(self, filter):
        raise RuntimeError('夹具源故意失败')
