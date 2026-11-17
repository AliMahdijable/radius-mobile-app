import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/tg_account_api.dart';
import '../../../core/util/bidi.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/design_sheet.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';

/// «طريقة الإرسال بتلغرام» (١٤ نوفمبر ٢٠٢٦ — كالويب): البوت / حسابي، وربط حساب الوكيل برقمه والرمز أو برمز QR. لا تظهر لحسابٍ لم
/// تُفتح له الميزة. [onStatus] يُبلغ الشاشة بالحال (على «حسابي» تُخفى أقسام البوت كالويب).
class TgAccountCard extends StatefulWidget {
  const TgAccountCard({super.key, required this.adminId, this.onStatus, this.botConnected, this.botUsername});
  final String adminId;
  final ValueChanged<TgAccountStatus?>? onStatus;

  /// حال البوت من الشاشة (TelegramStatus) — يُعرض في خيار «البوت» (مربوط @… / غير مربوط). null = لم يُعرف بعد.
  final bool? botConnected;
  final String? botUsername;

  @override
  State<TgAccountCard> createState() => _TgAccountCardState();
}

class _TgAccountCardState extends State<TgAccountCard> {
  TgAccountStatus? _s;
  bool _loaded = false;
  bool _busy = false;

  static const _tgBlue = AppColors.channelTelegram;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await TgAccountApi.status(widget.adminId);
    if (!mounted) return;
    setState(() {
      _s = s;
      _loaded = true;
    });
    widget.onStatus?.call(s);
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontFamily: AppType.family)),
      backgroundColor: error ? AppColors.error : AppColors.brand,
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _setMode(String mode) async {
    final s = _s;
    if (s == null || _busy || s.mode == mode) return;
    if (mode == 'account' && !s.linked) {
      await _link();
      return;
    }
    setState(() => _busy = true);
    final r = await TgAccountApi.setMode(widget.adminId, mode);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!r.ok) {
      _snack(r.message ?? 'تعذّر تغيير الطريقة', error: true);
      return;
    }
    await _load();
  }

  Future<void> _link() async {
    final linked = await showAppSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: AppColors.scrim,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => TgLinkSheet(adminId: widget.adminId),
    );
    if (linked == true) {
      _snack('رُبط حسابك على تلغرام');
      await _load();
      // ١٧ نوفمبر (المالك: «يفهم الوكيل انه رابط بوت او رقم تلفون»): الحساب المربوط للتوّ يصير الطريقة المستعمَلة.
      if (mounted && _s != null && _s!.linked && _s!.mode != 'account') await _setMode('account');
    }
  }

  Future<void> _logout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('فصل حسابك عن تلغرام', style: TextStyle(fontFamily: AppType.family, fontWeight: FontWeight.w700)),
        content: const Text('تُحذف الجلسة من خادمنا ويخرج الجهاز من قائمة أجهزتك في تلغرام، وتعود الطريقة إلى «البوت».',
            style: TextStyle(fontFamily: AppType.family, height: 1.5)),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('إلغاء')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.errorFill),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('فصل'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    final r = await TgAccountApi.logout(widget.adminId);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!r.ok) {
      _snack(r.message ?? 'تعذّر الفصل', error: true);
      return;
    }
    _snack('فُصل حسابك');
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep
    final s = _s;
    if (!_loaded || s == null || !s.enabled) return const SizedBox.shrink();
    final limitedNow = s.limitedUntil != null && s.limitedUntil!.isAfter(DateTime.now());
    final notConfigured = s.configured == false;
    final accountOk = s.linked && s.status != 'disconnected';
    final bot = widget.botConnected;
    final botName = (widget.botUsername ?? '').trim();
    final botMode = s.mode != 'account';
    // ١٧ نوفمبر (المالك: «تصميم قسم التليكرام مربك… يفهم الوكيل انه رابط بوت او رقم تلفون»): خياران بحاليهما — المحدَّد هو
    // المستعمَل، وكلٌّ يقول أهو مربوط وبماذا. كان: زرّان ثمّ سطر الحساب تحتهما ولو كانت الطريقة «البوت» غير المربوط.
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Container(
        key: const ValueKey('tg-account-card'),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(R.lg),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              const Icon(LucideIcons.send, size: 17, color: _tgBlue),
              const SizedBox(width: Sp.sm),
              Expanded(child: Text('طريقة الإرسال بتلغرام', style: AppType.label(color: AppColors.textHi))),
              if (_busy) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            ]),
            const SizedBox(height: 4),
            Text('المحدَّدة هي التي تخرج منها رسائل تلغرام لمشتركيك.', style: AppType.muted()),
            const SizedBox(height: Sp.md),
            _methodTile(
              key: const ValueKey('tg-method-bot'),
              selected: botMode,
              icon: LucideIcons.bot,
              title: 'البوت',
              hint: 'يصل لمن ضغط رابط بوتك من مشتركيك.',
              status: bot == null
                  ? null
                  : bot
                      ? _state(ok: true, label: 'مربوط', detail: botName.isEmpty ? null : '@$botName')
                      : _state(ok: false, label: 'غير مربوط', detail: botMode ? 'اربطه من «ربط البوت» أدناه' : null),
              footer: bot == true && !botMode
                  ? Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton.icon(
                        key: const ValueKey('tg-use-bot'),
                        onPressed: _busy ? null : () => _setMode('bot'),
                        icon: const Icon(LucideIcons.circleCheck, size: 15),
                        label: const Text('استعمل البوت'),
                      ),
                    )
                  : null,
              onTap: () => _setMode('bot'),
            ),
            const SizedBox(height: Sp.sm),
            _methodTile(
              key: const ValueKey('tg-method-account'),
              selected: !botMode,
              icon: LucideIcons.smartphone,
              title: 'حسابي — برقم هاتفي',
              hint: 'يصل من حسابك لكلّ مشتركٍ رقمه على تلغرام، ومن ليس عليه تصله بالواتساب.',
              status: accountOk
                  ? _state(ok: true, label: 'مربوط', detail: s.user?.display.isNotEmpty == true ? s.user!.display : null)
                  : s.linked
                      ? _state(ok: false, label: 'خرج من الجهاز', detail: 'أعد الربط')
                      : _state(ok: false, label: 'غير مربوط'),
              footer: accountOk
                  // ٣٢٠: العدّاد سطرٌ وحده والزرّان تحته (ينزلان سطراً إن ضاق) — كان العدّاد بجانبهما فيُعصر حرفاً حرفاً.
                  ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      if (s.todayNew != null && s.dailyNewCap != null)
                        Text('اليوم ${s.todayNew} من ${s.dailyNewCap} جديداً', style: AppType.micro(color: AppColors.textMid)),
                      Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, children: [
                        if (botMode)
                          TextButton.icon(
                            key: const ValueKey('tg-use-account'),
                            onPressed: _busy ? null : () => _setMode('account'),
                            icon: const Icon(LucideIcons.circleCheck, size: 15),
                            label: const Text('استعمل حسابي'),
                          ),
                        TextButton.icon(
                          onPressed: _busy ? null : _logout,
                          icon: const Icon(LucideIcons.unlink, size: 15),
                          label: const Text('فصل'),
                        ),
                      ]),
                    ])
                  : SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        key: const ValueKey('tg-account-link'),
                        style: FilledButton.styleFrom(backgroundColor: _tgBlue),
                        onPressed: _busy || !s.serviceUp || notConfigured ? null : _link,
                        icon: const Icon(LucideIcons.link, size: 16),
                        label: const Text('ربط حسابي'),
                      ),
                    ),
              onTap: () => _setMode('account'),
            ),
            if (!s.serviceUp) ...[
              const SizedBox(height: Sp.sm),
              _warn('خدمة تلغرام غير متاحة الآن — حاول بعد قليل'),
            ] else if (notConfigured) ...[
              const SizedBox(height: Sp.sm),
              _warn('تلغرام بالحساب غير مهيّأ على الخادم بعد — يضبطه المالك'),
            ],
            if (limitedNow) ...[
              const SizedBox(height: Sp.sm),
              _warn('تلغرام قيّد حسابك مؤقّتاً عن مراسلة غير المعارف — حتى ${_hm(s.limitedUntil!)}'),
            ],
          ],
        ),
      ),
    );
  }

  /// خيار طريقة: أيقونة + اسم + علامة «المستعمَلة» + سطر ما يفعل + حاله (+ تذييل). النقر يختاره (الحساب غير المربوط ⇒ يُربط أوّلاً).
  Widget _methodTile({
    required Key key,
    required bool selected,
    required IconData icon,
    required String title,
    required String hint,
    Widget? status,
    Widget? footer,
    required VoidCallback onTap,
  }) =>
      Material(
        key: key,
        color: selected ? _tgBlue.withValues(alpha: 0.08) : AppColors.surfaceSunken,
        borderRadius: BorderRadius.circular(R.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(R.md),
          onTap: _busy || selected ? null : onTap,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(R.md),
              border: Border.all(color: selected ? _tgBlue : AppColors.border, width: selected ? 1.5 : 1),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(icon, size: 18, color: selected ? _tgBlue : AppColors.textMid),
                const SizedBox(width: Sp.sm),
                Expanded(child: Text(title, style: AppType.bodyStrong(color: AppColors.textHi))),
                if (selected)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('المستعمَلة', style: AppType.micro(color: _tgBlue)),
                    const SizedBox(width: 4),
                    const Icon(LucideIcons.circleCheck, size: 17, color: _tgBlue),
                  ])
                else
                  Icon(LucideIcons.circle, size: 17, color: AppColors.textLow),
              ]),
              const SizedBox(height: 4),
              Text(hint, style: AppType.micro(color: AppColors.textMid)),
              if (status != null) ...[const SizedBox(height: Sp.sm), status],
              if (footer != null) ...[const SizedBox(height: Sp.sm), footer],
            ]),
          ),
        ),
      );

  /// «مربوط» (أخضر) / «غير مربوط» (تنبيه) وبجانبه ما رُبط (الاسم واليوزر / @البوت) أو ما يُفعل.
  Widget _state({required bool ok, required String label, String? detail}) => Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: ok ? AppColors.successSoftBg : AppColors.warningSoftBg,
            borderRadius: BorderRadius.circular(R.sm),
            border: Border.all(color: ok ? AppColors.successSoftBorder : AppColors.warningSoftBorder),
          ),
          child: Text(label, style: AppType.micro(color: ok ? AppColors.success : AppColors.warningOnSoft)),
        ),
        if (detail != null) ...[
          const SizedBox(width: Sp.sm),
          Expanded(
            child: Text(iso(detail),
                maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(color: AppColors.textHi)),
          ),
        ],
      ]);

  Widget _warn(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.warningSoftBg,
          borderRadius: BorderRadius.circular(R.sm),
          border: Border.all(color: AppColors.warningSoftBorder),
        ),
        child: Text(text, style: AppType.micro(color: AppColors.warningOnSoft)),
      );

  static String _hm(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.hour)}:${two(d.minute)}';
  }
}

