import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../services/permissions_service.dart';
import '../services/provider_service.dart';
import 'api_client.dart';

/// Employee row. Mirrors v1 _Employee.
class Employee {
  const Employee({
    required this.id,
    required this.username,
    this.fullName,
    this.phone,
    required this.isActive,
    required this.permissions,
    this.scopeAdminId,
    this.scopeAdminUsername,
    this.deleted = false,
    this.linked,
  });
  final int id;
  final String username;

  /// ٨ نوفمبر — «موظّفٌ بأكثر من صفحة»: صفٌّ مربوطٌ بشخصٍ يعمل في صفحاتٍ أخرى ([EmployeeLink])، وإلّا null.
  final EmployeeLink? linked;

  /// صفّ صفحةٍ مضافٌ من صفحةٍ أخرى — يدخل الشخص باسمه الأصليّ، فلا كلمة مرورٍ تُعرض أو تُغيَّر لهذا الصفّ.
  bool get isLinkedCopy => linked != null && !linked!.primary;
  final String? fullName;
  final String? phone;
  final bool isActive;

  /// Permission key → enabled bool. Default false when absent.
  final Map<String, bool> permissions;

  /// 2026-08-26: لو ≠ null، الموظّف مقيَّد بمدير فرعي محدَّد. يرى
  /// بيانات هذا المدير فقط (subscribers/managers/expenses/...).
  final String? scopeAdminId;
  final String? scopeAdminUsername;

  /// ٢٣ أكتوبر: موظّفٌ محذوف له حركات — يأتي مع `list(withDeleted: true)` وحده
  /// (فلاتر التقارير): حذفه يمسح صفّه وحركاته تبقى باسمه.
  final bool deleted;

  bool get isScoped => scopeAdminId != null && scopeAdminId!.isNotEmpty;

  /// Convenience for the list tile — drop unused / always-false. بلا «المساعد
  /// الذكي» ([ElEmployeePerms.assistantKey]): ليس عمليّة، والخادم يرسله `true`
  /// افتراضيّاً حتى والمساعد مطفأ (والمحرّر يخفيه) — كعدّ ايرث لنك نفسه.
  int get activePermsCount => permissions.entries.where((e) => e.value && e.key != ElEmployeePerms.assistantKey).length;

  static Employee? fromJson(Map<String, dynamic> j) {
    final id = int.tryParse(j['id']?.toString() ?? '') ?? 0;
    final username = (j['username'] ?? '').toString();
    if (id == 0 || username.isEmpty) return null;
    final rawPerms = j['permissions'];
    final m = <String, bool>{};
    if (rawPerms is Map) {
      rawPerms.forEach((k, v) => m[k.toString()] = v == true || v == 1);
    }
    return Employee(
      id: id,
      username: username,
      fullName: j['full_name']?.toString(),
      phone: j['phone']?.toString(),
      isActive: j['is_active'] == true || j['is_active'] == 1,
      permissions: m,
      scopeAdminId: j['scope_admin_id']?.toString(),
      scopeAdminUsername: j['scope_admin_username']?.toString(),
      deleted: j['deleted'] == true,
      linked: j['linked'] is Map ? EmployeeLink.fromJson(Map<String, dynamic>.from(j['linked'] as Map)) : null,
    );
  }
}

/// ٨ نوفمبر — «موظّفٌ بأكثر من صفحة» (الخادم `linked` في قائمة الموظّفين): اسم دخوله (صفّه الأصليّ)، وهل هذا الصفّ هو الأصليّ،
/// وعدد صفحاته.
class EmployeeLink {
  const EmployeeLink({required this.loginUsername, required this.primary, required this.pages});
  final String? loginUsername;
  final bool primary;
  final int pages;

  static EmployeeLink? fromJson(Map<String, dynamic> j) {
    final pages = int.tryParse(j['pages']?.toString() ?? '') ?? 1;
    final login = j['login_username']?.toString().trim();
    return EmployeeLink(
      loginUsername: login == null || login.isEmpty ? null : login,
      primary: j['primary'] == true,
      pages: pages < 1 ? 1 : pages,
    );
  }
}

/// ٨ نوفمبر — صفحةٌ من صفحات الموظّف (`pages` في `/api/v2/employees/me` وردّ الدخول): صفّه فيها، واسمها، وهل هي الحاليّة
/// أو الأصليّة (التي يدخل بها) أو معطَّلة.
class EmployeePageRef {
  const EmployeePageRef({
    required this.employeeId,
    required this.pageId,
    required this.pageName,
    this.sasCode,
    this.active = true,
    this.primary = false,
    this.current = false,
    this.loginUsername,
  });
  final int employeeId;
  final String pageId;
  final String pageName;
  final String? sasCode;
  final bool active;
  final bool primary;
  final bool current;

  /// اسم الدخول (صفّه الأصليّ) — يُحفظ مع جلسة التنقّل كما يُحفظ مع الدخول.
  final String? loginUsername;

  static EmployeePageRef? fromJson(Map<String, dynamic> j) {
    final id = int.tryParse(j['employee_id']?.toString() ?? '') ?? 0;
    final page = (j['page_id'] ?? '').toString().trim();
    if (id <= 0 || page.isEmpty) return null;
    final name = (j['page_name'] ?? '').toString().trim();
    final code = (j['sas_code'] ?? '').toString().trim();
    final login = (j['login_username'] ?? '').toString().trim();
    return EmployeePageRef(
      employeeId: id,
      pageId: page,
      pageName: name.isEmpty ? page : name,
      sasCode: code.isEmpty ? null : code,
      active: j['active'] != false,
      primary: j['primary'] == true,
      current: j['current'] == true,
      loginUsername: login.isEmpty ? null : login,
    );
  }

  Map<String, dynamic> toJson() => {
        'employee_id': employeeId,
        'page_id': pageId,
        'page_name': pageName,
        if (sasCode != null) 'sas_code': sasCode,
        'active': active,
        'primary': primary,
        'current': current,
        if (loginUsername != null) 'login_username': loginUsername,
      };

