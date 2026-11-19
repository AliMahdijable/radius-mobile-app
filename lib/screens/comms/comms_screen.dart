import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/broadcast_api.dart';
import '../../api/company_route.dart';
import '../../api/message_exclusions_api.dart';
import '../../api/whatsapp_api.dart';
import '../../core/widgets/permission_locked.dart';
import '../../services/merged_mode.dart';
import '../../services/permissions_service.dart';
import '../../services/provider_service.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../../widgets/delivery_channels.dart';
import '../../widgets/merged_section.dart';
import '../app_modules.dart';
import '../broadcast/broadcast_screen.dart';
import '../desktop/desk_widgets.dart';
import '../message_logs/message_logs_screen.dart';
import '../more_modules_screen.dart' show ModuleCard, ModuleGroupLabel;
import '../telegram/telegram_screen.dart';
import '../whatsapp/connection_alerts_screen.dart';
import '../whatsapp/message_exclusions_screen.dart';
import '../whatsapp/whatsapp_schedules_screen.dart';
import '../whatsapp/whatsapp_status_screen.dart';
import '../whatsapp/whatsapp_templates_screen.dart';

/// عناوين «التواصل» بترتيبها.
enum CommsSection {
  send('الإرسال'),
  templates('القوالب'),
  follow('المتابعة'),
  channels('القنوات'),
  settings('الضبط');

  const CommsSection(this.label);
  final String label;
}

/// بندٌ من «التواصل»: القسم نفسه بقفله وسببه كما كان بمدخله القديم (المزيد أو الإعدادات) — ومكانه تحت أيّ عنوان.
@immutable
class CommsEntry {
  const CommsEntry(this.section, this.module, {this.trailing});
  final CommsSection section;
  final AppModule module;

  /// رقمٌ محايد بطرف البطاقة (عدد المستثنين).
  final String? trailing;
}

/// عنوان «التواصل» وبطاقته بـ«المزيد» والإعدادات.
const kCommsTitle = 'التواصل';
const kCommsCardTitle = 'واتساب وتلغرام';
const kCommsCardHint = 'التبليغات والتذكيرات والقوالب وحالة الرسائل';

