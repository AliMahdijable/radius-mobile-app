import 'dart:io' show Platform;

import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/platform/desktop_layout.dart';
import '../../core/widgets/permission_locked.dart';
import '../../services/account_service.dart';
import '../../services/active_company.dart';
import '../../services/permissions_service.dart';
import '../../services/provider_service.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../../widgets/active_company_line.dart';
import '../app_modules.dart';
import '../search/quick_search_overlay.dart';
import '../settings_screen.dart';

/// غلاف الحاسبة: قائمةٌ جانبيّة بكلّ الأقسام (بترتيب الموقع) والمحتوى بجانبها — لا شريطٌ سفليّ ولا
/// صفحاتٌ تغطّي النافذة.
///
/// كلّ قسمٍ له Navigator خاصّ: ما يفتحه القسم (تفاصيل مشترك، تقرير، نافذة) يبقى داخل منطقة المحتوى
/// والقائمة ظاهرة، والرجوع للقسم يحفظ مكانك فيه. النقر على القسم المفتوح يعيده لبدايته.
/// التبويبات الثلاثة (الرئيسيّة، المشتركون، الأجهزة) هي نفسها شاشات الهاتف بحالتها؛ «قوائم أخرى»
/// تتوزّع على المجموعات من [buildAppModules] — نفس القفل والإخفاء.
class DesktopShell extends StatefulWidget {
  const DesktopShell({
    super.key,
    required this.currentTab,
    required this.tabBuilder,
    required this.onSelectTab,
    required this.onLeaveTabs,
    required this.onQuickAdd,
  });

  /// تبويب MainShell الحاليّ (0 الرئيسيّة · 1 المشتركون · 2 الأجهزة) — قد يتبدّل من داخل الشاشات.
  final int currentTab;
  final Widget Function(int index) tabBuilder;
  final ValueChanged<int> onSelectTab;

  /// فُتح قسمٌ غير التبويبات: تتوقّف تحديثاتها الدوريّة.
  final VoidCallback onLeaveTabs;
  final VoidCallback onQuickAdd;

  @override
  State<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends State<DesktopShell> {
  static const double _sidebarWidth = 264;

  /// أعرض من هذا يتوسّط المحتوى — شاشاتٌ بُنيت للهاتف لا تتمدّد على شاشةٍ عريضة جدّاً.
  static const double _maxContent = 1180;

  static const _moduleOrder = [
    'managers',
    'employees',
    'packages',
    'discounts',
    'subscriber_prices',
    'cards',
    'reports',
    'expenses',
    'settlements',
    'topup',
    'broadcast',
    'message_logs',
    'telegram',
    'portal',
    'el_transfer',
    'el_required_cards',
  ];

  late String _section = _tabId(widget.currentTab);
  final Map<String, GlobalKey<NavigatorState>> _navKeys = {};
  final List<String> _opened = [];
  final Map<String, Widget Function()> _roots = {};

  static String _tabId(int i) => 'tab:${i.clamp(0, 2)}';

  @override
  void initState() {
    super.initState();
    _open(_section);
    DesktopLayout.shellMounted();
  }

  @override
  void dispose() {
    DesktopLayout.shellUnmounted();
    super.dispose();
  }

  @override
  void didUpdateWidget(DesktopShell old) {
    super.didUpdateWidget(old);
    // انتقالٌ من داخل الشاشات (بطاقة في الرئيسيّة تفتح المشتركين بفلتر، إشعار…).
    final id = _tabId(widget.currentTab);
    if (widget.currentTab != old.currentTab && _section != id) _open(id);
  }

  void _open(String id, [Widget Function()? root]) {
    _section = id;
    if (_navKeys.containsKey(id)) return;
    _navKeys[id] = GlobalKey<NavigatorState>();
    _opened.add(id);
    if (root != null) _roots[id] = root;
  }

  void _select(String id, {Widget Function()? root, bool locked = false, String? unavailable}) {
    if (locked || unavailable != null) {
      showNoPermission(context, message: unavailable);
      return;
    }
    HapticFeedback.selectionClick();
    if (id == _section) {
      _navKeys[id]?.currentState?.popUntil((r) => r.isFirst);
      return;
    }
    setState(() => _open(id, root));
    if (id.startsWith('tab:')) {
      widget.onSelectTab(int.parse(id.substring(4)));
    } else {
      widget.onLeaveTabs();
    }
  }

  Widget _rootOf(String id) {
    if (id.startsWith('tab:')) {
      final i = int.parse(id.substring(4));
      // الصلاحيّات/المزوّد قد تُحسم بعد أوّل بناء (الأجهزة المقفلة للموظّف…).
      return ListenableBuilder(
        listenable: Listenable.merge([ProviderService.changes, Perms.changes]),
        builder: (_, __) => widget.tabBuilder(i),
      );
    }
    if (id == 'settings') return const SettingsScreen();
    return _roots[id]!();
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final mac = !kIsWeb && Platform.isMacOS;
    return CallbackShortcuts(
      bindings: {
        SingleActivator(LogicalKeyboardKey.keyK, control: !mac, meta: mac): () =>
            showQuickSearch(context),
        SingleActivator(LogicalKeyboardKey.keyN, control: !mac, meta: mac): widget.onQuickAdd,
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            _navKeys[_section]?.currentState?.maybePop(),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: AppColors.bg,
          body: Row(
            children: [
              SizedBox(width: _sidebarWidth, child: _sidebar(mac)),
              Expanded(child: _content()),
            ],
          ),
        ),
      ),
    );
  }