  /// صفحاتٌ من JSON (قائمة) — يُسقط التالف، وأقلّ من صفحتين ⇒ [] (موظّفٌ بصفحةٍ واحدة).
  static List<EmployeePageRef> listFrom(Object? raw) {
    if (raw is! List) return const [];
    final out = raw
        .whereType<Map>()
        .map((m) => EmployeePageRef.fromJson(Map<String, dynamic>.from(m)))
        .whereType<EmployeePageRef>()
        .toList();
    return out.length >= 2 ? List.unmodifiable(out) : const [];
  }
}

class PermissionDef {
  const PermissionDef({
    required this.key,
    required this.label,
    required this.category,
  });
  final String key;
  final String label;
  final String category;

  static PermissionDef? fromJson(String key, dynamic raw) {
    if (raw is! Map) return null;
    final label = raw['label']?.toString() ?? key;
    final category = raw['category']?.toString() ?? 'other';
    return PermissionDef(key: key, label: label, category: category);
  }
}

class PermCategory {
  const PermCategory({required this.key, required this.label});
  final String key;
  final String label;

  static PermCategory? fromJson(String key, dynamic raw) {
    if (raw is! Map) return null;
    final label = raw['label']?.toString() ?? key;
    return PermCategory(key: key, label: label);
  }
}

class PermPreset {
  const PermPreset({
    required this.key,
    required this.label,
    required this.description,
    required this.permissions,
  });
  final String key;
  final String label;
  final String description;
  final Map<String, bool> permissions;

  /// القالب فوق الصلاحيّات الحاليّة [current] (٩ نوفمبر — المنسّق بتفويض المالك): مفاتيحه كما هي، إلّا
  /// [ElEmployeePerms.roleFreeKeys] (الفحصان على الشبكة وما عبر VPN والتنبيهات) فتبقى على قيمتها في [current] — تُمنح فرادى، وقوالب
  /// الخادم (كاشير/مساعد مدير/مشاهد) لا تحملها فكانت تُطفئ الفحصين المفعّلين افتراضاً. والغائب عن [current] يبقى غائباً (الخادم
  /// يُبقيه على المحفوظ/الافتراضيّ).
  Map<String, bool> applyTo(Map<String, bool> current) {
    final out = Map<String, bool>.from(permissions);
    for (final k in ElEmployeePerms.roleFreeKeys) {
      final v = current[k];
      if (v == null) {
        out.remove(k);
      } else {
        out[k] = v;
      }
    }
    return out;
  }

  static PermPreset? fromJson(String key, dynamic raw) {
    if (raw is! Map) return null;
    final perms = <String, bool>{};
    final p = raw['permissions'];
    if (p is Map) {
      p.forEach((k, v) => perms[k.toString()] = v == true);
    }
    return PermPreset(
      key: key,
      label: raw['label']?.toString() ?? key,
      description: raw['description']?.toString() ?? '',
      permissions: perms,
    );
  }
}

/// Catalog returned by /api/v2/employees/permissions-catalog. The
/// editor uses it to render the categorized permissions grid + the
/// preset chips at the top of the perms tab.
class PermissionsCatalog {
  const PermissionsCatalog({
    required this.permissions,
    required this.categories,
    required this.permsByCategory,
    required this.defaults,
    required this.presets,
  });
  final Map<String, PermissionDef> permissions;
  final Map<String, PermCategory> categories;
  final Map<String, List<PermissionDef>> permsByCategory;
  final Map<String, bool> defaults;
  final Map<String, PermPreset> presets;

  static PermissionsCatalog fromJson(Map<String, dynamic> j) {
    final permsRaw = j['permissions'];
    final perms = <String, PermissionDef>{};
    if (permsRaw is Map) {
      permsRaw.forEach((k, v) {
        final d = PermissionDef.fromJson(k.toString(), v);
        if (d != null) perms[d.key] = d;
      });
    }
    final catsRaw = j['categories'];
    final cats = <String, PermCategory>{};
    if (catsRaw is Map) {
      catsRaw.forEach((k, v) {
        final c = PermCategory.fromJson(k.toString(), v);
        if (c != null) cats[c.key] = c;
      });
    }
    final byCat = <String, List<PermissionDef>>{};
    for (final p in perms.values) {
      byCat.putIfAbsent(p.category, () => []).add(p);
    }
    final defaultsRaw = j['defaults'];
    final defaults = <String, bool>{};
    if (defaultsRaw is Map) {
      defaultsRaw.forEach((k, v) => defaults[k.toString()] = v == true);
    }
    final presetsRaw = j['presets'];
    final presets = <String, PermPreset>{};
    if (presetsRaw is Map) {
      presetsRaw.forEach((k, v) {
        final p = PermPreset.fromJson(k.toString(), v);
        if (p != null) presets[p.key] = p;
      });
    }
    return PermissionsCatalog(
      permissions: perms,
      categories: cats,
      permsByCategory: byCat,
      defaults: defaults,
      presets: presets,
    );
  }

  /// الكتالوج بلا [keys] (المحرّر لا يعرضها ولا يرسلها، فيُبقي الخادم قيمتها
  /// المحفوظة — `employees.sanitizePermissions`). للمساعد الذكيّ: مفتاحه لا
  /// يظهر قبل أن يقول الخادم إنّ المساعد مفعّل ([ElEmployeePerms.assistantKey]).
  PermissionsCatalog without(Set<String> keys) {
    if (!keys.any(permissions.containsKey) && !keys.any(defaults.containsKey)) {
      return this;
    }
    bool keep(String k) => !keys.contains(k);
    return PermissionsCatalog(
      permissions: {
        for (final e in permissions.entries)
          if (keep(e.key)) e.key: e.value,
      },
      categories: categories,
      permsByCategory: permsByCategoryWhere(keep),
      defaults: {
        for (final e in defaults.entries)
          if (keep(e.key)) e.key: e.value,
      },
      presets: {
        for (final e in presets.entries)
          e.key: PermPreset(
            key: e.value.key,
            label: e.value.label,
            description: e.value.description,
            permissions: {
              for (final p in e.value.permissions.entries)
                if (keep(p.key)) p.key: p.value,
            },
          ),
      },
    );
  }

  /// [permsByCategory] مقصوراً على المفاتيح التي يقبلها [keep] — الفئات
  /// بترتيبها في الكتالوج، والفئة التي لا يبقى فيها شيءٌ تسقط.
  Map<String, List<PermissionDef>> permsByCategoryWhere(bool Function(String key) keep) {
    final out = <String, List<PermissionDef>>{};
    permsByCategory.forEach((cat, defs) {
      final kept = defs.where((d) => keep(d.key)).toList();
      if (kept.isNotEmpty) out[cat] = kept;
    });
    return out;
  }
}

