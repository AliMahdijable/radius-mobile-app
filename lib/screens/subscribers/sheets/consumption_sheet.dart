import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/traffic_api.dart';
import '../../../core/widgets/design_sheet.dart';
import '../../../models/subscriber.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';

/// استهلاك المشترك — يوميّ عبر أيّام الشهر، أو شهريّ عبر شهور السنة.
///
/// 🔬 المصدر: `GET /api/v2/subscribers/:id/traffic` الذي يغلّف
/// `user/traffic` في SAS4 (اكتُشف 2026-09-01 بفكّ حمولة من واجهته —
/// الحقل `report_type` غير موثَّق وبدونه يُرجع 500 صامتاً).
///
/// ⚠️ وأصلح هذا الشيت عطلاً صامتاً عاش منذ 2026-07-13: كان يعرض
/// «تحميل اليوم» و«رفع اليوم» من `daily_traffic_details.upload/download`
/// — وهما **غير موجودين** في ردّ SAS4 (يرسل `{user_id, traffic}` فقط).
/// فكانت البلاطتان تعرضان صفراً دائماً تحت إجماليٍّ صحيح. التفصيل
/// الحقيقيّ يأتي الآن من `rx`/`tx` لكلّ خانة.
Future<void> showConsumptionSheet(BuildContext context, Subscriber sub) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.scrim,
    isScrollControlled: true,
    builder: (_) => _ConsumptionSheet(sub: sub),
  );
}

/// وحدة موحَّدة للرسم كلّه، مشتقّة من أعلى عمود.
///
/// 🐛 بلاغ 2026-09-01: «القيم ليش بس أرقام بدون وحدات — شمعرّفه هو
/// كيغا ميغا كيلو بايت تيرا؟». كنتُ أقصّ الوحدة لتوفير العرض، فصار
/// الرقم بلا معنى.
///
/// ⚠️ ولا تُكتب الوحدة على كلّ عمود: ثلاثة أحرف إضافيّة في عمودٍ عرضه
/// 27 نقطة تُقصّ. والأهمّ أنّ وحدةً لكلّ عمود تُفسد المقارنة نفسها —
/// «500M» و«20G» رقمان لا يُقارَنان بالنظر رغم أنّ العمودين يُقارَنان.
///
/// فالوحدة واحدة للرسم كلّه، تُشتقّ من الأعلى وتُعلَن مرّة فوقه.
({int div, String name}) _unitFor(int peak) {
  const gb = 1000 * 1000 * 1000;
  const mb = 1000 * 1000;
  const kb = 1000;
  if (peak >= gb) return (div: gb, name: 'GB');
  if (peak >= mb) return (div: mb, name: 'MB');
  if (peak >= kb) return (div: kb, name: 'KB');
  return (div: 1, name: 'B');
}

/// رقم العمود بالوحدة الموحَّدة — بلا كسورٍ لا تُقرأ في 27 نقطة.
String _scaled(int bytes, int div) {
  if (bytes <= 0) return '';
  final v = bytes / div;
  if (v >= 100) return v.toStringAsFixed(0);
  if (v >= 10) return v.toStringAsFixed(0);
  if (v >= 1) return v.toStringAsFixed(1);
  return v.toStringAsFixed(2);
}

/// منفذان للاختبار — الدالّتان خاصّتان لأنّهما تفصيل عرض، لكنّ
/// اختيار الوحدة منطقٌ يستحقّ حارساً.
({int div, String name}) unitForTest(int peak) => _unitFor(peak);
String scaledForTest(int bytes, int div) => _scaled(bytes, div);

String fmtBytes(int b) {
  if (b <= 0) return '0';
  const gb = 1000 * 1000 * 1000;
  const mb = 1000 * 1000;
  const kb = 1000;
  if (b >= gb) return '${(b / gb).toStringAsFixed(b >= 10 * gb ? 0 : 1)} GB';
  if (b >= mb) return '${(b / mb).toStringAsFixed(0)} MB';
  if (b >= kb) return '${(b / kb).toStringAsFixed(0)} KB';
  return '$b B';
}

class _ConsumptionSheet extends StatefulWidget {
  const _ConsumptionSheet({required this.sub});
  final Subscriber sub;

  @override
  State<_ConsumptionSheet> createState() => _ConsumptionSheetState();
}

