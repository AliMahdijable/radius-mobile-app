import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/cards_api.dart';
import '../../core/util/format.dart';
import '../../core/widgets/design_sheet.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';

/// ما تتقاسمه شاشة «الكارتات» وشيت كارتات السلسلة (البند ٤ §١٢).

/// «46,000 د.ع».
String cardsMoney(num value) => '${formatIQD(value)} ${'common.currency'.tr()}';

/// «••4821» — آخر أربع خانات وحدها، كما في إشعار التفعيل بالكارت حرفيّاً
/// فيجد المدير الكارت هنا بالشكل الذي رآه هناك.
String cardTail(String? tail) => '••${tail ?? '••••'}';

/// الرقم التسلسليّ الكامل حين يرسله الخادم (قرار المالك: «عرض الأرقام لكلّ سلسلة»)، وإلّا آخر أربع خاناتٍ كبديل.
String cardSerial(CardItem c) => c.serial ?? cardTail(c.serialTail);

String _two(int n) => n.toString().padLeft(2, '0');

/// «2026-10-02 01:19» — تواريخ الساس بتوقيت بغداد تُقرأ كما هي
/// (`parseSasLocal`)، فلا `toLocal` هنا.
String cardsWhen(DateTime? d) => d == null
    ? '—'
    : '${d.year}-${_two(d.month)}-${_two(d.day)} ${_two(d.hour)}:${_two(d.minute)}';

/// «2027-09-01».
String cardsDay(DateTime? d) =>
    d == null ? '—' : '${d.year}-${_two(d.month)}-${_two(d.day)}';

/// اسم باقة السلسلة — ورقمها حين يغيب الاسم.
String seriesProfile(CardSeries s) =>
    s.profileName ?? (s.profileId == null ? '—' : '#${s.profileId}');

/// «سلسلةٌ» هي باقةٌ في الحقيقة — ايرث لنك لا تُصدر سلاسل، فالخادم يجمع كروتها
/// بالباقة برمزٍ داخليّ `el-<رقم الباقة>` لا يُعرض للمدير.
bool isPackageSeries(CardSeries s) => s.series.startsWith('el-');

/// عنوان السلسلة كما يقرؤه المدير: رقمها (SAS4)، أو اسم باقتها (ايرث لنك).
String seriesTitle(CardSeries s) =>
    isPackageSeries(s) ? seriesProfile(s) : s.series;

/// «حتى 2027-09-01» أو «انتهت …» — و`null` لسلسلةٍ بلا تاريخ انتهاء.
String? seriesValidity(CardSeries s) {
  final raw = s.expiration;
  if (raw == null) return null;
  final day = s.expirationDate == null ? raw : cardsDay(s.expirationDate);
  return (s.expired ? 'cards.ended' : 'cards.until')
      .tr(namedArgs: {'date': day});
}

/// السلاسل الأحدث أوّلاً — الخادم يرتّبها، وهذا حزامٌ ثانٍ لا يكلّف شيئاً.
///
/// ⚠️ `List.sort` في Dart لا يَعِد بالاستقرار، فالتعادل (أو التاريخ الغائب)
/// يُحسم بموضع الصفّ في ردّ الخادم.
List<CardSeries> newestFirst(List<CardSeries> list) {
  final indexed = [for (var i = 0; i < list.length; i++) (i, list[i])];
  indexed.sort((a, b) {
    final da = a.$2.createdAt ?? '';
    final db = b.$2.createdAt ?? '';
    final c = db.compareTo(da); // «2026-10-01 23:31:35» يُرتَّب نصّاً
    return c != 0 ? c : a.$1.compareTo(b.$1);
  });
  return [for (final e in indexed) e.$2];
}

/// حبّات حال السلسلة: الباقي والمستعمل، ثمّ «منتهية» أو «معلّقة».
///
/// الباقي بنغمة البراند حين يُسحب منه فعلاً؛ والباقي في سلسلةٍ منتهية أو
/// معلّقة محايدٌ — موجودٌ لكنّه لا يصلح للتفعيل.
class SeriesChips extends StatelessWidget {
  const SeriesChips({super.key, required this.series});
  final CardSeries series;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final s = series;
    return Wrap(
      spacing: Sp.x6,
      runSpacing: Sp.x6,
      children: [
        ToneChip(
          label: 'cards.chip_left'.tr(namedArgs: {'n': formatIQD(s.remaining)}),
          tone: s.usable ? AppTone.brand : AppTone.neutral,
          dense: true,
        ),
        ToneChip(
          label: 'cards.chip_used'.tr(namedArgs: {'n': formatIQD(s.used)}),
          dense: true,
        ),
        if (s.expired)
          ToneChip(
            label: 'cards.expired'.tr(),
            tone: AppTone.danger,
            icon: LucideIcons.calendarX,
            dense: true,
          ),
        if (s.suspended)
          ToneChip(
            label: 'cards.suspended'.tr(),
            tone: AppTone.warning,
            icon: LucideIcons.circlePause,
            dense: true,
          ),
      ],
    );
  }
}

/// شريط المتبقّي — رفيعٌ يمتلئ من بداية السطر (اليمين بالعربيّة).
///
/// الكسر الصغير جدّاً (٣ من ٥٠٠) يبقى نقطةً مرئيّة لا خطّاً بعرض نصف بكسل:
/// «باقي القليل» غير «لا شيء»، والصفر وحده فارغ.
class StockBar extends StatelessWidget {
  const StockBar({super.key, required this.ratio, required this.tone});

  /// المتبقّي ÷ الكلّ، بين ٠ و١.
  final double ratio;
  final AppTone tone;

  static const double _h = 6;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return LayoutBuilder(
      builder: (context, c) {
        final r = ratio.clamp(0.0, 1.0);
        final w =
            r <= 0 ? 0.0 : math.min(c.maxWidth, math.max(_h, r * c.maxWidth));
        return Container(
          height: _h,
          alignment: AlignmentDirectional.centerStart,
          decoration: BoxDecoration(
            // `border` لا `surfaceSunken`: الغاطس على السطح الأبيض ١٫٠٥:١ —
            // مسارٌ لا يُرى فيبدو الشريط الممتلئ قليلاً معلّقاً في الفراغ.
            color: AppColors.border,
            borderRadius: BorderRadius.circular(R.pill),
          ),
          child: Container(
            width: w,
            height: _h,
            decoration: BoxDecoration(
              color: tone.fill,
              borderRadius: BorderRadius.circular(R.pill),
            ),
          ),
        );
      },
    );
  }
}
