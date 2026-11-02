import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/national_device_api.dart';
import '../../core/widgets/app_sheet.dart';
import '../../core/widgets/design_sheet.dart';
import '../../core/widgets/sheet_scaffold.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';

/// قطعٌ مشتركة لنافذتي «تعديل معلومات الجهاز» و«تنصيب الجهاز» (المشروع الوطنيّ، ٢ نوفمبر): قسمٌ بعنوانه و«الحاليّ»، حقلٌ لاتينيّ
/// (سيريال/ماك/اسم/رمز)، اختيارٌ من قائمة (FDT · الفات · نوع الجهاز) بنافذةٍ فيها بحث، وقيمةٌ سرّيّة مخفيّة بنقاطٍ مع إظهارٍ ونسخ.

/// يحوّل المكتوب إلى حروفٍ كبيرة (السيريال كما تطبعه البوّابة).
class NationalUpperCase extends TextInputFormatter {
  const NationalUpperCase();
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) =>
      newValue.copyWith(text: newValue.text.toUpperCase());
}

/// قسمٌ في النافذة: أيقونة وعنوان، و«الحاليّ» في طرفه، ثمّ محتواه — وفاصلٌ فوقه لغير الأوّل.
class NationalEditSection extends StatelessWidget {
  const NationalEditSection({super.key, required this.icon, required this.title, this.now, required this.child, this.first = false});
  final IconData icon;
  final String title;
  final Widget? now;
  final Widget child;
  final bool first;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep
    return Container(
      padding: EdgeInsets.only(top: first ? 0 : Sp.lg),
      margin: EdgeInsets.only(top: first ? 0 : Sp.lg),
      decoration: first ? null : BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: 4,
            spacing: Sp.sm,
            children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, size: 18, color: AppColors.textMid),
                const SizedBox(width: Sp.sm),
                Text(title, style: AppType.cardTitle()),
              ]),
              if (now != null) now!,
            ],
          ),
          const SizedBox(height: Sp.md),
          child,
        ],
      ),
    );
  }
}

/// «الحاليّ X» — القيمة لاتينيّة باتّجاهها.
class NationalNowValue extends StatelessWidget {
  const NationalNowValue(this.value, {super.key});
  final String? value;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Text('الحاليّ ', style: AppType.micro(color: AppColors.textMid)),
      Flexible(
        child: Text(
          (value == null || value!.isEmpty) ? '—' : value!,
          textDirection: TextDirection.ltr,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppType.labelBold(color: AppColors.textHi),
        ),
      ),
    ]);
  }
}

/// قيمةٌ سرّيّة (رمز الجهاز): نقاطٌ، وزرّا إظهارٍ ونسخ — أو «محجوب» لموظّفٍ بلا «تعديل المشترك».
class NationalSecretValue extends StatefulWidget {
  const NationalSecretValue({super.key, required this.value, this.hidden = false, this.prefix = 'الحاليّ '});
  final String? value;
  final bool hidden;
  final String prefix;

  @override
  State<NationalSecretValue> createState() => _NationalSecretValueState();
}

class _NationalSecretValueState extends State<NationalSecretValue> {
  bool _show = false;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep
    if (widget.hidden) return Text('محجوب — يحتاج «تعديل المشترك»', style: AppType.micro(color: AppColors.textMid));
    final v = widget.value;
    if (v == null || v.isEmpty) return const NationalNowValue(null);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      if (widget.prefix.isNotEmpty) Text(widget.prefix, style: AppType.micro(color: AppColors.textMid)),
      Flexible(
        child: Text(_show ? v : '••••••••',
            textDirection: TextDirection.ltr, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.labelBold(color: AppColors.textHi)),
      ),
      IconButton(
        tooltip: _show ? 'إخفاء الرمز' : 'إظهار الرمز',
        visualDensity: VisualDensity.compact,
        onPressed: () => setState(() => _show = !_show),
        icon: Icon(_show ? LucideIcons.eyeOff : LucideIcons.eye, size: 18, color: AppColors.textMid),
      ),
      IconButton(
        tooltip: 'نسخ الرمز',
        visualDensity: VisualDensity.compact,
        onPressed: () async {
          await Clipboard.setData(ClipboardData(text: v));
          if (context.mounted) showSheetSnack(context, 'نُسخ الرمز');
        },
        icon: Icon(LucideIcons.copy, size: 18, color: AppColors.textMid),
      ),
    ]);
  }
}

