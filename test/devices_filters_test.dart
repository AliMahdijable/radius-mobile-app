import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/models/network_device.dart';
import 'package:rad_mysvcs/screens/network_devices/devices_filters.dart';

import 'support/devices_demo_data.dart';

/// منطق شريط «فلاتر» وتوزيعه (أعلى صفحة الأجهزة، ١ نوفمبر): ما يُعرض، وكلّ عدّادٍ ضمن المرشّحات الأخرى لا مرشّحه هو.
void main() {
  final all = [for (final j in DevicesDemoData.devices()) NetworkDevice.fromJson(j)];
  const names = {1: 'برج الشهداء', 2: 'الحيدريّة', 3: 'الكورنيش', 4: 'المركز'};
  String regionName(NetworkDevice d) => d.regionId == null ? '' : names[d.regionId!]!;
  DevicesFacets of(DevicesFilter f, {String q = ''}) =>
      DevicesFacets.compute(all, f, query: q, regionName: regionName);

  test('بلا مرشّح: الكلّ ظاهر والتوزيع كما في البيانات', () {
    final x = of(DevicesFilter.none);
    expect(x.shown, hasLength(14));
    expect(x.total, 14);
    expect([x.status('online'), x.status('offline'), x.status('unknown')], [11, 2, 1]);
    expect([x.type('sector'), x.type('link'), x.type('switch'), x.type('router'), x.type('other')], [5, 3, 2, 2, 2]);
    expect([x.region(1), x.region(2), x.region(3), x.region(4), x.region(DevicesFacets.noRegion)], [4, 3, 3, 3, 1]);
  });

  test('🚨 عدّاد الحالة لا يتقيّد بالحالة المختارة — «مفصول» يبقى يُقرأ وأنت على «متّصل»', () {
    final x = of(const DevicesFilter(status: 'online'));
    expect(x.shown, hasLength(11));
    expect(x.status('offline'), 2, reason: 'وإلّا صار «مفصول ٠» بمجرّد اختيار «متّصل»');
    expect(x.status('online'), 11);
    // والأنواع والمناطق ضمن «متّصل»
    expect(x.type('sector'), 4, reason: 'سكترٌ من الخمسة مفصول');
    expect(x.type('other'), 1, reason: 'أولت الكورنيش مفصول');
    expect(x.region(3), 2);
    expect(x.region(DevicesFacets.noRegion), 0, reason: 'راوتر الطوارئ لم يُفحص — ليس متّصلاً');
  });

  test('المنطقة تعرض توزيعها هي — «أيّ أجهزة الكورنيش معطّلة؟»', () {
    final x = of(const DevicesFilter(region: 3));
    expect(x.shown.map((d) => d.id), unorderedEquals([5, 10, 13]));
    expect(x.status('offline'), 1);
    expect(x.status('online'), 2);
    expect(x.type('link'), 1);
    expect(x.type('sector'), 1);
    expect(x.type('other'), 1);
    expect(x.type('switch'), 0);
    // عدّاد المناطق لا يتقيّد بالمنطقة المختارة
    expect(x.region(1), 4);
    expect(x.total, 14, reason: '«الكلّ» = ما يطابق البحث وحده');
  });

  test('«بلا منطقة» مرشّحٌ كأيّ منطقة', () {
    final x = of(const DevicesFilter(region: DevicesFacets.noRegion));
    expect(x.shown.map((d) => d.name), ['راوتر الطوارئ']);
    expect(x.status('unknown'), 1);
  });

  test('ثلاثة مرشّحات معاً + البحث جزءٌ من النطاق (واسم المنطقة في كومته)', () {
    final x = of(const DevicesFilter(status: 'online', type: 'sector', region: 1));
    expect(x.shown.map((d) => d.id), unorderedEquals([1, 2]));
    final q = of(DevicesFilter.none, q: 'الكورنيش');
    expect(q.total, 3, reason: 'لنك الكورنيش + سكتر الكورنيش + أولت الكورنيش (اسماً ومنطقةً)');
    expect(q.status('offline'), 1);
    final ip = of(const DevicesFilter(type: 'link'), q: '10.70.240.');
    expect(ip.shown, hasLength(3));
    expect(ip.total, 3);
    expect(ip.type('sector'), 0);
  });

  test('عدد المرشّحات الفعّالة (حبّة «فلاتر») والمساواة', () {
    expect(DevicesFilter.none.count, 0);
    expect(DevicesFilter.none.isEmpty, isTrue);
    const f = DevicesFilter(status: 'offline', region: DevicesFacets.noRegion);
    expect(f.count, 2);
    expect(f.withType('link').count, 3);
    expect(f.withStatus(null), const DevicesFilter(region: DevicesFacets.noRegion));
    expect(f.withRegion(null).withStatus(null), DevicesFilter.none);
    expect(f.hashCode, const DevicesFilter(status: 'offline', region: -1).hashCode);
  });
}
