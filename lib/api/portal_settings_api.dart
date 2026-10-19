import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../core/util/server_time.dart';
import 'api_client.dart';

/// Branding — كيف تبدو بوابة المشترك (اسم شركة/شعار/تواصل).
class Branding {
  const Branding({
    this.displayName,
    this.logoUrl,
    this.aboutText,
    this.supportPhone,
    this.whatsappNumber,
    this.facebookUrl,
    this.instagramUrl,
    this.telegramUrl,
  });

  final String? displayName;
  final String? logoUrl;
  final String? aboutText;
  final String? supportPhone;
  final String? whatsappNumber;
  final String? facebookUrl;
  final String? instagramUrl;
  final String? telegramUrl;

  static const empty = Branding();

  static Branding fromJson(Map<String, dynamic> j) => Branding(
        displayName: _s(j['display_name']),
        logoUrl: _s(j['logo_url']),
        aboutText: _s(j['about_text']),
        supportPhone: _s(j['support_phone']),
        whatsappNumber: _s(j['whatsapp_number']),
        facebookUrl: _s(j['facebook_url']),
        instagramUrl: _s(j['instagram_url']),
        telegramUrl: _s(j['telegram_url']),
      );

  Map<String, dynamic> toJson() => {
        'display_name': displayName,
        'logo_url': logoUrl,
        'about_text': aboutText,
        'support_phone': supportPhone,
        'whatsapp_number': whatsappNumber,
        'facebook_url': facebookUrl,
        'instagram_url': instagramUrl,
        'telegram_url': telegramUrl,
      };

  Branding copyWith({
    Object? displayName = _sentinel,
    Object? logoUrl = _sentinel,
    Object? aboutText = _sentinel,
    Object? supportPhone = _sentinel,
    Object? whatsappNumber = _sentinel,
    Object? facebookUrl = _sentinel,
    Object? instagramUrl = _sentinel,
    Object? telegramUrl = _sentinel,
  }) {
    String? p(Object? next, String? cur) =>
        identical(next, _sentinel) ? cur : next as String?;
    return Branding(
      displayName: p(displayName, this.displayName),
      logoUrl: p(logoUrl, this.logoUrl),
      aboutText: p(aboutText, this.aboutText),
      supportPhone: p(supportPhone, this.supportPhone),
      whatsappNumber: p(whatsappNumber, this.whatsappNumber),
      facebookUrl: p(facebookUrl, this.facebookUrl),
      instagramUrl: p(instagramUrl, this.instagramUrl),
      telegramUrl: p(telegramUrl, this.telegramUrl),
    );
  }
}

const Object _sentinel = Object();

/// حزمة كما يراها البوابة — تدمج SAS (اسم/سعر read-only) + تخصيصات المدير.
class PortalPackage {
  const PortalPackage({
    required this.profileId,
    required this.sasName,
    required this.price,
    this.displayName,
    this.description,
    this.imageUrl,
    this.displayOrder = 100,
    this.isHidden = false,
  });

  final int profileId;
  final String sasName;
  final num price;
  final String? displayName;
  final String? description;
  final String? imageUrl;
  final int displayOrder;
  final bool isHidden;

  /// الاسم المعروض للمشترك — displayName override أو sasName كـfallback.
  String get effectiveName =>
      (displayName != null && displayName!.trim().isNotEmpty)
          ? displayName!
          : sasName;

  static PortalPackage? fromJson(Map<String, dynamic> j) {
    final pidRaw = j['profile_id'];
    final pid = pidRaw is int ? pidRaw : int.tryParse(pidRaw?.toString() ?? '');
    if (pid == null) return null;
    num toNum(dynamic v) =>
        v is num ? v : (v == null ? 0 : (num.tryParse(v.toString()) ?? 0));
    return PortalPackage(
      profileId: pid,
      sasName: (j['sas_name'] ?? '').toString(),
      price: toNum(j['price']),
      displayName: _s(j['display_name']),
      description: _s(j['description']),
      imageUrl: _s(j['image_url']),
      displayOrder: (j['display_order'] is int
              ? j['display_order'] as int
              : int.tryParse(j['display_order']?.toString() ?? '')) ??
          100,
      isHidden: j['is_hidden'] == true || j['is_hidden'] == 1,
    );
  }

