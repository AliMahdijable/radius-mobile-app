import 'dart:async';

// `hide TextDirection`: الحزمة تصدّر نوع intl الذي يحجب نوع dart:ui.
import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/network_devices_api.dart';
import '../../core/platform/app_platform.dart';
import '../../core/util/format.dart';
import '../../core/widgets/app_sheet.dart';
import '../../core/widgets/design_sheet.dart';
import '../../core/widgets/permission_locked.dart';
import '../../core/widgets/voice_search_button.dart';
import '../../core/widgets/windows_voice_button.dart';
import '../../models/network_device.dart';
import '../../models/subscriber.dart';
import '../../services/agent_net_presence.dart';
import '../../services/ai_assistant_state.dart';
import '../../services/voice/voice_command.dart';
import '../../services/voice/voice_resolver.dart';
import '../../services/vpn_now.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../assistant/assistant_sheet.dart';
import '../network_devices/check/devices_check_screen.dart';
import '../network_devices/network_device_details_screen.dart';
import '../subscribers/subscriber_detail_screen.dart';

/// «أمر صوتي» (٧ نوفمبر — المالك: «المساعد الصوتي… وكيل يامره يفعل مشترك يطفي مشترك يفحص جهاز»).
///
/// المايك يسمع بنفسه حين تُفتح، والنصّ يُعدَّل أو يُكتب. الفهم والمطابقة على الجهاز ([VoiceCommand]، [VoiceResolver]) — لا شيء
/// يُرسل لفهمه بنموذج ذكاء. ويندوز يحوّل التسجيل لنص عربي على خادمنا بعد الموافقة، ثم يفهم النص محلياً مثل الهاتف.
/// والنتيجة كرت تأكيد: المشترك (أو الجهاز) بتفاصيله وزرّ العمليّة، والزرّ يفتح **شاشة العمليّة نفسها** بأقفالها
/// (التفعيل بسعره ودفعه، التطفية بتأكيدها) — لا تنفيذ بلا ضغطة الوكيل هناك.
///
/// ٧ نوفمبر (المالك: «لوتخلي الامر الصوتي مجرد نقر والمساعد الذكاء نخلي هو الثانوي»): تُفتح بنقرةٍ من رأس كلّ تبويب، و«المساعد
/// الذكي» صفٌّ ثانويٌّ أسفلها ([_assistantRow]) — قبل الأمر وحين لا يُفهم.
Future<void> showVoiceCommandSheet(BuildContext context) {
  HapticFeedback.selectionClick();
  final root = context;
  return showAppSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.scrim,
    builder: (_) => VoiceCommandSheet(rootContext: root),
  );
}

class VoiceCommandSheet extends StatefulWidget {
  const VoiceCommandSheet({super.key, required this.rootContext, this.autoListen = true});

  /// سياق الغلاف — يبقى حيّاً بعد إغلاق الورقة فتُفتح منه الشاشة التالية.
  final BuildContext rootContext;

  /// يبدأ المايك بنفسه (الاختبار يطفئه).
  final bool autoListen;

  @override
  State<VoiceCommandSheet> createState() => _VoiceCommandSheetState();
}

class _VoiceCommandSheetState extends State<VoiceCommandSheet> {
  final _ctrl = TextEditingController();
  bool _listening = false;
  bool _busy = false;
  int _gen = 0;
  VoiceIntent? _intent;
  VoiceMatches<Subscriber>? _subs;
  VoiceMatches<NetworkDevice>? _devs;
  Subscriber? _sub;
  NetworkDevice? _dev;

