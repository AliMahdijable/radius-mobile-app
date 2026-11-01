import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/main.dart' show transientNetworkError;

/// المالك ١ نوفمبر («شنو هاي هواي تجيني منها» — رسائل Crashlytics اليوميّة): انقطاع الشبكة العابر يُسجَّل «غير قاتل»،
/// والأعطال الحقيقيّة تبقى «انهياراً».
class ClientException implements Exception {
  ClientException(this.message);
  final String message;
  @override
  String toString() => 'ClientException with $message';
}

void main() {
  test('انقطاعات الشبكة عابرة', () {
    expect(transientNetworkError(const SocketException('Software caused connection abort')), isTrue);
    expect(transientNetworkError(const HttpException('Unexpected response (unsolicited response without request).')), isTrue);
    expect(transientNetworkError(const HandshakeException('Connection terminated during handshake')), isTrue);
    expect(transientNetworkError(TimeoutException('x')), isTrue);
    expect(transientNetworkError(ClientException('SocketException: Software caused connection abort')), isTrue);
  });
  test('الأعطال الحقيقيّة تبقى قاتلة', () {
    expect(transientNetworkError(StateError('bad state')), isFalse);
    expect(transientNetworkError(const FormatException('x')), isFalse);
    expect(transientNetworkError(ClientException('Bad request')), isFalse);
    expect(transientNetworkError(null), isFalse);
  });
}
