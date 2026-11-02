import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../core/util/error_text.dart';
import '../core/util/phone.dart' as phone_util;
import 'api_client.dart';

/// دين مشتركٍ محذوف (٢٣ أكتوبر) — صفٌّ من GET /api/v2/deleted-debts (الخادم
/// server/deletedDebts.js). المالك: «مرات شركه تحذف يوزرات معينه احنه لازم
/// نخلي الديون تبقى للوكيل».
///
/// [origin]: `auto` حذفته الشركة من الساس (رصيده من دفتر الخادم) · `manual`
/// أدخله الوكيل · `import` من ملف الاستيراد. [debt] موجب بالدينار.
class DeletedDebt {
  const DeletedDebt({
    required this.key,
    required this.origin,
    required this.name,
    required this.debt,
    this.username,
    this.phone,
    this.managerUsername,
    this.at,
    this.note,
  });

  /// `m<id>` يدويّ/مستورد · `a<id>` تلقائيّ (دفتر الشركة) · `d<id>` مخزن ديوننا (فحص الدخول — ٢ نوفمبر) — يُمرَّر كما هو لمسارات
  /// التسديد/الشطب.
  final String key;
  final String origin;
  final String name;
  final double debt;
  final String? username;
  final String? phone;
  final String? managerUsername;
  final DateTime? at;
  final String? note;

  bool get isAuto => origin == 'auto';

  /// 9647XXXXXXXXX ⇒ 07XXXXXXXXX للعرض والاتّصال.
  String? get localPhone {
    final p = phone;
    if (p == null || p.isEmpty) return null;
    return phone_util.localPhone(p);
  }

  static DeletedDebt? fromJson(Map<String, dynamic> j) {
    final key = (j['key'] ?? '').toString();
    final debt = double.tryParse(j['debt']?.toString() ?? '');
    if (!RegExp(r'^[mad]\d{1,18}$').hasMatch(key) || debt == null || debt <= 0) {
      return null;
    }
    String? s(Object? v) {
      final t = v?.toString().trim() ?? '';
      return t.isEmpty ? null : t;
    }

    final origin = (j['origin'] ?? '').toString();
    return DeletedDebt(
      key: key,
      origin: const {'auto', 'manual', 'import'}.contains(origin) ? origin : 'manual',
      name: s(j['name']) ?? s(j['username']) ?? '#$key',
      debt: debt,
      username: s(j['username']),
      phone: s(j['phone']),
      managerUsername: s(j['manager_username']),
      at: DateTime.tryParse(j['at']?.toString() ?? '')?.toLocal(),
      note: s(j['note']),
    );
  }
}

/// دينٌ مكرّر ينتظر قرار المدير (٢ نوفمبر — `pending_twins`، لصاحب الحساب وحده): صفٌّ يدويّ وتوأمه التلقائيّ مقفلان حتى «نفس الدين»
/// (يُحصَّل مرّةً) أو «دينان مختلفان» (كلٌّ وحده). [partialKeep] ≠ null ⇒ قرار «نفس الدين» حُفظ جزؤه ⇒ «أكمل القرار» وحده.
class PendingTwin {
  const PendingTwin({
    required this.manualKey,
    required this.autoKey,
    required this.name,
    required this.manualDebt,
    this.manualOrig,
    this.autoDebt,
    this.autoStatus,
    this.partialKeep,
  });
  final String manualKey;
  final String autoKey;
  final String name;
  final double manualDebt;
  final double? manualOrig;

  /// دين الطرف التلقائيّ كما عُرض — يُعاد للخادم (seen_auto_debt) فيرفض إن تغيّر بعد العرض.
  final double? autoDebt;

  /// deleted · absent · pending_sas · present.
  final String? autoStatus;
  final String? partialKeep;

  /// مبلغان مختلفان ⇒ يُسأل المدير أيّهما الصحيح.
  bool get differ {
    final o = manualOrig;
    final a = autoDebt;
    return o != null && a != null && a > 0 && (o - a).abs() >= 0.01;
  }

