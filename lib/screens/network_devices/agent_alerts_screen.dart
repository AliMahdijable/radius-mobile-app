import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/agent_alerts_api.dart';
import '../../core/util/server_time.dart';
import '../../core/widgets/app_sheet.dart';
import '../../core/widgets/design_sheet.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../../widgets/alerts_pager.dart';
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
  AgentVitalsStatus? _vit;
  bool _loading = true;
  bool _failed = false;
  String? _busy; // enabled | notify_up | v_enabled | v_volt

  /// كلّ قائمةٍ هنا عشرةٌ أوّلاً و«تحميل المزيد» (٩ نوفمبر — المالك: «تنبيهات المشتركين والأجهزة — خلّي بيها ١٠ قراءات وتحميل
  /// المزيد»): السجلّ صفحاتٌ من الخادم (كان ٥٠ دفعةً واحدة و«الأقدم»)، والطافية/المتذبذبة/القراءات الحسّاسة/الكهرباء من الحال نفسه.
  final AlertsPager<AgentAlertEvent> _log = AlertsPager<AgentAlertEvent>(
    fetch: ({String? before, required int have, required int size}) => AgentAlertsApi.logPage(before: before, size: size),
    keyOf: (e) => e.id,
  );
  final _downMore = AlertsReveal();
  final _quietMore = AlertsReveal();
  final _vitalsMore = AlertsReveal();
  final _powerMore = AlertsReveal();

  /// الكهرباء و«كيف تُراقَب» تنطويان (٦ نوفمبر — المالك: «قسم الكهرباء شوفه هذا يكون توكل»؛ ولا كرت يكبر بلا داعٍ).
  bool _powerOpen = false;
  bool _howOpen = false;

  @override
  void initState() {
    super.initState();
    _log.addListener(_onLog);
    _load();
  }

  @override
  void dispose() {
    _log.removeListener(_onLog);
    _log.dispose();
    super.dispose();
  }

  void _onLog() {
    if (mounted) setState(() {});
  }

  /// الحال، والسجلّ (العشرة الأحدث — أو بعمق ما عُرض بعد حفظٍ: [keepLog]) والقراءات الحسّاسة معاً.
  Future<void> _load({bool keepLog = false}) async {
    final st = await AgentAlertsApi.status();
    AgentVitalsStatus? vit;
    if (st != null && st.available && st.canUse) {
      final r = await Future.wait<Object?>([_log.reload(keepDepth: keepLog), AgentAlertsApi.vitalsStatus()]);
      vit = r[1] as AgentVitalsStatus?;
    }
    if (!mounted) return;
    setState(() {
      _st = st;
      _vit = vit;
      _failed = st == null;
      _loading = false;
    });
  }

  /// مفتاحا «القراءات الحسّاسة» والكهرباء على الشاشة نفسها (كانا داخل «الحدود» وحدها).
  Future<void> _setVitals(AgentVitalSettings next, String key) async {
    setState(() => _busy = key);
    final r = await AgentAlertsApi.saveVitals(next);
    if (!mounted) return;
    if (!r.ok) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(r.message ?? 'تعذّر الحفظ')));
    await _load(keepLog: true);
    if (mounted) setState(() => _busy = null);
  }

  Future<void> _set({bool? enabled, bool? notifyUp}) async {
    setState(() => _busy = enabled != null ? 'enabled' : 'notify_up');
    final r = await AgentAlertsApi.save(enabled: enabled, notifyUp: notifyUp);
    if (!mounted) return;
    if (!r.ok) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(r.message ?? 'تعذّر الحفظ')));
    await _load(keepLog: true);
    if (mounted) setState(() => _busy = null);
  }

  /// «تحميل المزيد» لقائمةٍ من الحال (تكشف عشرةً أخرى).
  Widget _revealMore(String key, AlertsReveal r) => Padding(
        padding: const EdgeInsets.only(top: Sp.xs, bottom: Sp.xs),
        child: AlertsMoreButton(key: ValueKey(key), onTap: () => setState(r.more)),
      );

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
        for (final d in _downMore.take(st.down)) _deviceRow(d, quiet: false),
        if (_downMore.hasMore(st.down)) _revealMore('aa-more-down', _downMore),
      ],
      if (st.quiet.isNotEmpty) ...[
        const SizedBox(height: Sp.lg),
        _section('تطفي وتشتغل — مسكوتٌ عنها ساعة'),
        for (final d in _quietMore.take(st.quiet)) _deviceRow(d, quiet: true),
        if (_quietMore.hasMore(st.quiet)) _revealMore('aa-more-quiet', _quietMore),
      ],
      if (_vit != null && _vit!.available && _vit!.canUse) ...[
        const SizedBox(height: Sp.lg),
        _vitalsSection(_vit!),
      ],
      const SizedBox(height: Sp.lg),
      _settings(st),
      const SizedBox(height: Sp.lg),
      _howCard(st),
      const SizedBox(height: Sp.lg),
      _section('السجلّ'),
      if (_log.items.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: Sp.md),
          child: _log.failed
              ? Text('تعذّر تحميل السجلّ — اسحب للأسفل لإعادة المحاولة', style: AppType.muted(color: AppColors.error))
              : Text('لا شيء بعد — يظهر هنا كلّ ما طفى أو رجع', style: AppType.muted(color: AppColors.textMid)),
        )
      else ...[
        for (final e in _log.items) _eventRow(e),
        if (_log.hasMore)
          Padding(
            padding: const EdgeInsets.only(top: Sp.sm),
            child: AlertsMoreButton(
                key: const ValueKey('aa-more-log'), busy: _log.loadingMore, failed: _log.moreFailed, onTap: _log.loadMore),
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
    final vit = _vit != null && _vit!.available ? _vit! : null;
    Widget row({required String title, required String sub, required bool value, required String key, required ValueChanged<bool> onChanged,
        bool? canEdit}) {
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
            : Switch(
                key: ValueKey('aa-switch-$key'), value: value, onChanged: (canEdit ?? st.canEdit) && _busy == null ? onChanged : null),
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
        // ٦ نوفمبر (المالك: «والداخلي الفحص وقسم الكهرباء… يكون توكل»): مفتاحان ظاهران لا داخل «الحدود» وحدها
        if (vit != null) ...[
          Divider(height: Sp.xl, color: AppColors.divider),
          row(
            title: 'نبّهني بالقراءات الحسّاسة',
            sub: 'المعالج والحرارة والإشارة وجودة الوصلة — حين تتجاوز حدودك',
            value: vit.settings.enabled,
            key: 'v_enabled',
            canEdit: vit.canEdit,
            onChanged: (v) => _setVitals(vit.settings.copyWith(enabled: v), 'v_enabled'),
          ),
          if (vit.settings.enabled) ...[
            Divider(height: Sp.xl, color: AppColors.divider),
            row(
              title: 'نبّهني حين تنزل الكهرباء',
              sub: 'نزولها عن طبيعيّ الجهاز ورجوعها — يصلك حتى بساعات الهدوء',
              value: vit.settings.voltOn,
              key: 'v_volt',
              canEdit: vit.canEdit,
              onChanged: (v) => _setVitals(vit.settings.copyWith(voltOn: v), 'v_volt'),
            ),
          ],
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
        _foldHead(
          key: 'aa-how-head',
          icon: LucideIcons.info,
          title: 'كيف تُراقَب أجهزتك',
          sub: r != null && r.on ? 'من موبايلك على شبكتك، والخادم عبر VPN وأنت بعيد' : 'من موبايلك وأنت على شبكتك',
          open: _howOpen,
          onTap: () => setState(() => _howOpen = !_howOpen),
        ),
        if (_howOpen) ...[
          const SizedBox(height: Sp.xs),
          _line(LucideIcons.smartphone, 'من موبايلك وأنت على شبكتك وقسم الأجهزة مفتوح (كلّ 20 ثانية)'),
          _line(
            r != null && r.on ? LucideIcons.shieldCheck : LucideIcons.cloudOff,
            r?.text ?? 'الفحص عن بُعد غير مفتوح لحسابك بعد — تُراقَب من موبايلك وأنت على شبكتك',
            color: r != null && r.on ? AppColors.success : null,
          ),
        ],
        if (r != null && r.fixableInVpn)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: () async {
                await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ConnVpnScreen()));
                if (mounted) _load(keepLog: true);
              },
              icon: const Icon(LucideIcons.shieldPlus, size: 16),
              label: const Text('ربط VPN'),
            ),
          ),
        if (_howOpen) ...[
          const SizedBox(height: Sp.xs),
          Text('«طفى» بعد دقيقتين من عدم الاستجابة، و«رجع» حين يستجيب مرّتين — والجهاز الذي لم يُرَ يعمل قطّ لا يُنبَّه عنه',
              style: AppType.micro(color: AppColors.textMid)),
        ],
      ]),
    );
  }

  /// رأسٌ ينطوي: أيقونة + عنوان + سطرٌ مختصر + سهم.
  Widget _foldHead({required String key, required IconData icon, required String title, required String sub, required bool open,
      required VoidCallback onTap, Color? subColor}) {
    return InkWell(
      key: ValueKey(key),
      borderRadius: BorderRadius.circular(R.sm),
      onTap: onTap,
      child: Row(children: [
        Icon(icon, size: 16, color: AppColors.textMid),
        const SizedBox(width: Sp.sm),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: AppType.bodyStrong(color: AppColors.textHi)),
            const SizedBox(height: 2),
            Text(sub, style: AppType.micro(color: subColor ?? AppColors.textMid)),
          ]),
        ),
        Icon(open ? LucideIcons.chevronUp : LucideIcons.chevronDown, size: 18, color: AppColors.textMid),
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
      'vital_power' => (LucideIcons.batteryWarning, AppColors.error),
      'vital_power_ok' => (LucideIcons.plugZap, AppColors.success),
      'vital_temp' => (LucideIcons.thermometer, AppColors.warning),
      'vital_cpu' => (LucideIcons.cpu, AppColors.warning),
      'vital_signal' || 'vital_ccq' => (LucideIcons.signalLow, AppColors.warning),
      'vital_ok' => (LucideIcons.circleCheck, AppColors.success),
      'vital_rebase' => (LucideIcons.refreshCw, AppColors.textMid),
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
    final title = (e.title ?? '').replaceFirst(RegExp(r'^(🔴|🟢|🟠|🔋|🔌|🌡️|⚠️|📉|✅)\s*'), '');
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

  // ── «القراءات الحسّاسة» (المرحلة ٢) ─────────────────────────────

  static const _vitalLabel = {'volt': 'الكهرباء', 'temp': 'الحرارة', 'cpu': 'المعالج', 'signal': 'الإشارة', 'ccq': 'جودة الوصلة'};

  Widget _vitalsSection(AgentVitalsStatus v) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: _section('القراءات الحسّاسة')),
        if (v.dryRun)
          Padding(
            padding: const EdgeInsetsDirectional.only(end: Sp.xs, bottom: Sp.sm),
            child: Text('تجربة', style: AppType.micro(color: AppColors.warningOnSoft)),
          ),
        if (v.canEdit)
          Padding(
            padding: const EdgeInsets.only(bottom: Sp.sm),
            child: TextButton.icon(
              onPressed: () => _editVitals(v.settings),
              icon: const Icon(LucideIcons.slidersHorizontal, size: 16),
              label: const Text('الحدود'),
            ),
          ),
      ]),
      if (!v.settings.enabled)
        _box(child: Text('القراءات الحسّاسة مطفأة — لا يُقال لك شيءٌ عنها', style: AppType.body(color: AppColors.textMid)))
      else if (v.alerts.isEmpty)
        _box(
          child: Row(children: [
            Icon(LucideIcons.gauge, size: 18, color: AppColors.success),
            const SizedBox(width: Sp.sm),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(v.watched > 0 ? 'كلّها طبيعيّة' : 'لم تصل قراءات بعد', style: AppType.body(color: AppColors.textHi)),
                Text(
                  v.watched > 0
                      ? 'المعالج والحرارة والكهرباء والإشارة — تُقرأ مع قسم الأجهزة'
                      : 'تصل حين تفتح قسم الأجهزة وأنت على شبكتك (كلّ 10 دقائق)',
                  style: AppType.micro(color: AppColors.textMid),
                ),
              ]),
            ),
          ]),
        )
      else ...[
        for (final a in _vitalsMore.take(v.alerts)) _vitalRow(a),
        if (_vitalsMore.hasMore(v.alerts)) _revealMore('aa-more-vitals', _vitalsMore),
      ],
      if (v.settings.enabled && (v.power.isNotEmpty || v.powerLearning > 0)) ...[
        const SizedBox(height: Sp.sm),
        _powerBox(v),
      ],
    ]);
  }

  /// الكهرباء بالفولت (المالك ٤ نوفمبر: «مافهمت ليش مسوي نسبة… مفروض توضح كم يعني للنسبه»): لكلّ جهازٍ فولتيّته الطبيعيّة وحدّ تنبيهه.
  Widget _powerBox(AgentVitalsStatus v) {
    final low = v.power.where((p) => p.alert).length;
    final sub = !v.settings.voltOn
        ? 'إشعارها مطفأ — القراءة مستمرّة'
        : v.power.isEmpty
            ? 'تتعلّم فولتيّة أجهزتك الطبيعيّة'
            : '${v.power.length} جهاز · ${low > 0 ? '$low تحت حدّه' : 'كلّها طبيعيّة'} · التنبيه إذا نزلت ${v.settings.voltDropPct}٪';
    return _box(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _foldHead(
          key: 'aa-power-head',
          icon: LucideIcons.plugZap,
          title: 'الكهرباء',
          sub: sub,
          subColor: low > 0 && v.settings.voltOn ? AppColors.error : null,
          open: _powerOpen,
          onTap: () => setState(() => _powerOpen = !_powerOpen),
        ),
        if (_powerOpen)
        for (final p in _powerMore.take(v.power))
          Padding(
            padding: const EdgeInsets.only(top: Sp.xs),
            child: Row(children: [
              Expanded(
                child: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: AppType.body(color: p.alert ? AppColors.error : AppColors.textBody)),
              ),
              const SizedBox(width: Sp.sm),
              Text('طبيعيّه ', style: AppType.micro(color: AppColors.textMid)),
              Directionality(textDirection: TextDirection.ltr, child: Text(vitalValueText('volt', p.base), style: AppType.micro(color: AppColors.textHi))),
              Text(' · التنبيه تحت ', style: AppType.micro(color: AppColors.textMid)),
              Directionality(
                textDirection: TextDirection.ltr,
                child: Text(vitalValueText('volt', p.alertBelow), style: AppType.microBold(color: AppColors.textHi)),
              ),
            ]),
          ),
        if (_powerOpen && _powerMore.hasMore(v.power))
          Padding(
            padding: const EdgeInsets.only(top: Sp.sm),
            child: AlertsMoreButton(key: const ValueKey('aa-more-power'), onTap: () => setState(_powerMore.more)),
          ),
        if (_powerOpen && v.powerLearning > 0)
          Padding(
            padding: const EdgeInsets.only(top: Sp.xs),
            child: Text(
              v.powerLearning == 1
                  ? 'جهازٌ واحد يتعلّم فولتيّته الطبيعيّة (ساعتان من القراءات)'
                  : '${v.powerLearning} أجهزة تتعلّم فولتيّتها الطبيعيّة (ساعتان من القراءات)',
              style: AppType.micro(color: AppColors.textMid),
            ),
          ),
      ]),
    );
  }

  Widget _vitalRow(AgentVitalAlert a) {
    final icon = switch (a.metric) {
      'volt' => LucideIcons.batteryWarning,
      'temp' => LucideIcons.thermometer,
      'cpu' => LucideIcons.cpu,
      _ => LucideIcons.signalLow,
    };
    final color = a.metric == 'volt' ? AppColors.error : AppColors.warning;
    // القيمة الآن وتحتها طبيعيّ الجهاز — لا سهم: «24.0V ← 19.9V» كان يُقرأ صعوداً من 19.9 إلى 24.0 (٤ نوفمبر)
    final ref = a.base == null
        ? null
        : switch (a.metric) {
            'volt' => 'طبيعيّه \u2066${vitalValueText('volt', a.base)}\u2069',
            'signal' => 'معدّلها \u2066${vitalValueText('signal', a.base)}\u2069',
            _ => null,
          };
    final since = a.sinceMs != null ? 'منذ ${_dur(DateTime.now().millisecondsSinceEpoch - a.sinceMs!)}' : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: Sp.xs),
      child: _box(
        child: Row(children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: Sp.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${_vitalLabel[a.metric] ?? a.metric} · ${a.name}', maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: AppType.body(color: AppColors.textHi)),
              Text([if (a.place != null) a.place!, if (since != null) since].join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: AppType.micro(color: AppColors.textMid)),
            ]),
          ),
          const SizedBox(width: Sp.sm),
          Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
            Directionality(
              textDirection: TextDirection.ltr,
              child: Text(vitalValueText(a.metric, a.value), style: AppType.bodyStrong(color: color)),
            ),
            if (ref != null) Text(ref, style: AppType.micro(color: AppColors.textMid)),
          ]),
        ]),
      ),
    );
  }

  Future<void> _editVitals(AgentVitalSettings cur) async {
    // (الأجهزة بفولتيّتها — مثالٌ حيّ بالفولت تحت «الكهرباء» في الحدود)
    final saved = await showAppSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: AppColors.scrim,
      builder: (_) => VitalsLimitsSheet(initial: cur, power: _vit?.power ?? const []),
    );
    if (saved == true && mounted) _load(keepLog: true);
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

