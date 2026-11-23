import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/field_team_api.dart';
import '../../core/util/bidi.dart';
import '../../core/util/phone.dart';
import '../../core/util/server_time.dart';
import '../../core/widgets/app_sheet.dart';
import '../../core/widgets/design_sheet.dart';
import '../../core/widgets/sheet_scaffold.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';

/// قطعٌ مشتركة لقسم «الصيانة والمبيعات» — بألوان الموقع ومعانيه (7ccfb8e): لون الحال، شرائط المراحل، الأحرف، التواصل.

/// لون الحال (الموقع: STATUS_TONE).
AppTone fieldStatusTone(String status) => switch (status) {
      'new' => AppTone.warning,
      'assigned' => AppTone.brand,
      'on_way' || 'working' => AppTone.info,
      'done' => AppTone.success,
      'failed' => AppTone.danger,
      _ => AppTone.neutral,
    };

/// «منذ…» بالعربيّة من لحظة الخادم.
String fieldAgo(DateTime? at) => timeAgoAr(at);

/// أوّل حرفين من الاسم (أحمد علي ⇒ أع).
String fieldInitials(String name) {
  final w = name.trim().split(RegExp(r'\s+')).where((x) => x.isNotEmpty).take(2).map((x) => x.characters.first).join();
  return w.isEmpty ? '؟' : w;
}

/// رابط الخريطة: الإحداثيّات إن وُجدت، وإلّا العنوان بحثاً.
String? fieldMapsUrl(({double lat, double lng})? loc, String? address) {
  if (loc != null) return 'https://www.google.com/maps/search/?api=1&query=${loc.lat},${loc.lng}';
  final a = (address ?? '').trim();
  if (a.isEmpty) return null;
  return 'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(a)}';
}

/// كلمة مرورٍ مقترحة: ٨ حروفٍ وأرقام تُقرأ بلا لبس (بلا 0/o و1/l/i) — كالموقع suggestPassword.
String fieldSuggestPassword([math.Random? rnd]) {
  const abc = 'abcdefghjkmnpqrstuvwxyz23456789';
  final r = rnd ?? math.Random.secure();
  return List.generate(8, (_) => abc[r.nextInt(abc.length)]).join();
}

/// رسالة بيانات الدخول للفنّي (نسخٌ أو واتساب) — نصّ الموقع credentialsText حرفاً.
String fieldCredentialsText(String name, String username, String password) => [
      'أهلاً $name،',
      'حسابك في تطبيق فريق الصيانة والمبيعات:',
      'الرابط: $kFieldTeamAppUrl',
      'اسم الدخول: $username',
      'كلمة المرور: $password',
      'افتح الرابط من هاتفك، ثمّ «إضافة إلى الشاشة الرئيسية» ليصير تطبيقاً تصلك عليه المهامّ.',
    ].join('\n');

/// اتّصالٌ بالرقم.
Future<void> fieldCall(BuildContext context, String phone) async {
  try {
    final ok = await launchUrl(Uri(scheme: 'tel', path: phone.trim()));
    if (!ok && context.mounted) showSheetSnack(context, 'تعذّر فتح الاتّصال', isError: true);
  } catch (_) {
    if (context.mounted) showSheetSnack(context, 'تعذّر فتح الاتّصال', isError: true);
  }
}

/// رابطٌ خارجيّ (واتساب، الخريطة).
Future<void> fieldOpenUrl(BuildContext context, String url, {String failText = 'تعذّر فتح الرابط'}) async {
  try {
    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) showSheetSnack(context, failText, isError: true);
  } catch (_) {
    if (context.mounted) showSheetSnack(context, failText, isError: true);
  }
}

/// واتساب برقمه الدوليّ (waPhone — قاعدة الخادم والموقع نفسها)، ومعه نصٌّ اختياريّ. بلا رقم ⇒ واتساب يختار المحادثة.
Future<void> fieldWhatsApp(BuildContext context, String? phone, {String? text}) {
  final to = waPhone(phone ?? '');
  final q = text == null ? '' : '?text=${Uri.encodeComponent(text)}';
  return fieldOpenUrl(context, 'https://wa.me/$to$q', failText: 'تعذّر فتح واتساب');
}

