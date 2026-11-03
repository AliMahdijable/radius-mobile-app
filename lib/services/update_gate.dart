import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/api_client.dart';
import '../core/platform/app_platform.dart';
import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';
import 'app_version.dart';

/// إجبار تحديث التطبيق (٣ نوفمبر — المالك: «اريد اجبار الكل على النسخه الاخر اصدار»). الخادم (server/appGate.js) يحدّد أقلّ نسخة
/// لكلّ نظام؛ التطبيق يرسل نسخته مع كلّ طلب (x-app-build) ويسأل `/api/app-gate` عند الإقلاع. نسخةٌ أقلّ — أو ردّ
/// `APP_FORCE_UPDATE` من أيّ طلب — ⇒ شاشة «حدّث التطبيق» فوق كلّ شيء، لا تُغلق، وفيها زرّ المتجر.
class UpdateRequired {
  const UpdateRequired({required this.message, required this.storeUrl, this.minBuild});
  final String message;
  final String storeUrl;
  final int? minBuild;
}

class UpdateGate {
  UpdateGate._();

  static final ValueNotifier<UpdateRequired?> required = ValueNotifier(null);

  static const _fallbackMessage = 'نسخةٌ جديدة من التطبيق متاحة ومطلوبة — حدّث التطبيق من المتجر لتكمل.';
  static const _fallbackStore = <String, String>{
    'android': 'https://play.google.com/store/apps/details?id=com.mysvcs.rad_mysvcs',
    'ios': 'https://apps.apple.com/app/id6770731907',
    'windows': 'https://apps.microsoft.com/detail/9P56SZQKPLTC',
    'macos': 'https://apps.apple.com/app/id6770731907',
  };

  static int get build => int.tryParse(AppVersion.buildNumber) ?? 0;

  @visibleForTesting
  static void debugReset() => required.value = null;

  /// عند الإقلاع: الخادم يقول أقلّ نسخة لهذا النظام. خطأٌ أو خادمٌ أقدم ⇒ لا شيء (لا حجب بالظنّ).
  static Future<void> check() async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>('/api/app-gate');
      final d = r.data?['data'];
      if (r.data?['success'] != true || d is! Map || d['enabled'] != true) return;
      final p = AppPlatform.deviceLabel;
      final min = d['min'] is Map ? (d['min'] as Map)[p] : null;
      final minBuild = min is num ? min.toInt() : int.tryParse('$min');
      if (minBuild == null || build <= 0 || build >= minBuild) return;
      final store = d['store'] is Map ? (d['store'] as Map)[p]?.toString() : null;
      required.value = UpdateRequired(
        message: (d['message']?.toString().trim().isNotEmpty ?? false) ? d['message'].toString() : _fallbackMessage,
        storeUrl: store ?? _fallbackStore[p] ?? _fallbackStore['android']!,
        minBuild: minBuild,
      );
    } catch (e) {
      if (!kReleaseMode) debugPrint('[UpdateGate] check: $e');
    }
  }

  /// ردّ أيّ طلب (ApiClient.onResponse): `409 {code: APP_FORCE_UPDATE}` ⇒ الشاشة.
  static bool fromResponse(int? status, Object? data) {
    if (status != 409 || data is! Map || data['code'] != 'APP_FORCE_UPDATE') return false;
    final p = AppPlatform.deviceLabel;
    final min = data['min_build'];
    required.value = UpdateRequired(
      message: (data['message']?.toString().trim().isNotEmpty ?? false) ? data['message'].toString() : _fallbackMessage,
      storeUrl: data['store_url']?.toString() ?? _fallbackStore[p] ?? _fallbackStore['android']!,
      minBuild: min is num ? min.toInt() : null,
    );
    return true;
  }
}

/// يلفّ التطبيق كلّه (MaterialApp.builder): حين يُطلب التحديث تغطّي شاشته كلّ شيء ولا تُغلق.
class UpdateGateOverlay extends StatelessWidget {
  const UpdateGateOverlay({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<UpdateRequired?>(
        valueListenable: UpdateGate.required,
        builder: (_, req, __) => req == null
            ? child
            : Stack(children: [
                // ما تحتها لا يُلمس ولا يُقرأ بقارئ الشاشة
                ExcludeSemantics(child: AbsorbPointer(child: child)),
                Positioned.fill(child: UpdateRequiredView(req: req)),
              ]),
      );
}

class UpdateRequiredView extends StatelessWidget {
  const UpdateRequiredView({super.key, required this.req});
  final UpdateRequired req;

  @override
  Widget build(BuildContext context) {
    final current = AppVersion.displayVersion;
    return Material(
      color: AppColors.bg,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Sp.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(color: AppColors.brand.withValues(alpha: 0.12), shape: BoxShape.circle),
                  child: Icon(LucideIcons.download, size: 34, color: AppColors.brand),
                ),
                const SizedBox(height: Sp.lg),
                Text('تحديثٌ مطلوب', textAlign: TextAlign.center, style: AppType.title(color: AppColors.textHi)),
                const SizedBox(height: Sp.sm),
                Text(req.message, textAlign: TextAlign.center, style: AppType.body(color: AppColors.textBody)),
                const SizedBox(height: Sp.sm),
                Text(
                  'نسختك: $current${req.minBuild != null ? ' — المطلوبة: ${req.minBuild} أو أحدث' : ''}',
                  textAlign: TextAlign.center,
                  textDirection: TextDirection.rtl,
                  style: AppType.micro(color: AppColors.textMid),
                ),
                const SizedBox(height: Sp.xl),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.brand,
                      foregroundColor: AppColors.onBrand,
                      minimumSize: const Size.fromHeight(50),
                    ),
                    onPressed: () => launchUrl(Uri.parse(req.storeUrl), mode: LaunchMode.externalApplication),
                    icon: const Icon(LucideIcons.download, size: 18),
                    label: const Text('حدّث الآن'),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
