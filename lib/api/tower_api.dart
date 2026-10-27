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
}