  static const _examples = [
    'فعّل علي حسين',
    'طفّي محمد كاظم',
    'سدّد دين أحمد ٢٥ ألف',
    'ضيف دين على زينب ١٠ آلاف',
    'ذكّر علي بالدين',
    'اطبع وصل حسين',
    'افحص سكتر الشمال',
    'فحص شامل',
  ];

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _run(String text) async {
    final t = text.trim();
    if (t.isEmpty) return;
    final gen = ++_gen;
    final intent = VoiceCommand.parse(t);
    setState(() {
      _intent = intent;
      _subs = null;
      _devs = null;
      _sub = null;
      _dev = null;
      _busy = intent.needsTarget;
    });
    if (!intent.needsTarget) return;
    if (intent.action == VoiceAction.checkDevice) {
      final d = await VoiceResolver.devices(intent.query, kind: intent.deviceKind);
      if (!mounted || gen != _gen) return;
      // لا جهاز بهذا الاسم ⇒ لعلّه مشترك («افحص علي») — مرشّحوه للفتح
      VoiceMatches<Subscriber>? s;
      if (d.isEmpty && d.error == null && intent.query.isNotEmpty) s = await VoiceResolver.subscribers(intent.query);
      if (!mounted || gen != _gen) return;
      setState(() {
        _busy = false;
        _devs = d;
        _subs = s;
        if (d.sure) _dev = d.items.first.item;
      });
      return;
    }
    final m = await VoiceResolver.subscribers(intent.query);
    if (!mounted || gen != _gen) return;
    setState(() {
      _busy = false;
      _subs = m;
      if (m.sure) _sub = m.items.first.item;
    });
  }

  // ───────────────────────── التنفيذ (شاشة العمليّة نفسها) ─────────────────────────

  Future<void> _openSubscriber(Subscriber s, VoiceIntent intent) async {
    final root = widget.rootContext;
    final auto = switch (intent.action) {
      VoiceAction.activate => SubscriberAutoAction.activate,
      VoiceAction.disable => SubscriberAutoAction.disable,
      VoiceAction.enable => SubscriberAutoAction.enable,
      VoiceAction.payDebt => SubscriberAutoAction.payDebt,
      VoiceAction.addDebt => SubscriberAutoAction.addDebt,
      VoiceAction.addCredit => SubscriberAutoAction.addCredit,
      VoiceAction.discount => SubscriberAutoAction.discount,
      VoiceAction.debtReminder => SubscriberAutoAction.debtReminder,
      VoiceAction.expiryWarning => SubscriberAutoAction.expiryWarning,
      VoiceAction.sendInfo => SubscriberAutoAction.sendInfo,
      VoiceAction.printReceipt => SubscriberAutoAction.printReceipt,
      VoiceAction.qr => SubscriberAutoAction.qr,
      VoiceAction.statement => SubscriberAutoAction.statement,
      VoiceAction.movements => SubscriberAutoAction.movements,
      VoiceAction.call => SubscriberAutoAction.call,
      VoiceAction.whatsapp => SubscriberAutoAction.whatsapp,
      _ => null,
    };
    Navigator.of(context).pop();
    await Navigator.of(root).push(MaterialPageRoute<void>(
      builder: (_) => SubscriberDetailScreen(
        sub: s,
        autoAction: auto,
        autoAmount: voiceMoneyActions.contains(intent.action) ? intent.amount : null,
        autoFullDebt: intent.action == VoiceAction.payDebt && intent.fullAmount,
      ),
    ));
  }

  Future<void> _openDevice(NetworkDevice d) async {
    final root = widget.rootContext;
    Navigator.of(context).pop();
    await Navigator.of(root).push(MaterialPageRoute<void>(builder: (_) => NetworkDeviceDetailsScreen(device: d)));
  }

