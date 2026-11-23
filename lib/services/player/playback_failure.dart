/// 把 mpv（或系统）报出来的原始失败信息，翻成一句能让人动手的话。
///
/// 播放页以前只把异常 `debugPrint` 掉，于是打不开的时候画面就是一片黑，和「加
/// 载中」长得一模一样。原版在这件事上的处理是「打不开时换其他内核重试」——我们
/// 只有 mpv 一个内核，能诚实做到的是：说清是哪一类失败，并给一个重试。
///
/// 分类只按**能不能据此动手**来分，不追求把 mpv 的错误表枚举全：渲染建不起来、
/// 地址失效、源鉴权、服务器 5xx，这四类各有一句不同的话，剩下的原样回报。
String playbackFailureHint(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return '播放器没有给出原因';

  final lower = text.toLowerCase();

  // 建不出渲染上下文：远程桌面、没有可用的 GPU 驱动、D3D/EGL 起不来都属于
  // 这一类，换地址没用，所以要说清是「这台机器」的问题。
  const render = [
    'could not create',
    'failed to create',
    'vo/gpu',
    'vo=gpu',
    'opengl',
    'd3d',
    'egl',
    'vulkan',
    'no video output',
    '无法创建',
    'rendering',
  ];
  if (render.any(lower.contains)) {
    return '无法创建播放画面：这台机器（或远程桌面）不支持当前的渲染方式';
  }

  const auth = [
    '403',
    '401',
    'forbidden',
    'unauthorized',
    'need login',
    '鉴权',
  ];
  if (auth.any(lower.contains)) {
    return '源拒绝了这个地址：可能需要登录，或者不让外链播放';
  }

  // 网络层就没通（实测原话：`tcp: Connection to tcp://127.0.0.1:1 failed:
  // Error number -138 occurred`）。这一句要排在下面前缀判断之前，否则「连不上」
  // 会被当成「地址打不开」，把网络问题说成源的问题。
  const network = [
    'tcp:',
    'connection to',
    'connection refused',
    'could not resolve',
    'error number -',
    'unreachable',
    'timed out',
    'timeout',
  ];
  if (network.any(lower.contains)) {
    return '连不上这个地址：网络不通，或者源服务器不可达';
  }

  // 本地文件打不开（实测原话：`Cannot open file '...': Invalid argument`）。
  if (lower.contains('cannot open file')) {
    return '打不开这个文件：路径不对，或者文件已经不在那个位置';
  }

  const gone = [
    '404',
    'not found',
    'failed to open',
    'no such file',
  ];
  if (gone.any(lower.contains)) {
    return '这一集的地址打不开：源可能已经换了地址或者下架了';
  }

  final server = RegExp(r'\b5\d\d\b').firstMatch(text);
  if (server != null) {
    return '源服务器出错了（HTTP ${server.group(0)}），过一会儿再试';
  }

  return text;
}
