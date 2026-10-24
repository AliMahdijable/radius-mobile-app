import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/account_api.dart';
import '../../core/widgets/design_sheet.dart';
import '../../services/active_company.dart';
import '../../services/company_creds_store.dart';
import '../../services/linked_companies.dart';
import '../../services/merged_mode.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../../widgets/active_company_line.dart';
import 'account_gate_screen.dart';
import 'company_open_flow.dart';
import 'subscription_screen.dart';
import '../../core/widgets/app_sheet.dart';

/// «تبديل الشركة» من داخل التطبيق — طلب المالك ٢١ أكتوبر: «اريدك اضيف زر
/// ثاني جنب زر تبديل بين المدراء بالتطبيق التبديل بين الشركات»، و«تنتبه لدينا
/// بالأصل زر تبديل بين المدراء وتحسب حساب التنقّل بينهم».
///
/// كان المدير يخرج إلى «شركاتي» ليفتح شركةً أخرى. الآن مربّعٌ بجانب «الصفحات»
/// في ترويسة الرئيسيّة (أو سطر الشركة نفسه حين لا يتّسع العرض — [fitsSquare])
/// يفتح ورقةً بشركات الحساب، والدخول **مسار «شركاتي» نفسه** ([CompanyOpenFlow]).
///
/// الزرّان لا يتداخلان:
/// • «الصفحات» = المدراء الفرعيّون **داخل** الشركة المفتوحة (مرجع «العودة
///   للأصل» يخصّ شركته وحدها — `SavedProfilesStore.originalFor`).
/// • «الشركات» = صفحات الحساب المربوطة؛ فتح إحداها يدخل صفحتها المربوطة من
///   جديد، فينتهي أيّ تبديلٍ لمديرٍ فرعيٍّ سبقه.
/// للمالك وحده ولحسابٍ بشركتين فأكثر ([LinkedCompanies.switcherVisible]).
class CompanySwitch {
  CompanySwitch._();

  /// أقلّ عرضٍ يبقى لاسم المدير وسطر شركته (عند سلّم خطّ 1) بجانب المربّعات —
  /// أغلب الأسماء ٧٠–١٣٠ نقطة («مهدي العبيدي» ٩٨). أضيق منه ⇒ لا مربّع، وسطر
  /// الشركة تحت الاسم هو الزرّ (بسهم ⌄).
  static const double minNameRoom = 104;

  /// يتّسع رأس الرئيسيّة لمربّع «الشركات»؟ [squares] = كلّ مربّعات الصفّ
  /// معه (الشركات · الصفحات · المساعد · الجرس · الترس)، و[side]/[gap] مقاسها
  /// على هذه الشاشة (`TopActionChip.sizeOf/gapOf`).
  static bool fitsSquare({
    required double width,
    required double textScale,
    required int squares,
    required double side,
    required double gap,
  }) {
    // حشوة الرأس ١٦ من الجانبين + فاصل ٨ بين الاسم والمربّعات.
    final room =
        width - Sp.lg * 2 - Sp.sm - squares * side - (squares - 1) * gap;
    return room >= minNameRoom * textScale;
  }
}

/// حال صفّ الشركة في الورقة من الجلسة القائمة.
enum CompanyRowState {
  /// شركةٌ أخرى — النقر يفتحها.
  other,

  /// هذه الصفحة نفسها (الساس واليوزر) — لا نقر.
  current,

  /// الشركة نفسها بمديرٍ فرعيٍّ غير مربوط (بُدّل إليه من «الصفحات») — النقر
  /// يعيد صفحتها المربوطة.
  insideAsOther,
}

/// حال كلّ صفّ: الصفحة المفتوحة بساسها ويوزرها؛ وإن لم تُربط (مديرٌ فرعيٌّ)
/// فكلّ صفحةٍ مربوطة على ساسها «مفتوحة بحساب …».
@visibleForTesting
List<CompanyRowState> companyRowStates(
    List<LinkedCompany> items, ActiveCompanyInfo? cur) {
  final out = List<CompanyRowState>.filled(items.length, CompanyRowState.other);
  if (cur == null || cur.isEmployee) return out;
  final host = CompanyCredsStore.hostOf(cur.sasUrl);
  final user = cur.username.trim().toLowerCase();
  bool sameSas(LinkedCompany c) =>
      (cur.sasCode.isNotEmpty && c.sasCode == cur.sasCode) ||
      (host.isNotEmpty && CompanyCredsStore.hostOf(c.sasUrl ?? '') == host);
  for (var i = 0; i < items.length; i++) {
    final c = items[i];
    if (!c.isEmployee &&
        sameSas(c) &&
        c.username.trim().toLowerCase() == user) {
      out[i] = CompanyRowState.current;
      return out;
    }
  }
  for (var i = 0; i < items.length; i++) {
    if (!items[i].isEmployee && sameSas(items[i])) {
      out[i] = CompanyRowState.insideAsOther;
    }
  }
  return out;
}