  PortalPackage copyWith({
    Object? displayName = _sentinel,
    Object? description = _sentinel,
    Object? imageUrl = _sentinel,
    int? displayOrder,
    bool? isHidden,
  }) {
    String? p(Object? next, String? cur) =>
        identical(next, _sentinel) ? cur : next as String?;
    return PortalPackage(
      profileId: profileId,
      sasName: sasName,
      price: price,
      displayName: p(displayName, this.displayName),
      description: p(description, this.description),
      imageUrl: p(imageUrl, this.imageUrl),
      displayOrder: displayOrder ?? this.displayOrder,
      isHidden: isHidden ?? this.isHidden,
    );
  }
}

/// حال قسمٍ من إعدادات البوّابة عند فتحه.
enum PortalLoad {
  /// وصل القسم ببياناته.
  ok,

  /// الخادم ردّ نجاحاً **بلا** القسم: جلسة ايرث لنك تأخذ ردّاً آمناً فارغاً
  /// (`{success, data:null, items:[]}`) لكلّ مسارٍ لا يمرّره خادمنا لها —
  /// ومنها `/api/v2/admin/branding` و`portal-packages` اليوم، وحفظهما 503.
  /// فلا نموذج يُملأ ويفشل حفظه؛ ومتى مرّرها الخادم صار القسم [ok] وحده.
  unsupported,

  /// شبكة أو خادم. ⚠️ لا نموذج فارغاً هنا: حفظه يرسل الحقول كلّها null
  /// فيمسح ما خزّنه المدير — بل «إعادة المحاولة».
  failed,
}

/// قسمٌ من تطبيق المشترك يختار الوكيل إظهاره لمشتركيه — مفاتيح `sections`
/// في `GET/PUT /api/v2/portal/settings` (وسيط البوّابة §11).
enum PortalSection {
  /// «حالة الاتصال»: متصلٌ أو لا، ومنذ متى، وجلسته، وآخر اتصال.
  connection('connection'),

  /// «الاستهلاك»: التحميل والرفع باليوم والشهر.
  usage('usage'),

  /// قراءات جهاز المشترك — مطفأٌ افتراضاً ولا يقرؤه تطبيق المشترك بعد، فلا
  /// مفتاح له في الشاشة: يُحمَل كما وصل ويُعاد كما هو مع كلّ حفظ.
  device('device');

  const PortalSection(this.key);

  /// اسمه في JSON.
  final String key;
}

/// ما يظهر لمشتركي الوكيل في تطبيقهم. الافتراض (لا صفّ، أو مفتاحٌ ناقص):
/// «حالة الاتصال» و«الاستهلاك» ظاهران، والجهاز مطفأ.
@immutable
class PortalSections {
  const PortalSections({
    this.connection = true,
    this.usage = true,
    this.device = false,
  });

  final bool connection;
  final bool usage;
  final bool device;

  bool of(PortalSection s) => switch (s) {
        PortalSection.connection => connection,
        PortalSection.usage => usage,
        PortalSection.device => device,
      };

  PortalSections withValue(PortalSection s, bool value) => PortalSections(
        connection: s == PortalSection.connection ? value : connection,
        usage: s == PortalSection.usage ? value : usage,
        device: s == PortalSection.device ? value : device,
      );

  /// مفتاحٌ غائبٌ أو غير مفهوم يأخذ قيمته من [fallback]: الافتراض عند
  /// القراءة، وما أُرسل عند ردّ الحفظ — فلا يقلب ردٌّ جزئيّ قسماً لم يُلمس.
  static PortalSections fromJson(
    Map<String, dynamic> j, {
    PortalSections fallback = const PortalSections(),
  }) =>
      PortalSections(
        connection: _flag(j[PortalSection.connection.key], fallback.connection),
        usage: _flag(j[PortalSection.usage.key], fallback.usage),
        device: _flag(j[PortalSection.device.key], fallback.device),
      );

  Map<String, bool> toJson() => {
        for (final s in PortalSection.values) s.key: of(s),
      };

  @override
  bool operator ==(Object other) =>
      other is PortalSections &&
      other.connection == connection &&
      other.usage == usage &&
      other.device == device;

