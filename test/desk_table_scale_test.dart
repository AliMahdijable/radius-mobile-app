import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/core/platform/desk_ui_scale.dart';
import 'package:rad_mysvcs/screens/desktop/desk_table_scroll.dart';
import 'package:rad_mysvcs/screens/subscribers/widgets/subscriber_columns.dart';
import 'package:rad_mysvcs/screens/subscribers/widgets/subscriber_table_row.dart';

/// المالك ٢٤ أكتوبر (صورة جدول المشتركين): «الجداول تبين كانها محصورة… ماكو امكانية يمرر ويسحب، ولا الجدول بيه
/// صلاحيّة يلگص ويزيد حجم الأعمدة» + «حاسبات بيها شاشات صغار التطبيق يطلع بيها كلش جبير».
void main() {
  setUp(() {
    SubscriberColumnPrefs.layout.value = SubscriberColumnPrefs.defaults;
    SubscriberColumnPrefs.widths.value = const {};
  });

  group('أعمدة جدول المشتركين', () {
    double colsSum(SubscriberTableColumns c) => c.shown.fold<double>(0, (s, x) => s + c.widthOf(x));

    test('شاشةٌ واسعة: كلّ الأعمدة بعروضها و«المشترك» يملأ الباقي — بلا تمرير', () {
      final c = SubscriberTableColumns.forWidth(1400);
      expect(c.scrolls, isFalse);
      expect(c.middleViewport, closeTo(colsSum(c), 0.01));
      const inner = 1400 - SubscriberTableColumns.borders;
      expect(SubscriberTableColumns.lead + c.nameWidth + c.middleViewport + SubscriberTableColumns.actions,
          closeTo(inner, 0.01));
    });

    test('لا عمود يسقط حين يضيق الجدول: «المشترك» ثابت والباقي يتمرّر', () {
      final c = SubscriberTableColumns.forWidth(720);
      expect(c.shown.length, SubscriberColumnPrefs.defaults.where((e) => e.$2).length);
      expect(c.scrolls, isTrue);
      expect(c.middleContent, closeTo(colsSum(c), 0.01));
      expect(c.nameWidth, greaterThanOrEqualTo(SubscriberTableColumns.nameMin));
      expect(c.middleViewport, greaterThan(0));
    });

    test('الأعمدة الافتراضيّة تتّسع على شاشة 1440 بلا تمرير', () {
      // الجدول على 1440 بعد القائمة الجانبيّة والحشوات ≈ 1120.
      expect(SubscriberTableColumns.forWidth(1120).scrolls, isFalse);
    });

    test('«إظهار الكلّ» على شاشةٍ عاديّة ⇒ تمرير لا ضغط', () {
      SubscriberColumnPrefs.layout.value = [for (final e in SubscriberColumnPrefs.defaults) (e.$1, true)];
      final c = SubscriberTableColumns.forWidth(1120);
      expect(c.shown.length, SubCol.values.where((x) => x.available).length);
      expect(c.scrolls, isTrue);
      for (final x in c.shown) {
        expect(c.widthOf(x), x.defaultWidth, reason: '${x.name} لا يُضغط');
      }
    });

    test('سحب حافّة عمود: يتّسع بقدر السحب، و«المشترك» يُثبَّت على عرضه أوّلاً', () {
      final before = SubscriberTableColumns.forWidth(1400);
      final nameBefore = before.nameWidth;
      resizeSubscriberColumn(before, SubCol.phone.name, 40);
      expect(SubscriberColumnPrefs.widths.value[SubCol.phone.name], SubCol.phone.defaultWidth + 40);
      expect(SubscriberColumnPrefs.nameWidth, nameBefore);
      final after = SubscriberTableColumns.forWidth(1400);
      expect(after.widthOf(SubCol.phone), SubCol.phone.defaultWidth + 40);
      expect(after.nameWidth, nameBefore, reason: 'الحافّة تحت المؤشّر تتحرّك، لا التي قبل العمود');
    });

    test('لا يضيق عمودٌ تحت أقلّه، والنقر المزدوج يعيده', () async {
      final c = SubscriberTableColumns.forWidth(1400);
      resizeSubscriberColumn(c, SubCol.balance.name, -1000);
      expect(SubscriberColumnPrefs.widths.value[SubCol.balance.name], SubCol.balance.minWidth);
      await SubscriberColumnPrefs.resetWidth(SubCol.balance.name);
      expect(SubscriberColumnPrefs.widths.value.containsKey(SubCol.balance.name), isFalse);
    });

    test('«المشترك» المثبَّت يبقى بعرضه والفراغ بعد الأعمدة', () {
      SubscriberColumnPrefs.widths.value = {SubscriberColumnPrefs.nameKey: 220};
      final c = SubscriberTableColumns.forWidth(1400);
      expect(c.nameWidth, 220);
      expect(c.scrolls, isFalse);
      expect(c.middleContent, c.middleViewport);
      expect(c.middleViewport, greaterThan(colsSum(c)));
    });

    test('حفظ العروض وقراءتها', () {
      final raw = SubscriberColumnPrefs.encodeWidths({'name': 230.4, 'phone': 190});
      expect(raw, 'name:230,phone:190');
      expect(SubscriberColumnPrefs.decodeWidths('$raw,bogus:50,mac:-3,usage:x'), {'name': 230.0, 'phone': 190.0});
    });
  });

  group('التمرير الأفقيّ', () {
    test('الموضع يُقصّ إلى المدى، ونافذةٌ اتّسعت تقصّه', () {
      final s = DeskHScroll()..setMetrics(viewport: 300, content: 900);
      expect(s.scrollable, isTrue);
      s.scrollBy(1000);
      expect(s.offset, 600);
      s.setMetrics(viewport: 800, content: 900);
      expect(s.offset, 100);
      s.setMetrics(viewport: 900, content: 900);
      expect(s.scrollable, isFalse);
      expect(s.offset, 0);
    });

    testWidgets('بالعربيّ: البداية يمين، والتمرير يكشف ما على اليسار — والمخفيّ لا يُنقر', (t) async {
      final s = DeskHScroll()..setMetrics(viewport: 300, content: 600);
      var tappedB = 0;
      await t.pumpWidget(Directionality(
        textDirection: TextDirection.rtl,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 300,
            height: 40,
            child: DeskHViewport(
              scroll: s,
              contentWidth: 600,
              child: Row(children: [
                const SizedBox(key: ValueKey('A'), width: 300, height: 40),
                GestureDetector(
                  onTap: () => tappedB++,
                  child: const SizedBox(key: ValueKey('B'), width: 300, height: 40, child: ColoredBox(color: Colors.red)),
                ),
              ]),
            ),
          ),
        ),
      ));
      // A (الأوّل) على اليمين ظاهر، وB خارج النافذة يساراً.
      expect(t.getRect(find.byKey(const ValueKey('A'))).left, closeTo(0, 0.5));
      expect(t.getRect(find.byKey(const ValueKey('B'))).right, closeTo(0, 0.5));
      await t.tapAt(const Offset(150, 20));
      expect(tappedB, 0);
      s.jumpTo(300);
      await t.pump();
      expect(t.getRect(find.byKey(const ValueKey('B'))).left, closeTo(0, 0.5));
      await t.tapAt(const Offset(150, 20));
      expect(tappedB, 1);
    });
  });

  group('حجم الواجهة التلقائيّ', () {
    test('يصغر على الشاشات الصغيرة بخطوات 5٪ حتى 75٪، ولا يكبر فوق 100٪', () {
      expect(DeskUiScale.autoFor(const Size(1440, 900)), 1.0);
      expect(DeskUiScale.autoFor(const Size(1920, 1080)), 1.0);
      expect(DeskUiScale.autoFor(const Size(1366, 768)), 0.85);
      expect(DeskUiScale.autoFor(const Size(1280, 720)), 0.8); // 1920×1080 بتكبير ويندوز 150٪
      expect(DeskUiScale.autoFor(const Size(1536, 864)), 0.95); // 1920×1080 بتكبير 125٪
      expect(DeskUiScale.autoFor(const Size(1024, 600)), 0.75);
      expect(DeskUiScale.autoFor(Size.zero), 1.0);
    });

    test('Ctrl + / − يتنقّلان بين المستويات من الحجم الحاليّ', () async {
      DeskUiScale.current = 0.85;
      DeskUiScale.zoomIn();
      expect(DeskUiScale.choice.value, 0.9);
      DeskUiScale.current = 0.9;
      DeskUiScale.zoomOut();
      expect(DeskUiScale.choice.value, 0.85);
      DeskUiScale.current = DeskUiScale.levels.last;
      DeskUiScale.zoomIn();
      expect(DeskUiScale.choice.value, DeskUiScale.levels.last);
      DeskUiScale.reset();
      expect(DeskUiScale.choice.value, isNull);
    });
  });
}
