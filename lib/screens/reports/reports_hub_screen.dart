import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/deleted_debts_api.dart';
import '../../core/widgets/desk_pressable.dart';
import '../../core/widgets/permission_locked.dart';
import '../../services/permissions_service.dart';
import '../../services/provider_service.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../el/el_reports.dart';
import 'activations_report_screen.dart';
import 'activity_log_report_screen.dart';
import 'all_managers_debts_screen.dart';
import 'daily_activations_report_screen.dart';
import 'deleted_debts_screen.dart';
import 'financial_report_screen.dart';
import 'package_distribution_screen.dart';
import 'sessions_report_screen.dart';
import '../../widgets/merged_company_strip.dart';
import '../desktop/desk_widgets.dart';
import '../../core/platform/desktop_layout.dart';

/// شاشة hub للتقارير — 7 كروت تنقل لكل تقرير منفصل.
/// تستبدل reports_screen.dart placeholder "تأتي قريباً".
///
/// كل كرت مرتبط بـperm حسب catalog الـbackend:
///   reports.financial / reports.activations / reports.daily_activations
///   reports.manager_debts / reports.account_statement
///   reports.sessions / reports.activity_log
///
/// 2026-09-13: المصروفات خرجت من هنا إلى «قوائم أخرى» وحدها — كانت
/// مكرّرةً في الشاشتين. وهي إدارةٌ لا تقرير (تُنشئ وتُعدّل وتحذف)،
/// فموضعها مع الوحدات لا مع التقارير التي تُقرأ فقط.
/// ManagerDebts يحوّل لصفحةٍ موجودة. AccountStatement يفتح من تفاصيل المشترك
/// لاحقاً، حالياً لا tile مستقل (مرتبط بمشترك واحد).
///
/// بلاغ 2026-10-14: الكرت بلا مفتاحه **يبقى بمكانه مقفلاً** (خافت + قفل،
/// والنقر رسالة لا تنقّل) بدل أن يختفي — إلّا مفتاحاً لا يُمنح لهذا الدور
/// ([permShown]: ديون المدراء عند موظّف ايرث لنك) فيبقى مخفيّاً.
///
/// ٢٣ أكتوبر: «ديون المشتركين المحذوفين» تظهر حين تُفعَّل للحساب وحده
/// ([DeletedDebtsHubSummary] — كبطاقة الويب)، وتُعاد قراءتها بعد الرجوع منها.
class ReportsHubScreen extends StatefulWidget {
  const ReportsHubScreen({super.key});

  @override
  State<ReportsHubScreen> createState() => _ReportsHubScreenState();
}

class _ReportsHubScreenState extends State<ReportsHubScreen> {
  DeletedDebtsPage? _deletedDebts;

  @override
  void initState() {
    super.initState();
    _loadDeletedDebts();
  }

