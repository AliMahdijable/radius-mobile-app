import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/national_more_api.dart';
import '../../api/national_sheet_api.dart';
import '../../api/national_team_api.dart';
import '../../core/util/bidi.dart';
import '../../core/util/format.dart';
import '../../core/widgets/design_sheet.dart';
import '../../core/widgets/sheet_scaffold.dart';
import '../../services/permissions_service.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../desktop/desk_widgets.dart';
import 'national_more_widgets.dart';
import 'national_team_sheet.dart';
import 'national_widgets.dart';

/// «فريقي» — المشروع الوطنيّ (١ نوفمبر، تبويب البوّابة نفسه): مستخدمو حساب الشريك في البوّابة — الاسم واليوزر (آخر ٤ أرقام حين
/// يكون هاتفاً) والوظيفة وحدّ المحفظة («غير محدود» بلا حدّ، «—» للرئيسيّ وما لا يُقرأ) وآخر تسجيل دخول، وعدد الأعضاء.
/// والإضافة والتعديل والحذف (٢ نوفمبر — كالموقع) لصاحب الحساب حين تسمح البوّابة («إدارة أعضاء الفريق») ومفتاح الكتابة: «إضافة عضو»
/// أعلى الصفحة، و«تعديل»/«حذف» لكلّ عضوٍ يقول الخادم can_manage (لا الرئيسيّ ولا أنت). **لا هاتف ولا بريد أبداً** (الخادم لا
/// يرسلهما). الخادم `/api/v2/ftth/team` (العقد §5).
class NationalTeamScreen extends StatefulWidget {
  const NationalTeamScreen({super.key});

  @override
  State<NationalTeamScreen> createState() => _NationalTeamScreenState();
}

class _NationalTeamScreenState extends State<NationalTeamScreen> {
  String _q = '';
  NationalMoreResult<Object?>? _locked;
  final _p = NationalPaged<NationalTeamMember>();

  /// الإدارة مسموحةٌ لهذا الحساب؟ صاحب الحساب + مفتاح الكتابة + صلاحيّة البوّابة (المجهولة لا تقفل).
  bool _canManage = false;

  @override
  void initState() {
    super.initState();
    _reload();
    if (!Perms.isEmployee) {
      NationalSheetApi.beta().then((b) {
        if (!mounted || b == null) return;
        setState(() => _canManage = b.on && b.canWrite && b.lockOf('team_manage') == null);
      });
    }
  }

  Future<void> _addMember() async {
    final changed = await showNationalTeamSheet(context);
    if (changed == true && mounted) _reload();
  }

  Future<void> _editMember(NationalTeamMember m) async {
    final changed = await showNationalTeamSheet(context, member: m);
    if (changed == true && mounted) _reload();
  }

  Future<void> _deleteMember(NationalTeamMember m) async {
    final name = m.name.isNotEmpty ? m.name : (m.login ?? 'العضو');
    final go = await showConfirmSheet(
      context,
      title: 'حذف «$name» من فريقك؟',
      message: 'لا يدخل بوّابة المشروع الوطني بعدها، ولا رجوع بعد الحذف.',
      confirmLabel: 'حذف',
      cancelLabel: 'تراجع',
      icon: LucideIcons.trash2,
      tone: AppTone.danger,
    );
    if (go != true || !mounted) return;
    final r = await NationalTeamApi.remove(m.id!);
    if (!mounted) return;
    if (r.ok) {
      showSheetSnack(context, r.outcome == 'applied' ? 'حُذف «$name» من فريقك' : (r.message ?? 'قبلت البوّابة الحذف — حدّث «فريقي» لتتأكّد'),
          duration: Duration(seconds: r.outcome == 'applied' ? 3 : 8));
      _reload();
      return;
    }
    showSheetSnack(context, r.unconfirmed ? (r.message ?? 'لم يتأكّد الحذف — حدّث «فريقي» وتحقّق') : r.text,
        isError: !r.unconfirmed, duration: const Duration(seconds: 10), autoExplain: false);
    if (r.unconfirmed) _reload();
  }

  @override
  void dispose() {
    _p.dispose();
    super.dispose();
  }

  void _reload() {
    _p.reset();
    _locked = null;
    setState(() {});
    _next();
  }

