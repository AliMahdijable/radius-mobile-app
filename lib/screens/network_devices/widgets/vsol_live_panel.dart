import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/network_devices_api.dart';
import '../../../api/vsol_olt_api.dart';
import '../../../models/network_device.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import 'expandable_section.dart';

/// لوحة مراقبة حيّة لـ**OLT من VSOL** عبر SNMP.
///
/// بنيتها من بنية اللوحات الأخرى: رأسٌ حيّ، ثمّ شريط الجهاز، ثمّ كروت
/// المقاييس، ثمّ أقسامٌ قابلة للطيّ. المستخدم ينتقل بين جهازٍ وآخر في
/// الشاشة نفسها، فاختلاف اللغة البصريّة يُقرأ عطلاً لا تنوّعاً.
///
/// وما يخصّ الـOLT وحده — منافذ PON والمشتركون — داخل القوالب نفسها.
class VsolLivePanel extends StatefulWidget {
  const VsolLivePanel({super.key, required this.device});
  final NetworkDevice device;

  @override
  State<VsolLivePanel> createState() => _VsolLivePanelState();
}

class _VsolLivePanelState extends State<VsolLivePanel>
    with WidgetsBindingObserver {
  VsolOltStats? _stats;
  String? _error;
  DateTime? _lastFetch;
  Timer? _timer;
  bool _loading = false;
  bool _monitoring = true;
  bool _foreground = true;
  int _gen = 0;

  bool _onlineOnly = false;
  String _query = '';

  /// المسحة الكاملة تستغرق ~٢٫٢ ثانية على جهازٍ فعليّ (‏٣٨ واجهة ×
  /// ستّة أعمدة). فنبضةٌ أسرع من ذلك تُنتج طابوراً لا تحديثاً.
  static const _interval = Duration(seconds: 12);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fetch();
    _arm();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _gen++;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final fg = state == AppLifecycleState.resumed;
    if (fg == _foreground) return;
    _foreground = fg;
    if (fg) {
      _fetch();
      _arm();
    } else {
      _timer?.cancel();
    }
  }

  void _arm() {
    _timer?.cancel();
    if (!_monitoring || !_foreground) return;
    _timer = Timer.periodic(_interval, (_) => _fetch());
  }

  Future<void> _fetch() async {
    if (_loading) return;
    final d = widget.device;
    final gen = ++_gen;
    if (mounted) setState(() => _loading = true);

    try {
      final creds = await NetworkDevicesApi.getCredentials(d.id);
      if (!mounted || gen != _gen) return;
      // الـcommunity تُحفَظ تحت `community`، ويُقبل `pass` لمن أدخلها
      // في حقل كلمة المرور قبل أن يوجد الحقل المخصّص.
      final community =
          (creds['community'] ?? creds['pass'] ?? '').toString().trim();
      if (community.isEmpty) {
        setState(() {
          _loading = false;
          _error = 'أدخل الـcommunity من إعدادات الجهاز';
        });
        return;
      }

      final s = await VsolOltApi.fetchStats(
        host: d.ip,
        port: d.apiPort ?? 161,
        community: community,
        onPartialReady: (partial) {
          if (!mounted || gen != _gen) return;
          if (_stats == null) setState(() => _stats = partial);
        },
      );
      if (!mounted || gen != _gen) return;
      setState(() {
        _loading = false;
        _error = null;
        _stats = s;
        _lastFetch = DateTime.now();
      });
    } on VsolException catch (e) {
      if (!mounted || gen != _gen) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted || gen != _gen) return;
      setState(() {
        _loading = false;
        _error = 'تعذّرت القراءة: $e';
      });
    }
  }

  // ══════════════════════════════════════════════════════════
  // البناء
  // ══════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final s = _stats;
    if (s == null && _error == null) {
      return Container(
        padding: const EdgeInsets.all(Sp.md),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(R.lg),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: AppColors.brand),
          ),
          const SizedBox(width: 10),
          Text('جاري قراءة الـOLT…',
              style: AppType.body(color: AppColors.textMid)),
        ]),
      );
    }

    return Column(children: [
      Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(R.lg),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(children: [
          _header(),
          if (_error != null) _errorBox(),
          if (s != null) ...[
            RepaintBoundary(child: _banner(s)),
            RepaintBoundary(child: _metrics(s)),
            const SizedBox(height: Sp.md),
          ],
        ]),
      ),
      if (s != null) ..._sections(s),
    ]);
  }

  Widget _header() => Padding(
        padding: const EdgeInsets.all(Sp.md),
        child: Row(children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.brandSoftBg,
              borderRadius: BorderRadius.circular(R.sm),
            ),
            child: Icon(LucideIcons.activity, size: 16, color: AppColors.brand),
          ),
          const SizedBox(width: 10),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('مراقبة حيّة (OLT · SNMP)', style: AppType.bodyBold()),
              const SizedBox(height: 2),
              Row(children: [
                if (_monitoring) ...[
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                        color: AppColors.success, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 4),
                ],
                Text(
                  _monitoring ? 'مباشر · كل ${_interval.inSeconds}s' : 'متوقّف',
                  style: TextStyle(
                      fontSize: 10.5, height: 1.3, color: AppColors.textMid),
                ),
                if (_lastFetch != null) ...[
                  Text(' • ',
                      style: TextStyle(
                          fontSize: 10.5,
                          height: 1.3,
                          color: AppColors.textLow)),
                  Text('آخر: ${_clock(_lastFetch!)}',
                      style: TextStyle(
                          fontSize: 10.5,
                          height: 1.3,
                          color: AppColors.textLow)),
                ],
              ]),
            ]),
          ),
          IconButton(
            icon: const Icon(LucideIcons.refreshCw, size: 16),
            onPressed: _loading ? null : _fetch,
            tooltip: 'تحديث الآن',
            color: AppColors.brand,
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            icon:
                Icon(_monitoring ? LucideIcons.pause : LucideIcons.play, size: 16),
            onPressed: () {
              setState(() => _monitoring = !_monitoring);
              _arm();
              if (_monitoring) _fetch();
            },
            tooltip: _monitoring ? 'إيقاف' : 'استئناف',
            color: AppColors.textMid,
            visualDensity: VisualDensity.compact,
          ),
        ]),
      );

  Widget _errorBox() => Container(
        margin: const EdgeInsets.fromLTRB(Sp.md, 0, Sp.md, Sp.md),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.dangerSoftBg,
          borderRadius: BorderRadius.circular(R.sm),
          border: Border.all(color: AppColors.dangerSoftBorder),
        ),
        child: Row(children: [
          Icon(LucideIcons.triangleAlert, size: 14, color: AppColors.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(_error!, style: AppType.micro(color: AppColors.error)),
          ),
        ]),
      );

  Widget _banner(VsolOltStats s) => Container(
        margin: const EdgeInsets.fromLTRB(Sp.md, Sp.md, Sp.md, 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.brandSoftBg,
          borderRadius: BorderRadius.circular(R.sm),
        ),
        child: Row(children: [
          Icon(LucideIcons.server, size: 18, color: AppColors.brand),
          const SizedBox(width: 8),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                s.sysName?.isNotEmpty == true
                    ? s.sysName!
                    : widget.device.name,
                style: TextStyle(
                    fontSize: 11,
                    height: 1.25,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textHi),
                overflow: TextOverflow.ellipsis,
              ),
              Text(s.sysDescr ?? 'VSOL OLT',
                  style: AppType.micro(color: AppColors.textMid),
                  overflow: TextOverflow.ellipsis),
            ]),
          ),
          if (s.uptime != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.brandSoftBg,
                borderRadius: BorderRadius.circular(R.sm),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(LucideIcons.clock, size: 9, color: AppColors.brand),
                const SizedBox(width: 3),
                Text(_uptime(s.uptime!),
                    style: AppType.microBold(color: AppColors.brand)),
              ]),
            ),
        ]),
      );

  Widget _metrics(VsolOltStats s) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: Sp.md),
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(
                child: _tile(
              LucideIcons.users,
              'المشتركون',
              '${s.onusOnline}',
              '/${s.onusTotal}',
              s.onusOnline > 0 ? AppColors.success : AppColors.textLow,
            )),
            const SizedBox(width: 8),
            Expanded(
                child: _tile(
              LucideIcons.splitSquareVertical,
              'منافذ PON',
              '${s.ponUp}',
              '/${s.ponPorts.length}',
              AppColors.brand,
            )),
            const SizedBox(width: 8),
            Expanded(
                child: _tile(
              LucideIcons.arrowUpDown,
              // ⚠️ من منافذ PON لا من جمع المشتركين: ما يمرّ على ONU
              // يمرّ على منفذه، فجمعهما يعدّ البايت مرّتين.
              'ترفك PON',
              _bytes(s.ponRxBytes + s.ponTxBytes),
              '',
              AppColors.brand,
            )),
          ]),
        ),
      );

  List<Widget> _sections(VsolOltStats s) {
    final shown = s.onus.where(_match).toList();
    return [
      if (s.ponPorts.isNotEmpty) ...[
        const SizedBox(height: Sp.md),
        ExpandableSection(
          key: PageStorageKey('vsol-${widget.device.id}-pon'),
          initiallyExpanded: true,
          header: Row(children: [
            Icon(LucideIcons.splitSquareVertical,
                size: 14, color: AppColors.brand),
            const SizedBox(width: 6),
            Text('منافذ PON (${s.ponUp}/${s.ponPorts.length})',
                style: AppType.bodyBold()),
          ]),
          content: RepaintBoundary(
            child: Column(children: [for (final p in s.ponPorts) _ponRow(p)]),
          ),
        ),
      ],
      const SizedBox(height: Sp.md),
      ExpandableSection(
        key: PageStorageKey('vsol-${widget.device.id}-onu'),
        initiallyExpanded: true,
        header: Row(children: [
          Icon(LucideIcons.users, size: 14, color: AppColors.brand),
          const SizedBox(width: 6),
          Text('المشتركون (${shown.length})', style: AppType.bodyBold()),
        ]),
        content: RepaintBoundary(child: _onuContent(shown)),
      ),
      if (s.uplinks.isNotEmpty) ...[
        const SizedBox(height: Sp.md),
        ExpandableSection(
          key: PageStorageKey('vsol-${widget.device.id}-up'),
          header: Row(children: [
            Icon(LucideIcons.network, size: 14, color: AppColors.brand),
            const SizedBox(width: 6),
            Text('منافذ الصعود (${s.uplinks.where((u) => u.up).length}'
                '/${s.uplinks.length})',
                style: AppType.bodyBold()),
          ]),
          content: Column(children: [for (final u in s.uplinks) _upRow(u)]),
        ),
      ],
    ];
  }

  bool _match(VsolOnu o) {
    if (_onlineOnly && !o.online) return false;
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return '${o.label} ${o.mac ?? ''}'.toLowerCase().contains(q);
  }

  Widget _ponRow(VsolPonPort p) => Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surfaceSunken,
          borderRadius: BorderRadius.circular(R.sm),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(children: [
          Container(
            width: 4,
            height: 26,
            decoration: BoxDecoration(
              color: p.up ? AppColors.success : AppColors.textLow,
              borderRadius: BorderRadius.circular(R.sm),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.label, style: AppType.rowLabelBold()),
              Text('${p.onuOnline}/${p.onuTotal} مشترك',
                  style: AppType.micro(color: AppColors.textMid)),
            ]),
          ),
          Directionality(
            textDirection: TextDirection.ltr,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('▼ ${_bytes(p.rxBytes)}',
                    style: AppType.micro(color: AppColors.success)),
                Text('▲ ${_bytes(p.txBytes)}',
                    style: AppType.micro(color: AppColors.brand)),
              ],
            ),
          ),
        ]),
      );

  Widget _onuContent(List<VsolOnu> shown) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: SizedBox(
                height: 34,
                child: TextField(
                  style: AppType.micro(),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'ابحث برقم المشترك أو MAC…',
                    hintStyle: AppType.micro(color: AppColors.textLow),
                    prefixIcon: Icon(LucideIcons.search,
                        size: 14, color: AppColors.textLow),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(R.sm),
                      borderSide: BorderSide(color: AppColors.border),
                    ),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilterChip(
              label: Text('المتّصلون', style: AppType.micro()),
              selected: _onlineOnly,
              onSelected: (v) => setState(() => _onlineOnly = v),
              visualDensity: VisualDensity.compact,
            ),
          ]),
          const SizedBox(height: 8),
          if (shown.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text('لا مشتركين مطابقين',
                  style: AppType.micro(color: AppColors.textLow)),
            )
          else
            for (final o in shown) _onuRow(o),
        ],
      );

  Widget _onuRow(VsolOnu o) => Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surfaceSunken,
          borderRadius: BorderRadius.circular(R.sm),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(children: [
          Container(
            width: 4,
            height: 26,
            decoration: BoxDecoration(
              color: o.online ? AppColors.success : AppColors.textLow,
              borderRadius: BorderRadius.circular(R.sm),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Directionality(
                textDirection: TextDirection.ltr,
                child: Text(o.label,
                    textAlign: TextAlign.left, style: AppType.rowLabelBold()),
              ),
              // العنوان للمتّصل وحده — انظر `VsolOnu.mac`.
              Directionality(
                textDirection: TextDirection.ltr,
                child: Text(
                  o.mac ?? (o.online ? '—' : 'غير متّصل'),
                  textAlign: TextAlign.left,
                  style: AppType.micro(color: AppColors.textLow),
                ),
              ),
            ]),
          ),
          if (o.online)
            Directionality(
              textDirection: TextDirection.ltr,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('▼ ${_bytes(o.rxBytes)}',
                      style: AppType.micro(color: AppColors.success)),
                  Text('▲ ${_bytes(o.txBytes)}',
                      style: AppType.micro(color: AppColors.brand)),
                ],
              ),
            ),
        ]),
      );

  Widget _upRow(VsolUplink u) => Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surfaceSunken,
          borderRadius: BorderRadius.circular(R.sm),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(children: [
          Container(
            width: 4,
            height: 22,
            decoration: BoxDecoration(
              color: u.up ? AppColors.success : AppColors.textLow,
              borderRadius: BorderRadius.circular(R.sm),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(u.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.rowLabelBold()),
          ),
          Text(u.up ? '${u.speedMbps}M' : '—',
              style: AppType.microBold(
                  color: u.up ? AppColors.textMid : AppColors.textLow)),
        ]),
      );

  Widget _tile(IconData icon, String label, String value, String unit,
          Color color) =>
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.surfaceSunken,
          borderRadius: BorderRadius.circular(R.sm),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(children: [
              Icon(icon, size: 12, color: color),
              const SizedBox(width: 4),
              Flexible(
                child: Text(label,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.microBold(color: AppColors.textMid)),
              ),
            ]),
            const SizedBox(height: 6),
            // اتّجاهٌ لاتينيٌّ مفروض — وإلّا رُسمت «13/26» مقلوبةً
            // في صفحةٍ عربيّة.
            Directionality(
              textDirection: TextDirection.ltr,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Flexible(
                    child: Text(value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            height: 1,
                            color: color)),
                  ),
                  if (unit.isNotEmpty) Text(unit, style: AppType.muted()),
                ],
              ),
            ),
          ],
        ),
      );

  // ══════════════════════════════════════════════════════════
  // تنسيق
  // ══════════════════════════════════════════════════════════

  /// «٦٨ يوماً و٢ ساعة» — تُقرأ ولا تُفكّ.
  static String _uptime(Duration d) {
    if (d.inDays > 0) {
      final h = d.inHours % 24;
      return h > 0 ? '${d.inDays}ي $hس' : '${d.inDays} يوماً';
    }
    if (d.inHours > 0) return '${d.inHours}س ${d.inMinutes % 60}د';
    return '${d.inMinutes} دقيقة';
  }

  static String _bytes(int b) {
    if (b <= 0) return '0';
    const u = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];
    var v = b.toDouble();
    var i = 0;
    while (v >= 1024 && i < u.length - 1) {
      v /= 1024;
      i++;
    }
    return '${v.toStringAsFixed(v >= 100 || i == 0 ? 0 : 1)}${u[i]}';
  }

  static String _clock(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';
}