  @override
  int get hashCode => Object.hash(connection, usage, device);

  @override
  String toString() => 'PortalSections(${toJson()})';
}

/// «رمز الوكيل» ومفتاح البوّابة — `GET /api/v2/portal/settings`.
///
/// الرمز ستّة أرقام لكلّ حساب وكيل (المالك؛ والموظّف يرى رمز مديره)، يكتبه
/// المشترك في تطبيق MyServices مع يوزره وكلمة مروره. يُنشئه الخادم عند أوّل
/// عرض، و`null` = لا رمز لحسابك (شركةٌ لا تخدمها البوّابة بعد، أو جداول
/// البوّابة غير مهيّأة) — حالةٌ هادئة لا خطأ.
class PortalAccess {
  const PortalAccess({required this.enabled, this.agentCode, this.sections});

  /// بوّابة مشتركي هذا الوكيل مفتوحة؟ مفتوحةٌ افتراضاً (لا صفّ = مفتوحة).
  final bool enabled;
  final String? agentCode;

  /// ما يظهر لمشتركيه (§11). `null` = خادمٌ لا يُرسل الأقسام — فلا مفاتيح
  /// لها في الشاشة (حفظٌ لا يقرؤه أحد).
  final PortalSections? sections;

  static PortalAccess fromJson(Map<String, dynamic> j) {
    final sections = j['sections'];
    return PortalAccess(
      enabled: !(j['enabled'] == false || j['enabled'] == 0),
      agentCode: parseAgentCode(j['agent_code']),
      sections: sections is Map
          ? PortalSections.fromJson(Map<String, dynamic>.from(sections))
          : null,
    );
  }

  PortalAccess copyWith({
    bool? enabled,
    Object? agentCode = _sentinel,
    Object? sections = _sentinel,
  }) =>
      PortalAccess(
        enabled: enabled ?? this.enabled,
        agentCode: identical(agentCode, _sentinel)
            ? this.agentCode
            : agentCode as String?,
        sections: identical(sections, _sentinel)
            ? this.sections
            : sections as PortalSections?,
      );
}

/// متغيّر القوالب الذي يُستبدل برمز وكيل المُرسِل — الخادم يملؤه في كلّ قالب
/// واتساب/تلغرام يمرّ به، والتطبيق فيما يركّبه ويرسله بنفسه
/// ([PortalSettingsApi.fillAgentCode]).
const kAgentCodeVariable = '{agent_code}';

/// رمز وكيلٍ صالح (ستّة أرقام بالضبط، نصّاً فلا تسقط الأصفار البادئة) — وإلّا
/// `null`، فلا يُعرض للمدير ولا يُشارَك رمزٌ لا يقبله الخادم.
String? parseAgentCode(dynamic raw) {
  final s = raw?.toString().trim() ?? '';
  return RegExp(r'^\d{6}$').hasMatch(s) ? s : null;
}

/// كيف حاول المشترك الدخول (`via` في السجلّ).
enum PortalLoginVia {
  /// يوزر وكلمة مرور — تحقّق خادمنا (`pw`) أو دخولٌ مباشر على الساس (`sas`).
  password,

  /// رمز QR من الوكيل.
  qr,

  /// لا طريقة: رُفض قبل التحقّق (بوّابةٌ موقوفة مثلاً).
  unknown,
}

/// نتيجة المحاولة (`result` في السجلّ).
enum PortalLoginResult {
  ok,
  badPassword,

  /// تعذّر التحقّق من كلمة المرور عند الوكيل (صلاحيّة رؤيتها مقفلة بالساس).
  unverifiable,

  /// البوّابة موقوفة من الوكيل.
  disabled,

  /// الخدمة غير متاحة لحساب الوكيل (اشتراكٌ منتهٍ/محظور).
  unavailable,

  /// قيمةٌ لا يعرفها هذا الإصدار — تُعرض «محاولة» لا نصّاً خاماً.
  other,
}

/// صفٌّ من «آخر دخول المشتركين» — `GET /api/v2/portal/logins` (بلا كلمات
/// مرور ولا توكنات؛ والخادم يحفظ ٩٠ يوماً).
class PortalLogin {
  const PortalLogin({
    this.at,
    this.username,
    this.via = PortalLoginVia.unknown,
    this.result = PortalLoginResult.other,
  });

