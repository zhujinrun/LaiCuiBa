import 'dart:convert';
import 'dart:io';

/// 一个 DLNA MediaRenderer。发现过程只拿 description XML，不碰设备上的其他服务。
class DlnaDevice {
  const DlnaDevice({
    required this.name,
    required this.location,
    required this.controlUrl,
  });

  final String name;
  final String location;
  final String controlUrl;
}

class DlnaException implements Exception {
  const DlnaException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 最小可用的 DLNA 投屏：SSDP 发现 MediaRenderer + AVTransport 播放。
/// 支持 HTTP(S) 代理不是这一层的职责，和设备直连同网段。
class Dlna {
  Dlna._();

  static const _searchTarget = 'urn:schemas-upnp-org:device:MediaRenderer:1';

  /// SSDP M-SEARCH。没有设备时返回空表，界面照原版说「没有找到设备」。
  static Future<List<DlnaDevice>> discover({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        0,
        reuseAddress: true,
      );
      socket.broadcastEnabled = true;
      final locations = <String>{};
      socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final datagram = socket?.receive();
        if (datagram == null) return;
        final text = utf8.decode(datagram.data, allowMalformed: true);
        final match = RegExp(r'^LOCATION:/s*(.+)$', multiLine: true, caseSensitive: false)
            .firstMatch(text);
        if (match != null) locations.add(match.group(1)!.trim());
      });

      final request = utf8.encode(
        'M-SEARCH * HTTP/1.1\r\n'
        'HOST: 239.255.255.250:1900\r\n'
        'MAN: "ssdp:discover"\r\n'
        'MX: 2\r\n'
        'ST: $_searchTarget\r\n'
        '\r\n',
      );
      socket.send(request, InternetAddress('239.255.255.250'), 1900);
      await Future<void>.delayed(timeout);

      final devices = <DlnaDevice>[];
      for (final location in locations) {
        try {
          devices.add(await describe(location));
        } on Object {
          // 一台设备答了半截 XML 不该让整次发现失败。
        }
      }
      return devices;
    } on Object catch (error) {
      throw DlnaException('投屏发现失败：$error');
    } finally {
      socket?.close();
    }
  }

  /// 解析设备的 description XML。抽成纯函数，测试不必发 UDP。
  static DlnaDevice? parseDescription(String location, String xml) {
    final nameMatch = RegExp(
      r'<friendlyName>\s*(.*?)\s*</friendlyName>',
      dotAll: true,
      caseSensitive: false,
    ).firstMatch(xml);
    final serviceMatch = RegExp(
      r'<service>.*?<serviceType>\s*urn:schemas-upnp-org:service:AVTransport:1\s*</serviceType>.*?<controlURL>\s*(.*?)\s*</controlURL>.*?</service>',
      dotAll: true,
      caseSensitive: false,
    ).firstMatch(xml);
    if (nameMatch == null || serviceMatch == null) return null;
    final base = Uri.tryParse(location);
    if (base == null) return null;
    final control = base.resolve(serviceMatch.group(1)!).toString();
    return DlnaDevice(
      name: nameMatch.group(1)!,
      location: location,
      controlUrl: control,
    );
  }

  static Future<DlnaDevice> describe(String location) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.getUrl(Uri.parse(location));
      final response = await request.close().timeout(const Duration(seconds: 10));
      final xml = await response.transform(utf8.decoder).join();
      final device = parseDescription(location, xml);
      if (device == null) throw const DlnaException('设备没有 AVTransport 服务');
      return device;
    } on DlnaException {
      rethrow;
    } on Object catch (error) {
      throw DlnaException('读取设备信息失败：$error');
    } finally {
      client.close();
    }
  }

  static Future<void> play(
    DlnaDevice device,
    String url, {
    String title = '',
  }) async {
    await _soap(
      device,
      'SetAVTransportURI',
      '<InstanceID>0</InstanceID>'
      '<CurrentURI>${_escape(url)}</CurrentURI>'
      '<CurrentURIMetaData>${_escape(
        '<DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/">'
        '<item id="0" parentID="-1" restricted="0">'
        '<dc:title xmlns:dc="http://purl.org/dc/elements/1.1/">'
        '${_escape(title)}</dc:title>'
        '<res protocolInfo="http-get:*:video/*:*">${_escape(url)}</res>'
        '</item></DIDL-Lite>',
      )}</CurrentURIMetaData>',
    );
    await _soap(
      device,
      'Play',
      '<InstanceID>0</InstanceID><Speed>1</Speed>',
    );
  }

  static Future<void> stop(DlnaDevice device) =>
      _soap(device, 'Stop', '<InstanceID>0</InstanceID>');

  static Future<void> _soap(
    DlnaDevice device,
    String action,
    String args,
  ) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 8);
    final uri = Uri.parse(device.controlUrl);
    final body = utf8.encode(
      '<?xml version="1.0" encoding="utf-8"?>'
      '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" '
      's:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">'
      '<s:Body>'
      '<u:$action xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">'
      '$args'
      '</u:$action>'
      '</s:Body></s:Envelope>',
    );
    try {
      final request = await client.postUrl(uri);
      request.headers
        ..set('content-type', 'text/xml; charset="utf-8"')
        ..set('SOAPACTION', '"urn:schemas-upnp-org:service:AVTransport:1#$action"')
        ..set('content-length', body.length);
      request.add(body);
      final response = await request.close().timeout(const Duration(seconds: 12));
      final text = await response.transform(utf8.decoder).join();
      if (response.statusCode >= 400 || text.contains('<s:Fault>')) {
        throw DlnaException('投屏失败：$action 被设备拒绝（HTTP ${response.statusCode}）');
      }
    } on DlnaException {
      rethrow;
    } on Object catch (error) {
      throw DlnaException('投屏失败：$error');
    } finally {
      client.close();
    }
  }

  static String _escape(String raw) => raw
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}
