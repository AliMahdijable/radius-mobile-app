import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../core/util/error_text.dart';
import '../models/fiber_network.dart';
import '../services/fiber/fiber_light.dart';
import 'api_client.dart';

/// شبكة الألياف على خادمنا (server/fiberRoutes.js، migration 033) — الصناديق والربط والإعدادات وتاريخ الضوء والأعطال،
/// فيراها المدير والموظّف من أيّ هاتفٍ أو حاسبة، ويصل إشعار العطل لأجهزة الحساب من أيّ جهازٍ رآه.
///
/// القراءة والتبليغ (الضوء، الأعطال، القدرات) `devices.view`؛ تعديل التخطيط والإعدادات `devices.manage`.
/// لا يرمي للواجهة: سجلّات `({ok, …, message})`. [notDeployed] = المسار غير موجود بعد (404) ⇒ الحفظ على الجهاز وحده.
class FiberApi {
  FiberApi._();

  static const _base = '/api/v2/admin/devices/fiber';

  static void _log(String where, Object e) {
    if (kDebugMode) debugPrint('[FiberApi] $where: $e');
  }

  static String _msg(Response<dynamic>? r, String fallback) {
    final m = r?.data is Map ? (r!.data as Map)['message'] : null;
    return m is String && m.trim().isNotEmpty ? m : fallback;
  }

  static bool _missing(Object e) => e is DioException && e.response?.statusCode == 404;

  /// ردٌّ لم يرمِ (معترضٌ حوّله ردّاً) بـ404 = المسار غير موجود بعد، كالمرميّ.
  static bool _absent(Response<dynamic>? r) => r?.statusCode == 404;

  static Options get _quick => Options(receiveTimeout: const Duration(seconds: 12), sendTimeout: const Duration(seconds: 12));

