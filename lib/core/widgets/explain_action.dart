// `hide TextDirection`: الحزمة تصدّر نوع intl الذي يحجب نوع dart:ui.
import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/ai_api.dart';
import '../../screens/assistant/assistant_sheet.dart';
import '../../services/ai_assistant_state.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';

export '../../api/ai_api.dart' show ExplainRequest;

/// «اشرحلي» — مدخل المساعد الذكيّ عند الخطأ.
///
/// يظهر **فقط** حين يقول الخادم إنّ المساعد مفتوحٌ لهذا الحساب
/// ([AiAssistantState.canExplain]) — وإلّا لا أثر له إطلاقاً، ولا يتغيّر
/// شيءٌ في الإشعار (لا مدّةٌ أطول ولا مساحة). والنقر يفتح نافذة المساعد
/// بالخطأ كما ظهر ([AssistantSheet.showExplain]) — لا عمليّة تُنفَّذ.

/// أقلّ مدّة لإشعارٍ يحمل «اشرحلي» — ليُقرأ الخطأ ويُضغط الزرّ.
const kExplainSnackDuration = Duration(seconds: 6);

/// يفتح «اشرحلي» من أيّ سياقٍ تحت `Navigator`.
Future<void> openExplain(BuildContext context, ExplainRequest request) {
  HapticFeedback.selectionClick();
  return AssistantSheet.showExplain(context, request);
}

/// زرّ «اشرحلي» المضغوط فوق سطحٍ ملوّن (إشعار الخطأ الأحمر) — طبقات
/// `onBrand*` ثابتة في الوضعين. منطقة اللمس ٤٤ على الأقلّ والحبّة ٣٢.
class ExplainPill extends StatelessWidget {
  const ExplainPill({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Semantics(
      button: true,
      label: 'ai.explain_a11y'.tr(),
      // الأبناء مستبعدون — فالنقر يُعلَن هنا وإلّا لا يفعّله قارئ الشاشة.
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
          child: Center(
            widthFactor: 1,
            child: Material(
              color: AppColors.onBrandFill2,
              shape: const StadiumBorder(
                side: BorderSide(color: AppColors.onBrandTertiary),
              ),
              child: InkWell(
                onTap: onTap,
                customBorder: const StadiumBorder(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: Sp.md, vertical: 7),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(LucideIcons.sparkles,
                          size: 14, color: AppColors.onBrand),
                      const SizedBox(width: Sp.xs),
                      Text(
                        'ai.explain'.tr(),
                        maxLines: 1,
                        style: AppType.bodyBold(color: AppColors.onBrand),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// محتوى شريط `SnackBar` (شاشات الحساب والدخول) يحمل «اشرحلي» حين يتوفّر.
///
/// الزرّ داخل المحتوى لا `SnackBarAction`: الإجراء يُحسم عند بناء الشريط،
/// وحالة المساعد قد تصل بعده بلحظة (أوّل خطأ في الجلسة) — فالمحتوى يستمع
/// للحالة ويُظهره متى عُرفت. وبلا [request] (رسالةٌ محلّيّة) نصٌّ وحده كما كان.
class ExplainSnackContent extends StatelessWidget {
  const ExplainSnackContent({
    super.key,
    required this.message,
    required this.style,
    required this.request,
    required this.onExplain,
  });

  final String message;

  /// `null` = نمط الشريط نفسه (`SnackBarTheme`) كما كان `Text(msg)`.
  final TextStyle? style;
  final ExplainRequest? request;
  final VoidCallback onExplain;

  @override
  Widget build(BuildContext context) {
    final text = Text(message, style: style);
    if (request == null) return text;
    return ValueListenableBuilder<AiStatus?>(
      valueListenable: AiAssistantState.gate,
      builder: (context, s, _) {
        if (!(s?.canExplain ?? false)) return text;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            text,
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: ExplainPill(onTap: onExplain),
            ),
          ],
        );
      },
    );
  }
}

/// شريطٌ عائم يحمل «اشرحلي» على خطأ الخادم حين يتوفّر — للشاشات التي تبني
/// `SnackBar` بنفسها (التحويل، ربط الواتساب، الموظّفون). الخطأ
/// يُستنتج من الردّ المرفوض الذي يعرضه الشريط ([AiAssistantState.explainFor])
/// أو يُعطى صريحاً ([explain]). رسالةٌ محلّيّة، أو نجاح، أو المساعد مطفأ ⇒
/// الشريط كما كان حرفيّاً (النصّ والنمط والمدّة).
SnackBar explainableSnackBar(
  BuildContext context,
  String message, {
  required bool error,
  required Color backgroundColor,
  TextStyle? style,
  ShapeBorder? shape,
  EdgeInsetsGeometry? margin,
  Duration duration = const Duration(milliseconds: 4000),
  ExplainRequest? explain,
}) {
  final ask = error ? (explain ?? AiAssistantState.explainFor(message)) : null;
  return SnackBar(
    content: ask == null
        ? Text(message, style: style)
        : ExplainSnackContent(
            message: message,
            style: style,
            request: ask,
            onExplain: () {
              ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
              if (context.mounted) openExplain(context, ask);
            },
          ),
    backgroundColor: backgroundColor,
    behavior: SnackBarBehavior.floating,
    shape: shape,
    margin: margin,
    duration: explainSnackDuration(duration, ask),
  );
}

/// مدّة شريطٍ قد يحمل «اشرحلي»: أطول إن كان الزرّ ظاهراً **الآن** — والمساعد
/// مطفأً تبقى المدّة كما هي حرفيّاً.
Duration explainSnackDuration(Duration base, ExplainRequest? request) =>
    request != null &&
            AiAssistantState.canExplain &&
            base < kExplainSnackDuration
        ? kExplainSnackDuration
        : base;
