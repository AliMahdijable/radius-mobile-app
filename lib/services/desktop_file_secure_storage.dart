import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:path_provider/path_provider.dart';

import '../core/platform/windows_dpapi.dart';

/// الخزنة الآمنة على الحاسبة: ملفٌّ واحد في مجلّد التطبيق للمستخدم (Application Support على الماك،
/// %APPDATA% على ويندوز)، والقيم كلّها في الذاكرة بعد أوّل قراءة.
///
/// لماذا لا إضافة flutter_secure_storage:
/// • الماك (نسخة التجربة): موقَّعةٌ محلّيّاً بلا فريق آبل، فسلسلة المفاتيح ترفضها (-34018) أو تسأل كلمة
///   سرّ الماك مع كلّ بناء — فتعلّق خطوات الدخول.
/// • ويندوز: الإضافة تحذف ملفّها وتعيد كتابته مع كلّ حفظ، فكتابتان متزامنتان (التوكن واليوزر عند الدخول)
///   تصطدمان: «Cannot delete file … flutter_secure_storage.dat — being used by another process» (تقرير
///   التطبيق ٢٣ أكتوبر) — يضيع التوكن فيرفض الخادم كلّ طلبٍ 401 ويطرد المدير بـ«انتهت الجلسة».
///
/// هنا: الكتابات واحدةٌ بعد أخرى (طابور)، كلّ كتابةٍ ملفٌّ مؤقّت ثمّ إعادة تسمية (لا ملفٌّ نصفُ مكتوب)،
/// وإعادة المحاولة إن أمسك الملفَّ برنامجٌ آخر لحظةً (مضادّ الفيروسات). على ويندوز المحتوى مشفّرٌ
/// بتشفير المستخدم (DPAPI) كما كان، وما في ملفّ الإضافة القديم يُنقل مرّةً فلا يضيع دخول الحساب.
class DesktopFileSecureStorage extends FlutterSecureStoragePlatform {
  DesktopFileSecureStorage({
    required this.fileName,
    this.encode,
    this.decode,
    this.legacyImport,
    Future<Directory> Function()? directory,
  }) : _directory = directory ?? getApplicationSupportDirectory;

  final String fileName;

  /// تشفير الملفّ (ويندوز) — null = نصّ JSON كما هو (الماك: ~/Library خاصٌّ بالمستخدم).
  final List<int> Function(List<int> plain)? encode;
  final List<int> Function(List<int> stored)? decode;

  /// قيمٌ من خزنةٍ سابقة تُقرأ حين لا ملفّ بعد (ملفّ إضافة ويندوز القديم).
  final Future<Map<String, String>> Function(Directory dir)? legacyImport;

  final Future<Directory> Function() _directory;
  Map<String, String>? _values;
  Future<void>? _loading;
  Future<void> _writes = Future<void>.value();
  File? _file;

  static void installForMac() => FlutterSecureStoragePlatform.instance =
      DesktopFileSecureStorage(fileName: 'secure_store.json');

  static void installForWindows() => FlutterSecureStoragePlatform.instance = DesktopFileSecureStorage(
        fileName: 'secure_store.dat',
        encode: WindowsDpapi.protect,
        decode: WindowsDpapi.unprotect,
        legacyImport: _importWindowsPluginFile,
      );

  /// ملفّ flutter_secure_storage_windows: خريطة JSON مشفّرة بـDPAPI. أفضل جهد — ملفٌّ تالف أو بصيغةٍ
  /// أخرى يُترك ويبدأ الدخول من جديد.
  static Future<Map<String, String>> _importWindowsPluginFile(Directory dir) async {
    final old = File('${dir.path}${Platform.pathSeparator}flutter_secure_storage.dat');
    if (!await old.exists()) return const {};
    final raw = jsonDecode(utf8.decode(WindowsDpapi.unprotect(await old.readAsBytes())));
    if (raw is! Map) return const {};
    return {for (final e in raw.entries) '${e.key}': '${e.value}'};
  }

  Future<Map<String, String>> _map() async {
    if (_values == null) await (_loading ??= _load());
    return _values!;
  }

  Future<void> _load() async {
    final dir = await _directory();
    await dir.create(recursive: true);
    final file = File('${dir.path}${Platform.pathSeparator}$fileName');
    _file = file;
    var values = <String, String>{};
    try {
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        final raw = jsonDecode(utf8.decode(decode == null ? bytes : decode!(bytes)));
        if (raw is Map) values = {for (final e in raw.entries) '${e.key}': '${e.value}'};
      } else if (legacyImport != null) {
        values = Map<String, String>.of(await legacyImport!(dir));
        _values = values;
        if (values.isNotEmpty) unawaited(_save());
      }
    } catch (e) {
      if (kDebugMode) debugPrint('🟠 desktop secure store unreadable, starting empty: $e');
    }
    _values = values;
  }

  /// كتابةٌ واحدة بعد أخرى (ملفٌّ مؤقّت ثمّ إعادة تسمية) — كتابات الجلسة المتوازية لا تتسابق.
  Future<void> _save() {
    final snapshot = utf8.encode(jsonEncode(_values));
    return _writes = _writes.then((_) async {
      final file = _file!;
      final tmp = File('${file.path}.tmp');
      final bytes = encode == null ? snapshot : encode!(snapshot);
      for (var attempt = 1;; attempt++) {
        try {
          await tmp.writeAsBytes(bytes, flush: true);
          await tmp.rename(file.path);
          return;
        } on FileSystemException {
          // برنامجٌ آخر يمسك الملفّ لحظةً (مضادّ فيروسات، فهرسة) — مرّتان بعد مهلةٍ قصيرة.
          if (attempt >= 3) rethrow;
          await Future<void>.delayed(Duration(milliseconds: 120 * attempt));
        }
      }
    }).catchError((Object e) {
      if (kDebugMode) debugPrint('🔴 desktop secure store save: $e');
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