/// دورٌ جاهز لموظّف ايرث لنك — يضبط المفاتيح كلّها دفعةً ثمّ يعدّل المالك.
class ElPermPreset {
  const ElPermPreset({
    required this.id,
    required this.label,
    required this.description,
    required this.keys,
  });

  /// معرّفٌ ثابت للواجهة (الأيقونة) — لا يُرسَل للخادم.
  final String id;
  final String label;
  final String description;

  /// المفاتيح المفعّلة؛ ما سواها من مفاتيح ايرث لنك يُطفأ.
  final Set<String> keys;
}

/// صلاحيّات موظّف ايرث لنك (Pro البند ٤).
///
/// الخادم يفرض على موظّفي EarthLink هذه المفاتيح **بالضبط** (جدول
/// `routePermission` في `server/earthlink/earthlinkRoutes.js`، والأجهزة
/// بمعالجاتها العامّة كباقي المزوّدين). ما سواها من الكتالوج إمّا ميزةٌ لا
/// وجود لها هناك (المدراء الفرعيّون، الإعدادات، البثّ…) وإمّا لصاحب الحساب
/// وحده بلا مفتاح (تحويل الرصيد وكشف الإيداع، إلغاء التسوية) — والموظّف لا
/// يدير موظّفين أبداً.
///
/// فمحرّر موظّفي ايرث لنك يعرض هذه وحدها، و[outgoing] لا يُرسل غيرها: الخادم
/// يكتب الغائب `false` (لا يمنح المحرّر ما لا يراه المالك)، إلّا مفاتيح
/// `KEEP_WHEN_MISSING` عنده فتبقى على المحفوظ أو الافتراضيّ (٩ نوفمبر — كانت
/// تُرسل `false` فيُسحب «الفحص الشامل» والرادار المفعّلان افتراضاً بصمت).
class ElEmployeePerms {
  ElEmployeePerms._();

  /// مفاتيح موظّف الشركة المفتوحة: فايبر اكس ([fiberxKeys]، ٣١ أكتوبر) أو ايرث لنك ([earthlinkKeys]).
  static Set<String> get keys => ProviderService.isFiberx
      ? fiberxKeys
      : ProviderService.isKit
          ? _kitKeysForSession()
          : earthlinkKeys;

  /// مفاتيح الشركة المُضافة كما تُعرض الآن: لصاحب الحساب ما يخدمه حسابه وحده (قدرته من الخادم ليست false — AccessGate بلا حساباتٍ
  /// فرعيّة فلا «المدراء»، وتفعيلٌ مطفأ لا يُمنح)، ولموظّفها مفاتيحها كلّها (الخادم أصلاً يعرض ما مُنح ∩ ما يخدمه حساب أبيه).
  /// والمشروع الوطنيّ يزيد [nationalExtraKeys] بلا تصفيةٍ بقدرات صاحبه (لا تخصّ الساس — أقسام بوّابته).
  static Set<String> _kitKeysForSession() {
    final base = PermissionsService.isEmployee ? kitKeys : kitKeys.where(Perms.has).toSet();
    // «التذاكر» لكلّ الشركات ما عدا الوطنيّ (المالك ٩ نوفمبر) — مفتاحاها لا يُعرضان لموظّفه
    return isNationalSession ? {...base, ...nationalExtraKeys}.difference(ticketKeys) : base;
  }

  /// «التذاكر» (٩ نوفمبر، الخادم server/tickets.js): العرض والإشعار، والردّ والحالة والإغلاق — مطفأان افتراضاً، ويُمنحان فرادى
  /// (خارج «موظّف عام»). لموظّفي ايرث لنك وفايبر اكس والشركات المُضافة كموظّفي الساس، ما عدا المشروع الوطنيّ.
  static const ticketKeys = <String>{'tickets.view', 'tickets.reply'};

  /// الفحصان على شبكة الوكيل (٨ نوفمبر — المالك: «الافتراضي يكون لديه صلاحيه على شبكه فقط»): «الفحص الشامل» للأجهزة والرادار
  /// («الفحص العامّ») للمشتركين — مفعّلان افتراضاً (`PermissionsService.deepCheckNet`/`subsCheckNet`)، فيُعرضان لكلّ شركة (٩ نوفمبر:
  /// كانا خارج المحرّر فيُرسلان false ويختفي الفحصان عن موظّفيها).
  static const checkKeys = <String>{'devices.deep_check', 'subscribers.check'};

  /// ما عبر VPN (٨ نوفمبر — مطفأةٌ افتراضاً، يفرضها الخادم `connVpn/agentRoutes`): الفحص الشامل والفحص العامّ عبر VPN، و«ربط VPN».
  /// ايرث لنك والشركات المُضافة وحدهما (بوّابتاهما تمرّران `conn-vpn`؛ فايبر اكس لا).
  static const vpnKeys = <String>{'devices.deep_check_vpn', 'subscribers.vpn_check', 'conn_vpn.link'};

  /// «تنبيهات المشتركين» و«تنبيهات الوكيل» (٤ نوفمبر) — القسم والإشعار، مطفأةٌ افتراضاً؛ ايرث لنك والشركات المُضافة وحدهما
  /// (بوّابتاهما تمرّران `connection-alerts` و`agent-alerts` منذ ٦ نوفمبر؛ فايبر اكس لا).
  static const alertKeys = <String>{'conn_alerts.use', 'conn_alerts.notify', 'agent_alerts.use', 'agent_alerts.notify'};

  /// خارج الأدوار الجاهزة: الدور لا يلمسها ([presets] · `_applyElPreset`) ولا تُحسب في مطابقته ([matching]) — تُمنح فرادى.
  static const roleFreeKeys = <String>{...checkKeys, ...vpnKeys, ...alertKeys};

  /// ما يُجري عمليّةً من [roleFreeKeys] (لا فحصاً ولا عرضاً ولا إشعاراً) بالاسم الذي يُقال للمالك: «ربط VPN»، وقسم «تنبيهات المشتركين»
  /// بموافقته وإرساله. الدور لا يلمسها، فإن بقيت ممنوحةً سمّاها سطر الدور ([captionFor]).
  static const roleFreeOperations = <String, String>{
    'conn_vpn.link': 'ربط VPN',
    'conn_alerts.use': 'تنبيهات المشتركين (الموافقة والإرسال)',
  };

