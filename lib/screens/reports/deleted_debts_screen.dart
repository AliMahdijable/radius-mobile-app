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
import '../../models/merged_company.dart';
import '../../services/merged_mode.dart';
import '../../services/merged_report_loader.dart';
import '../../services/permissions_service.dart';
import '../../services/provider_service.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../../widgets/company_tag.dart';
import '../account/company_switch_sheet.dart';
import 'v2/debt_age.dart';
import 'v2/report_kit.dart';
import 'widgets/report_export.dart';
import 'widgets/report_permission_gate.dart';
import '../../services/merged_text.dart';

/// «ديون المشتركين المحذوفين» (٢٣ أكتوبر) — GET/POST /api/v2/deleted-debts
/// (الخادم 5ab928a، الويب b412016). المالك: «مرات شركه تحذف يوزرات معينه احنه
/// لازم نخلي الديون تبقى للوكيل».
///
/// ثلاثة مصادر بقائمةٍ واحدة: «حذفته الشركة» (تلقائيّ — مدينٌ اختفى من القائمة
/// وأكّد الساس حذفه، رصيده من دفتر الخادم)، «يدويّ»، و«من ملف» (الاستيراد
/// بالويب). التسديد يدخل التقرير الماليّ محصَّلاً؛ الشطب يُسقطه بلا تحصيل.
/// المفاتيح `deleted_debts.view/add/pay/write_off` — ما لا يملكه الموظّف يبقى
/// بمكانه مقفلاً. «كل الشركات» (٨ نوفمبر): ديون محذوفي كلّ الشركات معاً، كلّ دينٍ بشارة شركته، والتسديد/الشطب/الإضافة/القرار
/// للشركة المفتوحة وحدها — دين شركةٍ أخرى يُفتح من شركته.
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

  /// قرار دينٍ مكرّر قيد الإرسال (مفتاح صفّه اليدويّ) — زرٌّ واحد في المرّة.
  String? _twinBusy;

  // ── «كل الشركات» (٨ نوفمبر — المالك: «نعم لازم نسوي كلشي»): الشاشة نفسها وشريط الشركات أعلاها؛ قائمة كلّ شركةٍ بطلبٍ موجَّه
  // لها، والأرقام مجموع المقروء وحده — المتعذّرة تُسمّى لا تُعدّ صفراً. [_page] في الوضع = صفحة الشركة المفتوحة (القرار والإضافة
  // لها وحدها، بلا مفتاح)، ودين شركةٍ أخرى يُدار من داخلها.
  bool get _mergedOn => MergedMode.active.value;
  MergedReport<DeletedDebtsPage>? _merged;
  String? _openKey;
  int _gen = 0;

  @override
  void initState() {
    super.initState();
    MergedMode.active.addListener(_onMergedMode);
    if (Perms.has('deleted_debts.view')) {
      _load();
    } else {
      _loading = false;
    }
  }

  @override
  void dispose() {
    _gen++;
    MergedMode.active.removeListener(_onMergedMode);
    _search.dispose();
    super.dispose();
  }

  void _onMergedMode() {
    if (!mounted || !Perms.has('deleted_debts.view')) return;
    _merged = null;
    _openKey = null;
    _page = null;
    _load();
  }

  static bool _servedFor(MergedCompany c) =>
      c.provider == MergedProvider.sas4 || c.provider == MergedProvider.earthlink || c.provider == MergedProvider.kit;

  Future<void> _load() async {
    final gen = ++_gen;
    if (_mergedOn) {
      setState(() {
        _loading = _merged == null;
        _error = null;
      });
      final openAdmin = await MergedMode.openAdminId();
      // الوطني بلا ديون محذوفين بعد (الخادم يرفضها)، وفايبر اكس من الموقع — لا تُطلبان
      final m = await loadMergedReport<DeletedDebtsPage>(
        perms: const ['deleted_debts.view'],
        supports: _servedFor,
        fetch: (c) async {
          final r = await DeletedDebtsApi.list();
          final p = r.page;
          return (
            ok: p != null,
            rows: p == null ? const <DeletedDebtsPage>[] : [p],
            error: r.error,
            note: p != null && p.enabled && p.truncated ? 'dd.truncated'.tr() : null,
          );
        },
      );
      if (!mounted || gen != _gen || !_mergedOn) return;
      String? openKey;
      DeletedDebtsPage? openPage;
      for (final p in m.parts) {
        if (openAdmin != null && openAdmin.isNotEmpty && p.company.adminId == openAdmin) {
          openKey = p.company.key;
          openPage = p.rows?.firstOrNull;
        }
      }
      setState(() {
        _loading = false;
        _merged = m;
        _openKey = openKey;
        _page = openPage;
        _error = m.parts.any((p) => p.ok) ? null : 'dd.load_failed'.tr();
      });
      return;
    }
    setState(() {
      _loading = _page == null;
      _error = null;
    });
    final r = await DeletedDebtsApi.list();
    if (!mounted || gen != _gen || _mergedOn) return;
    setState(() {
      _merged = null;
      _openKey = null;
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

  /* ── الدين المكرّر (٢ نوفمبر — كالموقع: «نفس الدين» يُحصَّل مرّةً، «دينان مختلفان» كلٌّ وحده، و«أكمل القرار» لما حُفظ جزؤه) ── */

  Future<void> _twinSame(PendingTwin t) async {
    var keep = t.partialKeep;
    if (keep == null && !t.differ) {
      // مبلغٌ واحد: تأكيدٌ صريح قبل الحسم (مراجعة r8 — نقرةٌ واحدة كانت تحسم)؛ الإغلاق لا يحفظ شيئاً
      final go = await showConfirmSheet(
        context,
        title: 'نفس الدين؟',
        message: '«${t.name}»: ${_money(t.manualOrig ?? t.manualDebt)} مسجَّلٌ يدويّاً و${t.autoKey.startsWith('d') ? 'بسجلّ ديونك' : 'بالدفتر'} — '
            'يُحصَّل مرّةً واحدة ويُشطب المكرّر (ليس نقداً).',
        confirmLabel: 'نعم، نفس الدين',
        cancelLabel: 'تراجع',
        icon: LucideIcons.scale,
      );
      if (go != true || !mounted) return;
    }
    if (keep == null && t.differ) {
      // خياران صريحان؛ الإغلاق (X أو السحب) لا يقرّر شيئاً — مراجعة r8: كان الإغلاق يعني «المسجَّل يدويّاً» فيُحسم «نفس الدين» بلا قصد.
      keep = await _pickTwinAmount(t);
      if (!mounted || keep == null) return;
    }
    await _decideTwin(t, same: true, keep: keep ?? 'manual');
  }

  String _ledgerWord(PendingTwin t) => t.autoKey.startsWith('d') ? 'سجلّ ديونك' : 'الدفتر';

  /// «أيّ المبلغين صحيح؟» ⇒ 'ledger' أو 'manual'، أو null إن أُغلقت بلا اختيار. [only] = الخيار الصحيح وحده (ردّ الخادم).
  Future<String?> _pickTwinAmount(PendingTwin t, {String? only}) {
    final manual = 'المسجَّل يدويّاً ${_money(t.manualOrig ?? t.manualDebt)}';
    final ledger = 'مبلغ ${_ledgerWord(t)} ${_money(t.autoDebt ?? 0)}';
    return showAppSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: AppColors.scrim,
      builder: (ctx) => DesignSheet(
        header: SheetHeaderBar(
          icon: LucideIcons.scale,
          title: 'أيّ المبلغين صحيح؟',
          subtitle: '«${t.name}» — نفس الدين',
          onClose: () => Navigator.of(ctx).pop(),
        ),
        body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(
            only == null
                ? 'المسجَّل يدويّاً ${_money(t.manualOrig ?? t.manualDebt)} و${t.autoKey.startsWith('d') ? 'بسجلّ ديونك' : 'دين الدفتر'} ${_money(t.autoDebt ?? 0)} — '
                    'يُحصَّل الصحيح مرّةً واحدة ويُشطب الآخر (ليس نقداً). الإغلاق لا يحفظ شيئاً.'
                : only == 'ledger'
                    ? 'تحرّك دين ${_ledgerWord(t)} بعد الربط (تسديدٌ أو تفعيل) — يُحصَّل من ${_ledgerWord(t)} ويُشطب الصفّ اليدويّ. الإغلاق لا يحفظ شيئاً.'
                    : 'لا دين على ${_ledgerWord(t)} الآن — يبقى التحصيل من صفّك اليدويّ. الإغلاق لا يحفظ شيئاً.',
            style: AppType.rowValue(color: AppColors.textBody).copyWith(height: 1.6),
          ),
          const SizedBox(height: Sp.lg),
          if (only != 'manual') _TwinAmountOption(label: ledger, icon: LucideIcons.bookOpen, onTap: () => Navigator.of(ctx).pop('ledger')),
          if (only == null) const SizedBox(height: Sp.sm),
          if (only != 'ledger') _TwinAmountOption(label: manual, icon: LucideIcons.pencil, onTap: () => Navigator.of(ctx).pop('manual')),
        ]),
      ),
    );
  }

  Future<void> _twinDistinct(PendingTwin t) async {
    final go = await showConfirmSheet(
      context,
      title: 'دينان مختلفان؟',
      message: 'يبقى الصفّ اليدويّ ودين الدفتر كلٌّ يُحصَّل وحده — لا يُعاد ربطهما.',
      confirmLabel: 'نعم، دينان مختلفان',
      cancelLabel: 'تراجع',
      icon: LucideIcons.split,
      tone: AppTone.warning,
    );
    if (go != true || !mounted) return;
    await _decideTwin(t, same: false);
  }

  Future<void> _decideTwin(PendingTwin t, {required bool same, String? keep}) async {
    if (_twinBusy != null) return;
    setState(() => _twinBusy = t.manualKey);
    final r = await DeletedDebtsApi.decideTwin(
      manualKey: t.manualKey,
      same: same,
      keep: keep,
      seenAutoDebt: t.partialKeep == null ? t.autoDebt : null,
    );
    if (!mounted) return;
    setState(() => _twinBusy = null);
    if (r.ok) {
      final d = r.data;
      final wm = (d['written_off_manual'] as num?) ?? 0;
      final msg = !same
          ? '«${t.name}»: دينان مختلفان — كلٌّ يُحصَّل وحده'
          : d['resumed'] == true
              ? '«${t.name}»: اكتمل القرار — ${d['keep'] == 'ledger' ? 'يُحصَّل من دفتر الشركة' : wm > 0 ? 'الدين مسدَّدٌ بدفتر الشركة وشُطب صفّك اليدويّ' : 'يُحصَّل من صفّك اليدويّ'}'
              : d['keep'] == 'ledger'
                  ? '«${t.name}»: نفس الدين بمبلغ دفتر الشركة — شُطب الصفّ اليدويّ ويُحصَّل من الدفتر'
                  : wm > 0
                      ? '«${t.name}»: دينه مسدَّدٌ بدفتر الشركة — شُطب الصفّ اليدويّ'
                      : d['manual_kept'] == true
                          ? '«${t.name}»: نفس الدين — لا دين على دفتر الشركة الآن، ويبقى التحصيل من صفّك اليدويّ'
                          : '«${t.name}»: نفس الدين — صُفّر من دفتر الشركة، ويُحصَّل من صفّك اليدويّ';
      showSheetSnack(context, msg, duration: const Duration(seconds: 5));
      await _load();
      return;
    }
    showSheetSnack(context, r.message ?? 'تعذّر حفظ القرار — أعد المحاولة', isError: true, duration: const Duration(seconds: 10), autoExplain: false);
    // البطاقة قديمة (حُفظ جزءٌ، أو حُسم، أو تغيّر دين الدفتر، أو تعذّر التأكّد) ⇒ تُقرأ من جديد
    const refresh = {
      'TWIN_PARTIAL', 'TWIN_RESUME_SAME', 'TWIN_DECIDED', 'TWIN_AUTO_CHANGED', 'TWIN_UNVERIFIED', 'TWIN_KEEP_REQUIRED',
      // تحرّك الدين بعد الربط، أو المبلغ الصحيح غير ما اختير (الخادم ٢ نوفمبر)
      'TWIN_MOVED', 'TWIN_KEEP_LEDGER', 'TWIN_KEEP_MANUAL',
    };
    if (refresh.contains(r.code)) await _load();
    // «نفس الدين» والمبلغ الصحيح غير ما أُرسل (الخادم ٢ نوفمبر): يُعرض الخيار الوحيد الصحيح صريحاً بدل طريقٍ مسدود — مرّةً واحدة
    if (same && (r.code == 'TWIN_KEEP_LEDGER' || r.code == 'TWIN_KEEP_MANUAL') && mounted) {
      final need = r.code == 'TWIN_KEEP_LEDGER' ? 'ledger' : 'manual';
      if (keep == need) return;
      final fresh = _page?.pendingTwins.where((x) => x.manualKey == t.manualKey).firstOrNull ?? t;
      final pick = await _pickTwinAmount(fresh, only: need);
      if (pick == need && mounted) await _decideTwin(fresh, same: true, keep: need);
    }
  }

  static bool _matches(DeletedDebt r, String s) {
    final sd = _digits(s);
    final text = [r.name, r.username, r.managerUsername]
        .any((v) => (v ?? '').toLowerCase().contains(s));
    return text ||
        (sd.length >= 3 &&
            (r.phone ?? '').contains(sd.replaceFirst(RegExp(r'^0'), '')));
  }

  /* ── «كل الشركات» ── */

  /// الشركات المختارة في الشريط (فارغ = كلّها) — اختيارٌ لهذا التقرير وحده كبقيّة التقارير الموحّدة.
  Set<String> _companies = {};

  bool _picked(String key) => _companies.isEmpty || _companies.contains(key);

  /// صفحات الشركات المعروضة المفعّلة، بترتيب الشريط.
  List<({MergedCompany c, DeletedDebtsPage page})> get _mergedPages {
    final m = _merged;
    if (m == null) return const [];
    return [
      for (final p in m.parts)
        if (_picked(p.company.key) && p.ok && p.rows!.isNotEmpty && p.rows!.first.enabled) (c: p.company, page: p.rows!.first),
    ];
  }

  /// دينٌ في شركةٍ غير المفتوحة: تسديده وشطبه من داخلها.
  Future<void> _openOther(String key) async {
    final name = MergedMode.companyOf(key)?.name ?? mergedWord('شركته', 'صفحته');
    final go = await showConfirmSheet(
      context,
      title: 'هذا الدين في «$name»',
      message: 'التسديد والشطب من داخل «$name» — افتحها لتديره',
      confirmLabel: 'فتح «$name»',
      cancelLabel: 'إلغاء',
      icon: LucideIcons.arrowLeftRight,
    );
    if (go == true && mounted) await showCompanySwitchSheet(context);
  }

  /// زرّ الإضافة: للشركة المفتوحة — في الوضع باسمها، ويختفي حين لا تُعرض.
  Widget? _fab() {
    if (!_mergedOn || _merged == null) return _page?.enabled == true ? _addButton() : null;
    if (_openKey == null || _page?.enabled != true || !_picked(_openKey!)) return null;
    return _addButton(company: MergedMode.companyOf(_openKey!)?.name);
  }

  void _toggleCompany(RpCompany c) {
    final all = [for (final p in _merged?.parts ?? const <MergedReportPart<DeletedDebtsPage>>[]) if (!p.unsupported) p.company.key];
    final picked = _companies.isEmpty ? {...all} : {..._companies};
    if (picked.contains(c.key)) {
      if (picked.length == 1) return;
      picked.remove(c.key);
    } else {
      picked.add(c.key);
    }
    setState(() {
      _companies = picked.length == all.length ? {} : picked;
      _tabAll = false;
    });
  }

  // ── الشكل الموحّد (٢٢ نوفمبر — «اكمل كلشي»؛ بند المقترح: «المجموع، وعمر الدين، وتقسيم حسب الشركة والمدير») ──

  int _tab = 0;
  bool _tabAll = false;

  /// صفحاتٌ تُعرض: المفتوحة وحدها، أو المختارة في «كل الشركات».
  List<({String? key, DeletedDebtsPage page})> get _views {
    if (_mergedOn && _merged != null) return [for (final e in _mergedPages) (key: e.c.key, page: e.page)];
    final p = _page;
    return p != null && p.enabled ? [(key: null, page: p)] : const [];
  }

  /// سطور البحث عبر الصفحات المعروضة.
  List<({String? key, DeletedDebt row})> _rowsOf(List<({String? key, DeletedDebtsPage page})> views) {
    final s = _search.text.trim().toLowerCase();
    return [
      for (final v in views)
        for (final r in v.page.rows)
          if (s.isEmpty || _matches(r, s)) (key: v.key, row: r),
    ];
  }

  /// شركاتٌ مختارةٌ تعذّرت — تُسمّى ولا تُجمع.
  List<String> get _failed => [
        for (final p in _merged?.parts ?? const <MergedReportPart<DeletedDebtsPage>>[])
          if (_mergedOn && _picked(p.company.key) && !p.ok && !p.unsupported) p.company.name,
      ];

  List<String> _truncatedNames(List<({String? key, DeletedDebtsPage page})> views) => [
        for (final v in views)
          if (v.page.truncated) v.key == null ? '' : (MergedMode.companyOf(v.key!)?.name ?? ''),
      ];

  RpCompany _rp(MergedCompany c, {bool selected = true, String? note}) =>
      RpCompany(key: c.key, name: c.name, colorIndex: c.colorIndex, selected: selected, note: note);

  RpCompany? _coOf(String? key) {
    final c = key == null ? null : MergedMode.companyOf(key);
    return c == null ? null : _rp(c);
  }

  List<String> get _tabs => [if (_mergedOn && _merged != null) 'الشركة', 'المدير', 'عمر الدين', 'المصدر'];

  List<RpShare> _shares(List<({String? key, DeletedDebt row})> rows, String tab) {
    if (tab == 'عمر الدين') {
      return DebtAge.shares(rows, at: (r) => r.row.at, amount: (r) => r.row.debt, now: DateTime.now());
    }
    final acc = <String, ({String name, num amount, int count, RpCompany? co})>{};
    for (final r in rows) {
      final co = tab == 'الشركة' ? _coOf(r.key) : (tab == 'المدير' && _mergedOn ? _coOf(r.key) : null);
      final name = switch (tab) {
        'الشركة' => co?.name ?? '—',
        'المدير' => (r.row.managerUsername ?? '').trim().isEmpty ? 'بلا مدير' : r.row.managerUsername!.trim(),
        _ => _originLabel(r.row.origin),
      };
      final k = '${co?.key ?? ''}|$name';
      final o = acc[k];
      acc[k] = (name: name, amount: (o?.amount ?? 0) + r.row.debt, count: (o?.count ?? 0) + 1, co: co);
    }
    final total = acc.values.fold<num>(0, (a, v) => a + (v.amount > 0 ? v.amount : 0));
    final list = acc.values.toList()..sort((a, b) => b.amount.compareTo(a.amount));
    return [
      for (final v in list)
        RpShare(name: v.name, amount: v.amount, count: v.count, share: total > 0 && v.amount > 0 ? v.amount / total : 0, company: v.co),
    ];
  }

  List<Widget> _gapped(List<Widget> parts) => [
        for (var i = 0; i < parts.length; i++) ...[if (i > 0) const SizedBox(height: Sp.md), parts[i]],
      ];

  Widget _retryNotice(String text) => _Notice(
        icon: LucideIcons.userX,
        text: text,
        action: TextButton.icon(
          onPressed: _load,
          icon: const Icon(LucideIcons.refreshCw, size: 16),
          label: Text('common.retry'.tr()),
        ),
      );

  /// الشاشة كلّها بالوضعين: الشركات ← «حسب الشركة» ← المجموع ← المدينون والأقدم ← «قسّم حسب» ← الدين المكرّر ← البحث والديون
  /// (أزرار التسديد والشطب كما كانت) ← التصدير بما على الشاشة.
  List<Widget> _frame() {
    final m = _mergedOn ? _merged : null;
    final out = <Widget>[];
    if (m != null) {
      out.add(RpCompanyChips(
        companies: [
          for (final p in m.parts)
            if (!p.unsupported) _rp(p.company, selected: _companies.isNotEmpty && _companies.contains(p.company.key)),
        ],
        allSelected: _companies.isEmpty,
        onAll: () => setState(() => _companies = {}),
        onToggle: _toggleCompany,
      ));
      out.add(_companyTable(m));
      final off = [
        for (final p in m.parts)
          if (_picked(p.company.key) && p.ok && p.rows!.isNotEmpty && !p.rows!.first.enabled) '«${p.company.name}»',
      ];
      if (off.isNotEmpty) out.add(Text('غير مفعّلة: ${off.join('، ')}', style: AppType.micro(color: AppColors.textLow)));
    }
    if (_loading) {
      out.add(const Padding(padding: EdgeInsets.symmetric(vertical: 48), child: Center(child: CircularProgressIndicator())));
      return _gapped(out);
    }
    final views = _views;
    if (views.isEmpty) {
      if (m == null) {
        out.add(_page == null ? _retryNotice(_error ?? 'dd.load_failed'.tr()) : _Notice(icon: LucideIcons.userX, text: 'dd.off'.tr()));
      } else {
        // لا أصفار لما لم يُقرأ: الكلّ تعذّر، أو غير مفعّل
        out.add(m.parts.any((x) => x.ok) ? _Notice(icon: LucideIcons.userX, text: 'dd.off'.tr()) : _retryNotice(_error ?? 'dd.load_failed'.tr()));
      }
      return _gapped(out);
    }
    final now = DateTime.now();
    final count = views.fold<int>(0, (a, v) => a + v.page.count);
    final total = views.fold<double>(0, (a, v) => a + v.page.total);
    final allRows = _rowsOf(views);
    final truncated = _truncatedNames(views);
    final failed = _failed;
    final searching = _search.text.trim().isNotEmpty;
    final oldRows = [for (final r in allRows) if (DebtAge.isOld(r.row.at, now)) r];
    final oldSum = oldRows.fold<double>(0, (a, r) => a + r.row.debt);
    String truncNote(List<String> names) => names.every((n) => n.isEmpty)
        ? 'dd.truncated'.tr()
        : '${names.where((n) => n.isNotEmpty).map((n) => '«$n»').join('، ')}: ${'dd.truncated'.tr()}';
    out.add(RpHeroKpi(
      kpi: RpKpi(id: 'total', label: 'dd.kpi_total'.tr(), value: total, icon: LucideIcons.handCoins, tone: RpTone.debt, upIsGood: false),
      compareWith: '',
      spark: const [],
      note: 'dd.info'.tr(),
      notes: [
        if (failed.isNotEmpty) 'merged.not_in_sum'.trm(args: [failed.map((n) => '«$n»').join('، ')]),
        if (truncated.isNotEmpty) '${truncNote(truncated)} — الأعمار والتقسيم منها',
      ],
    ));
    out.add(RpKpiGrid(compareWith: '', kpis: [
      RpKpi(id: 'count', label: 'dd.kpi_count'.tr(), value: count, isCount: true, unit: 'مدين', icon: LucideIcons.userX, tone: RpTone.loss),
      RpKpi(
        id: 'old',
        label: 'أقدم من 3 أشهر',
        value: oldSum,
        icon: LucideIcons.hourglass,
        tone: RpTone.debt,
        upIsGood: false,
        hint: '${formatIQD(oldRows.length)} مدين${searching ? ' — من نتائج البحث' : ''}',
      ),
    ]));
    // ── «قسّم حسب» ──
    final tabs = _tabs;
    final tab = tabs[_tab.clamp(0, tabs.length - 1)];
    final shares = _shares(allRows, tab);
    final cap = _tabAll ? shares.length : 6;
    out.add(RpBreakdownCard(
      tabs: tabs,
      selected: tabs.indexOf(tab),
      tone: RpTone.debt,
      unit: 'مدين',
      shares: shares.take(cap).toList(),
      onTab: (i) => setState(() {
        _tab = i;
        _tabAll = false;
      }),
      note: searching ? 'من نتائج البحث' : (tab == 'عمر الدين' ? 'من تاريخ تسجيل الدين عندنا' : null),
      more: shares.length > cap ? 'عرض الكلّ (${shares.length})' : null,
      onMore: () => setState(() => _tabAll = true),
    ));
    // ── الدين المكرّر: قرار المفتوحة هنا، وغيرها من داخلها ──
    final openShown = m == null || (_openKey != null && _picked(_openKey!));
    final openTwins = openShown ? (_page?.pendingTwins ?? const <PendingTwin>[]) : const <PendingTwin>[];
    if (openTwins.isNotEmpty) {
      out.add(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (m != null && views.length > 1) ...[
          Align(alignment: AlignmentDirectional.centerStart, child: CompanyTag(companyKey: _openKey!, fontSize: 11)),
          const SizedBox(height: Sp.xs),
        ],
        _TwinsCard(
          twins: openTwins,
          decide: _page!.twinsApi >= 2,
          busyKey: _twinBusy,
          onSame: _twinSame,
          onDistinct: _twinDistinct,
        ),
      ]));
    }
    if (m != null) {
      for (final e in _mergedPages) {
        if (e.c.key == _openKey || e.page.pendingTwins.isEmpty) continue;
        out.add(Material(
          color: AppColors.warningSoftBg,
          borderRadius: BorderRadius.circular(R.card),
          child: InkWell(
            key: ValueKey('dd-other-twins-${e.c.key}'),
            borderRadius: BorderRadius.circular(R.card),
            onTap: () => _openOther(e.c.key),
            child: Padding(
              padding: const EdgeInsets.all(Sp.md),
              child: Row(children: [
                Icon(LucideIcons.copy, size: 16, color: AppColors.warningOnSoft),
                const SizedBox(width: Sp.x6),
                Expanded(
                  child: Text(
                    '«${e.c.name}»: ديونٌ مكرّرة تنتظر قرارك (${e.page.pendingTwins.length}) — القرار من داخلها',
                    style: AppType.label(color: AppColors.warningOnSoft).copyWith(fontSize: 12.5, height: 1.5),
                  ),
                ),
                Icon(Icons.chevron_left_rounded, size: 18, color: AppColors.warningOnSoft),
              ]),
            ),
          ),
        ));
      }
    }
    // ── الديون: البحث ثمّ البطاقات بأزرارها ──
    final anyRows = views.any((v) => v.page.rows.isNotEmpty);
    if (anyRows) {
      out.add(SheetSearchField(controller: _search, hint: 'dd.search_hint'.tr(), onChanged: (_) => setState(() {})));
    }
    if (!anyRows) {
      out.add(_Notice(icon: LucideIcons.userX, text: 'dd.empty'.tr()));
    } else if (allRows.isEmpty) {
      out.add(_Notice(icon: LucideIcons.search, text: 'dd.no_results'.tr()));
    } else {
      final tagged = m != null && views.length > 1;
      out.add(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var i = 0; i < allRows.length; i++) ...[
          if (i > 0) const SizedBox(height: Sp.sm),
          if (tagged)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 4, bottom: 2),
              child: CompanyTag(companyKey: allRows[i].key!, fontSize: 11),
            ),
          _DebtTile(
            row: allRows[i].row,
            onPay: m == null || allRows[i].key == _openKey
                ? () => _afterSheet(_showPaySheet(context, allRows[i].row))
                : () => _openOther(allRows[i].key!),
            onWriteOff: m == null || allRows[i].key == _openKey
                ? () => _afterSheet(_showWriteOffSheet(context, allRows[i].row))
                : () => _openOther(allRows[i].key!),
          ),
        ],
      ]));
    }
    if (truncated.isNotEmpty) {
      out.add(Text(truncNote(truncated), textAlign: TextAlign.center, style: AppType.muted().copyWith(fontSize: 11.5)));
    }
    if (allRows.isNotEmpty) {
      out.add(RpExportBar(
        onPdf: () => _export('pdf', views, allRows),
        onExcel: () => _export('excel', views, allRows),
        onShare: () => _export('share', views, allRows),
      ));
    }
    return _gapped(out);
  }

  Widget _companyTable(MergedReport<DeletedDebtsPage> m) {
    final now = DateTime.now();
    final lines = <RpCompanyLine>[];
    final outside = <String>[];
    for (final p in m.parts) {
      if (p.unsupported || !_picked(p.company.key)) continue;
      final page = p.ok && p.rows!.isNotEmpty ? p.rows!.first : null;
      if (page != null && !page.enabled) continue; // «غير مفعّلة» سطرٌ هادئ تحته
      if (page == null) {
        lines.add(RpCompanyLine(company: _rp(p.company, note: p.error), state: _loading ? RpCompanyState.loading : RpCompanyState.failed));
        if (!_loading) outside.add('${p.company.name} (${p.error ?? 'dd.load_failed'.tr()})');
        continue;
      }
      // «أقدم من 3 أشهر» من السطور — ناقصٌ إن لم تُقرأ كلّها (أحدث ٢٠٠٠) ⇒ «—» لا رقمٌ ناقص
      final old = page.truncated
          ? null
          : page.rows.where((r) => DebtAge.isOld(r.at, now)).fold<double>(0, (a, r) => a + r.debt);
      lines.add(RpCompanyLine(company: _rp(p.company), a: page.count, b: page.total, c: old));
    }
    final ok = [for (final l in lines) if (l.state == RpCompanyState.ok) l];
    return RpCompanyTable(
      heads: const ['المدينون', 'الديون', 'أقدم من 3 أشهر'],
      tones: const [RpTone.loss, RpTone.debt, RpTone.loss],
      lines: lines,
      total: [
        ok.fold<num>(0, (a, l) => a + (l.a ?? 0)),
        ok.fold<num>(0, (a, l) => a + (l.b ?? 0)),
        ok.any((l) => l.c == null) ? null : ok.fold<num>(0, (a, l) => a + (l.c ?? 0)),
      ],
      outside: outside.isEmpty ? null : 'خارج المجموع الآن: ${outside.join(' · ')}',
      onTap: (c) => setState(() {
        _companies = {c.key};
        _tabAll = false;
      }),
      onRetry: (_) => _load(),
    );
  }

  /// الملفّ = ما على الشاشة حرفاً: الشركات المختارة والبحث، وكلّ «ناقص» في الرأس.
  Future<void> _export(String how, List<({String? key, DeletedDebtsPage page})> views, List<({String? key, DeletedDebt row})> rows) {
    final merged = _mergedOn && _merged != null;
    final columns = [
      if (merged) 'merged.col_company'.trm(),
      'الاسم',
      'اسم المستخدم',
      'الهاتف',
      'المدير',
      'المصدر',
      'التاريخ',
      'الدين',
      'الملاحظة',
    ];
    final data = [
      for (final r in rows)
        [
          if (merged) MergedMode.companyOf(r.key ?? '')?.name ?? '',
          r.row.name,
          r.row.username ?? '',
          r.row.phone ?? '',
          r.row.managerUsername ?? '',
          _originLabel(r.row.origin),
          r.row.at == null ? '' : iqDateOf(r.row.at!),
          formatIQD(r.row.debt),
          (r.row.note ?? '').trim(),
        ],
    ];
    final search = _search.text.trim();
    final truncated = _truncatedNames(views);
    final details = [
      if (merged) 'الشركات: ${[for (final v in views) MergedMode.companyOf(v.key ?? '')?.name ?? ''].where((n) => n.isNotEmpty).join('، ')}',
      if (search.isNotEmpty) 'البحث: «$search»',
      'المجموع: ${rpMoney(views.fold<double>(0, (a, v) => a + v.page.total))} · ${formatIQD(views.fold<int>(0, (a, v) => a + v.page.count))} مدين',
      'عدد السطور: ${data.length}',
      if (_failed.isNotEmpty) 'ناقص: ${'merged.not_in_sum'.trm(args: [_failed.map((n) => '«$n»').join('، ')])}',
      if (truncated.isNotEmpty) 'ناقص: ${truncated.every((n) => n.isEmpty) ? '' : '${truncated.where((n) => n.isNotEmpty).map((n) => '«$n»').join('، ')}: '}${'dd.truncated'.tr()}',
    ];
    final title = 'reports.deleted_debts'.tr();
    final subtitle = 'حتى ${iqDateOf(DateTime.now())}';
    const weights = [2.0, 1.3, 1.3, 1.2, 1.0, 1.0, 1.0, 2.0];
    final w = [if (merged) 1.2, ...weights];
    switch (how) {
      case 'pdf':
        return ReportExportActions.pdf(context,
            title: title, subtitle: subtitle, details: details, columns: columns, rows: data, columnWeights: w, fileNameBase: 'deleted-debts');
      case 'excel':
        return ReportExportActions.csv(context, title: title, subtitle: subtitle, details: details, columns: columns, rows: data, fileNameBase: 'deleted-debts');
      default:
        return ReportExportActions.sharePdf(context,
            title: title, subtitle: subtitle, details: details, columns: columns, rows: data, columnWeights: w, fileNameBase: 'deleted-debts');
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
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
            style: AppType.title(color: AppColors.textHi).copyWith(fontSize: 16),
          ),
          iconTheme: IconThemeData(color: AppColors.textHi),
        ),
        floatingActionButton: _fab(),
        body: SafeArea(
          child: RefreshIndicator(
            onRefresh: _load,
            color: AppColors.brand,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.huge + Sp.huge),
              children: _frame(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _addButton({String? company}) {
    final can = Perms.has('deleted_debts.add');
    return FloatingActionButton.extended(
      backgroundColor: can ? AppColors.warningFill : LockedStyle.box,
      foregroundColor: can ? AppColors.onBrand : LockedStyle.glyph,
      onPressed: can
          ? () => _afterSheet(_showAddSheet(context))
          : () => showNoPermission(context, action: true),
      icon: Icon(can ? LucideIcons.plus : LucideIcons.lock, size: 16),
      label: Text(company == null ? 'dd.add'.tr() : '${'dd.add'.tr()} · $company'),
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

/// «ديونٌ مكرّرة تنتظر قرارك» — صفٌّ لكلّ دين: اسمه والمبلغان وحال المشترك، و«نفس الدين» / «دينان مختلفان» (أو «أكمل القرار»).
class _TwinsCard extends StatelessWidget {
  const _TwinsCard({required this.twins, required this.busyKey, required this.onSame, required this.onDistinct, this.decide = true});
  final List<PendingTwin> twins;

  /// أزرار القرار (خادمٌ بـtwins_api ≥ 2)؛ وإلّا تُعرض الديون للقراءة و«القرار من الموقع».
  final bool decide;
  final String? busyKey;
  final ValueChanged<PendingTwin> onSame;
  final ValueChanged<PendingTwin> onDistinct;

  static const _status = {
    'deleted': 'محذوفٌ من الساس',
    'absent': 'غير موجود بقائمتك',
    'pending_sas': 'لم يُدرَج بعد',
    'present': 'موجودٌ الآن',
  };

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.warningSoftBg,
        borderRadius: BorderRadius.circular(R.card),
        border: Border.all(color: AppColors.warningSoftBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Icon(LucideIcons.copy, size: 16, color: AppColors.warningOnSoft),
            const SizedBox(width: Sp.x6),
            Expanded(
              child: Text('ديونٌ مكرّرة تنتظر قرارك (${twins.length})',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.label(color: AppColors.warningOnSoft)),
            ),
          ]),
          const SizedBox(height: Sp.xs),
          Text('دينٌ مسجَّلٌ يدويّاً ومتتبَّعٌ تلقائيّاً معاً — مقفلان حتى تقرّر، فلا يُحصَّل مرّتين.',
              style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 12.5, height: 1.5)),
          for (final t in twins) ...[
            const SizedBox(height: Sp.sm),
            Divider(height: 1, color: AppColors.warningSoftBorder),
            const SizedBox(height: Sp.sm),
            Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(color: AppColors.textHi)),
            const SizedBox(height: 2),
            Text(
              'المسجَّل يدويّاً ${_money(t.manualOrig ?? t.manualDebt)} · ${t.autoKey.startsWith('d') ? 'بسجلّ ديونك' : 'دين الدفتر'} ${t.autoDebt == null ? '—' : _money(t.autoDebt!)}'
              '${t.autoStatus != null && _status[t.autoStatus] != null ? ' · ${_status[t.autoStatus]}' : ''}',
              style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 12.5, height: 1.5),
            ),
            if (t.partialKeep != null) ...[
              const SizedBox(height: 2),
              Text('بدأ قرار «نفس الدين» ولم يكتمل — «أكمل القرار» يُتمّه بلا حركةٍ جديدة',
                  style: AppType.micro(color: AppColors.warningOnSoft)),
            ],
            const SizedBox(height: Sp.sm),
            if (!decide)
              Text('القرار من الموقع حاليّاً (الديون المحذوفة) — يصل هنا بتحديث الخادم', style: AppType.micro(color: AppColors.warningOnSoft))
            else
              Row(children: [
                Expanded(
                  child: FilledButton(
                    onPressed: busyKey != null ? null : () => onSame(t),
                    child: busyKey == t.manualKey
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(t.partialKeep != null ? 'أكمل القرار' : 'نفس الدين'),
                  ),
                ),
                if (t.partialKeep == null) ...[
                  const SizedBox(width: Sp.sm),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: busyKey != null ? null : () => onDistinct(t),
                      child: const Text('دينان مختلفان'),
                    ),
                  ),
                ],
              ]),
          ],
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

  Future<void> _submit({bool confirmRepeat = false}) async {
    if (!confirmRepeat) {
      final ok = await _confirm(
        context,
        title: 'dd.pay_confirm_title'.tr(),
        body: 'dd.pay_confirm_body'
            .tr(namedArgs: {'amount': _money(_amount), 'name': widget.row.name}),
        color: AppColors.success,
      );
      if (!ok || !mounted) return;
    }
    setState(() => _busy = true);
    final c = _comment.text.trim();
    final r = await DeletedDebtsApi.pay(
      key: widget.row.key,
      amount: _full ? null : _amount,
      payAll: _full,
      comment: c.isEmpty ? null : c,
      confirmRepeat: confirmRepeat,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (!r.ok) {
      // تسديدٌ بالمبلغ نفسه قبل لحظات ⇒ يُسأل المدير ثمّ يُعاد بالتأكيد وحده
      if (r.code == 'RECENT_DUPLICATE' && !confirmRepeat) {
        final again = await _confirm(
          context,
          title: 'تسديدٌ مكرّر؟',
          body: r.message ?? 'سُجّل تسديدٌ بالمبلغ نفسه لهذا الدين قبل لحظات — أكّد إن كان تسديداً آخر',
          color: AppColors.success,
          yes: 'سجّله',
        );
        if (again && mounted) await _submit(confirmRepeat: true);
        return;
      }
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

/// خيار مبلغٍ صريح في «أيّ المبلغين صحيح؟» — بعرض النافذة، بحدٍّ خافت.
class _TwinAmountOption extends StatelessWidget {
  const _TwinAmountOption({required this.label, required this.icon, required this.onTap});
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(R.lg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(R.lg),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: Sp.lg, vertical: Sp.md),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(R.lg), border: Border.all(color: AppColors.border)),
          child: Row(children: [
            Icon(icon, size: 18, color: AppColors.brand),
            const SizedBox(width: Sp.sm),
            Expanded(
              child: Text(label,
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.body(color: AppColors.textHi).copyWith(fontWeight: FontWeight.w600)),
            ),
            Icon(LucideIcons.chevronLeft, size: 18, color: AppColors.textMid),
          ]),
        ),
      ),
    );
  }
}
