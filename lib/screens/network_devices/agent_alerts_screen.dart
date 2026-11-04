import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/agent_alerts_api.dart';
import '../../core/util/server_time.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../desktop/desk_widgets.dart';
import '../whatsapp/conn_vpn_screen.dart';
import 'device_alerts_screen.dart';

/// إشعار «تنبيهات الوكيل» (data.type = agent_alert) ⇒ «تنبيهات أجهزتي».
Future<bool> openAgentAlertPush(NavigatorState nav, Map<String, String> data) async {
  if (data['type'] != 'agent_alert') return false;
  await nav.push(MaterialPageRoute(builder: (_) => const AgentAlertsScreen()));
  return true;
}

/// «تنبيهات أجهزتي» (٤ نوفمبر — الخادم server/agentAlerts.js): ما طفى الآن من أجهزة الشبكة، والسجلّ (ما قيل لك: طفى/رجع، البرج،
/// الشبكة كلّها، المتذبذب)، والإعداد (التنبيه + «أخبرني حين يرجع»)، وكيف تُراقَب (موبايلك على شبكتك، والخادم عبر VPN لمن ربطه).
/// الإشعار يصل حتى بساعات الهدوء (المالك: «اي نعم لان هذا شي حساس»). الموظّف بلا «تنبيهات أجهزة الشبكة» يراها مقفلةً لا مخفيّة.
class AgentAlertsScreen extends StatefulWidget {
  const AgentAlertsScreen({super.key});

  @override
  State<AgentAlertsScreen> createState() => _AgentAlertsScreenState();
}