/// ورقةٌ بطقم التطبيق (كـ«المبيعات»): لوحٌ شفّاف وستارة اللوحة وحدود الأمان.
Future<T?> showFieldSheet<T>(BuildContext context, Widget sheet) => showAppSheet<T>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: AppColors.scrim,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => sheet,
    );

/// إطار بطاقةٍ كبطاقات القسم: سطح، حدّ، زوايا.
class FieldCard extends StatelessWidget {
  const FieldCard({super.key, required this.child, this.padding = const EdgeInsets.all(Sp.lg), this.dim = false});
  final Widget child;
  final EdgeInsets padding;

  /// موقوفٌ (شخصٌ أو نوع) ⇒ بطاقةٌ أخفت.
  final bool dim;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Opacity(
      opacity: dim ? 0.78 : 1,
      child: Container(
        width: double.infinity,
        padding: padding,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(R.lg),
          border: Border.all(color: AppColors.border),
        ),
        child: child,
      ),
    );
  }
}

/// رأس قسمٍ في بطاقة: أيقونةٌ بلونها، والعنوان، وسطرٌ خافت اختياريّ.
class FieldSectionHead extends StatelessWidget {
  const FieldSectionHead({super.key, required this.icon, required this.title, this.tone = AppTone.brand, this.desc});
  final IconData icon;
  final String title;
  final AppTone tone;
  final String? desc;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      FieldIconBox(icon: icon, tone: tone, size: 34),
      const SizedBox(width: Sp.md),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: AppType.bodyBold(color: AppColors.textHi)),
          if ((desc ?? '').isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(desc!, style: AppType.micro(color: AppColors.textMid).copyWith(height: 1.5)),
          ],
        ]),
      ),
    ]);
  }
}

/// مربّع أيقونةٍ بخلفيّة لونه الخفيفة.
class FieldIconBox extends StatelessWidget {
  const FieldIconBox({super.key, required this.icon, this.tone = AppTone.brand, this.size = 40, this.round = false});
  final IconData icon;
  final AppTone tone;
  final double size;
  final bool round;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tone.softBg,
        shape: round ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: round ? null : BorderRadius.circular(R.md),
      ),
      child: Icon(icon, size: size * 0.46, color: tone.onSoft),
    );
  }
}

/// حبّة حالٍ أو نوع: نقطةٌ اختياريّة بلون العائلة ثمّ النصّ (يلتفّ لسطرين ولا يُقصّ).
class FieldPill extends StatelessWidget {
  const FieldPill({super.key, required this.label, this.tone = AppTone.neutral, this.icon, this.dot = false});
  final String label;
  final AppTone tone;
  final IconData? icon;
  final bool dot;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Sp.sm, vertical: 3),
      decoration: BoxDecoration(
        color: tone.softBg,
        borderRadius: BorderRadius.circular(R.pill),
        border: Border.all(color: tone.softBorder),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (dot) ...[
          Container(width: 6, height: 6, decoration: BoxDecoration(color: tone.fill, shape: BoxShape.circle)),
          const SizedBox(width: 5),
        ] else if (icon != null) ...[
          Icon(icon, size: 12, color: tone.onSoft),
          const SizedBox(width: 4),
        ],
        Flexible(
          child: Text(label, maxLines: 2, style: AppType.micro(color: tone.onSoft).copyWith(fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }
}

/// حبّة حال المهمّة بلونها ونقطتها.
class FieldStatusPill extends StatelessWidget {
  const FieldStatusPill({super.key, required this.status, required this.label});
  final String status;
  final String label;

  @override
  Widget build(BuildContext context) => FieldPill(label: label, tone: fieldStatusTone(status), dot: true);
}

/// شرائط المراحل الأربع (مُسندة ← في الطريق ← قيد العمل ← منجزة). لا شيء لما خرج منها (تعذّرت/ملغاة).
class FieldStageBars extends StatelessWidget {
  const FieldStageBars({super.key, required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final at = fieldStepAt(status);
    if (at == null) return const SizedBox.shrink();
    final fill = status == 'done' ? AppColors.success : AppColors.brandAccent;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      for (var i = 0; i < kFieldSteps.length; i++) ...[
        if (i > 0) const SizedBox(width: 3),
        Container(
          width: 16,
          height: 5,
          decoration: BoxDecoration(color: i <= at ? fill : AppColors.border, borderRadius: BorderRadius.circular(R.pill)),
        ),
      ],
    ]);
  }
}

/// صورة الاسم بأحرفه، ونقطة الحال (نشِطٌ الآن · غائب) حين تُعرف.
class FieldAvatar extends StatelessWidget {
  const FieldAvatar({super.key, required this.name, this.size = 40, this.live});
  final String name;
  final double size;

  /// true نشِطٌ الآن · false غائب · null بلا نقطة.
  final bool? live;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final dot = (size * 0.28).clamp(9.0, 13.0);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(clipBehavior: Clip.none, children: [
        Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: AppColors.brandSoftBg, shape: BoxShape.circle),
          child: Text(
            fieldInitials(name),
            maxLines: 1,
            style: (size >= 44 ? AppType.bodyBold(color: AppColors.brandOnSoft) : AppType.microBold(color: AppColors.brandOnSoft)),
          ),
        ),
        if (live != null)
          PositionedDirectional(
            end: -1,
            bottom: -1,
            child: Container(
              width: dot,
              height: dot,
              decoration: BoxDecoration(
                color: live! ? AppColors.success : AppColors.textLow,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.surface, width: 2),
              ),
            ),
          ),
      ]),
    );
  }
}

