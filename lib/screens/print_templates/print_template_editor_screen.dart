import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/print_templates_api.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';

/// محرّر قالب طباعة — نمط MVP:
///   - حقل اسم القالب
///   - Switch is_active
///   - Editor HTML (text field كبير)
///   - شريط أفقي بالمتغيّرات — الضغط يُدرج {var} عند مؤشّر الكتابة
///   - Preview بسيط: يعرض HTML كنص خام (سطر جديد لكل tag)
///   - زر حفظ + زر حذف (لو الـid موجود)
class PrintTemplateEditorScreen extends StatefulWidget {
  const PrintTemplateEditorScreen({
    super.key,
    required this.templateType,
    this.existing,
  });
  final String templateType;
  final PrintTemplate? existing;

  @override
  State<PrintTemplateEditorScreen> createState() =>
      _PrintTemplateEditorScreenState();
}

class _PrintTemplateEditorScreenState extends State<PrintTemplateEditorScreen> {
  late final TextEditingController _name;
  late final TextEditingController _content;
  bool _isActive = true;
  bool _saving = false;
  bool _dirty = false;
  final FocusNode _contentFocus = FocusNode();

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(
      text: widget.existing?.templateName ??
          (widget.templateType == 'a4'
              ? 'print_templates.a4_default_name'.tr()
              : 'print_templates.pos_default_name'.tr()),
    );
    _content = TextEditingController(
      text: widget.existing?.content ?? _defaultContent(widget.templateType),
    );
    _isActive = widget.existing?.isActive ?? true;
    _name.addListener(_markDirty);
    _content.addListener(_markDirty);
  }

  @override
  void dispose() {
    _name.dispose();
    _content.dispose();
    _contentFocus.dispose();
    super.dispose();
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _name.text.trim();
    final content = _content.text.trim();
    if (name.isEmpty || content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('print_templates.err_empty'.tr()),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    setState(() => _saving = true);
    bool ok;
    if (_isEdit) {
      ok = await PrintTemplatesApi.update(
        widget.existing!.id!,
        templateName: name,
        content: content,
        isActive: _isActive,
      );
    } else {
      final created = await PrintTemplatesApi.create(
        templateType: widget.templateType,
        templateName: name,
        content: content,
        isActive: _isActive,
      );
      ok = created != null;
    }
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'print_templates.saved'.tr()
              : 'print_templates.save_failed'.tr(),
        ),
        backgroundColor: ok ? AppColors.brand : AppColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
    if (ok) {
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _delete() async {
    if (!_isEdit || _saving) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(R.lg)),
        title: Text(
          'print_templates.delete_title'.tr(),
          style: AppType.title(color: AppColors.textHi).copyWith(fontSize: 16),
        ),
        content: Text(
          'print_templates.delete_body'.tr(),
          style: AppType.subtitle(color: AppColors.textMid),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('common.cancel'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('common.delete'.tr(),
                style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _saving = true);
    final ok = await PrintTemplatesApi.delete(widget.existing!.id!);
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'print_templates.deleted'.tr()
              : 'print_templates.delete_failed'.tr(),
        ),
        backgroundColor: ok ? AppColors.brand : AppColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
    if (ok) Navigator.of(context).pop(true);
  }

  void _insertVariable(String token) {
    HapticFeedback.selectionClick();
    final sel = _content.selection;
    final txt = _content.text;
    final start = sel.start < 0 ? txt.length : sel.start;
    final end = sel.end < 0 ? txt.length : sel.end;
    final next = txt.substring(0, start) + token + txt.substring(end);
    _content.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + token.length),
    );
    _contentFocus.requestFocus();
  }

  Future<void> _previewSheet() async {
    // معاينة بسيطة: نستخرج النصوص من الـHTML (بدون webview) بحيث المدير
    // يرى الشكل التقريبي + المتغيّرات كما هي.
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PreviewSheet(html: _content.text),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: Text(
          _isEdit
              ? 'print_templates.edit_title'.tr()
              : 'print_templates.create_title'.tr(),
          style: AppType.title(color: AppColors.textHi).copyWith(fontSize: 16),
        ),
        iconTheme: IconThemeData(color: AppColors.textHi),
        actions: [
          IconButton(
            tooltip: 'print_templates.preview'.tr(),
            icon: Icon(LucideIcons.eye, size: 18, color: AppColors.textHi),
            onPressed: _previewSheet,
          ),
          if (_isEdit)
            IconButton(
              tooltip: 'common.delete'.tr(),
              icon: Icon(LucideIcons.trash2,
                  size: 18, color: AppColors.error),
              onPressed: _saving ? null : _delete,
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.lg, Sp.lg, Sp.md),
              children: [
                _typeBadge(widget.templateType),
                const SizedBox(height: Sp.md),
                _labeledField(
                  label: 'print_templates.name_label'.tr(),
                  controller: _name,
                  hint: 'print_templates.name_hint'.tr(),
                  maxLength: 200,
                ),
                const SizedBox(height: Sp.md),
                SwitchListTile(
                  value: _isActive,
                  onChanged: (v) => setState(() {
                    _isActive = v;
                    _dirty = true;
                  }),
                  title: Text('print_templates.active_toggle'.tr(),
                      style: AppType.subtitle(color: AppColors.textHi)),
                  subtitle: Text(
                    'print_templates.active_hint'.tr(),
                    style: AppType.subtitle(color: AppColors.textMid)
                        .copyWith(fontSize: 10),
                  ),
                  activeColor: AppColors.brand,
                  contentPadding: EdgeInsets.zero,
                ),
                const SizedBox(height: Sp.md),
                _labeledField(
                  label: 'print_templates.content_label'.tr(),
                  controller: _content,
                  focusNode: _contentFocus,
                  hint: 'print_templates.content_hint'.tr(),
                  maxLines: 14,
                  minLines: 8,
                  maxLength: 20000,
                  monospace: true,
                ),
              ],
            ),
          ),
          // Variables inserter — أفقي
          Container(
            padding: const EdgeInsets.symmetric(vertical: Sp.sm),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border(
                  top: BorderSide(color: AppColors.textMid.withOpacity(0.12))),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: Sp.lg, vertical: 4),
                  child: Text(
                    'print_templates.variables_hint'.tr(),
                    style: AppType.subtitle(color: AppColors.textMid)
                        .copyWith(fontSize: 10),
                  ),
                ),
                SizedBox(
                  height: 40,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
                    itemCount: PrintTemplate.availableVariables.length,
                    separatorBuilder: (_, __) => const SizedBox(width: Sp.sm),
                    itemBuilder: (_, i) {
                      final v = PrintTemplate.availableVariables[i];
                      return _VariableChip(
                        label: v.label,
                        token: v.token,
                        onTap: () => _insertVariable(v.token),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          // Save button
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(Sp.lg),
              child: SizedBox(
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _saving || !_dirty ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation(Colors.white),
                          ),
                        )
                      : const Icon(LucideIcons.save, size: 18),
                  label: Text(
                    _isEdit
                        ? 'print_templates.save_changes'.tr()
                        : 'print_templates.create'.tr(),
                    style: AppType.button(color: Colors.white),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.brand,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor:
                        AppColors.brand.withOpacity(0.4),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(R.md)),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _typeBadge(String type) {
    final label = type == 'a4' ? 'A4' : 'POS';
    final color =
        type == 'a4' ? const Color(0xFF3B82F6) : const Color(0xFF10B981);
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: 6),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            border: Border.all(color: color.withOpacity(0.35)),
            borderRadius: BorderRadius.circular(R.pill),
          ),
          child: Text(
            '${'print_templates.type_prefix'.tr()} $label',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

class _VariableChip extends StatelessWidget {
  const _VariableChip({
    required this.label,
    required this.token,
    required this.onTap,
  });
  final String label;
  final String token;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.brand.withOpacity(0.08),
      borderRadius: BorderRadius.circular(R.pill),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.plus, size: 12, color: AppColors.brand),
              const SizedBox(width: 4),
              Text(label,
                  style: AppType.button(color: AppColors.brand)
                      .copyWith(fontSize: 11)),
              const SizedBox(width: 4),
              Text(
                token,
                style: TextStyle(
                  fontSize: 10,
                  color: AppColors.brand.withOpacity(0.65),
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PreviewSheet extends StatelessWidget {
  const _PreviewSheet({required this.html});
  final String html;

  @override
  Widget build(BuildContext context) {
    // معاينة نصّية بسيطة: نجرّد الـHTML ونبقي النصوص + line breaks
    // من <br> و </p> و </div>. تكفي للتحقّق أن المتغيّرات في المكان الصحيح.
    // معاينة WebView-based مؤجَّلة لتجنّب dependency إضافي.
    final stripped = _stripHtml(html);
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (ctx, scroll) => Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(R.xl)),
        ),
        child: Column(
          children: [
            const SizedBox(height: Sp.sm),
            Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textMid.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: Sp.md),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
                  child: Text(
                    'print_templates.preview'.tr(),
                    style: AppType.title(color: AppColors.textHi)
                        .copyWith(fontSize: 16),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  color: AppColors.textMid,
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
              ],
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                controller: scroll,
                padding: const EdgeInsets.all(Sp.lg),
                child: Container(
                  padding: const EdgeInsets.all(Sp.md),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(R.md),
                  ),
                  child: Text(
                    stripped,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.75,
                      color: Colors.grey.shade900,
                      fontFamily: 'Cairo',
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _stripHtml(String s) {
    // 1. أضف line-break بعد close tags الشائعة
    var t = s.replaceAllMapped(
      RegExp(r'</(p|div|tr|h1|h2|h3|h4|li|br)[^>]*>', caseSensitive: false),
      (m) => '\n',
    );
    t = t.replaceAllMapped(
      RegExp(r'<br\s*/?>', caseSensitive: false),
      (m) => '\n',
    );
    // 2. جرّد كل الـHTML tags
    t = t.replaceAll(RegExp(r'<[^>]+>'), '');
    // 3. entities شائعة
    t = t
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"');
    // 4. اضغط الأسطر الفارغة الزائدة
    t = t.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    // 5. اضغط المسافات المتتالية
    t = t.replaceAll(RegExp(r'[ \t]+'), ' ').trim();
    return t;
  }
}

Widget _labeledField({
  required String label,
  required TextEditingController controller,
  required String hint,
  FocusNode? focusNode,
  int? maxLength,
  int? maxLines = 1,
  int? minLines,
  bool monospace = false,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label,
          style: AppType.subtitle(color: AppColors.textMid)
              .copyWith(fontSize: 11)),
      const SizedBox(height: 4),
      TextField(
        controller: controller,
        focusNode: focusNode,
        maxLength: maxLength,
        maxLines: maxLines,
        minLines: minLines,
        style: AppType.subtitle(color: AppColors.textHi).copyWith(
          fontFamily: monospace ? 'monospace' : null,
          fontSize: monospace ? 12 : null,
          height: monospace ? 1.5 : null,
        ),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: AppType.subtitle(color: AppColors.textMid.withOpacity(0.5)),
          filled: true,
          fillColor: AppColors.surfaceInput,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(R.sm),
            borderSide: BorderSide(color: AppColors.textMid.withOpacity(0.2)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(R.sm),
            borderSide: BorderSide(color: AppColors.textMid.withOpacity(0.2)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(R.sm),
            borderSide: BorderSide(color: AppColors.brand),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.md),
          counterText: '',
        ),
      ),
    ],
  );
}

// ─── Default content templates ─────────────────
String _defaultContent(String type) {
  if (type == 'a4') {
    return '''<div style="padding: 40px; font-family: Cairo, sans-serif; direction: rtl;">
  <div style="text-align: center; margin-bottom: 30px;">
    <h1 style="margin: 0; color: #2D5F47;">فاتورة</h1>
    <p style="margin: 5px 0; color: #6b7280;">رقم الفاتورة: {invoice_number}</p>
    <p style="margin: 5px 0; color: #6b7280;">التاريخ: {date}</p>
  </div>
  <div style="margin-bottom: 30px;">
    <h3 style="margin-bottom: 15px; color: #1f2937;">بيانات المشترك:</h3>
    <table style="width: 100%; border-collapse: collapse;">
      <tr>
        <td style="padding: 10px; border: 1px solid #e5e7eb; font-weight: 600;">اسم المشترك:</td>
        <td style="padding: 10px; border: 1px solid #e5e7eb;">{subscriber_name}</td>
      </tr>
      <tr>
        <td style="padding: 10px; border: 1px solid #e5e7eb; font-weight: 600;">رقم الهاتف:</td>
        <td style="padding: 10px; border: 1px solid #e5e7eb;">{phone_number}</td>
      </tr>
      <tr>
        <td style="padding: 10px; border: 1px solid #e5e7eb; font-weight: 600;">اسم الباقة:</td>
        <td style="padding: 10px; border: 1px solid #e5e7eb;">{package_name}</td>
      </tr>
      <tr>
        <td style="padding: 10px; border: 1px solid #e5e7eb; font-weight: 600;">سعر الباقة:</td>
        <td style="padding: 10px; border: 1px solid #e5e7eb;">{package_price} IQD</td>
      </tr>
      <tr>
        <td style="padding: 10px; border: 1px solid #e5e7eb; font-weight: 600;">المبلغ المدفوع:</td>
        <td style="padding: 10px; border: 1px solid #e5e7eb;">{paid_amount} IQD</td>
      </tr>
      <tr>
        <td style="padding: 10px; border: 1px solid #e5e7eb; font-weight: 600;">تاريخ الانتهاء:</td>
        <td style="padding: 10px; border: 1px solid #e5e7eb;">{expiry_date}</td>
      </tr>
    </table>
  </div>
  <div style="text-align: center; margin-top: 40px; padding-top: 20px; border-top: 2px solid #e5e7eb;">
    <p style="margin: 0; color: #6b7280;">شكراً لتعاملكم معنا</p>
  </div>
</div>''';
  }
  // POS 80mm
  return '''<div style="width: 80mm; padding: 10px; font-family: Cairo, sans-serif; direction: rtl; font-size: 12px;">
  <div style="text-align: center; margin-bottom: 15px;">
    <h2 style="margin: 0; font-size: 18px;">فاتورة</h2>
    <p style="margin: 3px 0; font-size: 11px;">#{invoice_number}</p>
    <p style="margin: 3px 0; font-size: 11px;">{date}</p>
  </div>
  <div style="border-top: 1px dashed #000; border-bottom: 1px dashed #000; padding: 10px 0; margin-bottom: 10px;">
    <div><strong>المشترك:</strong> {subscriber_name}</div>
    <div><strong>الهاتف:</strong> {phone_number}</div>
    <div><strong>الباقة:</strong> {package_name}</div>
  </div>
  <div style="margin-bottom: 15px;">
    <div style="display:flex;justify-content:space-between;"><span>سعر الباقة:</span><span>{package_price}</span></div>
    <div style="display:flex;justify-content:space-between;"><span>المدفوع:</span><span>{paid_amount}</span></div>
    <div style="display:flex;justify-content:space-between;"><span>المتبقي:</span><span>{remaining_amount}</span></div>
    <div style="display:flex;justify-content:space-between;"><span>الانتهاء:</span><span>{expiry_date}</span></div>
  </div>
  <div style="border-top: 1px dashed #000; padding-top: 10px; text-align: center;">
    <p style="margin: 0; font-size: 11px;">شكراً لتعاملكم معنا</p>
  </div>
</div>''';
}
