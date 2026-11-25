import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/update_gate.dart';
import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';

/// «تحديث جديد» يطفو (٢٥ نوفمبر — المالك: «زر يمثل وجود تحديث للتطبيق… يظهر بشكل لامع» ثمّ «رمز احلى وماتاخذ مساحه… انريده
/// الزر يطفو بشكل حركي حتى يلفت الانتباه» و«لاتنسى لون الزر بالوضع الليلي»).
///
/// دائرةٌ صغيرة فوق المحتوى (لا مكان لها في الرؤوس ولا تزيح شيئاً) — في غلاف الهاتف ([MainShell]) وغلاف الحاسبة — بصاروخٍ أبيض
/// وشارة «جديد»، تطفو صعوداً ونزولاً وتلمع (هالةٌ تنبض وبريقٌ يعبر كلّ ~٢٫٤ث). تظهر بتكبيرٍ ناعم حين يقول الخادم إنّ لهذا النظام نسخةً
/// أحدث ([UpdateGate.available] من `latest` في /api/app-gate) وتختفي حين لا؛ والنقر يفتح صفحة التطبيق في متجر هذا النظام.
/// «تقليل الحركة» ⇒ ثابتةٌ لامعة بلا طفو. الوضع الليليّ: ظلٌّ معتم لا فاتح، إطارٌ أهدأ، وهالةٌ أقوى لتُرى على الداكن.
class UpdateFloatingBubble extends StatelessWidget {
  const UpdateFloatingBubble({super.key});

  /// للصور والاختبار: مرحلة الحركة ثابتة (٠..١) بدل التكرار.
  static double? debugPhase;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<UpdateAvailable?>(
        valueListenable: UpdateGate.available,
        builder: (context, u, _) => AnimatedSwitcher(
          duration: const Duration(milliseconds: 320),
          switchInCurve: Curves.easeOutBack,
          transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
          child: u == null
              ? const SizedBox.shrink(key: ValueKey('update-none'))
              : _FloatingUpdate(key: const ValueKey('update-float'), update: u),
        ),
      );
}

class _FloatingUpdate extends StatefulWidget {
  const _FloatingUpdate({super.key, required this.update});
  final UpdateAvailable update;

  @override
  State<_FloatingUpdate> createState() => _FloatingUpdateState();
}

class _FloatingUpdateState extends State<_FloatingUpdate> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = UpdateFloatingBubble.debugPhase != null || MediaQuery.maybeDisableAnimationsOf(context) == true;
    if (still) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    final u = Uri.tryParse(widget.update.storeUrl);
    if (u == null) return;
    try {
      await launchUrl(u, mode: LaunchMode.externalApplication);
    } catch (_) {/* بلا متجرٍ على الجهاز — لا شيء */}
  }

  @override
  Widget build(BuildContext context) {
    // الوضع الليليّ (المالك: «لاتنسى لون الزر بالوضع الليلي»): الظلّ معتمٌ لا فاتح، والإطار أهدأ، والهالة أقوى لتُرى على الداكن.
    final dark = Theme.of(context).brightness == Brightness.dark;
    final still = MediaQuery.maybeDisableAnimationsOf(context) == true;
    return Semantics(
      button: true,
      label: 'تحديث جديد للتطبيق — افتح المتجر',
      onTap: _open,
      excludeSemantics: true,
      child: Tooltip(
        message: 'تحديث جديد — حدّث التطبيق من المتجر',
        excludeFromSemantics: true,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final t = UpdateFloatingBubble.debugPhase ?? _c.value;
            final wave = math.sin(2 * math.pi * t);
            final bob = still ? 0.0 : -6 * wave;
            final pulse = 0.5 - 0.5 * math.cos(2 * math.pi * t);
            final glow = AppColors.brandAccent;
            return Transform.translate(
              offset: Offset(0, bob),
              child: GestureDetector(
                key: const ValueKey('update-glow'),
                onTap: _open,
                child: SizedBox(
                  width: 64,
                  height: 64,
                  child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: AlignmentDirectional.topStart,
                          end: AlignmentDirectional.bottomEnd,
                          colors: [AppColors.brand, glow],
                        ),
                        border: Border.all(color: AppColors.onBrand.withValues(alpha: dark ? 0.30 : 0.90), width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: glow.withValues(alpha: (dark ? 0.50 : 0.35) + (dark ? 0.40 : 0.35) * pulse),
                            blurRadius: 10 + 14 * pulse,
                            spreadRadius: 1 + 3 * pulse,
                          ),
                          BoxShadow(color: AppColors.scrim.withValues(alpha: dark ? 0.55 : 0.20), blurRadius: 10, offset: Offset(0, 6 - bob / 2)),
                        ],
                      ),
                      child: ClipOval(
                        child: Stack(alignment: Alignment.center, children: [
                          Positioned.fill(
                            child: IgnorePointer(
                              child: CustomPaint(painter: _ShinePainter(progress: (t / 0.4).clamp(0.0, 1.0), on: t < 0.4)),
                            ),
                          ),
                          Transform.rotate(
                            angle: still ? 0 : 0.07 * wave,
                            child: const Icon(LucideIcons.rocket, size: 26, color: AppColors.onBrand),
                          ),
                        ]),
                      ),
                    ),
                    // شارة «جديد» على ركن الدائرة
                    PositionedDirectional(
                      top: -2,
                      end: -6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.warning,
                          borderRadius: BorderRadius.circular(R.pill),
                          border: Border.all(color: AppColors.bg, width: 1.5),
                        ),
                        child: Text('جديد', style: AppType.micro(color: AppColors.onBrand).copyWith(fontWeight: FontWeight.w700, fontSize: 10.5, height: 1.2)),
                      ),
                    ),
                  ]),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// البريق: شريطٌ أبيض مائل يعبر الدائرة في أوّل ٤٠٪ من الدورة.
class _ShinePainter extends CustomPainter {
  const _ShinePainter({required this.progress, required this.on});
  final double progress;
  final bool on;

  @override
  void paint(Canvas canvas, Size size) {
    if (!on) return;
    final w = size.width;
    final band = math.max(14.0, w * 0.35);
    final x = -band + (w + 2 * band) * progress;
    final rect = Rect.fromLTWH(x - band / 2, 0, band, size.height);
    final paint = Paint()
      ..shader = LinearGradient(colors: [
        AppColors.onBrand.withValues(alpha: 0),
        AppColors.onBrand.withValues(alpha: 0.45),
        AppColors.onBrand.withValues(alpha: 0),
      ]).createShader(rect);
    canvas.save();
    canvas.translate(x, size.height / 2);
    canvas.skew(-0.35, 0);
    canvas.translate(-x, -size.height / 2);
    canvas.drawRect(rect, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ShinePainter old) => old.progress != progress || old.on != on;
}

