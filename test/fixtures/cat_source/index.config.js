'use strict';

// 夹具源的配置。宿主会 require 本文件并把 `default ?? 整个导出` 作为
// start(config) 的参数传进来，所以这里就是源的启动配置。
//
// 用 expectBridge: true 让夹具顺带校验宿主确实注入了可用的
// globalThis.catDartServerPort()（messageToDart 的回传通道）。
module.exports = {
  name: '夹具源',
  expectBridge: true,
};
