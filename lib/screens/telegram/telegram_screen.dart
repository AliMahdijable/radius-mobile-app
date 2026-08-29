import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/telegram_api.dart';
import '../../core/util/clipboard_helper.dart';
import '../../services/auth_storage.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import 'sheets/telegram_bindings_sheet.dart';
import 'sheets/telegram_broadcast_sheet.dart';
import 'sheets/telegram_bulk_links_sheet.dart';
import 'sheets/telegram_link_generator_sheet.dart';

/// TelegramScreen — 2026-08-26. نقل من client-v2 web للـmobile-app-v2.
///
/// **حالتان**:
/// 1. غير مربوط → SetupCard (steps guide + token entry + connect)
/// 2. مربوط → StatusCard (bot info + stats) + Actions Grid + Disconnect
///
/// **الوظائف الكاملة كما في الويب**:
/// - ربط البوت (bot token من @BotFather)
/// - ربط مشترك (deep link generator + share via WA/copy)
/// - بث جماعي لروابط الربط (send links via WA to all unbound)
/// - المرتبطون (list + search + unbind + pagination)
/// - إرسال عام (test broadcast to all bound)
/// - فصل البوت
///
/// **channel routing تلقائي** بعد الربط — كل عمليّة إرسال (تفعيل، تسديد،
/// تمديد، تذكير) من الموبايل تُوجَّه TG-first للمشتركين المربوطين. لا تعديل
/// في الموبايل — backend يقرّر عبر channelRouter.
class TelegramScreen extends StatefulWidget {
  const TelegramScreen({super.key});

  @override
  State<TelegramScreen> createState() => _TelegramScreenState();
}

class _TelegramScreenState extends State<TelegramScreen> {
  bool _loading = true;
  TelegramStatus? _status;
  String? _adminId;
  String? _adminUsername;

  static const _tgBlue = Color(0xFF229ED9);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    _adminId = await AuthStorage.readAdminId();
    _adminUsername = await AuthStorage.readAdminUsername();
    if (_adminId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final s = await TelegramApi.getStatus(_adminId!);
    if (!mounted) return;
    setState(() {
      _status = s;
      _loading = false;
    });
  }

