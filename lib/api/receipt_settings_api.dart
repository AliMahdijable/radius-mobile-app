import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../services/auth_storage.dart';
import '../services/receipt_layout.dart';
import 'api_client.dart';
import 'company_route.dart';

/// إعدادات الوصل كما يحفظها **مصمّم الويب** («قوالب الطباعة» في `/v2` ←
/// جدول `receipt_settings` بـ`POST /api/v2/receipt-settings`).
///
/// منذ ٢٤ أكتوبر يطبع التطبيق **كلّ** وصولاته بها لكلّ المزوّدين، كالموقع («مثل الويب» —
/// المالك): الترويسة والتذييل وما يظهر من الأقسام ورمز QR والطباعة التلقائيّة وعرض ورق
/// الكاشير. قوالب `print_templates` القديمة (الكلاسيك) لا يقرؤها الموقع ولا يكتبها أحد منذ
/// النقل. نوع الخطّ والإطارات لطباعة الويب وحدها؛ أبعاد الكاشير (الحواشي وحجم الخطّ والشعار وQR
/// والمسافات) يطبعها التطبيق كالموقع منذ ٣٠ أكتوبر.
///
/// «تصميم الوصل» v2 (١ نوفمبر): `design.layout` ([layout]) — الإخفاء والتسميات والأحجام والعناوين والنصوص والضغط —
/// يقرؤه المحلِّل من التصميم الخامّ ([design]) كما يقرؤه الموقع، ومعه المحاذاة وفواصل الصفوف وخطّ عناوين الأقسام. بلا
/// `layout` يُطبع الوصل بطريق v1 كما كان ([ReceiptPdf]).
@immutable
class ReceiptSettings {
  const ReceiptSettings({
    this.shopName,
    this.shopAddress,
    this.shopPhone,
    this.footerText,
    this.logo,
    this.showQr = true,
    this.autoPrint = false,
    this.paperWidthMm = 80,
    this.marginTopMm = 4,
    this.marginRightMm = 4,
    this.marginBottomMm = 4,
    this.marginLeftMm = 4,
    this.fontBasePx = 13,
    this.fontTitlePx = 16,
    this.logoSizeMm = 18,
    this.qrSizeMm = 35,
    this.sectionGapMm = 6,
    this.accent,
    this.showLogo = true,
    this.showShopInfo = true,
    this.showSubscriberInfo = true,
    this.showPackageInfo = true,
    this.showPackagePrice = true,
    this.showTransactionInfo = true,
    this.showFooter = true,
    this.showSignature = true,
    this.showReceiptId = true,
    this.showDateTime = true,
    this.rowSeparator = 'dotted',
    this.sectionTitleUnderline = true,
    this.lineHeight = 1.5,
    this.design,
    this.paperSize = 'pos',
    this.updatedAt,
    this.raw,
  });

  final String? shopName;
  final String? shopAddress;
  final String? shopPhone;
  final String? footerText;

  /// الشعار مفكوكاً من data URL — PNG أو JPEG وحدهما (ما يُرسم بلا مفاجآت).
  final Uint8List? logo;

  /// رمز QR لمعلومات المشترك على الوصل (`show_qr`، الافتراضيّ ظاهر كالخادم).
  final bool showQr;

  /// «الطباعة التلقائيّة» (`auto_print`): الوصل يُطبع بعد التفعيل/التمديد/التسديد بلا سؤال —
  /// خانة «طباعة وصل بعد التأكيد» تأتي معلَّمةً.
  final bool autoPrint;

  /// عرض ورق الكاشير بالملّيمتر (`design.paper_width_mm`، ٥٠–١٢٠) — طابعات ٥٨ موجودة.
  final double paperWidthMm;

