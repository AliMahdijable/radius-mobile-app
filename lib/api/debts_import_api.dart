import 'package:dio/dio.dart';

import 'api_client.dart';

/// نتيجة دفعةٍ من الاستيراد (`POST /api/v2/debts/bulk-import` ⇒ `data`) — أو مجموع الدفعات.
class DebtImportResult {
  DebtImportResult({this.total = 0});

  int total;
  int applied = 0;
  final notFound = <String>[];
  final invalid = <String>[];

  /// صفوفٌ لم تُطبَّق بسببها من الخادم («طُبّق قبل أقلّ من ٣٠ دقيقة»، «عمليّة أخرى جارية»…).
  final failed = <({String username, String error})>[];

  /// ما طُبِّق: الدين قبل وبعد.
  final details = <({String username, num previous, num next})>[];

  /// صفوفٌ لا تُعرف نتيجتها: دفعةٌ انقطع ردّها (مهلة/شبكة/5xx) — قد يكون بعضها طُبِّق. لا تُعاد تلقائيّاً.
  final unknown = <String>[];

  /// سبب توقّف الخادم إن أوقف الاستيراد (`stopped`).
  String? stopped;

  void add(Map<String, dynamic> j) {
    applied += (j['applied'] as num?)?.toInt() ?? 0;
    for (final u in (j['not_found'] as List?) ?? const []) {
      notFound.add('$u');
    }
    for (final x in (j['invalid'] as List?) ?? const []) {
      invalid.add(x is Map ? '${x['username'] ?? ''}' : '$x');
    }
    for (final x in (j['failed'] as List?) ?? const []) {
      if (x is Map) failed.add((username: '${x['username'] ?? ''}', error: '${x['error'] ?? ''}'));
    }
    for (final x in (j['details'] as List?) ?? const []) {
      if (x is Map) {
        details.add((
          username: '${x['username'] ?? ''}',
          previous: num.tryParse('${x['previous']}') ?? 0,
          next: num.tryParse('${x['new']}') ?? 0,
        ));
      }
    }
    final s = j['stopped'];
    if (s != null && '$s'.isNotEmpty) stopped = '$s';
  }
}

/// نتيجة «أضفها لديون المحذوفين» (`POST /api/v2/deleted-debts/import`).
class DeletedImportResult {
  const DeletedImportResult({
    required this.added,
    required this.debtAdded,
    required this.exists,
    required this.repeatRows,
    required this.duplicate,
    required this.invalid,
    required this.failed,
  });

  final int added;
  final num debtAdded;
  final int exists;

  /// أرقام الصفوف (من ١) التي أُضيفت قبل أقلّ من ٣٠ دقيقة — «أضف المكرّرة أيضاً» يعيدها وحدها.
  final List<int> repeatRows;
  final int duplicate;
  final int invalid;
  final int failed;

  static DeletedImportResult fromJson(Map<String, dynamic> j) {
    int n(Object? v) => v is List ? v.length : 0;
    return DeletedImportResult(
      added: (j['added'] as num?)?.toInt() ?? 0,
      debtAdded: (j['debt_added'] as num?) ?? 0,
      exists: n(j['exists']),
      repeatRows: [
        for (final x in (j['repeat'] as List?) ?? const [])
          if (x is Map && x['row'] is num) (x['row'] as num).toInt(),
      ],
      duplicate: n(j['duplicate']),
      invalid: n(j['invalid']),
      failed: n(j['failed']),
    );
  }
}

/// «استيراد / تصدير الديون» (٢٣ نوفمبر — كالموقع pages/DebtsImport.tsx): لصاحب الحساب وحده (الخادم يردّ الموظّف 403 OWNER_ONLY).
class DebtsImportApi {
  DebtsImportApi._();