  Future<void> _loadDeletedDebts() async {
    final p = await DeletedDebtsHubSummary.fetch(previous: _deletedDebts);
    if (mounted) setState(() => _deletedDebts = p);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return ListenableBuilder(
      listenable: Listenable.merge([
        PermissionsService.changes,
        ProviderService.changes,
      ]),
      builder: (context, _) {
        // ٢٤ أكتوبر (المالك: «التقارير لونها ليش هيج أسود وأبيض — اهتمّ بالتصميم»): مجموعاتٌ بعناوين، ولكلّ عائلةٍ
        // لونها الدلاليّ ثابتاً في الهاتف والحاسبة — المال أخضر والدين كهرمانيّ والمحذوف أحمر، التفعيلات بلون العلامة
        // واليوميّة أزرق، الجلسات أزرق والسجلّ بنفسجيّ. اللون مع الأيقونة والعنوان، لا وحده.
        final money = <Widget>[
          if (permShown(const ['reports.financial']))
            _ReportCard(
              locked: !Perms.has('reports.financial'),
              icon: LucideIcons.wallet,
              color: AppColors.success,
              title: 'reports.financial'.tr(),
              subtitle: 'reports.financial_hint'.tr(),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => const FinancialReportScreen()),
              ),
            ),
          // «توزيع الباقات والأرباح» (#٥، ٢٥ أكتوبر): بمفتاحه «توزيع الباقات» (الخادم يفرضه)، SAS4 وايرث لنك — لا
          // تقرير باقاتٍ للوطنيّ.
          if (permShown(const ['reports.packages']) && !ProviderService.isFtth)
            _ReportCard(
              locked: !Perms.has('reports.packages'),
              // ليست أيقونة «حسب الباقة» (تقرير ايرث لنك) — بطاقتان متجاورتان لموزّعها لا تتشابهان.
              icon: LucideIcons.chartPie,
              color: AppColors.success,
              title: 'reports.packages'.tr(),
              subtitle: 'reports.packages_hint'.tr(),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PackageDistributionScreen()),
              ),
            ),
          // ⚠️ **المصروفات ليست هنا**، وإنّما في «قوائم أخرى» وحدها.
          // كانت في الشاشتين بنفس الأيقونة والعنوان والوجهة — مدخلان
          // إلى صفحةٍ واحدة يجعلان المستخدم يظنّهما شيئين مختلفين
          // ويظلّ يبحث عن الفرق. (حُذفت من هنا بطلب صاحب المشروع.)
          if (permShown(const ['reports.manager_debts']))
            _ReportCard(
              locked: !Perms.has('reports.manager_debts'),
              icon: LucideIcons.users,
              color: AppColors.warning,
              title: 'reports.manager_debts'.tr(),
              subtitle: 'reports.manager_debts_hint'.tr(),
              // 2026-07-14: كانت stub بس (رسالة "افتح من مكان ثاني").
              // بُنيت الآن كتقرير حقيقي — summary + list + فلاتر حالة.
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const AllManagersDebtsScreen(),
                ),
              ),
            ),
          if (_deletedDebts case final dd?)
            _ReportCard(
              icon: LucideIcons.userX,
              color: AppColors.error,
              title: 'reports.deleted_debts'.tr(),
              subtitle: DeletedDebtsHubSummary.subtitle(dd),
              onTap: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const DeletedDebtsScreen()),
                );
                _loadDeletedDebts();
              },
            ),
        ];
        final activations = <Widget>[
          if (permShown(const ['reports.activations']))
            _ReportCard(
              locked: !Perms.has('reports.activations'),
              icon: LucideIcons.zap,
              color: AppColors.brand,
              title: 'reports.activations'.tr(),
              subtitle: 'reports.activations_hint'.tr(),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => const ActivationsReportScreen()),
              ),
            ),
          if (permShown(const ['reports.daily_activations']))
            _ReportCard(
              locked: !Perms.has('reports.daily_activations'),
              icon: LucideIcons.calendarDays,
              color: AppColors.info,
              title: 'reports.daily_activations'.tr(),
              subtitle: 'reports.daily_activations_hint'.tr(),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => const DailyActivationsReportScreen()),
              ),
            ),
        ];
        final activity = <Widget>[
          if (permShown(const ['reports.sessions']))
            _ReportCard(
              locked: !Perms.has('reports.sessions'),
              icon: LucideIcons.activity,
              color: AppColors.info,
              title: 'reports.sessions'.tr(),
              subtitle: 'reports.sessions_hint'.tr(),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SessionsReportScreen()),
              ),
            ),
          if (permShown(const ['reports.activity_log']))
            _ReportCard(
              locked: !Perms.has('reports.activity_log'),
              icon: LucideIcons.history,
              color: AppColors.anomaly,
              title: 'reports.activity_log'.tr(),
              subtitle: 'reports.activity_log_hint'.tr(),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => const ActivityLogReportScreen()),
              ),
            ),
        ];
        // ── ايرث لنك (البند ٤) — تقاريرُ خاصّةٌ تُقرأ فقط، لموزِّعي
        // EarthLink وحدهم. الحجب من `ProviderService.isEarthlink` (مصدره
        // /api/auth/me) لا صلاحيّة ساس، فالقائمة تستمع لـ`ProviderService.changes`.
        // وكلٌّ منها بمفتاح الخادم الذي يفرضه (كانت بلا حجبٍ فيفتحها الموظّف
        // ثمّ يردّ الخادم 403): التجريبي والباقات ← activations، والسجلّ
        // ← activity_log.
        final earthlink = <Widget>[
          if (ProviderService.isEarthlink) ...[
            _ReportCard(
              locked: !Perms.has('reports.activations'),
              icon: LucideIcons.flaskConical,
              color: AppColors.info,
              title: 'el.test_usage_title'.tr(),
              subtitle: 'el.test_usage_hint'.tr(),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ElTestUsageScreen()),
              ),
            ),
            _ReportCard(
              locked: !Perms.has('reports.activity_log'),
              icon: LucideIcons.history,
              color: AppColors.anomaly,
              title: 'el.audit_title'.tr(),
              subtitle: 'el.audit_hint'.tr(),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ElAuditScreen()),
              ),
            ),
            _ReportCard(
              locked: !Perms.has('reports.activations'),
              icon: LucideIcons.package,
              color: AppColors.brand,
              title: 'el.by_package_title'.tr(),
              subtitle: 'el.by_package_hint'.tr(),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ElByPackageScreen()),
              ),
            ),
          ],
        ];
        final groups = [
          (label: 'reports.group_money'.tr(), color: AppColors.success, tiles: money),
          (label: 'reports.group_activations'.tr(), color: AppColors.brand, tiles: activations),
          (label: 'reports.group_activity'.tr(), color: AppColors.info, tiles: activity),
          (label: 'reports.group_earthlink'.tr(), color: AppColors.anomaly, tiles: earthlink),
        ].where((g) => g.tiles.isNotEmpty).toList();
        final desk = DesktopScope.of(context);

        return Scaffold(
          backgroundColor: AppColors.bg,
          appBar: deskPageBar(
            context,
            mobile: AppBar(
              backgroundColor: AppColors.surface,
              elevation: 0,
              scrolledUnderElevation: 0,
              title: Text(
                'reports.title'.tr(),
                style:
                    AppType.title(color: AppColors.textHi).copyWith(fontSize: 16),
              ),
              iconTheme: IconThemeData(color: AppColors.textHi),
            ),
          ),
          body: SafeArea(
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                  Sp.lg, desk ? Sp.xs : Sp.lg, Sp.lg, Sp.huge),
              children: [
                // «كل الشركات»: الماليّ لكل الشركات، والبقيّة للشركة المفتوحة — تُسمّى
                const MergedOpenCompanyNote(
                  textKey: 'merged.reports_note',
                  padding: EdgeInsets.only(bottom: Sp.md),
                ),
                if (groups.isEmpty)
                  _emptyState()
                else if (desk)
                  // الحاسبة: لوحةٌ بأعمدة — كلّ عائلةٍ عمودٌ بعنوانه وبطاقاتها تحته، فتملأ الصفحة بلا عمودٍ فارغ
                  // (مجموعةٌ ببطاقتين في شبكة ثلاثيّة كانت تترك ثلثها خالياً). الضيّقة: عمودٌ تحت عمود.
                  DeskGrid(
                    minTileWidth: 280,
                    spacing: Sp.lg,
                    children: [
                      for (final g in groups)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _GroupLabel(text: g.label, color: g.color),
                            const SizedBox(height: Sp.md),
                            for (var i = 0; i < g.tiles.length; i++) ...[
                              if (i > 0) const SizedBox(height: Sp.md),
                              g.tiles[i],
                            ],
                          ],
                        ),
                    ],
                  )
                else
                  for (var g = 0; g < groups.length; g++) ...[
                    if (g > 0) const SizedBox(height: Sp.lg),
                    _GroupLabel(text: groups[g].label, color: groups[g].color),
                    const SizedBox(height: Sp.sm),
                    for (var i = 0; i < groups[g].tiles.length; i++) ...[
                      if (i > 0) const SizedBox(height: Sp.sm),
                      groups[g].tiles[i],
                    ],
                  ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _emptyState() {
    return Padding(
      padding: const EdgeInsets.only(top: Sp.huge),
      child: Center(
        child: Column(
          children: [
            Icon(LucideIcons.lock, size: 36, color: AppColors.textLow),
            const SizedBox(height: 10),
            Text(
              'reports.empty_perms'.tr(),
              style: AppType.label(color: AppColors.textMid),
            ),
            const SizedBox(height: 4),
            Text(
              'reports.empty_perms_hint'.tr(),
              style: AppType.muted().copyWith(fontSize: 12.5),
            ),
          ],
        ),
      ),
    );
  }
}

