import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../api/view_scope_api.dart';
import '../services/view_scope_events.dart';
import '../services/subscriber_events.dart';
import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';

/// «نطاق العرض» — يخفي مشتركي مدير فرعي أو ديونه من كلّ الشاشات.
///
/// ⚠️ تفضيل عرضٍ لا تحكّم وصول. لا يمنع أحداً من شيء ولا يوقف رسائل
/// الواتساب — ولهذا لم يُسمَّ «صلاحيات»: الاسم كان سيشتبك مع نظام
/// صلاحيات الموظّفين، وذاك يمنع أشخاصاً من أفعال بينما هذا يخصّ ما
/// **تراه أنت**.
///
/// الترشيح يقع على الخادم قبل أن يُسلسَل أيّ صفّ، فالعدّادات والقوائم
/// والتقارير تتّفق كلّها تلقائيّاً. البديل — ترشيحٌ في كلّ شاشة — كان
/// يعني أنّ شاشةً واحدة تنسى فتُسرّب.
class ViewScopeScreen extends StatefulWidget {
  const ViewScopeScreen({super.key});

  @override
  State<ViewScopeScreen> createState() => _ViewScopeScreenState();
}

class _ViewScopeScreenState extends State<ViewScopeScreen> {
  List<ViewScopeManager>? _managers;
  List<DashSection> _sections = const [];
  bool _loading = true;
  bool _failed = false;
  final Set<String> _saving = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    final r = await ViewScopeApi.load();
    if (!mounted) return;
    setState(() {
      _managers = r.managers;
      _sections = r.sections;
      _failed = r.managers == null;
      _loading = false;
    });
  }

  Future<void> _toggle(
    ViewScopeManager m, {
    bool? hideSubscribers,
    bool? hideDebts,
  }) async {
    final next = m.copyWith(
      hideSubscribers: hideSubscribers,
      hideDebts: hideDebts,
    );
    // تفاؤل مؤقّت ليستجيب المفتاح فوراً — ثمّ نتبنّى حقيقة الخادم.
    setState(() {
      _saving.add(m.username);
      _managers = [
        for (final x in _managers ?? const <ViewScopeManager>[])
          x.username == m.username ? next : x
      ];
    });

    final r = await ViewScopeApi.save(
      managerUsername: m.username,
      hideDebts: next.hideDebts,
      hideSubscribers: next.hideSubscribers,
    );
    if (!mounted) return;
    setState(() {
      _saving.remove(m.username);
      // ⚠️ نتبنّى ما أعاده الخادم لا تخميننا: الاسم قد يسقط في التحقّق
      // من شجرة SAS4، فالتفاؤل وحده يترك مفتاحاً يبدو مفعَّلاً بلا أثر.
      if (r.ok && r.managers != null) {
        _managers = r.managers;
      } else {
        _managers = [
          for (final x in _managers ?? const <ViewScopeManager>[])
            x.username == m.username ? m : x
        ];
      }
    });
    if (r.ok) ViewScopeEvents.notifyChanged();
    if (r.ok) {
      // 🐛 بلاغ 2026-08-31: «من انقر اخفاء الا ارفرش يلا يتحدث».
      //
      // الترشيح يقع على الخادم، لكنّ التطبيق يحمل قائمة مُخزَّنة 45
      // ثانية — فتبديل المفتاح كان يغيّر الخادم بينما تعرض الشاشات
      // اللقطة القديمة حتّى تنتهي المهلة أو يسحب المستخدم يدويّاً.
      //
      // `notifyChange` تُسقط الكاش وتُنبّه كلّ الشاشات المشتركة —
      // نفس ما تفعله أيّ عمليّة تعديل ناجحة على مشترك.
      SubscriberEvents.notifyChange();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(r.message ?? 'تعذّر الحفظ'),
          backgroundColor: AppColors.errorFill,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _toggleSection(DashSection sec, bool hidden) async {
    setState(() {
      _saving.add(sec.key);
      _sections = [
        for (final x in _sections)
          x.key == sec.key ? x.copyWith(hidden: hidden) : x
      ];
    });
    final r = await ViewScopeApi.setSection(sec.key, hidden);
    if (!mounted) return;
    setState(() {
      _saving.remove(sec.key);
      // نتبنّى حقيقة الخادم لا تخميننا — كما في مفاتيح المدراء.
      if (r.ok && r.sections.isNotEmpty) _sections = r.sections;
    });
    // بلّغ الشاشات المركَّبة أصلاً — الرئيسيّة تعيش في `IndexedStack`
    // فلا `initState` ثانٍ يوصل إليها التبديل.
    if (r.ok) ViewScopeEvents.notifyChanged();
    if (!r.ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(r.message ?? 'تعذّر الحفظ'),
        backgroundColor: AppColors.errorFill,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final list = _managers ?? const <ViewScopeManager>[];
    final hidden = list.where((m) => m.isHidden).length;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text('نطاق العرض',
            style:
                AppType.title(color: AppColors.textHi).copyWith(fontSize: 16)),
        iconTheme: IconThemeData(color: AppColors.textHi),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: AppColors.brand))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.sm, Sp.lg, Sp.huge),
                children: [
                  _Explainer(hidden: hidden, total: list.length),
                  const SizedBox(height: Sp.md),
                  if (_failed)
                    _Notice(
                      icon: LucideIcons.triangleAlert,
                      text: 'تعذّر جلب قائمة المدراء — اسحب للتحديث',
                      tone: AppColors.errorFill,
                    )
                  else if (list.isEmpty)
                    _Notice(
                      icon: LucideIcons.users,
                      text: 'لا يوجد مدراء فرعيّون تحت حسابك',
                      tone: AppColors.textLow,
                    )
                  else
                    for (final m in list)
                      _ManagerCard(
                        manager: m,
                        busy: _saving.contains(m.username),
                        onSubscribers: (v) =>
                            _toggle(m, hideSubscribers: v),
                        onDebts: (v) => _toggle(m, hideDebts: v),
                      ),
                  if (_sections.isNotEmpty) ...[
                    const SizedBox(height: Sp.lg),
                    const _GroupLabel(
                      icon: LucideIcons.layoutDashboard,
                      title: 'ما يظهر في الرئيسيّة',
                      // إخفاء القسم يُسقط نداءه كذلك — فالفائدة سرعة
                      // إقلاع لا ترتيب شاشة فقط. يستحقّ أن يُقال.
                      sub: 'القسم المخفيّ لا يُرسَم ولا تُجلب بياناته',
                    ),
                    const SizedBox(height: Sp.sm),
                    for (final sec in _sections)
                      _SectionRow(
                        section: sec,
                        busy: _saving.contains(sec.key),
                        onChanged: (hide) => _toggleSection(sec, hide),
                      ),
                  ],
                ],
              ),
            ),
    );
  }
}

