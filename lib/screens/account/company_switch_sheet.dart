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
import '../../widgets/merged_all_row.dart';
import 'account_gate_screen.dart';
import 'company_open_flow.dart';
import 'subscription_screen.dart';
import '../../core/widgets/app_sheet.dart';
import '../../services/merged_text.dart';

/// «تبديل الشركة» من داخل التطبيق — طلب المالك ٢١ أكتوبر: «اريدك اضيف زر
/// ثاني جنب زر تبديل بين المدراء بالتطبيق التبديل بين الشركات»، و«تنتبه لدينا
/// بالأصل زر تبديل بين المدراء وتحسب حساب التنقّل بينهم».
///
/// كان المدير يخرج إلى «شركاتي» ليفتح شركةً أخرى. الآن ورقةٌ بشركات الحساب، والدخول **مسار «شركاتي» نفسه**
/// ([CompanyOpenFlow]). منذ ٧ نوفمبر تُفتح من سطر الشركة تحت عنوان كلّ تبويب (`HeaderSwitch` في top_actions.dart) لا من
/// مربّعٍ في الرأس (المالك: «القوائم والازرار صارت بتزاحم كبير»)، و«الصفحات» صفٌّ أعلاها ([showCompanySwitchSheet] onPages).
///
/// الاثنان لا يتداخلان:
/// • «الصفحات» = المدراء الفرعيّون **داخل** الشركة المفتوحة (مرجع «العودة
///   للأصل» يخصّ شركته وحدها — `SavedProfilesStore.originalFor`).
/// • «الشركات» = صفحات الحساب المربوطة؛ فتح إحداها يدخل صفحتها المربوطة من
///   جديد، فينتهي أيّ تبديلٍ لمديرٍ فرعيٍّ سبقه.
/// للمالك وحده ولحسابٍ بشركتين فأكثر ([LinkedCompanies.switcherVisible]).

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
///
/// [autoOpen] («إشعارات كلّ شركاتي»، ٤ نوفمبر): نقرة إشعار شركةٍ غير المفتوحة ⇒ الورقة تفتحها بنفسها كأنّ المدير نقرها،
/// و[notice] سطرٌ أعلاها يقول لماذا (اسم شركة الإشعار).
///
/// [onPages] (٧ نوفمبر): صفّ «الصفحات» أعلى الورقة — يغلقها ثمّ يفتح «الصفحات» (null ⇒ لا صفّ: بلا `managers.edit`).
Future<void> showCompanySwitchSheet(BuildContext context,
    {LinkedCompany? autoOpen, String? notice, VoidCallback? onPages}) {
  HapticFeedback.selectionClick();
  return showAppSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.scrim,
    builder: (_) =>
        CompanySwitchSheet(autoOpen: autoOpen, notice: notice, onPages: onPages),
  );
}

class CompanySwitchSheet extends StatefulWidget {
  const CompanySwitchSheet({super.key, this.autoOpen, this.notice, this.onPages});

  /// تُفتح بنفسها عند ظهور الورقة (إشعارٌ لها).
  final LinkedCompany? autoOpen;

  /// اسم شركة الإشعار — سطرٌ أعلى الورقة.
  final String? notice;

  /// صفّ «الصفحات» أعلى الورقة (المدراء الفرعيّون داخل الشركة المفتوحة).
  final VoidCallback? onPages;

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
    final auto = widget.autoOpen;
    if (auto != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _open(auto);
      });
    }
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
      setState(() => _error = 'merged.unavailable'.trm());
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
            if ((widget.notice ?? '').trim().isNotEmpty) ...[
              _NoticeBanner(
                  text: 'company_switch.push_opening'
                      .tr(args: [widget.notice!.trim()])),
              const SizedBox(height: Sp.md),
            ],
            if (_error != null) ...[
              _ErrorBanner(text: _error!),
              const SizedBox(height: Sp.md),
            ],
            if (widget.onPages != null) ...[
              _PagesRow(
                locked: _busyKey != null || _entering,
                onTap: () {
                  Navigator.of(context).maybePop();
                  widget.onPages!();
                },
              ),
              const SizedBox(height: Sp.md),
            ],
            ValueListenableBuilder(
              valueListenable: MergedMode.data,
              builder: (context, _, __) => MergedMode.eligible
                  ? Padding(
                      padding: const EdgeInsets.only(bottom: Sp.md),
                      child: ValueListenableBuilder<bool>(
                        valueListenable: MergedMode.active,
                        builder: (context, on, _) => MergedAllRow(
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

/// «الصفحات» أعلى الورقة (٧ نوفمبر): التبديل بين مدراء **الشركة المفتوحة** — كان مربّعاً بجانب «الشركات» في رأس كلّ تبويب.
class _PagesRow extends StatelessWidget {
  const _PagesRow({required this.onTap, required this.locked});

  final VoidCallback onTap;

  /// شركةٌ تُفتح الآن ⇒ لا نقر.
  final bool locked;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Material(
      key: const ValueKey('company-switch-pages'),
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(R.md),
      child: InkWell(
        onTap: locked ? null : onTap,
        borderRadius: BorderRadius.circular(R.md),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.md),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: AppColors.brandSoftBg, borderRadius: BorderRadius.circular(R.sm)),
                child: Icon(Icons.swap_horiz_rounded, size: 22, color: AppColors.brand),
              ),
              const SizedBox(width: Sp.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('accounts.title'.tr(), style: AppType.bodyStrong(color: AppColors.textHi)),
                    const SizedBox(height: 3),
                    Text(
                      'company_switch.pages_sub'.tr(),
                      style: AppType.muted().copyWith(fontSize: 12.5, height: 1.45),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Sp.sm),
              Icon(Icons.chevron_left_rounded, color: AppColors.textMid),
            ],
          ),
        ),
      ),
    );
  }
}

/// «كل الشركات» أعلى الورقة: نقاط الشركات الصالحة بألوانها، والحال (مفعّل ⇒ العودة للشركة المفتوحة).
/// لماذا فُتحت الورقة: إشعارٌ لشركةٍ غير المفتوحة («إشعارات كلّ شركاتي»).
class _NoticeBanner extends StatelessWidget {
  const _NoticeBanner({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.infoSoftBg,
        borderRadius: BorderRadius.circular(R.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.notifications_active_outlined,
              size: 18, color: AppColors.info),
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

/// سطر الشركة (والرئيسيّة: اسم المدير معه) زرّاً واحداً لـ«التبديل» — مكان مربّعَي «الشركات» و«الصفحات» منذ ٧ نوفمبر
/// (`HeaderSwitch`). السهم خارج السطر فلا يبتره «…» اسمٌ طويل، والارتفاع كما هو (لا حشوة).
class CompanySwitchTap extends StatelessWidget {
  const CompanySwitchTap({
    super.key,
    required this.label,
    required this.onTap,
    required this.child,
    this.action,
  });

  /// اسم الشركة المفتوحة — لقارئ الشاشة.
  final String label;
  final VoidCallback onTap;
  final Widget child;

  /// اسم الفعل لقارئ الشاشة — «تبديل الشركة» افتراضاً، و«الصفحات» لمن لا شركات له.
  final String? action;

  @override
  Widget build(BuildContext context) {
    final what = action ?? 'company_switch.title'.tr();
    return Semantics(
      button: true,
      label: label.isEmpty ? what : '$what — $label',
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
