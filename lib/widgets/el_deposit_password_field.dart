import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../api/el_deposit_password.dart';
import '../core/widgets/design_sheet.dart';
import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';

/// حالة حقل باسورد الإيداع في نموذج عمليّة رصيد لايرث لنك: المحفوظ على الخادم
/// (فلا يُكتب شيء) أو نصٌّ يُكتب، و«احفظه» لصاحب الحساب.
///
/// الشيت يستمع إليه (`addListener` ← `setState`) فيتحدّث تفعيل زرّ الإرسال.
class ElDepositPasswordController extends ChangeNotifier {
  ElDepositPasswordController() {
    _lastSaved = ElDepositPassword.status.value?.saved;
    ElDepositPassword.status.addListener(_onStatus);
    text.addListener(notifyListeners);
  }

  final text = TextEditingController();
  bool _changing = false;
  bool _remember = true;
  bool? _lastSaved;

  ElDepositStatus? get status => ElDepositPassword.status.value;
  bool get loading => status == null;
  bool get saved => status?.saved == true;
  bool get canManage => status?.canManage == true;
  bool get changing => _changing;
  bool get remember => _remember;

  /// المحفوظ يُستعمل (لا حقل): الخادم يضيفه بنفسه.
  bool get useSaved => saved && !_changing;

  /// جاهزٌ للإرسال: محفوظٌ أو مكتوب.
  bool get ready => useSaved || text.text.trim().isNotEmpty;

  /// النصّ المُرسَل — `null` مع المحفوظ.
  String? get passwordToSend {
    if (useSaved) return null;
    final t = text.text.trim();
    return t.isEmpty ? null : t;
  }

  /// «احفظه» — لصاحب الحساب وحده ومع نصٍّ مكتوب.
  bool get rememberToSend => passwordToSend != null && canManage && _remember;

  void startChange() {
    _changing = true;
    notifyListeners();
  }

  void useSavedAgain() {
    _changing = false;
    text.clear();
    notifyListeners();
  }

  set remember(bool v) {
    _remember = v;
    notifyListeners();
  }

  void _onStatus() {
    final s = status?.saved;
    // حُفظ الآن أو مُسح (رفضته ايرث لنك) ⇒ يُفرَّغ المكتوب ويُغلق «تغيير».
    if (_lastSaved != null && s != null && s != _lastSaved) {
      _changing = false;
      text.clear();
    }
    if (s != null) _lastSaved = s;
    notifyListeners();
  }

  @override
  void dispose() {
    ElDepositPassword.status.removeListener(_onStatus);
    text.removeListener(notifyListeners);
    text.dispose();
    super.dispose();
  }
}

/// المحفوظ: «محفوظ — لا حاجة لإدخاله · تغيير» — وإلّا الحقل (+ «احفظه» لصاحب
/// الحساب، أو تلميحٌ للموظّف).
class ElDepositPasswordField extends StatefulWidget {
  const ElDepositPasswordField({
    super.key,
    required this.controller,
    this.enabled = true,
    this.hint = 'باسورد الإيداع',
    this.onSubmitted,
  });

  final ElDepositPasswordController controller;
  final bool enabled;
  final String hint;
  final VoidCallback? onSubmitted;

  @override
  State<ElDepositPasswordField> createState() => _ElDepositPasswordFieldState();
}

class _ElDepositPasswordFieldState extends State<ElDepositPasswordField> {
  @override
  void initState() {
    super.initState();
    ElDepositPassword.load();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final c = widget.controller;
        if (c.loading) return _loadingBox();
        if (c.useSaved) return _savedBox(c);
        return _inputBox(c);
      },
    );
  }

  Widget _loadingBox() => SheetBox(
        child: Row(
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppColors.textMid),
            ),
            const SizedBox(width: Sp.sm),
            Text('باسورد الإيداع…',
                style: AppType.input(color: AppColors.textPlaceholder)),
          ],
        ),
      );

  Widget _savedBox(ElDepositPasswordController c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
        constraints: const BoxConstraints(minHeight: 50),
        decoration: BoxDecoration(
          color: AppColors.successSoftBg,
          borderRadius: BorderRadius.circular(R.lg),
          border: Border.all(color: AppColors.successSoftBorder),
        ),
        child: Row(
          children: [
            Icon(LucideIcons.circleCheck, size: 18, color: AppColors.success),
            const SizedBox(width: Sp.sm),
            Expanded(
              child: Text(
                'باسورد الإيداع محفوظ — لا حاجة لإدخاله',
                style: AppType.label(color: AppColors.success)
                    .copyWith(fontWeight: FontWeight.w700),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (c.canManage)
              TextButton(
                onPressed: widget.enabled ? c.startChange : null,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.brand,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: Sp.md),
                  minimumSize: const Size(48, 36),
                ),
                child: Text('تغيير',
                    style: AppType.label(color: AppColors.brand)
                        .copyWith(fontWeight: FontWeight.w700)),
              ),
          ],
        ),
      );

  Widget _inputBox(ElDepositPasswordController c) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetBox(
            focused: c.text.text.isNotEmpty,
            child: TextField(
              controller: c.text,
              enabled: widget.enabled,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              textDirection: ui.TextDirection.ltr,
              textInputAction: widget.onSubmitted != null
                  ? TextInputAction.done
                  : TextInputAction.next,
              onSubmitted:
                  widget.onSubmitted == null ? null : (_) => widget.onSubmitted!(),
              style: AppType.input(),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                hintText: widget.hint,
                hintStyle: AppType.input(color: AppColors.textPlaceholder),
              ),
            ),
          ),
          const SizedBox(height: Sp.x6),
          if (c.canManage)
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(R.sm),
                    onTap: widget.enabled ? () => c.remember = !c.remember : null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: Sp.xs),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: Checkbox(
                              value: c.remember,
                              onChanged: widget.enabled
                                  ? (v) => c.remember = v ?? false
                                  : null,
                              activeColor: AppColors.brand,
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                          const SizedBox(width: Sp.sm),
                          Flexible(
                            child: Text(
                              c.saved
                                  ? 'احفظ الجديد بدل المحفوظ'
                                  : 'احفظه فلا يُطلب مرّة أخرى',
                              style: AppType.muted(color: AppColors.textMid),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (c.changing)
                  TextButton(
                    onPressed: widget.enabled ? c.useSavedAgain : null,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.brand,
                      visualDensity: VisualDensity.compact,
                    ),
                    child: Text('استعمال المحفوظ',
                        style: AppType.muted(color: AppColors.brand)
                            .copyWith(fontWeight: FontWeight.w700)),
                  ),
              ],
            )
          else
            Text(
              'يستطيع صاحب الحساب حفظه من الإعدادات فلا يُطلب منك.',
              style: AppType.micro(color: AppColors.textMid),
            ),
        ],
      );
}
