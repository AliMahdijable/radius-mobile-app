import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/deleted_debts_api.dart';
import '../../core/util/ar_date.dart';
import '../../core/util/amount_input.dart';
import '../../core/util/format.dart';
import '../../core/widgets/app_sheet.dart';
import '../../core/widgets/design_sheet.dart';
import '../../core/widgets/permission_locked.dart';
import '../../core/widgets/sheet_scaffold.dart';
import '../../services/permissions_service.dart';
import '../../services/provider_service.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../../widgets/merged_company_strip.dart';
import 'widgets/report_permission_gate.dart';

/// «ديون المشتركين المحذوفين» (٢٣ أكتوبر) — GET/POST /api/v2/deleted-debts
/// (الخادم 5ab928a، الويب b412016). المالك: «مرات شركه تحذف يوزرات معينه احنه
/// لازم نخلي الديون تبقى للوكيل».
///
/// ثلاثة مصادر بقائمةٍ واحدة: «حذفته الشركة» (تلقائيّ — مدينٌ اختفى من القائمة
/// وأكّد الساس حذفه، رصيده من دفتر الخادم)، «يدويّ»، و«من ملف» (الاستيراد
/// بالويب). التسديد يدخل التقرير الماليّ محصَّلاً؛ الشطب يُسقطه بلا تحصيل.
/// المفاتيح `deleted_debts.view/add/pay/write_off` — ما لا يملكه الموظّف يبقى
/// بمكانه مقفلاً. «كل الشركات»: للشركة المفتوحة وحدها (كبقيّة التقارير).
class DeletedDebtsScreen extends StatefulWidget {
  const DeletedDebtsScreen({super.key});

  @override
  State<DeletedDebtsScreen> createState() => _DeletedDebtsScreenState();
}