class _ConsumptionSheetState extends State<_ConsumptionSheet> {
  late int _year = DateTime.now().year;
  late int _month = DateTime.now().month;
  String _type = 'daily';
  TrafficReport? _report;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final id = widget.sub.idx;
    if (id == null || id.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'لا معرّف لهذا المشترك';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final r = await TrafficApi.fetch(
      subscriberId: id,
      type: _type,
      month: _month,
      year: _year,
    );
    if (!mounted) return;
    setState(() {
      _report = r.report;
      _error = r.error;
      _loading = false;
    });
  }

  void _switch(String t) {
    if (t == _type) return;
    setState(() => _type = t);
    _load();
  }

  void _shift(int delta) {
    setState(() {
      if (_type == 'monthly') {
        _year += delta;
      } else {
        var m = _month + delta;
        var y = _year;
        if (m < 1) {
          m = 12;
          y--;
        } else if (m > 12) {
          m = 1;
          y++;
        }
        _month = m;
        _year = y;
      }
    });
    _load();
  }

  String get _periodLabel =>
      _type == 'monthly' ? '$_year' : '$_year-$_month';

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.activity,
        title: 'الاستهلاك',
        subtitle: widget.sub.fullName.isNotEmpty
            ? widget.sub.fullName
            : widget.sub.username,
        onClose: () => Navigator.of(context).pop(),
      ),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TypeToggle(type: _type, onChanged: _switch),
          const SizedBox(height: Sp.md),
          _PeriodBar(
            label: _periodLabel,
            onPrev: () => _shift(-1),
            // لا تقدّم إلى مستقبلٍ لا بيانات فيه.
            onNext: _isCurrentPeriod ? null : () => _shift(1),
          ),
          const SizedBox(height: Sp.md),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: Sp.huge),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            _Notice(icon: LucideIcons.triangleAlert, text: _error!)
          else if (_report == null || _report!.isEmpty)
            const _Notice(
              icon: LucideIcons.inbox,
              text: 'لا استهلاك مسجَّل في هذه المدّة',
            )
          else ...[
            _Totals(report: _report!),
            const SizedBox(height: Sp.md),
            _Bars(report: _report!, type: _type),
          ],
        ],
      ),
    );
  }

  bool get _isCurrentPeriod {
    final now = DateTime.now();
    if (_type == 'monthly') return _year >= now.year;
    return _year > now.year || (_year == now.year && _month >= now.month);
  }
}

