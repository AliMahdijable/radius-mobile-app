import 'package:flutter/material.dart';

import '../../services/auth_storage.dart';
import '../../services/permissions_service.dart';
import '../../services/provider_service.dart';
import '../../core/widgets/permission_locked.dart';
import 'national_tickets_screen.dart';

/// نقرة تنبيه «تذكرة جديدة من المشروع الوطني» (الخادم `server/watani/wataniTicketAlerts.js`، `type: watani_ticket`، ١ نوفمبر —
/// المالك: «نحتاج fmc بالبرنامج يقره التكتات الي دزها الشركه ع الصفحه ينرسل تنبيه للتطبيق»): «التذاكر» وفوقها ورقة التذكرة
/// (تذكرةٌ واحدة)، أو «التذاكر» وحدها (ملخّص). مصدرٌ واحد لنقرة النظام ولنقرة صندوق الوارد.
enum NationalPushTarget { notTicket, otherAccount, notNational, noPermission, open }

final RegExp _uuid = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$', caseSensitive: false);

/// القرار وحده (نقيّ — للاختبار): التنبيه لحسابٍ آخر غير الجلسة المفتوحة ⇒ لا تُفتح تذاكر غيره.
NationalPushTarget nationalPushTarget(
  Map<String, String> data, {
  required String? currentAdminId,
  required bool isNational,
  required bool canView,
}) {
  if (data['type'] != 'watani_ticket') return NationalPushTarget.notTicket;
  final target = (data['admin_id'] ?? '').trim();
  if (target.isNotEmpty && target != (currentAdminId ?? '').trim()) return NationalPushTarget.otherAccount;
  if (!isNational) return NationalPushTarget.notNational;
  if (!canView) return NationalPushTarget.noPermission;
  return NationalPushTarget.open;
}

/// معرّف التذكرة لورقتها، أو null (ملخّص / معرّفٌ غير صالح ⇒ القائمة وحدها).
String? nationalPushTicketId(Map<String, String> data) {
  final id = (data['ticket_id'] ?? '').trim();
  return _uuid.hasMatch(id) ? id : null;
}

const nationalPushOtherAccount = 'هذا التنبيه لحسابك في المشروع الوطني — افتحه من «شركاتي» لترى التذكرة';

/// `false` = ليس تنبيه تذكرة، فيكمل الموجِّه طريقه.
Future<bool> openNationalTicketPush(NavigatorState nav, Map<String, String> data) async {
  if (data['type'] != 'watani_ticket') return false;
  final t = nationalPushTarget(
    data,
    currentAdminId: await AuthStorage.readAdminId(),
    isNational: ProviderService.isKit && ProviderService.parentIsZone,
    canView: Perms.has('subscribers.view'),
  );
  if (!nav.mounted) return true;
  switch (t) {
    case NationalPushTarget.notTicket:
      return false;
    case NationalPushTarget.otherAccount:
    case NationalPushTarget.notNational:
      ScaffoldMessenger.maybeOf(nav.context)?.showSnackBar(const SnackBar(content: Text(nationalPushOtherAccount)));
      return true;
    case NationalPushTarget.noPermission:
      showNoPermission(nav.context);
      return true;
    case NationalPushTarget.open:
      await nav.push(MaterialPageRoute(
        builder: (_) => NationalTicketsScreen(
          openTicketId: nationalPushTicketId(data),
          openDisplayId: data['display_id'],
        ),
      ));
      return true;
  }
}
