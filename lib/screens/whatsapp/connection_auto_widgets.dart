import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/connection_auto_api.dart';
import '../../core/util/server_time.dart';
import '../../core/widgets/design_sheet.dart';
import '../../services/permissions_service.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import 'conn_vpn_screen.dart';

/// «تنبيه المشترك» التلقائيّ (٣ نوفمبر): الوضع والضوابط بشاشة الإعدادات، وقائمة «بانتظار موافقتك».
/// النصوص بالعربيّة مباشرةً (كأقسام الوطنيّ) — كلماتٌ يفهمها الوكيل.

const _kindLabel = <String, String>{
  'cable': 'الكيبل',
  'signal': 'الإشارة',
  'ccq': 'CCQ',
  'fiber_rx': 'الضوئيّ',
  'fiber_temp': 'الحرارة',
};

const _modes = <(String, String, String)>[
  ('manual', 'يدويّ', 'ترسل أنت من كرت المشترك كما الآن — لا شيء تلقائيّ'),
  ('approval', 'بموافقتي', 'النظام يكتشف المشكلة ويتأكّد منها، وأنت تضغط «أرسل» قبل أن تصل للمشترك'),
  ('auto', 'تلقائيّ', 'النظام يرسل وحده بعد التأكّد — ضمن ساعات الإرسال والسقف اليوميّ'),
];

Widget _box({required Widget child, Color? color, Color? border}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.sm),
      decoration: BoxDecoration(
        color: color ?? AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: border ?? AppColors.border),
      ),
      child: child,
    );

Widget _dryBanner() => _box(
      color: AppColors.warningSoftBg,
      border: AppColors.warningSoftBorder,
      child: Row(children: [
        Icon(LucideIcons.flaskConical, size: 16, color: AppColors.warningOnSoft),
        const SizedBox(width: Sp.sm),
        Expanded(
          child: Text('وضع المحاكاة: كلّ شيءٍ يعمل كما هو، لكن لا تصل أيّ رسالة للمشترك — «أُرسل» هنا تجربة.',
              style: AppType.muted(color: AppColors.warningOnSoft)),
        ),
      ]),
    );

/* ═════════════════════════════ بطاقة الإعدادات ═════════════════════════════ */

class ConnAutoCard extends StatefulWidget {
  const ConnAutoCard({super.key, required this.canEdit});
  final bool canEdit;

  @override
  State<ConnAutoCard> createState() => _ConnAutoCardState();
}

class _ConnAutoCardState extends State<ConnAutoCard> {
  ConnAutoStatus _st = ConnectionAutoApi.status.value;
  ConnAutoSettings _s = ConnectionAutoApi.status.value.settings;