  /// سطر الوصف تحت الأدوار للدور المطابق [p] (مراجعة 3.0.18): «عرض فقط» بلا أيّ عمليّة — إلّا ما منحه المالك فرادى من
  /// [roleFreeOperations] وبقي (الدور لا يلمسه، 00b20601) فيُسمّى؛ كان يُقال «بلا أيّ عمليّة» والموظّف يربط VPN ويوافق ويرسل التنبيهات.
  /// [catalogKeys] كـ[matching]: ما لا يعرضه الكتالوج لا يُذكر.
  static String captionFor(ElPermPreset p, Map<String, bool> perms, {Iterable<String>? catalogKeys}) {
    if (p.id != 'view') return p.description;
    final shown = offered(catalogKeys);
    final kept = [
      for (final e in roleFreeOperations.entries)
        if (shown.contains(e.key) && perms[e.key] == true) e.value,
    ];
    return kept.isEmpty ? p.description : '${p.description} — عدا ما منحته فرادى: ${kept.join(' · ')}';
  }

  /// جلسة المشروع الوطنيّ (شركةٌ مُضافة أبو مشتركها الزون — watani).
  static bool get isNationalSession => ProviderService.isKit && ProviderService.parentIsZone;

  /// مفاتيح أقسام بوّابة المشروع الوطنيّ (١ نوفمبر — القرار ٢؛ العقد §9، `providerKit/employeeRoutes`): «الجلسات» و«تقرير الجلسات»
  /// (`reports.sessions`)، وجرس البوّابة — إشعاراتها وإعلاناتها (`notifications.view`)، والتعليق على المهامّ والطلبات
  /// (`subscribers.edit`). قدرات صاحب الحساب من الخادم تُبقي الأوّل والأخير false (لا تقرير جلسات الساس العامّ، ولا «تعديل» المشترك
  /// عند الوطنيّ) — فلا تُصفّى بها: يمنحها المالك لموظّفه لأقسام البوّابة وحدها، و[outgoing] يحفظ قيمها (كانت تُرسل false بصمت
  /// فيُسحب «عرض التبليغات» الممنوح من الويب بأيّ تعديلٍ من التطبيق). ومطابقٌ للويب (WATANI_EXTRA_KEYS).
  static const nationalExtraKeys = <String>{'reports.sessions', 'notifications.view', 'subscribers.edit', 'subscribers.add'};

  /// موظّفونا لحساب شركةٍ مُضافة (providerKit — نبض، AccessGate…، ٣٠ أكتوبر؛ الخادم 03cc682 providerKit/employeeRoutes): المشتركون
  /// كاملاً، والحسابات الفرعيّة عند الشركة ومالها، والأسعار والتقارير والتسويات والمبيعات وديون المحذوفين والأجهزة والمساعد. لا موقع
  /// ولا جلسات ولا ديون مدراء (لا تخدمها). وما لا يخدمه محوّل الشركة لحسابٍ بعينه يعرضه الخادم false. مطابقٌ للويب (KIT_EMPLOYEE_KEYS).
  static const kitKeys = <String>{
    // «ملاحظة خاصّة» (٣١ أكتوبر): جدولنا وحده، ومسارها ممرَّرٌ لكلّ مزوّد — يفحصها معالجه العامّ.
    'subscribers.private_note',
    'subscribers.view',
    'subscribers.add',
    'subscribers.activate',
    'subscribers.extend',
    'subscribers.toggle',
    'subscribers.edit',
    'subscribers.delete',
    'subscribers.view_credentials',
    'subscribers.add_debt',
    'subscribers.pay_debt',
    voidPaymentKey,
    'subscribers.add_credit',
    'subscribers.send_whatsapp',
    'subscribers.view_activity',
    'managers.view',
    'managers.add',
    'managers.edit',
    'managers.delete',
    'managers.deposit',
    'managers.withdraw',
    'managers.add_points',
    'packages.view',
    'packages.edit_prices',
    'discounts.view',
    'discounts.manage',
    'subscriber_prices.view',
    'subscriber_prices.manage',
    'reports.financial',
    'reports.packages',
    'reports.activations',
    'reports.daily_activations',
    'reports.expenses',
    'reports.account_statement',
    'reports.activity_log',
    'settlements.view',
    'settlements.create',
    'deleted_debts.view',
    'deleted_debts.add',
    'deleted_debts.pay',
    'deleted_debts.write_off',
    'sales.view',
    'sales.sell',
    'sales.items',
    'sales.void',
    'devices.view',
    'devices.monitor',
    'devices.manage',
    'assistant.use',
    ...ticketKeys,
    ...checkKeys,
    ...vpnKeys,
    ...alertKeys,
  };

  /// موظّفونا لحساب فايبر اكس (٣١ أكتوبر — المالك: «فايبر اكس خلي موظفينا فقط… احنه اصلا موفرين هلمزية»): ما يفرضه
  /// الخادم على مسارات فايبر اكس (fiberxRoutes.routePermission) ومعالجات التمرير. لا إضافة/تعديل/إيقاف مشترك، ولا كلمة
  /// سرّه أو موقعه، ولا الجلسات — فايبر اكس لا يخدمها. مطابقٌ للويب (FX_EMPLOYEE_KEYS).
  static const fiberxKeys = <String>{
    // «ملاحظة خاصّة» (٣١ أكتوبر): جدولنا وحده، ومسارها ممرَّرٌ لكلّ مزوّد — يفحصها معالجه العامّ.
    'subscribers.private_note',
    'subscribers.view',
    'subscribers.activate',
    'subscribers.extend',
    'subscribers.add_debt',
    'subscribers.pay_debt',
    voidPaymentKey,
    'subscribers.send_whatsapp',
    'subscribers.view_activity',
    'packages.view',
    'packages.edit_prices',
    'discounts.view',
    'discounts.manage',
    'subscriber_prices.view',
    'subscriber_prices.manage',
    'reports.financial',
    'reports.packages',
    'reports.activations',
    'reports.daily_activations',
    'reports.expenses',
    'reports.account_statement',
    'reports.activity_log',
    'settlements.view',
    'settlements.create',
    'deleted_debts.view',
    'deleted_debts.add',
    'deleted_debts.pay',
    'deleted_debts.write_off',
    'sales.view',
    'sales.sell',
    'sales.items',
    'sales.void',
    'devices.view',
    'devices.monitor',
    'devices.manage',
    assistantKey,
    ...ticketKeys,
    // الفحصان على الشبكة وحدهما — بوّابة فايبر اكس لا تمرّر ما عبر VPN ولا التنبيهات
    ...checkKeys,
  };