  /// `GET /fiber` — كلّ ما حُفظ للحساب.
  static Future<({bool ok, bool notDeployed, FiberLayout layout, Map<int, Map<String, dynamic>> caps, String? message})>
      load() async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>(_base, options: _quick);
      if (r.statusCode != 200 || r.data?['success'] != true) {
        return (ok: false, notDeployed: _absent(r), layout: FiberLayout.empty, caps: const <int, Map<String, dynamic>>{}, message: _msg(r, 'تعذّر جلب شبكة الألياف'));
      }
      final caps = <int, Map<String, dynamic>>{};
      final c = r.data?['caps'];
      if (c is Map) {
        for (final e in c.entries) {
          final id = int.tryParse('${e.key}');
          if (id != null && e.value is Map) caps[id] = Map<String, dynamic>.from(e.value as Map);
        }
      }
      return (ok: true, notDeployed: false, layout: FiberLayout.fromJson(r.data), caps: caps, message: null);
    } catch (e) {
      _log('load', e);
      return (
        ok: false,
        notDeployed: _missing(e),
        layout: FiberLayout.empty,
        caps: const <int, Map<String, dynamic>>{},
        message: humanError(e, fallback: 'تعذّر جلب شبكة الألياف'),
      );
    }
  }

  /// `PUT /fiber/boxes/:id` — رقمٌ سالب (محلّيّ) أو صفر ⇒ إنشاء، والردّ يحمل رقم الخادم.
  static Future<({bool ok, bool notDeployed, FiberBox? box, String? message})> saveBox(FiberBox b) async {
    try {
      final id = b.id > 0 ? b.id : 0;
      final r = await ApiClient.dio.put<Map<String, dynamic>>('$_base/boxes/$id', data: b.toJson()..remove('id'), options: _quick);
      final saved = FiberBox.fromJson(r.data?['box']);
      if (r.statusCode != 200 || r.data?['success'] != true || saved == null) {
        return (ok: false, notDeployed: _absent(r), box: null, message: _msg(r, 'تعذّر حفظ الصندوق'));
      }
      return (ok: true, notDeployed: false, box: saved, message: null);
    } catch (e) {
      _log('saveBox', e);
      return (ok: false, notDeployed: _missing(e), box: null, message: humanError(e, fallback: 'تعذّر حفظ الصندوق'));
    }
  }

  /// `DELETE /fiber/boxes/:id` — صناديقه ترتفع لأبيه وأجهزته بلا صندوق (على الخادم نفسه).
  static Future<({bool ok, bool notDeployed, String? message})> deleteBox(int id) async {
    try {
      final r = await ApiClient.dio.delete<Map<String, dynamic>>('$_base/boxes/$id', options: _quick);
      if (r.statusCode != 200 || r.data?['success'] != true) {
        return (ok: false, notDeployed: _absent(r), message: _msg(r, 'تعذّر حذف الصندوق'));
      }
      return (ok: true, notDeployed: false, message: null);
    } catch (e) {
      _log('deleteBox', e);
      return (ok: false, notDeployed: _missing(e), message: humanError(e, fallback: 'تعذّر حذف الصندوق'));
    }
  }

  /// `POST /fiber/onus` — سجلّات الأجهزة كاملةً (الصندوق والمشترك)؛ سجلٌّ فارغ يُحذف، و`old_key` لجهازٍ انتقل رقمه.
  static Future<({bool ok, bool notDeployed, int saved, String? message})> saveRecords(
    int oltId,
    List<({FiberOnuRecord record, String? oldKey})> items,
  ) async {
    if (items.isEmpty) return (ok: true, notDeployed: false, saved: 0, message: null);
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>(
        '$_base/onus',
        data: {
          'olt_id': oltId,
          'records': [
            for (final i in items)
              {
                ...i.record.toJson()..remove('olt_id')..remove('linked_at'),
                if (i.oldKey != null && i.oldKey != i.record.key) 'old_key': i.oldKey,
              },
          ],
        },
        options: _quick,
      );
      if (r.statusCode != 200 || r.data?['success'] != true) {
        return (ok: false, notDeployed: _absent(r), saved: 0, message: _msg(r, 'تعذّر حفظ الأجهزة'));
      }
      final n = r.data?['saved'];
      return (ok: true, notDeployed: false, saved: n is int ? n : items.length, message: null);
    } catch (e) {
      _log('saveRecords', e);
      return (ok: false, notDeployed: _missing(e), saved: 0, message: humanError(e, fallback: 'تعذّر حفظ الأجهزة'));
    }
  }

  /// `PUT /fiber/settings/:oltId`.
  static Future<({bool ok, bool notDeployed, String? message})> saveSettings(FiberOltSettings s) async {
    try {
      final r = await ApiClient.dio.put<Map<String, dynamic>>('$_base/settings/${s.oltId}', data: s.toJson(), options: _quick);
      if (r.statusCode != 200 || r.data?['success'] != true) {
        return (ok: false, notDeployed: _absent(r), message: _msg(r, 'تعذّر حفظ الإعدادات'));
      }
      return (ok: true, notDeployed: false, message: null);
    } catch (e) {
      _log('saveSettings', e);
      return (ok: false, notDeployed: _missing(e), message: humanError(e, fallback: 'تعذّر حفظ الإعدادات'));
    }
  }

  /// `POST /fiber/caps/:oltId` — ما يدعمه الأولت (بلا هويّات). أفضل جهد.
  static Future<bool> reportCaps(int oltId, Map<String, dynamic> caps) async {
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>('$_base/caps/$oltId', data: caps, options: _quick);
      return r.statusCode == 200 && r.data?['success'] == true;
    } catch (e) {
      _log('reportCaps', e);
      return false;
    }
  }

  /// `POST /fiber/rx` — أيّام الضوء التي تغيّرت (حتى ٢٠٠٠ صفّ).
  static Future<bool> uploadRx(int oltId, List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return true;
    try {
      for (var s = 0; s < rows.length; s += 2000) {
        final r = await ApiClient.dio.post<Map<String, dynamic>>(
          '$_base/rx',
          data: {'olt_id': oltId, 'rows': rows.skip(s).take(2000).toList()},
          options: _quick,
        );
        if (r.statusCode != 200 || r.data?['success'] != true) return false;
      }
      return true;
    } catch (e) {
      _log('uploadRx', e);
      return false;
    }
  }

  /// `GET /fiber/rx?olt_id&days` — تاريخ الضوء من كلّ أجهزة الحساب.
  static Future<({bool ok, List<({String key, RxDay day})> rows})> loadRx(int oltId, {int days = 14}) async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>(
        '$_base/rx',
        queryParameters: {'olt_id': '$oltId', 'days': '$days'},
        options: _quick,
      );
      if (r.statusCode != 200 || r.data?['success'] != true) return (ok: false, rows: const <({String key, RxDay day})>[]);
      final out = <({String key, RxDay day})>[];
      for (final x in (r.data?['rows'] is List ? r.data!['rows'] as List : const [])) {
        if (x is! Map) continue;
        final key = x['key'];
        final d = RxDay.fromJson(x);
        if (key is String && d != null) out.add((key: key, day: d));
      }
      return (ok: true, rows: out);
    } catch (e) {
      _log('loadRx', e);
      return (ok: false, rows: const <({String key, RxDay day})>[]);
    }
  }

  /// `POST /fiber/events` — عطلٌ رآه هذا الجهاز. الخادم يدمجه مع عطلٍ مفتوحٍ بالمكان نفسه (من جهازٍ آخر) أو ينشئه ويُشعر
  /// أجهزة الحساب.
  static Future<({bool ok, bool notDeployed, FiberEventRecord? event, bool pushed})> reportEvent({
    required int oltId,
    required String kind,
    required String scope,
    required String scopeKey,
    required String pon,
    required List<String> onus,
    required DateTime startedAt,
    int? boxId,
    String? title,
    String? body,
  }) async {
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>(
        '$_base/events',
        data: {
          'olt_id': oltId,
          'kind': kind,
          'scope': scope,
          'scope_key': scopeKey,
          'pon': pon,
          'box_id': boxId,
          'onus': onus,
          'started_at': startedAt.toUtc().toIso8601String(),
          if (title != null) 'title': title,
          if (body != null) 'body': body,
        },
        options: _quick,
      );
      final ev = FiberEventRecord.fromJson(r.data?['event']);
      if (r.statusCode != 200 || r.data?['success'] != true || ev == null) {
        return (ok: false, notDeployed: _absent(r), event: null, pushed: false);
      }
      return (ok: true, notDeployed: false, event: ev, pushed: r.data?['pushed'] == true);
    } catch (e) {
      _log('reportEvent', e);
      return (ok: false, notDeployed: _missing(e), event: null, pushed: false);
    }
  }

  /// `POST /fiber/events/:id/end` — رجعت الأجهزة.
  static Future<({bool ok, FiberEventRecord? event})> endEvent(int id, DateTime endedAt, {String? title, String? body}) async {
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>(
        '$_base/events/$id/end',
        data: {'ended_at': endedAt.toUtc().toIso8601String(), if (title != null) 'title': title, if (body != null) 'body': body},
        options: _quick,
      );
      final ev = FiberEventRecord.fromJson(r.data?['event']);
      return (ok: r.statusCode == 200 && r.data?['success'] == true, event: ev);
    } catch (e) {
      _log('endEvent', e);
      return (ok: false, event: null);
    }
  }

  /// `PUT /fiber/events/:id` — «لمّا يرجع النت أرسل لهم» و«بُلِّغوا».
  static Future<({bool ok, FiberEventRecord? event, String? message})> updateEvent(int id, {bool? autoBack, bool? notified}) async {
    try {
      final r = await ApiClient.dio.put<Map<String, dynamic>>(
        '$_base/events/$id',
        data: {if (autoBack != null) 'auto_back': autoBack, if (notified == true) 'notified': true},
        options: _quick,
      );
      if (r.statusCode != 200 || r.data?['success'] != true) {
        return (ok: false, event: null, message: _msg(r, 'تعذّر حفظ الاختيار'));
      }
      return (ok: true, event: FiberEventRecord.fromJson(r.data?['event']), message: null);
    } catch (e) {
      _log('updateEvent', e);
      return (ok: false, event: null, message: humanError(e, fallback: 'تعذّر حفظ الاختيار'));
    }
  }

  /// `POST /fiber/events/:id/back-claim` — مرّةً واحدة لكلّ عطل (أوّل جهازٍ يطلبها يرسل «رجع النت»، والبقيّة لا).
  static Future<bool> claimBack(int id) async {
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>('$_base/events/$id/back-claim', options: _quick);
      return r.statusCode == 200 && r.data?['success'] == true && r.data?['claimed'] == true;
    } catch (e) {
      _log('claimBack', e);
      return false;
    }
  }
}
