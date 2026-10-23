import 'dart:io' show Platform;

import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/platform/desktop_layout.dart';
import '../../core/widgets/permission_locked.dart';
import '../../services/active_company.dart';
import '../../services/alerts_service.dart';
import '../../services/permissions_service.dart';
import '../../services/linked_companies.dart';
import '../../services/provider_service.dart';
import '../../services/theme_service.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../account/company_switch_sheet.dart';
import '../app_modules.dart';
import '../search/quick_search_overlay.dart';
import '../settings_screen.dart';
import '../top_actions.dart';
import 'desk_widgets.dart';

/// غلاف الحاسبة بلغة الموقع (/v2): قائمةٌ جانبيّة بمجموعاتها، وشريطٌ علويّ فيه عنوان الصفحة وشريحة
/// الشركة والبحث (Ctrl/⌘K) وأزرار الأعلى المشتركة، والمحتوى تحته.
///
/// كلّ قسمٍ له Navigator خاصّ: ما يفتحه القسم يبقى في منطقة المحتوى والقائمة ظاهرة، والرجوع للقسم يحفظ
/// مكانك فيه، والنقر على القسم المفتوح يعيده لبدايته، وEsc رجوع. التبويبات الثلاثة (الرئيسيّة، المشتركون،
/// الأجهزة) شاشات الهاتف نفسها بحالتها، و«قوائم أخرى» تتوزّع على المجموعات من [buildAppModules].
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
  static const double _sidebarWidth = 272;
  static const double _railWidth = 76;

  /// أعرض من هذا يتوسّط المحتوى — شاشاتٌ بُنيت للهاتف لا تتمدّد على شاشةٍ عريضة جدّاً.
  static const double _maxContent = 1240;

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
    'sales',
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
  final Map<String, String> _titles = {};
  final Map<String, String> _subtitles = {};
  bool _collapsed = false;

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

  void _open(String id, [Widget Function()? root, String? title, String? subtitle]) {
    _section = id;
    if (title != null) _titles[id] = title;
    if (subtitle != null) _subtitles[id] = subtitle;
    if (_navKeys.containsKey(id)) return;
    _navKeys[id] = GlobalKey<NavigatorState>();
    _opened.add(id);
    if (root != null) _roots[id] = root;
  }

  void _select(
    String id, {
    Widget Function()? root,
    String? title,
    String? subtitle,
    bool locked = false,
    String? unavailable,
  }) {
    if (locked || unavailable != null) {
      showNoPermission(context, message: unavailable);
      return;
    }
    HapticFeedback.selectionClick();
    if (id == _section) {
      _navKeys[id]?.currentState?.popUntil((r) => r.isFirst);
      return;
    }
    setState(() => _open(id, root, title, subtitle));
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
    return DeskPageInfo(title: _titles[id], subtitle: _subtitles[id], child: _roots[id]!());
  }

  String _sectionTitle() {
    switch (_section) {
      case 'tab:0':
        return 'desktop.title_dashboard'.tr();
      case 'tab:1':
        return 'nav.subscribers'.tr();
      case 'tab:2':
        return 'nav.devices'.tr();
      case 'settings':
        return 'settings.title'.tr();
    }
    return _titles[_section] ?? '';
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
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                width: _collapsed ? _railWidth : _sidebarWidth,
                child: _sidebar(),
              ),
              Expanded(
                child: Column(
                  children: [
                    _TopBar(
                      title: _sectionTitle(),
                      shortcut: mac ? '⌘K' : 'Ctrl K',
                      onSearch: () => showQuickSearch(context),
                      openPage: (page) => _navKeys[_section]
                          ?.currentState
                          ?.push(MaterialPageRoute(builder: (_) => page)),
                    ),
                    Expanded(child: _content()),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ───────────────────────────── المحتوى ─────────────────────────────

  Widget _content() {
    return LayoutBuilder(builder: (context, c) {
      // حشوةٌ للجانبين فوق حشوة الصفحات (١٦) ⇒ ٢٤ من حافّة المحتوى كالموقع.
      final avail = c.maxWidth - 2 * Sp.sm;
      final width = avail > _maxContent ? _maxContent : avail;
      final mq = MediaQuery.of(context);
      return Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: width,
          height: c.maxHeight,
          // الشاشات تقيس MediaQuery: هنا عرض منطقة المحتوى لا النافذة كلّها.
          child: MediaQuery(
            data: mq.copyWith(size: Size(width, c.maxHeight), padding: EdgeInsets.zero),
            child: DesktopScope(
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
        ),
      );
    });
  }

  // ───────────────────────────── القائمة ─────────────────────────────

  Widget _sidebar() {
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
            Divider(height: 1, thickness: 1, color: AppColors.border),
            Expanded(
              child: ListenableBuilder(
                listenable: Listenable.merge([appModulesListenable(), AlertsService.count]),
                builder: (context, _) => _nav(),
              ),
            ),
            _collapseButton(),
            Divider(height: 1, thickness: 1, color: AppColors.border),
            _userCard(),
          ],
        ),
      ),
    );
  }

  Widget _brand() {
    final logo = Container(
      width: 40,
      height: 40,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Image.asset('assets/images/app_icon.png', fit: BoxFit.contain),
    );
    return SizedBox(
      height: 72,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
        child: _collapsed
            ? Center(child: logo)
            : Row(
                children: [
                  logo,
                  const SizedBox(width: Sp.md),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('MyServices',
                            style: AppType.label(color: AppColors.textHi)
                                .copyWith(fontSize: 17, fontWeight: FontWeight.w700)),
                        Text('desktop.brand_subtitle'.tr(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                AppType.muted(color: AppColors.textMid).copyWith(fontSize: 12.5)),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _nav() {
    final modules = buildAppModules()
      ..sort((a, b) => _moduleOrder.indexOf(a.id).compareTo(_moduleOrder.indexOf(b.id)));
    List<Widget> group(AppModuleGroup g) => [
          for (final m in modules.where((m) => m.group == g))
            _item('mod:${m.id}', m.icon, m.title,
                subtitle: m.subtitle,
                root: m.page,
                locked: m.locked,
                unavailable: m.unavailable),
        ];
    final finance = group(AppModuleGroup.finance);
    final comms = group(AppModuleGroup.comms);
    final earthlink = group(AppModuleGroup.earthlink);
    final attention = AlertsService.count.value;
    return ListView(
      key: const ValueKey('desk-sidebar'),
      padding: const EdgeInsets.fromLTRB(Sp.sm, Sp.xs, Sp.sm, Sp.md),
      children: [
        _groupTitle('nav.home'.tr()),
        _item('tab:0', LucideIcons.layoutDashboard, 'desktop.title_dashboard'.tr()),
        _groupTitle('desktop.group_manage'.tr()),
        _item('tab:1', LucideIcons.users, 'nav.subscribers'.tr(),
            badge: attention > 0 ? attention : null),
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

  Widget _groupTitle(String text) {
    if (_collapsed) return const SizedBox(height: Sp.md);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(Sp.md, Sp.lg, Sp.md, Sp.xs),
      child: Text(
        text,
        style: AppType.micro(color: AppColors.textLow).copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _item(
    String id,
    IconData icon,
    String title, {
    String? subtitle,
    Widget Function()? root,
    bool locked = false,
    String? unavailable,
    int? badge,
  }) {
    return _SideItem(
      icon: icon,
      title: title,
      collapsed: _collapsed,
      selected: id == _section,
      locked: locked || unavailable != null,
      badge: badge,
      onTap: () => _select(id,
          root: root,
          title: title,
          subtitle: subtitle,
          locked: locked,
          unavailable: unavailable),
    );
  }

  Widget _collapseButton() {
    return InkWell(
      onTap: () => setState(() => _collapsed = !_collapsed),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Sp.lg, vertical: Sp.sm),
        child: Row(
          mainAxisAlignment: _collapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
          children: [
            Icon(_collapsed ? LucideIcons.chevronsLeft : LucideIcons.chevronsRight,
                size: 16, color: AppColors.textLow),
            if (!_collapsed) ...[
              const SizedBox(width: Sp.sm),
              Text('desktop.collapse'.tr(),
                  style: AppType.muted(color: AppColors.textLow).copyWith(fontSize: 12.5)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _userCard() {
    return ValueListenableBuilder<ActiveCompanyInfo?>(
      valueListenable: ActiveCompany.listenable,
      builder: (context, info, _) {
        final name = info?.username ?? '';
        final avatar = _Avatar(name: name);
        return InkWell(
          onTap: () => _select('settings'),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.md),
            child: _collapsed
                ? Center(child: avatar)
                : Row(
                    children: [
                      avatar,
                      const SizedBox(width: Sp.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textDirection: TextDirection.ltr,
                              style: AppType.label(color: AppColors.textHi)
                                  .copyWith(fontSize: 14, fontWeight: FontWeight.w700),
                            ),
                            if (info != null)
                              Row(
                                children: [
                                  Icon(LucideIcons.building2,
                                      size: 13, color: AppColors.brandAccent),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      info.label,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: AppType.muted(color: AppColors.brandAccent)
                                          .copyWith(fontSize: 12.5, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                      Icon(LucideIcons.chevronDown, size: 16, color: AppColors.textLow),
                    ],
                  ),
          ),
        );
      },
    );
  }
}

/// الشريط العلويّ: عنوان الصفحة وشريحة الشركة يميناً، والبحث وأزرار الأعلى والوضع والصورة يساراً.
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    required this.shortcut,
    required this.onSearch,
    required this.openPage,
  });

  final String title;
  final String shortcut;
  final VoidCallback onSearch;
  final void Function(Widget page) openPage;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: Sp.xl),
      decoration: BoxDecoration(
        color: AppColors.bg,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          // عنوان الصفحة في رأسها الكبير — هنا الشركة المفتوحة (والنقر يبدّلها لمن عنده أكثر من شركة).
          Expanded(
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: ListenableBuilder(
                listenable: Listenable.merge([ActiveCompany.listenable, LinkedCompanies.items]),
                builder: (context, _) {
                  final info = ActiveCompany.current;
                  if (info == null) return const SizedBox.shrink();
                  return _CompanyCard(
                    info: info,
                    onTap: LinkedCompanies.switcherVisible
                        ? () => showCompanySwitchSheet(context)
                        : null,
                  );
                },
              ),
            ),
          ),
          _SearchBox(shortcut: shortcut, onTap: onSearch),
          const SizedBox(width: Sp.md),
          // «الشركات» في بطاقة الشركة يميناً — فلا يتكرّر مربّعها هنا.
          TopActions(switchers: true, companySquare: false, inDesktopBar: true, openPage: openPage),
          const SizedBox(width: Sp.sm),
          const _ThemeToggle(),
          const SizedBox(width: Sp.sm),
          ValueListenableBuilder<ActiveCompanyInfo?>(
            valueListenable: ActiveCompany.listenable,
            builder: (_, info, __) => _Avatar(name: info?.username ?? ''),
          ),
        ],
      ),
    );
  }
}

/// الشركة المفتوحة في الشريط العلويّ: أيقونة واسمها ويوزر المدير، وسهمٌ حين يمكن التبديل.
class _CompanyCard extends StatefulWidget {
  const _CompanyCard({required this.info, required this.onTap});

  final ActiveCompanyInfo info;
  final VoidCallback? onTap;

  @override
  State<_CompanyCard> createState() => _CompanyCardState();
}

class _CompanyCardState extends State<_CompanyCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final info = widget.info;
    final tap = widget.onTap;
    return Tooltip(
      message: tap == null ? '' : 'company_switch.title'.tr(),
      child: MouseRegion(
        cursor: tap == null ? MouseCursor.defer : SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: tap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            constraints: const BoxConstraints(maxWidth: 360),
            padding: const EdgeInsetsDirectional.fromSTEB(6, 6, Sp.md, 6),
            decoration: BoxDecoration(
              color: _hover && tap != null ? AppColors.surfaceSunken : AppColors.surface,
              borderRadius: BorderRadius.circular(R.md),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: AppColors.brandSoftBg,
                    borderRadius: BorderRadius.circular(R.sm),
                  ),
                  child: Icon(LucideIcons.building2, size: 17, color: AppColors.brandAccent),
                ),
                const SizedBox(width: Sp.sm),
                Flexible(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        info.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.label(color: AppColors.textHi)
                            .copyWith(fontSize: 14, fontWeight: FontWeight.w700),
                      ),
                      Text(
                        info.username,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textDirection: TextDirection.ltr,
                        style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
                if (tap != null) ...[
                  const SizedBox(width: Sp.sm),
                  Icon(LucideIcons.chevronsUpDown, size: 16, color: AppColors.textMid),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name});

  final String name;

  static String _initials(String n) {
    final parts = n.split(RegExp(r'[@.\s_-]+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '•';
    final a = parts.first.characters.first;
    final b = parts.length > 1 ? parts[1].characters.first : '';
    return (a + b).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      width: 38,
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.brandSoftBg,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.brandSoftBorder),
      ),
      child: Text(
        _initials(name),
        style: AppType.label(color: AppColors.brandOnSoft)
            .copyWith(fontSize: 13, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _ThemeToggle extends StatelessWidget {
  const _ThemeToggle();

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final dark = AppColors.isDark;
    return _IconSquare(
      icon: dark ? LucideIcons.sun : LucideIcons.moon,
      tooltip: (dark ? 'desktop.light_mode' : 'desktop.dark_mode').tr(),
      onTap: () => ThemeService.setMode(dark ? ThemeMode.light : ThemeMode.dark),
    );
  }
}

class _IconSquare extends StatelessWidget {
  const _IconSquare({required this.icon, required this.tooltip, required this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Tooltip(
      message: tooltip,
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.md),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(R.md),
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(R.md),
              border: Border.all(color: AppColors.border),
            ),
            child: Icon(icon, size: 19, color: AppColors.textHi),
          ),
        ),
      ),
    );
  }
}

class _SideItem extends StatefulWidget {
  const _SideItem({
    required this.icon,
    required this.title,
    required this.collapsed,
    required this.selected,
    required this.locked,
    required this.onTap,
    this.badge,
  });

  final IconData icon;
  final String title;
  final bool collapsed;
  final bool selected;
  final bool locked;
  final int? badge;
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
        ? AppColors.brandAccent
        : locked
            ? LockedStyle.glyph
            : AppColors.textMid;
    final row = Row(
      mainAxisAlignment: widget.collapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
      children: [
        Icon(widget.icon, size: 20, color: iconColor),
        if (!widget.collapsed) ...[
          const SizedBox(width: Sp.md),
          Expanded(
            child: Text(
              widget.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.label(color: fg).copyWith(
                fontSize: 15,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
          if (widget.badge != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
              decoration: BoxDecoration(
                color: AppColors.warningSoftBg,
                borderRadius: BorderRadius.circular(R.pill),
              ),
              child: Text(
                '${widget.badge}',
                style: AppType.micro(color: AppColors.warningOnSoft)
                    .copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          if (locked) Icon(LucideIcons.lock, size: 14, color: LockedStyle.glyph),
        ],
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Tooltip(
        message: widget.collapsed ? widget.title : '',
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: Sp.md),
              decoration: BoxDecoration(
                color: selected
                    ? AppColors.brandSoftBg
                    : _hover
                        ? AppColors.surfaceSunken
                        : Colors.transparent,
                borderRadius: BorderRadius.circular(R.md),
                border: selected
                    ? BorderDirectional(start: BorderSide(color: AppColors.brandAccent, width: 3))
                    : null,
              ),
              child: row,
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
    return SizedBox(
      width: 320,
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.md),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(R.md),
          child: Container(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: Sp.md),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(R.md),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Icon(LucideIcons.search, size: 17, color: AppColors.textMid),
                const SizedBox(width: Sp.sm),
                Expanded(
                  child: Text(
                    'desktop.search_hint'.tr(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.muted(color: AppColors.textLow).copyWith(fontSize: 13.5),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceSunken,
                    borderRadius: BorderRadius.circular(R.sm),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Text(
                    shortcut,
                    textDirection: TextDirection.ltr,
                    style: AppType.micro(color: AppColors.textMid).copyWith(fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