  /// بتوقيت الجهاز — `at` من قاعدتنا موسومٌ بـZ ([parseServerUtc]).
  final DateTime? at;

  /// اليوزر كما كتبه المشترك (بأحرفٍ صغيرة).
  final String? username;
  final PortalLoginVia via;
  final PortalLoginResult result;

  static PortalLogin fromJson(Map<String, dynamic> j) => PortalLogin(
        at: parseServerUtc(j['at']?.toString()),
        username: _s(j['username_lc']),
        via: switch (j['via']?.toString()) {
          'pw' || 'sas' => PortalLoginVia.password,
          'qr' => PortalLoginVia.qr,
          _ => PortalLoginVia.unknown,
        },
        result: switch (j['result']?.toString()) {
          'ok' => PortalLoginResult.ok,
          'bad_password' => PortalLoginResult.badPassword,
          'pw_unverifiable' => PortalLoginResult.unverifiable,
          'portal_disabled' => PortalLoginResult.disabled,
          'portal_unavailable' => PortalLoginResult.unavailable,
          _ => PortalLoginResult.other,
        },
      );
}

/// Portal settings API — branding + packages customization + «رمز الوكيل».
class PortalSettingsApi {
  PortalSettingsApi._();

  /// [PortalLoad.unsupported] لردٍّ ناجحٍ بلا `branding` (جلسة ايرث لنك —
  /// انظر [PortalLoad])، و[PortalLoad.failed] لما سواه من الإخفاق.
  static Future<({PortalLoad state, Branding branding})> loadBranding() async {
    try {
      final r = await ApiClient.dio
          .get<Map<String, dynamic>>('/api/v2/admin/branding');
      final body = r.data ?? const {};
      final b = body['branding'];
      if (r.statusCode == 200 && b is Map) {
        return (
          state: PortalLoad.ok,
          branding: Branding.fromJson(Map<String, dynamic>.from(b)),
        );
      }
      final unsupported = r.statusCode == 200 &&
          body['success'] == true &&
          !body.containsKey('branding');
      return (
        state: unsupported ? PortalLoad.unsupported : PortalLoad.failed,
        branding: Branding.empty,
      );
    } on DioException catch (e) {
      _log('branding (GET)', e);
      return (state: PortalLoad.failed, branding: Branding.empty);
    } catch (e) {
      _log('branding (GET)', e);
      return (state: PortalLoad.failed, branding: Branding.empty);
    }
  }

  /// [saved] ما خزّنه الخادم فعلاً (قد يطبّعه: صورة صفحة المشاركة، رقم 07…)،
  /// و[message] سبب الرفض العربيّ (رابط صفحةٍ لا صورة مثلاً) — وإلّا null.
  static Future<({bool ok, String? message, Branding? saved})> saveBranding(
      Branding b) async {
    try {
      final r = await ApiClient.dio.put<Map<String, dynamic>>(
        '/api/v2/admin/branding',
        data: b.toJson(),
      );
      if (r.statusCode == 200 && r.data?['success'] == true) {
        final row = r.data?['branding'];
        return (
          ok: true,
          message: null,
          saved: row is Map
              ? Branding.fromJson(Map<String, dynamic>.from(row))
              : null,
        );
      }
      return (ok: false, message: _refusal(r), saved: null);
    } on DioException catch (e) {
      _log('branding (PUT)', e);
      return (ok: false, message: null, saved: null);
    } catch (e) {
      _log('branding (PUT)', e);
      return (ok: false, message: null, saved: null);
    }
  }