  /// آخر ما حُفظ بالخادم — «حفظ» يظهر حين يختلف عنه وحده (🐛 ٣ نوفمبر: كان يُقارَن بحالةٍ تُستبدل بقراءةٍ سابقة للحفظ فيبقى ظاهراً)
  ConnAutoSettings _saved = ConnectionAutoApi.status.value.settings;
  bool _loaded = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    ConnectionAutoApi.load(force: true).then((st) {
      if (!mounted) return;
      setState(() {
        _st = st;
        _s = st.settings;
        _saved = st.settings;
        _loaded = true;
      });
    });
  }

  bool get _dirty => _s != _saved;

  Future<void> _save() async {
    setState(() => _saving = true);
    final r = await ConnectionAutoApi.save(_s);
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (r.ok) {
        _st = ConnectionAutoApi.status.value;
        _s = _st.settings;
        _saved = _st.settings;
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(r.ok ? 'تم حفظ الإرسال التلقائيّ' : (r.message ?? 'تعذّر الحفظ'))));
  }

  Future<void> _openQueue() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ConnAutoQueueScreen()));
    final st = await ConnectionAutoApi.load(force: true);
    if (mounted) setState(() => _st = st);
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || !_st.available) return const SizedBox.shrink();
    final on = _s.mode != 'manual';
    final edit = widget.canEdit && !_saving;
    return Padding(
      padding: const EdgeInsets.only(top: Sp.lg),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('الإرسال التلقائيّ', style: AppType.bodyStrong(color: AppColors.textHi)),
        const SizedBox(height: Sp.sm),
        if (_st.dryRun) ...[_dryBanner(), const SizedBox(height: Sp.sm)],
        if (!_st.alertsEnabled) ...[
          _box(
            color: AppColors.infoSoftBg,
            border: AppColors.infoSoftBorder,
            child: Text('فعّل «تنبيه المشترك» أعلاه واحفظ أوّلاً — بدونه لا يُقاس ولا يُرسل شيء.',
                style: AppType.muted(color: AppColors.textBody)),
          ),
          const SizedBox(height: Sp.sm),
        ],
        _box(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const SizedBox(height: Sp.xs),
            Row(
              children: [
                for (final m in _modes)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsetsDirectional.only(end: Sp.xs),
                      child: _ModeChip(
                        label: m.$2,
                        selected: _s.mode == m.$1,
                        onTap: edit ? () => setState(() => _s = _s.copyWith(mode: m.$1)) : null,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: Sp.sm),
            Text(_modes.firstWhere((m) => m.$1 == _s.mode).$3, style: AppType.muted(color: AppColors.textMid)),
            if (on) ...[
              _div(),
              _Stepper(
                icon: LucideIcons.repeat,
                label: 'ذكّر المشترك كلّ',
                unit: _s.remindDays == 1 ? 'يوم' : 'أيّام',
                value: _s.remindDays,
                min: 1,
                max: 30,
                onChanged: edit ? (v) => setState(() => _s = _s.copyWith(remindDays: v)) : null,
              ),
              _Stepper(
                icon: LucideIcons.listOrdered,
                label: 'أقصى رسائل للمشكلة نفسها',
                unit: 'رسائل',
                value: _s.maxSends,
                min: 1,
                max: 10,
                onChanged: edit ? (v) => setState(() => _s = _s.copyWith(maxSends: v)) : null,
              ),
              _Stepper(
                icon: LucideIcons.timer,
                label: 'تأكّد من المشكلة بعد',
                unit: 'دقيقة',
                value: _s.confirmMin,
                min: ConnAutoSettings.kConfirmSteps.first,
                max: ConnAutoSettings.kConfirmSteps.last,
                values: ConnAutoSettings.kConfirmSteps,
                onChanged: edit ? (v) => setState(() => _s = _s.copyWith(confirmMin: v)) : null,
              ),
              _Stepper(
                icon: LucideIcons.gauge,
                label: 'سقف الرسائل باليوم',
                unit: 'رسالة',
                value: _s.dailyCap,
                min: 1,
                max: 200,
                step: 5,
                onChanged: edit ? (v) => setState(() => _s = _s.copyWith(dailyCap: v)) : null,
              ),
              _Stepper(
                icon: LucideIcons.sunrise,
                label: 'يبدأ الإرسال الساعة',
                unit: '',
                value: _s.hourFrom,
                min: 0,
                max: _s.hourTo - 1,
                format: _hour,
                onChanged: edit ? (v) => setState(() => _s = _s.copyWith(hourFrom: v)) : null,
              ),
              _Stepper(
                icon: LucideIcons.sunset,
                label: 'وينتهي الساعة',
                unit: '',
                value: _s.hourTo,
                min: _s.hourFrom + 1,
                max: 24,
                format: _hour,
                onChanged: edit ? (v) => setState(() => _s = _s.copyWith(hourTo: v)) : null,
              ),
              const SizedBox(height: Sp.sm),
              Text('المشاكل التي يُنبَّه عنها', style: AppType.label(color: AppColors.textMid)),
              const SizedBox(height: Sp.xs),
              Wrap(spacing: Sp.x6, runSpacing: Sp.x6, children: [
                for (final k in ConnAutoSettings.kAllKinds)
                  FilterChip(
                    label: Text(_kindLabel[k] ?? k),
                    selected: _s.kinds.contains(k),
                    showCheckmark: true,
                    onSelected: edit
                        ? (v) => setState(() {
                              final ks = [..._s.kinds];
                              v ? ks.add(k) : ks.remove(k);
                              _s = _s.copyWith(kinds: ks);
                            })
                        : null,
                  ),
              ]),
              const SizedBox(height: Sp.xs),
            ],
            if (widget.canEdit && _dirty) ...[
              const SizedBox(height: Sp.sm),
              SheetFooterBar(label: 'حفظ الإرسال التلقائيّ', icon: LucideIcons.check, busy: _saving, onPressed: _save),
            ],
          ]),
        ),
        if (on) ...[
          const SizedBox(height: Sp.sm),
          _QueueTile(st: _st, onTap: _openQueue),
        ],
        // «ربط VPN» (٣ نوفمبر): لصاحب الحساب وحده — أسرار شبكته
        if (!PermissionsService.isEmployee) ...[
          const SizedBox(height: Sp.sm),
          _NavTile(
            icon: LucideIcons.shieldCheck,
            title: 'ربط VPN',
            subtitle: 'قياس أجهزة مشتركيك عبر VPN حين يكون تطبيقك خارج الشبكة',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ConnVpnScreen())),
          ),
        ],
      ]),
    );
  }

  static String _hour(int h) {
    if (h == 0 || h == 24) return '١٢ ليلاً';
    if (h == 12) return '١٢ ظهراً';
    return h < 12 ? '$h صباحاً' : '${h - 12} ${h < 17 ? 'ظهراً' : 'مساءً'}';
  }

  Widget _div() => Padding(
        padding: const EdgeInsets.symmetric(vertical: Sp.sm),
        child: Divider(height: 1, color: AppColors.divider),
      );
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({required this.label, required this.selected, this.onTap});
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: selected ? AppColors.brandSoftBg : AppColors.surfaceInput,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(R.md),
          side: BorderSide(color: selected ? AppColors.brand : AppColors.border),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(R.md),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: Sp.sm + 2),
            child: Center(
              child: Text(label,
                  style: (selected ? AppType.bodyStrong(color: AppColors.brand) : AppType.body(color: AppColors.textBody))),
            ),
          ),
        ),
      );
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.icon,
    required this.label,
    required this.unit,
    required this.value,
    required this.min,
    required this.max,
    this.step = 1,
    this.values,
    this.format,
    this.onChanged,
  });
  final IconData icon;
  final String label;
  final String unit;
  final int value;
  final int min;
  final int max;
  final int step;

  /// خياراتٌ محدّدة (التأكيد ٣/٥/١٠…٣٠) — ‑/+ ينتقلان للسابق/التالي بدل [step].
  final List<int>? values;
  final String Function(int)? format;
  final ValueChanged<int>? onChanged;

  int get _prev {
    final vs = values;
    if (vs == null) return (value - step).clamp(min, max);
    final lower = vs.where((v) => v < value);
    return lower.isEmpty ? value : lower.last;
  }

  int get _next {
    final vs = values;
    if (vs == null) return (value + step).clamp(min, max);
    final higher = vs.where((v) => v > value);
    return higher.isEmpty ? value : higher.first;
  }

  @override
  Widget build(BuildContext context) {
    final txt = format != null ? format!(value) : '$value${unit.isEmpty ? '' : ' $unit'}';
    Widget btn(IconData i, int to, String tip) {
      final ok = onChanged != null && to >= min && to <= max && to != value;
      return IconButton(
        tooltip: tip,
        visualDensity: VisualDensity.compact,
        onPressed: ok ? () => onChanged!(to) : null,
        icon: Icon(i, size: 18, color: ok ? AppColors.brand : AppColors.textHint),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        Icon(icon, size: 15, color: AppColors.textMid),
        const SizedBox(width: Sp.x6),
        Expanded(child: Text(label, style: AppType.body(color: AppColors.textHi), maxLines: 2)),
        btn(LucideIcons.minus, _prev, 'إنقاص'),
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 74),
          child: Text(txt, textAlign: TextAlign.center, style: AppType.bodyStrong(color: AppColors.brand)),
        ),
        btn(LucideIcons.plus, _next, 'زيادة'),
      ]),
    );
  }
}

