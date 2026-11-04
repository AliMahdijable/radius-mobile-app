import 'package:flutter/material.dart';

import '../api/account_api.dart';
import '../models/app_notification.dart';
import '../screens/account/company_switch_sheet.dart';
import 'auth_storage.dart';
import 'linked_companies.dart';

/// «إشعارات كلّ شركاتي» (٤ نوفمبر — المالك: «اي هاي ضروريه لان كل وكيل اذا عدنه اكثر من شركه كيف بهيج حاله»).
///
/// الخادم يرسل دفع كلّ شركةٍ مربوطةٍ بالحساب لهواتفه — والعنوان باسمها — وفي بيانات كلّ دفعٍ `company_admin_id`
/// (server/accountPush.js). نقرة إشعارٍ لشركةٍ من شركات الحساب غير المفتوحة ⇒ ورقة «تبديل الشركة» تفتحها بنفسها (مسار «شركاتي»
/// نفسه: استئنافٌ بلا كلمة سرّ، وإلّا نموذج الدخول برسالته)، والإشعار يُوجَّه فيها حين تُبنى رئيسيّتها. ليست من شركات الحساب
/// (موظّف، أو حسابٌ آخر) أو إشعارٌ بلا شركة ⇒ كما كان.
class CompanyPush {
  CompanyPush._();

  /// شركة الإشعار، أو null (إشعارٌ من خادمٍ أقدم بلا شركة).
  static String? companyOf(Map<String, String> data) {
    final v = data['company_admin_id']?.trim();
    return v == null || v.isEmpty ? null : v;
  }

  /// شركة الحساب (مديراً لا موظّفاً) التي معرّفها [adminId]، أو null.
  @visibleForTesting
  static LinkedCompany? pick(List<LinkedCompany>? items, String adminId) {
    for (final c in items ?? const <LinkedCompany>[]) {
      if (!c.isEmployee && c.adminId == adminId) return c;
    }
    return null;
  }

  /// إشعاراتٌ حُوّلت مرّة — لا تُحوَّل ثانيةً: لو اختلف معرّف الجلسة بعد الفتح عن معرّف الإشعار بصيغته، تُوجَّه حيث هي ولا
  /// تدور الورقة بلا نهاية.
  static final Set<String> _redirected = {};

  /// منفذ الاختبار: فتح الورقة على الشركة.
  @visibleForTesting
  static Future<void> Function(BuildContext context, LinkedCompany c, String label) openSheet =
      (context, c, label) => showCompanySwitchSheet(context, autoOpen: c, notice: label);

  @visibleForTesting
  static void debugReset() {
    _redirected.clear();
    openSheet = (context, c, label) => showCompanySwitchSheet(context, autoOpen: c, notice: label);
  }

  /// true = تولّى الإشعار (فُتحت ورقة شركته)؛ [defer] يحفظه لرئيسيّة الشركة بعد فتحها، و[undefer] يُسقطه إن لم تُفتح.
  static Future<bool> redirect(
    NavigatorState nav,
    AppNotification n, {
    required void Function(AppNotification n) defer,
    required void Function(AppNotification n) undefer,
  }) async {
    final target = companyOf(n.data);
    if (target == null || _redirected.contains(n.id)) return false;
    final open = (await AuthStorage.readAdminId())?.trim() ?? '';
    if (open.isEmpty || open == target) return false;
    if (!LinkedCompanies.ownerSession) return false;
    var c = pick(LinkedCompanies.items.value, target);
    if (c == null) {
      try {
        c = pick(await LinkedCompanies.load(), target);
      } catch (_) {/* بلا قائمة ⇒ كما كان */}
    }
    final ctx = nav.overlay?.context;
    if (c == null || ctx == null || !ctx.mounted) return false;
    _redirected.add(n.id);
    defer(n);
    final label = (n.data['company_label'] ?? '').trim();
    await openSheet(ctx, c, label.isNotEmpty ? label : c.label);
    final now = (await AuthStorage.readAdminId())?.trim() ?? '';
    if (now != target) undefer(n);
    return true;
  }
}