class _Explainer extends StatelessWidget {
  const _Explainer({required this.hidden, required this.total});
  final int hidden;
  final int total;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceInput,
        borderRadius: BorderRadius.circular(R.md),
        border: Border.all(color: AppColors.borderSoft),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.eyeOff, size: 16, color: AppColors.textMid),
          const SizedBox(width: Sp.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ما تخفيه يختفي من كلّ الشاشات — القائمة والعدّادات '
                  'والتقارير معاً، لك ولموظّفيك.',
                  style: AppType.muted(color: AppColors.textMid)
                      .copyWith(fontSize: 11.5, height: 1.5),
                ),
                const SizedBox(height: 4),
                Text(
                  'لا يمنع أحداً من العمل ولا يوقف رسائل الواتساب.'
                  '${total > 0 ? '  ·  مخفيّ الآن: $hidden من $total' : ''}',
                  style: AppType.muted(color: AppColors.textLow)
                      .copyWith(fontSize: 11, height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text, required this.tone});
  final IconData icon;
  final String text;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Sp.huge),
      child: Column(
        children: [
          Icon(icon, size: 32, color: tone),
          const SizedBox(height: Sp.sm),
          Text(
            text,
            textAlign: TextAlign.center,
            style: AppType.label(color: AppColors.textMid),
          ),
        ],
      ),
    );
  }
}