class _QueueTile extends StatelessWidget {
  const _QueueTile({required this.st, required this.onTap});
  final ConnAutoStatus st;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pending = st.count('pending');
    final sub = [
      if (st.count('watching') > 0) 'تحت المراقبة ${st.count('watching')}',
      if (st.count('queued') > 0) 'بالطابور ${st.count('queued')}',
      'أُرسل اليوم ${st.count('sent_today')} من ${st.settings.dailyCap}',
    ].join(' · ');
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.lg), side: BorderSide(color: AppColors.border)),
      child: InkWell(
        borderRadius: BorderRadius.circular(R.lg),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(Sp.md),
          child: Row(children: [
            Icon(LucideIcons.inbox, size: 18, color: AppColors.brand),
            const SizedBox(width: Sp.sm),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(st.settings.mode == 'approval' ? 'بانتظار موافقتك' : 'تنبيهات المشتركين',
                    style: AppType.bodyStrong(color: AppColors.textHi)),
                const SizedBox(height: 2),
                Text(sub, style: AppType.micro(color: AppColors.textMid)),
              ]),
            ),
            if (pending > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: AppColors.brand, borderRadius: BorderRadius.circular(R.sm)),
                child: Text('$pending', style: AppType.labelBold(color: AppColors.onBrand)),
              ),
            const SizedBox(width: Sp.xs),
            Icon(LucideIcons.chevronLeft, size: 18, color: AppColors.textMid),
          ]),
        ),
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({required this.icon, required this.title, required this.subtitle, required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.lg), side: BorderSide(color: AppColors.border)),
        child: InkWell(
          borderRadius: BorderRadius.circular(R.lg),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(Sp.md),
            child: Row(children: [
              Icon(icon, size: 18, color: AppColors.brand),
              const SizedBox(width: Sp.sm),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: AppType.bodyStrong(color: AppColors.textHi)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: AppType.micro(color: AppColors.textMid)),
                ]),
              ),
              Icon(LucideIcons.chevronLeft, size: 18, color: AppColors.textMid),
            ]),
          ),
        ),
      );
}

