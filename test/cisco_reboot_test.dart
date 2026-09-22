import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/cisco_api.dart';

/// اختبارات `reload` على خادم Telnet وهميّ.
///
/// لا تلمس جهازاً حقيقيّاً: إعادة تشغيل سويتشٍ يخدم مشتركين ثمنُها
/// دقيقتان من انقطاع، ولا تُختبَر بالتجريب.
void main() {
  /// خادمٌ يحاكي IOS: دخول، ثمّ حوار `reload` بحسب [scenario].
  Future<({ServerSocket server, List<String> sent, List<Socket> peers})>
      fakeSwitch(String scenario) async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final sent = <String>[];
    final peers = <Socket>[];
    server.listen((socket) {
      peers.add(socket);
      var phase = 0;
      var line = '';
      var iacRemaining = 0;
      final prompt = scenario == 'user-exec' ? 'switch>' : 'switch#';
      socket.write('\r\nUsername: ');

      socket.listen((bytes) {
        for (final b in bytes) {
          if (iacRemaining > 0) {
            iacRemaining--;
            continue;
          }
          if (b == 255) {
            iacRemaining = 2;
            continue;
          }
          // CR يُتجاهَل و LF وحده يُنهي السطر: عدُّ الاثنين يجعل «\r\n»
          // سطرين، الثاني فارغ — وهو ما يعنيه تأكيد [confirm] هنا.
          if (b == 13) continue;
          if (b == 10) {
            final input = line;
            line = '';
            if (phase == 0) {
              phase++;
              socket.write('Password: ');
              continue;
            }
            if (phase == 1) {
              phase++;
              socket.write('\r\n$prompt');
              continue;
            }
            sent.add(input);
            if (input == 'reload') {
              switch (scenario) {
                case 'refused':
                  socket.write('reload\r\n% Reload not authorized\r\n$prompt');
                case 'no-save-question':
                  socket.write('reload\r\nProceed with reload? [confirm]');
                case 'ignored':
                  socket.write('reload\r\n$prompt'); // عاد المحثّ بلا شيء
                default:
                  socket.write('reload\r\nSystem configuration has been '
                      'modified. Save? [yes/no]: ');
              }
            } else if (input == 'n' || input == 'no') {
              socket.write('\r\nProceed with reload? [confirm]');
            } else if (input == 'yes' || input == 'y') {
              // لو حدث هذا فقد حُفظت الإعدادات — الاختبار يمنعه.
              socket.write('\r\nBuilding configuration...\r\n[OK]\r\n$prompt');
            } else if (input.isEmpty) {
              // تأكيد [confirm] → الجهاز يقطع كلّ شيء
              socket.destroy();
            } else {
              socket.write('$input\r\n$prompt'); // terminal length 0 وغيرها
            }
          } else if (b >= 32 && b < 127) {
            line += ascii.decode([b]);
          }
        }
      }, onError: (_) {}, cancelOnError: false);
    });
    return (server: server, sent: sent, peers: peers);
  }

  Future<void> reboot(int port, {Duration? timeout}) => CiscoApi.rebootDevice(
        host: InternetAddress.loopbackIPv4.address,
        user: 'admin',
        pass: 'irrelevant',
        port: port,
        protocol: 'telnet',
        timeout: timeout ?? const Duration(seconds: 6),
      );

  test('سؤال الحفظ يُجاب بـ«لا» ثمّ التأكيد ثمّ ينقطع = نجاح', () async {
    final f = await fakeSwitch('save-question');
    addTearDown(() {
      for (final s in f.peers) {
        s.destroy();
      }
      return f.server.close();
    });

    await reboot(f.server.port); // لا يرمي

    expect(f.sent, contains('reload'));
    // الحفظ يُثبّت تغييراً لم يطلبه أحد — قد يكون عابراً وُضع ليزول.
    expect(f.sent, contains('n'));
    expect(f.sent, isNot(contains('yes')));
    expect(f.sent, isNot(contains('y')));
    // لا أمر كتابةٍ إطلاقاً
    expect(f.sent.where((c) => c.startsWith('write') || c.contains('copy run')),
        isEmpty);
  });

  test('جهازٌ بلا تعديلات: يذهب إلى [confirm] مباشرةً', () async {
    final f = await fakeSwitch('no-save-question');
    addTearDown(() {
      for (final s in f.peers) {
        s.destroy();
      }
      return f.server.close();
    });

    await reboot(f.server.port);

    expect(f.sent, contains('reload'));
    expect(f.sent, isNot(contains('n'))); // لم يُسأل فلم يُجب
  });

  test('رفض الجهاز الأمر يرمي خطأً مفهوماً لا يُبتلَع', () async {
    final f = await fakeSwitch('refused');
    addTearDown(() {
      for (final s in f.peers) {
        s.destroy();
      }
      return f.server.close();
    });

    await expectLater(
      reboot(f.server.port),
      throwsA(isA<CiscoException>().having(
          (e) => e.message, 'message', contains('Reload not authorized'))),
    );
  });

  test('عودة المحثّ بلا إعادة تشغيل ليست نجاحاً', () async {
    final f = await fakeSwitch('ignored');
    addTearDown(() {
      for (final s in f.peers) {
        s.destroy();
      }
      return f.server.close();
    });

    await expectLater(
      reboot(f.server.port),
      throwsA(isA<CiscoException>()
          .having((e) => e.message, 'message', contains('لم يُنفَّذ'))),
    );
  });

  test('مستوى user exec يُرفض قبل إرسال reload', () async {
    // المحثّ «>» لا يملك الأمر أصلاً — نمنعه بدل أن نرسله ونحتار.
    final f = await fakeSwitch('user-exec');
    addTearDown(() {
      for (final s in f.peers) {
        s.destroy();
      }
      return f.server.close();
    });

    await expectLater(
      reboot(f.server.port),
      throwsA(isA<CiscoException>()
          .having((e) => e.message, 'message', contains('user exec'))),
    );
    expect(f.sent, isNot(contains('reload')));
  });
}
