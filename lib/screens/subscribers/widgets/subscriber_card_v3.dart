import 'package:flutter/material.dart';
import '../../../core/util/server_time.dart';

import '../../../api/device_probe_api.dart';
import '../../../core/util/format.dart';
import '../../../models/device_health.dart';
import '../../../models/subscriber.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import 'device_chip_micro.dart' show DeviceProbeBus;

/// كارت المشترك — الشريحة 2 من إعادة التصميم (مخطّط HTML، 2026-08-29).
///
/// أربعة صفوف داخل كارت `r20` بحدّ 1px وبلا ظلّ:
///   1. مربّع حالة 40×40 + [الاسم · الحالة · المعرّف] + بلاطة الأيّام
///   2. الباقة · السعر ← الإشارة · LAN     (يفصلها خطّ شعري علوي)
///   3. ينتهي {تاريخ} ← نصّ الجلسة
///   4. شريط الدين (أحمر بزرَّين) أو شريط آخر تسديد (أخضر إخباري)
///
/// ── ما نُقل حرفيّاً من المخطّط ─────────────────────────────────────
/// كلّ القياسات والألوان: 40×40/r14 لمربّع الحالة · بلاطة الأيّام
/// `min-width 62 · padding 7×9 · r14` بالرقم 19/w700/lh1.1 والكلمة
/// 9.5/w600/opacity .8 · فاصل الصفّ 2 بـ`border-top #F0F1EE` وحشو
/// علوي 10 · `margin-top:-3` على الصفّ 3 · شريطا الدين وآخر تسديد
/// بنفس المقاسات (r14، padding 9×12) وبألوان متعاكسة.
///
/// ── ما قرّرناه لأنّ المخطّط لا يغطّيه ──────────────────────────────
/// • **الأرقام لاتينيّة**. المخطّط يخلط عربيّة-هنديّة (٣٤٠) ولاتينيّة
///   (135,000) بلا قاعدة، بينما `format.dart` يوثّق قراراً صريحاً
///   للمستخدم: «٥٤٠٬٠٠٠ أصعب من 540,000». اتّبعنا الكود.
/// • **حالة رابعة «معطّل»** — المخطّط يعرّف ثلاثاً فقط (متصل/غير
///   متصل/منتهي) لكنّ شرائح رأسه فيها «معطل». أضفناها رماديّة
///   بأيقونة `block`، وتطغى على كلّ ما عداها.
/// • **حالة التحديد** (تحديد متعدّد بالضغط المطوّل) غير موجودة في
///   المخطّط أصلاً — أبقيناها بحدّ براند 1.5 + تعبئة ناعمة.
/// • **عتبات الأيّام**: `late ≤ 1` · `soon ≤ 7` · `safe` بعدها —
///   استُنتجت من بيانات المخطّط الوهميّة (٦→soon، ٩→safe، ١→late).
///
/// ── فخّ محفوظ ──────────────────────────────────────────────────────
/// الأيّام تُحسب من `parsedExpiration` لا من `remainingDays`: SAS4
/// يقرّب لأعلى فيعطي 31 يوماً لباقة 30. (إصلاح 2026-08-18)
class SubscriberCardV3 extends StatelessWidget {
  const SubscriberCardV3({
    super.key,
    required this.sub,
    required this.selected,
    this.lastPayment,
    required this.onTap,
    required this.onLongPress,
    this.onSendDebtReminder,
    this.onPayDebt,
    this.onOpenLocation,
    this.hasTelegram = false,
  });

  final Subscriber sub;
  final bool selected;
  final Map<String, dynamic>? lastPayment;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  /// المشترك مربوط ببوت تلغرام الأدمن ⇒ رسائله تذهب عبر تلغرام
  /// (توجيه تلقائي في الـbackend). المخطّط لا يعرّف الشارة، لكنّها
  /// موجودة منذ 2026-08-26 ولا يصحّ إسقاطها بإعادة التصميم.
  final bool hasTelegram;

  /// زرّ «تذكير دين» في شريط الدين. null = الزرّ يختفي (صلاحيّات).
  final VoidCallback? onSendDebtReminder;

  /// زرّ «تسديد» في شريط الدين. null = الزرّ يختفي (صلاحيّات).
  final VoidCallback? onPayDebt;

