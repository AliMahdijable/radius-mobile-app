import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// عمليّة زين كاش بدأت ولم يصل حكم الخادم فيها بعد.
@immutable
class SelfDepositPending {
  const SelfDepositPending({
    required this.psid,
    required this.adminId,
    required this.createdAt,
    this.amount,
    this.methodLabel,
    this.returnUrl,
  });

  final String psid;

  /// صاحب العمليّة — لا يُعاد إرسالها في جلسة مديرٍ آخر على الهاتف نفسه.
  final String adminId;
  final DateTime createdAt;
  final int? amount;
  final String? methodLabel;

  /// رابط الرجوع كما التقطه الـWebView — **فيه توكن زين كاش**، وهو الدليل
  /// الوحيد على الدفع. `null` = لم يرجع بعد (أُغلقت الصفحة أو لم يُدفع).
  final String? returnUrl;

  SelfDepositPending withReturnUrl(String url) => SelfDepositPending(
        psid: psid,
        adminId: adminId,
        createdAt: createdAt,
        amount: amount,
        methodLabel: methodLabel,
        returnUrl: url,
      );

  Map<String, dynamic> toJson() => {
        'psid': psid,
        'admin': adminId,
        'at': createdAt.toUtc().toIso8601String(),
        if (amount != null) 'amount': amount,
        if (methodLabel != null) 'label': methodLabel,
        if (returnUrl != null) 'ret': returnUrl,
      };

  static SelfDepositPending? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final psid = raw['psid']?.toString() ?? '';
    final admin = raw['admin']?.toString() ?? '';
    final at = DateTime.tryParse(raw['at']?.toString() ?? '');
    if (psid.isEmpty || admin.isEmpty || at == null) return null;
    final amount = raw['amount'];
    return SelfDepositPending(
      psid: psid,
      adminId: admin,
      createdAt: at,
      amount: amount is num ? amount.round() : int.tryParse('$amount'),
      methodLabel: raw['label']?.toString(),
      returnUrl: raw['ret']?.toString(),
    );
  }
}