/// بنود «التواصل» (٢٠ نوفمبر — المالك: «القوائم صايره هوسه بالمزيد… اي شي يخص قوالب اعدادات واتساب حالات الارسال الجدولة
/// ننقلاه بقسم واحد… التواصل»). الشروط والأقفال والأغلفة نفسها التي كانت لكلٍّ منها: التبليغات وحالة الرسائل وتلغرام من «المزيد»،
/// وحالة الواتساب وقوالبه وجدولته و«تنبيه المشترك» و«المستثنون من الرسائل» من «الإعدادات».
List<CommsEntry> buildCommsEntries() {
  const tgKeys = ['whatsapp.broadcast', 'whatsapp.send', 'settings.edit'];
  // موظّف ايرث لنك: تلغرام لصاحب الحساب ما لم يوجد مفتاحٌ صريح — كالويب (`/telegram` ownerOnly).
  final tgGate = ProviderService.isEarthlink && Perms.isEmployee ? const ['whatsapp.broadcast', 'settings.edit'] : tgKeys;
  const logKeys = ['whatsapp.broadcast', 'whatsapp.send'];
  // قسم الواتساب بالإعدادات كان يظهر بمفتاحيه — ويختفي كلّه إن لم يكونا ممّا يُمنح لهذا الدور (موظّف ايرث لنك).
  final waShown = permShown(const ['whatsapp.connect', 'whatsapp.templates']);
  final mx = MessageExclusionsState.viewFor(MergedMode.active.value ? [for (final c in MergedMode.usable) c.key] : null);
  final mxOn = waShown && mx.any((v) => v.snap.enabled);
  final mxCount = mx.fold<int>(0, (n, v) => n + (v.snap.enabled ? v.snap.count : 0));
  return [
    if (permShown(const ['whatsapp.broadcast']))
      CommsEntry(
        CommsSection.send,
        AppModule(
          id: 'broadcast',
          group: AppModuleGroup.comms,
          locked: !Perms.has('whatsapp.broadcast'),
          icon: LucideIcons.megaphone,
          tone: AppTone.brand,
          title: 'more.broadcast'.tr(),
          subtitle: 'رسالة لكل المشتركين أو لفئة منهم — واتساب وتلغرام والتطبيق',
          page: () => MergedSection(
              readOnly: true,
              prefixes: const ['/api/whatsapp/broadcast', '/api/whatsapp/broadcasts', '/api/whatsapp/send-scope', '/api/v2/whatsapp'],
              perms: const ['whatsapp.broadcast'],
              lockTitle: 'more.broadcast'.tr(),
              child: const BroadcastScreen()),
        ),
      ),
    if (waShown)
      CommsEntry(
        CommsSection.send,
        AppModule(
          id: 'wa_schedules',
          group: AppModuleGroup.comms,
          locked: !Perms.has('whatsapp.templates'),
          icon: LucideIcons.calendarClock,
          tone: AppTone.brand,
          title: 'settings.whatsapp_schedules'.tr(),
          subtitle: 'تذكير الانتهاء والديون تلقائياً بالأيام والساعات اللي تحددها',
          page: () => const WhatsAppSchedulesScreen(),
        ),
      ),
    if (waShown)
      CommsEntry(
        CommsSection.templates,
        AppModule(
          id: 'wa_templates',
          group: AppModuleGroup.comms,
          locked: !Perms.has('whatsapp.templates'),
          icon: LucideIcons.messageSquareText,
          tone: AppTone.brand,
          title: 'settings.whatsapp_templates'.tr(),
          subtitle: 'نصوص التفعيل والتسديد والتذكير والانتهاء',
          page: () => const WhatsAppTemplatesScreen(),
        ),
      ),
    if (permShown(logKeys))
      CommsEntry(
        CommsSection.follow,
        AppModule(
          id: 'message_logs',
          group: AppModuleGroup.comms,
          locked: !Perms.hasAny(logKeys),
          icon: LucideIcons.history,
          tone: AppTone.brand,
          title: 'more.message_logs'.tr(),
          subtitle: 'كل رسالة: وصلت، تنتظر، أو فشلت — مع إعادة المحاولة',
          page: MessageLogsScreen.mergedPage,
        ),
      ),
    if (waShown)
      CommsEntry(
        CommsSection.channels,
        AppModule(
          id: 'wa_status',
          group: AppModuleGroup.comms,
          locked: !Perms.has('whatsapp.connect'),
          icon: LucideIcons.messageCircle,
          tone: AppTone.whatsapp,
          brandGlyph: AppColors.channelWhatsApp,
          title: 'واتساب',
          subtitle: 'ربط رقمك وحالة الاتصال',
          page: () => const WhatsAppStatusScreen(),
        ),
      ),
    if (permShown(tgGate))
      CommsEntry(
        CommsSection.channels,
        AppModule(
          id: 'telegram',
          group: AppModuleGroup.comms,
          locked: !Perms.hasAny(tgGate),
          icon: LucideIcons.send,
          tone: AppTone.telegram,
          brandGlyph: AppColors.channelTelegram,
          title: 'تلغرام',
          subtitle: 'ربط البوت أو حسابك، وربط المشتركين',
          page: () => MergedSection(
              readOnly: true, prefixes: const ['/api/telegram'], perms: tgGate, lockTitle: 'تلغرام', child: const TelegramScreen()),
        ),
      ),
    if (mxOn)
      CommsEntry(
        CommsSection.settings,
        AppModule(
          id: 'msg_exclusions',
          group: AppModuleGroup.comms,
          locked: !mx.any((v) => v.snap.enabled && v.snap.canManage),
          icon: LucideIcons.bellOff,
          tone: AppTone.neutral,
          title: 'المستثنون من الرسائل',
          subtitle: 'مشتركون ما توصلهم رسائل النظام',
          page: () => const MessageExclusionsScreen(),
        ),
        trailing: mxCount > 0 ? '$mxCount' : null,
      ),
    if (waShown)
      CommsEntry(
        CommsSection.settings,
        AppModule(
          id: 'conn_alerts',
          group: AppModuleGroup.comms,
          locked: !Perms.has('whatsapp.templates'),
          icon: LucideIcons.bellRing,
          tone: AppTone.neutral,
          title: 'conn_alerts.title'.tr(),
          subtitle: 'رسالة للمشترك لمّا جهازه يضعف أو ينقطع',
          page: () => const ConnectionAlertsScreen(),
        ),
      ),
  ];
}