/// حقلٌ لاتينيّ (سيريال/ماك/اسم/رمز/كود) في صندوق النوافذ — بإظهارٍ للرمز ([secret]) وخطأٍ تحته.
class NationalLatinField extends StatefulWidget {
  const NationalLatinField({
    super.key,
    required this.controller,
    this.hint,
    this.icon,
    this.maxLength = 30,
    this.secret = false,
    this.enabled = true,
    this.upper = false,
    this.error,
    this.helper,
    this.onChanged,
    this.semanticLabel,
  });
  final TextEditingController controller;
  final String? hint;
  final IconData? icon;
  final int maxLength;
  final bool secret;
  final bool enabled;
  final bool upper;
  final String? error;
  final Widget? helper;
  final ValueChanged<String>? onChanged;
  final String? semanticLabel;

  @override
  State<NationalLatinField> createState() => _NationalLatinFieldState();
}

class _NationalLatinFieldState extends State<NationalLatinField> {
  bool _show = false;
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetBox(
          icon: widget.icon,
          focused: _focus.hasFocus,
          borderColor: widget.error != null ? AppColors.error : null,
          padding: EdgeInsets.fromLTRB(15, widget.secret ? 4 : 13, widget.secret ? 4 : 15, widget.secret ? 4 : 13),
          child: Row(children: [
            Expanded(
              child: Semantics(
                label: widget.semanticLabel,
                child: TextField(
                  controller: widget.controller,
                  focusNode: _focus,
                  enabled: widget.enabled,
                  obscureText: widget.secret && !_show,
                  autocorrect: false,
                  enableSuggestions: false,
                  textDirection: TextDirection.ltr,
                  textAlign: TextAlign.left,
                  maxLength: widget.maxLength,
                  keyboardType: TextInputType.visiblePassword,
                  inputFormatters: [if (widget.upper) const NationalUpperCase()],
                  onChanged: widget.onChanged,
                  style: AppType.input(),
                  decoration: InputDecoration(
                    isDense: true,
                    counterText: '',
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                    hintText: widget.hint,
                    hintTextDirection: TextDirection.ltr,
                    hintStyle: AppType.input(color: AppColors.textPlaceholder),
                  ),
                ),
              ),
            ),
            if (widget.secret)
              IconButton(
                tooltip: _show ? 'إخفاء' : 'إظهار',
                onPressed: () => setState(() => _show = !_show),
                icon: Icon(_show ? LucideIcons.eyeOff : LucideIcons.eye, size: 18, color: AppColors.textMid),
              ),
          ]),
        ),
        if (widget.error != null) ...[
          const SizedBox(height: 6),
          Text(widget.error!, style: AppType.micro(color: AppColors.error)),
        ] else if (widget.helper != null) ...[
          const SizedBox(height: 6),
          widget.helper!,
        ],
      ],
    );
  }
}

/// اختيارٌ من قائمة: صندوقٌ يعرض المختار ويفتح نافذة القائمة (بحثٌ حين تطول).
class NationalPickField extends StatelessWidget {
  const NationalPickField({
    super.key,
    required this.title,
    required this.items,
    required this.selectedId,
    required this.onPicked,
    this.placeholder = 'اختر',
    this.enabled = true,
    this.icon,
    this.error,
    this.ltr = true,
  });
  final String title;
  final List<NationalNetRef> items;
  final String? selectedId;
  final ValueChanged<NationalNetRef> onPicked;
  final String placeholder;
  final bool enabled;
  final IconData? icon;
  final String? error;
  final bool ltr;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep
    final sel = items.where((x) => x.id == selectedId).firstOrNull;
    final live = enabled && items.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(R.lg),
            onTap: !live
                ? null
                : () async {
                    final p = await showNationalPicker(context, title: title, items: items, selectedId: selectedId, ltr: ltr);
                    if (p != null) onPicked(p);
                  },
            child: SheetBox(
              icon: icon,
              background: live ? null : AppColors.surfaceSunken,
              borderColor: error != null ? AppColors.error : null,
              child: Row(children: [
                Expanded(
                  child: Text(
                    sel?.name ?? placeholder,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textDirection: sel != null && ltr ? TextDirection.ltr : null,
                    textAlign: TextAlign.start,
                    style: AppType.input(color: sel == null ? AppColors.textPlaceholder : AppColors.textHi),
                  ),
                ),
                Icon(LucideIcons.chevronDown, size: 18, color: AppColors.textMid),
              ]),
            ),
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 6),
          Text(error!, style: AppType.micro(color: AppColors.error)),
        ],
      ],
    );
  }
}