/// الورقة على الـNavigator الجذر: فتح شركةٍ يستبدل التطبيق كلّه
/// (`pushAndRemoveUntil` في [CompanyOpenFlow]) والورقة فوقه.
Future<void> showCompanySwitchSheet(BuildContext context) {
  HapticFeedback.selectionClick();
  return showAppSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.scrim,
    builder: (_) => const CompanySwitchSheet(),
  );
}

class CompanySwitchSheet extends StatefulWidget {
  const CompanySwitchSheet({super.key});

  @override
  State<CompanySwitchSheet> createState() => _CompanySwitchSheetState();
}

class _CompanySwitchSheetState extends State<CompanySwitchSheet> {
  String? _busyKey;
  String? _error;
  bool _loadFailed = false;

  /// «كل الشركات»: جارٍ الدخول.
  bool _entering = false;

  static String _keyOf(LinkedCompany c) =>
      '${c.sasCode}|${c.sasUrl ?? ''}|${c.username}';

  @override
  void initState() {
    super.initState();
    _refresh();
    // «كل الشركات» يظهر حين يفتحه الخادم لهذا الحساب ولشركتين صالحتين فأكثر — لا ينتظر قائمة «شركاتي».
    MergedMode.load();
  }

  /// «كل الشركات»: دخولٌ بلا تسجيل (الجلسة المفتوحة كما هي)، أو العودة منه.
  Future<void> _toggleAll() async {
    if (_entering || _busyKey != null) return;
    if (MergedMode.active.value) {
      await MergedMode.exit();
      if (mounted) Navigator.of(context).maybePop();
      return;
    }
    setState(() {
      _entering = true;
      _error = null;
    });
    final ok = await MergedMode.enter();
    if (!mounted) return;
    setState(() => _entering = false);
    if (!ok) {
      setState(() => _error = 'merged.unavailable'.tr());
      return;
    }
    Navigator.of(context).maybePop();
  }

  /// القائمة المعروفة تُرسم فوراً، ويُسأل الخادم من جديد (شركةٌ أُضيفت أو
  /// أُزيلت من جهازٍ آخر). الفشل يُبقي المعروفة، وبلاها رسالةٌ و«إعادة».
  Future<void> _refresh() async {
    if (_loadFailed) setState(() => _loadFailed = false);
    try {
      await LinkedCompanies.load();
    } catch (_) {
      if (mounted && LinkedCompanies.items.value == null) {
        setState(() => _loadFailed = true);
      }
    }
  }

