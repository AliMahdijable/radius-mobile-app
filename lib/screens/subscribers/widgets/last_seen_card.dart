import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/util/format.dart';
import '../../../core/util/server_time.dart';
import '../../../core/widgets/sheet_scaffold.dart';
import '../../../models/subscriber.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';

/// «آخر اتصال» في كارت المشترك **غير المتّصل**: متى اتّصل آخر مرّة، وآخر
/// جهاز (MAC) اتّصل به — ما يقوله صفّ القائمة نفسه، هنا بالتاريخ كاملاً
/// و«آخر جهاز» يُنسخ بنقرة (المجموعة ② ١٨ أكتوبر).
///
/// المصدر صفّ القائمة لكلّ المزوّدين: `last_online` (SAS4، وايرث لنك من آخر
/// جلساتها المنتهية أو آخر دخولٍ تحمله قائمتها) و`last_mac` (ايرث لنك:
/// callerID — SAS4 لا يرسله في القائمة فيظهر له الوقت وحده).
///
/// المتّصل لا كرت له: «معلومات الاتصال» فوقه تقول جلسته وجهازه. ولا وقت ولا
/// MAC ⇒ لا كرت أيضاً — كرتٌ فارغ يوحي بقيمةٍ تعذّر جلبها.
class LastSeenCard extends StatelessWidget {
  const LastSeenCard({super.key, required this.sub, this.now});

  final Subscriber sub;

  /// «الآن» لحساب «قبل كذا» — للاختبار؛ وإلّا ساعة الجهاز.
  final DateTime? now;

  /// ما يُعرض: وقت آخر اتصال (توقيت الساس/ايرث لنك بغداديٌّ عارٍ فيُقرأ
  /// محلّيّاً — [parseSasLocal]) وآخر MAC؛ أو `null` حين لا شيء يُعرض.
  @visibleForTesting
  static ({DateTime? at, String? mac})? factsOf(Subscriber sub) {
    if (sub.isOnline) return null;
    final raw = sub.lastOnline?.trim() ?? '';
    // «0000-00-00 …» صفرُ الساس — غيابٌ لا تاريخ.
    final at =
        raw.isEmpty || raw.startsWith('0000') ? null : parseSasLocal(raw);
    final mac = sub.lastMac?.trim() ?? '';
    if (at == null && mac.isEmpty) return null;
    return (at: at, mac: mac.isEmpty ? null : mac);
  }

  /// «2026/10/17 · 21:05» — صيغة الانتهاء في كرت القائمة نفسها.
  @visibleForTesting
  static String dateTimeText(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}/${two(t.month)}/${two(t.day)} · '
        '${two(t.hour)}:${two(t.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final f = factsOf(sub);
    if (f == null) return const SizedBox.shrink();
    final at = f.at;
    final mac = f.mac;
    // وقتٌ في المستقبل (فرق ساعة الجهاز) بلا «قبل»: التاريخ وحده صادق.
    final mins = at == null
        ? null
        : (now ?? DateTime.now()).difference(at).inMinutes;
    return Padding(
      padding: const EdgeInsets.only(bottom: Sp.sm),
      child: Container(
        padding: const EdgeInsets.all(Sp.lg),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(R.card),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.history_rounded,
                    size: 18, color: AppColors.brandAccent),
                const SizedBox(width: Sp.sm),
                Text('آخر اتصال', style: AppType.cardTitle()),
                if (mins != null && mins >= 0) ...[
                  const SizedBox(width: Sp.sm),
                  Expanded(
                    child: Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: _AgoPill(text: humanMinutesAgo(mins)),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            if (at != null)
              _Tile(
                icon: Icons.event_rounded,
                label: 'الوقت',
                value: dateTimeText(at),
              ),
            if (at != null && mac != null) const SizedBox(height: 9),
            if (mac != null)
              _Tile(
                icon: Icons.memory_rounded,
                label: 'آخر جهاز (MAC)',
                value: mac,
                trailing: Icons.content_copy_rounded,
                onTap: () async {
                  await Clipboard.setData(ClipboardData(text: mac));
                  if (!context.mounted) return;
                  showSheetSnack(context, 'تم نسخ $mac',
                      duration: const Duration(seconds: 2));
                },
              ),
          ],
        ),
      ),
    );
  }
}

/// «قبل 3 س» بنبرةٍ محايدة — حبّة «متصل منذ» الخضراء للمتّصل وحده.
class _AgoPill extends StatelessWidget {
  const _AgoPill({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    const tone = AppTone.neutral;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        color: tone.softBg,
        borderRadius: BorderRadius.circular(R.pill),
        border: Border.all(color: tone.softBorder),
      ),
      child: Text(
        text,
        style: AppType.bodyStrong(color: tone.onSoft),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// بلاطةٌ غاطسة بعرض الكرت: تسميةٌ صغيرة فوق قيمةٍ لاتينيّة الاتّجاه — بعرضٍ
/// كامل لا نصفين، فـMAC كامل (١٧ خانة) يتّسع على ٣٢٠ بلا قصّ.
class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.label,
    required this.value,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final IconData? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final body = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 13, color: AppColors.textLabel),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        label,
                        style: AppType.micro(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  textDirection: ui.TextDirection.ltr,
                  style: AppType.cardTitle(color: AppColors.textHi)
                      .copyWith(fontWeight: FontWeight.w700),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: Sp.sm),
            Icon(trailing, size: 16, color: AppColors.textLabel),
          ],
        ],
      ),
    );
    return Material(
      color: AppColors.surfaceSunken,
      borderRadius: BorderRadius.circular(R.icon),
      clipBehavior: Clip.antiAlias,
      child: onTap == null ? body : InkWell(onTap: onTap, child: body),
    );
  }
}
