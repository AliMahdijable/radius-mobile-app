import 'package:flutter/material.dart';

import '../../../services/connection_alerts.dart';
import '../../../services/subscribers_check.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';

/// درجة المقياس: سليم · قريبٌ من الحدّ · مشكلة.
enum _Lvl { ok, near, bad }

/// مقاييس المشترك خاناتٍ متساوية كالكارت — المشكلة حمراء (بحدود المدير [limits])، والقريب من الحدّ برتقاليّ. تُعرض في «الفحص
/// العامّ» وفي جواب «افحص المشترك فلان» الصوتيّ (٨ نوفمبر) — واحدةٌ لا اثنتان.
class SubsMetricStrip extends StatelessWidget {
  const SubsMetricStrip({super.key, required this.reading, this.bad = const {}, required this.limits});

  final SubsReading reading;

  /// أنواع المشاكل المكتشفة (تُلوَّن حمراء).
  final Set<ConnectionProblemKind> bad;
  final ConnectionAlertThresholds limits;

  static String lanText(String lan) => switch (lan) {
        'unplugged' => 'مفصول',
        'on' => 'موصول',
        '1000' => '1G',
        _ => int.tryParse(lan) != null ? '${lan}M' : lan,
      };

  /// للاختبار والنصوص: هل في القراءة مقياسٌ يُعرض أصلاً.
  static bool hasCells(SubsReading x) =>
      x.sig != null || x.ccq != null || x.lan != null || x.rx != null || x.temp != null || x.ms != null;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final x = reading;
    final t = limits;
    _Lvl lvl(ConnectionProblemKind k, bool near) => bad.contains(k) ? _Lvl.bad : (near ? _Lvl.near : _Lvl.ok);
    final cells = <Widget>[
      if (x.sig != null) _cell('الإشارة', '${x.sig} dBm', lvl(ConnectionProblemKind.signal, x.sig! - t.signalDbm <= 5)),
      if (x.ccq != null) _cell('CCQ', '${x.ccq}%', lvl(ConnectionProblemKind.ccq, x.ccq! - t.ccqPct <= 10)),
      if (x.lan != null) _cell('الكيبل', lanText(x.lan!), lvl(ConnectionProblemKind.cable, false)),
      if (x.rx != null)
        _cell('الضوء', '${x.rx!.toStringAsFixed(1)} dBm', lvl(ConnectionProblemKind.fiberRx, x.rx! - t.fiberRxDbm <= 2)),
      if (x.temp != null)
        _cell('الحرارة', '${x.temp!.round()}°C', lvl(ConnectionProblemKind.fiberTemp, t.fiberTempC - x.temp! <= 5)),
    ];
    if (cells.isEmpty && x.ms != null) cells.add(_cell('الاستجابة', '${x.ms} ms', _Lvl.ok));
    if (cells.isEmpty) return const SizedBox.shrink();
    return Row(children: [
      for (var i = 0; i < cells.length; i++) ...[
        if (i > 0) const SizedBox(width: Sp.x6),
        Expanded(child: cells[i]),
      ],
    ]);
  }

  Widget _cell(String label, String value, _Lvl l) {
    final fg = switch (l) {
      _Lvl.bad => AppTone.danger.fill,
      _Lvl.near => AppColors.warning,
      _Lvl.ok => AppColors.textHi,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Sp.sm, vertical: Sp.x6),
      decoration: BoxDecoration(
        color: l == _Lvl.bad ? AppTone.danger.softBg : AppColors.surfaceSunken,
        borderRadius: BorderRadius.circular(R.sm),
        border: Border.all(color: l == _Lvl.bad ? AppTone.danger.softBorder : Colors.transparent),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppType.muted(color: l == _Lvl.bad ? AppTone.danger.onSoft : AppColors.textLow).copyWith(fontSize: 11)),
        const SizedBox(height: 1),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: Text(
            value,
            textDirection: TextDirection.ltr,
            style: AppType.label(color: fg).copyWith(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ]),
    );
  }
}
