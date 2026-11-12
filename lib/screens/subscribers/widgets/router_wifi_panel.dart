import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/net/router_ops.dart';
import '../../../core/net/router_types.dart';
import '../../../core/util/clipboard_helper.dart';
import '../../../models/device_health.dart';
import '../../../services/permissions_service.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';

typedef RouterCreds = ({String ip, String user, String pass});

/// «كلمة سرّ الواي فاي» في كرت الراوتر (١٢ نوفمبر — المالك: «عرض كلمة سر واي فاي وامكانيه تبيدله»): مطويّةٌ حتى ينقرها الوكيل —
/// القراءة دخولٌ على الراوتر لا تجري مع كلّ فتحٍ للكرت. لكلّ شبكة: الاسم وكلمة السرّ (مخفيّةٌ حتى تُكشف، وتُنسخ)، و«تغيير كلمة السرّ»
/// بتأكيدٍ صريح (الأجهزة المتّصلة تنقطع وتحتاج الكلمة الجديدة). صلاحيّة «إدارة الأجهزة» — بلاها يبقى السطر مقفلاً لا مخفيّاً.
class RouterWifiPanel extends StatefulWidget {
  const RouterWifiPanel({super.key, required this.vendor, required this.creds, this.onBusy});

  final String vendor;

  /// قبل كلّ عمليّة (true) وبعدها (false): الكرت يوقف نبضته الحيّة — دخولٌ آخر على راوترٍ بجلسةٍ واحدة يُسقط جلستها.
  final void Function(bool busy)? onBusy;

  /// الاعتماد الذي دخل به الفحص على هذا الراوتر (أو null حين لا اعتماد).
  final Future<RouterCreds?> Function() creds;

  @override
  State<RouterWifiPanel> createState() => _RouterWifiPanelState();
}

class _RouterWifiPanelState extends State<RouterWifiPanel> {
  bool _open = false;
  bool _busy = false;
  List<RouterWifi>? _wifi;
  String? _error;
  final _shown = <int>{};

  bool get _allowed => Perms.has('devices.manage');

  Future<void> _load() async {
    if (_busy) return;
    setState(() {
      _open = true;
      _busy = true;
      _error = null;
    });
    widget.onBusy?.call(true);
    try {
      await _loadInner();
    } finally {
      widget.onBusy?.call(false);
    }
  }

