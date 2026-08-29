import 'package:flutter/material.dart';

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
                      fontSize: 12,
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
                          .copyWith(fontSize: 12),
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
          constraints: const BoxConstraints(minWidth: 62),
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
          Icon(Icons.inventory_2_rounded, size: 15, color: AppColors.textHint),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              sub.profileName ?? '—',
              style: AppType.body().copyWith(fontSize: 12),
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
                  .copyWith(fontSize: 12),
            ),
          ],
          const Spacer(),
          _NetworkMetrics(sub: sub),
        ],
      ),
    );
  }

  // ─────────────────── الصفّ 3 ───────────────────

  Widget _expiryRow() {
    final session = _sessionVisual();
    return Row(
      children: [
        Icon(Icons.event_rounded, size: 15, color: AppColors.textHint),
        const SizedBox(width: 6),
        Text(
          'ينتهي',
          style: AppType.body(color: AppColors.textLabel)
              .copyWith(fontSize: 12),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            _formatExpiry(sub.parsedExpiration),
            textDirection: TextDirection.ltr,
            style: AppType.body()
                .copyWith(fontSize: 12, fontWeight: FontWeight.w600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        if (session != null)
          Flexible(
            child: Row(
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
            ),
          ),
      ],
    );
  }

  // ─────────────────── الصفّ 4 ───────────────────

  Widget _debtBar(double debt) {
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
          Text(
            'دين',
            style: AppType.body(color: AppColors.dangerOnSoft),
          ),
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
          const Spacer(),
          if (onSendDebtReminder != null) ...[
            _MiniButton(
              label: 'تذكير دين',
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
              label: 'تسديد',
              filled: true,
              color: AppColors.errorFill,
              onTap: onPayDebt!,
            ),
        ],
      ),
    );
  }

  Widget _lastPayBar() {
    final amount = _lastPayAmount();
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
          Flexible(
            child: Text(
              _lastPayText()!,
              style: AppType.body(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (amount != null) ...[
            const Spacer(),
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

  /// حالة الصفّ — «معطّل» تطغى، ثمّ «منتهي»، ثمّ الاتصال اللحظي.
  /// (المخطّط: منتهي يطغى على offline، ودليله بياناته الوهميّة.)
  _StatusVisual _status() {
    if (sub.isDisabled) {
      return _StatusVisual('معطّل', Icons.block_rounded, AppColors.textLabel,
          AppColors.surfaceDisabled);
    }
    if (sub.isExpired) {
      return _StatusVisual('منتهي', Icons.timer_off_rounded, AppColors.error,
          AppColors.dangerSoftBg);
    }
    if (sub.isOnline) {
      return _StatusVisual('متصل', Icons.wifi_rounded, AppColors.success,
          AppColors.brandSoftBg);
    }
    return _StatusVisual('غير متصل', Icons.wifi_off_rounded,
        AppColors.textLabel, AppColors.surfaceDisabled);
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
      return _DaysVisual('0', 'منتهي الاشتراك', AppColors.error,
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
      return _DaysVisual('$days', word, AppColors.error,
          AppColors.dangerSoftBg, AppColors.dangerSoftBorder);
    }
    if (days <= 7) {
      return _DaysVisual('$days', word, AppColors.warning,
          AppColors.warningSoftBg, AppColors.warningSoftBorder);
    }
    return _DaysVisual('$days', word, AppColors.success,
        AppColors.brandSoftBg, AppColors.brandSoftBorder);
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
    final t = DateTime.tryParse(last.trim());
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
    final t = DateTime.tryParse(raw.split('.').first.replaceAll('T', ' '));
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
    if (d > 0) return '$d يوم ${h}س ${m}د';
    if (h > 0) return '${h}س ${m}د';
    return '${m}د';
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
            items.add(_metric(Icons.network_wifi_rounded,
                '${u.signalDbm} dBm', _health(u.signalHealth)));
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
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: filled ? 12 : 10,
            vertical: filled ? 5 : 4,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            border: filled
                ? null
                : Border.all(color: borderColor ?? AppColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 15, color: filled ? AppColors.onBrand : color),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: AppType.body(
                  color: filled ? AppColors.onBrand : color,
                ).copyWith(fontSize: 12, fontWeight: FontWeight.w600),
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
