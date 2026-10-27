import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/bdcom_epon.dart';
import 'package:rad_mysvcs/api/vsol_olt_api.dart';
import 'package:rad_mysvcs/models/fiber_network.dart';
import 'package:rad_mysvcs/services/fiber/fiber_band.dart';
import 'package:rad_mysvcs/services/fiber/fiber_diagnosis.dart';
import 'package:rad_mysvcs/services/fiber/fiber_light.dart';
import 'package:rad_mysvcs/services/fiber/fiber_linker.dart';
import 'package:rad_mysvcs/services/fiber/fiber_onu.dart';
import 'package:rad_mysvcs/services/fiber/fiber_outage.dart';
import 'package:rad_mysvcs/services/fiber/fiber_tree.dart';
import 'package:rad_mysvcs/theme/colors.dart';

/// شبكة الألياف — المنطق بلا واجهة ولا شبكة. كلّ الماكات اصطناعيّة (02:…)، والأسماء أمثلة.
const olt = 7;

FiberOnuLive onu(
  int pon,
  int id, {
  bool online = true,
  double? rx,
  FiberDropReason? reason,
  DateTime? at,
  String? mac,
  String? name,
  List<String> learned = const [],
  VsolPonTechnology tech = VsolPonTechnology.epon,
}) =>
    FiberOnuLive(
      onu: VsolOnu(
        ifIndex: pon * 100 + id,
        slot: 0,
        ponPort: pon,
        onuId: id,
        online: online,
        mac: mac,
        name: name,
        technology: tech,
        learnedMacs: learned,
        reading: rx == null ? null : BdcomOnuReading(rxDbm: rx),
      ),
      reason: reason,
      changedAt: at,
    );

FiberBox box(int id, String name, {int? parent, FiberNodeKind kind = FiberNodeKind.box, int ratio = 8, String pon = 'EPON0/3'}) =>
    FiberBox(id: id, oltId: olt, pon: pon, name: name, parentId: parent, kind: kind, ratio: ratio);

FiberLayout layoutWith(List<FiberBox> boxes, Map<String, int> assign) {
  var l = FiberLayout.empty;
  for (final b in boxes) {
    l = l.withBox(b);
  }
  for (final e in assign.entries) {
    l = l.withRecord(FiberOnuRecord(oltId: olt, key: e.key, boxId: e.value));
  }
  return l;
}

