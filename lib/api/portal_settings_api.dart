import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

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

/// Portal settings API — branding + packages customization.
class PortalSettingsApi {
  PortalSettingsApi._();

  static Future<Branding> getBranding() async {
    try {
      final r =
          await ApiClient.dio.get<Map<String, dynamic>>('/api/v2/admin/branding');
      final body = r.data ?? const {};
      final b = body['branding'];
      if (b is Map) {
        return Branding.fromJson(Map<String, dynamic>.from(b));
      }
      return Branding.empty;
    } on DioException catch (e) {
      _log('branding (GET)', e);
      return Branding.empty;
    } catch (e) {
      _log('branding (GET)', e);
      return Branding.empty;
    }
  }

  static Future<bool> saveBranding(Branding b) async {
    try {
      final r = await ApiClient.dio.put<Map<String, dynamic>>(
        '/api/v2/admin/branding',
        data: b.toJson(),
      );
      return r.statusCode == 200 && r.data?['success'] == true;
    } on DioException catch (e) {
      _log('branding (PUT)', e);
      return false;
    } catch (e) {
      _log('branding (PUT)', e);
      return false;
    }
  }

  static Future<List<PortalPackage>> getPackages() async {
    try {
      final r = await ApiClient.dio
          .get<Map<String, dynamic>>('/api/v2/admin/portal-packages');
      final body = r.data ?? const {};
      final list = body['packages'];
      if (list is! List) return const [];
      return list
          .whereType<Map>()
          .map((m) => PortalPackage.fromJson(Map<String, dynamic>.from(m)))
          .whereType<PortalPackage>()
          .toList();
    } on DioException catch (e) {
      _log('portal-packages (GET)', e);
      return const [];
    } catch (e) {
      _log('portal-packages (GET)', e);
      return const [];
    }
  }

  /// PUT عام — يقبل حقول جزئية (displayName, description, imageUrl,
  /// displayOrder, isHidden). null = مسح القيمة على السيرفر.
  static Future<bool> updatePackage(
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
      return r.statusCode == 200 && r.data?['success'] == true;
    } on DioException catch (e) {
      _log('portal-packages (PUT $profileId)', e);
      return false;
    } catch (e) {
      _log('portal-packages (PUT $profileId)', e);
      return false;
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
}

// ─── helpers ──────────────────────────
String? _s(dynamic v) {
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

void _log(String tag, Object e) {
  if (kDebugMode) debugPrint('[PortalSettingsApi] $tag: $e');
}
