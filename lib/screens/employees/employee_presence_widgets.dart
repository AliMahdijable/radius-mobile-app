import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/employee_presence_api.dart';
import '../../core/platform/app_platform.dart';
import '../../core/util/ar_date.dart';
import '../../core/widgets/app_sheet.dart';
import '../../core/widgets/design_sheet.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';

/// «الموظف المتّصل الآن» (١٤ نوفمبر): نقطة الحال، ورقة «نشاط الموظفين» (الجميع بسطرٍ لكلٍّ منهم)، وورقة «نشاط الموظف» (اليوم وثلاثون
/// يوماً). للمدير وحده — الخادم يرفض غيره. كلّ ما يُعرض من الخادم؛ بلا موقعٍ ولا محتوى.

/// نقطة «متّصل الآن» الخضراء (أو رماديّة لغير المتّصل حين [showOffline]).
class PresenceDot extends StatelessWidget {
  const PresenceDot({super.key, required this.online, this.size = 10, this.showOffline = false, this.ring});
  final bool online;
  final double size;
  final bool showOffline;

  /// لون الحلقة حولها (خلفيّة ما تجلس عليه) — null بلا حلقة.
  final Color? ring;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    if (!online && !showOffline) return const SizedBox.shrink();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        // «النقطة الحيّة» نفسها التي تحملها حبّة «متصل منذ…» عند المشتركين
        color: online ? AppColors.successDot : AppColors.textLow.withValues(alpha: 0.5),
        shape: BoxShape.circle,
        border: ring == null ? null : Border.all(color: ring!, width: 1.5),
      ),
    );
  }
}

// ─────────────────────────── نشاط الموظفين (الجميع) ───────────────────────────

/// «نشاط الموظفين»: كلّ موظّفي الصفحة — المتّصلون أوّلاً — بسطرٍ لكلٍّ منهم («متّصل الآن · 12 عمليّة اليوم»). النقر يفتح نشاطه.
Future<void> showEmployeesPresenceSheet(BuildContext context, {required PresenceList list}) {
  return showAppSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.scrim,
    builder: (_) => EmployeesPresenceSheet(initial: list),
  );
}

class EmployeesPresenceSheet extends StatefulWidget {
  const EmployeesPresenceSheet({super.key, required this.initial, this.loader});
  final PresenceList initial;

  /// للاختبار: مصدرٌ بديل للقائمة.
  final Future<PresenceList?> Function()? loader;
  @override
  State<EmployeesPresenceSheet> createState() => _EmployeesPresenceSheetState();
}

class _EmployeesPresenceSheetState extends State<EmployeesPresenceSheet> {
  late PresenceList _list = widget.initial;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // تتجدّد كلّ دقيقة ما دامت مفتوحة (لا مؤقّت في اختبارات الواجهة)
    if (!AppPlatform.isUnderTest) _timer = Timer.periodic(const Duration(seconds: 60), (_) => _reload());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _reload() async {
    final l = await (widget.loader ?? EmployeePresenceApi.list)();
    if (!mounted || l == null) return;
    setState(() => _list = l);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    // المتّصلون أوّلاً، ثمّ الأحدث ظهوراً، والمعطَّلون آخراً
    final rows = [..._list.rows]..sort((a, b) {
        if (a.online != b.online) return a.online ? -1 : 1;
        if (a.active != b.active) return a.active ? -1 : 1;
        final x = a.lastSeenAt?.millisecondsSinceEpoch ?? 0;
        final y = b.lastSeenAt?.millisecondsSinceEpoch ?? 0;
        return y.compareTo(x);
      });
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.activity,
        title: 'نشاط الموظفين',
        subtitle: '${_list.onlineCount} متّصل الآن من ${_list.total}',
        onClose: () => Navigator.of(context).pop(),
      ),
      body: rows.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: Sp.lg),
              child: Center(child: Text('لا موظفين في هذه الصفحة بعد', style: AppType.muted())),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final r in rows)
                  Container(
                    margin: const EdgeInsets.only(bottom: Sp.x6),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(R.md),
                      border: Border.all(color: r.online ? AppColors.success.withValues(alpha: 0.55) : AppColors.border),
                    ),
                    child: InkWell(
                      key: ValueKey('presence-row-${r.employeeId}'),
                      borderRadius: BorderRadius.circular(R.md),
                      onTap: () => showEmployeeActivitySheet(context, employeeId: r.employeeId, name: r.displayName),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.sm),
                        child: Row(
                          children: [
                            PresenceDot(online: r.online, showOffline: true),
                            const SizedBox(width: Sp.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    r.active ? r.displayName : '${r.displayName} (معطّل)',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppType.bodyBold(color: r.active ? AppColors.textHi : AppColors.textLow),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    r.line(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppType.micro(color: r.online ? AppColors.success : AppColors.textMid),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: Sp.sm),
                            Icon(Icons.arrow_back_ios_new_rounded, size: 12, color: AppColors.textLow),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (_list.opsUnavailable)
                  Text('تعذّرت قراءة العمليّات الآن — الظهور كما هو.', style: AppType.micro(color: AppColors.warning)),
                const SizedBox(height: Sp.x6),
                Text(
                  '«متّصل الآن» = برنامجه مفتوح ويعمل خلال آخر دقيقتين. الموظف لا يصله إشعار.',
                  style: AppType.micro(color: AppColors.textLow),
                ),
              ],
            ),
    );
  }
}