  static PendingTwin? fromJson(Map<String, dynamic> j) {
    final mk = (j['manual_key'] ?? '').toString();
    final ak = (j['auto_key'] ?? '').toString();
    if (!RegExp(r'^m\d{1,18}$').hasMatch(mk) || !RegExp(r'^[ad]\d{1,18}$').hasMatch(ak)) return null;
    final m = j['manual'] is Map ? Map<String, dynamic>.from(j['manual'] as Map) : const <String, dynamic>{};
    final a = j['auto'] is Map ? Map<String, dynamic>.from(j['auto'] as Map) : null;
    final p = j['partial'] is Map ? Map<String, dynamic>.from(j['partial'] as Map) : null;
    double? n(dynamic v) => v == null ? null : double.tryParse(v.toString());
    final name = (m['name'] ?? m['username'] ?? (a == null ? null : a['name']) ?? mk).toString();
    return PendingTwin(
      manualKey: mk,
      autoKey: ak,
      name: name,
      manualDebt: n(m['debt']) ?? 0,
      manualOrig: n(m['orig']),
      autoDebt: a == null ? null : n(a['debt']),
      autoStatus: a?['status']?.toString(),
      partialKeep: p == null ? null : (p['keep'] == 'ledger' ? 'ledger' : 'manual'),
    );
  }
}

/// ردّ القائمة: [enabled] = الميزة مفعّلة لحساب الشركة المفتوحة.
class DeletedDebtsPage {
  const DeletedDebtsPage({
    required this.enabled,
    required this.rows,
    required this.count,
    required this.total,
    this.truncated = false,
    this.pendingTwins = const [],
  });
  final bool enabled;
  final List<DeletedDebt> rows;
  final int count;
  final double total;
  final bool truncated;

  /// ديونٌ مكرّرة تنتظر قرار المدير (لصاحب الحساب — الموظّف لا تصله).
  final List<PendingTwin> pendingTwins;
}

class DeletedDebtsApi {
  DeletedDebtsApi._();

  static const _base = '/api/v2/deleted-debts';