/// قيمة مقياسٍ بوحدته: 19.9V · 82° · -70 dBm · 95%
String vitalValueText(String metric, double? v) {
  if (v == null) return '—';
  return switch (metric) {
    'volt' => '${v.toStringAsFixed(1)}V',
    'temp' => '${v.round()}°',
    'signal' => '${v.round()} dBm',
    _ => '${v.round()}%',
  };
}

/// النسبة بالفولت (المالك ٤ نوفمبر: «مفروض توضح كم يعني للنسبه»): مثالٌ واحد بأوّل جهازٍ عُرفت فولتيّته، وإلّا بجهاز 24V —
/// سطرٌ ثانٍ قصير (كان مثالين باسمين طويلين: خمسة أسطر بعرض 320).
String voltDropHint(int pct, List<AgentVitalPower> power) {
  String v(double x) => '\u2066${vitalValueText('volt', x)}\u2069'; // عزلٌ: رقمٌ لاتينيّ داخل جملةٍ عربيّة
  final p = power.isEmpty ? null : power.first;
  final base = p?.base ?? 24.0;
  final who = p == null ? 'جهازٌ' : '«${_shortName(p.name)}»';
  const nb = '\u00A0'; // «طبيعيّه 24.0V» و«التنبيه تحت 20.4V» لا يُكسران بين سطرين
  return 'نزولها عن طبيعيّ الجهاز\nمثلاً: $who طبيعيّه$nb${v(base)}، التنبيه$nbتحت$nb${v(base * (1 - pct / 100))}';
}

