// «الترابط» بين الأبراج — المنطق الخالص (١١ نوفمبر): من الرئيسيّ ومن الفرعيّ، مكان كلّ برجٍ على رسمٍ بعرض الهاتف، سير
// الترافيك وحال الوصلة من قراءات طرفيها، واقتراح الوصلات ممّا تقوله الأجهزة.
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/core/util/bidi.dart';
import 'package:rad_mysvcs/models/network_device.dart';
import 'package:rad_mysvcs/models/tower_layout.dart';
import 'package:rad_mysvcs/screens/network_devices/device_vitals.dart';
import 'package:rad_mysvcs/screens/network_devices/tower/tower_reading.dart';
import 'package:rad_mysvcs/screens/network_devices/tower/tower_topology_logic.dart';

NetworkDevice dev(int id, String name, int? region, {String type = 'link', String? mac, String status = 'online'}) => NetworkDevice(
      id: id,
      adminId: '2',
      regionId: region,
      name: name,
      type: type,
      brand: 'ubnt',
      ip: '10.0.0.$id',
      port: 443,
      mac: mac,
      lastStatus: status,
      createdAt: DateTime(2026, 11, 1),
    );

TowerLink link(int id, int a, int b) => TowerLink(id: id, aDeviceId: a, bDeviceId: b);

TowerReading rd({
  String? mode,
  int? clients,
  int? signal,
  int? ccq,
  int? rx,
  int? tx,
  int? down,
  int? up,
  int? freq,
  int? width,
  List<PeerLink> peers = const [],
}) =>
    TowerReading(
      at: DateTime(2026, 11, 11, 3),
      wireless: true,
      mode: mode,
      clients: clients ?? peers.length,
      signal: signal,
      quality: ccq,
      radioRxBps: rx,
      radioTxBps: tx,
      downBps: down,
      upBps: up,
      frequency: freq,
      channelWidth: width,
      peers: peers,
    );

const towers4 = [
  TopoTower(id: 1, name: 'البرج الرئيسي', devices: 7),
  TopoTower(id: 2, name: 'برج الحي', devices: 4),
  TopoTower(id: 3, name: 'برج المعامل', devices: 3),
  TopoTower(id: 4, name: 'برج الجامعة', devices: 5),
];