  /// كـ[loadBranding]: `unsupported` لردٍّ ناجحٍ بلا `packages`، و`failed`
  /// للإخفاق — فلا تقول الشاشة «لا توجد باقات» لشبكةٍ انقطعت.
  static Future<({PortalLoad state, List<PortalPackage> packages})>
      loadPackages() async {
    try {
      final r = await ApiClient.dio
          .get<Map<String, dynamic>>('/api/v2/admin/portal-packages');
      final body = r.data ?? const {};
      final list = body['packages'];
      if (r.statusCode == 200 && list is List) {
        return (
          state: PortalLoad.ok,
          packages: list
              .whereType<Map>()
              .map((m) => PortalPackage.fromJson(Map<String, dynamic>.from(m)))
              .whereType<PortalPackage>()
              .toList(),
        );
      }
      final unsupported = r.statusCode == 200 &&
          body['success'] == true &&
          !body.containsKey('packages');
      return (
        state: unsupported ? PortalLoad.unsupported : PortalLoad.failed,
        packages: const <PortalPackage>[],
      );
    } on DioException catch (e) {
      _log('portal-packages (GET)', e);
      return (state: PortalLoad.failed, packages: const <PortalPackage>[]);
    } catch (e) {
      _log('portal-packages (GET)', e);
      return (state: PortalLoad.failed, packages: const <PortalPackage>[]);
    }
  }

  /// PUT عام — يقبل حقول جزئية (displayName, description, imageUrl,
  /// displayOrder, isHidden). null = مسح القيمة على السيرفر.
  /// [message] سبب الرفض العربيّ من الخادم (رابط صفحةٍ لا صورة) — وإلّا null.
  static Future<({bool ok, String? message})> updatePackage(
    int profileId, {
    Object? displayName = _sentinel,
    Object? description = _sentinel,
    Object? imageUrl = _sentinel,
    int? displayOrder,
    bool? isHidden,
  }) async {
    final body = <String, dynamic>{};
    if (!identical(displayName, _sentinel)) body['display_name'] = displayName;
    if (!identical(description, _sentinel)) body['description'] = description;
    if (!identical(imageUrl, _sentinel)) body['image_url'] = imageUrl;
    if (displayOrder != null) body['display_order'] = displayOrder;
    if (isHidden != null) body['is_hidden'] = isHidden;
    try {
      final r = await ApiClient.dio.put<Map<String, dynamic>>(
        '/api/v2/admin/portal-packages/$profileId',
        data: body,
      );
      if (r.statusCode == 200 && r.data?['success'] == true) {
        return (ok: true, message: null);
      }
      return (ok: false, message: _refusal(r));
    } on DioException catch (e) {
      _log('portal-packages (PUT $profileId)', e);
      return (ok: false, message: null);
    } catch (e) {
      _log('portal-packages (PUT $profileId)', e);
      return (ok: false, message: null);
    }
  }

  /// DELETE — يمسح التخصيصات، الباقة ترجع لبياناتها الأصلية من SAS.
  static Future<bool> resetPackage(int profileId) async {
    try {
      final r = await ApiClient.dio.delete<Map<String, dynamic>>(
        '/api/v2/admin/portal-packages/$profileId',
      );
      return r.statusCode == 200 && r.data?['success'] == true;
    } on DioException catch (e) {
      _log('portal-packages (DELETE $profileId)', e);
      return false;
    } catch (e) {
      _log('portal-packages (DELETE $profileId)', e);
      return false;
    }
  }

  // ─── «رمز الوكيل» ومفتاح البوّابة وسجلّ الدخول (وسيط البوّابة §6/§10) ───
  // كلّها للمزوّدين جميعاً: جلسات ايرث لنك تمرّ إلى المعالجات نفسها
  // (`v2/portal/` في elPassthrough.js)، والموظّف يُخدَم باسم مديره.

  /// يملأ [kAgentCodeVariable] في نصٍّ ركّبه التطبيق من قالب — قبل معاينته
  /// وقبل الإرسال **اليدويّ** (من واتساب المدير نفسه، فلا يمرّ بخادمنا الذي
  /// يملؤه في التلقائيّ؛ وكان يصل المشترك «{agent_code}» حرفيّاً).
  ///
  /// نصٌّ بلا المتغيّر يعود كما هو بلا نداء. ورمزٌ تعذّر جلبه يُبقي المتغيّر:
  /// يُرى في المعاينة، والخادم يملؤه إن أُرسل تلقائيّاً. أمّا حسابٌ ردّ الخادم
  /// أنّه **بلا رمز** (`agent_code: null`) فيُفرَّغ المتغيّر — كما يفعل الخادم
  /// نفسه في التلقائيّ (`templateHelper.applyAgentCode`)، فلا يصل المشترك
  /// «{agent_code}» حرفيّاً من اليدويّ.
  static Future<String> fillAgentCode(String text) async {
    if (!text.contains(kAgentCodeVariable)) return text;
    final access = await getAccess();
    if (access == null) return text;
    return text.replaceAll(kAgentCodeVariable, access.agentCode ?? '');
  }

