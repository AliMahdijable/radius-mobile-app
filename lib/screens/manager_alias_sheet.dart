import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../api/subscriber_edits_api.dart';
import '../core/util/bidi.dart';
import '../core/widgets/app_sheet.dart';
import '../core/widgets/design_sheet.dart';
import '../core/widgets/sheet_scaffold.dart';
import '../services/auth_storage.dart';
import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';

/// «اسمك في السجلات» (المالك ٢٠ نوفمبر: «المدير من يسوي الحركه تظهر باسمه نكدر نخلي اسم مستعار للمدير… بدل admin@»): حين ينفّذ
/// صاحب الصفحة بنفسه تظهر العمليّة بهذا الاسم بدل يوزر الساس (سجلّ العمليّات، آخر العمليّات، كشف المشترك، سجلّ التعديلات)؛
/// الموظّفون بأسمائهم كما كانوا. لصاحب الصفحة وحده (الخادم يردّ الموظّف بـ403، والإعدادات تريه الصفّ مقفلاً). كقسم الموقع
/// (`LogNameSection` في Settings.tsx).
Future<void> showManagerAliasSheet(BuildContext context) {
  return showAppSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.scrim,
    builder: (_) => const ManagerAliasSheet(),
  );
}

class ManagerAliasSheet extends StatefulWidget {
  const ManagerAliasSheet({super.key});

  @override
  State<ManagerAliasSheet> createState() => _ManagerAliasSheetState();
}

class _ManagerAliasSheetState extends State<ManagerAliasSheet> {
  final _ctrl = TextEditingController();
  bool _loading = true;
  String? _loadError;
  String? _current;
  String _login = '';
  bool _busy = false;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    _load();
    AuthStorage.readAdminUsername().then((u) {
      if (mounted) setState(() => _login = (u ?? '').trim());
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    final r = await ManagerAliasApi.get();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r.ok) {
        _current = r.alias;
        _ctrl.text = r.alias ?? '';
      } else {
        _loadError = (r.message ?? '').trim().isEmpty ? 'تعذّرت قراءة الاسم' : r.message!.trim();
      }
    });
  }

  bool get _changed => _ctrl.text.trim() != (_current ?? '');

  /// [next] فارغ ⇒ يُمسح الاسم (ترجع العمليّات بيوزر الصفحة).
  Future<void> _save(String next) async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _saveError = null;
    });
    final r = await ManagerAliasApi.save(next);
    if (!mounted) return;
    if (!r.ok) {
      setState(() {
        _busy = false;
        _saveError = (r.message ?? '').trim().isEmpty ? 'تعذّر الحفظ' : r.message!.trim();
      });
      return;
    }
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    Navigator.of(context).pop();
    if (overlay != null) {
      showSheetSnackOn(
        overlay,
        r.alias != null ? 'حُفظ — تظهر عمليّاتك باسم «${r.alias}»' : 'رجعت عمليّاتك تظهر بيوزر الصفحة',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final ready = !_loading && _loadError == null;
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.userPen,
        title: 'اسمك في السجلات',
        // قصيرٌ يسعه سطرٌ على ٣٢٠ بخطّ ١٫٢ (كان يُقصّ) — الشرح في الجسم
        subtitle: 'بدل يوزر الصفحة',
        onClose: () => Navigator.of(context).maybePop(),
      ),
      body: _body(),
      footer: SheetFooterBar(
        label: 'حفظ',
        icon: LucideIcons.check,
        busy: _busy,
        enabled: ready && _changed,
        onPressed: () => _save(_ctrl.text),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: Sp.xl),
        child: Center(
          child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    }
    if (_loadError != null) {
      return Padding(
        key: const ValueKey('alias-load-error'),
        padding: const EdgeInsets.symmetric(vertical: Sp.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_loadError!, style: AppType.subtitle(color: AppColors.error), textAlign: TextAlign.center),
            const SizedBox(height: Sp.md),
            OutlinedButton.icon(
              onPressed: _load,
              icon: const Icon(LucideIcons.refreshCw, size: 14),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      );
    }
    final shownNow = _current ?? (_login.isEmpty ? '—' : iso(_login));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'حين تنفّذ أنت عمليّةً (تفعيل، تسديد، تعديل…) تظهر بهذا الاسم بدل يوزر الصفحة. موظّفوك يبقون بأسمائهم.',
          style: AppType.muted(color: AppColors.textMid).copyWith(height: 1.6),
        ),
        const SizedBox(height: Sp.lg),
        SheetSection(
          label: 'الاسم',
          child: SheetBox(
            focused: _ctrl.text.isNotEmpty,
            child: TextField(
              key: const ValueKey('alias-field'),
              controller: _ctrl,
              enabled: !_busy,
              textInputAction: TextInputAction.done,
              inputFormatters: [LengthLimitingTextInputFormatter(ManagerAliasApi.maxChars)],
              onChanged: (_) => setState(() => _saveError = null),
              onSubmitted: (_) {
                if (_changed) _save(_ctrl.text);
              },
              style: AppType.input(),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                hintText: 'مثلاً: المكتب أو أبو علي',
                hintStyle: AppType.input(color: AppColors.textPlaceholder),
              ),
            ),
          ),
        ),
        if (_saveError != null) ...[
          const SizedBox(height: Sp.sm),
          Text(
            _saveError!,
            key: const ValueKey('alias-save-error'),
            style: AppType.muted(color: AppColors.error).copyWith(height: 1.5),
          ),
        ],
        const SizedBox(height: Sp.md),
        Text.rich(
          TextSpan(children: [
            TextSpan(text: 'يظهر الآن: ', style: AppType.muted(color: AppColors.textMid)),
            TextSpan(text: shownNow, style: AppType.bodyStrong(color: AppColors.textHi)),
          ]),
          key: const ValueKey('alias-now'),
        ),
        if (_current != null) ...[
          const SizedBox(height: Sp.xs),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              key: const ValueKey('alias-clear'),
              onPressed: _busy ? null : () => _save(''),
              icon: Icon(LucideIcons.eraser, size: 16, color: AppColors.textMid),
              label: Text('مسح الاسم — ارجع ليوزر الصفحة', style: AppType.label(color: AppColors.textMid)),
            ),
          ),
        ],
      ],
    );
  }
}
