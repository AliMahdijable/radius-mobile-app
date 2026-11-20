import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'api_client.dart';

/// «سجلّ التعديلات» للمشترك (المالك ٢٠ نوفمبر، صورةٌ من نظامٍ آخر: «من يوزر يعدلون عليه معلومات… سويها»):
/// `GET /api/v2/subscribers/:idx/edits?username=` (server/subscriberEdits.js) — كلّ تعديلٍ بما تغيّر «من … إلى …»، ومن عدّله
/// (الموظّف باسمه، والمدير باسمه في السجلات إن وضعه) ومتى. كلمات المرور «تغيّرت» بلا قيمة، والملاحظة الخاصّة بلا نصّها، وإعداد
/// الجهاز لمن يملك صلاحيّة الأجهزة. التعديلات قبل ٢٠ نوفمبر بأسماء حقولها وحدها ([SubscriberEdit.fields]).
class EditEntry {
  const EditEntry({
    required this.f,
    required this.label,
    this.from = '',
    this.to = '',
    this.secret = false,
    this.hidden = false,
    this.text,
    this.atExpiry = false,
  });

  final String f;
  final String label;
  final String from;
  final String to;

  /// كلمة مرور: «تغيّرت» بلا قيمة.
  final bool secret;

  /// إعداد الجهاز لمن لا يملك صلاحيّة الأجهزة.
  final bool hidden;

  /// الملاحظة الخاصّة: «أُضيفت/عُدّلت/حُذفت».
  final String? text;

  /// تغيير الباقة «عند انتهاء الاشتراك».
  final bool atExpiry;

  static EditEntry? fromJson(dynamic v) {
    if (v is! Map) return null;
    final f = (v['f'] ?? '').toString();
    if (f.isEmpty) return null;
    final t = v['text']?.toString();
    return EditEntry(
      f: f,
      label: (v['label'] ?? f).toString(),
      from: (v['from'] ?? '').toString(),
      to: (v['to'] ?? '').toString(),
      secret: v['secret'] == true,
      hidden: v['hidden'] == true,
      text: (t == null || t.isEmpty) ? null : t,
      atExpiry: v['at_expiry'] == true,
    );
  }
}

class SubscriberEdit {
  const SubscriberEdit({
    required this.id,
    required this.atMs,
    required this.kind,
    required this.title,
    required this.byEmployee,
    required this.byName,
    this.diff = const [],
    this.fields = const [],
    this.note,
  });

  final int id;
  final int? atMs;
  final String kind;
  final String title;
  final bool byEmployee;
  final String byName;
  final List<EditEntry> diff;

  /// سطرٌ قديم: أسماء الحقول وحدها.
  final List<String> fields;

  /// نصٌّ بديل حين لا تفاصيل (الاستثناء من الرسائل…).
  final String? note;

  static SubscriberEdit? fromJson(dynamic v) {
    if (v is! Map) return null;
    final id = int.tryParse('${v['id']}');
    if (id == null) return null;
    final by = v['by'] is Map ? v['by'] as Map : const {};
    final at = v['at'];
    final note = v['note']?.toString();
    return SubscriberEdit(
      id: id,
      atMs: at is num ? at.toInt() : int.tryParse('$at'),
      kind: (v['kind'] ?? 'other').toString(),
      title: (v['title'] ?? 'تعديل').toString(),
      byEmployee: by['employee'] == true,
      byName: (by['name'] ?? '').toString().trim().isEmpty
          ? (by['employee'] == true ? 'موظّف' : 'المدير')
          : by['name'].toString().trim(),
      diff: [
        for (final e in (v['diff'] is List ? v['diff'] as List : const []))
          if (EditEntry.fromJson(e) case final x?) x,
      ],
      fields: [for (final f in (v['fields'] is List ? v['fields'] as List : const [])) f.toString()],
      note: (note == null || note.trim().isEmpty) ? null : note,
    );
  }
}

String _msgOf(Object e, String fallback) {
  if (e is DioException) {
    final b = e.response?.data;
    final m = b is Map ? b['message']?.toString() : null;
    if (m != null && m.trim().isNotEmpty) return m;
  }
  return fallback;
}

class SubscriberEditsApi {
  SubscriberEditsApi._();

  static String path(String idx) => '/api/v2/subscribers/${Uri.encodeComponent(idx)}/edits';

  /// تعديلات المشترك الأحدث أوّلاً — ok:false برسالةٍ تقولها الشاشة.
  static Future<({bool ok, List<SubscriberEdit> rows, String? message})> list(String idx, {String? username}) async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>(
        path(idx),
        queryParameters: (username == null || username.isEmpty) ? null : {'username': username},
      );
      final b = r.data ?? const {};
      if (b['success'] != true) return (ok: false, rows: const <SubscriberEdit>[], message: b['message']?.toString());
      final list = b['data'] is List ? b['data'] as List : const [];
      return (
        ok: true,
        rows: [
          for (final x in list)
            if (SubscriberEdit.fromJson(x) case final e?) e,
        ],
        message: null,
      );
    } catch (e) {
      if (!kReleaseMode) debugPrint('🔴 subscriber edits: $e');
      return (ok: false, rows: const <SubscriberEdit>[], message: _msgOf(e, 'تعذّرت قراءة سجلّ التعديلات'));
    }
  }
}

/// «اسمك في السجلات» (المالك ٢٠ نوفمبر: «اسم مستعار للمدير بدل admin@»): `GET/PUT /api/v2/manager-alias`
/// (server/managerAlias.js) — حين ينفّذ صاحب الصفحة بنفسه تظهر العمليّة بهذا الاسم بدل يوزر الساس. لصاحب الصفحة وحده.
class ManagerAliasApi {
  ManagerAliasApi._();

  static const String path = '/api/v2/manager-alias';

  /// أقصى طول (يفرضه الخادم أيضاً).
  static const int maxChars = 40;

  static Future<({bool ok, String? alias, String? message})> get() async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>(path);
      final b = r.data ?? const {};
      if (b['success'] != true) return (ok: false, alias: null, message: b['message']?.toString());
      final a = b['alias']?.toString().trim();
      return (ok: true, alias: (a == null || a.isEmpty) ? null : a, message: null);
    } catch (e) {
      if (!kReleaseMode) debugPrint('🔴 manager alias GET: $e');
      return (ok: false, alias: null, message: _msgOf(e, 'تعذّرت قراءة الاسم'));
    }
  }

  /// حفظ [alias] — الفارغ يمسحه (يرجع السجلّ ليوزر الصفحة).
  static Future<({bool ok, String? alias, String? message})> save(String alias) async {
    try {
      final r = await ApiClient.dio.put<Map<String, dynamic>>(path, data: {'alias': alias.trim()});
      final b = r.data ?? const {};
      if (b['success'] != true) return (ok: false, alias: null, message: b['message']?.toString() ?? 'تعذّر الحفظ');
      final a = b['alias']?.toString().trim();
      return (ok: true, alias: (a == null || a.isEmpty) ? null : a, message: b['message']?.toString());
    } catch (e) {
      if (!kReleaseMode) debugPrint('🔴 manager alias PUT: $e');
      return (ok: false, alias: null, message: _msgOf(e, 'تعذّر الحفظ'));
    }
  }
}