  /// الإعدادات ورمز الوكيل — بلا صلاحيّة (المالك والموظّف). `null` = تعذّر.
  static Future<PortalAccess?> getAccess() async {
    try {
      final r = await ApiClient.dio
          .get<Map<String, dynamic>>('/api/v2/portal/settings');
      final body = r.data;
      if (r.statusCode == 200 && body != null && body['success'] == true) {
        return PortalAccess.fromJson(body);
      }
      return null;
    } on DioException catch (e) {
      _log('portal settings (GET)', e);
      return null;
    } catch (e) {
      _log('portal settings (GET)', e);
      return null;
    }
  }

  /// يفتح بوّابة مشتركي الوكيل كلّها أو يوقفها. الخادم: المالك دائماً،
  /// والموظّف بـ`settings.edit`.
  ///
  /// [denied] = ٤٠٣ (صلاحيّةٌ سُحبت بعد فتح الشاشة) — فتقول الشاشة «لا
  /// صلاحيّة» لا رسالة الخادم «لا تملك صلاحية: settings.edit» بمفتاحها الخام.
  /// [enabled] ما خزّنه الخادم فعلاً عند النجاح.
  static Future<({bool ok, bool? enabled, bool denied, String? message})>
      setPortalEnabled(bool enabled) async {
    try {
      final r = await ApiClient.dio.put<Map<String, dynamic>>(
        '/api/v2/portal/settings',
        data: {'enabled': enabled},
      );
      final body = r.data;
      if (r.statusCode == 200 && body?['success'] == true) {
        final saved = body?['enabled'];
        return (
          ok: true,
          enabled: saved is bool ? saved : enabled,
          denied: false,
          message: null,
        );
      }
      if (r.statusCode == 403) {
        return (ok: false, enabled: null, denied: true, message: null);
      }
      return (ok: false, enabled: null, denied: false, message: _refusal(r));
    } on DioException catch (e) {
      _log('portal settings (PUT)', e);
      return (ok: false, enabled: null, denied: false, message: null);
    } catch (e) {
      _log('portal settings (PUT)', e);
      return (ok: false, enabled: null, denied: false, message: null);
    }
  }

  /// يُظهر قسماً من تطبيق المشترك أو يخفيه (§11): يُرسل [section] **وحده**
  /// `{sections:{key: value}}` — الخادم يحفظ كلّ قسمٍ على حدة ويردّ الأقسام
  /// كاملةً كما حُفظت. فلا يُكتب فوق ما غيّره الويب أو جهازٌ آخر بعد فتح
  /// الشاشة (كان إرسال الثلاثة من نسخةٍ قديمة يُعيد قسماً أخفاه غيرك).
  /// والصلاحيّة كالمفتاح: المالك دائماً، والموظّف بـ`settings.edit`.
  ///
  /// [sections] ما خزّنه الخادم عند النجاح — مفتاحٌ ناقصٌ فيه من [current]
  /// مع القيمة المرسَلة — و`null` لردٍّ بلا أقسام (يبني المُستدعي على ما
  /// عنده)، و[denied] ٤٠٣، و[message] سبب الرفض العربيّ — كـ[setPortalEnabled].
  static Future<
          ({bool ok, PortalSections? sections, bool denied, String? message})>
      setPortalSections(PortalSection section, bool value,
          {PortalSections? current}) async {
    try {
      final r = await ApiClient.dio.put<Map<String, dynamic>>(
        '/api/v2/portal/settings',
        data: {
          'sections': {section.key: value},
        },
      );
      final body = r.data;
      if (r.statusCode == 200 && body?['success'] == true) {
        final saved = body?['sections'];
        return (
          ok: true,
          sections: saved is Map
              ? PortalSections.fromJson(Map<String, dynamic>.from(saved),
                  fallback: (current ?? const PortalSections())
                      .withValue(section, value))
              : null,
          denied: false,
          message: null,
        );
      }
      if (r.statusCode == 403) {
        return (ok: false, sections: null, denied: true, message: null);
      }
      return (ok: false, sections: null, denied: false, message: _refusal(r));
    } on DioException catch (e) {
      _log('portal sections (PUT)', e);
      return (ok: false, sections: null, denied: false, message: null);
    } catch (e) {
      _log('portal sections (PUT)', e);
      return (ok: false, sections: null, denied: false, message: null);
    }
  }

