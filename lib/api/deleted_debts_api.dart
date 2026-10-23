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

  /// `m<id>` يدويّ/مستورد · `a<id>` تلقائيّ — يُمرَّر كما هو لمسارات التسديد/الشطب.
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
    if (!RegExp(r'^[ma]\d{1,18}$').hasMatch(key) || debt == null || debt <= 0) {
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

/// ردّ القائمة: [enabled] = الميزة مفعّلة لحساب الشركة المفتوحة.
class DeletedDebtsPage {
  const DeletedDebtsPage({
    required this.enabled,
    required this.rows,
    required this.count,
    required this.total,
    this.truncated = false,
  });
  final bool enabled;
  final List<DeletedDebt> rows;
  final int count;
  final double total;
  final bool truncated;
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
      return (
        page: DeletedDebtsPage(
          enabled: body['enabled'] == true,
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
  static Future<({bool ok, String? message, double paid, double remaining})> pay({
    required String key,
    int? amount,
    bool payAll = false,
    String? comment,
  }) async {
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>('$_base/$key/pay', data: {
        if (payAll) 'payAll': true else 'amount': amount,
        if (comment != null && comment.isNotEmpty) 'comment': comment,
      });
      final body = r.data ?? const {};
      final d = body['data'] is Map ? body['data'] as Map : const {};
      final ok = body['success'] == true;
      return (
        ok: ok,
        message: body['message']?.toString() ?? (ok ? null : 'تعذّر التسديد'),
        paid: double.tryParse(d['amount_paid']?.toString() ?? '') ?? 0,
        remaining: double.tryParse(d['remaining_debt']?.toString() ?? '') ?? 0,
      );
    } catch (e) {
      _log('pay', e);
      return (ok: false, message: humanError(e, fallback: 'تعذّر التسديد'), paid: 0.0, remaining: 0.0);
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

  static void _log(String what, Object e) {
    if (kDebugMode) debugPrint('🔴 deleted-debts/$what: $e');
  }
}