  /// ما يختلف معناه لموظّف فايبر اكس عن ايرث لنك.
  static const _fiberxHints = <String, String>{
    'reports.financial': 'يشمل رصيد المحفظة وحركاتها',
    'subscribers.extend': '«التمديد» في فايبر اكس رسالةٌ منهم للمشترك ليمدّد من تطبيقهم — لا مال',
    'subscribers.activate': 'التفعيل من محفظة الوكيل — ويعمل حين يكون التفعيل مفتوحاً لحسابك',
  };

  /// توضيح المفتاح للشركة المفتوحة.
  static const _kitHints = <String, String>{
    'subscribers.add': 'مشتركٌ جديد عند الشركة بحسابك فيها',
    'reports.financial': 'يشمل رصيد حسابك عند الشركة',
    'subscribers.activate': 'التفعيل من رصيدك عند الشركة — ويعمل حين يكون التفعيل مفتوحاً لحسابك',
    'managers.view': 'الحسابات الفرعيّة عند الشركة (المدراء) وأرصدتها',
  };

  /// مفاتيح أقسام بوّابة المشروع الوطنيّ ([nationalExtraKeys]) — لا جلسات الساس ولا تبليغات الواتساب ولا تعديل المشترك (نصّ الويب).
  static const _nationalHints = <String, String>{
    'reports.sessions': 'جلسات المشتركين و«تقرير الجلسات» في بوّابة المشروع الوطني',
    'notifications.view': 'إشعارات بوّابة المشروع الوطني وإعلاناتها — للقراءة',
    'subscribers.edit': 'التعليق على المهامّ والطلبات في بوّابة المشروع الوطني',
    // ٣ نوفمبر (المالك: «ضيفهن بصلاحيه الهم»)
    'subscribers.add': '«إضافة مشترك» للمشروع الوطني — البطاقة الموحّدة وصورها ورمز الزبون',
    'subscribers.add_credit': 'إضافة رصيد، و«تعبئة محفظة المشترك» (من محفظة الحساب أو بكارت)',
  };

  static String? hintFor(String key) =>
      (ProviderService.isFiberx
          ? _fiberxHints[key]
          : ProviderService.isKit
              ? (isNationalSession ? _nationalHints[key] : null) ?? _kitHints[key]
              : null) ??
      hints[key];

  static const earthlinkKeys = <String>{
    'subscribers.private_note', // «ملاحظة خاصّة» (٣١ أكتوبر)
    ..._operations,
    // استيراد/تصدير الديون للمدير وحده — لا يُمنح لموظّف (قرار المالك ٢١ أكتوبر؛
    // الخادم يردّ OWNER_ONLY ولا مفتاح له في الكتالوج).
    // أجهزة الشبكة (OLT/مايكروتك…) — أجهزة الموزّع نفسه، لا علاقة لها بالمزوّد.
    'devices.view',
    'devices.monitor',
    'devices.manage',
    // شطب دين مشتركٍ محذوف — يُسقطه بلا تحصيل، فيُمنح وحده (خارج «موظّف عام»).
    'deleted_debts.write_off',
    // إلغاء بيعٍ نقديّ — يُرجع مالاً من الصندوق، فيُمنح وحده (خارج «موظّف عام»).
    'sales.void',
    // «إلغاء تسديد» (١١ نوفمبر) — يُرجع دين المشترك ويُخرج مبلغه من الصندوق، فيُمنح وحده (خارج «موظّف عام»).
    voidPaymentKey,
    // «التذاكر» (٩ نوفمبر) — تُمنح وحدها (خارج «موظّف عام»).
    ...ticketKeys,
    // الفحصان (مفعّلان افتراضاً) وما عبر VPN والتنبيهات (٩ نوفمبر) — خارج الأدوار الجاهزة ([roleFreeKeys]).
    ...checkKeys,
    ...vpnKeys,
    ...alertKeys,
  };

  /// المفاتيح بلا الأجهزة — «موظّف عام» يأخذها كلّها (الأجهزة تُمنح فرادى كما في
  /// قوالب الخادم لموظّفي ساس4: إدارتها تكشف بيانات دخول الأجهزة وتعيد تشغيلها).
  static const _operations = <String>{
    'subscribers.view',
    // إضافة مشترك (رصيد/كارت/تجريبي) — يحرس مسارات الإضافة الأربعة عند الخادم.
    'subscribers.add',
    'subscribers.activate',
    'subscribers.extend',
    'subscribers.toggle',
    'subscribers.edit',
    'subscribers.view_credentials',
    'subscribers.add_debt',
    'subscribers.pay_debt',
    'subscribers.send_whatsapp',
    'subscribers.view_activity',
    // موقع المشترك (GPS) — مخزنه لايرث لنك جدولٌ محلّيّ على خادمنا (١٨ أكتوبر).
    'subscribers.edit_location',
    'packages.view',
    'packages.edit_prices',
    'discounts.view',
    'discounts.manage',
    'subscriber_prices.view',
    'subscriber_prices.manage',
    'reports.financial',
    // «توزيع الباقات» (٢٥ أكتوبر) — بطاقة الرئيسيّة وتقريرها، بمفتاحه في جدول موظّفي ايرث لنك.
    'reports.packages',
    'reports.activations',
    'reports.daily_activations',
    'reports.expenses',
    'reports.account_statement',
    'reports.sessions',
    'reports.activity_log',
    'settlements.view',
    'settlements.create',
    // ديون المشتركين المحذوفين (٢٣ أكتوبر) — اليدويّ والمستورد لايرث لنك
    // (elPassthrough). الكتالوج لا يعرضها حتى تُفتح الميزة للكلّ، فالأدوار
    // تُطابَق على ما يعرضه وحده ([matching] · [offered]).
    'deleted_debts.view',
    'deleted_debts.add',
    'deleted_debts.pay',
    // المبيعات (٢٣ أكتوبر) — مسارات قاعدتنا لايرث لنك (elPassthrough): العرض والبيع
    // والموادّ. الكتالوج لا يعرضها حتى تُفتح للكلّ ([matching] · [offered]).
    'sales.view',
    'sales.sell',
    'sales.items',
    assistantKey,
  };