class _TypeToggle extends StatelessWidget {
  const _TypeToggle({required this.type, required this.onChanged});
  final String type;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Row(
      children: [
        for (final e in const [('daily', 'يوميّ'), ('monthly', 'شهريّ')]) ...[
          if (e.$1 != 'daily') const SizedBox(width: Sp.sm),
          Expanded(
            child: InkWell(
              onTap: () => onChanged(e.$1),
              borderRadius: BorderRadius.circular(R.md),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: type == e.$1 ? AppColors.brand : AppColors.surface,
                  borderRadius: BorderRadius.circular(R.md),
                  border: Border.all(
                    color: type == e.$1 ? AppColors.brand : AppColors.border,
                  ),
                ),
                child: Text(
                  e.$2,
                  style: AppType.bodyStrong(
                    color: type == e.$1 ? AppColors.onBrand : AppColors.textBody,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _PeriodBar extends StatelessWidget {
  const _PeriodBar({
    required this.label,
    required this.onPrev,
    required this.onNext,
  });
  final String label;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Row(
      children: [
        IconButton(
          onPressed: onPrev,
          icon: Icon(LucideIcons.chevronRight, size: 18, color: AppColors.textMid),
        ),
        Expanded(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: AppType.cardTitleBold(color: AppColors.textHi),
          ),
        ),
        IconButton(
          onPressed: onNext,
          icon: Icon(
            LucideIcons.chevronLeft,
            size: 18,
            // المعطَّل باهت: الحدّ الزمنيّ يُرى لا يُكتشف بالمحاولة.
            color: onNext == null ? AppColors.textLow : AppColors.textMid,
          ),
        ),
      ],
    );
  }
}

class _Totals extends StatelessWidget {
  const _Totals({required this.report});
  final TrafficReport report;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final rx = report.buckets.fold<int>(0, (a, b) => a + b.rx);
    final tx = report.buckets.fold<int>(0, (a, b) => a + b.tx);
    return Row(
      children: [
        Expanded(child: _tile('الإجمالي', report.total, AppColors.brand)),
        const SizedBox(width: Sp.sm),
        Expanded(child: _tile('تحميل', rx, AppColors.success)),
        const SizedBox(width: Sp.sm),
        Expanded(child: _tile('رفع', tx, AppColors.info)),
      ],
    );
  }

  Widget _tile(String label, int bytes, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: Sp.sm, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surfaceInput,
          borderRadius: BorderRadius.circular(R.md),
          border: Border.all(color: AppColors.borderSoft),
        ),
        child: Column(
          children: [
            Text(label, style: AppType.micro(color: AppColors.textMid)),
            const SizedBox(height: 3),
            Text(
              fmtBytes(bytes),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.cardTitleBold(color: c),
            ),
          ],
        ),
      );
}

/// أعمدة بسيطة مرسومة بالودجات لا بمكتبة رسم.
///
/// المطلوب هنا مقارنةٌ بصريّة بين خانات لا تحليلٌ بيانيّ: أيّ يومٍ
/// أثقل، وهل الشهر يتصاعد. الأعمدة تكفي، ولا تجرّ مكتبةً إلى شاشة
/// تُفتح من شيت.
class _Bars extends StatelessWidget {
  const _Bars({required this.report, required this.type});
  final TrafficReport report;
  final String type;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final peak = report.peak;
    if (peak <= 0) return const SizedBox.shrink();
    final unit = _unitFor(peak);
    // اليوميّ 31 عموداً لا تتّسع في عرض الشاشة، فيُمرَّر أفقيّاً.
    final bars = [
      for (final b in report.buckets)
        _Bar(
          bucket: b,
          peak: peak,
          unit: unit,
          // ⚠️ أرقام لا أسماء شهور عربيّة (طلب المستخدم 2026-09-01):
          // «كانون٢» و«تشرين١» لا يعرفهما أغلب المستخدمين، وSAS4 نفسه
          // يكتبها `2026-1` في جدوله. الرقم لا يحتاج ترجمة ولا يُقصّ.
          label: '${b.index}',
        ),
    ];
    // ⚠️ الوضعان يُمرَّران أفقيّاً بعرضٍ ثابت.
    //
    // كان الشهريّ يوزّع 12 عموداً على العرض بـ`Expanded`، فينال كلٌّ
    // نحو 28 نقطة — لا تتّسع لرقمٍ ووحدته. والتوزيع يجعل العمود يضيق
    // كلّما ضاقت الشاشة، فالجهاز الصغير يفقد الأرقام أوّلاً.
    //
    // العرض الثابت يفصل قراءة العمود عن حجم الشاشة: يُرى منه ما يُرى،
    // ويُمرَّر الباقي. (طلب المستخدم 2026-09-01: «وسّع السجلات».)
    return SizedBox(
      height: 158,
      child: ListView(
        scrollDirection: Axis.horizontal,
        reverse: true, // RTL: الخانة 1 على اليمين
        padding: const EdgeInsets.symmetric(horizontal: Sp.xs),
        children: bars,
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.bucket,
    required this.peak,
    required this.unit,
    required this.label,
  });
  final TrafficBucket bucket;
  final int peak;
  final ({int div, String name}) unit;
  final String label;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final ratio = peak > 0 ? bucket.total / peak : 0.0;
    final on = bucket.total > 0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: SizedBox(
        // 46 يتّسع لـ«660GB» بمقاس `micro` بلا قصّ.
        width: 46,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (on)
              Text(
                _scaled(bucket.total, unit.div),
                maxLines: 1,
                // `micro` كما هي — حارس design_scales يمنع المقاسات
                // خارج السلّم، وهو محقّ: مقاسٌ يتيم لا يُعاد استعماله
                // يصير دَيناً في كلّ إعادة تصميم لاحقة.
                style: AppType.micro(color: AppColors.textMid),
              ),
            const SizedBox(height: 2),
            Expanded(
              child: FractionallySizedBox(
                alignment: Alignment.bottomCenter,
                // حدٌّ أدنى مرئيّ: عمودٌ بارتفاع صفر لا يُميَّز عن غيابٍ
                // تامّ، والفرق بينهما معلومة.
                heightFactor: on ? (ratio < 0.02 ? 0.02 : ratio) : 0.0,
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.brand,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(3),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.micro(color: AppColors.textLow),
            ),
          ],
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Sp.huge),
      child: Column(
        children: [
          Icon(icon, size: 30, color: AppColors.textLow),
          const SizedBox(height: Sp.sm),
          Text(
            text,
            textAlign: TextAlign.center,
            style: AppType.label(color: AppColors.textMid),
          ),
        ],
      ),
    );
  }
}
