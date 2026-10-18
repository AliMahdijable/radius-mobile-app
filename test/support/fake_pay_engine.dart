import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:rad_mysvcs/screens/topup/topup_pay_page.dart';
import 'package:rad_mysvcs/theme/colors.dart';
import 'package:rad_mysvcs/theme/spacing.dart';
import 'package:rad_mysvcs/theme/typography.dart';

/// متصفّحٌ بديل لصفحة الدفع في الاختبار — منصّة WebView لا تعمل في
/// `flutter test`. يرسم صفحةً محايدة، ويحاكي التنقّل بـ[navigate] و[urlChanged]
/// كما يبلّغه الـWebView الحقيقيّ (`onNavigationRequest` · `onUrlChange`).
class FakePayEngine implements PayWebEngine {
  FakePayEngine(this.cb) {
    last = this;
  }

  /// آخر متصفّحٍ أُنشئ — الصفحة تنشئ واحداً لكلّ فتح.
  static FakePayEngine? last;

  final PayWebCallbacks cb;
  final opened = <Uri>[];
  int wipes = 0;
  int reloads = 0;

  /// تنقّلٌ يوشك أن يبدأ — `true` = حُمِّل، `false` = مُنع (التقاطٌ أو حجب).
  bool navigate(String url, {bool mainFrame = true}) =>
      cb.onNavigation(url, mainFrame: mainFrame);

  /// الرابط تغيّر بلا طلب تنقّل (هاش، أو صفحةٌ بدأت).
  void urlChanged(String url) => cb.onUrl(url);

  void failLoad() => cb.onLoadError();

  @override
  Widget view(BuildContext context) => const _FakePayView();

  @override
  Future<void> open(Uri url) async {
    opened.add(url);
    cb.onProgress(100);
  }

  @override
  Future<void> reload() async {
    reloads++;
    cb.onProgress(100);
  }

  @override
  Future<void> wipe() async {
    wipes++;
  }
}

/// صفحة دفعٍ محايدة — لا تحاكي واجهة أحد، تكفي لرؤية إطار الصفحة حولها.
class _FakePayView extends StatelessWidget {
  const _FakePayView();

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return ColoredBox(
      color: AppColors.bg,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(Sp.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.smartphone, size: 40, color: AppColors.textLow),
              const SizedBox(height: Sp.md),
              Text('صفحة الدفع',
                  style: AppType.cardTitleBold(color: AppColors.textMid)),
              const SizedBox(height: Sp.xs),
              Text('رقم المحفظة ثمّ رمز التحقّق',
                  style: AppType.body(color: AppColors.textLow)),
            ],
          ),
        ),
      ),
    );
  }
}