  /// المساعد الذكيّ («اشرحلي» و«كيف أسوّي؟») — أجوبةٌ بلا أيّ عمليّة، من حصّة
  /// صاحب الحساب اليوميّة. مفتوحٌ افتراضيّاً عند الخادم، فيحمله كلّ دورٍ جاهز
  /// (تطبيق «عرض فقط» لا يطفئه)، ولا يُعدّ في عدد الصلاحيّات ولا في مطابقة
  /// الدور ([activeCount] · [matching]): ليس عمليّةً، وخادمٌ أقدم بلا المفتاح
  /// لا يجعل كلّ موظّفٍ «مخصّصاً». وفي القائمة نفسها ليُرسَل كما اختاره المالك
  /// — ما خارجها يُرسَل `false` فيُطفئ المساعد عن الموظّف بصمت ([outgoing]).
  static const assistantKey = 'assistant.use';

  /// «إلغاء تسديد دين» (١١ نوفمبر — المالك: «أعطيها صلاحيّة للمدير يخصّصها للموظّف أو لا»؛ الخادم `server/paymentVoids.js`):
  /// الموظّف يلغي تسديداً سجّله هو فقط. مطفأٌ افتراضاً عند الخادم وخارج كلّ دورٍ جاهز ([presets])، وكتالوجه لا يعرضه حتى تُفتح
  /// الميزة للحساب ([offered]). وفي قوائم الشركات الثلاث ليُرسَل كما اختاره المالك — ما خارجها لا يُرسل، والخادم يُبقيه على المحفوظ.
  static const voidPaymentKey = 'subscribers.void_payment';

  /// ما يشمله المفتاح عند ايرث لنك ولا تقوله تسميته في الكتالوج.
  static const hints = <String, String>{
    voidPaymentKey: 'تسديدٌ سجّله هو فقط — يرجع دين المشترك وينقص المبلغ من الصندوق',
    'subscribers.add': 'بالرصيد (بباسورد الإيداع — يُخصم من رصيد الوكيل) أو بكارت أو تجريبي',
    'subscribers.toggle': 'يشمل قطع اتصال المشترك',
    'reports.financial': 'يشمل رصيد الوكيل والكارتات المطلوبة',
    'reports.packages': 'المشتركون والتفعيلات والإيراد لكلّ باقة — الكلفة والربح لصاحب الحساب وحده',
    'reports.expenses': 'عرض الصرفيات وإدارتها',
    'subscribers.edit_location': 'موقع المشترك على الخريطة',
    // بيانات دخول أجهزة المشتركين (الافتراضيّة وجهاز كلّ مشترك) تصل بالعرض
    // والمراقبة أيضاً — يحتاجها فحص الجهاز (`device_probe_api`). تُقال صراحةً
    // فلا يمنح المالك «العرض» ظنّاً أنّه لا يكشف كلمة سرّ (كـ`EL_KEY_HINTS` في
    // الويب، تدقيق ١٨ أكتوبر).
    'devices.view': 'أجهزة شبكتك (OLT/مايكروتك…) — ويشمل بيانات دخول أجهزة المشتركين (الراوترات) لفحصها',
    'devices.monitor': 'يشمل بيانات دخول أجهزة المشتركين (الراوترات) لفحصها',
    'devices.manage': 'تعديل الأجهزة وإعادة تشغيلها وبيانات دخول أجهزة الشبكة',
    'deleted_debts.pay': 'يدخل التقرير الماليّ محصَّلاً',
    'deleted_debts.write_off': 'يُسقط الدين بلا تحصيل',
    'sales.sell': 'البيع على دين المشترك يحتاج «إضافة دين» أيضاً',
    'sales.void': 'إلغاء بيعٍ نقديّ يُرجع مبلغه من الصندوق',
    assistantKey: 'يشرح الأخطاء ويجاوب «كيف أسوّي؟» — بلا أيّ عمليّة، ومن حصّة حسابك اليوميّة',
  };

  /// «موظّف عام» = مفاتيح العمليّات كلّها، ومنها `subscribers.add` (يحوي أصلاً ما
  /// يحرّك المال: تفعيل/تمديد/دين/تسوية). «تفعيل وتحصيل» بلا إضافة — كقالب
  /// «كاشير» في كتالوج الخادم — و«عرض فقط» بلا أيّ عمليّة.
  static const presets = <ElPermPreset>[
    ElPermPreset(
      id: 'general',
      label: 'موظّف عام',
      description: 'يرى ويعمل كلّ ما يُسمح به لموظّف',
      keys: _operations,
    ),
    ElPermPreset(
      id: 'collect',
      label: 'تفعيل وتحصيل',
      description: 'تفعيل وتمديد وتسديد ديون وواتساب',
      keys: {
        'subscribers.view',
        'subscribers.activate',
        'subscribers.extend',
        'subscribers.pay_debt',
        'subscribers.send_whatsapp',
        'packages.view',
        'subscribers.view_activity',
        // كقالب «كاشير» بالخادم: يبيع ولا يدير الموادّ.
        'sales.view',
        'sales.sell',
        assistantKey,
      },
    ),
    ElPermPreset(
      id: 'view',
      label: 'عرض فقط',
      description: 'يشاهد المشتركين والباقات والخصومات والأسعار بلا أيّ عمليّة',
      keys: {
        'subscribers.view',
        'packages.view',
        'discounts.view',
        'subscriber_prices.view',
        'subscribers.view_activity',
        'sales.view',
        assistantKey,
      },
    ),
  ];

  /// عدد مفاتيح ايرث لنك المفعّلة — ما يملكه الموظّف فعلاً (بلا المساعد:
  /// ليس عمليّة — [assistantKey]).
  static int activeCount(Map<String, bool> perms) => keys.where((k) => k != assistantKey && perms[k] == true).length;