/// حالةٌ وسط الصفحة: أيقونةٌ وعنوانٌ وسطرٌ وزرٌّ اختياريّ.
class FieldCenterState extends StatelessWidget {
  const FieldCenterState({super.key, required this.icon, required this.title, this.sub = '', this.action, this.tone = AppTone.brand});
  final IconData icon;
  final String title;
  final String sub;
  final Widget? action;
  final AppTone tone;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Sp.huge, horizontal: Sp.md),
      child: Column(children: [
        FieldIconBox(icon: icon, tone: tone, size: 64, round: true),
        const SizedBox(height: Sp.md),
        Text(title, textAlign: TextAlign.center, style: AppType.bodyStrong(color: AppColors.textHi)),
        if (sub.isNotEmpty) ...[
          const SizedBox(height: Sp.xs),
          Text(sub, textAlign: TextAlign.center, style: AppType.muted(color: AppColors.textMid).copyWith(height: 1.55)),
        ],
        if (action != null) ...[const SizedBox(height: Sp.md), action!],
      ]),
    );
  }
}

/// زرّ تواصلٍ كبير بلون عائلته (اتّصال · واتساب · الخريطة).
class FieldQuickLink extends StatelessWidget {
  const FieldQuickLink({super.key, required this.icon, required this.label, required this.tone, required this.onTap});
  final IconData icon;
  final String label;
  final AppTone tone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Material(
      color: tone.softBg,
      borderRadius: BorderRadius.circular(R.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(R.md),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Sp.sm, vertical: Sp.sm),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: 16, color: tone.onSoft),
              const SizedBox(width: Sp.x6),
              Flexible(child: Text(label, maxLines: 1, style: AppType.label(color: tone.onSoft).copyWith(fontWeight: FontWeight.w700))),
            ]),
          ),
        ),
      ),
    );
  }
}

/// زرّ أيقونةٍ صغير بإطار (اتّصال/واتساب الفنّي).
class FieldIconButton extends StatelessWidget {
  const FieldIconButton({super.key, required this.icon, required this.tooltip, required this.onTap, this.tone = AppTone.brand});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final AppTone tone;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Tooltip(
      message: tooltip,
      child: Material(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(R.md),
          side: BorderSide(color: AppColors.border),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(R.md),
          onTap: onTap,
          child: SizedBox(width: 40, height: 40, child: Icon(icon, size: 18, color: tone.fill)),
        ),
      ),
    );
  }
}