  void _next() {
    _p.next(
      (page) async {
        final r = await NationalMoreApi.team(page: page, q: _q);
        if (r.locked && mounted) _locked = r;
        return r.toResult();
      },
      onChange: () {
        if (mounted) setState(() {});
      },
      alive: () => mounted,
    );
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: deskPageBar(
        context,
        mobile: AppBar(
          backgroundColor: AppColors.surface,
          elevation: 0,
          scrolledUnderElevation: 0,
          title: Text('فريقي', style: AppType.title(color: AppColors.textHi).copyWith(fontSize: 16)),
          iconTheme: IconThemeData(color: AppColors.textHi),
          actions: [
            if (_canManage)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: Sp.sm),
                child: TextButton.icon(
                  onPressed: _addMember,
                  icon: const Icon(LucideIcons.userPlus, size: 18),
                  label: const Text('إضافة عضو'),
                ),
              ),
          ],
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.huge),
            children: [
              if (_locked == null) ...[
                NationalSearchField(
                  hint: 'الاسم أو اليوزر',
                  initial: _q,
                  onChanged: (v) {
                    _q = v;
                    _reload();
                  },
                ),
                if (_p.total != null && _p.rows.isNotEmpty) ...[
                  const SizedBox(height: Sp.sm),
                  Text('الأعضاء: ${nationalCount(_p.total)}', style: AppType.micro(color: AppColors.textMid)),
                ],
                const SizedBox(height: Sp.md),
              ],
              ..._body(),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _body() {
    if (_p.rows.isEmpty) {
      final l = _locked;
      if (l != null) return [NationalLockedBox(title: l.lockTitle, text: l.error ?? '')];
      if (_p.error != null) return [NationalStateBox.error(text: _p.error!, onRetry: _reload)];
      if (_p.pending) return const [NationalStateBox.pending()];
      if (_p.loading || _p.page == 0) return const [NationalStateBox.loading()];
      return [
        NationalStateBox.empty(
          text: _q.isNotEmpty ? 'لا يوجد عضوٌ يطابق البحث' : 'لا يوجد أعضاء في فريقك',
          icon: LucideIcons.usersRound,
        ),
      ];
    }
    return [
      for (final m in _p.rows) ...[
        _MemberCard(
          m: m,
          onEdit: _canManage && m.canManage && m.id != null ? () => _editMember(m) : null,
          onDelete: _canManage && m.canManage && m.id != null ? () => _deleteMember(m) : null,
        ),
        const SizedBox(height: Sp.sm),
      ],
      if (_p.hasMore)
        NationalLoadMore(loading: _p.loading, onTap: _next, shown: _p.rows.length, total: _p.total, unit: 'عضو'),
    ];
  }
}

class _MemberCard extends StatelessWidget {
  const _MemberCard({required this.m, this.onEdit, this.onDelete});
  final NationalTeamMember m;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep
    // كالبوّابة: حدّه، أو «غير محدود» (بلا محفظةٍ محدودة)، و«—» للمستخدم الرئيسيّ وما لا يُقرأ
    final wallet = switch (m.limited) {
      true => 'حدّ المحفظة: ${m.walletLimit == null ? '—' : iso(formatIQD(m.walletLimit!))}',
      false => 'حدّ المحفظة: غير محدود',
      null => 'حدّ المحفظة: —',
    };
    final role = m.role.isNotEmpty ? m.role : (m.main ? 'مشرف' : 'عضو الفريق');
    final login = m.login;
    return NationalCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(m.name.isEmpty ? (login ?? '—') : m.name,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.listName(color: AppColors.textHi)),
                    if (login != null && m.name.isNotEmpty)
                      Text(login, textDirection: TextDirection.ltr, style: AppType.micro(color: AppColors.textMid)),
                  ],
                ),
              ),
              const SizedBox(width: Sp.sm),
              Flexible(child: ToneChip(label: role, tone: m.main ? AppTone.info : AppTone.neutral, dense: true)),
              if (onEdit != null || onDelete != null)
                PopupMenuButton<String>(
                  tooltip: 'إدارة العضو',
                  icon: Icon(LucideIcons.ellipsisVertical, size: 18, color: AppColors.textMid),
                  onSelected: (v) => v == 'edit' ? onEdit?.call() : onDelete?.call(),
                  itemBuilder: (_) => [
                    if (onEdit != null)
                      const PopupMenuItem(value: 'edit', child: Row(children: [Icon(LucideIcons.userPen, size: 16), SizedBox(width: 8), Text('تعديل')])),
                    if (onDelete != null)
                      const PopupMenuItem(value: 'delete', child: Row(children: [Icon(LucideIcons.trash2, size: 16), SizedBox(width: 8), Text('حذف')])),
                  ],
                ),
            ],
          ),
          const SizedBox(height: Sp.sm),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              nationalMeta(LucideIcons.wallet, wallet),
              nationalMeta(LucideIcons.logIn, m.lastLogin == null ? 'آخر دخول: —' : 'آخر دخول ${iso(nationalTime(m.lastLogin))}'),
            ],
          ),
        ],
      ),
    );
  }
}
