import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../services/auth_storage.dart';
import 'api_client.dart';
import 'company_route.dart';

/// إعدادات الوصل كما يحفظها **مصمّم الويب** («قوالب الطباعة» في `/v2` ←
/// جدول `receipt_settings` بـ`POST /api/v2/receipt-settings`).
///
/// ⚠️ ليست قوالب `print_templates` التي يعرضها التطبيق للساس
/// ([PrintTemplatesApi]): تلك لا يكتبها اليوم أيّ عميل منشور، وحساب ايرث لنك
/// (`earthlink:<idx>`) جديدٌ في Pro فلا قالب له أصلاً — فكانت شاشته «لم يُنشَأ
/// بعد» دائماً وما يصمّمه المالك على الويب لا يصل التطبيق. ايرث لنك تقرأ هذه.
///
/// التطبيق يأخذ منها ما يرسمه وصله (الترويسة والتذييل)؛ الألوان والخطوط
/// والهوامش والمحاذاة لطباعة الويب وحدها.
@immutable
class ReceiptSettings {
  const ReceiptSettings({
    this.shopName,
    this.shopAddress,
    this.shopPhone,
    this.footerText,
    this.logo,
    this.showLogo = true,
    this.showShopInfo = true,
    this.showFooter = true,
  });

  final String? shopName;
  final String? shopAddress;
  final String? shopPhone;
  final String? footerText;

  /// الشعار مفكوكاً من data URL — PNG أو JPEG وحدهما (ما يُرسم بلا مفاجآت).
  final Uint8List? logo;

  /// أقسام الوصل في `design` (الغائب = ظاهر، كافتراض الويب).
  final bool showLogo;
  final bool showShopInfo;
  final bool showFooter;

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
    return ReceiptSettings(
      shopName: _str(j['shop_name']),
      shopAddress: _str(j['shop_address']),
      shopPhone: _str(j['shop_phone']),
      footerText: _str(j['footer_text']),
      logo: decodeLogo(j['logo_data']),
      showLogo: flag('show_logo'),
      showShopInfo: flag('show_shop_info'),
      showFooter: flag('show_footer'),
    );
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