/// زرٌّ صغير بإطارٍ ونصّ (تعديل · كلمة المرور · حذف · إعادة فتح…).
class FieldOutlineButton extends StatelessWidget {
  const FieldOutlineButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.tone = AppTone.brand,
    this.busy = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final AppTone tone;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final fg = tone == AppTone.danger ? AppColors.error : (tone == AppTone.brand ? AppColors.brand : tone.fill);
    return OutlinedButton(
      onPressed: busy ? null : onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: fg,
        side: BorderSide(color: tone == AppTone.danger ? AppColors.dangerSoftBorder : AppColors.border),
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: Sp.md),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.md)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (busy) const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) else Icon(icon, size: 16),
        const SizedBox(width: Sp.x6),
        Flexible(child: Text(label, maxLines: 1, style: AppType.label(color: fg).copyWith(fontWeight: FontWeight.w700))),
      ]),
    );
  }
}

/// زرٌّ ممتلئ أساسيّ صغير (مهمّة جديدة · إضافة للفريق · نوع جديد · إسناد).
class FieldFilledButton extends StatelessWidget {
  const FieldFilledButton({super.key, required this.icon, required this.label, required this.onTap, this.busy = false});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return FilledButton(
      onPressed: busy ? null : onTap,
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.brand,
        foregroundColor: AppColors.onBrand,
        disabledBackgroundColor: AppColors.border,
        minimumSize: const Size(0, 42),
        padding: const EdgeInsets.symmetric(horizontal: Sp.md),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.md)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (busy)
          const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onBrand))
        else
          Icon(icon, size: 16),
        const SizedBox(width: Sp.x6),
        Flexible(
          child: Text(label, maxLines: 1, style: AppType.label(color: AppColors.onBrand).copyWith(fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }
}

/// خيارٌ في ورقة الاختيار.
class FieldPickOption<T> {
  const FieldPickOption({required this.value, required this.label, this.sub, this.icon, this.enabled = true});
  final T? value;
  final String label;
  final String? sub;
  final IconData? icon;
  final bool enabled;
}

/// ورقة اختيارٍ من قائمة (النوع، الفنّي، الموظّف، نوع العمل). null = أُغلقت بلا اختيار؛ `(value: x)` = اختير x (وقد يكون null
/// لخيار «بلا نوع» أو «لاحقاً»).
Future<({T? value})?> showFieldPickSheet<T>(
  BuildContext context, {
  required String title,
  required String subtitle,
  required IconData icon,
  required List<FieldPickOption<T>> options,
  T? selected,
  String empty = 'لا خيارات',
}) {
  return showFieldSheet<({T? value})>(
    context,
    Builder(builder: (ctx) {
      Theme.of(ctx); // theme-dep (dark-mode)
      return DesignSheet(
        header: SheetHeaderBar(
          icon: icon,
          title: title,
          subtitle: subtitle,
          subtitleMaxLines: 2,
          onClose: () => Navigator.of(ctx).pop(),
        ),
        body: options.isEmpty
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: Sp.xl),
                child: Text(empty, textAlign: TextAlign.center, style: AppType.muted(color: AppColors.textMid)),
              )
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (final o in options) ...[
                  _PickRow<T>(option: o, on: o.value == selected, onTap: () => Navigator.of(ctx).pop((value: o.value))),
                  const SizedBox(height: Sp.x6),
                ],
              ]),
      );
    }),
  );
}

class _PickRow<T> extends StatelessWidget {
  const _PickRow({super.key, required this.option, required this.on, required this.onTap});
  final FieldPickOption<T> option;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final o = option;
    return Opacity(
      opacity: o.enabled ? 1 : 0.55,
      child: Material(
        color: on ? AppColors.brandSoftBg : AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        child: InkWell(
          borderRadius: BorderRadius.circular(R.lg),
          onTap: o.enabled ? onTap : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.md),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(R.lg),
              border: Border.all(color: on ? AppColors.brand : AppColors.border, width: on ? BW.selected : BW.normal),
            ),
            child: Row(children: [
              if (o.icon != null) ...[
                Icon(o.icon, size: 18, color: on ? AppColors.brand : AppColors.textMid),
                const SizedBox(width: Sp.md),
              ],
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(iso(o.label), style: AppType.bodyStrong(color: AppColors.textHi)),
                  if ((o.sub ?? '').isNotEmpty) Text(iso(o.sub!), style: AppType.micro(color: AppColors.textMid)),
                ]),
              ),
              if (on) Icon(LucideIcons.check, size: 18, color: AppColors.brand),
            ]),
          ),
        ),
      ),
    );
  }
}