class _DeletedDebtsScreenState extends State<DeletedDebtsScreen> {
  final _search = TextEditingController();
  DeletedDebtsPage? _page;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    if (Perms.has('deleted_debts.view')) {
      _load();
    } else {
      _loading = false;
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _page == null;
      _error = null;
    });
    final r = await DeletedDebtsApi.list();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r.page != null) {
        _page = r.page;
      } else if (_page == null) {
        _error = r.error;
      }
    });
    // تحديثٌ فشل والقائمة معروضة: تبقى كما هي، والسبب بشريط.
    if (r.page == null && _page != null) {
      showSheetSnack(context, r.error ?? 'dd.load_failed'.tr(), isError: true);
    }
  }

  Future<void> _afterSheet(Future<bool?> sheet) async {
    if (await sheet == true && mounted) await _load();
  }

  List<DeletedDebt> get _shown {
    final rows = _page?.rows ?? const <DeletedDebt>[];
    final s = _search.text.trim().toLowerCase();
    if (s.isEmpty) return rows;
    final sd = _digits(s);
    return rows.where((r) {
      final text = [r.name, r.username, r.managerUsername]
          .any((v) => (v ?? '').toLowerCase().contains(s));
      return text ||
          (sd.length >= 3 &&
              (r.phone ?? '').contains(sd.replaceFirst(RegExp(r'^0'), '')));
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final page = _page;
    final enabled = page?.enabled == true;
    return ReportPermissionGate(
      permission: 'deleted_debts.view',
      title: 'reports.deleted_debts'.tr(),
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(
          backgroundColor: AppColors.surface,
          elevation: 0,
          scrolledUnderElevation: 0,
          title: Text(
            'reports.deleted_debts'.tr(),
            style:
                AppType.title(color: AppColors.textHi).copyWith(fontSize: 16),
          ),
          iconTheme: IconThemeData(color: AppColors.textHi),
        ),
        floatingActionButton: enabled ? _addButton() : null,
        body: SafeArea(
          child: RefreshIndicator(
            onRefresh: _load,
            color: AppColors.brand,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(
                  Sp.lg, Sp.md, Sp.lg, Sp.huge + Sp.huge),
              children: [
                const MergedOpenCompanyNote(
                  textKey: 'merged.deleted_debts_note',
                  padding: EdgeInsets.only(bottom: Sp.md),
                ),
                ..._content(page),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _content(DeletedDebtsPage? page) {
    if (_loading) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 48),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    if (page == null) {
      return [
        _Notice(
          icon: LucideIcons.userX,
          text: _error ?? 'dd.load_failed'.tr(),
          action: TextButton.icon(
            onPressed: _load,
            icon: const Icon(LucideIcons.refreshCw, size: 16),
            label: Text('common.retry'.tr()),
          ),
        ),
      ];
    }
    if (!page.enabled) {
      return [_Notice(icon: LucideIcons.userX, text: 'dd.off'.tr())];
    }
    final shown = _shown;
    return [
      Row(
        children: [
          Expanded(
            child: _Kpi(
              icon: LucideIcons.userX,
              label: 'dd.kpi_count'.tr(),
              value: formatIQD(page.count),
              tone: AppTone.danger,
            ),
          ),
          const SizedBox(width: Sp.sm),
          Expanded(
            child: _Kpi(
              icon: LucideIcons.handCoins,
              label: 'dd.kpi_total'.tr(),
              value: _money(page.total),
              tone: AppTone.warning,
            ),
          ),
        ],
      ),
      const SizedBox(height: Sp.md),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(LucideIcons.info, size: 14, color: AppColors.textLow),
          ),
          const SizedBox(width: Sp.x6),
          Expanded(
            child: Text(
              'dd.info'.tr(),
              style: AppType.muted(color: AppColors.textMid)
                  .copyWith(fontSize: 12.5, height: 1.6),
            ),
          ),
        ],
      ),
      if (page.rows.isNotEmpty) ...[
        const SizedBox(height: Sp.md),
        SheetSearchField(
          controller: _search,
          hint: 'dd.search_hint'.tr(),
          onChanged: (_) => setState(() {}),
        ),
      ],
      const SizedBox(height: Sp.md),
      if (page.rows.isEmpty)
        _Notice(icon: LucideIcons.userX, text: 'dd.empty'.tr())
      else if (shown.isEmpty)
        _Notice(icon: LucideIcons.search, text: 'dd.no_results'.tr())
      else
        for (int i = 0; i < shown.length; i++) ...[
          if (i > 0) const SizedBox(height: Sp.sm),
          _DebtTile(
            row: shown[i],
            onPay: () => _afterSheet(_showPaySheet(context, shown[i])),
            onWriteOff: () =>
                _afterSheet(_showWriteOffSheet(context, shown[i])),
          ),
        ],
      if (page.truncated) ...[
        const SizedBox(height: Sp.md),
        Text(
          'dd.truncated'.tr(),
          textAlign: TextAlign.center,
          style: AppType.muted().copyWith(fontSize: 11.5),
        ),
      ],
    ];
  }

  Widget _addButton() {
    final can = Perms.has('deleted_debts.add');
    return FloatingActionButton.extended(
      backgroundColor: can ? AppColors.warningFill : LockedStyle.box,
      foregroundColor: can ? AppColors.onBrand : LockedStyle.glyph,
      onPressed: can
          ? () => _afterSheet(_showAddSheet(context))
          : () => showNoPermission(context, action: true),
      icon: Icon(can ? LucideIcons.plus : LucideIcons.lock, size: 16),
      label: Text('dd.add'.tr()),
    );
  }
}

String _money(num v) => '${formatIQD(v)} ${'common.currency'.tr()}';

/// ٠-٩ ⇒ 0-9 ثمّ الخانات وحدها (بحث الهاتف).
String _digits(String s) => s
    .replaceAllMapped(RegExp('[٠-٩]'),
        (m) => '${'٠١٢٣٤٥٦٧٨٩'.indexOf(m[0]!)}')
    .replaceAll(RegExp(r'[^0-9]'), '');

String _originLabel(String origin) => switch (origin) {
      'auto' => 'dd.origin_auto'.tr(),
      'import' => 'dd.origin_import'.tr(),
      _ => 'dd.origin_manual'.tr(),
    };

class _Kpi extends StatelessWidget {
  const _Kpi({
    required this.icon,
    required this.label,
    required this.value,
    required this.tone,
  });
  final IconData icon;
  final String label;
  final String value;
  final AppTone tone;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: tone.fill),
              const SizedBox(width: Sp.xs),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.micro(),
                ),
              ),
            ],
          ),
          const SizedBox(height: Sp.x6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              value,
              style: AppType.label(color: tone.fill)
                  .copyWith(fontSize: 17, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text, this.action});
  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Sp.huge),
      child: Column(
        children: [
          Icon(icon, size: 34, color: AppColors.textLow),
          const SizedBox(height: 10),
          Text(
            text,
            textAlign: TextAlign.center,
            style: AppType.label(color: AppColors.textMid)
                .copyWith(height: 1.6),
          ),
          if (action != null) ...[
            const SizedBox(height: Sp.sm),
            action!,
          ],
        ],
      ),
    );
  }
}

