import 'package:flutter/material.dart';

import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';

/// زرّ «Sign in with Apple» وفق إرشادات Apple (HIG): شعار Apple + نصّ،
/// أسود في الوضع الفاتح وأبيض في الداكن، بنفس حجم زرّ Google وزواياه
/// ومكانه قبله. يتبع السطوع الفعليّ للواجهة (مبدّل المظهر داخل التطبيق).
class AppleSignInButton extends StatelessWidget {
  const AppleSignInButton({super.key, required this.label, required this.onTap, this.loading = false});
  final String label;
  final VoidCallback? onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final dark = AppColors.isDark;
    final bg = dark ? Colors.white : Colors.black;
    final fg = dark ? Colors.black : Colors.white;
    final enabled = onTap != null && !loading;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: SizedBox(
        height: 54,
        child: Opacity(
          opacity: enabled || loading ? 1 : 0.5,
          child: Material(
            color: bg,
            borderRadius: BorderRadius.circular(R.md),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: enabled ? onTap : null,
              child: Center(
                child: loading
                    ? SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.2, color: fg),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.apple, color: fg, size: 24),
                          const SizedBox(width: Sp.sm),
                          Flexible(
                            child: Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppType.button(color: fg),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// خانة طريقة دخولٍ بأيقونةٍ فقط داخل صفٍّ متساوٍ (Apple · Google · موظّف): نفس
/// الحجم والبروز للجميع (App Store 4.8 — Apple ليس أصغر من Google)، وتسميةٌ
/// صغيرة تحت الخانة لا داخلها (زرّ Apple «شعارٌ فقط» كما يسمح HIG).
class AccountMethodTile extends StatelessWidget {
  const AccountMethodTile({
    super.key,
    required this.icon,
    required this.caption,
    required this.semanticLabel,
    required this.onTap,
    this.loading = false,
    this.filled = false,
  });

  final Widget icon;
  final String caption;
  final String semanticLabel;
  final VoidCallback? onTap;
  final bool loading;

  /// Apple: أسود بالفاتح وأبيض بالداكن (HIG). غيره: سطحٌ بحدّ.
  final bool filled;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final dark = AppColors.isDark;
    final bg = filled ? (dark ? Colors.white : Colors.black) : AppColors.surface;
    final fg = filled ? (dark ? Colors.black : Colors.white) : AppColors.textHi;
    final enabled = onTap != null && !loading;
    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Opacity(
            opacity: enabled || loading ? 1 : 0.5,
            child: Material(
              color: bg,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(R.md),
                side: filled ? BorderSide.none : BorderSide(color: AppColors.borderStrong),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: enabled ? onTap : null,
                child: SizedBox(
                  height: 46,
                  width: double.infinity,
                  child: Center(
                    child: loading
                        ? SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.2, color: fg),
                          )
                        : IconTheme(data: IconThemeData(color: fg, size: 22), child: icon),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: Sp.x6),
          Text(caption, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 12.5)),
        ],
      ),
    );
  }
}
