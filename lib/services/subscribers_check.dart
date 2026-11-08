import 'package:easy_localization/easy_localization.dart' show StringTranslateExtension;

import '../api/device_probe_api.dart';
import '../core/util/bidi.dart';
import '../models/device_health.dart';
import '../models/subscriber.dart';
import 'connection_alerts.dart';
import 'vpn_now.dart';

/// مشكلة مشتركٍ في «الفحص العامّ»: نوعها وسطرها كما يُعرض.
typedef SubsCheckProblem = ({ConnectionProblemKind kind, String label});

/// مشتركٌ بمشكلة (أو أكثر) في التقرير.
class SubsCheckRow {
  const SubsCheckRow(this.sub, this.problems);
  final Subscriber sub;
  final List<SubsCheckProblem> problems;
}

/// تقرير «الفحص العامّ» للمشتركين: كم قُرئ من كم، ومن بمشكلة مصنّفين بنوعها.
class SubsCheckReport {
  const SubsCheckReport({required this.total, required this.read, required this.rows, this.oldest});

  final int total;

  /// مشتركون لهم قراءةٌ معروفة (من الكارت/الذاكرة أو من فحص الـVPN).
  final int read;

  /// من بمشكلة — الأسوأ أوّلاً (الكيبل ثمّ الإشارة…).
  final List<SubsCheckRow> rows;

  /// أقدم قراءةٍ داخلة (للسطر «آخر قراءة قبل…»).
  final DateTime? oldest;

  int get unread => total - read;

  /// من بمشكلة بهذا النوع.
  List<SubsCheckRow> of(ConnectionProblemKind k) => [for (final r in rows) if (r.problems.any((p) => p.kind == k)) r];
}

/// «الفحص العامّ» للمشتركين (٨ نوفمبر — المالك: «أ» ثمّ «تره فحص المشتركين ثكيل كلش مو مثل فحص الاجهزه ولا مثل مايعرضون
/// الاشارات وسرعته بكارت المشتركين»): خفيفٌ — من القراءات التي يعرضها كارت المشترك نفسه (ذاكرة الفحص، أيّ عمر)، والموجة تعيد
/// القديم وحده؛ والمشكلة بحدود «تنبيه المشترك» نفسها ([ConnectionAlerts.detect]) — لا تعريفٌ ثانٍ للضعيف. عبر الـVPN: قراءات
/// فحص الخادم ([VpnNow.readingFor]) بالحدود نفسها لكلّ شركة.
class SubscribersCheck {
  SubscribersCheck._();

  static const _order = [
    ConnectionProblemKind.cable,
    ConnectionProblemKind.signal,
    ConnectionProblemKind.ccq,
    ConnectionProblemKind.fiberRx,
    ConnectionProblemKind.fiberTemp,
  ];

  static int _rank(SubsCheckRow r) =>
      r.problems.map((p) => _order.indexOf(p.kind)).fold<int>(_order.length, (a, b) => b < a ? b : a);

  /// من قراءات الهاتف (الكارت): [peek] يُستبدل في الاختبار.
  static SubsCheckReport local(
    List<Subscriber> subs,
    ConnectionAlertThresholds Function(String? company) limits, {
    ({DeviceHealthSnapshot? snap, bool stale, DateTime at})? Function(Subscriber s)? peek,
  }) {
    final look = peek ??
        (s) => DeviceProbeApi.peek(username: s.username, ip: s.ipAddress, company: s.companyKey);
    var read = 0;
    DateTime? oldest;
    final rows = <SubsCheckRow>[];
    for (final s in subs) {
      final p = look(s);
      final snap = p?.snap;
      // قراءةٌ بمقاييس (يوبيكويتي أو ONT) وحدها — جهازٌ آخر بلا أرقام ليس «مقروءاً»
      final metrics = snap != null &&
          ((snap.kind == DeviceKind.ubiquiti && snap.ubnt != null) || (snap.kind == DeviceKind.ont && snap.ont != null));
      if (!metrics) continue;
      read++;
      if (oldest == null || p!.at.isBefore(oldest)) oldest = p!.at;
      final probs = ConnectionAlerts.detect(snap, limits(s.companyKey));
      if (probs.isNotEmpty) rows.add(SubsCheckRow(s, [for (final x in probs) (kind: x.kind, label: x.label)]));
    }
    rows.sort((a, b) => _rank(a).compareTo(_rank(b)));
    return SubsCheckReport(total: subs.length, read: read, rows: rows, oldest: oldest);
  }

  /// من قراءات فحص الخادم عبر الـVPN: [reading] يُستبدل في الاختبار.
  static SubsCheckReport vpn(
    List<Subscriber> subs,
    ConnectionAlertThresholds Function(String? company) limits, {
    VpnSubReading? Function(Subscriber s)? reading,
  }) {
    final look = reading ?? (s) => VpnNow.readingFor(s.username, company: s.companyKey);
    var read = 0;
    final rows = <SubsCheckRow>[];
    for (final s in subs) {
      final r = look(s);
      if (r == null || r.dead) continue;
      read++;
      final probs = fromVpn(r, limits(s.companyKey));
      if (probs.isNotEmpty) rows.add(SubsCheckRow(s, probs));
    }
    rows.sort((a, b) => _rank(a).compareTo(_rank(b)));
    return SubsCheckReport(total: subs.length, read: read, rows: rows);
  }

  /// قراءة الخادم ⇒ المشاكل بحدود المدير — كـ[ConnectionAlerts.detect] حرفاً (الصفر ليس قراءة).
  static List<SubsCheckProblem> fromVpn(VpnSubReading r, ConnectionAlertThresholds t) {
    final out = <SubsCheckProblem>[];
    if (r.lan == 'unplugged') {
      out.add((kind: ConnectionProblemKind.cable, label: 'conn_alerts.p_lan_unplugged'.tr()));
    } else if (r.lan == '10') {
      out.add((kind: ConnectionProblemKind.cable, label: 'conn_alerts.p_lan_10'.tr()));
    }
    final s = r.sig;
    if (s != null && s < 0 && s < t.signalDbm) {
      out.add((kind: ConnectionProblemKind.signal, label: 'conn_alerts.p_signal'.tr(args: [iso('$s dBm')])));
    }
    final c = r.ccq;
    if (c != null && c > 0 && c <= t.ccqPct) {
      out.add((kind: ConnectionProblemKind.ccq, label: 'conn_alerts.p_ccq'.tr(args: [iso('$c%')])));
    }
    final rx = r.rx;
    if (rx != null && rx < 0 && rx < t.fiberRxDbm) {
      out.add((kind: ConnectionProblemKind.fiberRx, label: 'conn_alerts.p_fiber_rx'.tr(args: [iso('${rx.toStringAsFixed(1)} dBm')])));
    }
    final temp = r.temp;
    if (temp != null && temp > t.fiberTempC) {
      out.add((kind: ConnectionProblemKind.fiberTemp, label: 'conn_alerts.p_fiber_temp'.tr(args: [iso('${temp.toStringAsFixed(0)}°C')])));
    }
    return out;
  }
}
