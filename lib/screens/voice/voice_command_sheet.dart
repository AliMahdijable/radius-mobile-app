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
import '../../services/devices_check.dart';
import '../../services/devices_check_runner.dart';
import '../../services/merged_devices_check.dart';
import '../../services/merged_mode.dart';
import '../../services/permissions_service.dart';
import '../../services/subscribers_check.dart';
import '../../services/voice/voice_check.dart';
import '../../services/voice/voice_command.dart';
import '../../services/voice/voice_resolver.dart';
import '../../services/vpn_now.dart';
import '../../widgets/company_tag.dart';
import '../subscribers/widgets/subs_metric_strip.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../assistant/assistant_sheet.dart';
import '../network_devices/check/devices_check_screen.dart';
import '../network_devices/network_device_details_screen.dart';
import '../subscribers/subscriber_detail_screen.dart';
import '../../services/merged_text.dart';

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

  /// «افحص المشترك فلان»: جوابه (حاله ثمّ جهازه).
  SubscriberVoiceCheck? _subCheck;

  /// «افحص سكتر فلان»: فحص الجهاز نفسه وتقريره — أو لماذا لا يُفحص ([_devNote]).
  DevicesCheckRunner? _devRun;

  /// «افحص سكتر فلان» يمسك قسم الأجهزة ما دام يجري — كالفحص الشامل (المراجعة).
  CheckSectionHold? _devHold;

  /// جولة «افحص سكتر» — طلبٌ ثانٍ للجهاز نفسه وهو ينتظر الطريق لا يترك فاحصين (الأوّل يتيمٌ يمسك القسم) — المراجعة الثانية.
  int _devGen = 0;
  String? _devNote;
  bool _devViaVpn = false;

  static const _examples = [
    'افحص المشترك علي حسين',
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
  void initState() {
    super.initState();
    VpnNow.subscribers.addListener(_changed);
  }

  @override
  void dispose() {
    VpnNow.subscribers.removeListener(_changed);
    _clearChecks();
    _ctrl.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _clearChecks() {
    _devGen++;
    _subCheck?.removeListener(_changed);
    _subCheck?.dispose();
    _subCheck = null;
    _devHold?.dispose();
    _devHold = null;
    _devRun?.removeListener(_changed);
    _devRun?.dispose();
    _devRun = null;
    _devNote = null;
    _devViaVpn = false;
  }

  /// «كل الشركات»: شركة الصفّ (للاسم والشارة ونطاق فحصه) — null خارج الوضع.
  static bool get _merged => MergedMode.active.value;

  /// جواب «افحص المشترك فلان»: حاله فوراً ثمّ جهازه.
  void _startSubCheck(Subscriber s) {
    _subCheck?.removeListener(_changed);
    _subCheck?.dispose();
    final c = _merged ? MergedMode.companyOf(s.companyKey) : null;
    final job = SubscriberVoiceCheck(s, company: c)..addListener(_changed);
    setState(() {
      _sub = s;
      _subCheck = job;
      if (_intent != null && _intent!.action != VoiceAction.checkSubscriber) {
        _intent = VoiceIntent(VoiceAction.checkSubscriber, query: _intent!.query, raw: _intent!.raw);
      }
    });
    unawaited(job.run());
  }

  /// «افحص سكتر فلان»: فحص هذا الجهاز وحده بطريقه — المفتوحة من شبكتك (أو عبر VPN بوضعه/خارج شبكتك)، وجهاز شركةٍ أخرى عبر
  /// VPN شركته (كـ«الفحص الشامل» بـ«كل الشركات»).
  Future<void> _startDeviceCheck(NetworkDevice d) async {
    final token = ++_devGen;
    _devHold?.dispose();
    _devHold = null;
    _devRun?.removeListener(_changed);
    _devRun?.dispose();
    _devRun = null;
    setState(() {
      _dev = d;
      _devNote = null;
      if (_intent != null && _intent!.action != VoiceAction.checkDevice) {
        _intent = VoiceIntent(VoiceAction.checkDevice, query: _intent!.query, raw: _intent!.raw);
      }
    });
    final co = VoiceResolver.companyOfDevice(d.id);
    DevicesCheckRunner runner;
    if (co != null && !co.open) {
      if (!PermissionsService.deepCheckVpn) {
        setState(() => _devNote = 'الفحص الشامل عبر VPN غير مفعّل لك');
        return;
      }
      runner = MergedDevicesCheckRunner([
        MergedCheckPart(company: co.company, devices: [d])
      ], openViaVpn: false);
      _devViaVpn = true;
    } else {
      bool viaVpn;
      try {
        final r = await VpnNow.route();
        viaVpn = VpnNow.mode.value || (r?.linked == true && !AgentNetPresence.isOn);
      } catch (_) {
        viaVpn = VpnNow.mode.value;
      }
      if (!mounted || token != _devGen || _dev?.id != d.id) return;
      if (!viaVpn && AgentNetPresence.isOff) {
        setState(() => _devNote = 'خارج شبكتك — اربط VPN حتى يُفحص الجهاز عن بُعد');
        return;
      }
      if (viaVpn ? !PermissionsService.deepCheckVpn : !PermissionsService.deepCheckNet) {
        setState(() => _devNote = 'الفحص الشامل غير مفعّل لك — افتح صفحة الجهاز');
        return;
      }
      runner = DevicesCheckRunner([d], viaVpn: viaVpn);
      _devViaVpn = viaVpn;
    }
    _devRun = runner..addListener(_changed);
    setState(() {});
    unawaited(runner.run());
    _devHold = CheckSectionHold(runner);
  }

  Future<void> _run(String text) async {
    final t = text.trim();
    if (t.isEmpty) return;
    final gen = ++_gen;
    final intent = VoiceCommand.parse(t);
    _clearChecks();
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
      // لا جهاز بهذا الاسم ⇒ لعلّه مشترك («افحص جهاز علي») — فحصه هو
      VoiceMatches<Subscriber>? s;
      if (d.isEmpty && d.error == null && intent.query.isNotEmpty) s = await VoiceResolver.subscribers(intent.query);
      if (!mounted || gen != _gen) return;
      setState(() {
        _busy = false;
        _devs = d;
        _subs = s;
      });
      if (d.sure) {
        unawaited(_startDeviceCheck(d.items.first.item));
      } else if (s != null && s.sure) {
        _startSubCheck(s.items.first.item);
      }
      return;
    }
    if (intent.action == VoiceAction.check) {
      // «افحص فلان» بلا نوع: الأجهزة والمشتركون معاً، والأوضح يُفحص (والتعادل للمشترك — الأكثر سؤالاً)
      final r = await Future.wait([
        VoiceResolver.devices(intent.query),
        VoiceResolver.subscribers(intent.query),
      ]);
      if (!mounted || gen != _gen) return;
      final d = r[0] as VoiceMatches<NetworkDevice>;
      final s = r[1] as VoiceMatches<Subscriber>;
      setState(() {
        _busy = false;
        _devs = d;
        _subs = s;
      });
      final dTop = d.isEmpty ? 0 : d.items.first.score;
      final sTop = s.isEmpty ? 0 : s.items.first.score;
      if (d.sure && (!s.sure || dTop > sTop)) {
        unawaited(_startDeviceCheck(d.items.first.item));
      } else if (s.sure) {
        _startSubCheck(s.items.first.item);
      }
      return;
    }
    final m = await VoiceResolver.subscribers(intent.query);
    if (!mounted || gen != _gen) return;
    setState(() {
      _busy = false;
      _subs = m;
      if (m.sure && intent.action != VoiceAction.checkSubscriber) _sub = m.items.first.item;
    });
    if (m.sure && intent.action == VoiceAction.checkSubscriber) _startSubCheck(m.items.first.item);
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
          child: AppPlatform.isWindows
              ? WindowsVoiceButton(
                  controller: _ctrl,
                  autoStart: widget.autoListen,
                  onListening: (v) {
                    if (mounted) setState(() => _listening = v);
                  },
                  onFinal: _run,
                )
              : VoiceSearchButton(
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
              intent.action == VoiceAction.checkAll
                  ? 'أجلب أجهزتك…'
                  : 'أدوّر على «${intent.query}»${_merged ? mergedWord(' بكلّ الشركات', ' بكلّ الصفحات') : ''}…',
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
      case VoiceAction.checkSubscriber:
        final c = _subCheck;
        if (c != null) return [_subAnswer(c)];
        return _subscriberResult(intent, _subs);
      case VoiceAction.check:
        // بلا نوع ولا واحدٌ واضح: المشتركون ثمّ الأجهزة — الضغط يفحص
        final s = _subs;
        final d = _devs;
        if ((s == null || s.isEmpty) && (d == null || d.isEmpty)) {
          final err = s?.error ?? d?.error;
          return [
            _box(Text(err ?? 'ما لكيت مشترك ولا جهاز باسم «${intent.query}»',
                style: AppType.body(color: AppColors.textMid)))
          ];
        }
        return [
          if (s != null && s.items.isNotEmpty) ...[
            _hint('مشتركين — اختار للفحص:'),
            ..._subscriberPicks(s, VoiceAction.checkSubscriber)
          ],
          if (d != null && d.items.isNotEmpty) ...[
            const SizedBox(height: Sp.xs),
            _hint('أجهزة:'),
            ..._devicePicks(d),
          ],
        ];
      default:
        return _subscriberResult(intent, _subs);
    }
  }

  // ───────────────────────── جواب «افحص المشترك» ─────────────────────────

  Widget _subAnswer(SubscriberVoiceCheck c) {
    final s = c.sub;
    final name = s.fullName.trim().isEmpty ? s.username : s.fullName;
    final tone = c.disabled
        ? AppTone.neutral
        : c.expired
            ? AppTone.danger
            : (c.online ? AppTone.success : AppTone.warning);
    final r = c.row;
    final bad = {for (final p in r?.problems ?? const <SubsCheckProblem>[]) p.kind};
    final busy = c.phase == VoiceCheckPhase.probing || c.phase == VoiceCheckPhase.vpn;
    final vpnLine = c.phase == VoiceCheckPhase.vpn ? VpnNow.subscribers.line : null;
    final source = r?.reading == null
        ? null
        : [
            r!.reading!.vpn ? 'عبر VPN الشركة' : 'من شبكتك',
            if (r.reading!.via != null) 'من ${r.reading!.via}',
            if (r.reading!.device != null) r.reading!.device!,
          ].join(' · ');
    Widget chip(String text, AppTone t) => Container(
          padding: const EdgeInsets.symmetric(horizontal: Sp.sm, vertical: 3),
          decoration: BoxDecoration(
            color: t.softBg,
            borderRadius: BorderRadius.circular(R.pill),
            border: Border.all(color: t.softBorder),
          ),
          child:
              Text(text, style: AppType.label(color: t.onSoft).copyWith(fontSize: 12.5, fontWeight: FontWeight.w700)),
        );
    return Container(
      key: const ValueKey('voice-sub-answer'),
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.card),
        border: Border.all(color: tone.softBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(LucideIcons.userRoundSearch, size: 18, color: tone.fill),
          const SizedBox(width: Sp.sm),
          Expanded(
            child: Text(name,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(color: AppColors.textHi)),
          ),
          if (_merged && s.companyKey != null) CompanyTag(companyKey: s.companyKey!, fontSize: 11),
        ]),
        const SizedBox(height: 2),
        Text(s.username, style: AppType.muted(color: AppColors.textMid)),
        const SizedBox(height: Sp.sm),
        // الجواب أوّلاً: حاله (المالك: «يا اما مخلص متصل ومخلص طافي»)
        Wrap(spacing: Sp.x6, runSpacing: Sp.x6, children: [
          if (c.disabled)
            chip('مطفي', AppTone.neutral)
          else
            chip(c.expired ? 'منتهي' : 'فعّال', c.expired ? AppTone.danger : AppTone.success),
          // غير المتّصل بكلمة قسمه في «الفحص العامّ» (١٠ نوفمبر)
          chip(c.online ? 'متّصل' : 'غير متّصل', c.online ? AppTone.success : AppTone.warning),
        ]),
        Padding(
          padding: const EdgeInsets.only(top: Sp.x6),
          child: Text(c.headline,
              key: const ValueKey('voice-answer-headline'), style: AppType.bodyStrong(color: tone.fill)),
        ),
        if (c.daysLine != null) Text(c.daysLine!, style: AppType.muted(color: AppColors.textMid)),
        // ثمّ جهازه: متّصلٌ وفعّال ⇒ CCQ والإشارة والكيبل (أو الضوء) بحدود المدير
        if (c.wantsDevice) ...[
          const SizedBox(height: Sp.sm),
          if (busy)
            Row(children: [
              const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: Sp.sm),
              Expanded(
                child: Text(vpnLine ?? c.deviceLine ?? '', style: AppType.muted(color: AppColors.textMid)),
              ),
            ])
          else if (r?.reading != null) ...[
            SubsMetricStrip(reading: r!.reading!, bad: bad, limits: c.limits),
            const SizedBox(height: Sp.x6),
            Text(c.deviceLine ?? '',
                key: const ValueKey('voice-answer-device'),
                style: AppType.label(color: bad.isEmpty ? AppColors.success : AppTone.danger.fill)
                    .copyWith(fontSize: 13, fontWeight: FontWeight.w700)),
            if (source != null) Text(source, style: AppType.muted(color: AppColors.textLow)),
          ] else if (c.deviceLine != null)
            Text(c.deviceLine!,
                key: const ValueKey('voice-answer-device'), style: AppType.label(color: AppColors.warning)),
        ],
        const SizedBox(height: Sp.sm),
        FilledButton(
          key: const ValueKey('voice-confirm'),
          onPressed: () => _openSubscriber(s, VoiceIntent(VoiceAction.open, query: _intent?.query ?? '', raw: '')),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(44)),
          child: const Text('افتح المشترك'),
        ),
      ]),
    );
  }

  // ───────────────────────── جواب «افحص سكتر فلان» ─────────────────────────

  static AppTone _stateTone(CheckState s) => switch (s) {
        CheckState.down => AppTone.danger,
        CheckState.warn => AppTone.warning,
        CheckState.unread => AppTone.neutral,
        CheckState.ok => AppTone.success,
        CheckState.statusOnly => AppTone.neutral,
      };

  static AppTone _levelTone(CheckLevel l) => switch (l) {
        CheckLevel.bad => AppTone.danger,
        CheckLevel.warn => AppTone.warning,
        CheckLevel.info => AppTone.info,
      };

  static String _devProgress(DevicesCheckRunner? run, DeviceCheckReport? rep) {
    if (run?.line != null) return run!.line!;
    if (rep == null || !rep.pending) return 'يفحص الجهاز…';
    final why = rep.findings.map((f) => f.text).firstWhere((t) => t.contains('يكمل'), orElse: () => 'بطيء — يكمل قراءته…');
    return '${rep.stateLabel} — $why';
  }

  Widget _devAnswer(NetworkDevice d) {
    final run = _devRun;
    final rep = run?.reports[d.id];
    final co = VoiceResolver.companyOfDevice(d.id);
    final remote = co != null && !co.open;
    final note = _devNote;
    final tone = rep == null ? AppTone.brand : _stateTone(rep.state);
    final way = remote ? 'عبر VPN الشركة' : (_devViaVpn ? 'عبر VPN' : 'من شبكتك');
    final findings = [...?rep?.findings]..sort((a, b) => a.level.index.compareTo(b.level.index));
    return Container(
      key: const ValueKey('voice-dev-answer'),
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.card),
        border: Border.all(color: tone.softBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(LucideIcons.router, size: 18, color: tone.fill),
          const SizedBox(width: Sp.sm),
          Expanded(
            child: Text(d.name,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(color: AppColors.textHi)),
          ),
          if (co != null) CompanyTag(companyKey: co.company.key, fontSize: 11),
        ]),
        const SizedBox(height: 2),
        Text([if (rep != null) rep.roleLabel, d.ip, if (note == null) way].where((x) => x.isNotEmpty).join(' · '),
            style: AppType.muted(color: AppColors.textMid)),
        const SizedBox(height: Sp.sm),
        if (note != null)
          Text(note, key: const ValueKey('voice-dev-note'), style: AppType.label(color: AppColors.warning))
        else if (run == null || run.running)
          Row(children: [
            const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: Sp.sm),
            // البطيء بعد مهلته الأولى: سطره المؤقّت (بعمر آخر قراءته إن وُجدت) بدل دوّارةٍ صامتة حتى السقف (المراجعة)
            Expanded(
                child: Text(_devProgress(run, rep),
                    key: const ValueKey('voice-dev-progress'), style: AppType.muted(color: AppColors.textMid))),
          ])
        else if (rep == null)
          Text(run.error ?? 'ما انقرى الجهاز', style: AppType.label(color: AppColors.warning))
        else ...[
          // الجواب: حاله ثمّ ما به
          Row(children: [
            Container(
              key: const ValueKey('voice-dev-state'),
              padding: const EdgeInsets.symmetric(horizontal: Sp.sm, vertical: 3),
              decoration: BoxDecoration(
                color: tone.softBg,
                borderRadius: BorderRadius.circular(R.pill),
                border: Border.all(color: tone.softBorder),
              ),
              child: Text(rep.stateLabel,
                  style: AppType.label(color: tone.onSoft).copyWith(fontSize: 12.5, fontWeight: FontWeight.w700)),
            ),
          ]),
          if (rep.vitals.isNotEmpty) ...[
            const SizedBox(height: Sp.x6),
            Wrap(spacing: Sp.x6, runSpacing: Sp.x6, children: [
              for (final v in rep.vitals.take(4))
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: Sp.sm, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceSunken,
                    borderRadius: BorderRadius.circular(R.sm),
                  ),
                  child: Text('${v.k} ${v.v}', style: AppType.label(color: AppColors.textHi).copyWith(fontSize: 12.5)),
                ),
            ]),
          ],
          if (findings.isNotEmpty) ...[
            const SizedBox(height: Sp.x6),
            for (final f in findings.take(4))
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(color: _levelTone(f.level).fill, shape: BoxShape.circle),
                    ),
                  ),
                  const SizedBox(width: Sp.x6),
                  Expanded(
                    child: Text(f.text,
                        maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.body(color: AppColors.textHi)),
                  ),
                ]),
              ),
          ] else if (rep.state == CheckState.ok)
            Padding(
              padding: const EdgeInsets.only(top: Sp.x6),
              child: Text('ما به شي ✓', style: AppType.label(color: AppColors.success)),
            ),
          // السكتر/الأولت: من هم الضعاف بأسمائهم (المالك: «يعطي نتيجه الجهاز شنو اللي بي»)
          if (rep.subs.any((x) => x.bad || (x.light != null && x.light! < -27))) ...[
            const SizedBox(height: Sp.x6),
            Text(
              'الأضعف: ${[
                for (final x in rep.subs.where((x) => x.bad || (x.light != null && x.light! < -27)).take(3))
                  '${x.title} (${x.light != null ? '${x.light!.toStringAsFixed(1)} dBm' : x.weak && x.signal != null ? '${x.signal} dBm' : 'CCQ ${x.ccq ?? '-'}%'})',
              ].join(' · ')}',
              key: const ValueKey('voice-dev-weak'),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: AppType.muted(color: AppColors.textMid),
            ),
          ],
        ],
        const SizedBox(height: Sp.sm),
        Row(children: [
          if (rep != null)
            Expanded(
              child: FilledButton(
                key: const ValueKey('voice-dev-report'),
                onPressed: () => _openDeviceReport(d),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                child: const Text('التقرير الكامل'),
              ),
            ),
          if (rep != null && !remote) const SizedBox(width: Sp.sm),
          if (!remote)
            Expanded(
              child: OutlinedButton(
                key: const ValueKey('voice-dev-page'),
                onPressed: () => _openDevice(d),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                child: const Text('صفحة الجهاز'),
              ),
            ),
        ]),
      ]),
    );
  }

  /// التقرير الكامل للجهاز نفسه (تقرير «الفحص الشامل» لجهازٍ واحد) — بطريقه.
  Future<void> _openDeviceReport(NetworkDevice d) async {
    final root = widget.rootContext;
    final co = VoiceResolver.companyOfDevice(d.id);
    final remote = co != null && !co.open;
    final viaVpn = _devViaVpn;
    Navigator.of(context).pop();
    await Navigator.of(root).push(MaterialPageRoute<void>(
      builder: (_) => DevicesCheckScreen(
        devices: [d],
        viaVpn: viaVpn,
        runner: remote
            ? MergedDevicesCheckRunner([
                MergedCheckPart(company: co.company, devices: [d])
              ], openViaVpn: false)
            : null,
      ),
    ));
  }

  List<Widget> _deviceResult(VoiceIntent intent) {
    final d = _dev;
    if (d != null) return [_devAnswer(d)];
    final m = _devs;
    if (m == null) return const [];
    if (m.error != null) return [_box(Text(m.error!, style: AppType.body(color: AppColors.textMid)))];
    if (m.isEmpty) {
      final s = _subs;
      if (s != null && s.items.isNotEmpty) {
        return [
          _box(
              Text('ما لكيت جهاز باسم «${intent.query}» — بالمشتركين:', style: AppType.body(color: AppColors.textMid))),
          const SizedBox(height: Sp.xs),
          ..._subscriberPicks(s, VoiceAction.checkSubscriber),
        ];
      }
      return [_box(Text('ما لكيت جهاز باسم «${intent.query}»', style: AppType.body(color: AppColors.textMid)))];
    }
    return [_hint('اختار الجهاز:'), ..._devicePicks(m)];
  }

  List<Widget> _devicePicks(VoiceMatches<NetworkDevice> m) => [
        for (final x in m.items)
          _pickTile(
            key: ValueKey('voice-dev-${x.item.id}'),
            title: x.item.name,
            subtitle: [
              x.item.ip,
              if (VoiceResolver.companyOfDevice(x.item.id) != null)
                VoiceResolver.companyOfDevice(x.item.id)!.company.name
            ].join(' · '),
            onTap: () => _startDeviceCheck(x.item),
          ),
      ];

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
            key: ValueKey('voice-sub-${x.item.companyKey ?? ''}${x.item.idx ?? x.item.username}'),
            title: x.item.fullName.trim().isEmpty ? x.item.username : x.item.fullName,
            subtitle: [
              x.item.username,
              if ((x.item.profileName ?? '').isNotEmpty) x.item.profileName!,
              // «كل الشركات»: الشركة باسمها — اليوزر نفسه قد يكون بشركتين
              if (_merged && MergedMode.companyOf(x.item.companyKey) != null)
                MergedMode.companyOf(x.item.companyKey)!.name,
            ].join(' · '),
            onTap: () {
              if (a == VoiceAction.checkSubscriber) return _startSubCheck(x.item);
              setState(() {
                _sub = x.item;
                if (_intent != null && _intent!.action == VoiceAction.checkDevice) {
                  _intent = VoiceIntent(a, query: _intent!.query, raw: _intent!.raw);
                }
              });
            },
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
    final co = _merged ? MergedMode.companyOf(s.companyKey) : null;
    final lines = <String>[
      [s.username, if ((s.profileName ?? '').isNotEmpty) s.profileName!].join(' · '),
      [status, if (expiry != null) expiry].join(' · '),
      debt,
      if (co != null) 'الشركة: ${co.name}',
    ];
    final reminder = <String>[
      if (intent.months != null)
        intent.months == 1
            ? 'شهر'
            : intent.months == 2
                ? 'شهرين'
                : '${intent.months} اشهر',
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
            child:
                Text(l, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.muted(color: AppColors.textMid)),
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
                  Text(title,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(color: AppColors.textHi)),
                  if (subtitle.isNotEmpty)
                    Text(subtitle,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.muted(color: AppColors.textMid)),
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