  /// أبعاد وصل الكاشير من المصمّم بمدياته وافتراضاته (`print-receipt.ts`): حواشي الورق (`margin_*_mm`، ٠–٣٠)،
  /// الخطّ الأساسيّ والعنوان بنقاط الشاشة (`font_size_base` ٩–٢٢، `font_size_title` ١٢–٣٦)، ارتفاع الشعار
  /// (`logo_size_mm` ٨–٥٠)، رمز QR (`qr_size_mm` ١٥–٦٠)، والمسافة بين الأقسام (`section_gap_mm` ٠–٢٠).
  /// المالك ٣٠ أكتوبر: «الابعاد مجاي تتصح مثل الويب» — نحو ٤٠٪ من الوكلاء غيّروا واحداً منها على الأقلّ.
  final double marginTopMm;
  final double marginRightMm;
  final double marginBottomMm;
  final double marginLeftMm;
  final double fontBasePx;
  final double fontTitlePx;
  final double logoSizeMm;
  final double qrSizeMm;
  final double sectionGapMm;

  /// لون العناوين (`design.accent_color`، ARGB) لوصل A4 — ورق الكاشير أسود دائماً.
  final int? accent;

  /// أقسام الوصل في `design` (الغائب = ظاهر، كافتراض الويب).
  final bool showLogo;
  final bool showShopInfo;
  final bool showSubscriberInfo;
  final bool showPackageInfo;
  final bool showPackagePrice;
  final bool showTransactionInfo;
  final bool showFooter;

  /// «أصدره: …» (`show_manager_signature`).
  final bool showSignature;
  final bool showReceiptId;
  final bool showDateTime;

  /// فاصل صفوف الأقسام (`none|dotted|dashed|solid`) وخطّ تحت عنوان القسم — وصل v2 وحده.
  final String rowSeparator;
  final bool sectionTitleUnderline;

  /// ارتفاع السطر (١٫٠–٢٫٢) — للموقع؛ يُقرأ هنا لمعرفة «حجم الوصل» وحده.
  final double lineHeight;

  /// التصميم كما حفظه المصمّم (`data.design`: مفاتيح v1 و`layout`) — يقرؤه المحلِّل ([ReceiptResolver]) بدلالات الموقع.
  final Map<String, dynamic>? design;

  /// نوع الورق المحفوظ (`paper_size`: `pos` أو `a4`) — يكتبه المصمّم مع الأعمدة كلّها (عمودٌ غائب يعيده الخادم `pos`).
  /// الطباعة ما زالت بإعداد الجهاز («الطابعة الافتراضية»).
  final String paperSize;

  /// ختم آخر حفظ (`updated_at` نصّاً كما أعاده الخادم) — يعود مع الحفظ (`if_updated_at`) فلا يمحو جهازٌ آخر أو صفحةٌ
  /// قديمة تصميماً أحدث منه (409). null = خادمٌ أقدم أو لا صفّ بعد.
  final String? updatedAt;

  /// `data` كما أعادها الخادم بلا الشعار — المصمّم يرقّع التصميم الخامّ ويحفظ الأعمدة كلّها منه.
  final Map<String, dynamic>? raw;

  /// «تصميم الوصل» v2 — `null` = طريق v1 (كلّ التصاميم قبل ١ نوفمبر، وكلّ تصميمٍ بلا `layout`).
  ReceiptLayout? get layout => ReceiptLayout.fromJson(design?['layout']);

  /// «حجم الوصل» في المصمّم: `normal` · `compact` · `tight`، أو null («مخصّص») حين لا يطابق مقاساً.
  String? get preset {
    final l = layout;
    for (final e in receiptPresets.entries) {
      final p = e.value;
      final v = p.v1;
      bool same(num a, Object? b) => b is num && (a - b).abs() < 0.001;
      if (same(fontBasePx, v['font_size_base']) &&
          same(fontTitlePx, v['font_size_title']) &&
          same(sectionGapMm, v['section_gap_mm']) &&
          same(lineHeight, v['line_height']) &&
          same(marginTopMm, v['margin_top_mm']) &&
          same(marginRightMm, v['margin_right_mm']) &&
          same(marginBottomMm, v['margin_bottom_mm']) &&
          same(marginLeftMm, v['margin_left_mm']) &&
          same(logoSizeMm, v['logo_size_mm']) &&
          same(qrSizeMm, v['qr_size_mm']) &&
          rowSeparator == v['row_separator'] &&
          sectionTitleUnderline == v['section_title_underline'] &&
          (l?.density ?? 'normal') == p.density &&
          (l?.emoji ?? true) == p.emoji) {
        return e.key;
      }
    }
    return null;
  }

