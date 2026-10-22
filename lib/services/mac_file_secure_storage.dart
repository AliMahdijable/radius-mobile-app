import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:path_provider/path_provider.dart';

/// نسخة الماك للتجربة: الخزنة الآمنة ملفٌّ في «Application Support» بدل
/// سلسلة مفاتيح الماك. ~/Library خاصٌّ بالمستخدم.
///
/// لماذا: النسخة موقَّعةٌ محلّيّاً (بلا فريق آبل)، فسلسلة «Data Protection» ترفضها (-34018)، والقديمة
/// تسأل كلمة سرّ الماك مع كلّ بناءٍ جديد (توقيعٌ جديد) — فتعلّق خطوات الدخول ثمّ «تعذّر حفظ الدخول».
/// على ويندوز الخزنة ملفٌّ مشفّرٌ بـDPAPI أصلاً؛ أندرويد/آيفون لا يمرّان من هنا.
class MacFileSecureStorage extends FlutterSecureStoragePlatform {
  MacFileSecureStorage({Future<Directory> Function()? directory})
      : _directory = directory ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _directory;
  Map<String, String>? _values;
  Future<void>? _loading;
  Future<void> _writes = Future<void>.value();
  File? _file;

  static void install() => FlutterSecureStoragePlatform.instance = MacFileSecureStorage();

  Future<Map<String, String>> _map() async {
    if (_values == null) await (_loading ??= _load());
    return _values!;
  }

  Future<void> _load() async {
    final dir = await _directory();
    await dir.create(recursive: true);
    final file = File('${dir.path}/secure_store.json');
    _file = file;
    var values = <String, String>{};
    try {
      if (await file.exists()) {
        final raw = jsonDecode(await file.readAsString());
        if (raw is Map) values = {for (final e in raw.entries) '${e.key}': '${e.value}'};
      }
    } catch (e) {
      if (kDebugMode) debugPrint('🟠 mac secure store unreadable, starting empty: $e');
    }
    _values = values;
  }

  /// كتابةٌ واحدة بعد أخرى (ملفٌّ مؤقّت ثمّ إعادة تسمية) — كتابات الجلسة المتوازية لا تتسابق.
  Future<void> _save() {
    final snapshot = jsonEncode(_values);
    return _writes = _writes.then((_) async {
      final file = _file!;
      final tmp = File('${file.path}.tmp');
      // ~/Library خاصٌّ بالمستخدم (700) — لا يقرؤه مستخدمٌ آخر على الجهاز.
      await tmp.writeAsString(snapshot, flush: true);
      await tmp.rename(file.path);
    }).catchError((Object e) {
      if (kDebugMode) debugPrint('🔴 mac secure store save: $e');
    });
  }

  @override
  Future<void> write({required String key, required String value, required Map<String, String> options}) async {
    (await _map())[key] = value;
    await _save();
  }

  @override
  Future<String?> read({required String key, required Map<String, String> options}) async =>
      (await _map())[key];

  @override
  Future<bool> containsKey({required String key, required Map<String, String> options}) async =>
      (await _map()).containsKey(key);

  @override
  Future<void> delete({required String key, required Map<String, String> options}) async {
    if ((await _map()).remove(key) != null) await _save();
  }

  @override
  Future<Map<String, String>> readAll({required Map<String, String> options}) async =>
      Map<String, String>.of(await _map());

  @override
  Future<void> deleteAll({required Map<String, String> options}) async {
    (await _map()).clear();
    await _save();
  }
}
