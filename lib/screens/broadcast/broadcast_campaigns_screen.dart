import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/broadcast_api.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';

/// حملات البثّ اليدويّ (٢٧ أكتوبر، المالك: «الوكيل من يرسل جدوله يدوي ماعنده صلاحيه يوقف او يستأنف او يحذف»).
///
/// كلّ بثٍّ أرسله الوكيل = حملة (صفوف طابورٍ تحمل نفس المعرّف). تُعرض بأعدادها (أُرسل/معلّق/فشل) ونصّها ووقتها، ومع التحكّم:
/// إيقافٌ مؤقّت (يمنع إرسال المتبقّي)، استئناف، وحذف (إلغاء المعلّق). المُرسَل لا يتأثّر.
class BroadcastCampaignsScreen extends StatefulWidget {
  const BroadcastCampaignsScreen({super.key});

  @override
  State<BroadcastCampaignsScreen> createState() => _BroadcastCampaignsScreenState();
}

class _BroadcastCampaignsScreenState extends State<BroadcastCampaignsScreen> {
  List<BroadcastCampaign> _campaigns = const [];
  bool _loading = true;
  String? _error;
  final Set<String> _busy = {}; // حملاتٌ عمليّتها جارية (منع النقر المزدوج)

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await BroadcastApi.listCampaigns();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _campaigns = r.campaigns;
      _error = r.ok ? null : (r.message ?? 'تعذّر جلب الحملات');
    });
  }

  Future<void> _act(BroadcastCampaign c, String action, String verb) async {
    if (_busy.contains(c.batchId)) return;
    if (action == 'delete') {
      final ok = await _confirmDelete(c);
      if (ok != true) return;
    }
    setState(() => _busy.add(c.batchId));
    final r = await BroadcastApi.campaignAction(c.batchId, action);
    if (!mounted) return;
    setState(() => _busy.remove(c.batchId));
    _toast(r.ok ? (r.message ?? 'تمّ $verb') : (r.message ?? 'تعذّر $verb'), isError: !r.ok);
    if (r.ok) await _load();
  }

  Future<bool?> _confirmDelete(BroadcastCampaign c) => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('حذف الحملة'),
          content: Text('يُلغى إرسال ${c.pending} رسالة معلّقة من هذه الحملة. المُرسَل سابقاً لا يتأثّر.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('تراجع')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: AppColors.error),
              child: const Text('حذف'),
            ),
          ],
        ),
      );

  void _toast(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? AppColors.error : AppColors.brand,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('حملات التبليغ')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _campaigns.isEmpty
                ? _empty()
                : ListView.separated(
                    padding: const EdgeInsets.all(Sp.lg),
                    itemCount: _campaigns.length,
                    separatorBuilder: (_, __) => const SizedBox(height: Sp.sm),
                    itemBuilder: (_, i) => _card(_campaigns[i]),
                  ),
      ),
    );
  }

  Widget _empty() => ListView(
        children: [
          const SizedBox(height: 120),
          Icon(LucideIcons.megaphone, size: 40, color: AppColors.textLow),
          const SizedBox(height: Sp.md),
          Center(
            child: Text(
              _error ?? 'لا حملات تبليغٍ حديثة',
              style: AppType.body(color: AppColors.textMid),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      );

  Widget _card(BroadcastCampaign c) {
    final busy = _busy.contains(c.batchId);
    final done = c.sent + c.failed + c.cancelled;
    final (String pill, AppTone tone) = c.paused
        ? ('موقوفة', AppTone.warning)
        : c.active
            ? ('ترسل الآن', AppTone.brand)
            : ('انتهت', AppTone.neutral);
    return Container(
      padding: const EdgeInsets.all(Sp.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.card),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(c.telegram > 0 && c.telegram >= c.total ? LucideIcons.send : LucideIcons.messageCircle,
              size: 16, color: AppColors.brandAccent),
          const SizedBox(width: Sp.sm),
          Expanded(
            child: Text(
              c.createdAt == null ? 'حملة' : _when(c.createdAt!),
              style: AppType.muted(color: AppColors.textMid),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          _Pill(pill, tone: tone),
        ]),
        const SizedBox(height: Sp.sm),
        if (c.sample.isNotEmpty)
          Text(c.sample, style: AppType.body(color: AppColors.textHi), maxLines: 2, overflow: TextOverflow.ellipsis),
        const SizedBox(height: Sp.sm),
        // أُرسل من الكلّي
        Row(children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(R.pill),
              child: LinearProgressIndicator(
                value: c.total == 0 ? 0 : done / c.total,
                minHeight: 6,
                backgroundColor: AppColors.surfaceSunken,
                valueColor: AlwaysStoppedAnimation(AppColors.brand),
              ),
            ),
          ),
          const SizedBox(width: Sp.sm),
          Text('$done/${c.total}', style: AppType.muted(color: AppColors.textMid)),
        ]),
        const SizedBox(height: Sp.sm),
        Wrap(spacing: Sp.sm, runSpacing: 4, children: [
          _stat('أُرسل', c.sent, AppColors.success),
          _stat('معلّق', c.pending, AppColors.brand),
          if (c.failed > 0) _stat('فشل', c.failed, AppColors.error),
          if (c.cancelled > 0) _stat('أُلغي', c.cancelled, AppColors.textLow),
        ]),
        if (c.active || c.pending > 0) ...[
          const SizedBox(height: Sp.md),
          Row(children: [
            if (c.paused)
              Expanded(child: _btn('استئناف', LucideIcons.play, AppColors.brand, busy, () => _act(c, 'resume', 'الاستئناف')))
            else
              Expanded(child: _btn('إيقاف', LucideIcons.pause, AppColors.warning, busy, () => _act(c, 'pause', 'الإيقاف'))),
            const SizedBox(width: Sp.sm),
            Expanded(child: _btn('حذف', LucideIcons.trash2, AppColors.error, busy, () => _act(c, 'delete', 'الحذف'))),
          ]),
        ],
      ]),
    );
  }

  Widget _stat(String label, int n, Color color) => Text.rich(TextSpan(children: [
        TextSpan(text: '$n ', style: AppType.rowValue(color: color)),
        TextSpan(text: label, style: AppType.muted(color: AppColors.textMid)),
      ]));

  Widget _btn(String label, IconData icon, Color color, bool busy, VoidCallback onTap) => OutlinedButton.icon(
        onPressed: busy ? null : onTap,
        icon: busy
            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
            : Icon(icon, size: 15, color: color),
        label: Text(label, style: TextStyle(color: color)),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: color.withValues(alpha: 0.5)),
          minimumSize: const Size.fromHeight(40),
        ),
      );

  String _two(int n) => n.toString().padLeft(2, '0');
  String _when(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)} ${_two(d.hour)}:${_two(d.minute)}';
}

class _Pill extends StatelessWidget {
  const _Pill(this.text, {required this.tone});
  final String text;
  final AppTone tone;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: Sp.sm, vertical: 3),
        decoration: BoxDecoration(color: tone.softBg, borderRadius: BorderRadius.circular(R.pill)),
        child: Text(text, style: AppType.pillBold(color: tone.onSoft)),
      );
}