  Future<void> _loadInner() async {
    final c = await widget.creds();
    if (!mounted) return;
    if (c == null) {
      setState(() {
        _busy = false;
        _error = 'لا كلمة سرٍّ للراوتر — اكتبها من «الاعتمادات» أو إعداد المشترك';
      });
      return;
    }
    final r = await RouterOps.readWifi(widget.vendor, c.ip, c.user, c.pass);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _wifi = r.value;
      _error = r.ok ? null : routerFailText(r.fail!);
    });
  }

  void _toggle() {
    if (!_allowed) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('لا صلاحيّة — كلمة سرّ الواي فاي لمن عنده «إدارة الأجهزة»'),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    if (_open) {
      setState(() {
        _open = false;
        _shown.clear();
      });
      return;
    }
    _load();
  }

  Future<void> _change() async {
    final list = _wifi;
    if (list == null) return;
    final next = await showDialog<String>(context: context, builder: (_) => _ChangeWifiDialog(networks: list));
    if (next == null || !mounted) return;
    widget.onBusy?.call(true);
    try {
      await _changeInner(next);
    } finally {
      widget.onBusy?.call(false);
    }
  }

  Future<void> _changeInner(String next) async {
    setState(() => _busy = true);
    final c = await widget.creds();
    if (!mounted) return;
    if (c == null) {
      setState(() => _busy = false);
      return;
    }
    HapticFeedback.mediumImpact();
    final r = await RouterOps.setWifiPassword(widget.vendor, c.ip, c.user, c.pass, next);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (r.ok) _wifi = r.value;
    });
    if (r.needsReboot) {
      // الراوتر حفظها ولا يطبّقها إلّا بعد الإقلاع (TP-Link الكلاسيكيّ يقولها في صفحته) — نسأل الوكيل: الآن أم لاحقاً؟
      final now = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: Icon(LucideIcons.power, color: AppColors.warning, size: 30),
          title: const Text('انحفظت — تطبّق بعد إعادة التشغيل'),
          content: const Text('الراوتر حفظ كلمة السرّ الجديدة ويطبّقها بعد إعادة تشغيله.\nينقطع إنترنت المشترك دقيقة إلى دقيقتين.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('لاحقاً')),
            FilledButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: AppColors.warning),
              icon: const Icon(LucideIcons.power, size: 16),
              label: const Text('إعادة تشغيل الآن'),
            ),
          ],
        ),
      );
      if (now == true && mounted) {
        setState(() => _busy = true);
        final rb = await RouterOps.reboot(widget.vendor, c.ip, c.user, c.pass);
        if (!mounted) return;
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(rb.ok ? 'أُرسل أمر إعادة التشغيل — الواي فاي يرجع بالكلمة الجديدة خلال دقيقتين' : 'تعذّرت إعادة التشغيل: ${routerFailText(rb.fail!)}'),
          backgroundColor: rb.ok ? AppColors.success : AppColors.error,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
        ));
      }
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(r.ok ? 'تغيّرت كلمة سرّ الواي فاي — الأجهزة تتّصل بالكلمة الجديدة' : 'ما تغيّرت: ${routerFailText(r.fail!)}'),
      backgroundColor: r.ok ? AppColors.success : AppColors.error,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 5),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final head = InkWell(
      onTap: _busy ? null : _toggle,
      borderRadius: BorderRadius.circular(R.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Sp.sm),
        child: Row(
          children: [
            Icon(LucideIcons.wifi, size: 16, color: AppColors.brandAccent),
            const SizedBox(width: Sp.sm),
            Expanded(child: Text('كلمة سرّ الواي فاي', style: AppType.bodyStrong(color: AppColors.textHi))),
            if (_busy)
              SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brandAccent))
            else if (!_allowed)
              Icon(LucideIcons.lock, size: 15, color: AppColors.textHint)
            else
              Icon(_open ? LucideIcons.chevronUp : LucideIcons.chevronDown, size: 18, color: AppColors.textHint),
          ],
        ),
      ),
    );
    if (!_open) return head;
    final list = _wifi;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        head,
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: Sp.sm),
            child: Text(_error!, style: AppType.muted(color: AppColors.error)),
          ),
        if (list != null)
          for (var i = 0; i < list.length; i++) _network(i, list[i]),
        if (list != null && list.any((w) => w.enabled && w.canChange))
          Padding(
            padding: const EdgeInsets.only(top: Sp.xs, bottom: Sp.sm),
            child: OutlinedButton.icon(
              onPressed: _busy ? null : _change,
              icon: const Icon(LucideIcons.keyRound, size: 16),
              label: const Text('تغيير كلمة السرّ'),
            ),
          ),
      ],
    );
  }

  Widget _network(int i, RouterWifi w) {
    final shown = _shown.contains(i);
    final pass = w.password;
    return Container(
      margin: const EdgeInsets.only(bottom: Sp.sm),
      padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.sm),
      decoration: BoxDecoration(
        color: AppColors.surfaceSunken,
        borderRadius: BorderRadius.circular(R.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (w.band.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: Sp.x6, vertical: 2),
                  decoration: BoxDecoration(color: AppColors.brandSoftBg, borderRadius: BorderRadius.circular(R.pill)),
                  child: Text(w.band, style: AppType.micro(color: AppColors.brandOnSoft)),
                ),
                const SizedBox(width: Sp.sm),
              ],
              Expanded(
                child: GestureDetector(
                  onLongPress: () => copyToClipboard(context, w.ssid, label: 'اسم الشبكة'),
                  child: Text(w.ssid.isEmpty ? '—' : w.ssid,
                      textDirection: ui.TextDirection.ltr,
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.bodyStrong(color: AppColors.textHi)),
                ),
              ),
              const SizedBox(width: Sp.sm),
              Text(w.enabled ? w.security : 'مطفأة', style: AppType.micro(color: AppColors.textLabel)),
            ],
          ),
          const SizedBox(height: Sp.x6),
          if (pass == null)
            Text(w.security == 'مفتوحة' ? 'بلا كلمة سرّ (شبكة مفتوحة)' : 'لا كلمة سرٍّ شخصيّة تُعرض', style: AppType.muted())
          else
            Row(
              children: [
                Expanded(
                  child: Text(
                    shown ? pass : '•' * (pass.length.clamp(8, 16)),
                    textDirection: ui.TextDirection.ltr,
                    textAlign: TextAlign.right,
                    style: AppType.password(color: AppColors.textHi),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: shown ? 'إخفاء' : 'إظهار',
                  onPressed: () => setState(() => shown ? _shown.remove(i) : _shown.add(i)),
                  icon: Icon(shown ? LucideIcons.eyeOff : LucideIcons.eye, size: 18, color: AppColors.brandAccent),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'نسخ',
                  onPressed: () => copyToClipboard(context, pass, label: 'كلمة سرّ الواي فاي'),
                  icon: Icon(LucideIcons.copy, size: 17, color: AppColors.brandAccent),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _ChangeWifiDialog extends StatefulWidget {
  const _ChangeWifiDialog({required this.networks});
  final List<RouterWifi> networks;

  @override
  State<_ChangeWifiDialog> createState() => _ChangeWifiDialogState();
}

class _ChangeWifiDialogState extends State<_ChangeWifiDialog> {
  final _c = TextEditingController();
  bool _obscure = false;
  String? _err;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _submit() {
    final v = _c.text;
    final bad = wifiPasswordProblem(v);
    if (bad != null) {
      setState(() => _err = bad);
      return;
    }
    Navigator.of(context).pop(v);
  }

  @override
  Widget build(BuildContext context) {
    final names = widget.networks.where((w) => w.enabled && w.canChange).map((w) => w.band.isEmpty ? w.ssid : '${w.ssid} (${w.band})').join('، ');
    return AlertDialog(
      icon: Icon(LucideIcons.keyRound, color: AppColors.warning, size: 30),
      title: const Text('تغيير كلمة سرّ الواي فاي'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('تتغيّر لـ: $names\nالأجهزة المتّصلة تنقطع الآن وتحتاج كلمة السرّ الجديدة.', style: AppType.body()),
          const SizedBox(height: Sp.md),
          TextField(
            controller: _c,
            autofocus: true,
            obscureText: _obscure,
            textDirection: ui.TextDirection.ltr,
            keyboardType: TextInputType.visiblePassword,
            decoration: InputDecoration(
              hintText: '٨ أحرف على الأقل',
              errorText: _err,
              suffixIcon: IconButton(
                onPressed: () => setState(() => _obscure = !_obscure),
                icon: Icon(_obscure ? LucideIcons.eye : LucideIcons.eyeOff, size: 18),
              ),
            ),
            onChanged: (_) {
              if (_err != null) setState(() => _err = null);
            },
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('إلغاء')),
        FilledButton(onPressed: _submit, child: const Text('تغيير')),
      ],
    );
  }
}