/* ═════════════════════════════ القائمة ═════════════════════════════ */

/// نقرة تنبيه «بانتظار موافقتك» (الخادم: `type: conn_alert_pending`) ⇒ «تنبيهات المشتركين». false = ليس هذا التنبيه.
Future<bool> openConnAlertPush(NavigatorState nav, Map<String, String> data) async {
  if (data['type'] != 'conn_alert_pending') return false;
  await nav.push(MaterialPageRoute(builder: (_) => const ConnAutoQueueScreen()));
  return true;
}

class ConnAutoQueueScreen extends StatefulWidget {
  const ConnAutoQueueScreen({super.key});

  @override
  State<ConnAutoQueueScreen> createState() => _ConnAutoQueueScreenState();
}

class _ConnAutoQueueScreenState extends State<ConnAutoQueueScreen> {
  @override
  void initState() {
    super.initState();
    // من تنبيهٍ مباشرةً: الحالة (شريط المحاكاة) قد لا تكون محمّلة بعد
    ConnectionAutoApi.load().then((_) {
      if (mounted) setState(() {});
    });
  }

  static const _tabs = <(String, String)>[
    ('pending', 'بانتظار موافقتك'),
    ('queued', 'بالطابور'),
    ('sent,skipped', 'أُرسل'),
    ('watching', 'تحت المراقبة'),
    ('log', 'السجلّ'),
  ];

