import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/bdcom_epon.dart';
import 'package:rad_mysvcs/api/vsol_olt_api.dart';
import 'package:rad_mysvcs/models/fiber_network.dart';
import 'package:rad_mysvcs/screens/network_devices/fiber/fiber_map_screen.dart';
import 'package:rad_mysvcs/services/fiber/fiber_map.dart';
import 'package:rad_mysvcs/services/fiber/fiber_onu.dart';
import 'package:rad_mysvcs/services/fiber/fiber_tree.dart';

/// المالك ٢٨ أكتوبر: «من احدد بوكس ١:٨ مفروض ميتقبل اكثر من هلشي» + «رسم خريطة بمسارات الضوئي ٢d… يوضح سيرفر الترفك والربط».
/// الماكات والأسماء اصطناعيّة.
const olt = 7;

FiberOnuLive onu(int pon, int id, {bool online = true, double? rx}) => FiberOnuLive(
      onu: VsolOnu(
        ifIndex: pon * 100 + id,
        slot: 0,
        ponPort: pon,
        onuId: id,
        online: online,
        mac: '02:ab:00:00:${pon.toString().padLeft(2, '0')}:${id.toString().padLeft(2, '0')}',
        technology: VsolPonTechnology.epon,
        reading: rx == null ? null : BdcomOnuReading(rxDbm: rx),
      ),
    );

FiberBox box(int id, String name, {int? parent, FiberNodeKind kind = FiberNodeKind.box, int ratio = 8, String pon = 'EPON0/1'}) =>
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

VsolPonPort pon(int p, {bool up = true}) => VsolPonPort(
      index: 1000 + p,
      slot: 0,
      port: p,
      up: up,
      rxBytes: 0,
      txBytes: 0,
    );

