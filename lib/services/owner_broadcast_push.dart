import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/api_client.dart';
import 'auth_storage.dart';

/// «الإشعارات العامّة» (٢٥ نوفمبر — لوحة المالك، server/ownerBroadcast.js؛ المالك: «وشرط اشوف منو شاهده»): إشعارٌ من المالك
/// لكلّ المدراء — data: { type: owner_broadcast, broadcast_id, url? (مع «حدّث الآن»: رابط متجر نظام الجهاز) }.
///   • «شاهده»: وصل والتطبيق مفتوح، أو نُقر (من الهاتف أو الحاسبة أو صندوق الإشعارات) ⇒ POST /api/fcm/register/seen — مرّةً لكلّ إشعار
///     بهذا التشغيل (والخادم يحفظ الأوّل)، بلا انتظارٍ ولا خطأٍ يظهر؛ تعذّر ⇒ يُعاد بالمرّة القادمة.
///   • النقر ومعه رابط متجرٍ معروف (https لبلاي أو أبل أو مايكروسوفت وحدها) ⇒ يفتحه خارج التطبيق.
class OwnerBroadcastPush {
  OwnerBroadcastPush._();

  static const type = 'owner_broadcast';
  static const seenPath = '/api/fcm/register/seen';
  static const _storeHosts = {'play.google.com', 'apps.apple.com', 'apps.microsoft.com', 'www.microsoft.com'};
  static final Set<int> _reported = {};

  /// للاختبار: بدل النداء الفعليّ.
  @visibleForTesting
  static Future<void> Function(int id, String? adminId)? debugPost;

  /// للاختبار: بدل فتح الرابط.
  @visibleForTesting
  static Future<void> Function(Uri url)? debugLaunch;

  static bool isOwnerBroadcast(Map<String, dynamic> data) => data['type'] == type;

  static int? idOf(Map<String, dynamic> data) {
    final id = int.tryParse('${data['broadcast_id'] ?? ''}'.trim());
    return id != null && id > 0 ? id : null;
  }

  /// يبلّغ «شاهده» مرّةً لكلّ إشعار — لا يرمي.
  static Future<void> reportSeen(Map<String, dynamic> data) async {
    if (!isOwnerBroadcast(data)) return;
    final id = idOf(data);
    if (id == null || !_reported.add(id)) return;
    String? adminId;
    try {
      adminId = await AuthStorage.readAdminId();
    } catch (_) {
      adminId = null;
    }
    try {
      final f = debugPost;
      if (f != null) {
        await f(id, adminId);
        return;
      }
      await ApiClient.dio.post<Map<String, dynamic>>(seenPath, data: {
        'broadcast_id': id,
        if (adminId != null && adminId.isNotEmpty) 'adminId': adminId,
      });
    } catch (_) {
      _reported.remove(id); // يُعاد بالمرّة القادمة
    }
  }

  /// رابط «حدّث الآن» الآمن (متاجر التطبيق وحدها) أو null.
  static Uri? storeUrlOf(Map<String, dynamic> data) {
    final s = '${data['url'] ?? ''}'.trim();
    if (s.isEmpty) return null;
    final u = Uri.tryParse(s);
    if (u == null || u.scheme != 'https' || !_storeHosts.contains(u.host)) return null;
    return u;
  }

  /// النقر: «شاهده»، ورابط المتجر إن كان ⇒ true (إشعار المالك عولج — الموجّه لا يكمل).
  static Future<bool> handleTap(Map<String, dynamic> data) async {
    if (!isOwnerBroadcast(data)) return false;
    unawaited(reportSeen(data));
    final u = storeUrlOf(data);
    if (u != null) {
      try {
        final f = debugLaunch;
        if (f != null) {
          await f(u);
        } else {
          await launchUrl(u, mode: LaunchMode.externalApplication);
        }
      } catch (_) {/* المتجر لم يُفتح — الإشعار بالصندوق كما هو */}
    }
    return true;
  }

  @visibleForTesting
  static void resetForTest() {
    _reported.clear();
    debugPost = null;
    debugLaunch = null;
  }
}