  /// فتح موقع المشترك في خرائط جوجل أو Waze. يُمرَّر فقط لمن له موقع
  /// محفوظ — والزرّ لا يُبنى بدونه، فلا يشغل مكاناً في السطر.
  final VoidCallback? onOpenLocation;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final st = _status();
    final debt = sub.hasDebt ? sub.debtAbs : 0.0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(R.card),
        child: Opacity(
          opacity: sub.isDisabled ? 0.62 : 1,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
            decoration: BoxDecoration(
              color: selected ? AppColors.brandSoftBg : AppColors.surface,
              borderRadius: BorderRadius.circular(R.card),
              border: Border.all(
                color: selected ? AppColors.brand : AppColors.border,
                width: selected ? BW.selected : BW.normal,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _identityRow(st),
                const SizedBox(height: 11),
                _planRow(),
                // المخطّط يسحب الصفّ الثالث 3px للأعلى فيصير الفراغ 8
                // بدل 11 — تفصيلة تشدّ الصفّين معاً بصريّاً.
                const SizedBox(height: 8),
                _expiryRow(),
                if (debt > 0) ...[
                  const SizedBox(height: 11),
                  _debtBar(debt),
                ] else if (_lastPayText() != null) ...[
                  const SizedBox(height: 11),
                  _lastPayBar(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────────── الصفّ 1 ───────────────────

  Widget _identityRow(_StatusVisual st) {
    final days = _daysVisual();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: st.bg,
            borderRadius: BorderRadius.circular(R.icon),
          ),
          child: Icon(st.icon, size: 21, color: st.color),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      normalizeDigits(sub.fullName) ?? sub.username,
                      style: AppType.listName(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (hasTelegram) ...[
                    const SizedBox(width: 6),
                    Icon(Icons.send_rounded,
                        size: 13, color: AppColors.brandAccent),
                  ],
                ],
              ),
              const SizedBox(height: 3),
              Row(
                children: [
                  Text(
                    st.label,
                    style: AppType.body(color: st.color).copyWith(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Container(
                    width: 3,
                    height: 3,
                    decoration: BoxDecoration(
                      color: AppColors.borderStrong,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Flexible(
                    child: Text(
                      sub.username,
                      textDirection: TextDirection.ltr,
                      style: AppType.body(color: AppColors.textLabel)
                          .copyWith(fontSize: 12.5),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 11),
        Container(
          // ⚠️ سقفٌ **وأرضيّة**: كان `minWidth` وحده.
          //
          // 🐛 والبلاطة ابنٌ غير مرنٍ في الصفّ، فتُقاس بعرضٍ غير محدود
          // وتنمو إلى ما تشاء. و«منتهي الاشتراك» (السطر ٥٦٦) يوسّعها إلى
          // نحو ٩٧ نقطةً بدل ٦٢ — والفارق يُقتطع من `Expanded` الاسم
          // بجانبها. سرقةٌ لا قصّ: البلاطة سليمةٌ والاسم هو من يُقصّ.
          constraints: const BoxConstraints(minWidth: 62, maxWidth: 92),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
          decoration: BoxDecoration(
            color: days.bg,
            borderRadius: BorderRadius.circular(R.icon),
            border: Border.all(color: days.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(days.big, style: AppType.daysNumber(color: days.color)),
              const SizedBox(height: 1),
              Text(
                days.small,
                style: AppType.daysWord(
                  color: days.color.withValues(alpha: 0.8),
                ),
                maxLines: 1,
                // ⚠️ `maxLines` بلا `overflow` تعني `clip` — بترٌ من
                // منتصف الحرف بلا «…»، فتبدو الكلمة تامّةً وهي مبتورة.
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ─────────────────── الصفّ 2 ───────────────────

  Widget _planRow() {
    final price = sub.price;
    return Container(
      padding: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: [
          // ⚠️ محتوى البداية في `Expanded` واحد: كان `Flexible(الاسم)`
          // و`Spacer()` أخوين في الصفّ نفسه، ولكليهما flex=1 فيتقاسمان
          // الفراغ — ونصيب `Flexible` يضيع لأنّها بالملاءمة الرخوة تأخذ
          // مقاسها الطبيعي. النتيجة: مقاييس الشبكة لا تبلغ نهاية الصفّ.
          Expanded(
            child: Row(children: [
              Icon(Icons.inventory_2_rounded,
                  size: 15, color: AppColors.textHint),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  sub.profileName ?? '—',
                  style: AppType.body().copyWith(fontSize: 12.5),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (price != null && price > 0) ...[
                const SizedBox(width: 8),
                Container(
                  width: 3,
                  height: 3,
                  decoration: BoxDecoration(
                    color: AppColors.grabber,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${formatIQD(price)} د.ع',
                  style: AppType.body(color: AppColors.textMid)
                      .copyWith(fontSize: 12.5),
                ),
              ],
            ]),
          ),
          // زرّ الموقع: للوصول السريع من القائمة بلا فتح الكارت ثمّ
          // «إجراءات أخرى». يظهر فقط حين يوجد موقع محفوظ.
          if (onOpenLocation != null && sub.hasLocation) ...[
            InkResponse(
              radius: 18,
              onTap: onOpenLocation,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Icon(Icons.location_on_rounded,
                    size: 17, color: AppColors.info),
              ),
            ),
            const SizedBox(width: 4),
          ],
          _NetworkMetrics(sub: sub),
        ],
      ),
    );
  }

  // ─────────────────── الصفّ 3 ───────────────────

  /// صفّ الانتهاء ونصّ الجلسة.
  ///
  /// ⚠️ انحدار 2026-08-29: كان الطرفان `Flexible` بنفس الوزن على سطر
  /// واحد، فيقتسمان العرض ويُقصّ «متصل منذ …» على الشاشات الضيّقة.
  /// الآن: تحت 340dp ينزل نصّ الجلسة إلى سطر ثانٍ بعرض كامل بدل أن
  /// يُقصّ. المعلومتان زمنيّتان ومستقلّتان — لا داعي لحشرهما معاً.
  Widget _expiryRow() {
    final session = _sessionVisual();
    return LayoutBuilder(
      builder: (context, c) {
        final stacked = session != null && c.maxWidth < 340;
        final expiry = Row(
          children: [
            Icon(Icons.event_rounded, size: 15, color: AppColors.textHint),
            const SizedBox(width: 6),
            Text(
              'ينتهي',
              style: AppType.body(color: AppColors.textLabel)
                  .copyWith(fontSize: 12.5),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                _formatExpiry(sub.parsedExpiration),
                textDirection: TextDirection.ltr,
                style: AppType.body()
                    .copyWith(fontSize: 12.5, fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        );
        if (session == null) return expiry;
        final sessionRow = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(session.icon, size: 14, color: session.color),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                session.text,
                style: AppType.muted(color: session.color)
                    .copyWith(fontSize: 11.5),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        );
        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              expiry,
              const SizedBox(height: 5),
              sessionRow,
            ],
          );
        }
        return Row(
          children: [
            Flexible(flex: 5, child: expiry),
            const SizedBox(width: 8),
            Flexible(flex: 4, child: sessionRow),
          ],
        );
      },
    );
  }

  // ─────────────────── الصفّ 4 ───────────────────

  Widget _debtBar(double debt) {
    // ⚠️ انحدار 2026-08-29: كان `Spacer()` بين المبلغ والزرّين، وكلاهما
    // مرن بنفس الوزن — فيقتسمان الفراغ ويُقصّ المبلغ («دين …»). الآن
    // المجموعة النصّيّة `Expanded` وحدها، والزرّان بمقاسهما الطبيعي:
    // في الـRow تأخذ العناصر غير المرنة مقاسها أوّلاً ثمّ يذهب الباقي
    // للمرنة — فيحصل النصّ على كلّ ما تبقّى بالضبط.
    //
    // وعلى الشاشات الضيّقة يسقط نصّ الزرّين وتبقى الأيقونة وحدها بدل
    // أن يُقصّ المبلغ — المبلغ معلومة والزرّ إجراء معروف بأيقونته.
    return LayoutBuilder(
      builder: (context, c) {
        final tight = c.maxWidth < 330;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: AppColors.dangerSoftBg,
            borderRadius: BorderRadius.circular(R.icon),
            border: Border.all(color: AppColors.dangerSoftBorder),
          ),
          child: Row(
            children: [
              Icon(Icons.credit_card_rounded,
                  size: 16, color: AppColors.dangerOnSoft),
              const SizedBox(width: 7),
              Expanded(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('دين',
                        style: AppType.body(color: AppColors.dangerOnSoft)),
                    const SizedBox(width: 7),
                    Flexible(
                      child: Text(
                        '${formatIQD(debt)} د.ع',
                        style: AppType.bodyStrong(color: AppColors.error)
                            .copyWith(fontWeight: FontWeight.w700),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 7),
              if (onSendDebtReminder != null) ...[
                _MiniButton(
                  label: tight ? '' : 'تذكير دين',
                  icon: Icons.notifications_active_rounded,
                  filled: false,
                  color: AppColors.warning,
                  borderColor: AppColors.warningSoftBorder,
                  onTap: onSendDebtReminder!,
                ),
                const SizedBox(width: 7),
              ],
              if (onPayDebt != null)
                _MiniButton(
                  label: tight ? '' : 'تسديد',
                  icon: Icons.payments_rounded,
                  filled: true,
                  color: AppColors.errorFill,
                  onTap: onPayDebt!,
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _lastPayBar() {
    final amount = _lastPayAmount();
    // 🐛 انحدار ٢٠٢٦-٠٩-٠٤ (لقطة المستخدم): «تسديد دين قبل 22…» مقصوصاً
    // عند الرقم، وإلى جانبه فراغٌ واسع ثمّ المبلغ.
    //
    // السبب `Spacer()` كان هنا. و`Spacer` **هو** `Expanded(flex: 1)`،
    // فيقتسم الفراغ الحرّ مع `Flexible(flex: 1)` بالتساوي: قِيس عند
    // ٣٦٠px فنال النصّ ٥٩٫٨ نقطة وهو يحتاج ٢٢٥٫٥.
    //
    // ⚠️ وهذا **العطل نفسه** الذي أُصلح في `_debtBar` أعلاه يوم
    // ٢٠٢٦-٠٨-٢٩ — بقي في توأمه أسفله. فحين يُصلَح نمطٌ في دالّة،
    // تُفتّش أخواتها في الملفّ نفسه قبل إغلاق الأمر.
    //
    // والعلاج: `Expanded` وحده مرناً. في الـ`Row` تأخذ العناصر غير
    // المرنة مقاسها الطبيعيّ أوّلاً، ثمّ يذهب **كلّ** الباقي للمرن —
    // فالمبلغ كاملٌ دائماً والنصّ يأخذ ما تبقّى بالضبط، بلا فراغٍ ميّت.
    //
    // الحارس: `test/text_truncation_test.dart` (يسقط على النسخة القديمة).
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: AppColors.successSoftBg,
        borderRadius: BorderRadius.circular(R.icon),
        border: Border.all(color: AppColors.successSoftBorder),
      ),
      child: Row(
        children: [
          Icon(Icons.task_alt_rounded, size: 16, color: AppColors.success),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _lastPayText()!,
              style: AppType.body(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (amount != null) ...[
            const SizedBox(width: 8),
            Text(
              '${formatIQD(amount)} د.ع',
              style: AppType.bodyStrong(color: AppColors.success)
                  .copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ],
      ),
    );
  }

  // ─────────────────── منطق العرض ───────────────────

  /// حالة الصفّ — **سبع تركيبات** كما في v1، لا أربع.
  ///
  /// ⚠️ انحدار 2026-08-29 (بلاغ المستخدم): إعادة التصميم اختصرت الحالة
  /// إلى أربع فضاعت ثلاث معلومات كان المدير يقرؤها من اللون وحده. الرمز
  /// يحمل **بعدين مستقلّين** لا بعداً واحداً:
  ///   • **الأيقونة** = الاتصال اللحظي (wifi / wifiOff / block).
  ///   • **اللون** = حالة الاشتراك (فعّال / قارب الانتهاء / منتهي)،
  ///     ويتغيّر معناه حسب الاتصال.
  ///
  /// الجدول الأصلي (subscriber_card.dart:498-511 قبل حذفه):
  /// | الحالة | اللون |
  /// |---|---|
  /// | معطّل | رمادي |
  /// | متصل + فعّال | **أزرق** (`info`) |
  /// | متصل + قارب الانتهاء | كهرماني |
  /// | متصل + منتهي | **بنفسجي** (`anomaly`) — تناقض يستحقّ لوناً خاصّاً |
  /// | غير متصل + فعّال | **أخضر** (`success`) |
  /// | غير متصل + قارب الانتهاء | كهرماني |
  /// | غير متصل + منتهي | أحمر |
  ///
  /// لماذا الأزرق للمتصل والأخضر لغير المتصل (وهو ما يبدو مقلوباً):
  /// الأخضر هنا يعني «اشتراكه سليم» لا «متصل الآن»، والأزرق يعني «متصل
  /// الآن». مشترك سليم غير متصل حالة طبيعيّة تماماً، ومشترك منتهٍ لكنّه
  /// متصل حالة شاذّة — ولذلك لها لونها الخاصّ.
  _StatusVisual _status() {
    if (sub.isDisabled) {
      return _StatusVisual('معطّل', Icons.block_rounded, AppColors.textLabel,
          AppColors.surfaceDisabled);
    }
    if (sub.isOnline) {
      if (sub.isExpired) {
        return _StatusVisual('منتهي · متصل', Icons.wifi_rounded,
            AppColors.anomaly, AppColors.anomalySoftBg);
      }
      if (sub.isNearExpiry) {
        // `warning` لا `warningFill`: الثاني ثابت #97650B فلا يُرى على
        // سطح داكن (2.16:1)، والأوّل يفتح ليلاً إلى #E0B457.
        return _StatusVisual('متصل', Icons.wifi_rounded, AppColors.warning,
            AppColors.warningSoftBg);
      }
      // خلفيّة زرقاء لا خضراء: كانت `brandSoftBg` تحت أيقونة زرقاء
      // فبدا المربّع «غير ملوّن» بينما نظائره ملوّنة (بلاغ 2026-08-30).
      return _StatusVisual(
          'متصل', Icons.wifi_rounded, AppColors.info, AppColors.infoSoftBg);
    }
    if (sub.isExpired) {
      return _StatusVisual('منتهي', Icons.wifi_off_rounded, AppColors.error,
          AppColors.dangerSoftBg);
    }
    if (sub.isNearExpiry) {
      return _StatusVisual('غير متصل', Icons.wifi_off_rounded,
          AppColors.warning, AppColors.warningSoftBg);
    }
    return _StatusVisual('غير متصل', Icons.wifi_off_rounded, AppColors.success,
        AppColors.successSoftBg);
  }

  /// بلاطة الأيّام. تُحسب من `parsedExpiration` — لا من `remainingDays`
  /// (SAS4 يقرّب لأعلى: 31 يوماً لباقة 30).
  _DaysVisual _daysVisual() {
    if (sub.isDisabled) {
      return _DaysVisual('—', 'معطّل', AppColors.textLabel,
          AppColors.surfaceDisabled, AppColors.border);
    }
    final exp = sub.parsedExpiration;
    if (exp == null) {
      return _DaysVisual('—', '', AppColors.textLabel,
          AppColors.surfaceDisabled, AppColors.border);
    }
    final now = DateTime.now();
    final diff = exp.difference(now);
    if (diff.isNegative) {
      // «منتهي» لا «منتهي الاشتراك»: البلاطة مصمَّمةٌ لكلمةٍ تحت رقم،
      // والطويلة توسّعها فتأكل من اسم المشترك. وهي الكلمة نفسها
      // المستعملة في شارة الحالة في شاشة التفاصيل — فاتّسق الاثنان.
      return _DaysVisual('0', 'منتهي', AppColors.error,
          AppColors.dangerSoftBg, AppColors.dangerSoftBorder);
    }
    final days = diff.inDays;
    if (days == 0) {
      // آخر يوم: الساعات أنفع من «0 يوم» — المدير يريد أن يعرف
      // إن بقيت 5 ساعات أو 30 دقيقة.
      final h = diff.inHours;
      return _DaysVisual(
        h > 0 ? '$h' : '${diff.inMinutes}',
        h > 0 ? 'ساعة متبقية' : 'دقيقة متبقية',
        AppColors.error,
        AppColors.dangerSoftBg,
        AppColors.dangerSoftBorder,
      );
    }
    final word = days == 1 ? 'يوم متبقي' : 'أيام متبقية';
    if (days <= 1) {
      return _DaysVisual('$days', word, AppColors.error, AppColors.dangerSoftBg,
          AppColors.dangerSoftBorder);
    }
    if (days <= 7) {
      return _DaysVisual('$days', word, AppColors.warning,
          AppColors.warningSoftBg, AppColors.warningSoftBorder);
    }
    return _DaysVisual('$days', word, AppColors.success, AppColors.brandSoftBg,
        AppColors.brandSoftBorder);
  }

  /// نصّ الجلسة. متّصل ⇒ «متصل منذ …» أخضر بأيقونة ساعة؛ غير متّصل ⇒
  /// «آخر اتصال قبل …» رمادي بأيقونة سجلّ.
  _SessionVisual? _sessionVisual() {
    if (sub.isOnline) {
      final secs = sub.sessionTime;
      if (secs == null || secs <= 0) return null;
      return _SessionVisual(
        'متصل منذ ${_humanDuration(secs)}',
        Icons.schedule_rounded,
        AppColors.success,
      );
    }
    final last = sub.lastOnline;
    if (last == null || last.trim().isEmpty) return null;
    // ⚠️ **لا `parseServerUtc` هنا** — خلافاً لـ`_lastPayText` أسفله.
    //
    // `last_online` يأتي من ردّ SAS4 كما هو (server.js:10804 يوسمه
    // صراحةً `SAS4: data.last_online`)، وتوقيتُ الساس بغداد لا UTC.
    // فوسمُه Z يُقدّمه ثلاث ساعات ويجعل متّصلاً الآن يبدو متّصلاً منذ
    // ثلاث. حقلان في ملفٍّ واحد ومصدران مختلفان.
    final t = parseSasLocal(last);
    if (t == null) return null;
    final mins = DateTime.now().difference(t).inMinutes;
    if (mins < 0) return null;
    return _SessionVisual(
      'آخر اتصال ${humanMinutesAgo(mins)}',
      Icons.history_rounded,
      AppColors.textLabel,
    );
  }

  String? _lastPayText() {
    final p = lastPayment;
    if (p == null) return null;
    final raw = (p['date'] ?? p['created_at'] ?? p['payment_date'])?.toString();
    if (raw == null || raw.isEmpty) return 'آخر تسديد';
    // 🐛 هذا بالضبط ما بلّغ عنه المستخدم ٢٠٢٦-٠٩-٠٤: «تسديد دين منذ:
    // يقرأ ٣ ساعات حتّى لو هسّة سدّدته».
    //
    // تُتبّع الحقل كاملاً: `/api/subscribers/last-payments/:adminId`
    // → `db.getLastSubscriberFinancialMovements` → `activity_logs.created_at`
    // — جدولُنا، وقيمُه UTC. فقراءتُه محلّيّاً تُقدّم العدّاد ثلاث ساعات.
    final t = parseServerUtc(raw);
    if (t == null) return 'آخر تسديد';
    final mins = DateTime.now().difference(t).inMinutes;
    if (mins < 0) return 'آخر تسديد';
    return 'تسديد دين ${humanMinutesAgo(mins)}';
  }

  double? _lastPayAmount() {
    final p = lastPayment;
    if (p == null) return null;
    final v = p['amount'] ?? p['value'] ?? p['paid'];
    if (v == null) return null;
    final d = v is num ? v.toDouble() : double.tryParse(v.toString());
    if (d == null || d == 0) return null;
    return d.abs();
  }

  /// `2026/09/03 · 15:35` — نفس تنسيق المخطّط حرفيّاً.
  static String _formatExpiry(DateTime? t) {
    if (t == null) return '—';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}/${two(t.month)}/${two(t.day)} · '
        '${two(t.hour)}:${two(t.minute)}';
  }

  /// `11 يوم 6س 28د` — يُحذف جزء الأيّام إن كان صفراً.
  ///
  /// النسخة السابقة في `subscriber_card.dart` كانت تعرض الساعات فقط،
  /// فجلسة 11 يوماً تظهر «270س».
  static String _humanDuration(int seconds) {
    final d = seconds ~/ 86400;
    final h = (seconds % 86400) ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (d > 0) return '$d يوم $hس $mد';
    if (h > 0) return '$hس $mد';
    return '$mد';
  }
}

// ─────────────────── قياسات الشبكة (الإشارة + LAN) ───────────────────

/// يقرأ من كاش `DeviceProbeApi` فقط ولا يبدأ فحصاً — موجة القائمة هي
/// من تملك الفحص، وهذا الصفّ يستمع لـ`DeviceProbeBus` فيتحدّث معها.
class _NetworkMetrics extends StatelessWidget {
  const _NetworkMetrics({required this.sub});
  final Subscriber sub;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: DeviceProbeBus.tick,
      builder: (_, __, ___) {
        final ip = sub.ipAddress?.trim() ?? '';
        final snap = DeviceProbeApi.cachedForUser(sub.username) ??
            (ip.isEmpty ? null : DeviceProbeApi.cached(ip));
        if (snap == null) return const SizedBox.shrink();

        final items = <Widget>[];
        if (snap.kind == DeviceKind.ubiquiti && snap.ubnt != null) {
          final u = snap.ubnt!;
          if (u.signalDbm != null) {
            items.add(_metric(Icons.network_wifi_rounded, '${u.signalDbm} dBm',
                _health(u.signalHealth)));
          }
          if (u.lanSpeedShort != null) {
            items.add(_metric(
                Icons.lan_rounded, u.lanSpeedShort!, _health(u.lanHealth)));
          }
        } else if (snap.kind == DeviceKind.ont && snap.ont != null) {
          final o = snap.ont!;
          items.add(_metric(
            Icons.network_wifi_rounded,
            '${o.rxPower} dBm',
            o.rxOk ? AppColors.success : AppColors.error,
          ));
          items.add(_metric(
            Icons.device_thermostat_rounded,
            '${o.temperature}°C',
            o.tempOk ? AppColors.success : AppColors.warning,
          ));
        }
        if (items.isEmpty) return const SizedBox.shrink();

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const SizedBox(width: 11),
              items[i],
            ],
          ],
        );
      },
    );
  }

  static Color _health(String? h) {
    switch (h) {
      case 'bad':
        return AppColors.error;
      case 'warn':
        return AppColors.warning;
      default:
        return AppColors.success;
    }
  }

  Widget _metric(IconData icon, String value, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 3),
        Text(
          value,
          textDirection: TextDirection.ltr,
          style: AppType.muted(color: color).copyWith(fontSize: 11.5),
        ),
      ],
    );
  }
}

// ─────────────────── زرّ صغير داخل شريط الدين ───────────────────

/// الحشو الرأسي 4 للشبحي و5 للمملوء — لأنّ الشبحي يحمل حدّاً 1px،
/// فالارتفاع النهائي يتساوى. (تفصيلة من المخطّط.)
class _MiniButton extends StatelessWidget {
  const _MiniButton({
    required this.label,
    required this.filled,
    required this.color,
    required this.onTap,
    this.icon,
    this.borderColor,
  });

  final String label;
  final bool filled;
  final Color color;
  final VoidCallback onTap;
  final IconData? icon;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: filled ? color : AppColors.surface,
      borderRadius: BorderRadius.circular(R.sm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(R.sm),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: filled ? 12 : 10,
            vertical: filled ? 5 : 4,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.sm),
            border: filled
                ? null
                : Border.all(color: borderColor ?? AppColors.border),
          ),
          // تسمية فارغة ⇒ زرّ أيقونة فقط (الشاشات الضيّقة). الأيقونة
          // وحدها تكفي لإجراء معروف، والمساحة المحرَّرة تذهب للمبلغ.
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null)
                Icon(icon, size: 15, color: filled ? AppColors.onBrand : color),
              if (icon != null && label.isNotEmpty) const SizedBox(width: 4),
              if (label.isNotEmpty)
                Text(
                  label,
                  style: AppType.body(
                    color: filled ? AppColors.onBrand : color,
                  ).copyWith(fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────── حزم القيم ───────────────────

class _StatusVisual {
  const _StatusVisual(this.label, this.icon, this.color, this.bg);
  final String label;
  final IconData icon;
  final Color color;
  final Color bg;
}

class _DaysVisual {
  const _DaysVisual(this.big, this.small, this.color, this.bg, this.border);
  final String big;
  final String small;
  final Color color;
  final Color bg;
  final Color border;
}

class _SessionVisual {
  const _SessionVisual(this.text, this.icon, this.color);
  final String text;
  final IconData icon;
  final Color color;
}