void main() {
  group('الرسم: من الرئيسيّ ومن الفرعيّ', () {
    // كلام المالك حرفيّاً: «برج a منطي ٣ لنكات ماستر والابراج الفرعي سليف وياه»
    final towerOf = {11: 1, 12: 1, 13: 1, 21: 2, 31: 3, 41: 4};
    final star = [link(1, 11, 21), link(2, 12, 31), link(3, 13, 41)];

    test('برجٌ رئيسيّ بثلاثة لنكات ⇒ هو الأعلى وحده والفرعيّات الثلاثة تحته، وكلّ وصلةٍ وصلةُ شجرة', () {
      final t = TowerTopology.build(towers: towers4, towerOfDevice: towerOf, links: star);
      expect([for (final r in t.rows) [for (final n in r) n.tower.id]], [
        [1],
        [4, 2, 3], // بترتيب الأسماء: الجامعة · الحي · المعامل
      ]);
      expect(t.rows.first.single.root, isTrue);
      expect(t.rows.first.single.level, 0);
      expect(t.rows[1].every((n) => n.level == 1 && !n.root), isTrue);
      expect(t.loose, isEmpty);
      expect(t.broken, isEmpty);
      expect(t.edges.map((e) => (e.from, e.to, e.tree, e.links.length)).toSet(), {(1, 2, true, 1), (1, 3, true, 1), (1, 4, true, 1)});
      expect([for (final id in [1, 2, 3, 4]) t.roleOf(id)], [TopoRole.main, TopoRole.sub, TopoRole.sub, TopoRole.sub]);
    });

    test('فرعيٌّ يغذّي برجاً بعده «موزّع»، وبرجٌ بلا لنك «غير مربوط» في قائمته', () {
      final t = TowerTopology.build(
        towers: [...towers4, const TopoTower(id: 5, name: 'برج القرية', devices: 2)],
        towerOfDevice: {...towerOf, 22: 2, 51: 5},
        links: [link(1, 11, 21), link(2, 22, 31)], // الرئيسي ⇐ الحي ⇐ المعامل
      );
      expect([for (final r in t.rows) [for (final n in r) n.tower.id]], [
        [1],
        [2],
        [3],
      ]);
      expect([t.roleOf(1), t.roleOf(2), t.roleOf(3)], [TopoRole.main, TopoRole.relay, TopoRole.sub]);
      expect(t.loose.map((x) => x.id), [4, 5], reason: 'الجامعة ثمّ القرية بالاسم');
      expect(t.roleOf(4), TopoRole.loose);
    });

    test('عدّة لنكات بين البرجين نفسيهما وصلةٌ واحدة تحملها كلّها', () {
      final t = TowerTopology.build(
        towers: towers4,
        towerOfDevice: {...towerOf, 22: 2},
        links: [link(1, 11, 21), link(2, 12, 22), link(3, 13, 41)],
      );
      final e = t.edges.firstWhere((e) => e.to == 2);
      expect(e.links.map((l) => l.id), [1, 2]);
      expect(t.edges.length, 2);
    });

    test('لنكٌ طرفاه في البرج نفسه (نُقل أحدهما) أو أحد جهازيه محذوف لا يُرسم ويُذكر', () {
      final t = TowerTopology.build(
        towers: towers4,
        towerOfDevice: {11: 1, 12: 1, 21: 2},
        links: [link(1, 11, 21), link(2, 11, 12), link(3, 12, 99)],
      );
      expect(t.broken.map((l) => l.id), [2, 3]);
      expect(t.edges.single.links.single.id, 1);
      expect(t.loose.map((x) => x.id), [4, 3]);
    });

    test('حلقةٌ بلا رأس: الأكثر تفرّعاً رأسُها، وكلّ برجٍ يُرسم مرّةً، والوصلة الراجعة ليست وصلة شجرة', () {
      final t = TowerTopology.build(
        towers: towers4,
        towerOfDevice: {11: 1, 12: 1, 21: 2, 22: 2, 31: 3, 32: 3},
        // 1⇐2 ، 2⇐3 ، 3⇐1 ، و 1⇐3 أيضاً ⇒ البرج 1 يتفرّع لاثنين
        links: [link(1, 11, 21), link(2, 22, 31), link(3, 32, 12), link(4, 12, 32)],
      );
      final ids = [for (final n in t.nodes) n.tower.id];
      expect(ids.toSet(), {1, 2, 3});
      expect(ids.length, 3, reason: 'لا برج مكرّر');
      expect(t.nodes.where((n) => n.root).single.tower.id, 1);
      expect(t.edges.where((e) => !e.tree).map((e) => (e.from, e.to)).toSet(), {(2, 3), (3, 1)});
      expect(t.roleOf(1), TopoRole.main);
    });

    test('مستوى يزيد عن عرض الهاتف يُلفّ صفوفاً — لا تمرير أفقيّ', () {
      final many = [
        const TopoTower(id: 1, name: 'الرئيسي', devices: 5),
        for (var i = 2; i <= 7; i++) TopoTower(id: i, name: 'فرعي $i', devices: 2),
      ];
      final t = TowerTopology.build(
        towers: many,
        towerOfDevice: {for (var i = 2; i <= 7; i++) 10 + i: 1, for (var i = 2; i <= 7; i++) 100 + i: i},
        links: [for (var i = 2; i <= 7; i++) link(i, 10 + i, 100 + i)],
        maxPerRow: 4,
      );
      expect([for (final r in t.rows) r.length], [1, 4, 2]);
      expect([for (final n in t.rows[1]) n.tower.name], ['فرعي 2', 'فرعي 3', 'فرعي 4', 'فرعي 5'], reason: 'ترتيبٌ طبيعيّ');
      expect(t.rows[2].every((n) => n.level == 1), isTrue);
    });
  });

  group('المواضع على عرض الهاتف', () {
    final towerOf = {11: 1, 12: 1, 13: 1, 21: 2, 31: 3, 41: 4};
    final star = [link(1, 11, 21), link(2, 12, 31), link(3, 13, 41)];

    test('كم برجاً يسع الصفّ: ٣٢٠ ⇒ ٣، و٣٦٠–٤٣٠ ⇒ ٤', () {
      expect([for (final w in [288.0, 326.0, 356.0, 396.0]) TopoLayout.perRow(w)], [3, 3, 4, 4]);
    });

    test('كلّ الأبراج داخل العرض ولا يتراكب اثنان، والرئيسيّ فوق فرعيّاته — بكلّ عرضٍ ومع غير المربوطة', () {
      for (final w in [288.0, 326.0, 356.0, 396.0, 640.0]) {
        final per = TopoLayout.perRow(w);
        final t = TowerTopology.build(
          towers: [
            ...towers4,
            for (var i = 5; i <= 10; i++) TopoTower(id: i, name: 'برج $i', devices: 1),
          ],
          towerOfDevice: towerOf,
          links: star,
          maxPerRow: per,
        );
        final l = TopoLayout.compute(t, w);
        final rects = [for (final id in l.centers.keys) l.rectOf(id)];
        expect(rects.length, 10);
        for (final r in rects) {
          expect(r.left >= 0 && r.right <= w, isTrue, reason: 'w=$w $r');
          expect(r.top >= 0 && r.bottom <= l.size.height, isTrue, reason: 'w=$w $r h=${l.size.height}');
        }
        for (var i = 0; i < rects.length; i++) {
          for (var j = i + 1; j < rects.length; j++) {
            expect(rects[i].overlaps(rects[j]), isFalse, reason: 'w=$w: ${rects[i]} × ${rects[j]}');
          }
        }
        expect(l.centers[1]!.dy < l.centers[2]!.dy, isTrue);
        expect(l.looseTop, isNotNull);
        expect(l.looseTop! > l.rectOf(2).bottom, isTrue, reason: 'عنوان «غير مربوطة» تحت آخر صفٍّ مربوط');
        expect(l.size.height, closeTo(rects.map((r) => r.bottom).reduce((a, b) => a > b ? a : b) + TopoLayout.pad, 0.01));
      }
    });

    test('بالعربيّ (RTL) الأوّل يميناً — والرئيسيّ الوحيد في الوسط بالحالين', () {
      final t = TowerTopology.build(towers: towers4, towerOfDevice: towerOf, links: star);
      final ltr = TopoLayout.compute(t, 360);
      final rtl = TopoLayout.compute(t, 360, rtl: true);
      expect(ltr.centers[1]!.dx, 180);
      expect(rtl.centers[1]!.dx, 180);
      final first = t.rows[1].first.tower.id;
      final last = t.rows[1].last.tower.id;
      expect(ltr.centers[first]!.dx < ltr.centers[last]!.dx, isTrue);
      expect(rtl.centers[first]!.dx > rtl.centers[last]!.dx, isTrue);
    });

    test('بلا أيّ لنك: الأبراج صفوفاً بلا عنوان «غير مربوطة»', () {
      final t = TowerTopology.build(towers: towers4, towerOfDevice: towerOf, links: const []);
      final l = TopoLayout.compute(t, 360);
      expect(t.rows, isEmpty);
      expect(l.looseTop, isNull);
      expect(l.centers.length, 4);
    });

    test('نقطتا الوصلة: من أسفل الرئيسيّ لأعلى الفرعيّ تاركةً مكان حبّة السرعة؛ ومن الجانب حين يتجاوران', () {
      const a = Rect.fromLTWH(140, 10, 80, 100);
      const below = Rect.fromLTWH(20, 168, 80, 100);
      final v = TopoRoute.direct(a, below, pillRoom: 26);
      expect(v.from, a.bottomCenter);
      expect(v.to, const Offset(60, 142));
      expect(v.viaChannel, isFalse);
      const beside = Rect.fromLTWH(260, 10, 80, 100);
      final h = TopoRoute.direct(a, beside);
      expect([h.from.dx, h.to.dx], [220, 260]);
      final back = TopoRoute.direct(below, a);
      expect([back.from, back.to], [below.topCenter, a.bottomCenter], reason: 'وصلةٌ راجعة للأعلى');
    });

    // بلاغ المحاكاة (١١ نوفمبر): ستّة فرعيّات على هاتف ٣٦٠ تُلفّ صفّين، ووصلة الصفّ الثاني كانت تمرّ خلف أبراج الأوّل فتبدو
    // خارجةً منها — كأنّ الفرعيّ يغذّي فرعيّاً.
    group('مستوى يُلفّ: الوصلة تنزل في الممرّ بين الأبراج لا من خلفها', () {
      TowerTopology six(double w) => TowerTopology.build(
            towers: [
              const TopoTower(id: 1, name: 'الرئيسي', devices: 5),
              for (var i = 2; i <= 7; i++) TopoTower(id: i, name: 'فرعي $i', devices: 2),
            ],
            towerOfDevice: {for (var i = 2; i <= 7; i++) 10 + i: 1, for (var i = 2; i <= 7; i++) 100 + i: i},
            links: [for (var i = 2; i <= 7; i++) link(i, 10 + i, 100 + i)],
            maxPerRow: TopoLayout.perRow(w),
            wrapPerRow: TopoLayout.perGrid(w),
          );

      test('كم عموداً حين يُلفّ: ٣٢٠ ⇒ ٢، ٣٦٠ و٣٩٠ ⇒ ٣، ٤٣٠ ⇒ ٤', () {
        expect([for (final w in [286.0, 326.0, 356.0, 396.0]) TopoLayout.perGrid(w)], [2, 3, 3, 4]);
      });

      for (final rtl in [false, true]) {
        for (final w in [286.0, 326.0, 356.0, 396.0]) {
          test('عرض $w ${rtl ? 'RTL' : 'LTR'}: ممرّ كلّ وصلةٍ متخطّية لا يمسّ برجاً ولا حبّة سرعة في الصفوف التي يعبرها', () {
            final t = six(w);
            final l = TopoLayout.compute(t, w, rtl: rtl);
            expect(l.slot, isNotNull);
            var crossing = 0;
            for (final e in t.edges) {
              final r = l.routeOf(e, pillRoom: 26);
              final rowP = l.rowOf[e.from]!;
              final rowC = l.rowOf[e.to]!;
              expect(r.from, l.rectOf(e.from).bottomCenter);
              expect(r.to, Offset(l.centers[e.to]!.dx, l.rectOf(e.to).top - 26));
              if (rowC == rowP + 1) {
                expect(r.viaChannel, isFalse, reason: 'الصفّ التالي مباشرةً');
                continue;
              }
              crossing++;
              expect(r.viaChannel, isTrue);
              final x = r.channelX!;
              expect(x >= 0 && x <= w, isTrue, reason: 'الممرّ داخل الرسم');
              expect(r.channelTop! < r.channelBottom!, isTrue);
              for (final n in t.nodes) {
                final row = l.rowOf[n.tower.id]!;
                if (row <= rowP || row >= rowC) continue;
                final rect = l.rectOf(n.tower.id);
                expect(x < rect.left - 1 || x > rect.right + 1, isTrue, reason: 'الممرّ $x يمسّ ${n.tower.name} $rect');
                // حبّة سرعة ذلك البرج (بأقصى عرضها) فوقه
                final half = l.pillMaxFor(n.tower.id) / 2;
                expect((x - rect.center.dx).abs() >= half + 2, isTrue, reason: 'الممرّ $x يمسّ حبّة ${n.tower.name}');
                expect(r.channelTop! <= rect.top - 26 && r.channelBottom! >= rect.bottom, isTrue, reason: 'يعبر الصفّ كلّه');
              }
            }
            expect(crossing, greaterThan(0));
            // والأبراج ما زالت داخل العرض بلا تراكب
            final rects = [for (final id in l.centers.keys) l.rectOf(id)];
            for (var i = 0; i < rects.length; i++) {
              expect(rects[i].left >= 0 && rects[i].right <= w, isTrue);
              for (var j = i + 1; j < rects.length; j++) {
                expect(rects[i].overlaps(rects[j]), isFalse);
              }
            }
          });
        }
      }

      test('لكلّ عمودٍ ممرّه: وصلتان لعمودين مختلفين لا تتشاركان ممرّاً', () {
        final t = six(326);
        final l = TopoLayout.compute(t, 326);
        final xs = [
          for (final e in t.edges)
            if (l.routeOf(e).viaChannel) l.routeOf(e).channelX!,
        ];
        expect(xs.length, 3);
        expect(xs.toSet().length, 3);
      });

      test('بلا لفّ لا شبكة ولا ممرّات، وحبّات الصفّ المزدحم لا تتراكب', () {
        final t = TowerTopology.build(
          towers: [const TopoTower(id: 1, name: 'الرئيسي'), for (var i = 2; i <= 5; i++) TopoTower(id: i, name: 'فرعي $i')],
          towerOfDevice: {for (var i = 2; i <= 5; i++) 10 + i: 1, for (var i = 2; i <= 5; i++) 100 + i: i},
          links: [for (var i = 2; i <= 5; i++) link(i, 10 + i, 100 + i)],
          maxPerRow: TopoLayout.perRow(356),
          wrapPerRow: TopoLayout.perGrid(356),
        );
        final l = TopoLayout.compute(t, 356);
        expect([for (final r in t.rows) r.length], [1, 4], reason: 'أربعةٌ تسعها شاشة ٣٩٠');
        expect(l.slot, isNull);
        expect(t.edges.every((e) => !l.routeOf(e).viaChannel), isTrue);
        final xs = [for (var i = 2; i <= 5; i++) l.centers[i]!.dx]..sort();
        expect(l.pillMaxFor(2) <= xs[1] - xs[0], isTrue, reason: 'حبّتان متجاورتان بأقصى عرضهما لا تتراكبان');
      });
    });
  });

  group('سير الترافيك وحال الوصلة', () {
    test('ما ينزل للفرعيّ = ما يستقبله طرف الفرعيّ على الهواء (وما يرسله طرف الرئيسيّ إن لم يُقرأ الفرعيّ)', () {
      final both = LinkFlow.of(
        ra: rd(tx: 90000000, rx: 11000000, signal: -55, ccq: 97),
        rb: rd(mode: 'sta', rx: 84000000, tx: 12000000, signal: -57, ccq: 95),
      );
      expect([both.toSubBps, both.toMainBps], [84000000, 12000000]);
      expect([both.signal, both.ccq, both.state], [-57, 95, LinkState.ok]);
      final mainOnly = LinkFlow.of(ra: rd(tx: 90000000, rx: 11000000, signal: -55));
      expect([mainOnly.toSubBps, mainOnly.toMainBps, mainOnly.state], [90000000, 11000000, LinkState.ok]);
    });

    test('بلا واجهةٍ لاسلكيّة مقروءة (airFiber): «التنزيل» كما يحسبه البرج', () {
      final f = LinkFlow.of(rb: rd(down: 300000000, up: 40000000, signal: -48));
      expect([f.toSubBps, f.toMainBps], [300000000, 40000000]);
    });

    test('الحال بكلمات القسم نفسها: ممتاز · متوسّط · ضعيف (أسوأ الإشارة والجودة)', () {
      LinkState of({int? signal, int? ccq}) => LinkFlow.of(ra: rd(signal: signal, ccq: ccq, tx: 1)).state;
      expect(of(signal: -60, ccq: 90), LinkState.ok);
      expect(of(signal: -72, ccq: 90), LinkState.fair);
      expect(of(signal: -60, ccq: 55), LinkState.fair);
      expect(of(signal: -85, ccq: 90), LinkState.weak);
      expect(of(signal: -60, ccq: 30), LinkState.weak);
      expect(of(), LinkState.ok, reason: 'طرازٌ لا يعطي إشارةً ولا جودة — يُقرأ ولا يُتّهم');
    });

    test('🚨 «واقع» بحكم «لا يردّ» وحده — وما لم يُقرأ «لم يُقرأ» بلا أرقام، لا صفر', () {
      final down = LinkFlow.of(ra: rd(tx: 5, signal: -50), bDown: true);
      expect([down.state, down.subDown, down.mainDown, down.toSubBps], [LinkState.down, true, false, null]);
      const unread = LinkFlow();
      expect(LinkFlow.of().state, LinkState.unknown);
      expect([unread.toSubBps, unread.toMainBps, unread.signal], [null, null, null]);
    });

    test('عدّة لنكات لبرجٍ واحد: المجموع، و«واقع» حين تقع كلّها وحده — لنكٌ سليم يُبقي الفرع موصولاً', () {
      final ok = LinkFlow.of(rb: rd(rx: 50, tx: 5, signal: -55));
      final down = LinkFlow.of(aDown: true);
      final mixed = LinkFlow.merge([ok, down]);
      expect([mixed.state, mixed.toSubBps, mixed.toMainBps], [LinkState.weak, 50, 5]);
      expect(LinkFlow.merge([down, LinkFlow.of(bDown: true)]).state, LinkState.down);
      final two = LinkFlow.merge([ok, LinkFlow.of(rb: rd(rx: 30, tx: 2, signal: -74))]);
      expect([two.state, two.toSubBps, two.signal], [LinkState.fair, 80, -74]);
      expect(LinkFlow.merge([ok, const LinkFlow()]).state, LinkState.ok, reason: 'ما لم يُقرأ لا يغلب المقروء');
      expect(LinkFlow.merge(const []).state, LinkState.unknown);
    });
  });

  group('اقتراح الوصلات', () {
    final devices = [
      dev(11, 'AF الرئيسي', 1, mac: '00:11:22:33:44:01'),
      dev(21, 'AF الحي', 2, mac: '00-11-22-33-44-02'),
      dev(31, 'PB المعامل', 3),
      dev(12, 'PB الرئيسي 2', 1),
      dev(13, 'سكتر 1', 1, type: 'sector'),
    ];

    test('طرفٌ يرى الآخر بعنوانه ⇒ مقترحٌ باتّجاه نقطة الوصول ⇐ المستقبِل', () {
      final s = TowerLinkSuggest.find(
        devices: devices,
        readings: {
          // المستقبِل (الفرعيّ) يرى نقطة الوصول
          21: rd(mode: 'sta', peers: const [PeerLink(name: 'x', mac: '00:11:22:33:44:01')]),
          11: rd(mode: 'ap', peers: const [PeerLink(name: 'y', mac: '00:11:22:33:44:02')]),
        },
        links: const [],
      );
      expect(s.length, 1);
      expect([s.single.a.id, s.single.b.id, s.single.why], [11, 21, 'يراه بعنوانه']);
    });

    test('العنوان اللاسلكيّ غير المسجَّل: المتتالي أو المختلف ببتّ «محلّيّ» يُطابق — والبعيد لا، وقريبان معاً لا يُخمَّن بينهما', () {
      expect(TowerLinkSuggest.macNear('001122334401', '001122334402'), isTrue, reason: 'ether ⇒ wlan (+1)');
      expect(TowerLinkSuggest.macNear('788a20aabbcc', '7a8a20aabbcc'), isTrue, reason: 'بتّ محلّيّ في أوّل بايت');
      expect(TowerLinkSuggest.macNear('001122334401', '001122334409'), isFalse);
      expect(TowerLinkSuggest.macNear('001122334401', '001122344402'), isFalse, reason: 'بايتان مختلفان');
      final s = TowerLinkSuggest.find(
        devices: devices,
        readings: {
          // يرى واجهة الحيّ اللاسلكيّة (…03) والمسجَّل منفذها (…02)
          11: rd(mode: 'ap', peers: const [PeerLink(name: 'x', mac: '00:11:22:33:44:03')]),
        },
        links: const [],
      );
      expect([for (final x in s) (x.a.id, x.b.id)], [(11, 21)]);
      // جهازان قريبان من العنوان نفسه ⇒ لا تخمين
      final twins = [...devices, dev(41, 'AF آخر', 4, mac: '00:11:22:33:44:04')];
      expect(
        TowerLinkSuggest.find(
          devices: twins,
          readings: {11: rd(mode: 'ap', peers: const [PeerLink(name: 'x', mac: '00:11:22:33:44:03')])},
          links: const [],
        ),
        isEmpty,
      );
    });

    test('بالاسم حين لا ماك — ولا يُقترح ما بين جهازَي البرج نفسه', () {
      final s = TowerLinkSuggest.find(
        devices: devices,
        readings: {
          12: rd(mode: 'ap', peers: const [PeerLink(name: 'pb المعامل'), PeerLink(name: 'سكتر 1')]),
        },
        links: const [],
      );
      expect([for (final x in s) (x.a.id, x.b.id, x.why)], [(12, 31, 'يراه باسمه')]);
    });

    test('ما رُبط لا يُقترح ثانيةً (بأيّ اتّجاه)، ولا فرعيٌّ مربوط', () {
      final readings = {
        11: rd(mode: 'ap', peers: const [PeerLink(name: 'x', mac: '001122334402')]),
      };
      expect(TowerLinkSuggest.find(devices: devices, readings: readings, links: [link(1, 21, 11)]), isEmpty);
      expect(TowerLinkSuggest.find(devices: devices, readings: readings, links: [link(1, 12, 21)]), isEmpty);
      expect(TowerLinkSuggest.find(devices: devices, readings: readings, links: const []).length, 1);
    });

    test('التردّد نفسه: نقطة وصولٍ بطرفٍ واحد ومستقبِلٌ وحدهما عليه — وثلاثةٌ على التردّد لا تُقترح', () {
      final pair = {
        12: rd(mode: 'ap-bridge', clients: 1, freq: 5745, width: 40),
        31: rd(mode: 'station', clients: 1, freq: 5745, width: 40),
      };
      final s = TowerLinkSuggest.find(devices: devices, readings: pair, links: const []);
      expect([for (final x in s) (x.a.id, x.b.id, x.why)], [(12, 31, 'التردّد نفسه')]);
      final crowded = {...pair, 21: rd(mode: 'station', clients: 1, freq: 5745, width: 40)};
      expect(TowerLinkSuggest.find(devices: devices, readings: crowded, links: const []), isEmpty);
      // سكترٌ بمشتركين كثر على التردّد نفسه ليس لنكاً
      final sector = {12: rd(mode: 'ap-bridge', clients: 14, freq: 5745, width: 40), 31: pair[31]!};
      expect(TowerLinkSuggest.find(devices: devices, readings: sector, links: const []), isEmpty);
    });
  });

  // ── ١١ نوفمبر صباحاً — المالك: «اكو ابراج ترتبط مع بعضها فايبر… مرات مو لنك يعني مباشر كيبل ضوئي بين سوجات» ──
  group('الكيبل الضوئيّ بين سويجين', () {
    PortTraffic port(String name, {bool up = true, int? rx, int? tx, String? speed, double? light, bool half = false, bool physical = true}) =>
        PortTraffic(name: name, up: up, rxBps: rx, txBps: tx, linkSpeed: speed, sfpRx: light, halfDuplex: half, physical: physical);
    TowerReading sw(List<PortTraffic> ports) => TowerReading(at: DateTime(2026, 11, 11, 8), ports: ports);

    test('النموذج: النوع والمنفذان من الخادم، القلب يبدّل المنفذين مع الطرفين، واللنك اللاسلكيّ بلا منافذ', () {
      final f = TowerLink.fromJson({'id': 7, 'a_device_id': 100, 'b_device_id': 200, 'kind': 'fiber', 'a_port': ' sfp-sfpplus1 ', 'b_port': 'sfp1'})!;
      expect([f.kind, f.isFiber, f.aPort, f.bPort], [TowerLinkKind.fiber, true, 'sfp-sfpplus1', 'sfp1']);
      final flipped = f.flipped();
      expect([flipped.aDeviceId, flipped.bDeviceId, flipped.aPort, flipped.bPort, flipped.kind], [200, 100, 'sfp1', 'sfp-sfpplus1', TowerLinkKind.fiber]);
      expect(f == TowerLink.fromJson({'id': 7, 'a_device_id': 100, 'b_device_id': 200, 'kind': 'fiber', 'a_port': 'sfp-sfpplus1', 'b_port': 'sfp1'}), isTrue);
      expect(f == TowerLink.fromJson({'id': 7, 'a_device_id': 100, 'b_device_id': 200, 'kind': 'fiber', 'a_port': 'sfp-sfpplus1', 'b_port': 'sfp2'}), isFalse);
      // خادمٌ قبل الهجرة 087 (بلا kind) ⇒ لنكٌ لاسلكيّ؛ ومنفذٌ على لاسلكيّ يُهمل
      final old = TowerLink.fromJson({'id': 1, 'a_device_id': 11, 'b_device_id': 21})!;
      expect([old.kind, old.isFiber, old.aPort], [TowerLinkKind.radio, false, null]);
      expect(TowerLink.fromJson({'id': 1, 'a_device_id': 11, 'b_device_id': 21, 'kind': 'radio', 'b_port': 'ether1'})!.bPort, isNull);
      final lay = TowerLayouts.fromJson({'success': true, 'links': [], 'links_ready': true, 'fiber_ready': true});
      expect([lay.linksReady, lay.fiberReady], [true, true]);
      expect(TowerLayouts.fromJson({'success': true, 'links': [], 'links_ready': true}).fiberReady, isFalse, reason: 'خادمٌ أقدم');
    });

    test('قراءة السويج: المنفذ باسمه (بلا حالة أحرف)، والسلكيّة وحدها تصلح طرفَ كيبل', () {
      final r = sw([port('sfp-sfpplus1'), port('ether2'), port('wlan1'), port('bridge1', physical: false)]);
      expect(r.port('SFP-SFPPLUS1')?.name, 'sfp-sfpplus1');
      expect([r.port('sfp9'), r.port(null), r.port('  ')], [null, null, null]);
      expect(r.wiredPorts.map((p) => p.name).toList(), ['sfp-sfpplus1', 'ether2']);
    });

    test('🚨 ما يعبر الكيبل = ما يعبر منفذه بعينه — لا «أنشط منفذ» في السويج', () {
      // سويج الفرعيّ: منفذ الكيبل sfp1 يستقبل 340 ميغا من الرئيسيّ؛ ومنفذٌ آخر (ether5) أنشط منه
      final sub = sw([port('sfp1', rx: 340000000, tx: 28000000, speed: '10Gbps', light: -7.1), port('ether5', rx: 900000000, tx: 900000000, speed: '1Gbps')]);
      final main = sw([port('sfp-sfpplus1', tx: 342000000, rx: 28500000, speed: '10Gbps', light: -6.4), port('sfp-sfpplus2', tx: 5, rx: 5)]);
      final f = LinkFlow.ofFiber(ra: main, rb: sub, aPort: 'sfp-sfpplus1', bPort: 'sfp1');
      expect([f.fiber, f.state, f.toSubBps, f.toMainBps], [true, LinkState.ok, 340000000, 28000000]);
      expect([f.light, f.linkSpeed, f.signal, f.ccq], [-7.1, '10Gbps', null, null], reason: 'أضعف الضوءين، ولا إشارة ولا CCQ لكيبل');
      // الفرعيّ لم يُقرأ ⇒ من منفذ الرئيسيّ: ما يرسله ينزل للفرع
      final onlyMain = LinkFlow.ofFiber(ra: main, aPort: 'sfp-sfpplus1', bPort: 'sfp1');
      expect([onlyMain.state, onlyMain.toSubBps, onlyMain.toMainBps], [LinkState.ok, 342000000, 28500000]);
      // منفذ الفرعيّ وحده محدَّد
      final onlySubPort = LinkFlow.ofFiber(ra: main, rb: sub, bPort: 'sfp1');
      expect([onlySubPort.toSubBps, onlySubPort.light], [340000000, -7.1]);
    });

    test('🚨 «واقع» بدليل: السويج يردّ ويقول المنفذ طافٍ — أو طرفٌ لا يردّ؛ ومنفذٌ شغّال بلا عدّادات «يعمل» بلا رقم', () {
      final up = sw([port('sfp1', rx: 10, tx: 10)]);
      final off = sw([port('sfp1', up: false)]);
      final a = LinkFlow.ofFiber(ra: up, rb: off, aPort: 'sfp1', bPort: 'sfp1');
      expect([a.state, a.subPortDown, a.mainPortDown, a.subDown, a.toSubBps], [LinkState.down, true, false, false, null]);
      final b = LinkFlow.ofFiber(ra: off, rb: up, aPort: 'sfp1', bPort: 'sfp1');
      expect([b.state, b.mainPortDown, b.subPortDown], [LinkState.down, true, false]);
      final dead = LinkFlow.ofFiber(ra: up, aPort: 'sfp1', bPort: 'sfp1', bDown: true);
      expect([dead.state, dead.subDown, dead.subPortDown, dead.fiber], [LinkState.down, true, false, true]);
      // قراءةٌ عبر الـVPN: الحال والسرعة بلا عدّادات
      final vpn = LinkFlow.ofFiber(rb: sw([port('sfp1', speed: '1Gbps')]), bPort: 'sfp1');
      expect([vpn.state, vpn.toSubBps, vpn.linkSpeed], [LinkState.ok, null, '1Gbps']);
      expect(TopoText.stateOf(vpn), 'يعمل');
    });

    test('بلا منفذٍ محدَّد لا يُعرف أيّ منفذٍ يُقرأ ⇒ «بلا منفذ» بلا أرقام؛ ومنفذٌ غاب عن الجهاز يُسمّى', () {
      final busy = sw([port('ether5', rx: 900000000, tx: 900000000)]);
      final unset = LinkFlow.ofFiber(ra: busy, rb: busy);
      expect([unset.state, unset.portIssue, unset.toSubBps, unset.fiber], [LinkState.unknown, FiberPortIssue.unset, null, true]);
      expect(TopoText.stateOf(unset), 'بلا منفذ');
      final missing = LinkFlow.ofFiber(ra: busy, rb: busy, bPort: 'sfp1');
      expect([missing.state, missing.portIssue, missing.missingPort], [LinkState.unknown, FiberPortIssue.missing, 'sfp1']);
      expect(TopoText.stateOf(missing), 'المنفذ غير موجود');
      // الجهاز لم يُقرأ بعد (أو لا يعرض منافذه) ⇒ «لم يُقرأ» لا «غير موجود»
      final unread = LinkFlow.ofFiber(bPort: 'sfp1');
      expect([unread.state, unread.portIssue], [LinkState.unknown, null]);
      expect(TopoText.stateOf(unread), 'لم يُقرأ');
      expect(LinkFlow.ofFiber(rb: sw(const []), bPort: 'gpon-uplink').portIssue, isNull, reason: 'جهازٌ بلا منافذ مقروءة');
    });

    test('الانتباه بحدَّي «الفحص الشامل»: ضوءٌ تحت ‎−25 ضعيف وتحت ‎−30 ضعيف جدّاً، وhalf-duplex و≤10M — وبلا ضوءٍ مقروء «يعمل»', () {
      LinkFlow of({double? light, String? speed, bool half = false}) =>
          LinkFlow.ofFiber(rb: sw([port('sfp1', rx: 1, tx: 1, light: light, speed: speed, half: half)]), bPort: 'sfp1');
      expect([of(light: -7).state, TopoText.stateOf(of(light: -7))], [LinkState.ok, 'يعمل']);
      expect([of(light: -24.9).state, of(light: -25).state], [LinkState.ok, LinkState.ok], reason: 'الحدّ نفسه سليم (sfp < −25)');
      expect([of(light: -26.5).state, TopoText.stateOf(of(light: -26.5))], [LinkState.fair, 'ضوء ضعيف']);
      expect([of(light: -31).state, TopoText.stateOf(of(light: -31))], [LinkState.weak, 'ضوء ضعيف جدّاً']);
      expect([of(half: true).state, TopoText.stateOf(of(half: true))], [LinkState.fair, 'half-duplex']);
      expect([of(speed: '10Mbps').state, TopoText.stateOf(of(speed: '10Mbps'))], [LinkState.fair, 'سرعة واطية']);
      expect(of(speed: '100Mbps').state, LinkState.ok, reason: 'كيبل 100M قديم ليس عطلاً');
      expect(of().state, LinkState.ok, reason: 'سويجٌ لا يقرأ ضوء الـSFP لا يُتّهم');
      // أبطأ السرعتين وأضعف الضوءين من الطرفين
      final both = LinkFlow.ofFiber(
        ra: sw([port('a', rx: 1, tx: 1, speed: '10Gbps', light: -5)]),
        rb: sw([port('b', rx: 1, tx: 1, speed: '1000M', light: -12.5)]),
        aPort: 'a',
        bPort: 'b',
      );
      expect([both.linkSpeed, both.light], ['1000M', -12.5]);
    });

    test('كيبلان لبرجٍ واحد: المجموع وأضعف الضوء، و«واقع» حين يقعان معاً وحده؛ وكيبلٌ مع لنك لاسلكيّ وصلةٌ مختلطة', () {
      final c1 = LinkFlow.ofFiber(rb: sw([port('sfp1', rx: 300, tx: 30, light: -6)]), bPort: 'sfp1');
      final c2 = LinkFlow.ofFiber(rb: sw([port('sfp2', rx: 200, tx: 20, light: -27)]), bPort: 'sfp2');
      final two = LinkFlow.merge([c1, c2]);
      expect([two.fiber, two.toSubBps, two.toMainBps, two.light, two.state], [true, 500, 50, -27, LinkState.fair]);
      final off = LinkFlow.ofFiber(rb: sw([port('sfp2', up: false)]), bPort: 'sfp2');
      expect(LinkFlow.merge([c1, off]).state, LinkState.weak, reason: 'كيبلٌ سليم يُبقي الفرع موصولاً');
      final bothOff = LinkFlow.merge([off, off]);
      expect([bothOff.state, bothOff.subPortDown], [LinkState.down, true]);
      final radio = LinkFlow.of(rb: rd(rx: 50, tx: 5, signal: -55, ccq: 97));
      final mixed = LinkFlow.merge([c1, radio]);
      expect([mixed.fiber, mixed.toSubBps, mixed.light, mixed.signal], [false, 350, null, -55]);
    });

    test('الرسم: وصلةٌ كلّها كيابل «كيبل»، والمختلطة لا؛ والعدّ كلّ نوعٍ باسمه', () {
      const fiber = TowerLink(id: 1, aDeviceId: 100, bDeviceId: 200, kind: TowerLinkKind.fiber);
      const radio = TowerLink(id: 2, aDeviceId: 11, bDeviceId: 21);
      expect(const TopoEdge(from: 1, to: 2, links: [fiber]).fiber, isTrue);
      expect(const TopoEdge(from: 1, to: 2, links: [fiber, radio]).fiber, isFalse);
      expect(const TopoEdge(from: 1, to: 2, links: [radio]).fiber, isFalse);
      expect([for (final n in [0, 1, 2, 5, 12]) TopoText.cables(n)], ['لا كيابل', 'كيبل واحد', 'كيبلان', '5 كيابل', '12 كيبلاً']);
      expect(TopoText.linkCounts(radio: 3, fiber: 0), '3 لنكات', reason: 'بلا كيابل كما كان');
      expect(TopoText.linkCounts(radio: 0, fiber: 0), 'لا لنكات');
      expect(TopoText.linkCounts(radio: 0, fiber: 2), 'كيبلان');
      expect(TopoText.linkCounts(radio: 1, fiber: 2), 'لنك واحد · كيبلان');
    });

    test('أرقام السطر بنوعها: اللنك إشارته وCCQ، والكيبل سرعة منفذه وضوؤه', () {
      expect([for (final v in ['10Gbps', '1Gbps', '1000M', '100Mbps', '2.5Gbps', null, 'auto']) TopoText.speed(v)], ['10G', '1G', '1G', '100M', '2.5G', '—', 'auto']);
      expect([TopoText.light(-7.123), TopoText.light(null)], ['-7.1 dBm', '—']);
      final cable = LinkFlow.ofFiber(rb: sw([port('sfp1', rx: 1, tx: 1, speed: '10Gbps', light: -7.1)]), bPort: 'sfp1');
      // الرقم السالب بعد كلمةٍ عربيّة معزولٌ اتّجاهيّاً — وإلّا انقلبت إشارته لآخره («7.1-»)
      expect(TopoText.lightFact(-7.1), 'ضوء ${iso('-7.1 dBm')}');
      expect(TopoText.facts(cable), ['10G', TopoText.lightFact(-7.1)]);
      expect(TopoText.facts(LinkFlow.ofFiber(rb: sw([port('ether1', rx: 1, tx: 1)]), bPort: 'ether1')), isEmpty);
      final radio = LinkFlow.of(rb: rd(rx: 1, tx: 1, signal: -52, ccq: 98));
      expect(TopoText.facts(radio), ['-52 dBm', 'CCQ 98٪']);
      expect([TopoText.stateOf(radio), TopoText.stateOf(const LinkFlow())], ['ممتاز', 'لم يُقرأ'], reason: 'اللنك بكلماته كما كان');
    });

    test('🚨 منافذ العدّ (قراءة الخادم «٣ من ٥» بلا أسماء) ليست منافذ: لا «واقع» ولا «غير موجود» منها، ولا تُعرض للاختيار', () {
      // قراءة الخادم عبر الـVPN بلا قائمة المنافذ: تُصاغ ether1…ether5 للعدّ، والأوائل «شغّالة» — ليست حال منفذٍ بعينه
      final counted = DeviceVitals.fromVpn({'kind': 'ros', 'cpu': 5, 'ports': {'up': 3, 'total': 5}}).detail!;
      expect(counted.ports.length, 5);
      expect(counted.ports.every((p) => p.placeholder), isTrue);
      final r = TowerReading.fromProbe(ProbeResult(vitals: const [], detail: counted, counters: const {}));
      expect([r.portsUp, r.portsTotal], [3, 5], reason: 'العدّ يبقى');
      expect(r.ports, isEmpty);
      expect(r.wiredPorts, isEmpty, reason: 'منتقي المنفذ لا يعرض أسماءً مصطنعة');
      expect(r.port('ether4'), isNull);
      // كيبلٌ منفذه ether4 («طافٍ» في العدّ المصطنع) أو ether1 («شغّال»): لا حكم — لم يُقرأ
      for (final name in ['ether4', 'ether1', 'sfp1']) {
        final f = LinkFlow.ofFiber(rb: r, bPort: name);
        expect([f.state, f.subPortDown, f.portIssue], [LinkState.unknown, false, null], reason: name);
      }
      // وقراءة الخادم المفصّلة (pl) بأسماء الجهاز تُطابَق: حال المنفذ وسرعته وضوؤه — بلا عدّادات فلا رقم
      final listed = DeviceVitals.fromVpn({
        'kind': 'ros',
        'ports': {'up': 1, 'total': 2},
        'pl': [
          {'n': 'sfp-sfpplus1', 'r': true, 'sp': '10Gbps', 'sfp': -6.5},
          {'n': 'ether1', 'r': false},
        ],
      }).detail!;
      expect(listed.ports.any((p) => p.placeholder), isFalse);
      final r2 = TowerReading.fromProbe(ProbeResult(vitals: const [], detail: listed, counters: const {}));
      expect(r2.wiredPorts.map((p) => p.name), ['sfp-sfpplus1', 'ether1']);
      final up = LinkFlow.ofFiber(rb: r2, bPort: 'sfp-sfpplus1');
      expect([up.state, up.toSubBps, up.light, up.linkSpeed], [LinkState.ok, null, -6.5, '10Gbps']);
      final off = LinkFlow.ofFiber(rb: r2, bPort: 'ether1');
      expect([off.state, off.subPortDown], [LinkState.down, true]);
      expect(LinkFlow.ofFiber(rb: r2, bPort: 'sfp9').portIssue, FiberPortIssue.missing);
    });

    group('أيّ منفذٍ هو منفذ الكيبل: ما يرسله طرفٌ يستقبله الآخر', () {
      // منفذ الرئيسيّ نحو هذا البرج: يرسل 615 وينزل له 71
      final peer = port('sfp-sfpplus1', tx: 615000000, rx: 71000000);
      // سويج الفرعيّ: منفذ الكيبل يستقبل ما أُرسل له، ومنفذ السكتر يرسله لمشتركيه (فيخالف بالاتّجاهين)
      List<PortTraffic> sub() => [
            port('sfp1', rx: 612000000, tx: 70000000),
            port('ether1', rx: 69000000, tx: 600000000),
            port('ether2', rx: 900000, tx: 12000000),
            port('sfp2', up: false),
          ];

      test('المنفذ الذي يعبره المقدار نفسه معكوساً — واحدٌ بعينه', () {
        expect(FiberPortMatch.find(sub(), peer), 'sfp1');
        // والعكس: منفذ الرئيسيّ يُعرف من منفذ الفرعيّ (العلاقة نفسها من الطرف الآخر)
        final main = [peer, port('sfp-sfpplus2', tx: 231000000, rx: 30000000), port('ether1', tx: 880000000, rx: 990000000)];
        expect(FiberPortMatch.find(main, port('sfp1', rx: 612000000, tx: 70000000)), 'sfp-sfpplus1');
      });

      test('اتّجاهٌ واحد يطابق والآخر يخالف ⇒ ليس هو (منفذ السكتر يرسل ما وصل لا ما يستقبله)', () {
        // يستقبل ما يطابق (≈615)، لكنّه يرسل 400 والطرف الآخر يستقبل 71
        expect(FiberPortMatch.find([port('x', rx: 612000000, tx: 400000000)], peer), isNull);
      });

      test('منفذان يطابقان (كيبلان متوازيان) ⇒ لا تخمين', () {
        expect(FiberPortMatch.find([...sub(), port('sfp3', rx: 620000000, tx: 72000000)], peer), isNull);
      });

      test('اتّجاهٌ خاملٌ عند الطرفين لا يُحكم به — يكفي الاتّجاه الحامل', () {
        final quiet = port('sfp-sfpplus1', tx: 80000000, rx: 300000);
        expect(FiberPortMatch.find([port('sfp1', rx: 78000000, tx: 500000), port('ether1', rx: 200000, tx: 77000000)], quiet), 'sfp1');
      });

      test('خاملٌ بالاتّجاهين، أو لم تُقرأ عدّاداته، أو منفذ الطرف الآخر طافٍ ⇒ لا مطابقة', () {
        expect(FiberPortMatch.find(sub(), port('p', tx: 900000, rx: 100000)), isNull, reason: 'تحت الحدّ: الخاملة كلّها تتشابه');
        expect(FiberPortMatch.find(sub(), port('p')), isNull, reason: 'قراءة VPN بلا عدّادات');
        expect(FiberPortMatch.find(sub(), port('p', up: false, tx: 615000000, rx: 71000000)), isNull);
        expect(FiberPortMatch.find(sub(), null), isNull);
        expect(FiberPortMatch.find(const [], peer), isNull);
      });

      test('الفرق المسموح ١٥٪ من الأكبر — أبعد منه ليس مطابقة', () {
        expect(FiberPortMatch.find([port('a', rx: 530000000, tx: 62000000)], peer), 'a', reason: '≈14٪');
        expect(FiberPortMatch.find([port('a', rx: 500000000, tx: 71000000)], peer), isNull, reason: '≈19٪');
        expect(FiberPortMatch.minBps, 2000000);
      });

      test('قراءتان متباعدتا اللحظة لا تُقارنان (ما يعبر تغيّر)', () {
        expect(FiberPortMatch.find(sub(), peer, skew: const Duration(seconds: 60)), 'sfp1');
        expect(FiberPortMatch.find(sub(), peer, skew: const Duration(seconds: -60)), 'sfp1', reason: 'أيّهما الأقدم سواء');
        expect(FiberPortMatch.find(sub(), peer, skew: const Duration(minutes: 3)), isNull);
        expect(FiberPortMatch.find(sub(), peer, skew: const Duration(minutes: -3)), isNull);
      });

      test('المنفذ الطافي عند هذا الطرف لا يُطابَق ولو حمل أرقاماً قديمة', () {
        expect(FiberPortMatch.find([port('sfp1', up: false, rx: 612000000, tx: 70000000)], peer), isNull);
      });
    });
  });

  test('النصوص بتمييز العدد العربيّ', () {
    expect([for (final n in [0, 1, 2, 4, 11]) TopoText.towers(n)], ['لا أبراج', 'برج واحد', 'برجان', '4 أبراج', '11 برجاً']);
    expect([for (final n in [1, 2, 3, 11]) TopoText.toTowers(n)], ['إلى برج واحد', 'إلى برجين', 'إلى 3 أبراج', 'إلى 11 برجاً'], reason: 'المثنّى مجروراً بالياء');
    expect([for (final n in [0, 1, 2, 3, 12]) TopoText.links(n)], ['لا لنكات', 'لنك واحد', 'لنكان', '3 لنكات', '12 لنكاً']);
    expect([for (final n in [0, 1, 2, 6, 23]) TopoText.devices(n)], ['بلا أجهزة', 'جهاز واحد', 'جهازان', '6 أجهزة', '23 جهازاً']);
    expect(LinkState.values.map(TopoText.state).toList(), ['ممتاز', 'متوسّط', 'ضعيف', 'واقع', 'لم يُقرأ']);
  });
}