  /// الفحص الشامل: عبر الـVPN بوضعه أو وأنت خارج شبكتك ولك طريق؛ خارجها بلا طريق لا فحص (المحلّيّ سيقول «طافي» كذباً).
  Future<void> _checkAll() async {
    final root = widget.rootContext;
    final messenger = ScaffoldMessenger.maybeOf(root);
    setState(() => _busy = true);
    List<NetworkDevice> devs;
    bool viaVpn;
    try {
      devs = await NetworkDevicesApi.list();
      final r = await VpnNow.route();
      viaVpn = VpnNow.mode.value || (r?.linked == true && !AgentNetPresence.isOn);
    } catch (_) {
      if (mounted) setState(() => _busy = false);
      messenger?.showSnackBar(const SnackBar(content: Text('تعذّر جلب الأجهزة الآن — حاول بعد قليل')));
      return;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (devs.isEmpty) {
      messenger?.showSnackBar(const SnackBar(content: Text('ما عندك أجهزة بقسم الأجهزة')));
      return;
    }
    if (!viaVpn && AgentNetPresence.isOff) {
      messenger?.showSnackBar(const SnackBar(content: Text('خارج شبكتك — اربط VPN حتى تُفحص أجهزتك عن بُعد')));
      return;
    }
    if (!mounted || !root.mounted) return;
    Navigator.of(context).pop();
    await Navigator.of(root).push(MaterialPageRoute<void>(
      builder: (_) => DevicesCheckScreen(devices: devs, viaVpn: viaVpn),
    ));
  }

  // ───────────────────────── الواجهة ─────────────────────────

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.mic,
        title: 'أمر صوتي',
        // قصيرٌ ليُقرأ كاملاً على ٣٢٠ («…بعد تأ…» كان يُبتر).
        subtitle: 'احچي أو اكتب — وتأكّد قبل التنفيذ',
        onClose: () => Navigator.of(context).pop(),
      ),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _input(),
          const SizedBox(height: Sp.md),
          ..._result(),
          // المساعد ثانويّ: قبل الأمر وحين لا يُفهم — لا بجانب كرت تأكيد. حاله من الخادم كزرّه القديم بالرأس.
          ValueListenableBuilder(
            valueListenable: AiAssistantState.gate,
            builder: (context, _, __) =>
                AiAssistantState.visible && (_intent == null || _intent!.action == VoiceAction.unknown)
                    ? Padding(padding: const EdgeInsets.only(top: Sp.lg), child: _assistantRow())
                    : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  /// «المساعد الذكي» — يغلق الورقة ويفتح «كيف أسوّي؟» من سياق الرأس (الموافقة أوّلاً). موظّفٌ بلا صلاحيّته ⇒ الصفّ بمكانه مقفلاً
  /// والنقر رسالة القفل بلا طلب (والورقة باقية) — قاعدة «مقفل لا مخفيّ».
  Widget _assistantRow() {
    final locked = AiAssistantState.askLocked;
    void tap() {
      if (locked) return showNoPermission(context);
      Navigator.of(context).pop();
      unawaited(AssistantSheet.showAsk(widget.rootContext));
    }

    Widget box = Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: locked ? LockedStyle.box : AppColors.brandSoftBg,
        borderRadius: BorderRadius.circular(R.icon),
      ),
      child: Icon(LucideIcons.sparkles, size: 18, color: locked ? LockedStyle.glyph : AppColors.brandAccent),
    );
    if (locked) box = PermLockBadge(child: box);
    return Semantics(
      button: true,
      label: locked ? 'locked.a11y'.tr(args: ['ai.title'.tr()]) : 'ai.title'.tr(),
      onTap: tap,
      excludeSemantics: true,
      child: Material(
        key: const ValueKey('voice-assistant'),
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.md),
        child: InkWell(
          onTap: tap,
          borderRadius: BorderRadius.circular(R.md),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(R.md),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(children: [
              box,
              const SizedBox(width: Sp.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('ai.title'.tr(),
                        style: AppType.bodyStrong(color: locked ? LockedStyle.title : AppColors.textHi)),
                    Text('ai.empty_title'.tr(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.muted(color: locked ? LockedStyle.subtitle : AppColors.textMid)),
                  ],
                ),
              ),
              Icon(LucideIcons.chevronLeft, size: 18, color: AppColors.textLow),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _input() {
    return Container(
      key: const ValueKey('voice-input'),
      padding: const EdgeInsetsDirectional.fromSTEB(Sp.md, Sp.xs, Sp.xs, Sp.xs),
      decoration: BoxDecoration(
        color: AppColors.surfaceSunken,
        borderRadius: BorderRadius.circular(R.card),
        border: Border.all(color: _listening ? AppColors.brandAccent : AppColors.border),
      ),
      child: Row(children: [
        Expanded(
          child: TextField(
            key: const ValueKey('voice-text'),
            controller: _ctrl,
            textInputAction: TextInputAction.go,
            onSubmitted: _run,
            style: AppType.body(color: AppColors.textHi),
            decoration: InputDecoration(
              isDense: true,
              border: InputBorder.none,
              hintText: _listening ? 'أسمعك…' : 'مثلاً: فعّل علي حسين',
              hintStyle: AppType.body(color: AppColors.textLow),
            ),
          ),
        ),
        IconButton(
          key: const ValueKey('voice-go'),
          tooltip: 'نفّذ',
          onPressed: () => _run(_ctrl.text),
          icon: Icon(LucideIcons.cornerDownLeft, size: 18, color: AppColors.textMid),
        ),
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _listening ? AppColors.dangerSoftBg : AppColors.brandSoftBg,
          ),
          alignment: Alignment.center,
          child: AppPlatform.isWindows ? WindowsVoiceButton(
            controller: _ctrl,
            autoStart: widget.autoListen,
            onListening: (v) { if (mounted) setState(() => _listening = v); },
            onFinal: _run,
          ) : VoiceSearchButton(
            controller: _ctrl,
            size: 24,
            autoStart: widget.autoListen,
            idleColor: AppColors.brandOnSoft,
            onListening: (v) {
              if (mounted) setState(() => _listening = v);
            },
            onFinal: _run,
          ),
        ),
      ]),
    );
  }

  List<Widget> _result() {
    final intent = _intent;
    if (intent == null) return [_examplesBox(title: 'جرّب:')];
    if (_busy) {
      return [
        _box(Row(children: [
          const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: Sp.sm),
          Expanded(
            child: Text(
              intent.action == VoiceAction.checkAll ? 'أجلب أجهزتك…' : 'أدوّر على «${intent.query}»…',
              style: AppType.body(color: AppColors.textMid),
            ),
          ),
        ])),
      ];
    }
    switch (intent.action) {
      case VoiceAction.unknown:
        return [
          _box(Text('ما فهمت الأمر «${intent.raw}» — قل الفعل ثمّ الاسم.',
              style: AppType.bodyStrong(color: AppColors.textHi))),
          const SizedBox(height: Sp.sm),
          _examplesBox(title: 'مثل:'),
        ];
      case VoiceAction.checkAll:
        return [
          _actionCard(
            key: const ValueKey('voice-check-all'),
            icon: LucideIcons.radar,
            title: 'فحص شامل لكلّ أجهزتك',
            lines: const ['تقريرٌ لكلّ جهاز — والسكتر بمشتركيه'],
            button: 'ابدأ الفحص',
            onTap: _checkAll,
          ),
        ];
      case VoiceAction.checkDevice:
        return _deviceResult(intent);
      default:
        return _subscriberResult(intent, _subs);
    }
  }

