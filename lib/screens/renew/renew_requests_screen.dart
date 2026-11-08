import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/renew_requests_api.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../desktop/desk_widgets.dart';
import '../portal_settings/portal_settings_screen.dart';
import 'renew_widgets.dart';
import '../../widgets/merged_section.dart';

/// «طلبات التفعيل» (٤ نوفمبر — المالك): مشتركوك يطلبون التجديد من تطبيقهم مع صورة التحويل. المفتوحة (بانتظارك ثمّ المقبولة) أو
/// آخر ٣٠ يوماً، والنقر يفتح الطلب بصورته وإجراءاته. الموظّف بلا «طلبات التفعيل» يراها مقفلةً لا مخفيّة.
class RenewRequestsScreen extends StatefulWidget {
  const RenewRequestsScreen({super.key});

  @override
  State<RenewRequestsScreen> createState() => _RenewRequestsScreenState();
}

class _RenewRequestsScreenState extends State<RenewRequestsScreen> {
  RenewAccess? _access;
  List<RenewRequest> _items = const [];
  int _pending = 0, _accepted = 0;
  bool _all = false;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final a = await RenewRequestsApi.access();
    ({List<RenewRequest> items, int pending, int accepted})? l;
    if (a != null && a.available && a.canUse) l = await RenewRequestsApi.list(all: _all);
    if (!mounted) return;
    setState(() {
      _access = a;
      _failed = a == null || (a.available && a.canUse && l == null);
      if (l != null) {
        _items = _all ? l.items : sortOpenFirst(l.items);
        _pending = l.pending;
        _accepted = l.accepted;
      }
      _loading = false;
    });
    // الجرس يتبع ما رأيته هنا
    if (l != null && !_all) await RenewRequestsState.ensureFresh(force: true);
  }

  void _setView(bool all) {
    if (all == _all) return;
    setState(() {
      _all = all;
      _loading = true;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: deskPageBar(
        context,
        mobile: AppBar(
          backgroundColor: AppColors.surface,
          elevation: 0,
          scrolledUnderElevation: 0,
          iconTheme: IconThemeData(color: AppColors.textHi),
          title: Text('طلبات التفعيل', style: AppType.title(color: AppColors.textHi).copyWith(fontSize: 16)),
        ),
        title: 'طلبات التفعيل',
      ),
      body: MergedSectionBody(child: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.huge),
                children: _body(),
              ),
            )),
    );
  }

  List<Widget> _body() {
    final a = _access;
    if (a == null) return [_center(LucideIcons.wifiOff, 'تعذّر جلب الطلبات الآن', 'اسحب للأسفل لإعادة المحاولة')];
    if (!a.available) return [_center(LucideIcons.inbox, '«طلبات التفعيل» غير مفعّلة لحسابك بعد', '')];
    if (!a.canUse) {
      return [
        _center(LucideIcons.lock, 'لا صلاحيّة',
            a.scoped ? 'القسم يشمل كلّ مشتركي الحساب — لا يُفتح لموظّفٍ مقيَّد بمديرٍ فرعيّ' : 'يفتحها لك المدير من صلاحيّاتك: «طلبات التفعيل من تطبيق المشترك — القسم»'),
      ];
    }
    return [
      if (!a.enabled) ...[
        Container(
          padding: const EdgeInsets.all(Sp.md),
          decoration: BoxDecoration(
            color: AppColors.warningSoftBg,
            borderRadius: BorderRadius.circular(R.lg),
            border: Border.all(color: AppColors.warningSoftBorder),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('مشتركوك لا يرون «طلب التجديد» بتطبيقهم بعد — فعّله من «بوابة المشترك» واكتب رقم زين كاش أو الماستر.',
                style: AppType.label(color: AppColors.warningOnSoft).copyWith(height: 1.5)),
            if (a.canEdit) ...[
              const SizedBox(height: Sp.sm),
              OutlinedButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PortalSettingsScreen())),
                child: const Text('فتح الإعداد'),
              ),
            ],
          ]),
        ),
        const SizedBox(height: Sp.md),
      ],
      Row(children: [
        Expanded(child: _stat(LucideIcons.hourglass, 'بانتظارك', _pending, AppColors.warningOnSoft, AppColors.warningSoftBg)),
        const SizedBox(width: Sp.sm),
        Expanded(child: _stat(LucideIcons.clock, 'مقبول', _accepted, AppColors.info, AppColors.infoSoftBg)),
      ]),
      const SizedBox(height: Sp.md),
      SegmentedButton<bool>(
        segments: [
          ButtonSegment(value: false, label: Text('المفتوحة${_pending + _accepted > 0 ? ' (${_pending + _accepted})' : ''}')),
          const ButtonSegment(value: true, label: Text('آخر ٣٠ يوماً')),
        ],
        selected: {_all},
        showSelectedIcon: false,
        onSelectionChanged: (s) => _setView(s.first),
      ),
      const SizedBox(height: Sp.md),
      if (_failed)
        _center(LucideIcons.wifiOff, 'تعذّر جلب الطلبات الآن', 'اسحب للأسفل لإعادة المحاولة')
      else if (_items.isEmpty)
        _center(LucideIcons.inbox, _all ? 'لا طلبات خلال ٣٠ يوماً' : 'لا طلبات مفتوحة الآن',
            'حين يطلب مشترك تجديد اشتراكه من تطبيقه يظهر هنا مع صورة التحويل')
      else
        for (final r in _items) ...[
          RenewRequestTile(
            request: r,
            onTap: () async {
              await showRenewRequestSheet(context, r);
              if (mounted) await _load();
            },
          ),
          const SizedBox(height: Sp.sm),
        ],
    ];
  }

  Widget _stat(IconData icon, String label, int n, Color fg, Color bg) => Container(
        padding: const EdgeInsets.all(Sp.md),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(R.lg),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(R.sm)),
            child: Icon(icon, size: 18, color: fg),
          ),
          const SizedBox(width: Sp.sm),
          Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.label(color: AppColors.textMid))),
          Text('$n', style: AppType.statValue(color: fg)),
        ]),
      );

  Widget _center(IconData icon, String title, String sub) => Padding(
        padding: const EdgeInsets.only(top: Sp.mega),
        child: Column(children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(color: AppColors.brandSoftBg, shape: BoxShape.circle),
            child: Icon(icon, size: 30, color: AppColors.brand),
          ),
          const SizedBox(height: Sp.md),
          Text(title, textAlign: TextAlign.center, style: AppType.bodyStrong(color: AppColors.textHi)),
          if (sub.isNotEmpty) ...[
            const SizedBox(height: Sp.xs),
            Text(sub, textAlign: TextAlign.center, style: AppType.muted(color: AppColors.textMid)),
          ],
        ]),
      );
}
