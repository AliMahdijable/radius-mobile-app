import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/design_sheet.dart';
import '../../../core/util/bidi.dart';
import '../../../services/receipt_layout.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import 'controls.dart';

/// «إدراج متغيّر»: المتغيّرات بمجموعاتها (المحلّ · الوصل · المشترك · الباقة · المال · الفاتورة) — يعيد المختار.
Future<String?> showVarPicker(BuildContext context, {required String kind}) => showAppSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: AppColors.scrim,
      builder: (ctx) => DesignSheet(
        maxHeightFactor: 0.7,
        header: SheetHeaderBar(
          icon: LucideIcons.braces,
          title: 'إدراج متغيّر',
          subtitle: 'يُملأ من بيانات كلّ وصل',
          onClose: () => Navigator.of(ctx).pop(),
        ),
        body: _VarGroups(kind: kind),
      ),
    );

class _VarGroups extends StatelessWidget {
  const _VarGroups({required this.kind});
  final String kind;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final groups = <String, List<ReceiptVarDef>>{
      for (final g in receiptVarGroups) g.label: [for (final v in receiptVariables) if (v.group == g.id) v],
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final g in groups.entries) ...[
          Text(g.key, style: AppType.label()),
          const SizedBox(height: Sp.x6),
          Wrap(
            spacing: Sp.x6,
            runSpacing: Sp.x6,
            children: [
              for (final v in g.value)
                DesignerChip(
                  label: v.kinds.contains(kind) ? v.label : '${v.label} ·',
                  selected: false,
                  onTap: () => Navigator.of(context).pop(v.id),
                ),
            ],
          ),
          const SizedBox(height: Sp.md),
        ],
        Text('المتغيّر الذي لا قيمة له في نوع الوصل يُترك فارغاً (·).', style: AppType.muted()),
      ],
    );
  }
}

/// حقل نصٍّ يقبل المتغيّرات: «إدراج متغيّر» عند المؤشّر، وتنبيه المتغيّر المجهول، وسطر مثالٍ مملوء بعيّنة الوصل.
/// يتزامن مع المصمّم (تراجعٌ يعيد نصّه) دون أن يقفز المؤشّر أثناء الكتابة.
class TemplatedInput extends StatefulWidget {
  const TemplatedInput({
    super.key,
    required this.value,
    required this.onChanged,
    required this.kind,
    required this.sampleVars,
    this.hint,
    this.maxLength = 40,
    this.maxLines = 1,
    this.vars = true,
    this.ltr = false,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final String kind;

  /// قيم المتغيّرات في عيّنة النوع المعروض (سطر المثال).
  final Map<String, String> sampleVars;
  final String? hint;
  final int maxLength;
  final int maxLines;

  /// false = نصٌّ يُطبع كما هو (نصّ الذيل وأعمدة المحلّ — التطبيقات القديمة تطبعها حرفيّاً).
  final bool vars;
  final bool ltr;

  @override
  State<TemplatedInput> createState() => _TemplatedInputState();
}

class _TemplatedInputState extends State<TemplatedInput> {
  late final TextEditingController _c = TextEditingController(text: widget.value);
  String _emitted = '';

  @override
  void initState() {
    super.initState();
    _emitted = widget.value;
  }

  @override
  void didUpdateWidget(TemplatedInput old) {
    super.didUpdateWidget(old);
    // تغيّر من خارج الحقل (تراجع، قالب، عنصرٌ آخر) ⇒ نصّه الجديد.
    if (widget.value != _emitted && widget.value != _c.text) {
      _c.value = TextEditingValue(text: widget.value, selection: TextSelection.collapsed(offset: widget.value.length));
      _emitted = widget.value;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _emit(String v) {
    _emitted = v;
    widget.onChanged(v);
  }

  Future<void> _insert() async {
    final id = await showVarPicker(context, kind: widget.kind);
    if (id == null || !mounted) return;
    final token = '{$id}';
    final sel = _c.selection;
    final text = _c.text;
    final start = sel.isValid ? sel.start : text.length;
    final end = sel.isValid ? sel.end : text.length;
    final next = text.replaceRange(start, end, token);
    if (next.runes.length > widget.maxLength) {
      HapticFeedback.heavyImpact();
      return;
    }
    _c.value = TextEditingValue(text: next, selection: TextSelection.collapsed(offset: start + token.length));
    _emit(next);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final text = _c.text;
    final unknown = widget.vars ? receiptUnknownVars(text) : const <String>[];
    final hasVar = widget.vars && RegExp(r'\{[a-z_]+\}').hasMatch(text);
    final sample = hasVar ? receiptFill(text, widget.sampleVars) : null;
    final count = text.runes.length;
    final lines = '\n'.allMatches(text).length + 1;
    final over = count > widget.maxLength;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _c,
          maxLines: widget.maxLines,
          minLines: 1,
          textDirection: widget.ltr ? TextDirection.ltr : null,
          style: AppType.input(),
          decoration: InputDecoration(
            isDense: true,
            hintText: widget.hint,
            hintStyle: AppType.input(color: AppColors.textPlaceholder),
            filled: true,
            fillColor: AppColors.surfaceInput,
            contentPadding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.sm),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(R.sm),
              borderSide: BorderSide(color: AppColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(R.sm),
              borderSide: BorderSide(color: over || unknown.isNotEmpty ? AppColors.error : AppColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(R.sm),
              borderSide: BorderSide(color: AppColors.brand, width: BW.selected),
            ),
            suffixIcon: widget.vars
                ? IconButton(
                    tooltip: 'إدراج متغيّر',
                    icon: Icon(LucideIcons.braces, size: 16, color: AppColors.brand),
                    onPressed: _insert,
                  )
                : null,
          ),
          onChanged: (v) {
            setState(() {});
            _emit(v);
          },
        ),
        if (over || (widget.maxLines > 1 && lines > 4))
          Padding(
            padding: const EdgeInsets.only(top: Sp.xs),
            child: Text(
              over ? 'أطول من المسموح: $count حرفاً (الحدّ ${widget.maxLength})' : 'أكثر من ٤ أسطر — الخادم يرفضه',
              style: AppType.muted(color: AppColors.error),
            ),
          ),
        if (unknown.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: Sp.xs),
            child: Text(
              'متغيّرٌ غير معروف: ${unknown.map((u) => '{$u}').join('، ')} — اختره من «إدراج متغيّر»',
              style: AppType.muted(color: AppColors.error),
            ),
          ),
        if (sample != null && unknown.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: Sp.xs),
            child: Text(
              sample.hidden ? 'مثال: (لا يُطبع — متغيّراته فارغة في هذا النوع)' : 'مثال: ${isoLatinRuns(sample.text)}',
              style: AppType.muted(color: AppColors.textMid),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );
  }
}

final RegExp _latinRun = RegExp(r'[#+@]?[0-9A-Za-z](?:[0-9A-Za-z@#.,:/_+\- ]*[0-9A-Za-z])?');

/// كلّ مقطعٍ لاتينيّ (تاريخٌ ووقت، هاتفٌ بمسافات، مبلغ) معزولاً — لا ينقلب «2026-12-01 10:00» في سطرٍ عربيّ.
String isoLatinRuns(String text) => text.replaceAllMapped(_latinRun, (m) => iso(m.group(0)!));