  List<Widget> _deviceResult(VoiceIntent intent) {
    final d = _dev;
    if (d != null) {
      return [
        _actionCard(
          key: const ValueKey('voice-device-card'),
          icon: LucideIcons.router,
          title: d.name,
          lines: [d.ip, if (d.lastStatus == 'online') 'آخر حال: يردّ' else if (d.lastStatus == 'offline') 'آخر حال: لا يردّ'],
          button: 'افحص الجهاز',
          onTap: () => _openDevice(d),
        ),
      ];
    }
    final m = _devs;
    if (m == null) return const [];
    if (m.error != null) return [_box(Text(m.error!, style: AppType.body(color: AppColors.textMid)))];
    if (m.isEmpty) {
      final s = _subs;
      if (s != null && s.items.isNotEmpty) {
        return [
          _box(Text('ما لكيت جهاز باسم «${intent.query}» — بالمشتركين:', style: AppType.body(color: AppColors.textMid))),
          const SizedBox(height: Sp.xs),
          ..._subscriberPicks(s, VoiceAction.open),
        ];
      }
      return [_box(Text('ما لكيت جهاز باسم «${intent.query}»', style: AppType.body(color: AppColors.textMid)))];
    }
    return [
      _hint('اختار الجهاز:'),
      for (final x in m.items)
        _pickTile(
          key: ValueKey('voice-dev-${x.item.id}'),
          title: x.item.name,
          subtitle: x.item.ip,
          onTap: () => setState(() => _dev = x.item),
        ),
    ];
  }

