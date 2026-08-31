import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../api/view_scope_api.dart';
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
    final list = await ViewScopeApi.load();
    if (!mounted) return;
    setState(() {
      _managers = list;
      _failed = list == null;
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
    if (!r.ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(r.message ?? 'تعذّر الحفظ'),
          backgroundColor: AppColors.errorFill,
          behavior: SnackBarBehavior.floating,
        ),
      );
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