  Future<void> _disconnect() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('فصل البوت',
            style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w800)),
        content: const Text(
            'سيتوقّف كل إرسال تلغرام. المشتركون المربوطون يبقون في قاعدة البيانات — يمكن إعادة الربط لاحقاً بنفس التوكن.',
            style: TextStyle(fontFamily: 'Cairo', height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('فصل',
                style: TextStyle(
                    fontFamily: 'Cairo', fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final done = await TelegramApi.disconnectBot(_adminId!);
    if (!mounted) return;
    if (done) {
      _snack('تمّ فصل البوت');
      _load();
    } else {
      _snack('فشل الفصل', error: true);
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontFamily: 'Cairo')),
      backgroundColor: error ? AppColors.error : AppColors.brand,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text(
          'تلغرام',
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        iconTheme: IconThemeData(color: AppColors.textHi),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _adminId == null
                ? _authErrorState()
                : RefreshIndicator(
                    onRefresh: _load,
                    color: _tgBlue,
                    child: ListView(
                      padding: EdgeInsets.only(
                          bottom: MediaQuery.paddingOf(context).bottom + 32),
                      children: [
                        if (_status?.connected == true)
                          ..._connectedContent()
                        else
                          ..._setupContent(),
                      ],
                    ),
                  ),
      ),
    );
  }

  // ─── SETUP (not connected) ─────────────────────────────────────

  List<Widget> _setupContent() {
    return [
      _compactHeader(
        icon: LucideIcons.send,
        title: 'ابدأ بربط البوت',
        subtitle: 'أنشئ بوت من @BotFather وربطه هنا خلال دقيقتين.',
        color: _tgBlue,
      ),
      const SizedBox(height: 12),
      _StepsCard(tgBlue: _tgBlue),
      const SizedBox(height: 12),
      _TokenEntryCard(
        adminId: _adminId!,
        adminUsername: _adminUsername ?? '',
        onConnected: _load,
        tgBlue: _tgBlue,
      ),
      if (_status?.exists == true && (_status?.lastError ?? '').isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.dangerSoftBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: AppColors.dangerSoftBorder,
                width: 0.5,
              ),
            ),
            child: Row(
              children: [
                Icon(LucideIcons.circleAlert, size: 16, color: AppColors.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'آخر محاولة فشلت: ${_status!.lastError}',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.error,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
    ];
  }

  // ─── CONNECTED ────────────────────────────────────────────────

  List<Widget> _connectedContent() {
    final s = _status!;
    return [
      _compactHeader(
        icon: LucideIcons.circleCheck,
        title: 'متّصل بـ@${s.botUsername ?? '?'}',
        subtitle: s.botFirstName ?? 'بوت التلغرام يعمل',
        color: AppColors.success,
      ),
      _statsRow(s),
      const SizedBox(height: 12),
      _actionsGrid(),
      const SizedBox(height: 16),
      _disconnectRow(),
    ];
  }

  Widget _statsRow(TelegramStatus s) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          _statCard('مرتبطون', s.totalBindings, _tgBlue),
          const SizedBox(width: 8),
          _statCard('نشطون', s.activeBindings, AppColors.success),
          const SizedBox(width: 8),
          _statCard('حظر', s.blockedBindings, AppColors.error),
        ],
      ),
    );
  }

  Widget _statCard(String label, int value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border, width: 0.5),
        ),
        child: Column(
          children: [
            Text(
              '$value',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: color,
                fontFeatures: const [FontFeature.tabularFigures()],
                letterSpacing: -0.4,
                height: 1,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.textMid,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionsGrid() {
    final actions = <_TgAction>[
      _TgAction(
        icon: LucideIcons.link,
        color: _tgBlue,
        title: 'ربط مشترك',
        subtitle: 'أنشئ رابط ربط وأرسله عبر واتساب',
        onTap: () => showTelegramLinkGeneratorSheet(context,
            adminId: _adminId!, onDone: _load),
      ),
      _TgAction(
        icon: LucideIcons.megaphone,
        color: AppColors.warning,
        title: 'بث روابط جماعي',
        subtitle: 'أرسل رابط الربط لكل مشترك عبر واتساب',
        onTap: () => showTelegramBulkLinksSheet(context,
            adminId: _adminId!, onDone: _load),
      ),
      _TgAction(
        icon: LucideIcons.users,
        color: AppColors.success,
        title: 'المرتبطون',
        subtitle: 'قائمة المشتركين المربوطين + بحث',
        onTap: () => showTelegramBindingsSheet(context,
            adminId: _adminId!, onChanged: _load),
      ),
      _TgAction(
        icon: LucideIcons.messageCircle,
        color: AppColors.brandAccent,
        title: 'إرسال عام',
        subtitle: 'ابعث رسالة لكل المرتبطين',
        onTap: () => showTelegramBroadcastSheet(context, adminId: _adminId!),
      ),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        children: [
          for (final a in actions) ...[
            _actionTile(a),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  Widget _actionTile(_TgAction a) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: a.onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border, width: 0.5),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: a.color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(11),
                ),
                alignment: Alignment.center,
                child: Icon(a.icon, color: a.color, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      a.title,
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textHi,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      a.subtitle,
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textMid,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(LucideIcons.chevronLeft, size: 18, color: AppColors.textLow),
            ],
          ),
        ),
      ),
    );
  }

  Widget _disconnectRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: SizedBox(
        width: double.infinity,
        height: 46,
        child: OutlinedButton.icon(
          onPressed: _disconnect,
          icon: Icon(LucideIcons.powerOff, size: 16, color: AppColors.error),
          label: const Text(
            'فصل البوت',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.error,
            side: BorderSide(color: AppColors.dangerSoftBorder, width: 1),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
    );
  }

  Widget _compactHeader({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(
          bottom: BorderSide(color: AppColors.border, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textHi,
                    height: 1.15,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMid,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _authErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text('تعذّر قراءة هويّة الحساب. سجّل دخول من جديد.',
            style: TextStyle(
              fontFamily: 'Cairo',
              color: AppColors.textMid,
            )),
      ),
    );
  }
}

class _TgAction {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _TgAction({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
}

// ─── Setup helpers ────────────────────────────────────────────

class _StepsCard extends StatelessWidget {
  const _StepsCard({required this.tgBlue});
  final Color tgBlue;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('الخطوات (دقيقتان)',
              style: AppType.label(color: AppColors.textHi)
                  .copyWith(fontSize: 13, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          _step(1, 'افتح ', botLink: '@BotFather', suffix: ' في تلغرام'),
          _step(2, 'أرسل الأمر ', code: '/newbot', suffix: ' واتّبع التعليمات'),
          _step(3, 'اختر اسم بوت + username ينتهي بـ ', code: 'bot'),
          _step(4, 'انسخ التوكن الذي يبدأ بـ ', code: '123456789:AAE...'),
          _step(5, 'الصق التوكن أدناه واضغط ', codeBold: 'ربط البوت'),
        ],
      ),
    );
  }

  Widget _step(int n, String prefix,
      {String? code, String? codeBold, String? botLink, String? suffix}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: tgBlue.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text('$n',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: tgBlue,
                  fontFeatures: const [FontFeature.tabularFigures()],
                )),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(prefix,
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textMid,
                      height: 1.5,
                    )),
                if (botLink != null)
                  InkWell(
                    onTap: () async {
                      final url = Uri.parse('https://t.me/BotFather');
                      // ignore: unawaited_futures
                      launchUrl(url, mode: LaunchMode.externalApplication);
                    },
                    child: Text(botLink,
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: tgBlue,
                          decoration: TextDecoration.underline,
                        )),
                  ),
                if (code != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceInput,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(code,
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textHi,
                        )),
                  ),
                if (codeBold != null)
                  Text('"$codeBold"',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textHi,
                      )),
                if (suffix != null)
                  Text(suffix,
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textMid,
                      )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TokenEntryCard extends StatefulWidget {
  const _TokenEntryCard({
    required this.adminId,
    required this.adminUsername,
    required this.onConnected,
    required this.tgBlue,
  });
  final String adminId;
  final String adminUsername;
  final VoidCallback onConnected;
  final Color tgBlue;

  @override
  State<_TokenEntryCard> createState() => _TokenEntryCardState();
}