  Future<void> _open(LinkedCompany c) async {
    if (_busyKey != null) return;
    setState(() => _error = null);
    await CompanyOpenFlow.open(
      context,
      c,
      CompanyOpenHost(
        setBusy: (busy) {
          if (mounted) setState(() => _busyKey = busy ? _keyOf(c) : null);
        },
        showError: (msg, {duration}) {
          if (mounted) setState(() => _error = msg);
        },
        accountMe: () async {
          try {
            return await AccountApi.me();
          } catch (_) {
            return null;
          }
        },
        openSubscription: _openSubscription,
        afterLoginForm: () async {
          if (mounted) await _refresh();
        },
        // قُبلت كلمة السرّ: غطاءٌ يملأ الشاشة قبل مسح الجلسة — لا تُرى الرئيسيّة
        // تتبدّل تحته، ولا تُغلق الورقة في منتصف الحفظ.
        beforeSessionSwap: (c) {
          if (!mounted) return;
          Navigator.of(context).push(_SwitchingRoute(label: c.label));
        },
        // الجلسة السابقة مُسحت والجديدة لم تُحفظ: لا بقاء على رئيسيّةٍ بلا
        // جلسة — بوّابة الحساب برسالتها، ومنها «شركاتي».
        sessionSwapFailed: (msg, {duration}) {
          if (!mounted) return;
          Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => AccountGateScreen(message: msg)),
            (_) => false,
          );
        },
      ),
    );
  }

  /// «تفعيل كود» (أندرويد) من نافذة «الشركة تحتاج باقة».
  Future<void> _openSubscription() async {
    AccountMe me;
    try {
      me = await AccountApi.me();
    } catch (_) {
      if (mounted) setState(() => _error = 'account.err_network'.tr());
      return;
    }
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SubscriptionScreen(me: me, fromCompanies: true),
    ));
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return DesignSheet(
      header: SheetHeaderBar(
        icon: Icons.apartment_rounded,
        title: 'company_switch.title'.tr(),
        subtitle: 'company_switch.subtitle'.tr(),
        onClose: () => Navigator.of(context).maybePop(),
      ),
      body: ValueListenableBuilder<List<LinkedCompany>?>(
        valueListenable: LinkedCompanies.items,
        builder: (context, items, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null) ...[
              _ErrorBanner(text: _error!),
              const SizedBox(height: Sp.md),
            ],
            ValueListenableBuilder(
              valueListenable: MergedMode.data,
              builder: (context, _, __) => MergedMode.eligible
                  ? Padding(
                      padding: const EdgeInsets.only(bottom: Sp.md),
                      child: ValueListenableBuilder<bool>(
                        valueListenable: MergedMode.active,
                        builder: (context, on, _) => _AllCompaniesRow(
                          active: on,
                          busy: _entering,
                          onTap: _toggleAll,
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            ..._rows(items),
          ],
        ),
      ),
    );
  }

  List<Widget> _rows(List<LinkedCompany>? items) {
    if (items == null) {
      if (_loadFailed) {
        return [
          Text('company_switch.load_failed'.tr(),
              textAlign: TextAlign.center,
              style: AppType.body(color: AppColors.textBody)),
          const SizedBox(height: Sp.md),
          Center(
            child: TextButton(
              onPressed: _refresh,
              child: Text('common.retry'.tr(),
                  style: AppType.button(color: AppColors.brand)),
            ),
          ),
        ];
      }
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: Sp.huge),
          child: Center(
            child: CircularProgressIndicator(
                color: AppColors.brand, strokeWidth: 2.4),
          ),
        ),
      ];
    }
    final cur = ActiveCompany.current;
    final states = companyRowStates(items, cur);
    return [
      for (var i = 0; i < items.length; i++) ...[
        if (i > 0) const SizedBox(height: Sp.sm),
        _CompanyRow(
          company: items[i],
          state: states[i],
          insideAs: cur?.username ?? '',
          busy: _busyKey == _keyOf(items[i]),
          locked: _busyKey != null,
          onTap: () => _open(items[i]),
        ),
      ],
    ];
  }
}

/// «كل الشركات» أعلى الورقة: نقاط الشركات الصالحة بألوانها، والحال (مفعّل ⇒ العودة للشركة المفتوحة).
class _AllCompaniesRow extends StatelessWidget {
  const _AllCompaniesRow({required this.active, required this.busy, required this.onTap});

  final bool active;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final usable = MergedMode.usable;
    return Material(
      color: active ? AppColors.brandSoftBg : AppColors.surface,
      borderRadius: BorderRadius.circular(R.md),
      child: InkWell(
        onTap: busy ? null : onTap,
        borderRadius: BorderRadius.circular(R.md),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.md),
            border: Border.all(color: active ? AppColors.brand : AppColors.border, width: active ? 1.5 : 1),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: AppColors.brandSoftBg, borderRadius: BorderRadius.circular(R.sm)),
                child: Icon(Icons.layers_rounded, size: 22, color: AppColors.brand),
              ),
              const SizedBox(width: Sp.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('merged.all_title'.tr(), style: AppType.bodyStrong(color: AppColors.textHi)),
                    const SizedBox(height: 3),
                    Text(
                      busy
                          ? 'merged.entering'.tr()
                          : active
                              ? 'merged.all_active'.tr()
                              : 'merged.all_sub'.tr(args: ['${usable.length}']),
                      style: AppType.muted().copyWith(fontSize: 12.5, height: 1.45),
                    ),
                    if (usable.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          for (final c in usable)
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(color: AppColors.company(c.colorIndex), shape: BoxShape.circle),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: Sp.sm),
              if (busy)
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(color: AppColors.brand, strokeWidth: 2.2),
                )
              else
                Icon(active ? Icons.check_circle_rounded : Icons.chevron_left_rounded,
                    color: active ? AppColors.brand : AppColors.textMid),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.dangerSoftBg,
        borderRadius: BorderRadius.circular(R.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, size: 18, color: AppColors.error),
          const SizedBox(width: Sp.sm),
          Expanded(
            child: Text(text,
                style: AppType.body(color: AppColors.textBody)
                    .copyWith(height: 1.5)),
          ),
        ],
      ),
    );
  }
}

class _CompanyRow extends StatelessWidget {
  const _CompanyRow({
    required this.company,
    required this.state,
    required this.insideAs,
    required this.busy,
    required this.locked,
    required this.onTap,
  });

  final LinkedCompany company;
  final CompanyRowState state;

  /// يوزر الجلسة — «مفتوحة بحساب …» لـ[CompanyRowState.insideAsOther].
  final String insideAs;
  final bool busy;