/// صفّ دين: الاسم ومصدره والمبلغ، ثمّ اليوزر/المدير/الهاتف/التاريخ والملاحظة،
/// وزرّا التسديد والشطب — المقفل منهما يبقى بمكانه.
class _DebtTile extends StatelessWidget {
  const _DebtTile({
    required this.row,
    required this.onPay,
    required this.onWriteOff,
  });
  final DeletedDebt row;
  final VoidCallback onPay;
  final VoidCallback onWriteOff;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final phone = row.localPhone;
    final at = row.at;
    final meta = <Widget>[
      if (row.username != null)
        _MetaText(row.username!, icon: LucideIcons.atSign, ltr: true),
      if (row.managerUsername != null)
        _MetaText('dd.manager'.tr(args: [row.managerUsername!]),
            icon: LucideIcons.user),
      if (phone != null)
        InkWell(
          onTap: () => _call(context, phone),
          borderRadius: BorderRadius.circular(R.sm),
          child: _MetaText(phone, icon: LucideIcons.phone, ltr: true),
        ),
      if (at != null)
        _MetaText(iqDateOf(at), icon: LucideIcons.calendar),
    ];
    final auto = row.isAuto;
    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Wrap(
                  spacing: Sp.x6,
                  runSpacing: Sp.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      row.name,
                      style: AppType.label(color: AppColors.textHi).copyWith(
                          fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: Sp.x6, vertical: 2),
                      decoration: BoxDecoration(
                        color: auto
                            ? AppColors.dangerSoftBg
                            : AppColors.surfaceSunken,
                        borderRadius: BorderRadius.circular(R.sm),
                      ),
                      child: Text(
                        _originLabel(row.origin),
                        style: AppType.micro(
                          color: auto
                              ? AppColors.dangerOnSoft
                              : AppColors.textMid,
                        ).copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Sp.sm),
              Text(
                _money(row.debt),
                style: AppType.label(color: AppColors.error)
                    .copyWith(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          if (meta.isNotEmpty) ...[
            const SizedBox(height: Sp.x6),
            Wrap(spacing: Sp.md, runSpacing: Sp.xs, children: meta),
          ],
          if (row.note != null) ...[
            const SizedBox(height: Sp.x6),
            Text(
              row.note!,
              style: AppType.muted(color: AppColors.textMid)
                  .copyWith(fontSize: 12.5, height: 1.5),
            ),
          ],
          const SizedBox(height: Sp.sm),
          Row(
            children: [
              Expanded(
                child: _ActionButton(
                  label: 'dd.pay'.tr(),
                  icon: LucideIcons.handCoins,
                  tone: AppTone.success,
                  locked: !Perms.has('deleted_debts.pay'),
                  onTap: onPay,
                ),
              ),
              const SizedBox(width: Sp.sm),
              Expanded(
                child: _ActionButton(
                  label: 'dd.write_off'.tr(),
                  icon: LucideIcons.eraser,
                  tone: AppTone.danger,
                  locked: !Perms.has('deleted_debts.write_off'),
                  onTap: onWriteOff,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// كـ`_call` بتفاصيل المشترك: الفتح مباشرةً (فحص `tel:` يكذب على الآيفون).
  static Future<void> _call(BuildContext ctx, String phone) async {
    var ok = false;
    try {
      ok = await launchUrl(Uri.parse('tel:$phone'),
          mode: LaunchMode.externalApplication);
    } catch (_) {
      ok = false;
    }
    if (ok || !ctx.mounted) return;
    showSheetSnack(ctx, 'لا يمكن فتح الرابط', isError: true);
  }
}

class _MetaText extends StatelessWidget {
  const _MetaText(this.text, {required this.icon, this.ltr = false});
  final String text;
  final IconData icon;
  final bool ltr;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: AppColors.textLow),
        const SizedBox(width: 3),
        Text(
          text,
          textDirection: ltr ? TextDirection.ltr : null,
          style: AppType.muted(color: AppColors.textMid)
              .copyWith(fontSize: 11.5),
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.tone,
    required this.locked,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final AppTone tone;
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final fg = locked ? LockedStyle.glyph : tone.fill;
    final button = Material(
      color: locked ? LockedStyle.box : tone.softBg,
      borderRadius: BorderRadius.circular(R.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(R.md),
        onTap: locked
            ? () => showNoPermission(context, action: true)
            : onTap,
        child: SizedBox(
          height: 38,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(locked ? LucideIcons.lock : icon, size: 15, color: fg),
              const SizedBox(width: Sp.x6),
              Text(
                label,
                style: AppType.label(color: fg)
                    .copyWith(fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
    if (!locked) return button;
    return Semantics(
      button: true,
      label: 'locked.a11y'.tr(args: [label]),
      excludeSemantics: true,
      child: button,
    );
  }
}

// ═══════════════════════════ الشيتات ═══════════════════════════

Future<bool?> _showSheet(BuildContext context, Widget sheet) {
  return showAppSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.scrim,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => sheet,
  );
}

Future<bool?> _showAddSheet(BuildContext context) =>
    _showSheet(context, const _AddSheet());

Future<bool?> _showPaySheet(BuildContext context, DeletedDebt row) =>
    _showSheet(context, _PaySheet(row: row));

Future<bool?> _showWriteOffSheet(BuildContext context, DeletedDebt row) =>
    _showSheet(context, _WriteOffSheet(row: row));

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String body,
  required Color color,
  String? yes,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(
        title,
        style: AppType.label(color: AppColors.textHi)
            .copyWith(fontSize: 16, fontWeight: FontWeight.w700),
      ),
      content: Text(body, style: AppType.subtitle(color: AppColors.textMid)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text('common.cancel'.tr()),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: color),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(yes ?? 'common.confirm'.tr()),
        ),
      ],
    ),
  );
  return ok == true;
}

/// حقلٌ نصّيّ بصندوق الشيت — الاسم والهاتف واليوزر والملاحظة والسبب.
class _SheetText extends StatelessWidget {
  const _SheetText({
    required this.controller,
    required this.icon,
    this.hint,
    this.maxLength = 100,
    this.keyboardType,
    this.ltr = false,
    this.maxLines = 1,
    this.onChanged,
  });
  final TextEditingController controller;
  final IconData icon;
  final String? hint;
  final int maxLength;
  final TextInputType? keyboardType;
  final bool ltr;
  final int maxLines;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return SheetBox(
      icon: icon,
      alignTop: maxLines > 1,
      child: TextField(
        controller: controller,
        style: AppType.input(),
        maxLength: maxLength,
        maxLines: maxLines,
        minLines: 1,
        keyboardType: keyboardType,
        textDirection: ltr ? TextDirection.ltr : null,
        onChanged: onChanged,
        decoration: InputDecoration(
          isDense: true,
          counterText: '',
          border: InputBorder.none,
          contentPadding: EdgeInsets.zero,
          hintText: hint,
          hintStyle: AppType.input(color: AppColors.textPlaceholder),
        ),
      ),
    );
  }
}

class _AddSheet extends StatefulWidget {
  const _AddSheet();

  @override
  State<_AddSheet> createState() => _AddSheetState();
}

class _AddSheetState extends State<_AddSheet> {
  final _name = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _phone = TextEditingController();
  final _username = TextEditingController();
  final _note = TextEditingController();
  int _amount = 0;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _amountCtrl.dispose();
    _phone.dispose();
    _username.dispose();
    _note.dispose();
    super.dispose();
  }

  bool get _amountOk =>
      _amount > 0 && _amount % _kStep == 0;
  bool get _canSubmit => !_busy && _name.text.trim().length >= 2 && _amountOk;

  Future<void> _submit({bool confirmRepeat = false}) async {
    setState(() => _busy = true);
    final name = _name.text.trim();
    final r = await DeletedDebtsApi.add(
      name: name,
      amount: _amount,
      phone: _phone.text.trim(),
      username: _username.text.trim(),
      note: _note.text.trim(),
      confirmRepeat: confirmRepeat,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (r.ok) {
      showSheetSnack(context,
          'dd.added'.tr(namedArgs: {'name': name, 'amount': _money(_amount)}));
      Navigator.of(context).pop(true);
      return;
    }
    if (r.code == 'RECENT_DUPLICATE' && !confirmRepeat) {
      final again = await _confirm(
        context,
        title: 'dd.repeat_title'.tr(),
        body: '${r.message ?? ''}\n\n${'dd.repeat_q'.tr()}',
        color: AppColors.warningFill,
        yes: 'dd.repeat_yes'.tr(),
      );
      if (again && mounted) await _submit(confirmRepeat: true);
      return;
    }
    showSheetSnack(context, r.message ?? 'dd.not_saved'.tr(), isError: true);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.userX,
        title: 'dd.add_title'.tr(),
        subtitle: 'dd.add_subtitle'.tr(),
        tint: AppColors.warningFill,
        tintBg: AppColors.warningSoftBg,
        onClose: () => Navigator.of(context).pop(),
      ),
      footer: SheetFooterBar(
        label: _busy ? 'dd.adding'.tr() : 'dd.add'.tr(),
        icon: LucideIcons.plus,
        color: AppColors.warningFill,
        enabled: _canSubmit,
        busy: _busy,
        onPressed: () => _submit(),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetSection(
            label: '${'dd.f_name'.tr()} *',
            child: _SheetText(
              controller: _name,
              icon: LucideIcons.user,
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(height: Sp.lg),
          SheetSection(
            label: '${'dd.f_amount'.tr()} *',
            footnote:
                _amount > 0 && !_amountOk ? 'dd.step_250'.tr() : null,
            child: SheetBox(
              focused: _amount > 0,
              radius: 18,
              padding:
                  const EdgeInsets.symmetric(horizontal: Sp.lg, vertical: 14),
              child: AmountTextField(
                controller: _amountCtrl,
                currency: 'common.currency'.tr(),
                onValue: (v) => setState(() => _amount = v),
              ),
            ),
          ),
          const SizedBox(height: Sp.lg),
          SheetSection(
            label: 'dd.f_phone'.tr(),
            hint: 'dd.optional'.tr(),
            child: _SheetText(
              controller: _phone,
              icon: LucideIcons.phone,
              hint: '07XXXXXXXXX',
              maxLength: 20,
              keyboardType: TextInputType.phone,
              ltr: true,
            ),
          ),
          const SizedBox(height: Sp.lg),
          SheetSection(
            label: 'dd.f_username'.tr(),
            hint: 'dd.optional'.tr(),
            // فحص «ما زال بالساس» لـSAS4 وحده — ايرث لنك تُحفظ كما كُتبت.
            footnote:
                ProviderService.isEarthlink ? null : 'dd.username_foot'.tr(),
            child: _SheetText(
              controller: _username,
              icon: LucideIcons.atSign,
              maxLength: 64,
              ltr: true,
            ),
          ),
          const SizedBox(height: Sp.lg),
          SheetSection(
            label: 'dd.f_note'.tr(),
            hint: 'dd.optional'.tr(),
            child: _SheetText(
              controller: _note,
              icon: LucideIcons.fileText,
              hint: 'dd.note_hint'.tr(),
              maxLength: 200,
            ),
          ),
        ],
      ),
    );
  }
}

/// أصغر ورقة — الخادم يرفض غير مضاعفاتها (`deletedDebts.STEP`).
const _kStep = 250;

class _PaySheet extends StatefulWidget {
  const _PaySheet({required this.row});
  final DeletedDebt row;

  @override
  State<_PaySheet> createState() => _PaySheetState();
}

class _PaySheetState extends State<_PaySheet> {
  final _amountCtrl = TextEditingController();
  final _comment = TextEditingController();
  int _amount = 0;
  bool _busy = false;

  /// الدين بالدينار الصحيح — الخادم يحفظ أرقاماً صحيحة (مضاعفات 250).
  late final int _debt = widget.row.debt.round();

  @override
  void dispose() {
    _amountCtrl.dispose();
    _comment.dispose();
    super.dispose();
  }

  bool get _full => _amount == _debt;
  bool get _amountOk =>
      _amount > 0 &&
      _amount <= _debt &&
      (_full || _amount % _kStep == 0);

  void _setAll() {
    _amountCtrl.text = AmountShorthand.format(_debt);
    setState(() => _amount = _debt);
  }

  String? get _problem {
    if (_amount <= 0 || _amountOk) return null;
    if (_amount > _debt) {
      return 'dd.over_debt'.tr(args: [_money(_debt)]);
    }
    return 'dd.step_250'.tr();
  }

  Future<void> _submit() async {
    final ok = await _confirm(
      context,
      title: 'dd.pay_confirm_title'.tr(),
      body: 'dd.pay_confirm_body'
          .tr(namedArgs: {'amount': _money(_amount), 'name': widget.row.name}),
      color: AppColors.success,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    final c = _comment.text.trim();
    final r = await DeletedDebtsApi.pay(
      key: widget.row.key,
      amount: _full ? null : _amount,
      payAll: _full,
      comment: c.isEmpty ? null : c,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (!r.ok) {
      showSheetSnack(context, r.message ?? 'dd.pay_failed'.tr(),
          isError: true);
      return;
    }
    // المبلغ من ردّ الخادم: «الكل» يسدّد رصيده المحفوظ لا الرقم المعروض.
    showSheetSnack(
      context,
      r.remaining > 0
          ? 'dd.paid_part'.tr(namedArgs: {
              'paid': _money(r.paid),
              'rem': _money(r.remaining),
            })
          : 'dd.paid_full'.tr(namedArgs: {
              'name': widget.row.name,
              'paid': _money(r.paid),
            }),
    );
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final problem = _problem;
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.handCoins,
        title: 'dd.pay_title'.tr(args: [widget.row.name]),
        subtitle: 'dd.pay_subtitle'.tr(),
        tint: AppColors.success,
        tintBg: AppColors.successSoftBg,
        onClose: () => Navigator.of(context).pop(),
      ),
      footer: SheetFooterBar(
        label: _busy ? 'dd.paying'.tr() : 'dd.pay'.tr(),
        icon: LucideIcons.check,
        color: AppColors.success,
        enabled: !_busy && _amountOk,
        busy: _busy,
        onPressed: _submit,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetSummaryBox(
            label: 'dd.current_debt'.tr(),
            value: _money(_debt),
            valueColor: AppColors.error,
          ),
          const SizedBox(height: Sp.lg),
          SheetSection(
            label: 'dd.f_received'.tr(),
            gap: 9,
            footnote: problem,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SheetBox(
                  focused: _amount > 0,
                  radius: 18,
                  padding: const EdgeInsets.symmetric(
                      horizontal: Sp.lg, vertical: 14),
                  child: AmountTextField(
                    controller: _amountCtrl,
                    currency: 'common.currency'.tr(),
                    // دينٌ دون الألف (باقٍ بعد تسديدٍ جزئيّ) يُكتب كما هو.
                    shorthand: _debt >= 1000,
                    onValue: (v) => setState(() => _amount = v),
                  ),
                ),
                const SizedBox(height: 9),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    SheetQuickChip(
                      label: 'dd.all'.tr(),
                      selected: _full,
                      onTap: _setAll,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: Sp.lg),
          _SheetText(
            controller: _comment,
            icon: LucideIcons.fileText,
            hint: 'dd.f_comment'.tr(),
            maxLength: 200,
          ),
          if (_amountOk) ...[
            const SizedBox(height: Sp.lg),
            SheetResultBanner(
              icon: LucideIcons.arrowLeft,
              label: 'dd.remaining_after'.tr(),
              value: _money(_debt - _amount),
              tone: _full ? AppTone.success : AppTone.warning,
            ),
          ],
        ],
      ),
    );
  }
}

class _WriteOffSheet extends StatefulWidget {
  const _WriteOffSheet({required this.row});
  final DeletedDebt row;

  @override
  State<_WriteOffSheet> createState() => _WriteOffSheetState();
}

class _WriteOffSheetState extends State<_WriteOffSheet> {
  final _reason = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  bool get _canSubmit => !_busy && _reason.text.trim().length >= 2;

  Future<void> _submit() async {
    final ok = await _confirm(
      context,
      title: 'dd.wo_confirm_title'.tr(),
      body: 'dd.wo_confirm_body'.tr(namedArgs: {
        'amount': _money(widget.row.debt),
        'name': widget.row.name,
      }),
      color: AppColors.errorFill,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    final r = await DeletedDebtsApi.writeOff(
        key: widget.row.key, reason: _reason.text.trim());
    if (!mounted) return;
    setState(() => _busy = false);
    if (!r.ok) {
      showSheetSnack(context, r.message ?? 'dd.wo_failed'.tr(),
          isError: true);
      return;
    }
    showSheetSnack(context, 'dd.written_off'.tr(args: [widget.row.name]));
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.eraser,
        title: 'dd.wo_title'.tr(args: [widget.row.name]),
        subtitle: 'dd.wo_subtitle'.tr(args: [_money(widget.row.debt)]),
        tint: AppColors.errorFill,
        tintBg: AppColors.dangerSoftBg,
        onClose: () => Navigator.of(context).pop(),
      ),
      footer: SheetFooterBar(
        label: _busy ? 'dd.writing_off'.tr() : 'dd.wo_btn'.tr(),
        icon: LucideIcons.eraser,
        color: AppColors.errorFill,
        enabled: _canSubmit,
        busy: _busy,
        onPressed: _submit,
      ),
      body: SheetSection(
        label: '${'dd.f_reason'.tr()} *',
        child: _SheetText(
          controller: _reason,
          icon: LucideIcons.fileText,
          hint: 'dd.reason_hint'.tr(),
          maxLength: 200,
          maxLines: 3,
          onChanged: (_) => setState(() {}),
        ),
      ),
    );
  }
}

/// بطاقة التقارير: تظهر حين تُفعَّل الميزة للحساب وحده (GET ⇒ `enabled`)،
/// ووصفها عددها ومجموعها — كبطاقة الويب. موظّفٌ بلا `deleted_debts.view`
/// لا يسأل الخادم أصلاً (يردّه 403) فلا بطاقة، والويب كذلك.
class DeletedDebtsHubSummary {
  DeletedDebtsHubSummary._();

  /// تعذّر السؤال (شبكة/خادم) ⇒ [previous] كما هو: البطاقة لا تختفي لعطلٍ عابر.
  static Future<DeletedDebtsPage?> fetch({DeletedDebtsPage? previous}) async {
    if (!Perms.has('deleted_debts.view')) return null;
    final r = await DeletedDebtsApi.list();
    final p = r.page;
    if (p == null) return previous;
    return p.enabled ? p : null;
  }

  static String subtitle(DeletedDebtsPage p) => p.count > 0
      ? 'reports.deleted_debts_count'
          .tr(namedArgs: {'count': formatIQD(p.count), 'total': _money(p.total)})
      : 'reports.deleted_debts_hint'.tr();
}