/// ورقة الربط: «برقم الهاتف» (الافتراض على الهاتف) أو «رمز QR» (الافتراض على الشاشة العريضة)، ثمّ كلمة التحقّق بخطوتين إن طلبها.
/// تُرجع true حين يُربط. الإغلاق قبل الربط يلغي المحاولة بالخادم.
class TgLinkSheet extends StatefulWidget {
  const TgLinkSheet({super.key, required this.adminId});
  final String adminId;

  @override
  State<TgLinkSheet> createState() => _TgLinkSheetState();
}

enum _Stage { phone, code, password }

class _TgLinkSheetState extends State<TgLinkSheet> {
  bool? _qrTab;
  _Stage _stage = _Stage.phone;
  String? _loginId;
  String? _hint;
  String? _error;
  bool _busy = false;
  bool _done = false;
  final _phone = TextEditingController();
  final _code = TextEditingController();
  final _pw = TextEditingController();

  // رمز QR
  Timer? _poll;
  String _qrState = 'starting';
  Uint8List? _qrPng;

  @override
  void dispose() {
    _poll?.cancel();
    final id = _loginId;
    if (!_done && id != null) unawaited(TgAccountApi.cancel(widget.adminId, id));
    _phone.dispose();
    _code.dispose();
    _pw.dispose();
    super.dispose();
  }