  @override
  Widget build(BuildContext context) {
    final st = ConnectionAutoApi.status.value;
    return DefaultTabController(
      length: _tabs.length,
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(
          backgroundColor: AppColors.surface,
          elevation: 0,
          scrolledUnderElevation: 0,
          iconTheme: IconThemeData(color: AppColors.textHi),
          title: Text('تنبيهات المشتركين', style: AppType.title(color: AppColors.textHi).copyWith(fontSize: 16)),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: AppColors.brand,
            unselectedLabelColor: AppColors.textMid,
            indicatorColor: AppColors.brand,
            tabs: [for (final t in _tabs) Tab(text: t.$2)],
          ),
        ),
        body: Column(children: [
          if (st.dryRun) Padding(padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, 0), child: _dryBanner()),
          Expanded(
            child: TabBarView(children: [
              for (final t in _tabs) t.$1 == 'log' ? const _LogList() : _CaseList(state: t.$1),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _CaseList extends StatefulWidget {
  const _CaseList({required this.state});
  final String state;

  @override
  State<_CaseList> createState() => _CaseListState();
}

class _CaseListState extends State<_CaseList> with AutomaticKeepAliveClientMixin {
  List<ConnAlertCase>? _items;
  String? _err;
  final Set<String> _busy = {};

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await ConnectionAutoApi.queue(widget.state);
      if (mounted) setState(() { _items = items; _err = null; });
    } catch (_) {
      if (mounted) setState(() => _err = 'تعذّر التحميل — اسحب للتحديث');
    }
  }

  Future<void> _act(String action, List<String> keys, {bool all = false}) async {
    if (action == 'send_now') {
      setState(() => _busy.addAll(keys));
      final r = await ConnectionAutoApi.sendNow(keys.single);
      if (!mounted) return;
      _busy.clear();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(!r.ok ? (r.message ?? 'تعذّر الإرسال الآن') : r.dry ? 'أُرسل (محاكاة — لم يصل للمشترك)' : 'أُرسل التنبيه للمشترك')));
      await _load();
      return;
    }
    setState(() => _busy.addAll(all ? (_items ?? const []).map((e) => e.key) : keys));
    final r = await ConnectionAutoApi.act(action, keys, all: all);
    if (!mounted) return;
    _busy.clear();
    final msg = !r.ok
        ? (r.message ?? 'تعذّر الآن')
        : switch (action) {
            'approve' => r.done > 1 ? 'سيُرسل لـ${r.done} مشتركاً تدريجيّاً ضمن ساعات الإرسال' : 'سيُرسل ضمن ساعات الإرسال',
            'skip' => 'تُجوهل — يرجع بعد مدّة التذكير إن بقيت المشكلة',
            'mute' => 'لن يُرسل لهذا المشترك',
            'unmute' => 'سُمح بالإرسال له',
            _ => 'تم',
          };
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final items = _items;
    if (items == null && _err == null) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.huge),
        children: [
          if (_err != null) Text(_err!, style: AppType.muted(color: AppColors.error)),
          if (widget.state == 'pending' && (items?.isNotEmpty ?? false)) ...[
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: AppColors.brand, foregroundColor: AppColors.onBrand, minimumSize: const Size.fromHeight(46)),
              onPressed: _busy.isEmpty ? () => _act('approve', const [], all: true) : null,
              icon: const Icon(LucideIcons.sendHorizontal, size: 18),
              label: Text('أرسل للكلّ (${items!.where((e) => !e.muted).length})'),
            ),
            const SizedBox(height: Sp.md),
          ],
          if (items != null && items.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: Sp.huge),
              child: Column(children: [
                Icon(LucideIcons.circleCheck, size: 36, color: AppColors.successDot),
                const SizedBox(height: Sp.sm),
                Text(_emptyText, textAlign: TextAlign.center, style: AppType.muted(color: AppColors.textMid)),
              ]),
            ),
          for (final c in items ?? const <ConnAlertCase>[]) ...[
            _CaseCard(c: c, busy: _busy.contains(c.key), onAct: (a) => _act(a, [c.key])),
            const SizedBox(height: Sp.sm),
          ],
        ],
      ),
    );
  }

  String get _emptyText => switch (widget.state) {
        'pending' => 'لا شيء بانتظار موافقتك',
        'queued' => 'الطابور فارغ',
        'watching' => 'لا مشتركين تحت المراقبة — المشكلة تُراقَب حتى تتأكّد بقراءةٍ ثانية',
        _ => 'لا رسائل بعد',
      };
}

