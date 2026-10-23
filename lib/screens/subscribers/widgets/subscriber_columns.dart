import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../services/provider_service.dart';
import 'sort_sheet.dart';

/// أعمدة جدول المشتركين على الحاسبة. «المشترك» (الاسم واليوزر) والإجراءات ثابتان؛ الباقي يُظهَر
/// ويُخفى ويُرتَّب من زرّ «الأعمدة»، ويُحفظ على هذا الجهاز.
enum SubCol { phone, package, manager, expiration, remaining, session, mac, usage, balance }

extension SubColInfo on SubCol {
  String get label => switch (this) {
        SubCol.phone => 'desktop.col_phone'.tr(),
        SubCol.package => 'desktop.col_package'.tr(),
        SubCol.manager => ProviderService.isFtth ? 'desktop.col_zone'.tr() : 'desktop.col_manager'.tr(),
        SubCol.expiration => 'desktop.col_expiry'.tr(),
        SubCol.remaining => 'desktop.col_days'.tr(),
        SubCol.session => 'desktop.col_session'.tr(),
        SubCol.mac => 'desktop.col_mac'.tr(),
        SubCol.usage => 'desktop.col_usage'.tr(),
        SubCol.balance => 'desktop.col_balance'.tr(),
      };

  /// عرضٌ ثابت؛ والباقة null = تأخذ ما بقي مع الاسم.
  double? get width => switch (this) {
        SubCol.phone => 178,
        SubCol.package => null,
        SubCol.manager => 124,
        SubCol.expiration => 108,
        SubCol.remaining => 104,
        SubCol.session => 148,
        SubCol.mac => 148,
        SubCol.usage => 140,
        SubCol.balance => 118,
      };

  /// أقلّ عرضٍ للباقة حين تتمدّد.
  static const double packageMin = 112;

  /// حقل الترتيب حين يُنقر رأس العمود؛ null = لا ترتيب به.
  SortField? get sortField => switch (this) {
        SubCol.phone => SortField.phone,
        SubCol.package => SortField.profileName,
        SubCol.manager => SortField.parentUsername,
        SubCol.expiration => SortField.expiration,
        SubCol.remaining => SortField.remainingDays,
        SubCol.session => SortField.sessionTime,
        SubCol.mac => null,
        SubCol.usage => SortField.dailyTraffic,
        SubCol.balance => SortField.notes,
      };

  /// حين يضيق الجدول تسقط الأعمدة من الأقلّ أولويّةً (الأكبر رقماً) — والمتبقّي والرصيد لا يسقطان.
  int get dropOrder => switch (this) {
        SubCol.mac => 7,
        SubCol.session => 6,
        SubCol.usage => 5,
        SubCol.manager => 4,
        // الانتهاء قبل الهاتف: «المتبقّي» يحمل معناه، والهاتف لا بديل له في الصفّ.
        SubCol.expiration => 3,
        SubCol.phone => 2,
        SubCol.package => 1,
        SubCol.remaining || SubCol.balance => 0,
      };

  /// متاحٌ لهذا المزوّد؟ (استهلاك المشروع الوطنيّ في لوحته لا هنا).
  bool get available => this != SubCol.usage || !ProviderService.isFtth;
}

/// ترتيب الأعمدة وظهورها — على هذا الجهاز وحده (كالموقع: v2_subs_hidden_cols).
class SubscriberColumnPrefs {
  SubscriberColumnPrefs._();

  static const _storage = FlutterSecureStorage();
  static const _kLayout = 'desk.subs.columns.v1';

  static const List<(SubCol, bool)> defaults = [
    (SubCol.phone, true),
    (SubCol.package, true),
    (SubCol.manager, true),
    (SubCol.expiration, true),
    (SubCol.remaining, true),
    (SubCol.session, false),
    (SubCol.mac, false),
    (SubCol.usage, false),
    (SubCol.balance, true),
  ];

  static final ValueNotifier<List<(SubCol, bool)>> layout =
      ValueNotifier<List<(SubCol, bool)>>(defaults);

  static bool _loaded = false;

  /// مرّةً عند أوّل جدول — صامتٌ إن تعذّرت الخزنة (الافتراضيّ يبقى).
  static Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final raw = await _storage.read(key: _kLayout);
      if (raw != null && raw.isNotEmpty) layout.value = decode(raw);
    } catch (_) {}
  }

  static Future<void> set(List<(SubCol, bool)> next) async {
    layout.value = List.unmodifiable(next);
    try {
      await _storage.write(key: _kLayout, value: encode(next));
    } catch (_) {}
  }

  static Future<void> reset() => set(defaults);

  static bool get isDefault => listEquals(layout.value, defaults);

  /// «phone:1,package:1,…» — عمودٌ جديد (لم يكن يوم الحفظ) يُلحق بمكانه الافتراضيّ.
  @visibleForTesting
  static String encode(List<(SubCol, bool)> l) =>
      l.map((e) => '${e.$1.name}:${e.$2 ? 1 : 0}').join(',');

  @visibleForTesting
  static List<(SubCol, bool)> decode(String raw) {
    final out = <(SubCol, bool)>[];
    for (final part in raw.split(',')) {
      final kv = part.split(':');
      if (kv.length != 2) continue;
      final col = SubCol.values.where((c) => c.name == kv[0]).firstOrNull;
      if (col == null || out.any((e) => e.$1 == col)) continue;
      out.add((col, kv[1] == '1'));
    }
    for (var i = 0; i < defaults.length; i++) {
      final d = defaults[i];
      if (!out.any((e) => e.$1 == d.$1)) out.insert(i.clamp(0, out.length), d);
    }
    return out;
  }

  /// الأعمدة الظاهرة بالترتيب، وما يتّسع منها لعرض [width] (يُسقط الأقلّ أولويّةً أوّلاً).
  /// [reserved] عرض «المشترك» والتحديد والإجراءات.
  static ({List<SubCol> shown, int dropped}) fit(double width, {required double reserved}) {
    final wanted = [
      for (final e in layout.value)
        if (e.$2 && e.$1.available) e.$1,
    ];
    final shown = [...wanted];
    double need() =>
        reserved +
        shown.fold<double>(0, (s, c) => s + (c.width ?? SubColInfo.packageMin));
    var dropped = 0;
    while (need() > width) {
      final candidates = shown.where((c) => c.dropOrder > 0).toList()
        ..sort((a, b) => b.dropOrder.compareTo(a.dropOrder));
      if (candidates.isEmpty) break;
      shown.remove(candidates.first);
      dropped++;
    }
    return (shown: shown, dropped: dropped);
  }
}
