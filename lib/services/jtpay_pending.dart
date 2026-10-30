import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// رابط رجوعٍ التُقط ولم يتأكّد الخادم من استلامه — «شحن من pay الجزيرة».
///
/// يُحفظ **قبل** تسليمه (قتل التطبيق أو انقطاع النت بعد الدفع لا يُضيعه) ويُمحى حين يقول الخادم
/// `received`. يُعاد تسليمه عند فتح الشاشة؛ والخادم لا يسلّم الرابط نفسه للموقع مرّتين (بصمته فريدة).
/// مربوطٌ بحساب صاحبه: لا يُسلَّم بجلسة مديرٍ آخر.
@immutable
class JtpayPending {
  const JtpayPending({required this.opId, required this.adminId, required this.returnUrl, required this.at, this.amount});

  final String opId;
  final String adminId;
  final String returnUrl;
  final DateTime at;
  final int? amount;

  Map<String, dynamic> toJson() => {
        'op': opId,
        'admin': adminId,
        'ret': returnUrl,
        'at': at.toUtc().toIso8601String(),
        if (amount != null) 'amount': amount,
      };

  static JtpayPending? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final op = raw['op']?.toString() ?? '';
    final admin = raw['admin']?.toString() ?? '';
    final ret = raw['ret']?.toString() ?? '';
    final at = DateTime.tryParse(raw['at']?.toString() ?? '');
    if (op.isEmpty || admin.isEmpty || ret.isEmpty || at == null) return null;
    final a = raw['amount'];
    return JtpayPending(
      opId: op,
      adminId: admin,
      returnUrl: ret,
      at: at,
      amount: a is num ? a.round() : int.tryParse('$a'),
    );
  }
}

class JtpayPendingStore {
  JtpayPendingStore._();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(resetOnError: false),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );
  static const _key = 'jtpay.pending.v1';

  /// رابطٌ أقدم من هذا لا يُعاد (الخادم يحتفظ بنسخته المشفّرة ٧ أيّام، و«تحقّق» يكفي بعدها).
  static const maxAge = Duration(days: 7);
  static const maxEntries = 20;

  /// للاختبار وحده: تخزينٌ في الذاكرة بدل الخزنة.
  @visibleForTesting
  static Map<String, String>? debugMemory;

  static Future<void>? _lock;

  static Future<T> _serial<T>(Future<T> Function() op) async {
    while (_lock != null) {
      await _lock;
    }
    final done = Completer<void>();
    _lock = done.future;
    try {
      return await op();
    } finally {
      _lock = null;
      done.complete();
    }
  }

  static Future<String?> _read() async {
    final mem = debugMemory;
    if (mem != null) return mem[_key];
    try {
      return await _storage.read(key: _key);
    } catch (_) {
      return null;
    }
  }

  static Future<void> _write(String? v) async {
    final mem = debugMemory;
    if (mem != null) {
      if (v == null) {
        mem.remove(_key);
      } else {
        mem[_key] = v;
      }
      return;
    }
    try {
      if (v == null) {
        await _storage.delete(key: _key);
      } else {
        await _storage.write(key: _key, value: v);
      }
    } catch (_) {/* أفضل جهد — الخادم يحفظ نسخته أيضاً */}
  }

  static Future<List<JtpayPending>> _all() async {
    final raw = await _read();
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return [];
      final cutoff = DateTime.now().subtract(maxAge);
      return [
        for (final e in list)
          if (JtpayPending.fromJson(e) case final p? when p.at.isAfter(cutoff)) p,
      ];
    } catch (_) {
      return [];
    }
  }

  static Future<void> _save(List<JtpayPending> list) =>
      _write(list.isEmpty ? null : jsonEncode([for (final p in list.take(maxEntries)) p.toJson()]));

  /// يحفظ الرابط الملتقَط (يحلّ محلّ ما للعمليّة نفسها).
  static Future<void> put(JtpayPending p) => _serial(() async {
        final list = (await _all()).where((x) => x.opId != p.opId).toList();
        await _save([p, ...list]);
      });

  static Future<void> remove(String opId) => _serial(() async {
        final list = await _all();
        final next = list.where((x) => x.opId != opId).toList();
        if (next.length != list.length) await _save(next);
      });

  /// ما لم يُستلم لهذا الحساب وحده.
  static Future<List<JtpayPending>> forAdmin(String? adminId) async {
    if (adminId == null || adminId.isEmpty) return const [];
    return (await _all()).where((p) => p.adminId == adminId).toList();
  }
}