/// «تحت المراقبة»: هذه أوّل قراءة — متى تتأكّد، وأنّ «أرسل الآن» يرسل له وحده الآن (٣ نوفمبر — المالك).
String _watchNote(ConnAlertCase c) {
  final mins = ConnectionAutoApi.status.value.settings.confirmMin;
  final due = c.firstBadAt?.add(Duration(minutes: mins));
  final left = due?.difference(DateTime.now());
  final when = left == null
      ? 'بعد $mins دقيقة من أوّل قراءة'
      : left.inMinutes >= 1
          ? 'بعد ${left.inMinutes} دقيقة تقريباً'
          : 'بأوّل قراءةٍ قادمة';
  return 'هذه أوّل قراءةٍ سيّئة — تتأكّد بقراءةٍ ثانية $when ثمّ تنتقل لـ«بانتظار موافقتك». '
      'تقدر ترسل له التنبيه الآن مباشرةً بـ«أرسل الآن».';
}

class _CaseCard extends StatelessWidget {
  const _CaseCard({required this.c, required this.busy, required this.onAct});
  final ConnAlertCase c;
  final bool busy;
  final ValueChanged<String> onAct;

  @override
  Widget build(BuildContext context) {
    final when = <String>[
      if (c.state == 'watching' && c.firstBadAt != null) 'أوّل قراءة سيّئة ${timeAgoAr(c.firstBadAt)}',
      if (c.confirmedAt != null && c.state != 'watching') 'تأكّدت ${timeAgoAr(c.confirmedAt)}',
      if (c.sends > 0) 'أُرسل ${c.sends} ${c.sends == 1 ? 'مرّة' : 'مرّات'}${c.lastSentAt != null ? '، آخرها ${timeAgoAr(c.lastSentAt)}' : ''}',
      if (c.lastReadingAt != null) 'آخر قراءة ${timeAgoAr(c.lastReadingAt)}',
    ].join(' · ');
    Widget act(String a, String label, IconData i, {bool primary = false, Color? color}) => Padding(
          padding: const EdgeInsetsDirectional.only(end: Sp.x6),
          child: primary
              ? FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: AppColors.brand, foregroundColor: AppColors.onBrand, visualDensity: VisualDensity.compact),
                  onPressed: busy ? null : () => onAct(a),
                  icon: Icon(i, size: 16),
                  label: Text(label),
                )
              : OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: color ?? AppColors.textBody, visualDensity: VisualDensity.compact),
                  onPressed: busy ? null : () => onAct(a),
                  icon: Icon(i, size: 16),
                  label: Text(label),
                ),
        );
    return _box(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SizedBox(height: Sp.xs),
        Row(children: [
          Expanded(child: Text(c.title, style: AppType.bodyStrong(color: AppColors.textHi), maxLines: 1, overflow: TextOverflow.ellipsis)),
          if (c.muted)
            Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(LucideIcons.bellOff, size: 14, color: AppColors.textMid),
              const SizedBox(width: 4),
              Text('لا يُرسل له', style: AppType.micro(color: AppColors.textMid)),
            ]),
        ]),
        if ((c.username ?? '').isNotEmpty && c.username != c.title)
          Text(c.username!, style: AppType.micro(color: AppColors.textMid)),
        const SizedBox(height: Sp.x6),
        Wrap(spacing: Sp.x6, runSpacing: Sp.x6, children: [
          for (final p in c.problems)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.warningSoftBg,
                borderRadius: BorderRadius.circular(R.sm),
                border: Border.all(color: AppColors.warningSoftBorder),
              ),
              child: Text('${p.label}: ${p.text}', style: AppType.micro(color: AppColors.warningOnSoft)),
            ),
        ]),
        if (when.isNotEmpty) ...[
          const SizedBox(height: Sp.x6),
          Text(when, style: AppType.micro(color: AppColors.textMid)),
        ],
        if (c.state == 'watching') ...[
          const SizedBox(height: Sp.x6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: Sp.sm, vertical: Sp.x6),
            decoration: BoxDecoration(color: AppColors.infoSoftBg, borderRadius: BorderRadius.circular(R.sm), border: Border.all(color: AppColors.infoSoftBorder)),
            child: Text(_watchNote(c), style: AppType.micro(color: AppColors.textBody)),
          ),
        ],
        if (c.lastError != null) ...[
          const SizedBox(height: 2),
          Text(c.lastError == 'no_phone' ? 'لا رقم هاتف لهذا المشترك' : 'لم يُرسل: ${c.lastError}',
              style: AppType.micro(color: AppColors.error)),
        ],
        const SizedBox(height: Sp.sm),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            if (c.state == 'pending' && !c.muted) ...[
              act('approve', 'أرسل', LucideIcons.send, primary: true),
              act('skip', 'تجاهل', LucideIcons.clock),
            ],
            if (c.state == 'watching' && !c.muted) act('send_now', 'أرسل الآن', LucideIcons.send, primary: true),
            if (['sent', 'skipped'].contains(c.state) && !c.muted) act('requeue', 'ذكّره الآن', LucideIcons.repeat),
            if (!c.muted && c.state != 'watching') act('mute', 'لا ترسل له', LucideIcons.bellOff, color: AppColors.error),
            if (c.muted) act('unmute', 'اسمح بالإرسال له', LucideIcons.bell),
            if (c.state == 'queued') Text('يُرسل ضمن ساعات الإرسال', style: AppType.micro(color: AppColors.textMid)),

          ]),
        ),
        const SizedBox(height: Sp.xs),
      ]),
    );
  }
}