  /// الحقول المخفيّة في «المعلومات»: مفاتيح v1 الأربعة (الرقم والوقت وسعر الباقة و«أصدره») وما أخفاه v2.
  int get hiddenFields =>
      [showReceiptId, showDateTime, showPackagePrice, showSignature].where((on) => !on).length + (layout?.hiddenFields ?? 0);

  /// النصوص الإضافيّة (v2).
  int get customTexts => layout?.texts.length ?? 0;

  /// هل خصّص المالك شيئاً يظهر في الوصل؟ (لا = يُطبع باسم الحساب كما كان.)
  bool get isCustomized =>
      [shopName, shopAddress, shopPhone, footerText]
          .any((s) => (s ?? '').trim().isNotEmpty) ||
      logo != null;

  static String? _str(Object? v) {
    final s = v?.toString().trim() ?? '';
    return s.isEmpty ? null : s;
  }

  /// `data:image/png;base64,…` ← بايتات، أو null لغير PNG/JPEG أو التالف.
  @visibleForTesting
  static Uint8List? decodeLogo(Object? raw) {
    final s = raw?.toString() ?? '';
    final comma = s.indexOf(',');
    if (!s.startsWith('data:image/') || comma < 0) return null;
    try {
      final bytes = base64Decode(s.substring(comma + 1).trim());
      final png = bytes.length > 8 &&
          bytes[0] == 0x89 &&
          bytes[1] == 0x50 &&
          bytes[2] == 0x4E &&
          bytes[3] == 0x47;
      final jpeg = bytes.length > 3 &&
          bytes[0] == 0xFF &&
          bytes[1] == 0xD8 &&
          bytes[2] == 0xFF;
      return png || jpeg ? bytes : null;
    } catch (_) {
      return null;
    }
  }