class _ManagerCard extends StatelessWidget {
  const _ManagerCard({
    required this.manager,
    required this.busy,
    required this.onSubscribers,
    required this.onDebts,
  });

  final ViewScopeManager manager;
  final bool busy;
  final ValueChanged<bool> onSubscribers;
  final ValueChanged<bool> onDebts;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final on = manager.isHidden;
    return Container(
      margin: const EdgeInsets.only(bottom: Sp.sm),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.md),
        border: Border.all(
          color: on ? AppColors.warningSoftBorder : AppColors.border,
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Sp.md, 10, Sp.md, 6),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: on
                        ? AppColors.warningSoftBg
                        : AppColors.surfaceInput,
                    borderRadius: BorderRadius.circular(R.sm),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    on ? LucideIcons.eyeOff : LucideIcons.userCog,
                    size: 15,
                    color: on ? AppColors.warning : AppColors.textLow,
                  ),
                ),
                const SizedBox(width: Sp.sm),
                Expanded(
                  child: Text(
                    manager.username,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textDirection: TextDirection.ltr,
                    textAlign: TextAlign.right,
                    style: AppType.label(color: AppColors.textHi)
                        .copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                if (busy)
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.brand,
                    ),
                  ),
              ],
            ),
          ),
          Divider(height: 1, color: AppColors.border),
          _MiniToggle(
            icon: LucideIcons.users,
            label: 'إخفاء مشتركيه',
            value: manager.hideSubscribers,
            onChanged: busy ? null : onSubscribers,
          ),
          _MiniToggle(
            icon: LucideIcons.wallet,
            label: 'إخفاء ديونه',
            value: manager.hideDebts,
            onChanged: busy ? null : onDebts,
          ),
        ],
      ),
    );
  }
}

class _MiniToggle extends StatelessWidget {
  const _MiniToggle({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(Sp.md, 0, Sp.sm, 0),
      child: Row(
        children: [
          Icon(icon, size: 14, color: AppColors.textLow),
          const SizedBox(width: Sp.sm),
          Expanded(
            child: Text(
              label,
              style: AppType.label(color: AppColors.textMid),
            ),
          ),
          Switch.adaptive(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel({
    required this.icon,
    required this.title,
    required this.sub,
  });
  final IconData icon;
  final String title;
  final String sub;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: AppColors.textMid),
        const SizedBox(width: Sp.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: AppType.label(color: AppColors.textHi)
                      .copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(sub, style: AppType.micro(color: AppColors.textLow)),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionRow extends StatelessWidget {
  const _SectionRow({
    required this.section,
    required this.busy,
    required this.onChanged,
  });
  final DashSection section;
  final bool busy;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final meta = dashSectionLabels[section.key];
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsetsDirectional.fromSTEB(Sp.md, 4, Sp.sm, 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.md),
        border: Border.all(
          color: section.hidden ? AppColors.warningSoftBorder : AppColors.border,
        ),
      ),
      child: Row(
        children: [
          Icon(
            section.hidden ? LucideIcons.eyeOff : LucideIcons.eye,
            size: 15,
            color: section.hidden ? AppColors.warning : AppColors.textLow,
          ),
          const SizedBox(width: Sp.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  meta?.title ?? section.key,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.label(color: AppColors.textHi),
                ),
                if (meta != null)
                  Text(
                    meta.sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.micro(color: AppColors.textLow),
                  ),
              ],
            ),
          ),
          if (busy)
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            // المفتاح يعني «ظاهر» لا «مخفيّ»: الإيجاب أسهل قراءةً من
            // النفي، ومفتاحٌ مطفأ يعني غياباً بلا تفكير مزدوج.
            Switch.adaptive(
              value: !section.hidden,
              onChanged: (visible) => onChanged(!visible),
            ),
        ],
      ),
    );
  }
}