  /// دفعةٌ واحدة: [rows] = (اليوزر، المبلغ)، [mode] 'set' (استبدال) أو 'add' (إضافة). ردٌّ مقروء ⇒ data؛ رفضٌ بسببه ⇒ message؛ انقطاعٌ
  /// بلا ردّ (مهلة/شبكة/5xx) ⇒ [unknown] — لا يُعاد: قد يكون الخادم طبّق بعضها (الصفوف المطبَّقة لا تُطبَّق ثانيةً خلال ٣٠ دقيقة).
  static Future<({Map<String, dynamic>? data, String? message, bool unknown})> bulkImport(
    List<({String username, double amount})> rows,
    String mode,
  ) async {
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>(
        '/api/v2/debts/bulk-import',
        data: {
          'rows': [for (final x in rows) {'username': x.username, 'amount': x.amount == x.amount.truncate() ? x.amount.truncate() : x.amount}],
          'mode': mode,
        },
        options: Options(sendTimeout: const Duration(seconds: 30), receiveTimeout: const Duration(seconds: 120)),
      );
      final body = r.data ?? const {};
      final code = r.statusCode ?? 0;
      if (body['success'] == true && body['data'] is Map) {
        return (data: Map<String, dynamic>.from(body['data'] as Map), message: null, unknown: false);
      }
      if (code >= 500 || code == 0) return (data: null, message: null, unknown: true);
      return (data: null, message: body['message']?.toString() ?? 'لم يُطبَّق', unknown: false);
    } on DioException catch (e) {
      final code = e.response?.statusCode ?? 0;
      final data = e.response?.data;
      // رفضٌ صريح قبل التطبيق (4xx برسالته) — ليس «غير مؤكَّد»
      if (code >= 400 && code < 500) {
        return (data: null, message: data is Map ? (data['message']?.toString() ?? 'لم يُطبَّق') : 'لم يُطبَّق', unknown: false);
      }
      return (data: null, message: null, unknown: true);
    } catch (_) {
      return (data: null, message: null, unknown: true);
    }
  }

  /// أرقام التواصل الإضافيّة لكلّ المشتركين (للتصدير) — null حين لا تُفتح للحساب أو تتعذّر (يُصدَّر بلاها كالموقع).
  static Future<Map<String, ({String? wa2, String? tg})>?> contactsAll() async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>('/api/v2/subscriber-contacts/all');
      final body = r.data ?? const {};
      if (body['success'] != true || body['enabled'] != true) return null;
      final c = body['contacts'];
      final out = <String, ({String? wa2, String? tg})>{};
      if (c is Map) {
        for (final e in c.entries) {
          final v = e.value;
          out['${e.key}'] = v is Map ? (wa2: v['wa_phone2']?.toString(), tg: v['tg_contact']?.toString()) : (wa2: null, tg: null);
        }
      }
      return out;
    } catch (_) {
      return null;
    }
  }

  /// صفوف «غير موجود» ⇒ «ديون المشتركين المحذوفين» بالاسم والهاتف والمبلغ. [confirmRepeat] ⇒ تُضاف المكرّرة خلال ٣٠ دقيقة أيضاً.
  static Future<({DeletedImportResult? result, String? message})> importDeleted(
    List<({String name, double amount, String phone, String username})> rows, {
    bool confirmRepeat = false,
  }) async {
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>(
        '/api/v2/deleted-debts/import',
        data: {
          'rows': [
            for (final x in rows) {'name': x.name, 'amount': x.amount, 'phone': x.phone, 'username': x.username},
          ],
          if (confirmRepeat) 'confirmRepeat': true,
        },
        options: Options(receiveTimeout: const Duration(seconds: 120)),
      );
      final body = r.data ?? const {};
      if (body['success'] == true && body['data'] is Map) {
        return (result: DeletedImportResult.fromJson(Map<String, dynamic>.from(body['data'] as Map)), message: null);
      }
      return (result: null, message: body['message']?.toString() ?? 'تعذّرت الإضافة');
    } on DioException catch (e) {
      final data = e.response?.data;
      return (result: null, message: data is Map ? (data['message']?.toString() ?? 'تعذّرت الإضافة') : 'تعذّرت الإضافة');
    } catch (_) {
      return (result: null, message: 'تعذّرت الإضافة');
    }
  }
}