  /// من `data` في ردّ الخادم. صفّ لم يُحفظ بعد يأتي بقيمٍ فارغة (لا خطأ).
  ///
  /// [logo] بايتات الشعار مفكوكةً سلفاً (مسوّدة المصمّم تُبنى مع كلّ تعديل — لا يُفكّ الشعار كلّ مرّة)؛ بلاها من
  /// `logo_data`.
  static ReceiptSettings fromJson(Map<String, dynamic> j, {Uint8List? logo}) {
    final design = j['design'];
    bool flag(String k) =>
        design is Map ? (design[k] == null ? true : design[k] == true) : true;
    // tinyint يصل 0/1 أو true/false أو "1".
    bool on(Object? v, {required bool fallback}) =>
        v == null ? fallback : (v == true || v == 1 || '$v' == '1' || '$v' == 'true');
    final width = design is Map ? num.tryParse('${design['paper_width_mm'] ?? ''}') : null;
    // رقمٌ من المصمّم بمداه، والغائب أو التالف افتراض الموقع.
    double dim(String k, double fallback, double lo, double hi) {
      final v = design is Map ? num.tryParse('${design[k] ?? ''}') : null;
      return v == null || !v.isFinite ? fallback : v.toDouble().clamp(lo, hi).toDouble();
    }

    // نصٌّ من قائمةٍ مغلقة، وغيره افتراض الموقع.
    String pick(String k, List<String> allowed, String fallback) {
      final v = design is Map ? design[k] : null;
      return v is String && allowed.contains(v) ? v : fallback;
    }

    return ReceiptSettings(
      shopName: _str(j['shop_name']),
      shopAddress: _str(j['shop_address']),
      shopPhone: _str(j['shop_phone']),
      footerText: _str(j['footer_text']),
      logo: logo ?? decodeLogo(j['logo_data']),
      showQr: on(j['show_qr'], fallback: true),
      autoPrint: on(j['auto_print'], fallback: false),
      paperWidthMm: width == null ? 80 : width.toDouble().clamp(50, 120).toDouble(),
      marginTopMm: dim('margin_top_mm', 4, 0, 30),
      marginRightMm: dim('margin_right_mm', 4, 0, 30),
      marginBottomMm: dim('margin_bottom_mm', 4, 0, 30),
      marginLeftMm: dim('margin_left_mm', 4, 0, 30),
      fontBasePx: dim('font_size_base', 13, 9, 22),
      fontTitlePx: dim('font_size_title', 16, 12, 36),
      logoSizeMm: dim('logo_size_mm', 18, 8, 50),
      qrSizeMm: dim('qr_size_mm', 35, 15, 60),
      sectionGapMm: dim('section_gap_mm', 6, 0, 20),
      accent: design is Map ? parseHex(design['accent_color']) : null,
      showLogo: flag('show_logo'),
      showShopInfo: flag('show_shop_info'),
      showSubscriberInfo: flag('show_subscriber_info'),
      showPackageInfo: flag('show_package_info'),
      showPackagePrice: flag('show_package_price'),
      showTransactionInfo: flag('show_transaction_info'),
      showFooter: flag('show_footer'),
      showSignature: flag('show_manager_signature'),
      showReceiptId: flag('show_receipt_id'),
      showDateTime: flag('show_datetime'),
      rowSeparator: pick('row_separator', const ['none', 'dotted', 'dashed', 'solid'], 'dotted'),
      sectionTitleUnderline: flag('section_title_underline'),
      lineHeight: dim('line_height', 1.5, 1, 2.2),
      design: design is Map ? Map<String, dynamic>.from(design) : null,
      paperSize: j['paper_size'] == 'a4' ? 'a4' : 'pos',
      updatedAt: _str(j['updated_at']),
      raw: Map<String, dynamic>.from(j)..remove('logo_data'),
    );
  }

  /// `#RRGGBB` ← ARGB معتم، أو null لغيره.
  @visibleForTesting
  static int? parseHex(Object? v) {
    final m = RegExp(r'^#?([0-9a-fA-F]{6})$').firstMatch('${v ?? ''}'.trim());
    return m == null ? null : 0xFF000000 | int.parse(m.group(1)!, radix: 16);
  }
}

/// `GET /api/v2/receipt-settings` — إعدادات وصل الحساب الحاليّ.
class ReceiptSettingsApi {
  ReceiptSettingsApi._();

  /// الشعار قد يقارب نصف ميغابايت — فالطباعة لا تجلبه مع كلّ وصل. مخبّأٌ
  /// **بمعرّف الحساب** (تبديل الشركة لا يطبع بهويّة سابقتها) ولدقائق
  /// (تعديلٌ على الويب يصل قريباً، والشاشة تجلب جديداً دائماً).
  static const _ttl = Duration(minutes: 5);
  static ({String adminId, DateTime at, ReceiptSettings value})? _cache;