  /// ما يُرسَل للخادم: مفاتيح الكتالوج التي يعرضها المحرّر ([keys]) بقيمها من [perms] — **وحدها**. ما لا يعرضه لا يُرسل
  /// (٩ نوفمبر): الخادم يكتب الغائب `false` فلا يُمنح ما لا يراه المالك، ومفاتيح `KEEP_WHEN_MISSING` عنده (الفحصان المفعّلان
  /// افتراضاً، التنبيهات، طلبات التفعيل…) تبقى على المحفوظ أو الافتراضيّ — كان يُرسلها `false` فيُطفئها بصمت. والطلب يحمل
  /// `perms_shown_only` ([EmployeesApi.create]/[EmployeesApi.update]) فيثق الخادم بقيم الفحصين المعروضين.
  /// الاستثناء `whatsapp.send`: يتبع «إرسال واتساب» (`subscribers.send_whatsapp`) — مسارا تذكير الدين/معلومات المشترك يرسلان
  /// عبر `/api/whatsapp/send-message` بتوكن الموظّف، وهو يفحص `whatsapp.send`، فبدونه يُرفض موظّفٌ مُنح المراسلة (كـbuildElPermissions
  /// في الويب).
  static Map<String, bool> outgoing(Iterable<String> catalogKeys, Map<String, bool> perms) {
    final shown = keys;
    var hasWhatsappSend = false;
    final out = <String, bool>{};
    for (final k in catalogKeys) {
      if (k == 'whatsapp.send') hasWhatsappSend = true;
      if (shown.contains(k)) out[k] = perms[k] == true;
    }
    if (hasWhatsappSend) out['whatsapp.send'] = perms['subscribers.send_whatsapp'] == true;
    return out;
  }

  /// الدور الجاهز المطابق للمفعَّل الآن تماماً، وإلّا null (مخصّص).
  /// [catalogKeys]: ما يعرضه كتالوج الخادم — مفتاحٌ لا يعرضه (ميزةٌ لم تُفتح
  /// للحساب) لا يُحسب من الدور، فلا يصير «موظّف عام» القديم «مخصّصاً».
  /// ولا [roleFreeKeys] (الفحصان وما عبر VPN والتنبيهات): تُمنح فرادى، فالفحص المفعّل افتراضاً لا يجعل الدور «مخصّصاً».
  static ElPermPreset? matching(Map<String, bool> perms, {Iterable<String>? catalogKeys}) {
    final avail = offered(catalogKeys).difference(roleFreeKeys);
    final on = {
      for (final k in avail)
        if (k != assistantKey && perms[k] == true) k,
    };
    for (final p in presets) {
      final want = p.keys.where((k) => k != assistantKey && avail.contains(k)).toSet();
      if (want.length == on.length && on.containsAll(want)) return p;
    }
    return null;
  }

  /// مفاتيح ايرث لنك التي يعرضها الكتالوج (null = كلّها).
  static Set<String> offered(Iterable<String>? catalogKeys) {
    if (catalogKeys == null) return keys;
    final c = catalogKeys.toSet();
    return keys.where(c.contains).toSet();
  }
}

/// Identity returned by /api/v2/employees/me. Used at login time to
/// decide gating (sidebar, action visibility) for employee accounts.
class CurrentIdentity {
  const CurrentIdentity({
    required this.isEmployee,
    this.adminId,
    this.adminUsername,
    this.employeeId,
    this.employeeUsername,
    this.permissions,
    this.pages = const [],
  });
  final bool isEmployee;

  /// ٨ نوفمبر — «موظّفٌ بأكثر من صفحة»: صفحاته (صفحتان فأكثر)، وإلّا [].
  final List<EmployeePageRef> pages;
  final String? adminId;
  final String? adminUsername;
  final int? employeeId;
  final String? employeeUsername;

  /// Null when the actor is the admin itself (full access).
  final Map<String, bool>? permissions;

  static CurrentIdentity? fromJson(Map<String, dynamic> j) {
    final perms = j['permissions'];
    final m = perms is Map
        ? <String, bool>{
            for (final e in perms.entries) e.key.toString(): e.value == true,
          }
        : null;
    return CurrentIdentity(
      isEmployee: j['is_employee'] == true,
      adminId: j['admin_id']?.toString(),
      adminUsername: j['admin_username']?.toString(),
      employeeId: j['employee_id'] is int ? j['employee_id'] as int : int.tryParse(j['employee_id']?.toString() ?? ''),
      employeeUsername: j['employee_username']?.toString(),
      permissions: m,
      pages: EmployeePageRef.listFrom(j['pages']),
    );
  }
}

class EmployeesApi {
  EmployeesApi._();

