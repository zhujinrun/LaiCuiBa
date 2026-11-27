import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lai_cui_ba/services/cast/dlna.dart';

const _xml = '''<?xml version="1.0"?>
<root xmlns="urn:schemas-upnp-org:device-1-0">
  <device>
    <friendlyName>客厅电视</friendlyName>
    <serviceList>
      <service>
        <serviceType>urn:schemas-upnp-org:service:AVTransport:1</serviceType>
        <controlURL>/AVTransport/control</controlURL>
      </service>
    </serviceList>
  </device>
</root>''';

void main() {
  test('设备描述解析出名字和绝对 controlURL', () {
    final device = Dlna.parseDescription(
      'http://192.168.1.9:80/desc.xml',
      _xml,
    );
    expect(device, isNotNull);
    expect(device!.name, '客厅电视');
    expect(device.controlUrl, 'http://192.168.1.9/AVTransport/control');
    expect(
      Dlna.parseDescription('http://x/', '<root/>'),
      isNull,
      reason: '没有 AVTransport 的设备不能拿去投屏',
    );
  });

  test('AVTransport 的 SetAVTransportURI 与 Play 真发到设备', () async {
    HttpOverrides.global = null;
    final server = await HttpServer.bind('127.0.0.1', 0);
    final actions = <String>[];
    final bodies = <String>[];
    server.listen((request) {
      actions.add(request.headers.value('SOAPACTION') ?? '');
      request.cast<List<int>>().transform(utf8.decoder).join().then((body) {
        bodies.add(body);
        request.response.write('<s:Envelope><s:Body/></s:Envelope>');
        request.response.close();
      });
    });

    try {
      final device = DlnaDevice(
        name: '测试电视',
        location: 'http://127.0.0.1:${server.port}/desc.xml',
        controlUrl: 'http://127.0.0.1:${server.port}/AVTransport/control',
      );
      await Dlna.play(
        device,
        'https://example.com/a.m3u8?x=1&y=2',
        title: '测试 <片>',
      );
      expect(actions.length, 2);
      expect(actions.first, contains('SetAVTransportURI'));
      expect(actions.last, contains('#Play'));
      expect(bodies.first, contains('&amp;'));
      expect(bodies.first, contains('https://example.com/a.m3u8?x=1&amp;y=2'));

      await Dlna.stop(device);
      expect(actions.last, contains('#Stop'));
    } finally {
      await server.close();
    }
  });
}