  List<Widget> _subscriberResult(VoiceIntent intent, VoiceMatches<Subscriber>? m) {
    final s = _sub;
    if (s != null) return [_subscriberCard(s, intent)];
    if (m == null) return const [];
    if (m.error != null) return [_box(Text(m.error!, style: AppType.body(color: AppColors.textMid)))];
    if (m.isEmpty) {
      return [_box(Text('ما لكيت مشترك باسم «${intent.query}»', style: AppType.body(color: AppColors.textMid)))];
    }
    return [_hint('أكثر من مشترك — اختار:'), ..._subscriberPicks(m, intent.action)];
  }

  List<Widget> _subscriberPicks(VoiceMatches<Subscriber> m, VoiceAction a) => [
        for (final x in m.items)
          _pickTile(
            key: ValueKey('voice-sub-${x.item.idx ?? x.item.username}'),
            title: x.item.fullName.trim().isEmpty ? x.item.username : x.item.fullName,
            subtitle: [x.item.username, if ((x.item.profileName ?? '').isNotEmpty) x.item.profileName!].join(' · '),
            onTap: () => setState(() {
              _sub = x.item;
              if (_intent != null && _intent!.action == VoiceAction.checkDevice) {
                _intent = VoiceIntent(a, query: _intent!.query, raw: _intent!.raw);
              }
            }),
          ),
      ];

  Widget _subscriberCard(Subscriber s, VoiceIntent intent) {
    final name = s.fullName.trim().isEmpty ? s.username : s.fullName;
    final status = s.isDisabled ? 'مطفي' : (s.isOnline ? 'متّصل' : 'غير متّصل');
    final days = s.remainingDays;
    final expiry = days == null
        ? null
        : days < 0
            ? 'منتهي منذ ${-days} يوم'
            : 'باقي $days يوم';
    final debt = s.hasDebt ? 'عليه ${formatIQD(s.debtAbs.round())}' : 'ما عليه دين';
    final lines = <String>[
      [s.username, if ((s.profileName ?? '').isNotEmpty) s.profileName!].join(' · '),
      [status, if (expiry != null) expiry].join(' · '),
      debt,
    ];
    final reminder = <String>[
      if (intent.months != null) intent.months == 1 ? 'شهر' : intent.months == 2 ? 'شهرين' : '${intent.months} اشهر',
      if (intent.payment == VoicePayment.debt) 'بالدين',
      if (intent.payment == VoicePayment.cash) 'نقد',
    ];
    if (reminder.isNotEmpty) lines.add('قلت: ${reminder.join(' ')} — تختارها بشاشة التفعيل');
    // المبلغ كما فُهم — بخانة النافذة ويُصحَّح هناك (٧ نوفمبر: «العمليات المهمه كلها»)
    final amount = intent.amount;
    if (voiceMoneyActions.contains(intent.action)) {
      if (intent.action == VoiceAction.payDebt && intent.fullAmount && s.hasDebt) {
        lines.add('المبلغ: الدين كلّه ${formatIQD(s.debtAbs.round())}');
      } else if (amount != null) {
        lines.add('المبلغ: ${formatIQD(amount)}');
      } else {
        lines.add('المبلغ تكتبه بالنافذة');
      }
    }
    final (String button, IconData icon) = switch (intent.action) {
      VoiceAction.activate => ('فعّل', LucideIcons.refreshCw),
      VoiceAction.disable => ('طفّي', LucideIcons.ban),
      VoiceAction.enable => ('شغّل', LucideIcons.circleCheck),
      VoiceAction.debt => ('افتح المشترك', LucideIcons.wallet),
      VoiceAction.payDebt => ('سدّد الدين', LucideIcons.banknote),
      VoiceAction.addDebt => ('أضف الدين', LucideIcons.plus),
      VoiceAction.addCredit => ('أضف الرصيد', LucideIcons.badgeDollarSign),
      VoiceAction.discount => ('الخصم', LucideIcons.tag),
      VoiceAction.debtReminder => ('ذكّره بالدين', LucideIcons.bellRing),
      VoiceAction.expiryWarning => ('نبّهه بالانتهاء', LucideIcons.clockAlert),
      VoiceAction.sendInfo => ('أرسل المعلومات', LucideIcons.info),
      VoiceAction.printReceipt => ('اطبع الوصل', LucideIcons.printer),
      VoiceAction.qr => ('رمز QR', LucideIcons.qrCode),
      VoiceAction.statement => ('كشف الحساب', LucideIcons.fileText),
      VoiceAction.movements => ('سجل الحركات', LucideIcons.history),
      VoiceAction.call => ('اتّصل', LucideIcons.phone),
      VoiceAction.whatsapp => ('واتساب', LucideIcons.messageCircle),
      _ => ('افتح المشترك', LucideIcons.userRound),
    };
    return _actionCard(
      key: const ValueKey('voice-sub-card'),
      icon: icon,
      title: name,
      lines: lines,
      button: button,
      warn: intent.action == VoiceAction.disable,
      onTap: () => _openSubscriber(s, intent),
    );
  }