  static Future<({DeletedDebtsPage? page, String? error})> list() async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>(_base);
      final body = r.data ?? const {};
      if (body['success'] != true) {
        return (page: null, error: body['message']?.toString() ?? 'تعذّر الجلب');
      }
      final raw = body['data'];
      final rows = raw is List
          ? raw
              .whereType<Map>()
              .map((m) => DeletedDebt.fromJson(Map<String, dynamic>.from(m)))
              .whereType<DeletedDebt>()
              .toList()
          : const <DeletedDebt>[];
      final totals = body['totals'] is Map ? body['totals'] as Map : const {};
      final tw = body['pending_twins'];
      final twins = tw is List
          ? tw.whereType<Map>().map((m) => PendingTwin.fromJson(Map<String, dynamic>.from(m))).whereType<PendingTwin>().toList()
          : const <PendingTwin>[];
      return (
        page: DeletedDebtsPage(
          enabled: body['enabled'] == true,
          pendingTwins: twins,
          rows: rows,
          count: int.tryParse(totals['count']?.toString() ?? '') ?? rows.length,
          total: double.tryParse(totals['debt']?.toString() ?? '') ??
              rows.fold<double>(0, (s, r) => s + r.debt),
          truncated: body['truncated'] == true,
        ),
        error: null,
      );
    } catch (e) {
      _log('list', e);
      return (page: null, error: humanError(e, fallback: 'تعذّر جلب ديون المحذوفين'));
    }
  }

  /// إضافة يدويّة: الاسم والمبلغ إجباريّان. [code] = `RECENT_DUPLICATE` ⇒ يُسأل
  /// المستخدم ثمّ يُعاد بـ[confirmRepeat]؛ `SUBSCRIBER_EXISTS` ⇒ المشترك ما زال بالساس.
  /// ردود 4xx تصل ردّاً عاديّاً (`validateStatus < 500` في [ApiClient]) فيُقرأ
  /// الرمز والرسالة من جسمه.
  static Future<({bool ok, String? message, String? code})> add({
    required String name,
    required int amount,
    String? phone,
    String? username,
    String? note,
    bool confirmRepeat = false,
  }) async {
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>(_base, data: {
        'name': name,
        'amount': amount,
        if (phone != null && phone.isNotEmpty) 'phone': phone,
        if (username != null && username.isNotEmpty) 'username': username,
        if (note != null && note.isNotEmpty) 'note': note,
        if (confirmRepeat) 'confirmRepeat': true,
      });
      final body = r.data ?? const {};
      final ok = body['success'] == true;
      return (
        ok: ok,
        message: body['message']?.toString() ?? (ok ? null : 'تعذّر الحفظ'),
        code: ok ? null : body['code']?.toString(),
      );
    } on DioException catch (e) {
      _log('add', e);
      final body = e.response?.data;
      return (
        ok: false,
        message: humanError(e, fallback: 'تعذّر الحفظ'),
        code: body is Map ? body['code']?.toString() : null,
      );
    } catch (e) {
      _log('add', e);
      return (ok: false, message: humanError(e, fallback: 'تعذّر الحفظ'), code: null);
    }
  }

  /// تسديد: [payAll] الكلّ، وإلّا [amount] (مضاعف 250 ≤ الدين) — الخادم يحسب من
  /// الرصيد المحفوظ ويحصيه بالتقرير الماليّ محصَّلاً.
  static Future<({bool ok, String? message, double paid, double remaining, String? code})> pay({
    required String key,
    int? amount,
    bool payAll = false,
    String? comment,
    bool confirmRepeat = false,
  }) async {
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>('$_base/$key/pay', data: {
        if (payAll) 'payAll': true else 'amount': amount,
        if (comment != null && comment.isNotEmpty) 'comment': comment,
        // تسديدٌ بالمبلغ نفسه خلال دقيقتين (الخادم ٢ نوفمبر) ⇒ RECENT_DUPLICATE، ويُعاد بعد تأكيد المدير وحده
        if (confirmRepeat) 'confirmRepeat': true,
      });
      final body = r.data ?? const {};
      final d = body['data'] is Map ? body['data'] as Map : const {};
      final ok = body['success'] == true;
      return (
        ok: ok,
        message: body['message']?.toString() ?? (ok ? null : 'تعذّر التسديد'),
        paid: double.tryParse(d['amount_paid']?.toString() ?? '') ?? 0,
        remaining: double.tryParse(d['remaining_debt']?.toString() ?? '') ?? 0,
        code: ok ? null : body['code']?.toString(),
      );
    } catch (e) {
      _log('pay', e);
      return (ok: false, message: humanError(e, fallback: 'تعذّر التسديد'), paid: 0.0, remaining: 0.0, code: null);
    }
  }

  /// شطب: يُسقط الدين بلا تحصيل ([reason] إجباريّ) — لا يُحسب نقداً.
  static Future<({bool ok, String? message})> writeOff({
    required String key,
    required String reason,
  }) async {
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>(
        '$_base/$key/write-off',
        data: {'reason': reason},
      );
      final body = r.data ?? const {};
      final ok = body['success'] == true;
      return (
        ok: ok,
        message: body['message']?.toString() ?? (ok ? null : 'تعذّر الشطب'),
      );
    } catch (e) {
      _log('write-off', e);
      return (ok: false, message: humanError(e, fallback: 'تعذّر الشطب'));
    }
  }

  /// قرار الدين المكرّر (لصاحب الحساب): [same] «نفس الدين» — [keep] 'manual' (يُحصَّل اليدويّ وتُصفَّر نسخة الدفتر) أو 'ledger' (يُشطب
  /// اليدويّ ويُحصَّل الدفتر)؛ وإلّا «دينان مختلفان». [seenAutoDebt] دين الدفتر كما عُرض — تغيّر ⇒ 409 TWIN_AUTO_CHANGED بلا حركة.
  static Future<({bool ok, String? message, String? code, Map<String, dynamic> data})> decideTwin({
    required String manualKey,
    required bool same,
    String? keep,
    double? seenAutoDebt,
  }) async {
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>('$_base/$manualKey/twin', data: {
        'same': same,
        if (same && keep != null) 'keep': keep,
        if (same && seenAutoDebt != null && seenAutoDebt >= 0) 'seen_auto_debt': seenAutoDebt,
      });
      final body = r.data ?? const {};
      final ok = body['success'] == true;
      final d = body['data'] is Map ? Map<String, dynamic>.from(body['data'] as Map) : const <String, dynamic>{};
      return (ok: ok, message: body['message']?.toString(), code: ok ? null : body['code']?.toString(), data: d);
    } on DioException catch (e) {
      _log('twin', e);
      final b = e.response?.data;
      return (
        ok: false,
        message: b is Map && b['message'] != null ? b['message'].toString() : humanError(e, fallback: 'تعذّر حفظ القرار — أعد المحاولة'),
        code: b is Map ? b['code']?.toString() : null,
        data: const <String, dynamic>{},
      );
    } catch (e) {
      _log('twin', e);
      return (ok: false, message: humanError(e, fallback: 'تعذّر حفظ القرار — أعد المحاولة'), code: null, data: const <String, dynamic>{});
    }
  }

  static void _log(String what, Object e) {
    if (kDebugMode) debugPrint('🔴 deleted-debts/$what: $e');
  }
}