/// «لا يضيع توكنٌ أبداً» — عمليّات زين كاش المعلّقة في الخزنة الآمنة.
///
/// زين كاش يرجع إلى الساس بتوكن، والرصيد لا يُضاف إلّا إن سلّمه خادمنا
/// للساس (`paymentgateway/process/zaincash`). فإن انقطع النت لحظة الرجوع،
/// أو أُغلق التطبيق قبل أن يردّ الخادم، ضاع الدليل الوحيد على مالٍ دُفع.
/// لذلك يُكتب الرابط هنا **قبل** إرساله، ولا يُمحى إلّا حين يقول الخادم إنّه
/// استلمه أو حسمه (`settled`)، ويُعاد إرساله ([SelfDepositSync]) عند الإقلاع
/// والعودة للواجهة وفتح الشاشة وبإعادةٍ متباعدة — مهما كان مفتاح الميزة.
///
/// • لكلّ مديرٍ عمليّاته — لا تُرسل في جلسة غيره.
/// • قيدٌ **فيه رابط رجوع** لا يُطرد بالعدد ولا يسقط بيومٍ: يبقى حتى حكم الخادم
///   (وبحدٍّ أقصى [maxAgeCaptured] و[maxCaptured] حمايةً للخزنة). وقيدٌ بلا رجوع
///   (فُتحت الصفحة ولم يُدفع) مذكّرةٌ لا دليل: [maxAge] و[maxEntries].
/// • خارج مسح الجلسة عمداً: خروج المدير وسط الدفع لا يمحو ماله.
class SelfDepositPendingStore {
  SelfDepositPendingStore._();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(resetOnError: false),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );
  static const _key = 'selfdeposit.pending.v1';

  /// قيدٌ بلا رابط رجوع (مذكّرة): يوم، وأحدث خمسة.
  static const maxAge = Duration(hours: 24);
  static const maxEntries = 5;

  /// قيدٌ فيه رابط رجوع (الدليل): لا يسقط إلّا بحكم الخادم — أو بعد ٣٠ يوماً
  /// (الخادم يمحو ما يحفظه بعد ٧)، وحتّى ٥٠ قيداً.
  static const maxAgeCaptured = Duration(days: 30);
  static const maxCaptured = 50;

  /// قراءةٌ ثمّ كتابة: عمليّتان متزامنتان (الالتقاط وحكم الخادم) قد تتسابقان
  /// فتمحو إحداهما ما كتبته الأخرى — فتُصفّ واحدةً بعد واحدة.
  ///
  /// قفلٌ يُفرَّغ حين لا عمليّة — لا سلسلةٌ دائمة: سلسلةٌ ثابتة تُبقي آخر
  /// `Future` حيّاً إلى الأبد، والمستقبل يحمل منطقته (zone) فيعلق ما يُعلَّق
  /// عليه في منطقةٍ انتهت (يقع هذا بين الاختبارات).
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

  static Future<List<SelfDepositPending>> _readAll() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null || raw.isEmpty) return [];
      final j = jsonDecode(raw);
      if (j is! List) return [];
      final now = DateTime.now();
      return [
        for (final e in j)
          if (SelfDepositPending.fromJson(e) case final p?)
            if (now.difference(p.createdAt) <
                (p.returnUrl != null ? maxAgeCaptured : maxAge))
              p,
      ];
    } catch (e) {
      if (kDebugMode) debugPrint('SelfDepositPendingStore.read: ${e.runtimeType}');
      return [];
    }
  }

  static Future<void> _writeAll(List<SelfDepositPending> items) async {
    try {
      if (items.isEmpty) {
        await _storage.delete(key: _key);
      } else {
        // الطرد بالعدد للمذكّرات وحدها — رابط رجوعٍ لم يُسلَّم لا يُطرد لأنّ
        // خمس عمليّاتٍ أحدث منه بدأت.
        final captured = [for (final p in items) if (p.returnUrl != null) p];
        final plain = [for (final p in items) if (p.returnUrl == null) p];
        final keepC = captured.length > maxCaptured
            ? captured.sublist(captured.length - maxCaptured).toSet()
            : captured.toSet();
        final keepP = plain.length > maxEntries
            ? plain.sublist(plain.length - maxEntries).toSet()
            : plain.toSet();
        final kept = [
          for (final p in items)
            if (keepC.contains(p) || keepP.contains(p)) p,
        ];
        await _storage.write(
            key: _key, value: jsonEncode([for (final p in kept) p.toJson()]));
      }
    } catch (e) {
      if (kDebugMode) debugPrint('SelfDepositPendingStore.write: ${e.runtimeType}');
    }
  }

  /// عمليّات هذا المدير — الأحدث أخيراً.
  static Future<List<SelfDepositPending>> forAdmin(String? adminId) {
    if (adminId == null || adminId.isEmpty) {
      return Future.value(const <SelfDepositPending>[]);
    }
    return _serial(() async {
      final all = await _readAll();
      return all.where((p) => p.adminId == adminId).toList(growable: false);
    });
  }

  /// يُضيف العمليّة أو يستبدلها (بالمعرّف نفسه).
  static Future<void> put(SelfDepositPending p) => _serial(() async {
        final all = await _readAll();
        all.removeWhere((e) => e.psid == p.psid);
        all.add(p);
        await _writeAll(all);
      });

  /// رابط الرجوع وصل — يُكتب قبل أن يُرسل. وإن غاب القيد (فشلت كتابته عند
  /// بدء الدفع) يُنشأ الآن بمعرّف المدير: الرابط لا يبقى في الذاكرة وحدها.
  static Future<void> attachReturnUrl(
    String psid,
    String url, {
    String? adminId,
    int? amount,
    String? methodLabel,
  }) =>
      _serial(() async {
        final all = await _readAll();
        final i = all.indexWhere((e) => e.psid == psid);
        if (i >= 0) {
          all[i] = all[i].withReturnUrl(url);
        } else if (adminId != null && adminId.isNotEmpty) {
          all.add(SelfDepositPending(
            psid: psid,
            adminId: adminId,
            createdAt: DateTime.now(),
            amount: amount,
            methodLabel: methodLabel,
            returnUrl: url,
          ));
        } else {
          return;
        }
        await _writeAll(all);
      });

  /// حكمٌ نهائيّ من الخادم — تُمحى.
  static Future<void> remove(String psid) => _serial(() async {
        final all = await _readAll();
        final before = all.length;
        all.removeWhere((e) => e.psid == psid);
        if (all.length != before) await _writeAll(all);
      });
}