class _LogList extends StatefulWidget {
  const _LogList();

  @override
  State<_LogList> createState() => _LogListState();
}

class _LogListState extends State<_LogList> with AutomaticKeepAliveClientMixin {
  List<ConnAlertLogEntry>? _items;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await ConnectionAutoApi.log();
      if (mounted) setState(() => _items = items);
    } catch (_) {
      if (mounted) setState(() => _items = const []);
    }
  }

  static const _action = <String, String>{
    'confirmed': 'تأكّدت مشكلة',
    'approved': 'وافقتَ على الإرسال',
    'sent': 'أُرسلت رسالة',
    'sim_sent': 'أُرسلت (محاكاة — لم تصل)',
    'failed': 'تعذّر الإرسال',
    'resolved': 'حُلّت المشكلة',
    'reminder': 'حان التذكير',
    'skip': 'تجاهلتَه',
    'mute': 'منعتَ الإرسال له',
    'unmute': 'سمحتَ بالإرسال له',
    'requeue': 'طلبتَ تذكيره الآن',
  };

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final items = _items;
    if (items == null) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.huge),
        itemCount: items.isEmpty ? 1 : items.length,
        separatorBuilder: (_, __) => Divider(height: 1, color: AppColors.divider),
        itemBuilder: (_, i) {
          if (items.isEmpty) {
            return Padding(
              padding: const EdgeInsets.only(top: Sp.huge),
              child: Text('السجلّ فارغ', textAlign: TextAlign.center, style: AppType.muted(color: AppColors.textMid)),
            );
          }
          final e = items[i];
          final kinds = e.kinds.map((k) => _kindLabel[k] ?? k).join('، ');
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: Sp.sm),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${_action[e.action] ?? e.action}${e.name != null ? ' — ${e.name}' : ''}',
                      style: AppType.body(color: e.action == 'failed' ? AppColors.error : AppColors.textHi)),
                  if (kinds.isNotEmpty || (e.detail ?? '').isNotEmpty)
                    Text([if (kinds.isNotEmpty) kinds, if ((e.detail ?? '').isNotEmpty && e.action == 'failed') e.detail!].join(' · '),
                        style: AppType.micro(color: AppColors.textMid)),
                ]),
              ),
              Text(timeAgoAr(e.at), style: AppType.micro(color: AppColors.textMid)),
            ]),
          );
        },
      ),
    );
  }
}
