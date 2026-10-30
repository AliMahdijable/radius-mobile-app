import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../services/provider_service.dart';
import 'sort_sheet.dart';

/// أعمدة جدول المشتركين على الحاسبة. «المشترك» (الاسم واليوزر) والإجراءات ثابتان؛ الباقي يُظهَر
/// ويُخفى ويُرتَّب من زرّ «الأعمدة»، ويُحفظ على هذا الجهاز.
///
/// ٢٩ أكتوبر (المالك على الحاسبة: «ما يظهر اشارات المشتركين… والماك واسم الجهاز اعزله بحقل ثاني»):
/// [SubCol.mac] صار «IP / الإشارة» — IP الجلسة وقراءة جهاز المشترك (النانو/الـONU) — ويبقى اسمه `mac`
/// حتى لا يضيع مكانه وعرضه المحفوظان؛ والماك واسم الجهاز انتقلا إلى [SubCol.device] الجديد.
enum SubCol { phone, package, manager, expiration, remaining, session, mac, device, usage, balance, debtAge }

extension SubColInfo on SubCol {
  String get label => switch (this) {
        SubCol.phone => 'desktop.col_phone'.tr(),
        SubCol.package => 'desktop.col_package'.tr(),
        SubCol.manager => ProviderService.isFtth ? 'desktop.col_zone'.tr() : 'desktop.col_manager'.tr(),
        SubCol.expiration => 'desktop.col_expiry'.tr(),
        SubCol.remaining => 'desktop.col_days'.tr(),
        SubCol.session => 'desktop.col_session'.tr(),
        SubCol.mac => 'desktop.col_mac'.tr(),
        SubCol.device => 'desktop.col_device'.tr(),
        SubCol.usage => 'desktop.col_usage'.tr(),
        SubCol.balance => 'desktop.col_balance'.tr(),
        // «أيّام الدين» (٣٠ أكتوبر).
        SubCol.debtAge => 'desktop.col_debt_age'.tr(),
      };

  /// العرض الافتراضيّ — والمدير يغيّره بسحب حافّة العمود في الرأس ([SubscriberColumnPrefs.widths]).
  /// (مضبوطةٌ لتتّسع الأعمدة الافتراضيّة على شاشة 1440 بلا تمرير؛ ما زاد عليها يتمرّر.)
  double get defaultWidth => switch (this) {
        SubCol.phone => 176,
        SubCol.package => 130,
        SubCol.manager => 116,
        SubCol.expiration => 104,
        SubCol.remaining => 96,
        SubCol.session => 140,
        SubCol.mac => 144,
        SubCol.device => 150,
        SubCol.usage => 132,
        SubCol.balance => 112,
        // الشارة الرفيعة «47 يوماً (تفعيل)» ~١٠٠ نقطة — ١٢٠ تكفيها وتُبقي الأعمدة الافتراضيّة بلا تمرير على الشاشة الواسعة.
        SubCol.debtAge => 120,
      };

  /// أضيق ما يُسحب إليه: تسميةٌ قصيرة وقيمةٌ تُقرأ.
  double get minWidth => switch (this) {
        SubCol.phone => 120,
        SubCol.mac || SubCol.device || SubCol.session || SubCol.usage || SubCol.debtAge => 96,
        _ => 76,
      };

  static const double maxWidth = 520;

  /// حقل الترتيب حين يُنقر رأس العمود؛ null = لا ترتيب به.
  SortField? get sortField => switch (this) {
        SubCol.phone => SortField.phone,
        SubCol.package => SortField.profileName,
        SubCol.manager => SortField.parentUsername,
        SubCol.expiration => SortField.expiration,
        SubCol.remaining => SortField.remainingDays,
        SubCol.session => SortField.sessionTime,
        SubCol.mac => null,
        SubCol.device => null,
        SubCol.usage => SortField.dailyTraffic,
        SubCol.balance => SortField.notes,
        SubCol.debtAge => SortField.debtAge,
      };

  /// متاحٌ لهذا المزوّد؟ (استهلاك المشروع الوطنيّ في لوحته لا هنا).
  bool get available => this != SubCol.usage || !ProviderService.isFtth;
}

/// ترتيب الأعمدة وظهورها — على هذا الجهاز وحده (كالموقع: v2_subs_hidden_cols).
class SubscriberColumnPrefs {
  SubscriberColumnPrefs._();