/// عنوان مجموعةٍ بنقطة لونها — يقسم الصفحة لعائلاتٍ تُقرأ بنظرة (المال، التفعيلات، النشاط).
class _GroupLabel extends StatelessWidget {
  const _GroupLabel({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: Sp.sm),
        Text(
          text,
          style: AppType.label(color: AppColors.textMid)
              .copyWith(fontSize: 13, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({
    this.locked = false,
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;

  /// لون عائلة التقرير (الدلاليّ من اللوحة): شريط البطاقة، صندوق الأيقونة، والإطار والظلّ عند المرور.
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  /// بلا صلاحيّة: المقاس نفسه، ألوان [LockedStyle] (يُهمل [color])، والقفل
  /// مكان السهم، والنقر رسالةٌ لا تنقّل — فلا يُفتح تقريرٌ يردّه الخادم 403.
  final bool locked;

  void _open(BuildContext context) {
    if (locked) {
      showNoPermission(context);
      return;
    }
    HapticFeedback.selectionClick();
    onTap();
  }

  /// خلفيّة صندوق الأيقونة: اللون نفسه ممزوجاً بسطح البطاقة (أصمد من الشفافيّة تحت الظلّ، وأقوى قليلاً ليلاً).
  Color get _soft =>
      Color.alphaBlend(color.withValues(alpha: AppColors.isDark ? 0.22 : 0.14), AppColors.surface);

  Widget _iconBox(double size) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: locked ? LockedStyle.box : _soft,
          borderRadius: BorderRadius.circular(R.md),
        ),
        child: Icon(icon, color: locked ? LockedStyle.glyph : color, size: size * 0.46),
      );

  Widget _texts(bool desk) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppType.label(color: locked ? LockedStyle.title : AppColors.textHi)
                .copyWith(fontSize: desk ? 16 : 14, fontWeight: FontWeight.w700),
          ),
          SizedBox(height: desk ? 4 : 2),
          Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppType.muted(color: locked ? LockedStyle.subtitle : AppColors.textMid)
                .copyWith(fontSize: desk ? 13 : 11.5, height: 1.45),
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final card = DesktopScope.of(context) ? _desk(context) : _phone(context);
    if (!locked) return card;
    return Semantics(
      button: true,
      label: 'locked.a11y'.tr(args: [title]),
      excludeSemantics: true,
      child: card,
    );
  }

  /// الحاسبة: بطاقةٌ بشريط لونها أعلاها، وعند المرور ترتفع قليلاً بإطارٍ وظلٍّ بلونها ويمتلئ سهمها — والكيبورد
  /// يصلها (Tab ثمّ Enter) بحلقة تركيز.
  Widget _desk(BuildContext context) {
    final radius = BorderRadius.circular(R.card);
    return DeskPressable(
      radius: radius,
      semanticLabel: locked ? null : title,
      onTap: () => _open(context),
      builder: (context, hover) {
        final live = hover && !locked;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          transform: Matrix4.translationValues(0, live ? -2 : 0, 0),
          decoration: DeskCard.decoration(hover: live, accent: color),
          child: ClipRRect(
            borderRadius: radius,
            child: Stack(
              children: [
                PositionedDirectional(
                  start: 0,
                  end: 0,
                  top: 0,
                  child: Container(height: 3, color: locked ? LockedStyle.box : color),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(Sp.xl, Sp.xl + 3, Sp.xl, Sp.xl),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 64),
                    child: Row(
                      children: [
                        _iconBox(52),
                        const SizedBox(width: Sp.lg),
                        Expanded(child: _texts(true)),
                        const SizedBox(width: Sp.md),
                        if (locked)
                          const PermLockIcon()
                        else
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 160),
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: live ? _soft : AppColors.surfaceSunken,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(LucideIcons.chevronLeft,
                                size: 18, color: live ? color : AppColors.textMid),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// الهاتف: صفٌّ بشريط لونه على حافّته وصندوق أيقونةٍ ملوّن.
  Widget _phone(BuildContext context) {
    final radius = BorderRadius.circular(R.lg);
    return Material(
      color: AppColors.surface,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _open(context),
        borderRadius: radius,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: AppColors.border),
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 4, color: locked ? LockedStyle.box : color),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(Sp.md, Sp.md, Sp.md, Sp.md),
                    child: Row(
                      children: [
                        _iconBox(44),
                        const SizedBox(width: Sp.md),
                        Expanded(child: _texts(false)),
                        const SizedBox(width: Sp.sm),
                        if (locked)
                          const PermLockIcon()
                        else
                          Icon(LucideIcons.chevronLeft, color: color, size: 18),
                      ],
                    ),
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
