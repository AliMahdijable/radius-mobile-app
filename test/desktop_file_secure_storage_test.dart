import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/services/desktop_file_secure_storage.dart';

/// خزنة الحاسبة (بلاغ ويندوز ٢٣ أكتوبر: كتابتان متزامنتان في ملفّ الإضافة ⇒ ضاع التوكن ⇒ 401 ⇒ طرد).
void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('desk_store_'));
  tearDown(() => dir.deleteSync(recursive: true));

  DesktopFileSecureStorage store({Future<Map<String, String>> Function(Directory)? legacy}) =>
      DesktopFileSecureStorage(
        fileName: 'secure_store.dat',
        // «تشفير» قابلٌ للعكس يثبت أنّ الملفّ يمرّ بالترميز لا نصّاً صريحاً.
        encode: (b) => b.map((x) => x ^ 0x5a).toList(),
        decode: (b) => b.map((x) => x ^ 0x5a).toList(),
        legacyImport: legacy,
        directory: () async => dir,
      );

  test('كتابات الدخول المتزامنة كلّها تبقى — وتُقرأ بعد إعادة التشغيل', () async {
    final a = store();
    await Future.wait([
      for (var i = 0; i < 25; i++) a.write(key: 'k$i', value: 'v$i', options: const {}),
    ]);
    final b = store(); // تشغيلٌ جديد يقرأ الملفّ
    final all = await b.readAll(options: const {});
    expect(all.length, 25);
    expect(all['k7'], 'v7');
    // مرمَّز لا نصّاً صريحاً.
    final raw = File('${dir.path}/secure_store.dat').readAsStringSync();
    expect(raw.contains('k7'), isFalse);
  });

  test('الحذف ومسح الكلّ يُحفظان', () async {
    final a = store();
    await a.write(key: 'auth.token', value: 't', options: const {});
    await a.write(key: 'x', value: 'y', options: const {});
    await a.delete(key: 'x', options: const {});
    expect(await store().readAll(options: const {}), {'auth.token': 't'});
    await a.deleteAll(options: const {});
    expect(await store().readAll(options: const {}), isEmpty);
  });

  test('ما في الخزنة القديمة يُنقل مرّةً حين لا ملفّ بعد', () async {
    var calls = 0;
    Future<Map<String, String>> legacy(Directory _) async {
      calls++;
      return {'account.refresh': 'r1'};
    }

    final a = store(legacy: legacy);
    expect(await a.read(key: 'account.refresh', options: const {}), 'r1');
    await a.write(key: 'auth.token', value: 't', options: const {});
    final b = store(legacy: legacy);
    expect(await b.readAll(options: const {}), {'account.refresh': 'r1', 'auth.token': 't'});
    expect(calls, 1, reason: 'الملفّ الجديد موجودٌ ⇒ لا يُقرأ القديم ثانيةً');
  });

  test('ملفٌّ تالف لا يُسقط التطبيق — يبدأ فارغاً', () async {
    File('${dir.path}/secure_store.dat').writeAsStringSync('ليس JSON');
    expect(await store().readAll(options: const {}), isEmpty);
  });
}
