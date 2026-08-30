import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/whatsapp_api.dart';
import '../../services/manual_wa_prefs.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import 'whatsapp_templates_screen.dart';
import 'widgets/send_scope_panel.dart';

/// شاشة حالة WhatsApp — تعرض حالة الاتصال + QR للربط + قائمة
/// الـtoggles لكل المسارات التلقائية + رابط لقوالب الواتساب.
/// مطابق v1 web's WhatsApp settings page.
class WhatsAppStatusScreen extends StatefulWidget {
  const WhatsAppStatusScreen({super.key});

  @override
  State<WhatsAppStatusScreen> createState() => _WhatsAppStatusScreenState();
}

/// Pairing method the admin selected before hitting Connect.
enum _AuthMode { qr, code }

class _WhatsAppStatusScreenState extends State<WhatsAppStatusScreen>
    with WidgetsBindingObserver {
  WhatsConnectionStatus? _status;
  WhatsFeatures? _features;
  String? _qrData;
  String? _pairCode;
  final TextEditingController _pairPhoneCtl = TextEditingController();
  _AuthMode _authMode = _AuthMode.qr;
  bool _loading = true;
  bool _busy = false;
  bool _savingFeatures = false;
  Timer? _statusPoll;
  Timer? _qrPoll;
  int _qrPollElapsed = 0;
  static const int _qrPollTimeoutSec = 90;
  static const int _pairCodeTimeoutSec = 240; // ~4 min (WAHA gives ~3-5)
  // 2026-08-28 (Google 2027 audit): نتذكّر إذا polling كان نشطاً قبل الـpause
  // لنستأنفه على resume. بلا هذا كل مرة يقفل المستخدم الشاشة، الـpolling
  // يستمر (battery drain) — أو لو أوقفناه بلا تذكّر، ما نعرف نُعيده.
  bool _wasQrPolling = false;
  bool _appActive = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _statusPoll?.cancel();
    _qrPoll?.cancel();
    _pairPhoneCtl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 2026-08-28 (Google 2027 audit HIGH): توفير بطارية + محافظة على backend.
    // Timer.periodic كل 3-4ث كان يستمر لو المدير قفل الشاشة وتركها.
    // نلغيها على paused/inactive ونعيدها على resumed.
    _appActive = state == AppLifecycleState.resumed;
    if (_appActive) {
      _startStatusPolling();
      if (_wasQrPolling && _qrPollElapsed < _qrPollTimeoutSec) {
        _startQrPolling();
      }
    } else {
      _wasQrPolling = _qrPoll?.isActive == true;
      _statusPoll?.cancel();
      _qrPoll?.cancel();
    }
    super.didChangeAppLifecycleState(state);
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
    _startStatusPolling();
  }

  void _startStatusPolling() {
    _statusPoll?.cancel();
    _statusPoll = Timer.periodic(const Duration(seconds: 4), (_) async {
      if (!mounted) return;
      final s = await WhatsAppApi.connectionStatus();
      if (!mounted) return;
      setState(() => _status = s);
      // لو ربط نجح، أخفِ QR/كود وأوقف الـpolling
      if (s?.connected == true) {
        _stopQrPolling();
        if (_qrData != null || _pairCode != null) {
          setState(() {
            _qrData = null;
            _pairCode = null;
          });
        }
      }
    });
  }

  void _stopQrPolling() {
    _qrPoll?.cancel();
    _qrPoll = null;
    _qrPollElapsed = 0;
  }

  /// مطابق v1 web (WhatsApp.tsx:handleConnect):
  /// 1) جرّب reconnect أولاً — لو الجلسة المحفوظة اشتغلت مباشرة، خلصنا.
  /// 2) وإلا start-session ثم polling على /pending-qr/ كل 3ث حتى 90ث.
  ///
  /// زر واحد "اتصال" فقط عند فصل الاتصال (طلب المستخدم 2026-07-12: زر
  /// إعادة اتصال منفصل لا معنى له بدون جلسة سابقة).
  Future<void> _connect() async {
    // Pair-code path: validate phone first — no point round-tripping to
    // the backend when we can catch a bad number here.
    if (_authMode == _AuthMode.code) {
      final digits = _pairPhoneCtl.text.replaceAll(RegExp(r'\D'), '');
      if (digits.length < 8) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('wa.enter_phone_intl'.tr()),
            backgroundColor: AppColors.errorFill,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      setState(() {
        _busy = true;
        _qrData = null;
        _pairCode = null;
      });
      final ss = await WhatsAppApi.startSessionCode(phone: digits);
      if (!mounted) return;
      if (!ss.ok || ss.code == null) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ss.message ?? 'common.error'.tr()),
            backgroundColor: AppColors.errorFill,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      setState(() {
        _pairCode = ss.code;
        _busy = false;
      });
      _startPairCodePolling();
      return;
    }

    // QR path (default)
    setState(() {
      _busy = true;
      _qrData = null;
      _pairCode = null;
    });

    // 1) reconnect silent — لو نجح فوراً بدون QR، خلاص.
    final rc = await WhatsAppApi.reconnect();
    if (!mounted) return;
    if (rc.ok) {
      final s = await WhatsAppApi.connectionStatus(live: true);
      if (!mounted) return;
      if (s?.connected == true) {
        setState(() {
          _status = s;
          _busy = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('wa.reconnected'.tr()),
            backgroundColor: AppColors.brand,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
    }

    // 2) start-session ثم polling على QR.
    final ss = await WhatsAppApi.startSession();
    if (!mounted) return;
    if (!ss.ok) {
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ss.message ?? 'common.error'.tr()),
          backgroundColor: AppColors.errorFill,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    _startQrPolling();
  }

  /// Countdown loop while the admin types the 8-digit code into WhatsApp.
  /// Poll uses connection-status only — the code is already known locally
  /// from startSessionCode's response, so no need to re-fetch it.
  void _startPairCodePolling() {
    _stopQrPolling();
    _qrPoll = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (!mounted) return;
      _qrPollElapsed += 3;
      if (_qrPollElapsed > _pairCodeTimeoutSec) {
        _stopQrPolling();
        if (!mounted) return;
        setState(() {
          _busy = false;
          _pairCode = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('wa.pair_timeout'.tr()),
            backgroundColor: AppColors.errorFill,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      final s = await WhatsAppApi.connectionStatus(live: true);
      if (!mounted) return;
      if (s?.connected == true) {
        _stopQrPolling();
        setState(() {
          _status = s;
          _pairCode = null;
          _busy = false;
        });
      }
    });
  }

  void _startQrPolling() {
    _stopQrPolling();
    _qrPoll = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (!mounted) return;
      _qrPollElapsed += 3;
      if (_qrPollElapsed > _qrPollTimeoutSec) {
        _stopQrPolling();
        if (!mounted) return;
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('wa.qr_timeout'.tr()),
            backgroundColor: AppColors.errorFill,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      final res = await WhatsAppApi.pendingQr();
      if (!mounted) return;
      if (res.connected) {
        _stopQrPolling();
        final s = await WhatsAppApi.connectionStatus(live: true);
        if (!mounted) return;
        setState(() {
          _status = s;
          _qrData = null;
          _busy = false;
        });
        return;
      }
      if (res.qr != null) {
        setState(() {
          _qrData = res.qr;
          _busy = false;
        });
      }
    });
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
            style: FilledButton.styleFrom(backgroundColor: AppColors.errorFill),
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
        content: Text(
            r.ok ? 'wa.disconnected'.tr() : (r.message ?? 'common.error'.tr())),
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
            style: FilledButton.styleFrom(backgroundColor: AppColors.warning),
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
          backgroundColor: AppColors.errorFill,
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
          style: AppType.title(color: AppColors.textHi).copyWith(fontSize: 16),
        ),
        iconTheme: IconThemeData(color: AppColors.textHi),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: accent,
          onRefresh: _bootstrap,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.huge),
            children: [
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(child: CircularProgressIndicator()),
                )
              else ...[
                // 2026-08-26: كارت الوضع اليدوي في أعلى الشاشة — قبل كل شيء
                // آخر. الفكرة الأساسيّة: يشتغل حتى لو WA السيرفر مقطوع، فمو
                // منطقي نخبيه خلف status. يجب أن يكون أوّل شيء يشوفه المدير.
                _manualModeCard(accent),
                const SizedBox(height: Sp.md),
                _statusCard(accent),
                const SizedBox(height: Sp.md),
                if (_hasSafetyNotices) ...[
                  _safetyNotices(),
                  const SizedBox(height: Sp.md),
                ],
                if (_qrData != null) ...[
                  _qrCard(),
                  const SizedBox(height: Sp.md),
                ],
                if (_pairCode != null) ...[
                  _pairCodeCard(accent),
                  const SizedBox(height: Sp.md),
                ],
                // Show the QR/Code mode picker only when disconnected AND
                // no pending pairing is in flight — otherwise it just adds
                // visual noise.
                if (_status?.connected != true &&
                    _qrData == null &&
                    _pairCode == null) ...[
                  _authModePicker(accent),
                  const SizedBox(height: Sp.sm),
                ],
                _actionsBar(accent),
                // 2026-08-26: نطاق الإرسال يظهر دائماً (حتى قبل ربط WA).
                // ⚠️ حرج: المدير يحتاج يقرّر نطاقه بمعزل عن حالة الجلسة —
                // خصوصاً لو WA مقطوع والوضع اليدوي مفعّل (يريد يعرف لأي
                // مدراء يفتح واتساب لهم). SendScopePanel داخلياً يُخفي نفسه
                // لو ما فيه sub-managers، فلا يزعج المدراء الفرديين.
                const SizedBox(height: Sp.md),
                const SendScopePanel(),
                // Features + Templates تظهر فقط عند الاتصال — طلب المستخدم
                // 2026-07-12: لا معنى لعرض toggles إشعارات وقوالب واتساب
                // إذا الجلسة أصلاً غير مربوطة.
                if (_status?.connected == true) ...[
                  const SizedBox(height: Sp.md),
                  _featuresCard(accent),
                  const SizedBox(height: Sp.md),
                  _templatesLink(accent),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  bool get _hasSafetyNotices {
    final s = _status;
    if (s == null) return false;
    return (s.needsPairing && !s.connected) ||
        s.reachoutRestricted ||
        s.messageCapping?.isWarning == true ||
        s.messageCapping?.isCapped == true;
  }

  Widget _safetyNotices() {
    final s = _status;
    if (s == null) return const SizedBox.shrink();
    final notices = <Widget>[];

    if (s.needsPairing && !s.connected) {
      final rawStatus = (s.sessionStatus ?? '').trim();
      notices.add(_safetyNotice(
        color: AppColors.warning,
        icon: LucideIcons.qrCode,
        title: 'wa.needs_pairing_title'.tr(),
        body: rawStatus.isEmpty
            ? 'wa.needs_pairing_body'.tr()
            : 'wa.needs_pairing_body_status'.tr(
                namedArgs: {'status': rawStatus},
              ),
      ));
    }

    if (s.reachoutRestricted) {
      final endsAt = _formatUnixTime(s.restrictionEndsAt);
      notices.add(_safetyNotice(
        color: AppColors.error,
        icon: LucideIcons.triangleAlert,
        title: 'wa.reachout_title'.tr(),
        body: endsAt == null
            ? 'wa.reachout_body'.tr()
            : 'wa.reachout_body_until'.tr(namedArgs: {'time': endsAt}),
      ));
    }

    final capping = s.messageCapping;
    if (capping?.isWarning == true || capping?.isCapped == true) {
      final capped = capping!.isCapped;
      final cycleEnd = _formatUnixTime(capping.cycleEnd);
      final quotaKnown = capping.usedQuota != null &&
          capping.totalQuota != null &&
          capping.totalQuota! > 0;
      final quotaText = quotaKnown
          ? 'wa.capping_quota'.tr(namedArgs: {
              'used': '${capping.usedQuota}',
              'total': '${capping.totalQuota}',
            })
          : '';
      final guidance = capped
          ? (cycleEnd == null
              ? 'wa.capping_body'.tr()
              : 'wa.capping_body_until'.tr(namedArgs: {'time': cycleEnd}))
          : 'wa.capping_warning_body'.tr();
      final progress = quotaKnown
          ? (capping.usedQuota! / capping.totalQuota!)
              .clamp(0.0, 1.0)
              .toDouble()
          : null;
      notices.add(_safetyNotice(
        color: capped ? AppColors.error : AppColors.warning,
        icon: LucideIcons.triangleAlert,
        title:
            capped ? 'wa.capping_title'.tr() : 'wa.capping_warning_title'.tr(),
        body: [quotaText, guidance].where((part) => part.isNotEmpty).join(' '),
        progress: progress,
      ));
    }

    return Column(
      children: [
        for (var i = 0; i < notices.length; i++) ...[
          if (i > 0) const SizedBox(height: Sp.sm),
          notices[i],
        ],
      ],
    );
  }

  Widget _safetyNotice({
    required Color color,
    required IconData icon,
    required String title,
    required String body,
    double? progress,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(R.md),
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppType.title(color: color).copyWith(fontSize: 13),
                ),
                const SizedBox(height: 3),
                Text(
                  body,
                  style: AppType.muted(color: AppColors.textMid)
                      .copyWith(fontSize: 11, height: 1.55),
                ),
                if (progress != null) ...[
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(R.pill),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 5,
                      backgroundColor: color.withValues(alpha: 0.12),
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String? _formatUnixTime(int? seconds) {
    if (seconds == null || seconds <= 0) return null;
    final value = DateTime.fromMillisecondsSinceEpoch(
      seconds * 1000,
      isUtc: true,
    ).toLocal();
    String two(int part) => part.toString().padLeft(2, '0');
    return '${value.year}/${two(value.month)}/${two(value.day)} '
        '${two(value.hour)}:${two(value.minute)}';
  }

  Widget _statusCard(Color accent) {
    final connected = _status?.connected == true;
    final stabilizing = _status?.stabilizing == true;
    final restricted = _status?.hasSendingRestriction == true;
    final needsPairing = _status?.needsPairing == true;
    final color = connected && !restricted
        ? accent
        : (connected || stabilizing || needsPairing
            ? AppColors.warning
            : AppColors.error);
    final label = needsPairing && !connected
        ? 'wa.needs_pairing'.tr()
        : connected
            ? (restricted
                ? 'wa.connected_limited'.tr()
                : 'subscribers.status_online'.tr())
            : (stabilizing
                ? 'wa.stabilizing'.tr()
                : 'wa.disconnected_state'.tr());
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
                    border: Border.all(color: AppColors.surface, width: 2),
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
                      .copyWith(fontSize: 17, letterSpacing: -0.4),
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
        body =
            SelectableText(qr, style: AppType.input(color: AppColors.textHi));
      }
    } else {
      body = SelectableText(qr,
          style:
              AppType.input(color: AppColors.textHi).copyWith(fontSize: 9.5));
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
            style:
                AppType.title(color: AppColors.textHi).copyWith(fontSize: 13),
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

  /// Segmented control + phone input for choosing QR vs pair-code before
  /// hitting Connect. Only shown while disconnected (see build()).
  Widget _authModePicker(Color accent) {
    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'wa.auth_mode_title'.tr(),
            style:
                AppType.title(color: AppColors.textHi).copyWith(fontSize: 13),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _modeChip(
                  icon: LucideIcons.qrCode,
                  label: 'wa.mode_qr'.tr(),
                  active: _authMode == _AuthMode.qr,
                  accent: accent,
                  onTap: () => setState(() => _authMode = _AuthMode.qr),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _modeChip(
                  icon: LucideIcons.smartphone,
                  label: 'wa.mode_code'.tr(),
                  active: _authMode == _AuthMode.code,
                  accent: accent,
                  onTap: () => setState(() => _authMode = _AuthMode.code),
                ),
              ),
            ],
          ),
          if (_authMode == _AuthMode.code) ...[
            const SizedBox(height: 10),
            TextField(
              controller: _pairPhoneCtl,
              keyboardType: TextInputType.phone,
              textDirection: ui.TextDirection.ltr,
              style:
                  AppType.input(color: AppColors.textHi).copyWith(fontSize: 14),
              decoration: InputDecoration(
                isDense: true,
                hintText: '9647701234567',
                hintStyle: AppType.muted(),
                prefixIcon:
                    Icon(LucideIcons.phone, size: 16, color: AppColors.textLow),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(R.md),
                  borderSide: BorderSide(color: AppColors.border),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'wa.mode_code_hint'.tr(),
              style: AppType.muted().copyWith(fontSize: 10.5, height: 1.4),
            ),
          ] else ...[
            const SizedBox(height: 4),
            Text(
              'wa.mode_qr_hint'.tr(),
              style: AppType.muted().copyWith(fontSize: 10.5, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }

  Widget _modeChip({
    required IconData icon,
    required String label,
    required bool active,
    required Color accent,
    required VoidCallback onTap,
  }) {
    return Material(
      color: active ? accent.withValues(alpha: 0.15) : AppColors.surface,
      borderRadius: BorderRadius.circular(R.md),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.md),
            border: Border.all(
              color: active ? accent : AppColors.border,
              width: active ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: active ? accent : AppColors.textLow),
              const SizedBox(width: 6),
              Text(
                label,
                style: AppType.bodyBold(color: active ? accent : AppColors.textMid),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// عرض كبير للرمز الثماني من WAHA — Cairo مثل بقيّة التطبيق.
  /// The admin types this into WhatsApp → Linked Devices → Link with
  /// phone number. Kept intentionally large + selectable.
  Widget _pairCodeCard(Color accent) {
    final code = _pairCode ?? '';
    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: accent.withValues(alpha: 0.4), width: 1.5),
      ),
      child: Column(
        children: [
          Text(
            'wa.pair_code_title'.tr(),
            style:
                AppType.title(color: AppColors.textHi).copyWith(fontSize: 13),
          ),
          const SizedBox(height: 4),
          Text(
            'wa.pair_code_hint'.tr(),
            style: AppType.muted().copyWith(fontSize: 11, height: 1.4),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.surfaceSunken,
              borderRadius: BorderRadius.circular(R.md),
              border: Border.all(color: accent.withValues(alpha: 0.3)),
            ),
            child: SelectableText(
              code,
              textDirection: ui.TextDirection.ltr,
              style: TextStyle(
                fontSize: 28,
                height: 1.15,
                fontWeight: FontWeight.w700,
                letterSpacing: 6,
                color: AppColors.textHi,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: accent,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'wa.pair_waiting'.tr(),
                style: AppType.muted().copyWith(fontSize: 11),
              ),
              const SizedBox(width: 10),
              TextButton(
                onPressed: () {
                  _stopQrPolling();
                  setState(() {
                    _pairCode = null;
                    _busy = false;
                  });
                },
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 28),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: Text(
                  'common.cancel'.tr(),
                  style: AppType.pillBold(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _actionsBar(Color accent) {
    final connected = _status?.connected == true;
    // عند الفصل: زر واحد "اتصال" — يجرّب reconnect صامتاً ثم start-session
    // + polling للـQR. مطابق v1 web (طلب المستخدم 2026-07-12: زر إعادة
    // اتصال منفصل بلا جلسة سابقة كان يربك المستخدم).
    if (!connected) {
      final labelKey = _busy
          ? 'wa.connecting'
          : (_qrData != null ? 'wa.waiting_scan' : 'wa.connect_btn');
      return _btn(
        icon: _busy ? LucideIcons.loader : LucideIcons.qrCode,
        label: labelKey.tr(),
        color: accent,
        onTap: _busy ? null : _connect,
      );
    }
    // عند الاتصال: قطع + إعادة تهيئة كاملة
    return Row(
      children: [
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
            color: AppColors.warning,
            onTap: _busy ? null : _softReset,
          ),
        ),
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
              color: disabled ? AppColors.border : color.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: disabled ? AppColors.textLow : color),
              const SizedBox(width: 5),
              Text(
                label,
                style: AppType.bodyBold(color: disabled ? AppColors.textLow : color),
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
          Divider(color: AppColors.borderSoft, height: 16),
          _toggle(
            label: 'wa.welcome_msg'.tr(),
            value: f.welcomeMessage,
            enabled: masterOn,
            onChanged: (v) => _updateFeatures(f.copyWith(welcomeMessage: v)),
          ),
          _toggle(
            label: 'wa.activation_notif'.tr(),
            value: f.sendOnActivation,
            enabled: masterOn,
            onChanged: (v) => _updateFeatures(f.copyWith(sendOnActivation: v)),
          ),
          _toggle(
            label: 'wa.extend_notif'.tr(),
            value: f.sendOnExtension,
            enabled: masterOn,
            onChanged: (v) => _updateFeatures(f.copyWith(sendOnExtension: v)),
          ),
          _toggle(
            label: 'wa.near_expiry_notif'.tr(),
            value: f.expiryReminder,
            enabled: masterOn,
            onChanged: (v) => _updateFeatures(f.copyWith(expiryReminder: v)),
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
      activeThumbColor: const Color(0xFF25D366),
      title: Text(
        label,
        style:
            AppType.label(color: enabled ? AppColors.textHi : AppColors.textLow)
                .copyWith(fontSize: 12.5, fontWeight: FontWeight.w700),
      ),
      value: enabled ? value : false,
      onChanged: enabled ? onChanged : null,
    );
  }

  Widget _manualModeCard(Color accent) {
    final purple = AppColors.brandAccent;
    return ValueListenableBuilder<bool>(
      valueListenable: ManualWaPrefs.enabled,
      builder: (context, isManual, _) {
        return Material(
          // 2026-08-26: خلفيّة بنفسجيّة خفيفة عندما مفعّل — يبرز بصريّاً
          // لأنه مسار "protected" مختلف عن الافتراضيّ.
          color: isManual ? purple.withValues(alpha: 0.06) : AppColors.surface,
          borderRadius: BorderRadius.circular(R.lg),
          clipBehavior: Clip.antiAlias,
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(R.lg),
              border: Border.all(
                color: isManual
                    ? purple.withValues(alpha: 0.35)
                    : AppColors.border,
                width: isManual ? 1 : 0.5,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: purple.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(R.chip),
                      ),
                      alignment: Alignment.center,
                      child: Icon(LucideIcons.shieldCheck,
                          color: purple, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'الوضع اليدوي للواتساب',
                            style: AppType.buttonBold(),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isManual
                                ? 'مفعّل — يفتح واتسابك'
                                : 'مطفأ — الإرسال تلقائي',
                            style: AppType.pillBold(color: isManual ? purple : AppColors.textMid),
                          ),
                        ],
                      ),
                    ),
                    Switch.adaptive(
                      value: isManual,
                      onChanged: (v) => ManualWaPrefs.setEnabled(v),
                      activeThumbColor: purple,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  isManual
                      ? '✅ بعد كل عمليّة (تسديد/تفعيل/تمديد/تذكير/QR/إرسال معلومات) تفتح نافذة معاينة الرسالة → تضغط "افتح واتسابي" → واتسابك يفتح مع النصّ جاهز → تضغط إرسال. يشتغل حتى لو WA السيرفر مقطوع.'
                      : 'الإرسالات تمرّ عبر جلسة WA السيرفر تلقائياً. لو حصل ban/تعليق للجلسة أو تخاف من مخاطر WA على السيرفر، فعّل الوضع اليدوي.',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textMid,
                    height: 1.7,
                  ),
                ),
              ],
            ),
          ),
        );
      },
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
              Icon(LucideIcons.chevronLeft, size: 16, color: AppColors.textLow),
            ],
          ),
        ),
      ),
    );
  }
}
