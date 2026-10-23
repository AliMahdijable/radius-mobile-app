import 'package:flutter/material.dart';

import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../platform/desktop_layout.dart';

/// كلّ ورقةٍ في التطبيق تُفتح من هنا: على الهاتف `showModalBottomSheet` كما هي حرفاً، وعلى الحاسبة
/// (نافذةٌ عريضة) نافذةٌ في وسط الشاشة بعرضٍ مريح — ورقةٌ تصعد من أسفل شاشةٍ عريضة تبدو هاتفاً
/// مكبَّراً، والفأرة بعيدةٌ عنها. المحتوى نفسه في الحالتين؛ [DesignSheet] يقرأ [DeskDialogScope]
/// فيرسم زواياه الأربع ويُسقط مقبض السحب.
Future<T?> showAppSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Color? backgroundColor,
  Color? barrierColor,
  bool isScrollControlled = false,
  bool useSafeArea = false,
  ShapeBorder? shape,
  bool useRootNavigator = false,
  bool enableDrag = true,
  bool isDismissible = true,
}) {
  if (DesktopLayout.wide(context)) {
    return showDialog<T>(
      context: context,
      barrierColor: barrierColor ?? AppColors.scrim,
      barrierDismissible: isDismissible,
      // فوق القائمة الجانبيّة والشريط العلويّ معاً — نافذةٌ واحدة تخصّ الشاشة كلّها.
      useRootNavigator: true,
      builder: (ctx) => DeskSheetDialog(child: builder(ctx)),
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    builder: builder,
    backgroundColor: backgroundColor,
    barrierColor: barrierColor,
    isScrollControlled: isScrollControlled,
    useSafeArea: useSafeArea,
    shape: shape,
    useRootNavigator: useRootNavigator,
    enableDrag: enableDrag,
    isDismissible: isDismissible,
  );
}

/// إطار الورقة حين تُفتح نافذةً على الحاسبة: بعرض ٥٦٠ وسط الشاشة، زواياها الأربع مدوّرة، وارتفاعها
/// لا يتجاوز ٨٨٪ من النافذة. ما في داخلها يقيس MediaQuery بعرض النافذة الصغيرة لا الشاشة.
class DeskSheetDialog extends StatelessWidget {
  const DeskSheetDialog({super.key, required this.child});

  final Widget child;

  static const double width = 560;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final mq = MediaQuery.of(context);
    final maxH = mq.size.height * 0.88;
    final w = mq.size.width - 2 * Sp.xl < width ? mq.size.width - 2 * Sp.xl : width;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: w, maxHeight: maxH),
        child: Material(
          type: MaterialType.transparency,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(R.card),
            child: MediaQuery(
              data: mq.copyWith(
                size: Size(w, maxH),
                padding: EdgeInsets.zero,
                viewPadding: EdgeInsets.zero,
                viewInsets: EdgeInsets.zero,
              ),
              child: DeskDialogScope(child: child),
            ),
          ),
        ),
      ),
    );
  }
}
