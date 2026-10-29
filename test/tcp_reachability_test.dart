import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/core/net/tcp_reachability.dart';

/// بنگ جهاز المشترك (③) والانتقال للاعتماد التالي (⑦) يسألان «واصل؟» — عنوانٌ مخصّص بمنفذ (جهازٌ خلف تحويل منفذ)
/// يُسأل عن منفذه نفسه، لا 80/443/8080 على اسمٍ فيه نقطتان (كان «غير واصل» دائماً).
void main() {
  test('تفكيك العنوان', () {
    expect(TcpReachability.split('10.0.0.5:8080'), (host: '10.0.0.5', port: 8080));
    expect(TcpReachability.split(' 10.0.0.5 '), (host: '10.0.0.5', port: null));
    expect(TcpReachability.split('fe80::1').port, isNull, reason: 'IPv6 بلا أقواس ليس منفذاً');
  });

  test('عنوانٌ بمنفذ ⇒ ذلك المنفذ وحده', () async {
    final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    s.listen((c) => c.destroy());
    final port = s.port;
    expect(await TcpReachability.isReachable('127.0.0.1:$port'), isTrue);
    await s.close();
    expect(await TcpReachability.isReachable('127.0.0.1:$port', timeout: const Duration(milliseconds: 300)), isFalse);
  });
}