  bool get _qr => _qrTab ?? (MediaQuery.sizeOf(context).width >= 700);

  void _switchTab(bool qr) {
    if (_busy || qr == _qr) return;
    _poll?.cancel();
    final id = _loginId;
    if (id != null) unawaited(TgAccountApi.cancel(widget.adminId, id));
    setState(() {
      _qrTab = qr;
      _loginId = null;
      _stage = _Stage.phone;
      _error = null;
      _qrPng = null;
      _qrState = 'starting';
    });
    if (qr) _startQr();
  }

  Future<void> _startQr() async {
    setState(() {
      _busy = true;
      _error = null;
      _qrState = 'starting';
      _qrPng = null;
    });
    final r = await TgAccountApi.loginQr(widget.adminId);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!r.ok) {
      setState(() => _error = r.message);
      return;
    }
    _loginId = r.data['login_id']?.toString();
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 2), (_) => _pollOnce());
    unawaited(_pollOnce());
  }

  bool _polling = false;
  Future<void> _pollOnce() async {
    final id = _loginId;
    if (id == null || _polling || _done) return;
    _polling = true;
    final r = await TgAccountApi.pollQr(widget.adminId, id);
    _polling = false;
    if (!mounted || _done) return;
    if (!r.ok) {
      _poll?.cancel();
      setState(() => _error = r.message);
      return;
    }
    final st = r.data['state']?.toString() ?? 'starting';
    if (st == 'linked') {
      _finish();
      return;
    }
    if (st == 'password') {
      _poll?.cancel();
      setState(() {
        _stage = _Stage.password;
        _hint = r.data['hint']?.toString();
      });
      return;
    }
    if (st == 'expired') _poll?.cancel();
    setState(() {
      _qrState = st;
      final png = TgAccountApi.pngOf(r.data['qr_png']);
      if (png != null) _qrPng = png;
    });
  }

  void _finish() {
    _done = true;
    _poll?.cancel();
    Navigator.of(context).pop(true);
  }

  Future<void> _sendCode() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await TgAccountApi.loginPhone(widget.adminId, _phone.text.trim());
    if (!mounted) return;
    setState(() => _busy = false);
    if (!r.ok) {
      setState(() => _error = r.message);
      return;
    }
    setState(() {
      _loginId = r.data['login_id']?.toString();
      _stage = _Stage.code;
    });
  }

  Future<void> _sendCodeValue() async {
    final id = _loginId;
    if (id == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await TgAccountApi.loginCode(widget.adminId, id, _code.text.trim());
    if (!mounted) return;
    setState(() => _busy = false);
    if (!r.ok) {
      setState(() => _error = r.message);
      return;
    }
    if (r.data['need_password'] == true) {
      setState(() {
        _stage = _Stage.password;
        _hint = r.data['hint']?.toString();
      });
      return;
    }
    _finish();
  }

  Future<void> _sendPassword() async {
    final id = _loginId;
    if (id == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await TgAccountApi.loginPassword(widget.adminId, id, _pw.text);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!r.ok) {
      setState(() => _error = r.message);
      return;
    }
    _finish();
  }

  InputDecoration _deco(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: AppType.input(color: AppColors.textHint),
        filled: true,
        fillColor: AppColors.surfaceInput,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(R.md), borderSide: BorderSide(color: AppColors.border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(R.md), borderSide: BorderSide(color: AppColors.border)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(R.md), borderSide: const BorderSide(color: AppColors.channelTelegram, width: 1.5)),
      );

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep
    final qr = _qr;
    if (qr && _loginId == null && !_busy && _error == null && _stage == _Stage.phone) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _loginId == null && !_busy) _startQr();
      });
    }
    final passwordStage = _stage == _Stage.password;
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.send,
        title: 'ربط حسابك على تلغرام',
        subtitle: 'ترسل رسائل تلغرام من حسابك بدل البوت',
        onClose: () => Navigator.of(context).pop(false),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!passwordStage) ...[
            Row(children: [
              Expanded(child: _tab('برقم الهاتف', !qr, () => _switchTab(false))),
              const SizedBox(width: Sp.sm),
              Expanded(child: _tab('رمز QR', qr, () => _switchTab(true))),
            ]),
            const SizedBox(height: Sp.md),
          ],
          if (passwordStage) ...[
            Text('حسابك محميّ بكلمة تحقّقٍ بخطوتين — اكتبها هنا.', style: AppType.muted()),
            if ((_hint ?? '').isNotEmpty) Text('تلميحها: $_hint', style: AppType.micro(color: AppColors.textMid)),
            const SizedBox(height: Sp.sm),
            TextField(
              key: const ValueKey('tg-link-password'),
              controller: _pw,
              obscureText: true,
              autofocus: true,
              decoration: _deco('كلمة التحقّق'),
            ),
          ] else if (qr) ...[
            Text('افتح تلغرام بهاتفك: الإعدادات ← الأجهزة ← ربط جهاز، وامسح الرمز.', style: AppType.muted()),
            const SizedBox(height: Sp.md),
            Center(
              child: Container(
                width: 220,
                height: 220,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(R.md)),
                child: _qrPng != null && _qrState == 'qr'
                    ? Image.memory(_qrPng!, key: const ValueKey('tg-link-qr'), fit: BoxFit.contain)
                    : _qrState == 'expired'
                        ? Center(
                            child: TextButton(onPressed: _startQr, child: const Text('انتهى الرمز — رمزٌ جديد')))
                        : const Center(child: CircularProgressIndicator()),
              ),
            ),
          ] else if (_stage == _Stage.phone) ...[
            Text('رقم حسابك على تلغرام — يصلك رمزٌ في تطبيق تلغرام.', style: AppType.muted()),
            const SizedBox(height: Sp.sm),
            TextField(
              key: const ValueKey('tg-link-phone'),
              controller: _phone,
              keyboardType: TextInputType.phone,
              textDirection: TextDirection.ltr,
              autofocus: true,
              decoration: _deco('07701234567'),
            ),
          ] else ...[
            Text('اكتب الرمز الذي وصلك في تلغرام.', style: AppType.muted()),
            const SizedBox(height: Sp.sm),
            TextField(
              key: const ValueKey('tg-link-code'),
              controller: _code,
              keyboardType: TextInputType.number,
              textDirection: TextDirection.ltr,
              autofocus: true,
              decoration: _deco('12345'),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: Sp.sm),
            Text(_error!, style: AppType.micro(color: AppColors.error)),
          ],
        ],
      ),
      footer: qr && !passwordStage
          ? null
          : SheetFooterBar(
              label: passwordStage || _stage == _Stage.code ? 'دخول' : 'أرسل الرمز',
              icon: LucideIcons.check,
              busy: _busy,
              enabled: !_busy,
              onPressed: passwordStage
                  ? _sendPassword
                  : _stage == _Stage.code
                      ? _sendCodeValue
                      : _sendCode,
            ),
    );
  }

  Widget _tab(String label, bool on, VoidCallback onTap) => Material(
        color: on ? AppColors.channelTelegram.withValues(alpha: 0.12) : AppColors.surfaceSunken,
        borderRadius: BorderRadius.circular(R.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(R.md),
          onTap: onTap,
          child: Container(
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(R.md),
              border: Border.all(color: on ? AppColors.channelTelegram : AppColors.border),
            ),
            child: Text(label, style: AppType.label(color: on ? AppColors.channelTelegram : AppColors.textMid)),
          ),
        ),
      );
}