  // ───────────────────────────── المحتوى ─────────────────────────────

  Widget _content() {
    return LayoutBuilder(builder: (context, c) {
      final width = c.maxWidth > _maxContent ? _maxContent : c.maxWidth;
      final mq = MediaQuery.of(context);
      return Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: width,
          height: c.maxHeight,
          // الشاشات تقيس MediaQuery: هنا عرض منطقة المحتوى لا النافذة كلّها.
          child: MediaQuery(
            data: mq.copyWith(size: Size(width, c.maxHeight)),
            child: IndexedStack(
              index: _opened.indexOf(_section),
              children: [
                for (final id in _opened)
                  Navigator(
                    key: _navKeys[id],
                    onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => _rootOf(id)),
                  ),
              ],
            ),
          ),
        ),
      );
    });
  }

  // ───────────────────────────── القائمة ─────────────────────────────

  Widget _sidebar(bool mac) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: BorderDirectional(end: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _brand(),
            Padding(
              padding: const EdgeInsets.fromLTRB(Sp.md, 0, Sp.md, Sp.sm),
              child: _SearchBox(
                shortcut: mac ? '⌘K' : 'Ctrl K',
                onTap: () => showQuickSearch(context),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Sp.md, 0, Sp.md, Sp.md),
              child: _AddButton(onTap: widget.onQuickAdd),
            ),
            Divider(height: 1, thickness: 1, color: AppColors.border),
            Expanded(
              child: ListenableBuilder(
                listenable: appModulesListenable(),
                builder: (context, _) => _nav(),
              ),
            ),
            _footer(),
          ],
        ),
      ),
    );
  }

  Widget _brand() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.md, Sp.lg, Sp.md, Sp.md),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(R.sm),
            child: Image.asset('assets/images/app_icon.png', width: 38, height: 38),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'MyServices Pro',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.label(color: AppColors.textHi)
                      .copyWith(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                ValueListenableBuilder<ActiveCompanyInfo?>(
                  valueListenable: ActiveCompany.listenable,
                  builder: (_, info, __) => info == null
                      ? const SizedBox.shrink()
                      : ActiveCompanyLine(info: info, fontSize: 11.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _nav() {
    final modules = buildAppModules()
      ..sort((a, b) => _moduleOrder.indexOf(a.id).compareTo(_moduleOrder.indexOf(b.id)));
    List<Widget> group(AppModuleGroup g) => [
          for (final m in modules.where((m) => m.group == g))
            _item('mod:${m.id}', m.icon, m.title,
                root: m.page, locked: m.locked, unavailable: m.unavailable),
        ];
    final finance = group(AppModuleGroup.finance);
    final comms = group(AppModuleGroup.comms);
    final earthlink = group(AppModuleGroup.earthlink);
    return ListView(
      padding: const EdgeInsets.fromLTRB(Sp.sm, Sp.sm, Sp.sm, Sp.md),
      children: [
        _item('tab:0', LucideIcons.layoutDashboard, 'nav.home'.tr()),
        _groupTitle('desktop.group_manage'.tr()),
        _item('tab:1', LucideIcons.users, 'nav.subscribers'.tr()),
        _item('tab:2', LucideIcons.router, 'nav.devices'.tr()),
        ...group(AppModuleGroup.manage),
        if (finance.isNotEmpty) ...[_groupTitle('desktop.group_finance'.tr()), ...finance],
        if (comms.isNotEmpty) ...[_groupTitle('desktop.group_comms'.tr()), ...comms],
        _groupTitle('desktop.group_customize'.tr()),
        ...group(AppModuleGroup.customize),
        _item('settings', LucideIcons.settings, 'settings.title'.tr()),
        if (earthlink.isNotEmpty) ...[_groupTitle('desktop.group_earthlink'.tr()), ...earthlink],
      ],
    );
  }

  Widget _groupTitle(String text) => Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(Sp.sm, Sp.md, Sp.sm, Sp.xs),
        child: Text(
          text,
          style: AppType.micro(color: AppColors.textLow)
              .copyWith(fontWeight: FontWeight.w600, letterSpacing: 0.2),
        ),
      );

  Widget _item(
    String id,
    IconData icon,
    String title, {
    Widget Function()? root,
    bool locked = false,
    String? unavailable,
  }) {
    return _SideItem(
      icon: icon,
      title: title,
      selected: id == _section,
      locked: locked || unavailable != null,
      onTap: () => _select(id, root: root, locked: locked, unavailable: unavailable),
    );
  }

  Widget _footer() {
    final email = AccountService.currentUser?.email;
    if (email == null || email.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.fromLTRB(Sp.md, Sp.sm, Sp.md, Sp.md),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
      child: Row(
        children: [
          Icon(LucideIcons.circleUserRound, size: 18, color: AppColors.textLow),
          const SizedBox(width: Sp.sm),
          Expanded(
            child: Text(
              email,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.start,
              style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _SideItem extends StatefulWidget {
  const _SideItem({
    required this.icon,
    required this.title,
    required this.selected,
    required this.locked,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final bool selected;
  final bool locked;
  final VoidCallback onTap;

  @override
  State<_SideItem> createState() => _SideItemState();
}

class _SideItemState extends State<_SideItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final selected = widget.selected;
    final locked = widget.locked;
    final fg = selected
        ? AppColors.brandOnSoft
        : locked
            ? LockedStyle.title
            : AppColors.textHi;
    final iconColor = selected
        ? AppColors.brand
        : locked
            ? LockedStyle.glyph
            : AppColors.textMid;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.brandSoftBg
                  : _hover
                      ? AppColors.surfaceSunken
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(R.sm),
            ),
            child: Row(
              children: [
                Icon(widget.icon, size: 18, color: iconColor),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.label(color: fg).copyWith(
                      fontSize: 13.5,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
                if (locked) Icon(LucideIcons.lock, size: 14, color: LockedStyle.glyph),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchBox extends StatelessWidget {
  const _SearchBox({required this.shortcut, required this.onTap});

  final String shortcut;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Material(
      color: AppColors.surfaceSunken,
      borderRadius: BorderRadius.circular(R.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(R.md),
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.md),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Icon(LucideIcons.search, size: 16, color: AppColors.textLow),
              const SizedBox(width: Sp.sm),
              Expanded(
                child: Text(
                  'desktop.search_hint'.tr(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.muted(color: AppColors.textLow).copyWith(fontSize: 13),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(R.sm),
                  border: Border.all(color: AppColors.border),
                ),
                child: Text(
                  shortcut,
                  textDirection: TextDirection.ltr,
                  style: AppType.micro(color: AppColors.textMid).copyWith(fontSize: 10.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return SizedBox(
      height: 40,
      child: FilledButton.icon(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.brand,
          foregroundColor: AppColors.onBrand,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.md)),
          textStyle: AppType.label().copyWith(fontWeight: FontWeight.w700, fontSize: 13.5),
        ),
        icon: const Icon(LucideIcons.plus, size: 18),
        label: Text('desktop.add'.tr()),
      ),
    );
  }
}
