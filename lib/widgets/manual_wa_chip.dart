import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../services/manual_wa_prefs.dart';
import '../theme/colors.dart';

/// 2026-08-26: Chip يعرض وضع إرسال الواتساب الحالي (تلقائي/يدوي).
/// النقر عليه يبدّل الوضع لهذه العمليّة فقط (override محلّي).
///
/// إذا الأدمن ما يحبّ يبدّل يدوياً، يقدر يخلّي الـglobal setting من
/// شاشة إعدادات واتساب — والـchip يعرضه ولا يحتاج لمس.
///
/// [modeOverride] لو null → يستعمل global default من ManualWaPrefs.
/// لو مُعطى → override محلّي (لسلوك هذا الـsheet فقط).
/// [onModeChanged] يستقبل الوضع الجديد بعد التبديل.
class ManualWaChip extends StatelessWidget {
  const ManualWaChip({
    super.key,
    required this.mode,
    required this.onModeChanged,
    this.compact = false,
  });

  /// true = يدوي، false = تلقائي.
  final bool mode;
  final ValueChanged<bool> onModeChanged;

  /// compact = يعرض نصّاً مختصراً بلا subtitle (للـsheets الضيّقة).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final isManual = mode;
    final color = isManual
        ? AppColors.brandAccent // بنفسجي — يدوي (وضع خاصّ)
        : AppColors.success; // تيّل — تلقائي (الطبيعيّ)
    return Material(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onModeChanged(!isManual);
        },
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 10 : 12,
            vertical: compact ? 6 : 8,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: color.withValues(alpha: 0.3),
              width: 0.6,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isManual ? LucideIcons.smartphone : LucideIcons.zap,
                size: compact ? 12 : 13,
                color: color,
              ),
              const SizedBox(width: 6),
              Text(
                isManual ? 'وضع يدوي' : 'وضع تلقائي',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: compact ? 11 : 11.5,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
              if (!compact) ...[
                const SizedBox(width: 6),
                Container(
                  width: 1,
                  height: 10,
                  color: color.withValues(alpha: 0.25),
                ),
                const SizedBox(width: 6),
                Icon(LucideIcons.arrowRightLeft, size: 11, color: color),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// stateful wrapper يستمع لـManualWaPrefs.enabled ويعطي الـchild القيمة
/// الحاليّة + آلية التبديل المحلّي (يبدأ من الـglobal لكن يقبل override).
class ManualWaModeBuilder extends StatefulWidget {
  const ManualWaModeBuilder({super.key, required this.builder});
  final Widget Function(
          BuildContext context, bool manualMode, ValueChanged<bool> setMode)
      builder;

  @override
  State<ManualWaModeBuilder> createState() => _ManualWaModeBuilderState();
}

class _ManualWaModeBuilderState extends State<ManualWaModeBuilder> {
  bool? _override; // null = تابع global، غير null = override للـsheet

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: ManualWaPrefs.enabled,
      builder: (context, globalManual, _) {
        final current = _override ?? globalManual;
        return widget.builder(context, current, (v) {
          setState(() => _override = v);
        });
      },
    );
  }
}

/// Sheet مصغّرة تعرض معاينة الرسالة + chip للتبديل + زر إرسال.
/// تُستعمل للأزرار المباشرة (تذكير دين/تحذير انتهاء/إرسال معلومات) بدل
/// إطلاق الإرسال فوراً — الأدمن يشوف بالضبط ماذا سيرسل قبل التأكيد.
Future<ManualWaChoice?> showManualWaPreviewSheet(
  BuildContext context, {
  required String title,
  required String phone,
  required String messagePreview,
  Color accent = const Color(0xFF25D366),
}) {
  return showModalBottomSheet<ManualWaChoice>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.scrim,
    builder: (_) => _WaPreviewSheet(
      title: title,
      phone: phone,
      messagePreview: messagePreview,
      accent: accent,
    ),
  );
}

class ManualWaChoice {
  const ManualWaChoice({required this.confirmed, required this.manualMode});
  final bool confirmed;
  final bool manualMode;
}

class _WaPreviewSheet extends StatelessWidget {
  const _WaPreviewSheet({
    required this.title,
    required this.phone,
    required this.messagePreview,
    required this.accent,
  });
  final String title;
  final String phone;
  final String messagePreview;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom + 12,
          left: 16,
          right: 16,
          top: 12,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    alignment: Alignment.center,
                    child: Icon(LucideIcons.messageCircle,
                        color: accent, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textHi,
                            )),
                        const SizedBox(height: 2),
                        Text('إلى: $phone',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textMid,
                            ),
                            textDirection: TextDirection.ltr),
                      ],
                    ),
                  ),
                  IconButton(
                    icon:
                        Icon(LucideIcons.x, size: 20, color: AppColors.textMid),
                    onPressed: () => Navigator.of(context).pop(),
                    splashRadius: 20,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceInput,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border, width: 0.5),
                ),
                child: Text(
                  messagePreview,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12.5,
                    color: AppColors.textHi,
                    height: 1.6,
                  ),
                  maxLines: 8,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 12),
              ManualWaModeBuilder(
                builder: (ctx, manualMode, setMode) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: ManualWaChip(
                        mode: manualMode,
                        onModeChanged: setMode,
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      height: 46,
                      child: FilledButton.icon(
                        onPressed: () => Navigator.of(ctx).pop(
                          ManualWaChoice(
                            confirmed: true,
                            manualMode: manualMode,
                          ),
                        ),
                        icon: Icon(
                          manualMode
                              ? LucideIcons.smartphone
                              : LucideIcons.send,
                          size: 15,
                        ),
                        label: Text(
                          manualMode ? 'افتح واتسابي' : 'إرسال تلقائي',
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor:
                              manualMode ? AppColors.brandAccent : accent,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