/// ما تتغيّر به بنود «التواصل».
Listenable commsListenable() => Listenable.merge([appModulesListenable(), MessageExclusionsState.changes, MergedMode.active, MergedMode.data]);

/// «التواصل»: كلّ ما يخصّ رسائل المشتركين بمكانٍ واحد — بطاقةٌ واحدة في «المزيد» وصفٌّ في «الإعدادات».
class CommsScreen extends StatefulWidget {
  const CommsScreen({super.key});

  @override
  State<CommsScreen> createState() => _CommsScreenState();
}

class _CommsScreenState extends State<CommsScreen> {
  WhatsConnectionStatus? _wa;
  BroadcastChannelsInfo? _channels;

  @override
  void initState() {
    super.initState();
    // «المستثنون من الرسائل»: هل الميزة مفتوحةٌ للحساب وكم مستثنى — كما كانت بالإعدادات
    unawaited(MessageExclusionsState.ensureFresh());
    if (MergedMode.active.value) {
      unawaited(MessageExclusionsState.ensureCompanies([for (final c in MergedMode.usable) c.key]));
    }
    // سطر الحال تحت «واتساب» و«تلغرام» — قراءتان خفيفتان؛ تعذّرهما ⇒ الوصف الثابت
    if (Perms.has('whatsapp.connect')) {
      unawaited(WhatsAppApi.connectionStatus().then((s) {
        if (mounted && s != null) setState(() => _wa = s);
      }));
    }
    // للمفتوحة صراحةً: «التواصل» ليس قسماً موجَّهاً، وقسم التبليغات المفتوح فوقه (بشريطه) لا يغيّر شركة هذا السطر.
    if (Perms.has('whatsapp.broadcast')) {
      unawaited(CompanyRoute.runOpen(BroadcastApi.channelsInfo).then((c) {
        if (mounted && c != null) setState(() => _channels = c);
      }));
    }
  }

  /// الوصف الحيّ لبطاقات القنوات — أو الوصف الثابت.
  String _subtitleOf(AppModule m) {
    final wa = _wa;
    if (m.id == 'wa_status' && wa != null) {
      final phone = (wa.phone ?? '').trim();
      if (wa.connected) return phone.isEmpty ? 'متّصل' : 'متّصل · $phone';
      return 'غير مربوط — اضغط حتى تربط رقمك';
    }
    if (m.id == 'telegram' && _channels != null) {
      final n = _channels!.reach[DeliveryChannel.telegram];
      if (n != null) return n == 0 ? 'ماكو مشترك مربوط بعد — اربطهم من هنا' : '$n مشترك مربوط';
    }
    return m.subtitle;
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: deskPageBar(
        context,
        mobile: AppBar(
          backgroundColor: AppColors.bg,
          elevation: 0,
          scrolledUnderElevation: 0,
          title: Text(kCommsTitle, style: AppType.title(color: AppColors.textHi).copyWith(fontSize: 17, fontWeight: FontWeight.w700)),
          iconTheme: IconThemeData(color: AppColors.textHi),
        ),
        title: kCommsTitle,
        subtitle: kCommsCardHint,
      ),
      body: ListenableBuilder(
        listenable: commsListenable(),
        builder: (context, _) {
          final entries = buildCommsEntries();
          final children = <Widget>[];
          for (final s in CommsSection.values) {
            final inSection = entries.where((e) => e.section == s).toList();
            if (inSection.isEmpty) continue;
            children.add(ModuleGroupLabel(s.label, key: ValueKey('comms-section-${s.name}')));
            for (var i = 0; i < inSection.length; i++) {
              final e = inSection[i];
              final m = e.module;
              if (i > 0) children.add(const SizedBox(height: Sp.sm));
              children.add(ModuleCard(
                key: ValueKey('comms-${m.id}'),
                locked: m.locked,
                unavailable: m.unavailable,
                icon: m.icon,
                tone: m.tone,
                brandGlyph: m.brandGlyph,
                title: m.title,
                subtitle: _subtitleOf(m),
                trailing: e.trailing,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => m.page())),
              ));
            }
          }
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 920),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(Sp.lg, 0, Sp.lg, Sp.huge),
                children: children,
              ),
            ),
          );
        },
      ),
    );
  }
}
