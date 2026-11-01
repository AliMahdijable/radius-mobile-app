import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/national_more_api.dart';
import '../../core/util/bidi.dart';
import '../../core/util/format.dart';
import '../../core/widgets/design_sheet.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../desktop/desk_widgets.dart';
import 'national_more_widgets.dart';
import 'national_widgets.dart';

/// «فريقي» — المشروع الوطنيّ (١ نوفمبر، تبويب البوّابة نفسه): مستخدمو حساب الشريك في البوّابة — الاسم واليوزر (آخر ٤ أرقام حين
/// يكون هاتفاً) والوظيفة وحدّ المحفظة («غير محدود» بلا حدّ، «—» حين لا تقوله البوّابة) وآخر تسجيل دخول، وإجماليّ حدود الفريق.
/// قراءةٌ وحدها: لا إضافة ولا تعبئة ولا تصفير للمصادقة من هنا، و**لا هاتف ولا بريد أبداً** (الخادم لا يرسلهما). الخادم
/// `/api/v2/ftth/team` (العقد §5).
class NationalTeamScreen extends StatefulWidget {
  const NationalTeamScreen({super.key});

  @override
  State<NationalTeamScreen> createState() => _NationalTeamScreenState();
}

class _NationalTeamScreenState extends State<NationalTeamScreen> {
  String _q = '';
  NationalMoreResult<Object?>? _locked;
  final _p = NationalPaged<NationalTeamMember>();

  @override
  void initState() {
    super.initState();
    _reload();
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
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.huge),
            children: [
              if (_locked == null) ...[
                _Summary(raw: _p.raw, total: _p.total, busy: _p.loading || _p.pending),
                const SizedBox(height: Sp.md),
                NationalSearchField(
                  hint: 'الاسم أو اليوزر',
                  initial: _q,
                  onChanged: (v) {
                    _q = v;
                    _reload();
                  },
                ),
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
        _MemberCard(m: m),
        const SizedBox(height: Sp.sm),
      ],
      if (_p.hasMore)
        NationalLoadMore(loading: _p.loading, onTap: _next, shown: _p.rows.length, total: _p.total, unit: 'عضو'),
    ];
  }
}

/// عدد الأعضاء وإجماليّ حدود محافظهم (كالبوّابة: «اجمالي حد المحفظة للفريق») — ما لا يُعرف «—».
class _Summary extends StatelessWidget {
  const _Summary({required this.raw, required this.total, required this.busy});
  final Map<String, dynamic> raw;
  final int? total;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep
    final lim = raw['limits_total'];
    String dash() => busy ? '…' : '—';
    return NationalCard(
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: AppColors.brandSoftBg, borderRadius: BorderRadius.circular(R.icon)),
            child: Icon(LucideIcons.usersRound, color: AppColors.brand, size: 20),
          ),
          const SizedBox(width: Sp.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('الأعضاء', style: AppType.muted()),
                const SizedBox(height: 2),
                Text(total == null ? dash() : nationalCount(total),
                    textDirection: TextDirection.ltr, style: AppType.statValue(color: AppColors.textHi)),
              ],
            ),
          ),
          Container(width: 1, height: 36, color: AppColors.divider),
          const SizedBox(width: Sp.md),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('إجماليّ حدود المحافظ', style: AppType.muted()),
              const SizedBox(height: 2),
              Text(lim is num ? formatIQD(lim) : dash(),
                  textDirection: TextDirection.ltr, style: AppType.amount(color: AppColors.textHi).copyWith(fontSize: 15)),
            ],
          ),
        ],
      ),
    );
  }
}

class _MemberCard extends StatelessWidget {
  const _MemberCard({required this.m});
  final NationalTeamMember m;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep
    // كالبوّابة: الوكيل الرئيسيّ بلا حدٍّ يُذكر؛ العضو: حدّه، أو «غير محدود»، أو «—» حين لا تقوله البوّابة
    final wallet = m.main
        ? null
        : switch (m.limited) {
            true => 'حدّ المحفظة: ${m.walletLimit == null ? '—' : iso(formatIQD(m.walletLimit!))}',
            false => 'حدّ المحفظة: غير محدود',
            null => 'حدّ المحفظة: —',
          };
    final role = m.role.isNotEmpty ? m.role : (m.main ? 'الوكيل الرئيسيّ' : 'عضو الفريق');
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
            ],
          ),
          const SizedBox(height: Sp.sm),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              if (wallet != null) nationalMeta(LucideIcons.wallet, wallet),
              nationalMeta(LucideIcons.logIn, m.lastLogin == null ? 'آخر دخول: —' : 'آخر دخول ${iso(nationalTime(m.lastLogin))}'),
            ],
          ),
        ],
      ),
    );
  }
}