  /// دخولٌ جارٍ لشركةٍ أخرى — الصفوف كلّها تنتظره.
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final c = company;
    final current = state == CompanyRowState.current;
    final tappable = !current && !locked;
    final note = switch (state) {
      CompanyRowState.insideAsOther =>
        'company_switch.inside_as'.tr(args: [insideAs]),
      _ => null,
    };
    return Material(
      color: current ? AppColors.brandSoftBg : AppColors.surface,
      borderRadius: BorderRadius.circular(R.lg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: tappable ? onTap : null,
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.md),
          child: Row(
            children: [
              Container(
                width: H.iconBox,
                height: H.iconBox,
                decoration: BoxDecoration(
                  color: current ? AppColors.surface : AppColors.brandSoftBg,
                  borderRadius: BorderRadius.circular(R.icon),
                ),
                child: Icon(Icons.router_outlined,
                    color: AppColors.brand, size: 20),
              ),
              const SizedBox(width: Sp.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // الاسم كاملاً يلتفّ (حتى ٣ أسطر على ٣٢٠) — لا يُقصّ في سطرٍ واحد.
                    Text(c.label,
                        style: AppType.listName(color: AppColors.textHi),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: Sp.xxs),
                    Row(children: [
                      Flexible(
                        child: Text(c.username,
                            style: AppType.body(color: AppColors.textMid),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textDirection: TextDirection.ltr),
                      ),
                      if (c.isEmployee) ...[
                        const SizedBox(width: Sp.sm),
                        _Pill(text: 'account.role_employee'.tr()),
                      ],
                    ]),
                    if (note != null) ...[
                      const SizedBox(height: Sp.xxs),
                      Text(note,
                          style: AppType.muted(color: AppColors.textMid)
                              .copyWith(fontSize: 11.5),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: Sp.sm),
              if (busy)
                SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.2, color: AppColors.brand))
              else if (current)
                _Pill(text: 'company_switch.current'.tr(), strong: true)
              else
                Icon(Icons.chevron_left_rounded,
                    color: locked ? AppColors.textHint : AppColors.textLow),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, this.strong = false});
  final String text;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Sp.sm, vertical: 2),
      decoration: BoxDecoration(
        color: strong ? AppColors.surface : AppColors.surfaceInput,
        borderRadius: BorderRadius.circular(R.pill),
      ),
      child: Text(text,
          style: AppType.pillBold(
              color: strong ? AppColors.brand : AppColors.textMid)),
    );
  }
}

/// غطاء «جارٍ فتح الشركة…» أثناء حفظ الجلسة الجديدة — لا رجوع منه: ينتهي بفتح
/// التطبيق على الشركة، أو ببوّابة الحساب إن تعذّر الحفظ.
class _SwitchingRoute extends PageRouteBuilder<void> {
  _SwitchingRoute({required String label})
      : super(
          opaque: true,
          transitionDuration: const Duration(milliseconds: 150),
          pageBuilder: (context, _, __) => PopScope(
            canPop: false,
            child: Scaffold(
              backgroundColor: AppColors.bg,
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(Sp.xl),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(
                          color: AppColors.brand, strokeWidth: 2.4),
                      const SizedBox(height: Sp.lg),
                      Text('company_switch.opening'.tr(args: [label]),
                          textAlign: TextAlign.center,
                          style: AppType.body(color: AppColors.textBody)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          transitionsBuilder: (context, a, _, child) =>
              FadeTransition(opacity: a, child: child),
        );
}

/// اسم المدير وسطر شركته زرّاً واحداً لـ«تبديل الشركة» — حين لا يتّسع الرأس
/// لمربّعه ([CompanySwitch.fitsSquare]). السهم خارج السطر فلا يبتره «…» اسمٌ
/// طويل، والارتفاع كما هو (لا حشوة).
class CompanySwitchTap extends StatelessWidget {
  const CompanySwitchTap({
    super.key,
    required this.label,
    required this.onTap,
    required this.child,
  });

  /// اسم الشركة المفتوحة — لقارئ الشاشة.
  final String label;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '${'company_switch.title'.tr()} — $label',
      onTap: onTap,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(R.sm),
        child: child,
      ),
    );
  }
}

/// سطر الشركة وبعده سهم ⌄ — إشارة أنّ السطر زرّ.
class CompanySwitchLine extends StatelessWidget {
  const CompanySwitchLine({super.key, required this.info, this.omitUsername});

  final ActiveCompanyInfo info;
  final String? omitUsername;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
            child: ActiveCompanyLine(info: info, omitUsername: omitUsername)),
        const SizedBox(width: 2),
        Icon(Icons.expand_more_rounded, size: 15, color: AppColors.textMid),
      ],
    );
  }
}