/// اسمٌ طويل ⇒ أوّل ١٥ حرفاً مقطوعةً عند آخر كلمةٍ كاملة («سويج البرج…» لا «سويج البرج الرئ…»).
String _shortName(String name) {
  final c = name.trim().characters;
  if (c.length <= 16) return c.toString();
  final head = c.take(15).toString();
  final cut = head.lastIndexOf(' ');
  return '${cut >= 6 ? head.substring(0, cut) : head}…';
}

/// حدود «القراءات الحسّاسة» — أزرار ± بخطوات الخادم وحدوده (server/agentVitals.js LIMITS).
class VitalsLimitsSheet extends StatefulWidget {
  const VitalsLimitsSheet({super.key, required this.initial, this.power = const []});
  final AgentVitalSettings initial;

  /// أجهزة الوكيل بفولتيّتها الطبيعيّة — مثالٌ حيّ بالفولت تحت «الكهرباء»
  final List<AgentVitalPower> power;

  @override
  State<VitalsLimitsSheet> createState() => _VitalsLimitsSheetState();
}

class _VitalsLimitsSheetState extends State<VitalsLimitsSheet> {
  late AgentVitalSettings _s = widget.initial;
  bool _busy = false;

  Future<void> _save() async {
    setState(() => _busy = true);
    final r = await AgentAlertsApi.saveVitals(_s);
    if (!mounted) return;
    setState(() => _busy = false);
    if (r.ok) {
      Navigator.of(context).pop(true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(r.message ?? 'تعذّر الحفظ')));
    }
  }

  Widget _stepper({required String title, required String hint, required int value, required String unit, required int min,
      required int max, required int step, required ValueChanged<int> onChanged}) {
    Widget btn(IconData icon, int next, String tip) => IconButton(
          tooltip: tip,
          onPressed: !_busy && next >= min && next <= max ? () => setState(() => onChanged(next)) : null,
          icon: Icon(icon, size: 18),
        );
    return Padding(
      padding: const EdgeInsets.only(bottom: Sp.sm),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: AppType.body(color: AppColors.textHi)),
            Text(hint, style: AppType.micro(color: AppColors.textMid)),
          ]),
        ),
        btn(LucideIcons.minus, value - step, 'أقلّ'),
        SizedBox(
          width: 64,
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Text('$value$unit', textAlign: TextAlign.center, style: AppType.bodyStrong(color: AppColors.textHi)),
          ),
        ),
        btn(LucideIcons.plus, value + step, 'أكثر'),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.slidersHorizontal,
        title: 'حدود القراءات الحسّاسة',
        subtitle: 'متى نخبرك بكلّ قراءة',
        onClose: () => Navigator.of(context).pop(false),
      ),
      footer: SheetFooterBar(label: 'حفظ', icon: LucideIcons.check, busy: _busy, onPressed: _save),
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text('نبّهني بالقراءات الحسّاسة', style: AppType.body(color: AppColors.textHi))),
          Switch(value: _s.enabled, onChanged: _busy ? null : (v) => setState(() => _s = _s.copyWith(enabled: v))),
        ]),
        const SizedBox(height: Sp.sm),
        _stepper(title: 'المعالج', hint: 'إذا بقي فوق هذا الحدّ', value: _s.cpuMax, unit: '%', min: 50, max: 100, step: 5,
            onChanged: (v) => _s = _s.copyWith(cpuMax: v)),
        _stepper(title: 'الحرارة', hint: 'إذا بلغها الجهاز', value: _s.tempMax, unit: '°', min: 50, max: 110, step: 5,
            onChanged: (v) => _s = _s.copyWith(tempMax: v)),
        _stepper(title: 'الكهرباء', hint: voltDropHint(_s.voltDropPct, widget.power), value: _s.voltDropPct,
            unit: '%', min: 5, max: 50, step: 5, onChanged: (v) => _s = _s.copyWith(voltDropPct: v)),
        _stepper(title: 'الإشارة', hint: 'أسوأ من معدّلها بهذا القدر', value: _s.signalDropDb, unit: ' dB', min: 3, max: 30, step: 1,
            onChanged: (v) => _s = _s.copyWith(signalDropDb: v)),
        _stepper(title: 'أضعف إشارة', hint: 'دونها تنبيهٌ ولو بلا معدّل', value: _s.signalMin, unit: '', min: -95, max: -40, step: 5,
            onChanged: (v) => _s = _s.copyWith(signalMin: v)),
        _stepper(title: 'جودة الوصلة (CCQ)', hint: 'إذا نزلت دونها', value: _s.ccqMin, unit: '%', min: 10, max: 95, step: 5,
            onChanged: (v) => _s = _s.copyWith(ccqMin: v)),
        const SizedBox(height: Sp.xs),
        Text('الكهرباء تصلك حتى بساعات الهدوء (انقطاع)؛ الباقي يحترمها.', style: AppType.micro(color: AppColors.textMid)),
      ]),
    );
  }
}