void main() {
  final t0 = DateTime.utc(2026, 10, 27, 11, 32, 8);

  group('رتب الضوء', () {
    test('الحدود كما في التصميم: جيّد > −25 · حدّي حتى ما فوق −27 · ضعيف −27 وأقلّ · قويّ زيادة > −8', () {
      expect(FiberBands.of(-24.9), FiberBand.good);
      expect(FiberBands.of(-25.0), FiberBand.marginal);
      expect(FiberBands.of(-26.99), FiberBand.marginal);
      expect(FiberBands.of(-27.0), FiberBand.weak);
      expect(FiberBands.of(-31.2), FiberBand.weak);
      expect(FiberBands.of(-7.9), FiberBand.strong);
      expect(FiberBands.of(-8.0), FiberBand.good);
      expect(FiberBands.tone(-6), AppTone.warning);
      expect(FiberBands.tone(-4), AppTone.danger, reason: 'فوق −5 خطر إشباع');
      expect(FiberBands.tone(-21.4), AppTone.success);
      expect(FiberBands.tone(-26), AppTone.warning);
      expect(FiberBands.tone(-28.6), AppTone.danger);
    });

    test('لا رتبة لما لم يُقرأ أو لا يُعقل: null · 0 · −50 · NaN', () {
      for (final v in <double?>[null, 0, -50, double.nan, 12]) {
        expect(FiberBands.of(v), isNull, reason: '$v');
        expect(FiberBands.tone(v), AppTone.neutral);
      }
    });

    test('خانات المدرّج نقيّة: رتبة الخانة = رتبة كلّ قراءةٍ فيها', () {
      for (var v = -40.0; v <= -3.0; v += 0.05) {
        final b = FiberBands.of(double.parse(v.toStringAsFixed(2)));
        if (b == null) continue;
        expect(FiberBands.bandOfBin(FiberBands.bin(double.parse(v.toStringAsFixed(2)))), b, reason: v.toStringAsFixed(2));
      }
      expect(FiberBands.bin(-25.2), -25);
      expect(FiberBands.bin(-27.0), -27);
      expect(FiberBands.bin(-24.0), -24);
    });
  });

  group('النموذج', () {
    test('هويّة الـONU مطبَّعة: ماك بلا فواصل بحروفٍ صغيرة، SN بكبيرة، والصفر/البثّ لا هويّة', () {
      expect(fiberIdent('02:AB:00:00:00:1F'), '02ab0000001f');
      expect(fiberIdent('02-ab-00-00-00-1f'), '02ab0000001f');
      expect(fiberIdent('vsol00001234'), 'VSOL00001234');
      expect(fiberIdent('00:00:00:00:00:00'), isNull);
      expect(fiberIdent('FF:FF:FF:FF:FF:FF'), isNull);
      expect(fiberIdent('  '), isNull);
    });

    test('تواريخ الخادم UTC بأيّ صيغة', () {
      expect(fiberParseUtc('2026-10-27 11:32:08'), DateTime.utc(2026, 10, 27, 11, 32, 8));
      expect(fiberParseUtc('2026-10-27T11:32:08Z'), DateTime.utc(2026, 10, 27, 11, 32, 8));
      expect(fiberParseUtc('2026-10-27T14:32:08+03:00'), DateTime.utc(2026, 10, 27, 11, 32, 8));
      expect(fiberParseUtc(''), isNull);
      expect(fiberParseUtc(null), isNull);
    });

    test('الحفظ والقراءة سواء (JSON)، والقيم الفاسدة تُسقط لا تُخمَّن', () {
      final l = layoutWith([box(1, 'موزّع 1:4', kind: FiberNodeKind.splitter, ratio: 4), box(2, 'صندوق 3-أ', parent: 1, ratio: 16)],
              {'EPON0/3:1': 2})
          .withSettings(const FiberOltSettings(oltId: olt, techName: 'حسن', minOnus: 4))
          .withRecord(const FiberOnuRecord(oltId: olt, key: 'EPON0/3:2', ident: '02ab00000002', username: 'ali.k12', source: FiberLinkSource.mac));
      final back = FiberLayout.fromJson(l.toJson());
      expect(back.boxes, l.boxes);
      expect(back.onus.length, 2);
      expect(back.settingsOf(olt).minOnus, 4);
      expect(back.recordFor(olt, 'EPON0/3:2', '02ab00000002')!.username, 'ali.k12');
      expect(FiberBox.fromJson({'id': 3, 'olt_id': olt, 'pon': 'EPON0/1', 'name': 'x', 'ratio': 999, 'lat': 0, 'lng': 0})!.ratio, 8);
      expect(FiberBox.fromJson({'id': 3, 'olt_id': olt, 'pon': 'EPON0/1', 'name': 'x', 'lat': 0, 'lng': 0})!.hasGps, isFalse);
      expect(FiberBox.fromJson({'id': 3, 'olt_id': olt, 'pon': 'EPON0/1'}), isNull, reason: 'بلا اسم');
      expect(FiberOltSettings.fromJson({'olt_id': olt, 'min_onus': 1})!.minOnus, FiberOltSettings.minOnusFloor);
    });

    test('جهازٌ أُعيد تسجيله برقمٍ آخر يُعرف من هويّته فلا يضيع صندوقه ولا مشتركه', () {
      var l = layoutWith([box(2, 'صندوق 3-أ')], {});
      l = l.withRecord(const FiberOnuRecord(oltId: olt, key: 'EPON0/3:5', ident: '02ab00000005', boxId: 2, username: 'omar'));
      // صار EPON0/3:9 بالهويّة نفسها
      final r = l.recordFor(olt, 'EPON0/3:9', '02ab00000005');
      expect(r!.username, 'omar');
      // هويّةٌ أخرى على الرقم القديم ⇒ ليس سجلّه
      expect(l.recordFor(olt, 'EPON0/3:5', '02ab000000ff'), isNull);
      // الحفظ تحت الرقم الجديد يحذف القديم
      l = l.withRecord(r.copyWith(key: 'EPON0/3:9'));
      expect(l.onus.keys, ['$olt|EPON0/3:9']);
    });

    test('حذف موزّع: صناديقه ترتفع لأبيه وأجهزته بلا صندوق؛ والرقم المحلّيّ يُستبدل برقم الخادم في كلّ ما يشير إليه', () {
      var l = layoutWith([
        box(1, 'رئيسي', kind: FiberNodeKind.splitter),
        box(2, 'فرعي', parent: 1, kind: FiberNodeKind.splitter),
        box(3, 'صندوق', parent: 2),
      ], {'EPON0/3:1': 2, 'EPON0/3:2': 3});
      l = l.withoutBox(2);
      expect(l.boxes[3]!.parentId, 1);
      expect(l.recordFor(olt, 'EPON0/3:1', null)?.boxId, isNull);
      expect(l.recordFor(olt, 'EPON0/3:2', null)!.boxId, 3);
      var m = layoutWith([box(-1, 'جديد'), box(4, 'تحته', parent: -1)], {'EPON0/3:7': -1});
      m = m.withBoxId(-1, box(55, 'جديد'));
      expect(m.boxes.containsKey(-1), isFalse);
      expect(m.boxes[4]!.parentId, 55);
      expect(m.recordFor(olt, 'EPON0/3:7', null)!.boxId, 55);
    });
  });

  group('شجرة المنفذ', () {
    final l = layoutWith([
      box(1, 'موزّع رئيسي', kind: FiberNodeKind.splitter, ratio: 4),
      box(2, 'صندوق 3-أ', parent: 1, ratio: 16),
      box(3, 'صندوق 3-ب', parent: 1, ratio: 8),
      box(9, 'صندوق PON2', pon: 'EPON0/2'),
    ], {
      for (var i = 1; i <= 12; i++) 'EPON0/3:$i': 2,
      for (var i = 13; i <= 19; i++) 'EPON0/3:$i': 3,
    });
    final onus = [for (var i = 1; i <= 21; i++) onu(3, i)];

    test('الجذور والفروع والأجهزة تحت كلٍّ منها، وما لا صندوق له', () {
      final t = FiberPonTree.build(oltId: olt, pon: 'EPON0/3', layout: l, onus: onus);
      expect(t.roots.map((b) => b.id), [1]);
      expect(t.childrenOf(1).map((b) => b.name), ['صندوق 3-أ', 'صندوق 3-ب']);
      expect(t.onusUnder(1).length, 19);
      expect(t.unassigned.map((o) => o.key), ['EPON0/3:20', 'EPON0/3:21']);
      expect(t.nodes.containsKey(9), isFalse, reason: 'صندوق منفذٍ آخر');
      expect(t.freePorts(2), 4);
      expect(t.freePorts(3), 1);
      expect(t.freePorts(1), 2, reason: 'الموزّع: فرعان من أربعة');
      expect(t.freeBoxPorts, 5);
      expect(t.pathTo(2).map((b) => b.id), [1, 2]);
    });

    test('حلقةٌ أبويّة في بياناتٍ قديمة لا تعلّق الشجرة', () {
      final bad = layoutWith([box(1, 'أ', parent: 2), box(2, 'ب', parent: 1)], {'EPON0/3:1': 1});
      final t = FiberPonTree.build(oltId: olt, pon: 'EPON0/3', layout: bad, onus: onus);
      expect(t.roots, isNotEmpty);
      expect(t.onusUnder(t.roots.first.id), isNotEmpty);
    });
  });

  group('كشف العطل', () {
    // PON 3: موزّع رئيسي ← 3-أ (١٢) · 3-ب (٧) · 3-ج (٣)، وجهازان بلا صندوق.
    final l = layoutWith([
      box(1, 'موزّع رئيسي', kind: FiberNodeKind.splitter, ratio: 4),
      box(2, 'صندوق 3-أ', parent: 1, ratio: 16),
      box(3, 'صندوق 3-ب', parent: 1),
      box(4, 'صندوق 3-ج', parent: 1),
    ], {
      for (var i = 1; i <= 12; i++) 'EPON0/3:$i': 2,
      for (var i = 13; i <= 19; i++) 'EPON0/3:$i': 3,
      for (var i = 20; i <= 22; i++) 'EPON0/3:$i': 4,
    });

    List<FiberOnuLive> pon3({Set<int> down = const {}, FiberDropReason? reason, Duration step = const Duration(milliseconds: 450), bool timed = true}) => [
          for (var i = 1; i <= 24; i++)
            down.contains(i)
                ? onu(3, i, online: false, reason: reason, at: timed ? t0.add(step * (i - 1)) : null)
                : onu(3, i, rx: -21),
        ];

    test('صندوق 3-أ كلّه خلال ٥ ثوانٍ بفقدان ضوء وجيرانه شغّالون ⇒ عطلٌ واحد بالصندوق، قطع ليف', () {
      final out = FiberOutageDetector.detect(
        oltId: olt,
        layout: l,
        onus: pon3(down: {for (var i = 1; i <= 12; i++) i}, reason: FiberDropReason.fiber),
        now: t0.add(const Duration(minutes: 23)),
      );
      expect(out.length, 1);
      final e = out.single;
      expect(e.scope, FiberEventScope.box);
      expect(e.boxId, 2);
      expect(e.scopeKey, 'box:2');
      expect(e.kind, FiberEventKind.cut);
      expect(e.count, 12);
      expect(e.timed, isTrue);
      expect(e.startedAt, t0);
      expect(e.spread!.inSeconds, 4);
      expect(e.onuKeys.first, 'EPON0/3:1');
      expect(e.onuKeys.last, 'EPON0/3:12', reason: 'ترتيبٌ رقميّ لا أبجديّ');
    });

    test('انطفاء كهرباء بأجهزةٍ من صناديق مختلفة ⇒ مجموعة، والسبب كهرباء', () {
      final out = FiberOutageDetector.detect(
        oltId: olt,
        layout: l,
        onus: pon3(down: {1, 2, 13, 14, 20}, reason: FiberDropReason.power, step: const Duration(seconds: 10)),
        now: t0.add(const Duration(minutes: 5)),
      );
      expect(out.single.scope, FiberEventScope.group);
      expect(out.single.kind, FiberEventKind.power);
    });

    test('المنفذ كلّه سقط ⇒ نطاق المنفذ (الكيبل الرئيسيّ أو منفذ الأولت)', () {
      final out = FiberOutageDetector.detect(
        oltId: olt,
        layout: l,
        onus: pon3(down: {for (var i = 1; i <= 24; i++) i}, reason: FiberDropReason.fiber, step: const Duration(milliseconds: 100)),
        now: t0.add(const Duration(minutes: 1)),
      );
      expect(out.single.scope, FiberEventScope.pon);
      expect(out.single.scopeKey, 'pon:EPON0/3');
      expect(out.single.count, 24);
    });

    test('موزّعٌ كامل (صندوقاه) سقط والمنافذ الأخرى سليمة ⇒ نطاق الموزّع', () {
      final l2 = layoutWith([
        box(1, 'موزّع أ', kind: FiberNodeKind.splitter, ratio: 4),
        box(5, 'موزّع ب', kind: FiberNodeKind.splitter, ratio: 4),
        box(2, 'صندوق 1', parent: 1),
        box(3, 'صندوق 2', parent: 1),
        box(4, 'صندوق 3', parent: 5),
      ], {
        for (var i = 1; i <= 4; i++) 'EPON0/3:$i': 2,
        for (var i = 5; i <= 8; i++) 'EPON0/3:$i': 3,
        for (var i = 9; i <= 16; i++) 'EPON0/3:$i': 4,
      });
      final out = FiberOutageDetector.detect(
        oltId: olt,
        layout: l2,
        onus: [for (var i = 1; i <= 16; i++) i <= 8 ? onu(3, i, online: false, at: t0, reason: FiberDropReason.fiber) : onu(3, i)],
        now: t0.add(const Duration(minutes: 1)),
      );
      expect(out.single.scope, FiberEventScope.splitter);
      expect(out.single.boxId, 1);
    });

    test('سقوطٌ متفرّق بساعاتٍ بينها ليس عطلاً جماعيّاً، وجهازان أقلّ من الحدّ', () {
      expect(
          FiberOutageDetector.detect(
            oltId: olt,
            layout: l,
            onus: pon3(down: {1, 5, 9}, reason: FiberDropReason.fiber, step: const Duration(hours: 2)),
            now: t0.add(const Duration(hours: 20)),
          ),
          isEmpty);
      expect(
          FiberOutageDetector.detect(oltId: olt, layout: l, onus: pon3(down: {1, 2}), now: t0.add(const Duration(minutes: 1))),
          isEmpty);
    });

    test('بلا صناديق: خمسة سقطوا معاً ⇒ مجموعة على المنفذ؛ وبلا سببٍ من الأولت ⇒ «غير معروف» لا قطع', () {
      final out = FiberOutageDetector.detect(
        oltId: olt,
        layout: FiberLayout.empty,
        onus: pon3(down: {3, 4, 5, 6, 7}),
        now: t0.add(const Duration(minutes: 1)),
      );
      expect(out.single.scope, FiberEventScope.group);
      expect(out.single.kind, FiberEventKind.unknown);
    });

    test('سببٌ مختلط (٥ ضوء + ٤ كهرباء من ١٠) ⇒ خليط', () {
      final onus = [
        for (var i = 1; i <= 24; i++)
          i <= 10
              ? onu(3, i, online: false, at: t0, reason: i <= 5 ? FiberDropReason.fiber : (i <= 9 ? FiberDropReason.power : null))
              : onu(3, i),
      ];
      final out = FiberOutageDetector.detect(oltId: olt, layout: FiberLayout.empty, onus: onus, now: t0);
      expect(out.single.kind, FiberEventKind.mixed);
      expect(out.single.reasons[FiberDropReason.fiber], 5);
    });

    test('بلا لحظات سقوط (الأولت لا يعطيها): صندوقٌ كلّه مفصول وغيره شغّال ⇒ عطلٌ بالصندوق «منذ وقتٍ غير معروف»', () {
      final out = FiberOutageDetector.detect(
        oltId: olt,
        layout: l,
        onus: pon3(down: {13, 14, 15, 16, 17, 18, 19}, timed: false),
        now: t0,
      );
      expect(out.single.scope, FiberEventScope.box);
      expect(out.single.boxId, 3);
      expect(out.single.timed, isFalse);
      expect(out.single.startedAt, isNull);
    });

    test('لحظةٌ في المستقبل (ساعة أولتٍ خاطئة) لا تُحسب سقوطاً حديثاً', () {
      final out = FiberOutageDetector.detect(
        oltId: olt,
        layout: l,
        onus: [for (var i = 1; i <= 24; i++) i <= 12 ? onu(3, i, online: false, at: t0.add(const Duration(days: 30))) : onu(3, i)],
        now: t0,
      );
      expect(out, isEmpty);
    });
  });

  group('صحّة الضوء', () {
    final now = DateTime.utc(2026, 10, 27, 9);
    final today = fiberDay(now);

    RxDailyBook bookOf(Map<String, List<double>> daily) {
      final b = RxDailyBook();
      for (final e in daily.entries) {
        for (var i = 0; i < e.value.length; i++) {
          final day = fiberDayBefore(today, e.value.length - i);
          final at = DateTime.utc(int.parse(day.substring(0, 4)), int.parse(day.substring(5, 7)), int.parse(day.substring(8)), 9);
          b.record(e.key, e.value[i], at);
        }
      }
      return b;
    }

    test('يوم بغداد ويومه السابق', () {
      expect(fiberDay(DateTime.utc(2026, 10, 26, 21, 30)), '2026-10-27');
      expect(fiberDay(DateTime.utc(2026, 10, 26, 20, 59)), '2026-10-26');
      expect(fiberDayBefore('2026-11-01'), '2026-10-31');
      expect(fiberDayBefore('2026-03-01', 1), '2026-02-28');
    });

    test('الدفتر: متوسّطٌ موزون، دمجٌ من الخادم، ورفعُ ما تغيّر وحده', () {
      final b = RxDailyBook();
      b.record('EPON0/3:1', -21, now);
      b.record('EPON0/3:1', -23, now);
      expect(b.data['EPON0/3:1']![today]!.avg, -22);
      expect(b.data['EPON0/3:1']![today]!.min, -23);
      final rows = b.takeDirty();
      expect(rows.single['n'], 2);
      expect(b.takeDirty(), isEmpty);
      b.mergeServer('EPON0/3:1', const RxDay(day: '2026-10-20', min: -20, avg: -20, max: -20, n: 30), today: today);
      expect(b.data['EPON0/3:1']!['2026-10-20']!.n, 30);
      final back = RxDailyBook.fromJson(b.toJson());
      expect(back.data['EPON0/3:1']!.length, 2);
      b.record('EPON0/3:1', 0, now); // ليس قراءة
      expect(b.data['EPON0/3:1']![today]!.n, 2);
    });

    test('التوزيع والرتب، ونزولٌ فجائيّ لجهازٍ وحده، وصندوقٌ نزل كلّه، وضعيفٌ ثابت', () {
      final l = layoutWith([box(2, 'صندوق 2-ج', pon: 'EPON0/2')], {for (var i = 1; i <= 4; i++) 'EPON0/2:$i': 2});
      final onus = [
        onu(2, 1, rx: -26.9), onu(2, 2, rx: -25.6), onu(2, 3, rx: -25.2), onu(2, 4, rx: -23.4), // الصندوق: ٤ نزلت ~2.4
        onu(1, 1, rx: -28.6), // نزل فجأة وحده
        onu(1, 2, rx: -29.1), // ضعيفٌ ثابت
        onu(1, 3, rx: -20.0),
        onu(1, 4, online: false),
      ];
      final book = bookOf({
        'EPON0/2:1': [-24.5, -24.5, -24.5, -24.4, -24.6, -24.5, -24.5],
        'EPON0/2:2': [-23.2, -23.2, -23.2, -23.2, -23.2, -23.2, -23.2],
        'EPON0/2:3': [-22.8, -22.8, -22.8, -22.8, -22.8, -22.8, -22.8],
        'EPON0/2:4': [-21.0, -21.0, -21.0, -21.0, -21.0, -21.0, -21.0],
        'EPON0/1:1': [-23.9, -23.9, -23.9, -24.0, -23.8, -23.9, -23.9],
        'EPON0/1:2': [-29.0, -29.1, -29.2, -29.1, -29.0, -29.1, -29.1],
        'EPON0/1:3': [-20.0, -20.1, -20.0, -20.0, -20.1, -20.0, -20.0],
      });
      final trees = [
        FiberPonTree.build(oltId: olt, pon: 'EPON0/2', layout: l, onus: onus),
        FiberPonTree.build(oltId: olt, pon: 'EPON0/1', layout: l, onus: onus),
      ];
      final r = FiberLightAnalysis.analyze(onus: onus, book: book, now: now, trees: trees);
      expect([r.good, r.marginal, r.weak, r.strong, r.noReading], [2, 3, 2, 0, 1]);
      expect(r.histogram[-25], 2);
      expect(r.histogram[-26], 1);
      expect(r.boxDrops.single.boxId, 2);
      expect(r.boxDrops.single.drops.length, 4);
      expect(r.boxDrops.single.avgDrop, closeTo(2.4, 0.1));
      expect(r.suddenDrops.map((d) => d.key), ['EPON0/1:1'], reason: 'أجهزة الصندوق تُعرض مع صندوقها لا وحدها');
      expect(r.suddenDrops.single.drop, closeTo(4.7, 0.05));
      expect(r.stableWeak.map((s) => s.key), ['EPON0/1:2']);
      expect(r.attention, 5);
    });

    test('بلا تاريخ: لا «نزل فجأة» ولا «ثابت» — والتوزيع يبقى', () {
      final r = FiberLightAnalysis.analyze(onus: [onu(1, 1, rx: -28.6)], book: RxDailyBook(), now: now);
      expect(r.weak, 1);
      expect(r.suddenDrops, isEmpty);
      expect(r.stableWeak, isEmpty);
      expect(r.historyDays, 0);
    });
  });

  group('الربط التلقائيّ', () {
    test('الوصف = اليوزر · ماك خلفه = جلسته · ماك الـONU نفسها · وقريبٌ منه محتمل', () {
      final onus = [
        onu(1, 1, name: 'karar77'),
        onu(1, 2, learned: ['02:00:00:00:10:02']),
        onu(1, 3, mac: '02:00:00:00:20:03'),
        onu(1, 4, mac: '02:00:00:00:30:04'),
        onu(1, 5, online: false),
        onu(1, 6, learned: ['02:00:00:00:99:99']),
        onu(1, 7),
      ];
      final p = FiberLinker.plan(
        oltId: olt,
        onus: onus,
        layout: FiberLayout.empty,
        sessionMacByUser: {'maryam.s': '02:00:00:00:10:02', 'noor.h': '02000000200 3'.replaceAll(' ', ''), 'ahmed.f': '02:00:00:00:30:05'},
        knownUsernames: {'karar77': 'Karar77'},
      );
      final by = {for (final s in p.suggestions) s.key: s};
      expect(by['EPON0/1:1']!.username, 'Karar77');
      expect(by['EPON0/1:1']!.source, FiberLinkSource.name);
      expect(by['EPON0/1:2']!.username, 'maryam.s');
      expect(by['EPON0/1:2']!.sure, isTrue);
      expect(by['EPON0/1:3']!.source, FiberLinkSource.onuMac);
      expect(by['EPON0/1:3']!.sure, isTrue);
      expect(by['EPON0/1:4']!.username, 'ahmed.f');
      expect(by['EPON0/1:4']!.sure, isFalse, reason: 'فرق ١ ⇒ محتمل');
      expect(p.unlinked[FiberUnlinkedReason.offline], ['EPON0/1:5']);
      expect(p.unlinked[FiberUnlinkedReason.noSession], ['EPON0/1:6']);
      expect(p.unlinked[FiberUnlinkedReason.unknownDevices], ['EPON0/1:7']);
      expect(p.sureCount, 3);
    });

    test('المربوط لا يُقترح، ويوزرٌ مربوط لا يُقترح لغيره، ويوزرٌ لجهازين بالقوّة نفسها يُسقط الاثنين', () {
      final layout = FiberLayout.empty.withRecord(const FiberOnuRecord(oltId: olt, key: 'EPON0/1:1', username: 'ali'));
      final onus = [
        onu(1, 1, learned: ['02:00:00:00:00:01']),
        onu(1, 2, learned: ['02:00:00:00:00:01']),
        onu(1, 3, learned: ['02:00:00:00:00:03']),
        onu(1, 4, learned: ['02:00:00:00:00:03']),
      ];
      final p = FiberLinker.plan(
        oltId: olt,
        onus: onus,
        layout: layout,
        sessionMacByUser: {'ali': '02:00:00:00:00:01', 'zain': '02:00:00:00:00:03'},
      );
      expect(p.linkedCount, 1);
      expect(p.suggestions, isEmpty, reason: 'ali مربوطٌ أصلاً، وzain لجهازين');
      expect(p.unlinked[FiberUnlinkedReason.noSession]!.toSet(), {'EPON0/1:2', 'EPON0/1:3', 'EPON0/1:4'});
    });

    test('ماكٌ خلف جهاز يطابق يوزرين (جلستان بالماك نفسه) ⇒ لا اقتراح', () {
      final p = FiberLinker.plan(
        oltId: olt,
        onus: [onu(1, 1, learned: ['02:00:00:00:00:01'])],
        layout: FiberLayout.empty,
        sessionMacByUser: {'a': '02:00:00:00:00:01', 'b': '02:00:00:00:00:01'},
      );
      expect(p.suggestions, isEmpty);
    });
  });

  group('تشخيص المشترك', () {
    const active = FiberSubscriberFacts(expired: false, disabled: false, sessionOnline: false, remainingDays: 9);
    final now = DateTime.utc(2026, 10, 27, 12);

    test('الراوتر: الضوء والجهاز والاشتراك سليمة ولا جلسة', () {
      final d = FiberDiagnose.of(sub: active, onu: onu(2, 7, rx: -21.4, at: now.subtract(const Duration(days: 3))), now: now);
      expect(d.kind, FiberVerdictKind.router);
      expect(d.steps.map((s) => s.state), [FiberStepState.ok, FiberStepState.ok, FiberStepState.ok, FiberStepState.bad]);
      expect(d.steps[1].detail, 'متّصل من 3 أيّام');
      expect(d.steps[2].detail, '-21.4 dBm · جيّد');
    });

    test('قطع ليف عنده وحده · كهرباء البيت · ضمن عطلٍ جماعيّ · بلا سبب', () {
      final at = DateTime(2026, 10, 27, 14, 32);
      expect(FiberDiagnose.of(sub: active, onu: onu(2, 7, online: false, reason: FiberDropReason.fiber, at: at), boxOnline: 6, boxTotal: 6, now: now).kind,
          FiberVerdictKind.fiberHome);
      final p = FiberDiagnose.of(sub: active, onu: onu(2, 7, online: false, reason: FiberDropReason.power, at: at), now: now);
      expect(p.kind, FiberVerdictKind.power);
      expect(p.body, contains('14:32'));
      expect(p.steps[1].state, FiberStepState.warn);
      expect(p.steps[3].state, FiberStepState.skip);
      expect(FiberDiagnose.of(sub: active, onu: onu(2, 7, online: false, reason: FiberDropReason.fiber), inOutage: true, now: now).kind,
          FiberVerdictKind.outage);
      expect(FiberDiagnose.of(sub: active, onu: onu(2, 7, online: false), now: now).kind, FiberVerdictKind.onuDown);
    });

    test('الاشتراك المنتهي يغلب الراوتر، والجهاز المفصول يغلب الاشتراك (التجديد لا يُرجع نتّاً لجهازٍ مفصول)', () {
      const expired = FiberSubscriberFacts(expired: true, disabled: false, sessionOnline: false);
      expect(FiberDiagnose.of(sub: expired, onu: onu(2, 7, rx: -21), now: now).kind, FiberVerdictKind.subscription);
      expect(FiberDiagnose.of(sub: expired, onu: onu(2, 7, rx: -21), now: now).steps[3].state, FiberStepState.warn);
      expect(FiberDiagnose.of(sub: expired, onu: onu(2, 7, online: false, reason: FiberDropReason.power), now: now).kind,
          FiberVerdictKind.power);
      const disabled = FiberSubscriberFacts(expired: false, disabled: true, sessionOnline: false);
      expect(FiberDiagnose.of(sub: disabled, onu: onu(2, 7, rx: -21), now: now).title, 'حسابه معطَّل');
    });

    test('حساب المشترك غير معروف ⇒ لا «فعّال» ولا «ماكو جلسة» بلا دليل', () {
      final d = FiberDiagnose.of(sub: null, onu: onu(2, 7, rx: -21.4), now: now);
      expect(d.kind, FiberVerdictKind.onuOnly);
      expect(d.steps[0].state, FiberStepState.skip);
      expect(d.steps[0].detail, 'غير مربوط بمشترك');
      expect(d.steps[3].state, FiberStepState.skip);
      expect(d.body, isNot(contains('فعّال')));
      final why = FiberDiagnose.of(sub: null, onu: onu(2, 7, rx: -21.4), now: now, subUnknown: 'ما قدرنا نقرأ حسابه من الساس');
      expect(why.steps[0].detail, 'ما قدرنا نقرأ حسابه من الساس');
      expect(FiberDiagnose.of(sub: null, onu: onu(2, 7, rx: -28.6), now: now).kind, FiberVerdictKind.weakLight);
      expect(FiberDiagnose.of(sub: null, onu: onu(2, 7, online: false, reason: FiberDropReason.power), now: now).kind,
          FiberVerdictKind.power);
      expect(FiberDiagnose.of(sub: null, now: now).kind, FiberVerdictKind.noOnu);
    });

    test('ضوءٌ ضعيف، وكلّ شي سليم، وبلا جهاز مربوط', () {
      const on = FiberSubscriberFacts(expired: false, disabled: false, sessionOnline: true, debt: 15000);
      expect(FiberDiagnose.of(sub: on, onu: onu(2, 7, rx: -28.6), now: now).kind, FiberVerdictKind.weakLight);
      final ok = FiberDiagnose.of(sub: on, onu: onu(2, 7, rx: -21), now: now);
      expect(ok.kind, FiberVerdictKind.allGood);
      expect(ok.steps.first.state, FiberStepState.warn, reason: 'عليه دين');
      expect(FiberDiagnose.of(sub: active, now: now).kind, FiberVerdictKind.noOnu);
      expect(FiberDiagnose.of(sub: active, now: now).steps[1].state, FiberStepState.skip);
    });
  });

  test('أسماء العرض: PON 3 وONU 3:2، والبطاقة حين لا تكون صفراً', () {
    expect(fiberPonDisplay('EPON0/3'), 'PON 3');
    expect(fiberPonDisplay('GPON1/2'), 'PON 1/2');
    expect(fiberOnuDisplay(onu(3, 2).onu), 'ONU 3:2');
  });
}
