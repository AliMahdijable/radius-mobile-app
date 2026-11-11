import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../core/util/error_text.dart';
import '../models/tower_layout.dart';
import 'api_client.dart';

/// عرض البرج — حفظ شكل البرج ومكان كلّ جهاز على خادمنا (server/towerRoutes.js)، فيراه المدير والموظّف من أيّ هاتف.
///
/// القراءة `devices.view`، والتعديل `devices.manage`. لا يرمي للواجهة: سجلّاتٌ `({ok, …, message})`.
/// تعذّر الجلب لا يمنع العرض — الشاشة ترسم الترتيب التلقائيّ في الذاكرة (نفسه على كلّ هاتف).
class TowerApi {
  TowerApi._();

  static const _base = '/api/v2/admin/devices';

  static void _log(String where, Object e) {
    if (kDebugMode) debugPrint('[TowerApi] $where: $e');
  }

  static String _msg(Response<dynamic>? r, String fallback) {
    final m = r?.data is Map ? (r!.data as Map)['message'] : null;
    return m is String && m.trim().isNotEmpty ? m : fallback;
  }

  /// `GET /towers` — كلّ أبراج الحساب ومواقع أجهزته.
  static Future<({bool ok, TowerLayouts layouts, String? message})> load() async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>(
        '$_base/towers',
        options: Options(receiveTimeout: const Duration(seconds: 10)),
      );
      if (r.statusCode != 200 || r.data?['success'] != true) {
        return (ok: false, layouts: TowerLayouts.empty, message: _msg(r, 'تعذّر جلب ترتيب البرج'));
      }
      return (ok: true, layouts: TowerLayouts.fromJson(r.data), message: null);
    } catch (e) {
      _log('load', e);
      return (ok: false, layouts: TowerLayouts.empty, message: humanError(e, fallback: 'تعذّر جلب ترتيب البرج'));
    }
  }

  /// `PUT /towers/:regionId` — نوع البرج وارتفاعه وحلقاته.
  static Future<({bool ok, String? message})> saveTower(TowerSettings s) async {
    try {
      final r = await ApiClient.dio.put<Map<String, dynamic>>('$_base/towers/${s.regionId}', data: s.toJson());
      if (r.statusCode != 200 || r.data?['success'] != true) {
        return (ok: false, message: _msg(r, 'تعذّر حفظ شكل البرج'));
      }
      return (ok: true, message: null);
    } catch (e) {
      _log('saveTower', e);
      return (ok: false, message: humanError(e, fallback: 'تعذّر حفظ شكل البرج'));
    }
  }

  /// `PUT /:id/tower` — مكان جهازٍ واحد كاملاً (تعديل الوكيل بيده أو بالبوصلة).
  static Future<({bool ok, String? message})> savePlacement(TowerPlacement p) async {
    try {
      final r = await ApiClient.dio.put<Map<String, dynamic>>('$_base/${p.deviceId}/tower', data: p.toJson());
      if (r.statusCode != 200 || r.data?['success'] != true) {
        return (ok: false, message: _msg(r, 'تعذّر حفظ مكان الجهاز'));
      }
      return (ok: true, message: null);
    } catch (e) {
      _log('savePlacement', e);
      return (ok: false, message: humanError(e, fallback: 'تعذّر حفظ مكان الجهاز'));
    }
  }

  /// `POST /towers/placements` — «رتّبها لي»: دفعةٌ واحدة. الخادم لا يستبدل مكاناً ثبّته الوكيل بمكانٍ تقريبيّ.
  static Future<({bool ok, int saved, String? message})> savePlacements(Iterable<TowerPlacement> list) async {
    final items = [for (final p in list) p.toJson()];
    if (items.isEmpty) return (ok: true, saved: 0, message: null);
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>('$_base/towers/placements', data: {'placements': items});
      if (r.statusCode != 200 || r.data?['success'] != true) {
        return (ok: false, saved: 0, message: _msg(r, 'تعذّر حفظ الترتيب'));
      }
      final n = r.data?['saved'];
      return (ok: true, saved: n is int ? n : items.length, message: null);
    } catch (e) {
      _log('savePlacements', e);
      return (ok: false, saved: 0, message: humanError(e, fallback: 'تعذّر حفظ الترتيب'));
    }
  }

  // ── ترابط الأبراج (١١ نوفمبر — الهجرة 086) ───────────────────────────────────────────────────

  /// `POST /towers/links` — ربطٌ من جهاز البرج الرئيسيّ [aDeviceId] إلى جهاز الفرعيّ [bDeviceId]: لنكٌ لاسلكيّ (الافتراضيّ،
  /// كما كان) أو كيبلٌ ضوئيّ ([kind] = fiber) بمنفذه عند كلّ طرف ([aPort]/[bPort] — يُحدَّدان الآن أو لاحقاً).
  /// [existed]: الخادم وجده مربوطاً من قبل فأعاده كما هو.
  static Future<({bool ok, TowerLink? link, bool existed, String? message})> addLink(
    int aDeviceId,
    int bDeviceId, {
    String? label,
    TowerLinkKind kind = TowerLinkKind.radio,
    String? aPort,
    String? bPort,
  }) async {
    String? port(String? v) => v == null || v.trim().isEmpty ? null : v.trim();
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>('$_base/towers/links', data: {
        'a_device_id': aDeviceId,
        'b_device_id': bDeviceId,
        if (label != null && label.trim().isNotEmpty) 'label': label.trim(),
        // اللاسلكيّ بلا «kind»: الطلب نفسه الذي يفهمه خادمٌ قبل الهجرة 087
        if (kind == TowerLinkKind.fiber) ...{
          'kind': kind.wire,
          if (port(aPort) != null) 'a_port': port(aPort),
          if (port(bPort) != null) 'b_port': port(bPort),
        },
      });
      final link = TowerLink.fromJson(r.data?['link']);
      if (r.statusCode != 200 || r.data?['success'] != true || link == null) {
        return (ok: false, link: null, existed: false, message: _msg(r, 'تعذّر حفظ الربط'));
      }
      return (ok: true, link: link, existed: r.data?['existed'] == true, message: null);
    } catch (e) {
      _log('addLink', e);
      return (ok: false, link: null, existed: false, message: humanError(e, fallback: 'تعذّر حفظ الربط'));
    }
  }

  /// `PUT /towers/links/:id` — نوع الربط ومنفذا الكيبل معاً (المنفذ null يُمسح؛ واللاسلكيّ بلا منافذ).
  static Future<({bool ok, TowerLink? link, String? message})> setLinkMedium(
    int id, {
    required TowerLinkKind kind,
    String? aPort,
    String? bPort,
  }) async {
    String? port(String? v) => v == null || v.trim().isEmpty ? null : v.trim();
    try {
      final r = await ApiClient.dio.put<Map<String, dynamic>>('$_base/towers/links/$id', data: {
        'kind': kind.wire,
        if (kind == TowerLinkKind.fiber) ...{'a_port': port(aPort), 'b_port': port(bPort)},
      });
      final link = TowerLink.fromJson(r.data?['link']);
      if (r.statusCode != 200 || r.data?['success'] != true || link == null) {
        return (ok: false, link: null, message: _msg(r, 'تعذّر تعديل الربط'));
      }
      return (ok: true, link: link, message: null);
    } catch (e) {
      _log('setLinkMedium', e);
      return (ok: false, link: null, message: humanError(e, fallback: 'تعذّر تعديل الربط'));
    }
  }

  /// `PUT /towers/links/:id` — قلب الاتّجاه ([flip]) و/أو الاسم ([label]؛ نصٌّ فارغ يمسحه).
  static Future<({bool ok, TowerLink? link, String? message})> updateLink(int id, {bool flip = false, String? label}) async {
    try {
      final r = await ApiClient.dio.put<Map<String, dynamic>>('$_base/towers/links/$id', data: {
        if (flip) 'flip': true,
        if (label != null) 'label': label.trim().isEmpty ? null : label.trim(),
      });
      final link = TowerLink.fromJson(r.data?['link']);
      if (r.statusCode != 200 || r.data?['success'] != true || link == null) {
        return (ok: false, link: null, message: _msg(r, 'تعذّر تعديل الربط'));
      }
      return (ok: true, link: link, message: null);
    } catch (e) {
      _log('updateLink', e);
      return (ok: false, link: null, message: humanError(e, fallback: 'تعذّر تعديل الربط'));
    }
  }

  /// `DELETE /towers/links/:id`.
  static Future<({bool ok, String? message})> deleteLink(int id) async {
    try {
      final r = await ApiClient.dio.delete<Map<String, dynamic>>('$_base/towers/links/$id');
      if (r.statusCode != 200 || r.data?['success'] != true) return (ok: false, message: _msg(r, 'تعذّر حذف الربط'));
      return (ok: true, message: null);
    } catch (e) {
      _log('deleteLink', e);
      return (ok: false, message: humanError(e, fallback: 'تعذّر حذف الربط'));
    }
  }

  /// `POST /regions/:id/assign` — أجهزةٌ لبرج (منطقة) دفعةً؛ [regionId] 0 = بلا منطقة.
  static Future<({bool ok, int moved, String? message})> assignDevices(int regionId, Iterable<int> deviceIds) async {
    final ids = deviceIds.toSet().toList();
    if (ids.isEmpty) return (ok: true, moved: 0, message: null);
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>('$_base/regions/$regionId/assign', data: {'device_ids': ids});
      if (r.statusCode != 200 || r.data?['success'] != true) return (ok: false, moved: 0, message: _msg(r, 'تعذّر نقل الأجهزة'));
      final n = r.data?['moved'];
      return (ok: true, moved: n is int ? n : ids.length, message: null);
    } catch (e) {
      _log('assignDevices', e);
      return (ok: false, moved: 0, message: humanError(e, fallback: 'تعذّر نقل الأجهزة'));
    }
  }
}