  // ── قطع ──
  Widget _box(Widget child) => Container(
        padding: const EdgeInsets.all(Sp.md),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(R.card),
          border: Border.all(color: AppColors.border),
        ),
        child: child,
      );

  Widget _hint(String t) => Padding(
        padding: const EdgeInsets.only(bottom: Sp.xs),
        child: Text(t, style: AppType.muted(color: AppColors.textMid)),
      );

  Widget _actionCard({
    required Key key,
    required IconData icon,
    required String title,
    required List<String> lines,
    required String button,
    required VoidCallback onTap,
    bool warn = false,
  }) {
    return Container(
      key: key,
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.card),
        border: Border.all(color: AppColors.brandSoftBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(icon, size: 18, color: AppColors.brandOnSoft),
          const SizedBox(width: Sp.sm),
          Expanded(
            child: Text(title,
                maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(color: AppColors.textHi)),
          ),
        ]),
        const SizedBox(height: Sp.xs),
        for (final l in lines)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(l, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.muted(color: AppColors.textMid)),
          ),
        const SizedBox(height: Sp.sm),
        FilledButton(
          key: const ValueKey('voice-confirm'),
          onPressed: onTap,
          // التطفية بلون التحذير — كزرّ «تعطيل» في نافذة صفحة المشترك نفسها
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(44),
            backgroundColor: warn ? AppColors.warning : null,
          ),
          child: Text(button),
        ),
      ]),
    );
  }

  Widget _pickTile({required Key key, required String title, required String subtitle, required VoidCallback onTap}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Sp.xs),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.card),
        child: InkWell(
          key: key,
          borderRadius: BorderRadius.circular(R.card),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.sm),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(R.card),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(color: AppColors.textHi)),
                  if (subtitle.isNotEmpty)
                    Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.muted(color: AppColors.textMid)),
                ]),
              ),
              Icon(LucideIcons.chevronLeft, size: 18, color: AppColors.textLow),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _examplesBox({required String title}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _hint(title),
      Wrap(spacing: Sp.xs, runSpacing: Sp.xs, children: [
        for (final e in _examples)
          ActionChip(
            label: Text(e, style: AppType.micro(color: AppColors.textBody)),
            onPressed: () {
              _ctrl.text = e;
              unawaited(_run(e));
            },
          ),
      ]),
    ]);
  }
}