// ─────────────────────────── نشاط الموظف (واحد) ───────────────────────────

/// «نشاط الموظف»: حاله الآن ومنصّته، نشاط اليوم (أوّل ظهورٍ وآخره، مدّة الاستعمال، العمليّات بأنواعها)، آخر عمليّة، وسجلّ ثلاثين يوماً.
Future<void> showEmployeeActivitySheet(BuildContext context, {required int employeeId, required String name}) {
  return showAppSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.scrim,
    builder: (_) => EmployeeActivitySheet(employeeId: employeeId, name: name),
  );
}

class EmployeeActivitySheet extends StatefulWidget {
  const EmployeeActivitySheet({super.key, required this.employeeId, required this.name, this.loader});
  final int employeeId;
  final String name;

  /// للاختبار: مصدرٌ بديل للتفصيل.
  final Future<({PresenceDetail? data, String? message})> Function()? loader;
  @override
  State<EmployeeActivitySheet> createState() => _EmployeeActivitySheetState();
}

class _EmployeeActivitySheetState extends State<EmployeeActivitySheet> {
  PresenceDetail? _d;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _d == null;
      _error = null;
    });
    final r = await (widget.loader ?? () => EmployeePresenceApi.detail(widget.employeeId))();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _d = r.data ?? _d;
      _error = r.data == null ? (r.message ?? 'تعذّر تحميل نشاط الموظف') : null;
    });
  }

  Widget _fact(String label, String value, {Key? valueKey}) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.sm),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(R.md),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.micro(color: AppColors.textLow)),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(value, key: valueKey, maxLines: 1, style: AppType.bodyBold(color: AppColors.textHi)),
              ),
            ],
          ),
        ),
      );

  Widget _body(PresenceDetail d) {
    final r = d.row;
    final today = d.todayRow;
    final ops = r.opsToday;
    return Column(
      key: const ValueKey('emp-activity'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.sm),
          decoration: BoxDecoration(
            color: r.online ? AppColors.successSoftBg : AppColors.surface,
            borderRadius: BorderRadius.circular(R.md),
            border: Border.all(color: r.online ? AppColors.success.withValues(alpha: 0.55) : AppColors.border),
          ),
          child: Row(
            children: [
              PresenceDot(online: r.online, showOffline: true),
              const SizedBox(width: Sp.sm),
              Expanded(
                child: Text(
                  r.seenText(),
                  key: const ValueKey('emp-activity-seen'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.bodyBold(color: r.online ? AppColors.success : AppColors.textMid),
                ),
              ),
              if (r.platformLabel != null) ...[
                const SizedBox(width: Sp.sm),
                Icon(LucideIcons.monitorSmartphone, size: 13, color: AppColors.textMid),
                const SizedBox(width: Sp.xs),
                Text(
                  r.appBuild == null ? r.platformLabel! : '${r.platformLabel} · ${r.appBuild}',
                  style: AppType.micro(color: AppColors.textMid),
                ),
              ],
            ],
          ),
        ),
        if (!r.active) ...[
          const SizedBox(height: Sp.x6),
          Text('حسابه معطَّل — لا يُعدّ متّصلاً.', style: AppType.micro(color: AppColors.warning)),
        ],
        const SizedBox(height: Sp.lg),
        Text('نشاط اليوم', style: AppType.bodyBold(color: AppColors.textHi)),
        const SizedBox(height: Sp.sm),
        Row(children: [
          _fact('أوّل ظهور', presenceClock(today?.firstSeenAt)),
          const SizedBox(width: Sp.sm),
          _fact('آخر ظهور', presenceClock(today?.lastSeenAt)),
        ]),
        const SizedBox(height: Sp.sm),
        Row(children: [
          _fact('مدّة الاستعمال', presenceUsage(r.minutesToday)),
          const SizedBox(width: Sp.sm),
          _fact('العمليّات', ops == null ? '—' : '$ops', valueKey: const ValueKey('emp-activity-ops')),
        ]),
        if (d.opsByType.isNotEmpty) ...[
          const SizedBox(height: Sp.sm),
          Wrap(
            spacing: Sp.x6,
            runSpacing: Sp.x6,
            children: [
              for (final t in d.opsByType) ToneChip(label: '${t.label} ${t.count}', dense: true),
            ],
          ),
        ],
        const SizedBox(height: Sp.sm),
        Row(
          children: [
            Icon(LucideIcons.clock, size: 13, color: AppColors.textLow),
            const SizedBox(width: Sp.x6),
            Expanded(
              child: Text(
                r.lastOp == null ? 'لا عمليّة مسجّلة باسمه بعد' : 'آخر عمليّة: ${r.lastOp!.text()}',
                key: const ValueKey('emp-activity-last-op'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.micro(color: AppColors.textMid),
              ),
            ),
          ],
        ),
        if (d.opsUnavailable) ...[
          const SizedBox(height: Sp.x6),
          Text('تعذّرت قراءة العمليّات الآن — الظهور كما هو.', style: AppType.micro(color: AppColors.warning)),
        ],
        const SizedBox(height: Sp.lg),
        Text('آخر ${d.keepDays} يوماً', style: AppType.bodyBold(color: AppColors.textHi)),
        const SizedBox(height: Sp.sm),
        if (d.days.length <= 1 && today?.lastSeenAt == null && (today?.ops ?? 0) == 0)
          Text('لا ظهور ولا عمليّة في هذه المدّة بعد.', style: AppType.micro(color: AppColors.textLow))
        else
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(R.md),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                for (var i = 0; i < d.days.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: AppColors.border),
                  _dayRow(d.days[i], d.today),
                ],
              ],
            ),
          ),
        const SizedBox(height: Sp.md),
        Text(
          '«متّصل الآن» = برنامجه مفتوح ويعمل خلال آخر دقيقتين. الظهور من فتح البرنامج واستعماله، والعمليّات من سجلّ الحركات باسمه — '
          'بلا موقعٍ ولا محتوى. الموظف لا يصله إشعار.',
          style: AppType.micro(color: AppColors.textLow),
        ),
      ],
    );
  }

  Widget _dayRow(PresenceDay x, String today) => Padding(
        key: ValueKey('emp-activity-day-${x.day}'),
        padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.sm),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    x.day == today ? 'اليوم' : iqDateLabel(x.day),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.body(color: AppColors.textHi),
                  ),
                  Text(
                    x.firstSeenAt == null
                        ? 'بلا ظهورٍ مسجَّل'
                        : '${presenceClock(x.firstSeenAt)} – ${presenceClock(x.lastSeenAt)} · ${presenceUsage(x.minutes)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.micro(color: AppColors.textMid),
                  ),
                ],
              ),
            ),
            const SizedBox(width: Sp.sm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(x.ops == null ? '—' : '${x.ops}', style: AppType.bodyBold(color: AppColors.textHi)),
                Text('عمليّة', style: AppType.micro(color: AppColors.textLow)),
              ],
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final d = _d;
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.activity,
        title: 'نشاط الموظف',
        subtitle: widget.name,
        onClose: () => Navigator.of(context).pop(),
      ),
      body: d != null
          ? _body(d)
          : _loading
              ? const Padding(padding: EdgeInsets.all(Sp.xl), child: Center(child: CircularProgressIndicator()))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(_error ?? 'تعذّر تحميل نشاط الموظف', style: AppType.body(color: AppColors.textMid)),
                    const SizedBox(height: Sp.md),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: OutlinedButton(onPressed: _load, child: const Text('إعادة المحاولة')),
                    ),
                  ],
                ),
    );
  }
}
