import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'api_client.dart';

/// «أرقام تواصل إضافيّة» للمشترك (المالك ١٤ نوفمبر: «اضافة امكانيه اضافة رقم واتساب ومعرف او رقم تلي كرام للمشترك هذا ماله علاقة
/// بالي موجود بالساس … يستعين بالرقم الثاني … بمعرف تلي»): على خادمنا وحده (`server/subscriberContacts.js`) — لا يُكتب في الساس.
/// يُستعملان حين لا يصل رقم المشترك: الواتساب الثاني، ثمّ تلغرامه (بحساب الوكيل لمن ربط «حسابي»). المفتاح مطفأ ⇒ enabled:false.
class SubscriberContacts {
  const SubscriberContacts({this.waPhone2, this.tgContact});

  /// الواتساب الثاني بالصيغة المحلّيّة (07…) كما يعيده الخادم.
  final String? waPhone2;

  /// تلغرام: «@معرّف» أو رقمٌ دوليّ.
  final String? tgContact;

  bool get isEmpty => (waPhone2 ?? '').isEmpty && (tgContact ?? '').isEmpty;

  static SubscriberContacts? fromJson(dynamic v) {
    if (v is! Map) return null;
    String? s(dynamic x) {
      final t = x?.toString().trim() ?? '';
      return t.isEmpty ? null : t;
    }

    final c = SubscriberContacts(waPhone2: s(v['wa_phone2']), tgContact: s(v['tg_contact']));
    return c.isEmpty ? null : c;
  }
}

class SubscriberContactsApi {
  SubscriberContactsApi._();

  static const String path = '/api/v2/subscriber-contacts';

  static String _msg(Object e, String fallback) {
    if (e is DioException) {
      final b = e.response?.data;
      final m = b is Map ? b['message']?.toString() : null;
      if (m != null && m.trim().isNotEmpty) return m;
    }
    return fallback;
  }

  /// أرقام المشترك — ok:true وcontact:null = لا أرقام؛ enabled:false = الميزة لم تُفتح للحساب (لا قسم ولا زرّ).
  static Future<({bool ok, bool enabled, SubscriberContacts? contact, String? message})> get(String username) async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>(path, queryParameters: {'username': username});
      final b = r.data ?? const {};
      if (b['success'] != true) return (ok: false, enabled: false, contact: null, message: b['message']?.toString());
      return (ok: true, enabled: b['enabled'] == true, contact: SubscriberContacts.fromJson(b['contact']), message: null);
    } catch (e) {
      if (!kReleaseMode) debugPrint('🔴 subscriber-contacts GET: $e');
      return (ok: false, enabled: false, contact: null, message: _msg(e, 'تعذّر جلب الأرقام'));
    }
  }

  /// حفظ الرقمين — الفارغان يحذفانهما. خطأ حقلٍ ⇒ field ('wa_phone2' | 'tg_contact') ورسالته العربيّة من الخادم.
  static Future<({bool ok, SubscriberContacts? contact, String? field, String? message})> save(
    String username, {
    required String wa,
    required String tg,
    String? phone,
  }) async {
    try {
      final r = await ApiClient.dio.put<Map<String, dynamic>>(path, data: {
        'username': username,
        'wa_phone2': wa.trim(),
        'tg_contact': tg.trim(),
        'phone': phone ?? '',
      });
      final b = r.data ?? const {};
      if (b['success'] != true) {
        return (ok: false, contact: null, field: b['field']?.toString(), message: b['message']?.toString() ?? 'تعذّر الحفظ');
      }
      return (ok: true, contact: SubscriberContacts.fromJson(b['contact']), field: null, message: null);
    } catch (e) {
      if (!kReleaseMode) debugPrint('🔴 subscriber-contacts PUT: $e');
      String? field;
      if (e is DioException) {
        final b = e.response?.data;
        if (b is Map && b['field'] != null) field = b['field'].toString();
      }
      return (ok: false, contact: null, field: field, message: _msg(e, 'تعذّر الحفظ'));
    }
  }
}