  /// `null` على أيّ فشل (شبكة/صلاحيّة/خادمٌ أقدم) — والطباعة تمضي بلاها.
  static Future<ReceiptSettings?> fetch({bool force = false}) async {
    // «كل الشركات»: إعدادات وصل شركة الطلب الموجَّه (مخبّأةٌ بمفتاحها) لا الشركة المفتوحة
    final adminId = CompanyRoute.currentKey ?? await AuthStorage.readAdminId();
    if (adminId == null || adminId.isEmpty) return null;
    final c = _cache;
    if (!force &&
        c != null &&
        c.adminId == adminId &&
        DateTime.now().difference(c.at) < _ttl) {
      return c.value;
    }
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>(
        '/api/v2/receipt-settings',
        options: Options(receiveTimeout: const Duration(seconds: 8)),
      );
      final body = r.data ?? const {};
      final data = body['data'];
      // خادمٌ قديم أمام ايرث لنك يردّ «فارغاً ناجحاً» (قائمة) — لا إعدادات.
      if (body['success'] != true || data is! Map) return null;
      final value = ReceiptSettings.fromJson(Map<String, dynamic>.from(data));
      _cache = (adminId: adminId, at: DateTime.now(), value: value);
      return value;
    } on DioException catch (e) {
      if (kDebugMode) debugPrint('[ReceiptSettingsApi] fetch: ${e.type}');
      return null;
    } catch (e) {
      if (kDebugMode) debugPrint('[ReceiptSettingsApi] fetch: $e');
      return null;
    }
  }

  /// المصمّم: جديدٌ دائماً للشركة **المفتوحة** (في «كل الشركات» لا يوجَّه — الحفظ لها وحدها في الخادم أيضاً)، وفشلٌ بنصٍّ
  /// يُعرض لا null. ويحدّث مخبأ الطباعة.
  static Future<ReceiptDesignLoad> fetchRaw() async {
    try {
      final r = await ApiClient.dio.get<dynamic>(
        '/api/v2/receipt-settings',
        options: Options(receiveTimeout: const Duration(seconds: 12)),
      );
      final body = r.data;
      final data = body is Map ? body['data'] : null;
      if (body is! Map || body['success'] != true || data is! Map) {
        final m = body is Map ? body['message'] : null;
        return ReceiptDesignLoad.failed(m is String && m.trim().isNotEmpty ? m.trim() : 'تعذّر جلب تصميم الوصل');
      }
      final value = ReceiptSettings.fromJson(Map<String, dynamic>.from(data));
      final adminId = await AuthStorage.readAdminId();
      if (adminId != null && adminId.isNotEmpty) _cache = (adminId: adminId, at: DateTime.now(), value: value);
      return ReceiptDesignLoad.ok(value);
    } on DioException catch (e) {
      if (kDebugMode) debugPrint('[ReceiptSettingsApi] fetchRaw: ${e.type}');
      return const ReceiptDesignLoad.failed('تعذّر جلب تصميم الوصل — تحقّق من الاتصال ثمّ أعد المحاولة');
    } catch (e) {
      if (kDebugMode) debugPrint('[ReceiptSettingsApi] fetchRaw: $e');
      return const ReceiptDesignLoad.failed('تعذّر جلب تصميم الوصل');
    }
  }

  /// `POST /api/v2/receipt-settings` — المصمّم يرسل الأعمدة السبعة كلّها (الغائب يمحوه الخادم أو يعيده افتراضيّاً)،
  /// والتصميم كاملاً، و`if_updated_at`، **بلا الشعار** (يبقى المحفوظ). الرفض بنصّه ورمزه ومساره (400)، والتعارض (409)،
  /// والطلب الكبير (413). النجاح يُسقط مخبأ الطباعة فيُطبع الوصل التالي بالجديد.
  static Future<ReceiptSaveResult> save(Map<String, dynamic> body) async {
    try {
      final r = await ApiClient.dio.post<dynamic>(
        '/api/v2/receipt-settings',
        data: body,
        options: Options(sendTimeout: const Duration(seconds: 20), receiveTimeout: const Duration(seconds: 20)),
      );
      final status = r.statusCode ?? 0;
      final m = r.data is Map ? Map<String, dynamic>.from(r.data as Map) : const <String, dynamic>{};
      if (status >= 200 && status < 300 && m['success'] == true) {
        clearCache();
        final design = m['design'];
        final at = m['updated_at'];
        return ReceiptSaveResult(
          ok: true,
          status: status,
          message: _text(m['message']) ?? 'تمّ حفظ تصميم الوصل',
          design: design is Map ? Map<String, dynamic>.from(design) : null,
          hasDesign: m.containsKey('design'),
          updatedAt: at,
          hasUpdatedAt: m.containsKey('updated_at'),
        );
      }
      final code = _text(m['code']);
      return ReceiptSaveResult(
        ok: false,
        status: status,
        code: code,
        path: _text(m['path']),
        message: _text(m['message']) ?? _defaultError(status, code),
      );
    } on DioException catch (e) {
      if (kDebugMode) debugPrint('[ReceiptSettingsApi] save: ${e.type} ${e.response?.statusCode}');
      final status = e.response?.statusCode;
      return ReceiptSaveResult(
        ok: false,
        status: status,
        message: status == null ? 'تعذّر الحفظ — تحقّق من الاتصال ثمّ أعد المحاولة' : _defaultError(status, null),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[ReceiptSettingsApi] save: $e');
      return const ReceiptSaveResult(ok: false, message: 'تعذّر الحفظ — أعد المحاولة');
    }
  }

  static String? _text(Object? v) => v is String && v.trim().isNotEmpty ? v.trim() : null;

  /// نصّ الرفض حين لا يرسل الخادم نصّاً (خادمٌ أقدم، أو 413 من محلّل الطلب قبل المعالج).
  static String _defaultError(int status, String? code) {
    if (code == 'STALE_DESIGN') return 'تغيّر تصميم الوصل من جهازٍ آخر بعد فتحك له — حدّث ثمّ أعد تعديلك';
    if (code == 'LAYOUT_NEWER') return 'هذا التصميم صُنع بالمصمّم الجديد — حدّث ثمّ احفظ';
    return switch (status) {
      413 => 'الطلب أكبر من المسموح — صغّر الشعار ثمّ احفظ',
      403 => 'ليس لديك صلاحيّة لتعديل تصميم الوصل',
      409 => 'تغيّر تصميم الوصل من جهازٍ آخر بعد فتحك له — حدّث ثمّ أعد تعديلك',
      >= 500 => 'تعذّر الحفظ من الخادم — أعد المحاولة',
      _ => 'تعذّر حفظ تصميم الوصل',
    };
  }

  @visibleForTesting
  static void clearCache() => _cache = null;
}

