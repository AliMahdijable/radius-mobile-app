import 'package:flutter/foundation.dart';

import '../../models/network_device.dart';

/// مرشّحات قائمة الأجهزة الثلاثة — الحالة والنوع والمنطقة. `null` في أيٍّ منها = الكلّ.
///
/// قيمةٌ ثابتة تتنقّل بين الشاشة وورقة «فلاتر» وشريط التوزيع؛ الشاشة تحفظ الحقول الثلاثة نفسها كما كانت
/// (`_statusFilter`/`_typeFilter`/`_regionFilter`) فلا يتغيّر شيءٌ ممّا يقرؤها (عرض البرج، مسح الفلتر من الحالة الفارغة).
@immutable
class DevicesFilter {
  const DevicesFilter({this.status, this.type, this.region});

  /// `online` · `offline` (كما في `lastStatus`).
  final String? status;

  /// مفتاحٌ من [NetworkDeviceLabels.types].
  final String? type;

  /// معرّف منطقة، أو [DevicesFacets.noRegion] = «بلا منطقة».
  final int? region;

  static const none = DevicesFilter();

  /// كم مرشّحاً فعّالاً — العدد على شريحة «فلاتر».
  int get count => (status == null ? 0 : 1) + (type == null ? 0 : 1) + (region == null ? 0 : 1);

  bool get isEmpty => count == 0;

  DevicesFilter withStatus(String? v) => DevicesFilter(status: v, type: type, region: region);
  DevicesFilter withType(String? v) => DevicesFilter(status: status, type: v, region: region);
  DevicesFilter withRegion(int? v) => DevicesFilter(status: status, type: type, region: v);

  @override
  bool operator ==(Object other) =>
      other is DevicesFilter && other.status == status && other.type == type && other.region == region;

  @override
  int get hashCode => Object.hash(status, type, region);

  @override
  String toString() => 'DevicesFilter(status: $status, type: $type, region: $region)';
}

/// ما يُعرض من الأجهزة وتوزيعها — منطقٌ صرف بلا واجهة، مرّةً واحدة لكلّ بناء (لا مسحٌ لكلّ شريحة).
///
/// ⚠️ كلّ عدّادٍ **ضمن المرشّحات الأخرى لا مرشّحه هو**: «مفصول ٢» وأنت على منطقة «الكورنيش» = المفصول فيها وحدها —
/// وهو السؤال اليوميّ «أيّ أجهزة الكرادة معطّلة؟». وعدّاد الحالة لا يتقيّد بالحالة المختارة، وإلّا صار «مفصول ٠» بمجرّد
/// اختيار «متّصل» ولا يُعرف كم مفصولاً بقي. والبحث جزءٌ من النطاق: العدّاد يصف ما يمكن أن يُرى، لا رقماً من خارجه.
class DevicesFacets {
  const DevicesFacets._({
    required this.shown,
    required this.total,
    required this.byStatus,
    required this.byType,
    required this.byRegion,
  });

  /// «بلا منطقة» في [DevicesFilter.region] — الأجهزة التي لم تُسنَد إلى منطقة.
  static const int noRegion = -1;

  /// ما يطابق المرشّحات كلّها والبحث — بلا ترتيب (الشاشة ترتّبه باختيار المستخدم).
  final List<NetworkDevice> shown;

  /// ما يطابق البحث وحده — رقم «الكلّ».
  final int total;

  /// `lastStatus` ← العدد، ضمن النوع والمنطقة.
  final Map<String, int> byStatus;

  /// `type` ← العدد، ضمن الحالة والمنطقة.
  final Map<String, int> byType;

  /// `regionId` ← العدد (`null` = بلا منطقة)، ضمن الحالة والنوع.
  final Map<int?, int> byRegion;

  int status(String s) => byStatus[s] ?? 0;
  int type(String t) => byType[t] ?? 0;

  /// [id] معرّف منطقة أو [noRegion].
  int region(int id) => byRegion[id == noRegion ? null : id] ?? 0;

  static bool _inRegion(NetworkDevice d, int? region) =>
      region == null || (region == noRegion ? d.regionId == null : d.regionId == region);

  /// [regionName] اسم منطقة الجهاز («» بلا منطقة) — جزءٌ من كومة البحث: المنطقة تُعرض على كلّ كرت، والبحث الذي لا
  /// يجد ما تراه العين يبدو مكسوراً.
  static DevicesFacets compute(
    List<NetworkDevice> all,
    DevicesFilter f, {
    String query = '',
    String Function(NetworkDevice d)? regionName,
  }) {
    final q = query.trim().toLowerCase();
    final shown = <NetworkDevice>[];
    final byStatus = <String, int>{};
    final byType = <String, int>{};
    final byRegion = <int?, int>{};
    var total = 0;
    for (final d in all) {
      if (q.isNotEmpty) {
        final haystack =
            '${d.name} ${d.ip} ${d.mac ?? ''} ${d.location ?? ''} ${d.model ?? ''} ${regionName?.call(d) ?? ''}'
                .toLowerCase();
        if (!haystack.contains(q)) continue;
      }
      total++;
      final okStatus = f.status == null || d.lastStatus == f.status;
      final okType = f.type == null || d.type == f.type;
      final okRegion = _inRegion(d, f.region);
      if (okType && okRegion) byStatus[d.lastStatus] = (byStatus[d.lastStatus] ?? 0) + 1;
      if (okStatus && okRegion) byType[d.type] = (byType[d.type] ?? 0) + 1;
      if (okStatus && okType) byRegion[d.regionId] = (byRegion[d.regionId] ?? 0) + 1;
      if (okStatus && okType && okRegion) shown.add(d);
    }
    return DevicesFacets._(
      shown: shown,
      total: total,
      byStatus: byStatus,
      byType: byType,
      byRegion: byRegion,
    );
  }
}
