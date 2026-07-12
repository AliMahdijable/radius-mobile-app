import 'dart:async';
import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/whatsapp_api.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import 'whatsapp_templates_screen.dart';

/// شاشة حالة WhatsApp — تعرض حالة الاتصال + QR للربط + قائمة
/// الـtoggles لكل المسارات التلقائية + رابط لقوالب الواتساب.
/// مطابق v1 web's WhatsApp settings page.
class WhatsAppStatusScreen extends StatefulWidget {
  const WhatsAppStatusScreen({super.key});

  @override
  State<WhatsAppStatusScreen> createState() => _WhatsAppStatusScreenState();
}

class _WhatsAppStatusScreenState extends State<WhatsAppStatusScreen> {
  WhatsConnectionStatus? _status;
  WhatsFeatures? _features;
  String? _qrData;
  bool _loading = true;
  bool _busy = false;
  bool _savingFeatures = false;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      WhatsAppApi.connectionStatus(live: true),
      WhatsAppApi.getFeatures(),
    ]);
    if (!mounted) return;
    setState(() {
      _status = results[0] as WhatsConnectionStatus?;
      _features = results[1] as WhatsFeatures?;
      _loading = false;
    });
    _startPolling();
  }

  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 4), (_) async {
      if (!mounted) return;
      final s = await WhatsAppApi.connectionStatus();
      if (!mounted) return;
      setState(() => _status = s);
      // لو ربط نجح، أخفِ QR
      if (s?.connected == true && _qrData != null) {
        setState(() => _qrData = null);
      }
    });
  }

  Future<void> _startQrSession() async {
    setState(() => _busy = true);
    await WhatsAppApi.startSession();
    // ننتظر قليلاً ثم نطلب الـQR
    await Future.delayed(const Duration(seconds: 2));
    final qr = await WhatsAppApi.getQr();
    if (!mounted) return;
    setState(() {
      _qrData = qr;
      _busy = false;
    });
    if (qr == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('wa.qr_not_ready'.tr()),
          backgroundColor: Color(0xFFE08F2D),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _reconnect() async {
    setState(() => _busy = true);
    final r = await WhatsAppApi.reconnect();
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(r.ok ? 'wa.reconnecting'.tr() : (r.message ?? 'common.error'.tr())),
        backgroundColor: r.ok ? AppColors.brand : AppColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _disconnect() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('wa.disconnect_title'.tr()),
        content: Text('wa.disconnect_body'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('common.cancel'.tr()),
          ),
          FilledButton(
            style:
                FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('wa.disconnect_btn'.tr()),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    final r = await WhatsAppApi.disconnect();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _qrData = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(r.ok ? 'wa.disconnected'.tr() : (r.message ?? 'common.error'.tr())),
        backgroundColor: r.ok ? AppColors.brand : AppColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
    if (r.ok) {
      // refresh status
      final s = await WhatsAppApi.connectionStatus();
      if (mounted) setState(() => _status = s);
    }
  }

  Future<void> _softReset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('wa.full_reset_title'.tr()),
        content: Text('wa.full_reset_body'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('common.cancel'.tr()),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFE08F2D)),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('common.next'.tr()),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    await WhatsAppApi.softReset();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _qrData = null;
    });
    await _bootstrap();
  }

  Future<void> _updateFeatures(WhatsFeatures next) async {
    setState(() {
      _features = next;
      _savingFeatures = true;
    });
    final r = await WhatsAppApi.saveFeatures(next);
    if (!mounted) return;
    setState(() => _savingFeatures = false);
    if (!r.ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(r.message ?? 'devices.save_failed'.tr()),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    const accent = Color(0xFF25D366);
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          'settings.whatsapp'.tr(),
          style: AppType.title(color: AppColors.textHi)
              .copyWith(fontSize: 16),
        ),
        iconTheme: IconThemeData(color: AppColors.textHi),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: accent,
          onRefresh: _bootstrap,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
                Sp.lg, Sp.md, Sp.lg, Sp.huge),
            children: [
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(child: CircularProgressIndicator()),
                )
              else ...[
                _statusCard(accent),
                const SizedBox(height: Sp.md),
                if (_qrData != null) ...[
                  _qrCard(),
                  const SizedBox(height: Sp.md),
                ],
                _actionsBar(accent),
                const SizedBox(height: Sp.lg),
                _featuresCard(accent),
                const SizedBox(height: Sp.md),
                _templatesLink(accent),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusCard(Color accent) {
    final connected = _status?.connected == true;
    final stabilizing = _status?.stabilizing == true;
    final color = connected
        ? accent
        : (stabilizing ? const Color(0xFFE08F2D) : AppColors.error);
    final label = connected
        ? 'subscribers.status_online'.tr()
        : (stabilizing ? 'wa.stabilizing'.tr() : 'wa.disconnected_state'.tr());
    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            color.withValues(alpha: 0.18),
            color.withValues(alpha: 0.05),
          ],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Stack(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(R.md),
                ),
                alignment: Alignment.center,
                child: Icon(LucideIcons.send, color: color, size: 20),
              ),
              Positioned(
                right: -1,
                bottom: -1,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: AppColors.surface, width: 2),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppType.title(color: AppColors.textHi)
                      .copyWith(fontSize: 18, letterSpacing: -0.4),
                ),
                if (connected && (_status?.phone ?? '').isNotEmpty)
                  Text(
                    _status!.phone!,
                    style: AppType.muted().copyWith(fontSize: 11),
                  ),
                if (connected && (_status?.pushname ?? '').isNotEmpty)
                  Text(
                    _status!.pushname!,
                    style: AppType.muted(color: AppColors.textHi)
                        .copyWith(fontSize: 11, fontWeight: FontWeight.w700),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _qrCard() {
    final qr = _qrData;
    if (qr == null) return const SizedBox.shrink();
    // الـQR من الـbackend يأتي إما base64 (data:image/png;base64,...) أو نص
    // قابل للقراءة. نعرض الـimage لو data URL، وإلا نص.
    Widget body;
    if (qr.startsWith('data:image')) {
      final base64Str = qr.split(',').last;
      try {
        body = Image.memory(
          base64Decode(base64Str),
          width: 240,
          height: 240,
          fit: BoxFit.contain,
        );
      } catch (_) {
        body = SelectableText(qr, style: AppType.input(color: AppColors.textHi));
      }
    } else {
      body = SelectableText(qr,
          style: AppType.input(color: AppColors.textHi).copyWith(
              fontFamily: 'monospace', fontSize: 9));
    }
    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Text(
            'wa.scan_qr'.tr(),
            style: AppType.title(color: AppColors.textHi)
                .copyWith(fontSize: 13),
          ),
          const SizedBox(height: 4),
          Text(
            'wa.scan_qr_hint'.tr(),
            style: AppType.muted().copyWith(fontSize: 11),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: Sp.md),
          Center(child: body),
        ],
      ),
    );
  }

  Widget _actionsBar(Color accent) {
    final connected = _status?.connected == true;
    return Row(
      children: [
        if (!connected) ...[
          Expanded(
            child: _btn(
              icon: LucideIcons.qrCode,
              label: 'wa.qr_pair'.tr(),
              color: accent,
              onTap: _busy ? null : _startQrSession,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _btn(
              icon: LucideIcons.refreshCw,
              label: 'wa.reconnect'.tr(),
              color: const Color(0xFF3B82F6),
              onTap: _busy ? null : _reconnect,
            ),
          ),
        ] else ...[
          Expanded(
            child: _btn(
              icon: LucideIcons.powerOff,
              label: 'wa.disconnect_short'.tr(),
              color: AppColors.error,
              onTap: _busy ? null : _disconnect,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _btn(
              icon: LucideIcons.refreshCw,
              label: 'wa.full_reset_btn'.tr(),
              color: const Color(0xFFE08F2D),
              onTap: _busy ? null : _softReset,
            ),
          ),
        ],
      ],
    );
  }

  Widget _btn({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback? onTap,
  }) {
    final disabled = onTap == null;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(R.md),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.md),
            border: Border.all(
              color: disabled
                  ? AppColors.border
                  : color.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 14, color: disabled ? AppColors.textLow : color),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  color: disabled ? AppColors.textLow : color,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _featuresCard(Color accent) {
    final f = _features ?? const WhatsFeatures();
    final masterOn = f.notificationsEnabled;
    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.settings, color: accent, size: 16),
              const SizedBox(width: 6),
              Text(
                'wa.auto_notifs'.tr(),
                style: AppType.title(color: AppColors.textHi)
                    .copyWith(fontSize: 14),
              ),
              const Spacer(),
              if (_savingFeatures)
                const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'wa.master_hint'.tr(),
            style: AppType.muted().copyWith(fontSize: 11, height: 1.4),
          ),
          const SizedBox(height: 8),
          _toggle(
            label: 'wa.master_switch'.tr(),
            value: masterOn,
            onChanged: (v) =>
                _updateFeatures(f.copyWith(notificationsEnabled: v)),
          ),
          Divider(color: AppColors.border.withValues(alpha: 0.5), height: 16),
          _toggle(
            label: 'wa.welcome_msg'.tr(),
            value: f.welcomeMessage,
            enabled: masterOn,
            onChanged: (v) =>
                _updateFeatures(f.copyWith(welcomeMessage: v)),
          ),
          _toggle(
            label: 'wa.activation_notif'.tr(),
            value: f.sendOnActivation,
            enabled: masterOn,
            onChanged: (v) =>
                _updateFeatures(f.copyWith(sendOnActivation: v)),
          ),
          _toggle(
            label: 'wa.extend_notif'.tr(),
            value: f.sendOnExtension,
            enabled: masterOn,
            onChanged: (v) =>
                _updateFeatures(f.copyWith(sendOnExtension: v)),
          ),
          _toggle(
            label: 'wa.near_expiry_notif'.tr(),
            value: f.expiryReminder,
            enabled: masterOn,
            onChanged: (v) =>
                _updateFeatures(f.copyWith(expiryReminder: v)),
          ),
          _toggle(
            label: 'wa.expired_notif'.tr(),
            value: f.serviceEndNotification,
            enabled: masterOn,
            onChanged: (v) =>
                _updateFeatures(f.copyWith(serviceEndNotification: v)),
          ),
          _toggle(
            label: 'wa.debt_notif'.tr(),
            value: f.debtReminder,
            enabled: masterOn,
            onChanged: (v) => _updateFeatures(f.copyWith(debtReminder: v)),
          ),
        ],
      ),
    );
  }

  Widget _toggle({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
    bool enabled = true,
  }) {
    return SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      dense: true,
      activeColor: const Color(0xFF25D366),
      title: Text(
        label,
        style: AppType.label(
                color: enabled ? AppColors.textHi : AppColors.textLow)
            .copyWith(fontSize: 12.5, fontWeight: FontWeight.w700),
      ),
      value: enabled ? value : false,
      onChanged: enabled ? onChanged : null,
    );
  }

  Widget _templatesLink(Color accent) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(R.lg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const WhatsAppTemplatesScreen(),
          ),
        ),
        child: Container(
          padding: const EdgeInsets.all(Sp.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.lg),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(R.md),
                ),
                alignment: Alignment.center,
                child: Icon(LucideIcons.messageSquareText,
                    color: accent, size: 16),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'settings.whatsapp_templates'.tr(),
                      style: AppType.title(color: AppColors.textHi)
                          .copyWith(fontSize: 14),
                    ),
                    Text(
                      'wa.templates_hint'.tr(),
                      style: AppType.muted().copyWith(fontSize: 11),
                    ),
                  ],
                ),
              ),
              Icon(LucideIcons.chevronLeft,
                  size: 16, color: AppColors.textLow),
            ],
          ),
        ),
      ),
    );
  }
}