void main() {
  group('السعة — ١:٨ لا يقبل أكثر من ٨', () {
    // موزّع 1:2 تحته صندوقان 1:4؛ ٣ أجهزة في الأوّل، والثاني ممتلئ (٤).
    final onus = [for (var i = 1; i <= 9; i++) onu(1, i, online: i != 2)];
    final layout = layoutWith([
      box(1, 'موزّع', kind: FiberNodeKind.splitter, ratio: 2),
      box(2, 'صندوق أ', parent: 1, ratio: 4),
      box(3, 'صندوق ب', parent: 1, ratio: 4),
    ], {
      'EPON0/1:1': 2, 'EPON0/1:2': 2, 'EPON0/1:3': 2,
      'EPON0/1:4': 3, 'EPON0/1:5': 3, 'EPON0/1:6': 3, 'EPON0/1:7': 3,
    });
    final t = FiberPonTree.build(oltId: olt, pon: 'EPON0/1', layout: layout, onus: onus);

    test('يتّسع لما بقي، وما كان فيه أصلاً لا يأخذ منفذاً جديداً', () {
      expect(t.freePorts(2), 1);
      expect(t.fit(2, ['EPON0/1:8']).ok, isTrue);
      expect(t.fit(2, ['EPON0/1:8', 'EPON0/1:9']).ok, isFalse, reason: 'جهازان ومنفذٌ واحد');
      final again = t.fit(2, ['EPON0/1:1', 'EPON0/1:2', 'EPON0/1:3', 'EPON0/1:8']);
      expect(again.needed, 1);
      expect(again.ok, isTrue, reason: 'الثلاثة فيه أصلاً');
    });

    test('الممتلئ لا يقبل، والمنقول من صندوقٍ آخر يأخذ منفذاً', () {
      expect(t.freePorts(3), 0);
      expect(t.fit(3, ['EPON0/1:8']).ok, isFalse);
      expect(t.fit(3, ['EPON0/1:1']).needed, 1, reason: 'منقولٌ من صندوق أ');
      expect(t.fit(3, ['EPON0/1:4']).ok, isTrue, reason: 'فيه أصلاً');
    });

    test('الموزّع الممتلئ لا يأخذ فرعاً جديداً — والفرع الذي تحته أصلاً يبقى', () {
      expect(t.usedPorts(1), 2);
      expect(t.canHang(1), isFalse);
      expect(t.canHang(1, movingId: 2), isTrue);
      expect(t.canHang(1, movingId: 99), isFalse);
      expect(t.canHang(404), isFalse);
    });
  });

  group('مخطّط الشبكة', () {
    final onus = [
      for (var i = 1; i <= 7; i++) onu(1, i, online: i != 3),
      for (var i = 1; i <= 3; i++) onu(2, i, online: false),
      onu(3, 1),
    ];
    final layout = layoutWith([
      box(1, 'موزّع رئيسي', kind: FiberNodeKind.splitter, ratio: 4),
      box(2, 'صندوق 1', parent: 1),
      box(3, 'صندوق 2', parent: 1, ratio: 16),
      box(4, 'صندوق المنفذ 2', pon: 'EPON0/2'),
    ], {
      'EPON0/1:1': 2, 'EPON0/1:2': 2, 'EPON0/1:3': 2,
      'EPON0/1:4': 3, 'EPON0/1:5': 3,
      'EPON0/2:1': 4, 'EPON0/2:2': 4,
    });
    FiberMapOlt input({String name = 'أولت الساحة', int id = olt, List<FiberOnuLive>? list}) => FiberMapOlt(
          oltId: id,
          name: name,
          model: 'V1600D',
          pons: [pon(1), pon(2), pon(3)],
          onus: list ?? onus,
          ponRates: const {'EPON0/1': VsolTraffic(2.5e6, 48.2e6)},
          uplinkRates: const {'GE1': VsolTraffic(120e6, 9e6)},
        );

    test('السيرفر ⇐ الأولت ⇐ المنافذ ⇐ الموزّع ⇐ الصناديق، و«بلا صندوق» لكلّ منفذ', () {
      final m = FiberMapModel.build(olts: [input()], layout: layout, rtl: false);
      expect(m.root.kind, FiberMapKind.core);
      expect(m.root.downBps, 120e6, reason: 'ترفك الأبلنك النازل');
      final o = m.root.children.single;
      expect([o.kind, o.online, o.total], [FiberMapKind.olt, 7, 11]);
      expect(o.children.map((n) => n.title), ['PON 1', 'PON 2', 'PON 3']);
      final p1 = o.children.first;
      expect(p1.downBps, 48.2e6, reason: 'tx المنفذ = نحو المشتركين');
      expect(p1.children.map((n) => n.kind), [FiberMapKind.splitter, FiberMapKind.loose]);
      final sp = p1.children.first;
      expect(sp.children.map((n) => n.title), ['صندوق 1', 'صندوق 2']);
      final b1 = sp.children.first;
      expect(b1.slots.where((s) => s == FiberMapSlot.up).length, 2);
      expect(b1.slots.where((s) => s == FiberMapSlot.down).length, 1);
      expect(b1.slots.where((s) => s == FiberMapSlot.free).length, 5);
      expect(b1.state, FiberMapState.partial);
      final loose = p1.children.last;
      expect([loose.total, loose.online], [2, 2]);
      final p2 = o.children[1];
      expect(p2.state, FiberMapState.down, reason: 'كلّها مفصولة');
    });

    test('لا تداخل بين العقد، والأب في وسط أبنائه، والمخطّط يسع كلّ شيء', () {
      final m = FiberMapModel.build(olts: [input(), input(name: 'أولت الشارع', id: 8, list: [onu(1, 1)])], layout: layout);
      for (var i = 0; i < m.nodes.length; i++) {
        final a = m.nodes[i];
        expect(a.x >= 0 && a.y >= 0 && a.x + a.w <= m.width + 0.01 && a.y + a.h <= m.height + 0.01, isTrue, reason: a.title);
        for (var j = i + 1; j < m.nodes.length; j++) {
          final b = m.nodes[j];
          final overlap = a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h;
          expect(overlap, isFalse, reason: '${a.title} ⟷ ${b.title}');
        }
        if (a.children.length > 1) {
          final mid = (a.children.first.cx + a.children.last.cx) / 2;
          expect((a.cx - mid).abs() < 0.5 || a.w > (a.children.last.x + a.children.last.w - a.children.first.x).abs(), isTrue, reason: a.title);
        }
        for (final c in a.children) {
          expect(c.y > a.y + a.h, isTrue, reason: 'الابن تحت أبيه');
        }
      }
      expect(m.root.children.length, 2, reason: 'أولتان تحت سيرفرٍ واحد');
    });

    test('إخفاء الصناديق: الموزّع وحده بعدد المخفيّ، وصناديق المنفذ المباشرة مجموعةٌ واحدة', () {
      final m = FiberMapModel.build(olts: [input()], layout: layout, showBoxes: false, showLoose: false);
      final o = m.root.children.single;
      final sp = o.children.first.children.single;
      expect(sp.kind, FiberMapKind.splitter);
      expect(sp.children, isEmpty);
      expect(sp.hiddenBoxes, 2);
      final g = o.children[1].children.single;
      expect([g.hiddenBoxes, g.total], [1, 2]);
      expect(m.nodes.any((n) => n.kind == FiberMapKind.box || n.kind == FiberMapKind.loose), isFalse);
    });

    test('أولتٌ لم يُقرأ بعد: عقدته وحدها «يقرأ…»، والضغط يجد العقدة تحت الإصبع', () {
      final m = FiberMapModel.build(
          olts: [const FiberMapOlt(oltId: 9, name: 'جديد', pons: [], onus: [], ready: false)], layout: FiberLayout.empty);
      final o = m.root.children.single;
      expect(o.children, isEmpty);
      expect(o.sub, contains('يقرأ'));
      expect(m.hit(o.cx, o.y + 5)?.id, o.id);
      expect(m.hit(-5, -5), isNull);
    });

    testWidgets('الرسم يعمل نهاريّاً بلا أخطاء (عربيّ من اليمين)', (t) async {
      final m = FiberMapModel.build(olts: [input()], layout: layout);
      await t.pumpWidget(MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Center(
            child: CustomPaint(size: Size(m.width, m.height), painter: FiberMapPainter(m, FiberMapColors.of(), TextDirection.rtl)),
          ),
        ),
      ));
      expect(t.takeException(), isNull);
    });
  });
}