  /// رمزٌ جديد فوراً، والقديم يتوقّف الآن — لصاحب الحساب وحده (الموظّف
  /// ٤٠٣ `OWNER_ONLY` ولو بكلّ الصلاحيّات). [code] الجديد عند النجاح،
  /// و[message] سبب الرفض العربيّ («لصاحب الحساب فقط»، «غير متاح بعد»).
  static Future<({String? code, bool ownerOnly, String? message})>
      rotateAgentCode() async {
    try {
      final r = await ApiClient.dio
          .post<Map<String, dynamic>>('/api/v2/portal/agent-code/rotate');
      final body = r.data;
      final code = parseAgentCode(body?['agent_code']);
      if (r.statusCode == 200 && body?['success'] == true && code != null) {
        return (code: code, ownerOnly: false, message: null);
      }
      return (
        code: null,
        ownerOnly: r.statusCode == 403 && body?['code'] == 'OWNER_ONLY',
        message: _refusal(r),
      );
    } on DioException catch (e) {
      _log('agent-code rotate', e);
      return (code: null, ownerOnly: false, message: null);
    } catch (e) {
      _log('agent-code rotate', e);
      return (code: null, ownerOnly: false, message: null);
    }
  }

  /// آخر محاولات دخول مشتركي الوكيل، الأحدث أوّلاً. الخادم يطلب
  /// `subscribers.view` من الموظّف — فالشاشة لا تسأل بدونها ([denied] احتياطٌ
  /// لصلاحيّةٍ سُحبت). [rows] `null` = تعذّر الجلب.
  static Future<({List<PortalLogin>? rows, bool denied})> getLogins({
    int limit = 20,
  }) async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>(
        '/api/v2/portal/logins',
        queryParameters: {'limit': limit},
      );
      final body = r.data;
      if (r.statusCode == 403) return (rows: null, denied: true);
      final data = body?['data'];
      if (r.statusCode == 200 && body?['success'] == true && data is List) {
        return (
          rows: data
              .whereType<Map>()
              .map((m) => PortalLogin.fromJson(Map<String, dynamic>.from(m)))
              .toList(),
          denied: false,
        );
      }
      return (rows: null, denied: false);
    } on DioException catch (e) {
      _log('portal logins (GET)', e);
      return (rows: null, denied: false);
    } catch (e) {
      _log('portal logins (GET)', e);
      return (rows: null, denied: false);
    }
  }
}

// ─── helpers ──────────────────────────
String? _s(dynamic v) {
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

/// مفتاح قسمٍ كما يرسله الخادم: `true/false`، أو `1/0` (عمود TINYINT)، أو
/// نصّهما — وإلّا [fallback].
bool _flag(dynamic v, bool fallback) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) {
    switch (v.trim().toLowerCase()) {
      case 'true' || '1':
        return true;
      case 'false' || '0':
        return false;
    }
  }
  return fallback;
}

/// رسالة الرفض من ردٍّ ٤xx (الـ٥xx يرمي — `validateStatus`) — كرفض رابط
/// صفحةٍ لا صورة: «هذا رابط صفحة لا صورة — افتح الصورة واختر نسخ رابط
/// الصورة المباشر». العربيّة وحدها تُعرض (غيرها قد يكون أثراً تقنيّاً)،
/// وإلّا null فتقول الشاشة «فشل الحفظ» كما كانت.
String? _refusal(Response<Map<String, dynamic>> r) {
  final m = r.data?['message'];
  if (m is! String) return null;
  final t = m.trim();
  return t.isNotEmpty && RegExp(r'[؀-ۿ]').hasMatch(t) ? t : null;
}

void _log(String tag, Object e) {
  if (kDebugMode) debugPrint('[PortalSettingsApi] $tag: $e');
}
