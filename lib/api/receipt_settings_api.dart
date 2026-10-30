import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../services/auth_storage.dart';
import 'api_client.dart';
import 'company_route.dart';

/// إعدادات الوصل كما يحفظها **مصمّم الويب** («قوالب الطباعة» في `/v2` ←
/// جدول `receipt_settings` بـ`POST /api/v2/receipt-settings`).
///
/// منذ ٢٤ أكتوبر يطبع التطبيق **كلّ** وصولاته بها لكلّ المزوّدين، كالموقع («مثل الويب» —
/// المالك): الترويسة والتذييل وما يظهر من الأقسام ورمز QR والطباعة التلقائيّة وعرض ورق
/// الكاشير. قوالب `print_templates` القديمة (الكلاسيك) لا يقرؤها الموقع ولا يكتبها أحد منذ
/// النقل. نوع الخطّ والمحاذاة والإطارات لطباعة الويب وحدها؛ أبعاد الكاشير (الحواشي وحجم الخطّ والشعار وQR
/// والمسافات) يطبعها التطبيق كالموقع منذ ٣٠ أكتوبر.
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
  static ReceiptSettings fromJson(Map<String, dynamic> j) {
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

    return ReceiptSettings(
      shopName: _str(j['shop_name']),
      shopAddress: _str(j['shop_address']),
      shopPhone: _str(j['shop_phone']),
      footerText: _str(j['footer_text']),
      logo: decodeLogo(j['logo_data']),
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

  @visibleForTesting
  static void clearCache() => _cache = null;
}