  /// [withDeleted]: فلاتر التقارير — يُلحق الخادم المحذوفين الذين لهم حركات بعد
  /// الحاليّين (`deleted`). شاشة الموظّفين بلاه.
  static Future<({List<Employee> rows, String? error})> list({bool withDeleted = false}) async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>(
        '/api/v2/employees',
        queryParameters: withDeleted ? const {'with_deleted': 1} : null,
      );
      final body = r.data ?? const {};
      if (body['success'] != true) {
        return (rows: const <Employee>[], error: body['message']?.toString());
      }
      final list = body['data'];
      if (list is! List) return (rows: const <Employee>[], error: null);
      return (
        rows: list
            .whereType<Map>()
            .map((m) => Employee.fromJson(Map<String, dynamic>.from(m)))
            .whereType<Employee>()
            .toList(),
        error: null,
      );
    } on DioException catch (e) {
      _log('employees (GET)', e);
      return (rows: const <Employee>[], error: 'فشل التحميل');
    } catch (e) {
      _log('employees (GET)', e);
      return (rows: const <Employee>[], error: 'فشل التحميل');
    }
  }

  static Future<PermissionsCatalog?> catalog() async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>(
        '/api/v2/employees/permissions-catalog',
      );
      final body = r.data ?? const {};
      if (body['success'] != true) return null;
      final data = body['data'];
      if (data is! Map) return null;
      return PermissionsCatalog.fromJson(Map<String, dynamic>.from(data));
    } catch (e) {
      _log('employees catalog', e);
      return null;
    }
  }

  static Future<CurrentIdentity?> me() async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>('/api/v2/employees/me');
      final body = r.data ?? const {};
      if (body['success'] != true) return null;
      final data = body['data'];
      if (data is! Map) return null;
      return CurrentIdentity.fromJson(Map<String, dynamic>.from(data));
    } catch (e) {
      _log('employees me', e);
      return null;
    }
  }

  /// [status] رمز HTTP الردّ — `409` = اسم المستخدم محجوز (الأسماء فريدةٌ
  /// على مستوى النظام كلّه، لا عند المدير وحده).
  static Future<({bool ok, String? message, Employee? employee, int? status})> create({
    required String username,
    required String password,
    String? fullName,
    String? phone,
    bool isActive = true,
    required Map<String, bool> permissions,

    /// 2026-08-26: يقيّد الموظّف بمدير فرعي (يشوف بياناته فقط).
    /// null = يشاهد بيانات الأب كاملة.
    String? scopeAdminId,

    /// محرّر ايرث لنك/فايبر اكس/الشركات المُضافة ([ElEmployeePerms.outgoing]، ٩ نوفمبر): [permissions] ما عرضه المحرّر وحده —
    /// فيثق الخادم بقيم الفحصين فيه (محرّرٌ أقدم بلا العلامة يُرسل `false` لما لم يعرضه فيعدّه الخادم غائباً).
    bool permsShownOnly = false,
  }) async {
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>(
        '/api/v2/employees',
        data: {
          'username': username,
          'password': password,
          if (fullName != null) 'full_name': fullName,
          if (phone != null) 'phone': phone,
          'is_active': isActive,
          'permissions': permissions,
          if (permsShownOnly) 'perms_shown_only': true,
          if (scopeAdminId != null && scopeAdminId.isNotEmpty) 'scope_admin_id': scopeAdminId,
        },
      );
      final body = r.data ?? const {};
      Employee? emp;
      final data = body['data'];
      if (data is Map) {
        emp = Employee.fromJson(Map<String, dynamic>.from(data));
      }
      return (
        ok: body['success'] == true,
        message: body['message']?.toString(),
        employee: emp,
        status: r.statusCode,
      );
    } on DioException catch (e) {
      _log('employees (POST)', e);
      final body = e.response?.data;
      final msg = body is Map ? body['message']?.toString() : null;
      return (
        ok: false,
        message: msg ?? 'تعذّر الإنشاء',
        employee: null,
        status: e.response?.statusCode,
      );
    } catch (e) {
      _log('employees (POST)', e);
      return (ok: false, message: 'تعذّر الإنشاء', employee: null, status: null);
    }
  }

  static Future<({bool ok, String? message})> update({
    required int id,
    String? fullName,
    String? phone,
    String? password,
    bool? isActive,
    Map<String, bool>? permissions,

    /// 2026-08-26: scope الحقل الثلاثيّ:
    ///   - null (parameter): لا تغيير (default)
    ///   - '' (empty string): مسح القيد → يشاهد كل شجرة الأب
    ///   - non-empty: يقيّد بمدير فرعي محدَّد
    String? scopeAdminId,

    /// كـ[create]: [permissions] ما عرضه محرّر ايرث لنك/فايبر اكس/الشركات المُضافة وحده.
    bool permsShownOnly = false,
  }) async {
    try {
      final r = await ApiClient.dio.put<Map<String, dynamic>>(
        '/api/v2/employees/$id',
        data: {
          if (fullName != null) 'full_name': fullName,
          if (phone != null) 'phone': phone,
          if (password != null && password.isNotEmpty) 'password': password,
          if (isActive != null) 'is_active': isActive,
          if (permissions != null) 'permissions': permissions,
          if (permissions != null && permsShownOnly) 'perms_shown_only': true,
          // فرّق بين "لا تغيير" (null) و "مسح" (empty string).
          if (scopeAdminId != null) 'scope_admin_id': scopeAdminId.isEmpty ? null : scopeAdminId,
        },
      );
      final body = r.data ?? const {};
      return (ok: body['success'] == true, message: body['message']?.toString());
    } on DioException catch (e) {
      _log('employees (PUT)', e);
      final body = e.response?.data;
      final msg = body is Map ? body['message']?.toString() : null;
      return (ok: false, message: msg ?? 'تعذّر التعديل');
    } catch (e) {
      _log('employees (PUT)', e);
      return (ok: false, message: 'تعذّر التعديل');
    }
  }

  /// GET /api/v2/employees/:id/password — كلمة سرّ الموظّف الحاليّة.
  /// Backend يفكّ التشفير AES من `employees.password_encrypted`.
  /// الحقل يُملأ عند create/update. موظّف قديم (قبل feature) → 404
  /// مع نصيحة "عدّل كلمة سرّه مرّة".
  static Future<({String? password, String? message})> fetchPassword(int id) async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>(
        '/api/v2/employees/$id/password',
      );
      final body = r.data ?? const {};
      if (body['success'] != true) {
        return (password: null, message: body['message']?.toString());
      }
      final data = body['data'] as Map?;
      return (password: data?['password']?.toString(), message: null);
    } on DioException catch (e) {
      final msg = e.response?.data is Map ? (e.response?.data as Map)['message']?.toString() : null;
      return (password: null, message: msg ?? 'تعذّر جلب كلمة السر');
    } catch (_) {
      return (password: null, message: 'تعذّر جلب كلمة السر');
    }
  }

  static Future<({bool ok, String? message})> delete(int id) async {
    try {
      final r = await ApiClient.dio.delete<Map<String, dynamic>>('/api/v2/employees/$id');
      final body = r.data ?? const {};
      return (ok: body['success'] == true, message: body['message']?.toString());
    } on DioException catch (e) {
      _log('employees (DELETE)', e);
      final body = e.response?.data;
      final msg = body is Map ? body['message']?.toString() : null;
      return (ok: false, message: msg ?? 'تعذّر الحذف');
    } catch (e) {
      _log('employees (DELETE)', e);
      return (ok: false, message: 'تعذّر الحذف');
    }
  }

  static void _log(String endpoint, Object err) {
    if (kReleaseMode) return;
    if (err is DioException) {
      debugPrint(
        '🔴 $endpoint: status=${err.response?.statusCode} body=${err.response?.data}',
      );
    } else {
      debugPrint('🔴 $endpoint: $err');
    }
  }
}