/// حقلٌ يفتح ورقة اختيار: أيقونةٌ ثمّ القيمة (أو تلميحها) ثمّ سهم.
class FieldPickerBox extends StatelessWidget {
  const FieldPickerBox({super.key, required this.icon, required this.text, required this.placeholder, required this.onTap});
  final IconData icon;
  final String? text;
  final String placeholder;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final has = (text ?? '').isNotEmpty;
    return InkWell(
      borderRadius: BorderRadius.circular(R.lg),
      onTap: onTap,
      child: SheetBox(
        icon: icon,
        child: Row(children: [
          Expanded(
            child: Text(
              has ? iso(text!) : placeholder,
              maxLines: 2,
              style: AppType.input(color: has ? AppColors.textHi : AppColors.textPlaceholder),
            ),
          ),
          Icon(LucideIcons.chevronDown, size: 18, color: AppColors.textLow),
        ]),
      ),
    );
  }
}

/// حقل نصٍّ بطقم الأوراق (SheetBox + TextField بلا إطار).
class FieldTextBox extends StatelessWidget {
  const FieldTextBox({
    super.key,
    required this.controller,
    required this.icon,
    required this.hint,
    this.maxLength,
    this.minLines = 1,
    this.maxLines = 1,
    this.ltr = false,
    this.keyboardType,
    this.onChanged,
    this.trailing,
    this.enabled = true,
    this.lowercase = false,
  });
  final TextEditingController controller;
  final IconData icon;
  final String hint;
  final int? maxLength;
  final int minLines;
  final int maxLines;
  final bool ltr;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;
  final Widget? trailing;
  final bool enabled;

  /// اسم الدخول: حروفٌ صغيرة كما يحفظها الخادم.
  final bool lowercase;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final multi = maxLines > 1;
    return SheetBox(
      icon: icon,
      alignTop: multi,
      child: Row(crossAxisAlignment: multi ? CrossAxisAlignment.start : CrossAxisAlignment.center, children: [
        Expanded(
          child: TextField(
            controller: controller,
            enabled: enabled,
            minLines: minLines,
            maxLines: maxLines,
            maxLength: maxLength,
            keyboardType: keyboardType ?? (multi ? TextInputType.multiline : TextInputType.text),
            textDirection: ltr ? TextDirection.ltr : null,
            autocorrect: !ltr,
            enableSuggestions: !ltr,
            textCapitalization: TextCapitalization.none,
            onChanged: lowercase
                ? (v) {
                    final low = v.toLowerCase();
                    if (low != v) {
                      final sel = controller.selection;
                      controller.value = TextEditingValue(text: low, selection: sel);
                    }
                    onChanged?.call(low);
                  }
                : onChanged,
            style: AppType.input(color: AppColors.textHi),
            decoration: InputDecoration(
              isDense: true,
              counterText: '',
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
              hintText: hint,
              hintTextDirection: TextDirection.rtl,
              hintStyle: AppType.input(color: AppColors.textPlaceholder),
            ),
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: Sp.sm), trailing!],
      ]),
    );
  }
}

/// سطر ملاحظةٍ ملوّن (معلومة · تحذير · خطأ).
class FieldNote extends StatelessWidget {
  const FieldNote({super.key, required this.icon, required this.text, this.tone = AppTone.info, this.title});
  final IconData icon;
  final String text;
  final String? title;
  final AppTone tone;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: tone.softBg,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: tone.softBorder),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 18, color: tone.onSoft),
        const SizedBox(width: Sp.sm),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if ((title ?? '').isNotEmpty) Text(title!, style: AppType.bodyBold(color: tone.onSoft)),
            if (text.isNotEmpty) Text(text, style: AppType.label(color: tone.onSoft).copyWith(height: 1.55)),
          ]),
        ),
      ]),
    );
  }
}
