import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/el_deposit_password.dart';
import '../../core/widgets/design_sheet.dart';
import '../../core/widgets/sheet_scaffold.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';

/// إعدادات باسورد إيداع ايرث لنك المحفوظ — لصاحب الحساب وحده (الإعدادات).
///
/// يُحفظ مشفّراً على الخادم بعد أن يتحقّق منه لدى ايرث لنك (قراءة كشف الحساب،
/// بلا صرف)، ويُستعمل تلقائيّاً في التفعيل والإضافة بالرصيد والتحويل وكشف
/// الحساب؛ الموظّفون يفعّلون به دون أن يروه.
Future<void> showElDepositPasswordSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.scrim,
    builder: (_) => const _DepositPasswordSheet(),
  );
}

class _DepositPasswordSheet extends StatefulWidget {
  const _DepositPasswordSheet();

  @override
  State<_DepositPasswordSheet> createState() => _DepositPasswordSheetState();
}

class _DepositPasswordSheetState extends State<_DepositPasswordSheet> {
  final _ctrl = TextEditingController();
  bool _busy = false;
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    ElDepositPassword.load(force: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final pw = _ctrl.text.trim();
    if (pw.isEmpty || _busy) return;
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    final r = await ElDepositPassword.save(pw);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (r.ok) {
        _editing = false;
        _ctrl.clear();
      }
    });
    showSheetSnack(context, r.message ?? (r.ok ? 'حُفظ باسورد الإيداع' : 'تعذّر الحفظ'),
        isError: !r.ok);
  }

  Future<void> _remove() async {
    final ok = await showConfirmSheet(
      context,
      title: 'مسح الباسورد المحفوظ',
      message: 'سيُطلب باسورد الإيداع في كلّ عمليّة رصيد بعد المسح.',
      confirmLabel: 'مسح',
      icon: LucideIcons.trash2,
      tone: AppTone.danger,
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    final r = await ElDepositPassword.remove();
    if (!mounted) return;
    setState(() => _busy = false);
    showSheetSnack(context, r.message ?? (r.ok ? 'مُسح الباسورد' : 'تعذّر المسح'),
        isError: !r.ok);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ElDepositStatus?>(
      valueListenable: ElDepositPassword.status,
      builder: (context, st, _) {
        final saved = st?.saved == true;
        final showInput = st != null && (!saved || _editing);
        return DesignSheet(
          header: SheetHeaderBar(
            icon: LucideIcons.keyRound,
            title: 'باسورد الإيداع',
            subtitle: 'ايرث لنك — يُحفظ مشفّراً',
            onClose: () => Navigator.of(context).maybePop(),
          ),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (st == null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: Sp.xl),
                  child: Center(
                    child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                )
              else
                _statusBox(saved),
              const SizedBox(height: Sp.md),
              Text(
                'يُستعمل تلقائيّاً في التفعيل والإضافة بالرصيد وتحويل الرصيد وكشف '
                'الحساب — فلا يُطلب كلّ مرّة، وموظّفوك يفعّلون به دون أن يروه. '
                'إن رفضته ايرث لنك يُمسح ويُطلب من جديد.',
                style: AppType.muted(color: AppColors.textMid)
                    .copyWith(height: 1.6),
              ),
              if (showInput) ...[
                const SizedBox(height: Sp.lg),
                SheetSection(
                  label: saved ? 'الباسورد الجديد' : 'باسورد الإيداع',
                  child: SheetBox(
                    focused: _ctrl.text.isNotEmpty,
                    child: TextField(
                      controller: _ctrl,
                      enabled: !_busy,
                      obscureText: true,
                      autocorrect: false,
                      enableSuggestions: false,
                      textDirection: ui.TextDirection.ltr,
                      textInputAction: TextInputAction.done,
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => _save(),
                      style: AppType.input(),
                      decoration: InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                        hintText: '••••••',
                        hintStyle:
                            AppType.input(color: AppColors.textPlaceholder),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: Sp.sm),
                Text(
                  'يُتحقَّق منه لدى ايرث لنك قبل الحفظ بقراءة كشف الحساب — بلا أيّ صرف.',
                  style: AppType.micro(color: AppColors.textMid),
                ),
                if (_editing) ...[
                  const SizedBox(height: Sp.xs),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                                _editing = false;
                                _ctrl.clear();
                              }),
                      child: Text('إلغاء',
                          style: AppType.label(color: AppColors.textMid)),
                    ),
                  ),
                ],
              ],
              if (saved && !_editing) ...[
                const SizedBox(height: Sp.lg),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy
                            ? null
                            : () => setState(() => _editing = true),
                        icon: Icon(LucideIcons.pencil,
                            size: 16, color: AppColors.brand),
                        label: Text('تغيير',
                            style: AppType.button(color: AppColors.brand)),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          side: BorderSide(color: AppColors.brandSoftBorder),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(R.md)),
                        ),
                      ),
                    ),
                    const SizedBox(width: Sp.sm),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : _remove,
                        icon: Icon(LucideIcons.trash2,
                            size: 16, color: AppColors.dangerOnSoft),
                        label: Text('مسح',
                            style:
                                AppType.button(color: AppColors.dangerOnSoft)),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          side: BorderSide(color: AppColors.dangerSoftBorder),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(R.md)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
          footer: showInput
              ? SheetFooterBar(
                  label: saved ? 'حفظ الجديد' : 'حفظ',
                  icon: LucideIcons.check,
                  busy: _busy,
                  enabled: _ctrl.text.trim().isNotEmpty,
                  onPressed: _save,
                )
              : null,
        );
      },
    );
  }

  Widget _statusBox(bool saved) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
        decoration: BoxDecoration(
          color: saved ? AppColors.successSoftBg : AppColors.surfaceInput,
          borderRadius: BorderRadius.circular(R.lg),
          border: Border.all(
              color: saved ? AppColors.successSoftBorder : AppColors.border),
        ),
        child: Row(
          children: [
            Icon(saved ? LucideIcons.circleCheck : LucideIcons.circleDashed,
                size: 18,
                color: saved ? AppColors.success : AppColors.textMid),
            const SizedBox(width: Sp.sm),
            Expanded(
              child: Text(
                saved
                    ? 'محفوظ — يُستعمل تلقائيّاً'
                    : 'غير محفوظ — يُطلب في كلّ عمليّة رصيد',
                style: AppType.label(
                        color: saved ? AppColors.success : AppColors.textHi)
                    .copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      );
}