class _AgentAlertsScreenState extends State<AgentAlertsScreen> {
  AgentAlertsStatus? _st;
  List<AgentAlertEvent> _log = const [];
  bool _loading = true;
  bool _failed = false;
  bool _more = false;
  bool _noOlder = false;
  String? _busy; // enabled | notify_up

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final st = await AgentAlertsApi.status();
    List<AgentAlertEvent>? log;
    if (st != null && st.available && st.canUse) log = await AgentAlertsApi.log();
    if (!mounted) return;
    setState(() {
      _st = st;
      _failed = st == null;
      if (log != null) {
        _log = log;
        _noOlder = log.length < 50;
      }
      _loading = false;
    });
  }

  Future<void> _older() async {
    if (_log.isEmpty || _more) return;
    setState(() => _more = true);
    final more = await AgentAlertsApi.log(before: _log.last.id);
    if (!mounted) return;
    setState(() {
      _more = false;
      if (more != null) {
        _log = [..._log, ...more];
        _noOlder = more.length < 50;
      }
    });
  }

  Future<void> _set({bool? enabled, bool? notifyUp}) async {
    setState(() => _busy = enabled != null ? 'enabled' : 'notify_up');
    final r = await AgentAlertsApi.save(enabled: enabled, notifyUp: notifyUp);
    if (!mounted) return;
    if (!r.ok) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(r.message ?? 'تعذّر الحفظ')));
    await _load();
    if (mounted) setState(() => _busy = null);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: deskPageBar(
        context,
        mobile: AppBar(
          backgroundColor: AppColors.surface,
          elevation: 0,
          scrolledUnderElevation: 0,
          iconTheme: IconThemeData(color: AppColors.textHi),
          title: Text('تنبيهات أجهزتي', style: AppType.title(color: AppColors.textHi).copyWith(fontSize: 16)),
        ),
        title: 'تنبيهات أجهزتي',
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.huge),
                children: _body(),
              ),
            ),
    );
  }

  List<Widget> _body() {
    final st = _st;
    if (_failed || st == null) {
      return [
        _center(LucideIcons.wifiOff, 'تعذّر جلب الحال الآن', 'اسحب للأسفل لإعادة المحاولة'),
      ];
    }
    if (!st.available) {
      return [
        _center(LucideIcons.bellOff, 'تنبيهات الأجهزة من الخادم غير مفعّلة لحسابك بعد',
            'تنبيهات موبايلك (وقسم الأجهزة مفتوح) تبقى كما هي'),
        const SizedBox(height: Sp.md),
        OutlinedButton.icon(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DeviceAlertsScreen())),
          icon: const Icon(LucideIcons.siren, size: 18),
          label: const Text('تنبيهات موبايلك'),
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        ),
      ];
    }
    if (!st.canUse) {
      return [
        _center(LucideIcons.lock, 'لا صلاحيّة', 'يفتحها لك المدير من صلاحيّاتك: «تنبيهات أجهزة الشبكة — القسم»'),
      ];
    }
    return [
      if (st.dryRun) ...[
        _box(
          color: AppColors.warningSoftBg,
          border: AppColors.warningSoftBorder,
          child: Row(children: [
            Icon(LucideIcons.flaskConical, size: 18, color: AppColors.warningOnSoft),
            const SizedBox(width: Sp.sm),
            Expanded(
              child: Text('تجربة: يُسجَّل ما كان سيُقال لك هنا، ولا يصلك إشعارٌ بعد',
                  style: AppType.body(color: AppColors.warningOnSoft)),
            ),
          ]),
        ),
        const SizedBox(height: Sp.sm),
      ],
      _stateCard(st),
      if (st.down.isNotEmpty) ...[
        const SizedBox(height: Sp.lg),
        _section('طافية الآن'),
        for (final d in st.down) _deviceRow(d, quiet: false),
      ],
      if (st.quiet.isNotEmpty) ...[
        const SizedBox(height: Sp.lg),
        _section('تطفي وتشتغل — مسكوتٌ عنها ساعة'),
        for (final d in st.quiet) _deviceRow(d, quiet: true),
      ],
      const SizedBox(height: Sp.lg),
      _settings(st),
      const SizedBox(height: Sp.lg),
      _howCard(st),
      const SizedBox(height: Sp.lg),
      _section('السجلّ'),
      if (_log.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: Sp.md),
          child: Text('لا شيء بعد — يظهر هنا كلّ ما طفى أو رجع', style: AppType.muted(color: AppColors.textMid)),
        )
      else ...[
        for (final e in _log) _eventRow(e),
        if (!_noOlder)
          Padding(
            padding: const EdgeInsets.only(top: Sp.sm),
            child: TextButton(
              onPressed: _more ? null : _older,
              child: Text(_more ? 'يجلب…' : 'الأقدم'),
            ),
          ),
      ],
    ];
  }

  Widget _stateCard(AgentAlertsStatus st) {
    final bad = st.networkDown || st.down.isNotEmpty;
    final String head;
    if (!st.enabled) {
      head = 'التنبيه مطفأ — لا يُقال لك شيء';
    } else if (st.networkDown) {
      head = 'شبكتك لا تستجيب';
    } else if (st.down.isNotEmpty) {
      head = switch (st.down.length) {
        1 => 'جهازٌ واحد طافٍ الآن',
        2 => 'جهازان طافيان الآن',
        final n when n <= 10 => '$n أجهزة طافية الآن',
        final n => '$n جهازاً طافياً الآن',
      };
    } else if (st.monitored == 0) {
      head = 'لم تُرَ أجهزتك بعد — افتح قسم الأجهزة وأنت على شبكتك';
    } else {
      head = 'كلّ أجهزتك تعمل';
    }
    final seen = <String>[
      if (st.lastAppMs != null) 'من موبايلك ${timeAgoAr(DateTime.fromMillisecondsSinceEpoch(st.lastAppMs!))}',
      if (st.lastVpnMs != null) 'من الخادم ${timeAgoAr(DateTime.fromMillisecondsSinceEpoch(st.lastVpnMs!))}',
    ];
    return _box(
      color: !st.enabled ? null : (bad ? AppColors.dangerSoftBg : AppColors.successSoftBg),
      border: !st.enabled ? null : (bad ? AppColors.dangerSoftBorder : AppColors.successSoftBorder),
      child: Row(children: [
        Icon(
          !st.enabled ? LucideIcons.bellOff : (bad ? LucideIcons.triangleAlert : LucideIcons.shieldCheck),
          size: 22,
          color: !st.enabled ? AppColors.textMid : (bad ? AppColors.dangerOnSoft : AppColors.success),
        ),
        const SizedBox(width: Sp.md),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(head, style: AppType.bodyStrong(color: AppColors.textHi)),
            const SizedBox(height: 2),
            Text(
              [
                if (st.monitored > 0) '${countDevices(st.monitored)} تحت المراقبة',
                if (seen.isNotEmpty) 'آخر فحص ${seen.join(' · ')}',
              ].join(' · ').ifEmpty('يُراقَب كلّ جهازٍ رُئي يعمل من موبايلك أو من الخادم'),
              style: AppType.micro(color: AppColors.textMid),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _deviceRow(AgentAlertDevice d, {required bool quiet}) {
    final when = quiet
        ? (d.untilMs != null ? 'حتى ${_clock(d.untilMs!)}' : null)
        : (d.sinceMs != null ? 'منذ ${_dur(DateTime.now().millisecondsSinceEpoch - d.sinceMs!)}' : null);
    return Padding(
      padding: const EdgeInsets.only(bottom: Sp.xs),
      child: _box(
        child: Row(children: [
          Icon(quiet ? LucideIcons.activity : LucideIcons.wifiOff, size: 18, color: quiet ? AppColors.warning : AppColors.error),
          const SizedBox(width: Sp.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(d.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.body(color: AppColors.textHi)),
              if (d.place != null)
                Text(d.place!, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.micro(color: AppColors.textMid)),
            ]),
          ),
          if (when != null) ...[
            const SizedBox(width: Sp.sm),
            Text(when, style: AppType.micro(color: AppColors.textMid)),
          ],
        ]),
      ),
    );
  }

  Widget _settings(AgentAlertsStatus st) {
    Widget row({required String title, required String sub, required bool value, required String key, required ValueChanged<bool> onChanged}) {
      final busy = _busy == key;
      return Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: AppType.body(color: AppColors.textHi)),
            const SizedBox(height: 2),
            Text(sub, style: AppType.micro(color: AppColors.textMid)),
          ]),
        ),
        const SizedBox(width: Sp.sm),
        busy
            ? const SizedBox(width: 40, height: 24, child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))))
            : Switch(value: value, onChanged: st.canEdit && _busy == null ? onChanged : null),
      ]);
    }

    return _box(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        row(
          title: 'نبّهني حين يطفى جهاز',
          sub: 'يصلك حتى بساعات الهدوء — إشعارٌ واحد للبرج أو للشبكة كلّها لا لكلّ جهاز',
          value: st.enabled,
          key: 'enabled',
          onChanged: (v) => _set(enabled: v),
        ),
        if (st.enabled) ...[
          Divider(height: Sp.xl, color: AppColors.divider),
          row(
            title: 'أخبرني حين يرجع',
            sub: 'مع مدّة الانقطاع',
            value: st.notifyUp,
            key: 'notify_up',
            onChanged: (v) => _set(notifyUp: v),
          ),
        ],
        if (!st.canEdit) ...[
          const SizedBox(height: Sp.sm),
          Text('التعديل للمدير أو لمن يملك «إدارة الأجهزة»', style: AppType.micro(color: AppColors.textMid)),
        ],
      ]),
    );
  }

  Widget _howCard(AgentAlertsStatus st) {
    final r = st.remote;
    return _box(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('كيف تُراقَب أجهزتك', style: AppType.bodyStrong(color: AppColors.textHi)),
        const SizedBox(height: Sp.xs),
        _line(LucideIcons.smartphone, 'من موبايلك وأنت على شبكتك وقسم الأجهزة مفتوح (كلّ 20 ثانية)'),
        _line(
          r != null && r.on ? LucideIcons.shieldCheck : LucideIcons.cloudOff,
          r?.text ?? 'الفحص عن بُعد غير مفتوح لحسابك بعد — تُراقَب من موبايلك وأنت على شبكتك',
          color: r != null && r.on ? AppColors.success : null,
        ),
        if (r != null && r.fixableInVpn)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: () async {
                await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ConnVpnScreen()));
                if (mounted) _load();
              },
              icon: const Icon(LucideIcons.shieldPlus, size: 16),
              label: const Text('ربط VPN'),
            ),
          ),
        const SizedBox(height: Sp.xs),
        Text('«طفى» بعد دقيقتين من عدم الاستجابة، و«رجع» حين يستجيب مرّتين — والجهاز الذي لم يُرَ يعمل قطّ لا يُنبَّه عنه',
            style: AppType.micro(color: AppColors.textMid)),
      ]),
    );
  }

  Widget _eventRow(AgentAlertEvent e) {
    final (IconData icon, Color color) = switch (e.kind) {
      'network_down' => (LucideIcons.globe, AppColors.error),
      'network_up' => (LucideIcons.globe, AppColors.success),
      'tower_down' => (LucideIcons.radioTower, AppColors.error),
      'tower_up' => (LucideIcons.radioTower, AppColors.success),
      'flap' => (LucideIcons.activity, AppColors.warning),
      'blip' => (LucideIcons.zap, AppColors.textMid),
      'up' => (LucideIcons.wifi, AppColors.success),
      _ => (LucideIcons.wifiOff, AppColors.error),
    };
    final tag = switch (e.push) {
      'dry' => 'تجربة',
      'off' => 'بلا إشعار',
      'failed' => 'لم يصل',
      _ => null,
    };
    // العنوان كما وصلك بلا رمزه الملوّن (الأيقونة تحمله)
    // (بالبدائل لا [..]: الرمز زوجٌ بديل في UTF-16 — فئةٌ تقطعه نصفين فيُرمى النصّ)
    final title = (e.title ?? '').replaceFirst(RegExp(r'^(🔴|🟢|🟠)\s*'), '');
    return Padding(
      padding: const EdgeInsets.only(bottom: Sp.xs),
      child: _box(
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.only(top: 2), child: Icon(icon, size: 18, color: color)),
          const SizedBox(width: Sp.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title.isEmpty ? '—' : title, style: AppType.body(color: AppColors.textHi)),
              if ((e.detail ?? '').isNotEmpty) Text(e.detail!, style: AppType.micro(color: AppColors.textMid)),
              const SizedBox(height: 2),
              Row(children: [
                if (e.atMs != null)
                  Text(timeAgoAr(DateTime.fromMillisecondsSinceEpoch(e.atMs!)), style: AppType.micro(color: AppColors.textLow)),
                if (tag != null) ...[
                  const SizedBox(width: Sp.sm),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: Sp.x6, vertical: 1),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceSunken,
                      borderRadius: BorderRadius.circular(R.pill),
                    ),
                    child: Text(tag, style: AppType.micro(color: AppColors.textMid)),
                  ),
                ],
              ]),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _line(IconData icon, String text, {Color? color}) => Padding(
        padding: const EdgeInsets.only(top: Sp.xs),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.only(top: 2), child: Icon(icon, size: 16, color: color ?? AppColors.textMid)),
          const SizedBox(width: Sp.sm),
          Expanded(child: Text(text, style: AppType.body(color: AppColors.textBody))),
        ]),
      );

  Widget _section(String text) => Padding(
        padding: const EdgeInsets.only(bottom: Sp.sm),
        child: Text(text, style: AppType.bodyStrong(color: AppColors.textHi)),
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
          const SizedBox(height: Sp.xs),
          Text(sub, textAlign: TextAlign.center, style: AppType.muted(color: AppColors.textMid)),
        ]),
      );

  Widget _box({required Widget child, Color? color, Color? border}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.sm),
        decoration: BoxDecoration(
          color: color ?? AppColors.surface,
          borderRadius: BorderRadius.circular(R.lg),
          border: Border.all(color: border ?? AppColors.border),
        ),
        child: child,
      );

  static String _dur(int ms) {
    final m = (ms / 60000).round().clamp(1, 1 << 30);
    if (m < 60) return '$m د';
    final h = m ~/ 60;
    final r = m % 60;
    if (h < 24) return r > 0 ? '$h س $r د' : '$h س';
    final d = h ~/ 24;
    final rh = h % 24;
    return rh > 0 ? '$d يوم $rh س' : '$d يوم';
  }

  static String _clock(int ms) {
    final t = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }
}

/// «جهازٌ واحد» · «جهازان» · «3 أجهزة» · «12 جهازاً»
@visibleForTesting
String countDevices(int n) => switch (n) {
      1 => 'جهازٌ واحد',
      2 => 'جهازان',
      final n when n >= 3 && n <= 10 => '$n أجهزة',
      _ => '$n جهازاً',
    };

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}