class _TokenEntryCardState extends State<_TokenEntryCard> {
  final _ctrl = TextEditingController();
  bool _busy = false;
  String? _err;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData('text/plain');
    if (data?.text?.isNotEmpty == true && mounted) {
      setState(() {
        _ctrl.text = data!.text!.trim();
        _err = null;
      });
    }
  }

  Future<void> _connect() async {
    final token = _ctrl.text.trim();
    if (token.isEmpty) {
      setState(() => _err = 'أدخل التوكن أوّلاً');
      return;
    }
    setState(() {
      _busy = true;
      _err = null;
    });
    final res = await TelegramApi.connectBot(
      adminId: widget.adminId,
      adminUsername: widget.adminUsername,
      botToken: token,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (res.ok) {
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('تمّ الربط بـ@${res.botUsername ?? "?"}',
            style: const TextStyle(fontFamily: 'Cairo')),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
      widget.onConnected();
    } else {
      setState(() => _err = res.message ?? 'فشل الربط');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('توكن البوت',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.textLow,
                letterSpacing: 0.4,
              )),
          const SizedBox(height: 6),
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: AppColors.surfaceInput,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _err != null ? AppColors.error : AppColors.border,
                width: _err != null ? 1 : 0.5,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    obscureText: false,
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      isCollapsed: true,
                      hintText: '123456789:AAE...',
                      hintStyle: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12,
                        color: AppColors.textLow,
                      ),
                    ),
                    onChanged: (_) {
                      if (_err != null) setState(() => _err = null);
                    },
                  ),
                ),
                IconButton(
                  icon: Icon(LucideIcons.clipboardPaste,
                      size: 18, color: widget.tgBlue),
                  onPressed: _pasteFromClipboard,
                  tooltip: 'لصق من الحافظة',
                  splashRadius: 18,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
              ],
            ),
          ),
          if (_err != null) ...[
            const SizedBox(height: 6),
            Text(_err!,
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.error,
                )),
          ],
          const SizedBox(height: 12),
          SizedBox(
            height: 46,
            child: FilledButton.icon(
              onPressed: _busy ? null : _connect,
              icon: _busy
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 1.5, color: Colors.white))
                  : const Icon(LucideIcons.link, size: 16),
              label: const Text('ربط البوت',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  )),
              style: FilledButton.styleFrom(
                backgroundColor: widget.tgBlue,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(LucideIcons.shieldCheck, size: 12, color: AppColors.textLow),
              const SizedBox(width: 5),
              Text('التوكن يُحفظ مشفَّراً — لا يظهر مجدَّداً.',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 10.5,
                    color: AppColors.textLow,
                    fontWeight: FontWeight.w600,
                  )),
            ],
          ),
        ],
      ),
    );
  }
}

// keep imports clean
// ignore: unused_element
void _unused() {
  // ignore: unused_local_variable
  final _ = Sp.md;
}