  static const _storage = FlutterSecureStorage();
  // v2 (٢٤ أكتوبر): كلّ الأعمدة ظاهرة افتراضيّاً والجدول يتمرّر — المالك: «يعرض كل الاعمده». v1 المحفوظ (يُخفي
  // بعضها) يُترك فيبدأ الجميع بالجدول كاملاً، والإخفاء من زرّ «الأعمدة» كما كان.
  static const _kLayout = 'desk.subs.columns.v2';
  static const _kWidths = 'desk.subs.colwidths.v1';

  static const List<(SubCol, bool)> defaults = [
    (SubCol.phone, true),
    (SubCol.package, true),
    (SubCol.manager, true),
    (SubCol.expiration, true),
    (SubCol.remaining, true),
    (SubCol.session, true),
    (SubCol.mac, true),
    // جديد ٢٩ أكتوبر — يُلحق تلقائيّاً بمكانه عند من حفظ تخطيطاً قديماً ([decode]).
    (SubCol.device, true),
    (SubCol.usage, true),
    (SubCol.balance, true),
    (SubCol.debtAge, true),
  ];

  static final ValueNotifier<List<(SubCol, bool)>> layout = ValueNotifier<List<(SubCol, bool)>>(defaults);

  static bool _loaded = false;

  /// مرّةً عند أوّل جدول — صامتٌ إن تعذّرت الخزنة (الافتراضيّ يبقى).
  static Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final raw = await _storage.read(key: _kLayout);
      if (raw != null && raw.isNotEmpty) layout.value = decode(raw);
    } catch (_) {}
    try {
      final raw = await _storage.read(key: _kWidths);
      if (raw != null && raw.isNotEmpty) widths.value = decodeWidths(raw);
    } catch (_) {}
  }

  // ───────── عروض الأعمدة (السحب من حافّة رأس العمود) ─────────

  /// مفتاح عمود «المشترك» في [widths] — بلا قيمةٍ يملأ ما يبقى من عرض الجدول.
  static const String nameKey = 'name';

  /// ما غيّره المدير بالسحب: اسم العمود ⇐ عرضه. الغائب على عرضه الافتراضيّ.
  static final ValueNotifier<Map<String, double>> widths = ValueNotifier<Map<String, double>>(const {});

  static double widthOf(SubCol c) =>
      (widths.value[c.name] ?? c.defaultWidth).clamp(c.minWidth, SubColInfo.maxWidth).toDouble();

  /// عرض «المشترك» إن ثبّته المدير؛ null = يملأ الباقي.
  static double? get nameWidth => widths.value[nameKey];

  /// أثناء السحب: يُحدَّث الجدول فوراً ولا يُكتب للخزنة إلّا عند الإفلات ([saveWidths]).
  static void setWidthsLive(Map<String, double> next) => widths.value = Map.unmodifiable(next);

  static Future<void> saveWidths() async {
    try {
      await _storage.write(key: _kWidths, value: encodeWidths(widths.value));
    } catch (_) {}
  }

  /// النقر المزدوج على حافّة عمود: يعود لعرضه الافتراضيّ («المشترك» يعود يملأ الباقي).
  static Future<void> resetWidth(String key) async {
    if (!widths.value.containsKey(key)) return;
    setWidthsLive({...widths.value}..remove(key));
    await saveWidths();
  }

  static Future<void> resetWidths() async {
    setWidthsLive(const {});
    await saveWidths();
  }

  @visibleForTesting
  static String encodeWidths(Map<String, double> w) => w.entries.map((e) => '${e.key}:${e.value.round()}').join(',');

  @visibleForTesting
  static Map<String, double> decodeWidths(String raw) {
    final out = <String, double>{};
    for (final part in raw.split(',')) {
      final kv = part.split(':');
      if (kv.length != 2) continue;
      final v = double.tryParse(kv[1]);
      final known = kv[0] == nameKey || SubCol.values.any((c) => c.name == kv[0]);
      if (v == null || !known || v <= 0) continue;
      out[kv[0]] = v;
    }
    return out;
  }

  static Future<void> set(List<(SubCol, bool)> next) async {
    layout.value = List.unmodifiable(next);
    try {
      await _storage.write(key: _kLayout, value: encode(next));
    } catch (_) {}
  }

  /// «الافتراضيّ»: الأعمدة وترتيبها وعروضها.
  static Future<void> reset() async {
    await set(defaults);
    await resetWidths();
  }

  static bool get isDefault => listEquals(layout.value, defaults) && widths.value.isEmpty;

  /// «phone:1,package:1,…» — عمودٌ جديد (لم يكن يوم الحفظ) يُلحق بمكانه الافتراضيّ.
  @visibleForTesting
  static String encode(List<(SubCol, bool)> l) => l.map((e) => '${e.$1.name}:${e.$2 ? 1 : 0}').join(',');

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
}