/// جلب المصمّم: الإعدادات أو نصّ الفشل.
@immutable
class ReceiptDesignLoad {
  const ReceiptDesignLoad.ok(ReceiptSettings this.settings) : error = null;
  const ReceiptDesignLoad.failed(String this.error) : settings = null;

  final ReceiptSettings? settings;
  final String? error;
}

/// نتيجة حفظ المصمّم.
@immutable
class ReceiptSaveResult {
  const ReceiptSaveResult({
    required this.ok,
    required this.message,
    this.status,
    this.code,
    this.path,
    this.design,
    this.hasDesign = false,
    this.updatedAt,
    this.hasUpdatedAt = false,
  });

  final bool ok;

  /// null = لا ردّ (الشبكة).
  final int? status;
  final String message;

  /// `LAYOUT_*` · `STALE_DESIGN` · `LAYOUT_NEWER` · `BODY_TOO_BIG` …
  final String? code;

  /// موضع الرفض في التصميم (`fields.username.pt`) — 400 وحده.
  final String? path;

  /// التصميم كما حُفظ (ردّ الخادم).
  final Map<String, dynamic>? design;

  /// الردّ يحمل `design` (حتّى null = حُذف التصميم).
  final bool hasDesign;

  /// ختم الحفظ الجديد كما أعاده الخادم (يُرسل كما هو مع الحفظ التالي).
  final Object? updatedAt;

  /// الردّ يحمل `updated_at` (خادمٌ يعرف بروتوكول التعارض).
  final bool hasUpdatedAt;

  /// تعارضٌ مع حفظٍ أحدث (جهازٌ آخر أو المصمّم الجديد) — يُعرض «تحديث».
  bool get conflict => status == 409;
}