/// نافذة اختيارٍ من قائمة — بحثٌ حين تزيد عن عشرة.
Future<NationalNetRef?> showNationalPicker(
  BuildContext context, {
  required String title,
  required List<NationalNetRef> items,
  String? selectedId,
  bool ltr = true,
}) {
  return showAppSheet<NationalNetRef>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.scrim,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _PickerSheet(title: title, items: items, selectedId: selectedId, ltr: ltr),
  );
}

class _PickerSheet extends StatefulWidget {
  const _PickerSheet({required this.title, required this.items, this.selectedId, this.ltr = true});
  final String title;
  final List<NationalNetRef> items;
  final String? selectedId;
  final bool ltr;

  @override
  State<_PickerSheet> createState() => _PickerSheetState();
}

class _PickerSheetState extends State<_PickerSheet> {
  final _q = TextEditingController();

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep
    final q = _q.text.trim().toLowerCase();
    final shown = q.isEmpty ? widget.items : widget.items.where((x) => x.name.toLowerCase().contains(q)).toList();
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.listChecks,
        title: widget.title,
        subtitle: widget.items.length > 10 ? '${widget.items.length} خيار — ابحث أو اختر' : 'اختر من القائمة',
        onClose: () => Navigator.of(context).pop(),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.items.length > 10) ...[
            SheetSearchField(controller: _q, hint: 'ابحث', onChanged: (_) => setState(() {})),
            const SizedBox(height: Sp.sm),
          ],
          if (shown.isEmpty) Padding(padding: const EdgeInsets.all(Sp.lg), child: Text('لا شيء بهذا البحث', style: AppType.muted())),
          for (final x in shown)
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(R.md),
                onTap: () => Navigator.of(context).pop(x),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
                  child: Row(children: [
                    Expanded(
                      child: Text(
                        x.name,
                        textDirection: widget.ltr ? TextDirection.ltr : null,
                        textAlign: TextAlign.start,
                        style: AppType.body(color: x.id == widget.selectedId ? AppColors.brand : AppColors.textHi),
                      ),
                    ),
                    if (x.id == widget.selectedId) Icon(LucideIcons.check, size: 18, color: AppColors.brand),
                  ]),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// نتيجة حفظٍ ⇒ إشعارٌ قصير (النجاح والقبول والمجهول والرفض بنصّه).
void nationalEditSnack(BuildContext context, NationalEditResult r, String what) {
  if (r.ok) {
    final m = switch (r.outcome) {
      'applied' => 'تمّ $what',
      'not_applied' => r.message ?? 'قبلت البوّابة الطلب ولم يتغيّر — جرّب من البوّابة نفسها',
      'unknown' => r.message ?? 'قبلت البوّابة الطلب — تحقّق بعد قليل',
      _ => r.message ?? 'قبلت البوّابة $what',
    };
    showSheetSnack(context, m, isError: r.outcome == 'not_applied', duration: Duration(seconds: r.outcome == 'applied' ? 3 : 8));
    return;
  }
  showSheetSnack(context, r.unconfirmed ? (r.message ?? 'لم يتأكّد $what — تحقّق قبل الإعادة') : r.text,
      isError: !r.unconfirmed, duration: const Duration(seconds: 10), autoExplain: false);
}
