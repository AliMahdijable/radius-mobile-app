import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';

/// قنوات إرسال الرسائل للمشترك (١٨ نوفمبر ٢٠٢٦ — المالك: «يكدر يختار اكثر من نوع او نوعين او نوع او ثلاث او تلقائي»، و«تلقائي
/// خلي يكون بالاولية… للواتساب ثم تلي ثم التطبيق… اذا لا واتساب ولا تلي متوفر يلجا للتطبيق»).
///
/// ثلاث قنوات: واتساب · تلغرام · تطبيق MyServices. الوكيل يختار «تلقائي» (رسالةٌ واحدة لكلّ مشترك بأوّل قناةٍ عنده بهذا الترتيب،
/// وينتقل للتالية إن لم تكن عنده أو فشلت) أو قناةً أو اثنتين أو الثلاث (تصل من كلّ قناةٍ مختارة موجودة عنده). كلّ قناةٍ تُقفل وحدها
/// ما دام إرسالها جارياً ([ChannelLock]) — لا حملتان فوق بعض.
enum DeliveryChannel { whatsapp, telegram, app }

extension DeliveryChannelX on DeliveryChannel {
  String get label => switch (this) {
        DeliveryChannel.whatsapp => 'واتساب',
        DeliveryChannel.telegram => 'تلغرام',
        DeliveryChannel.app => 'التطبيق',
      };

  IconData get icon => switch (this) {
        DeliveryChannel.whatsapp => LucideIcons.messageCircle,
        DeliveryChannel.telegram => LucideIcons.send,
        DeliveryChannel.app => LucideIcons.smartphone,
      };

  Color get color => switch (this) {
        DeliveryChannel.whatsapp => AppColors.channelWhatsApp,
        DeliveryChannel.telegram => AppColors.channelTelegram,
        DeliveryChannel.app => AppColors.channelApp,
      };
}

/// أولويّة «تلقائي» (قرار المالك): واتساب ثمّ تلغرام ثمّ التطبيق.
const autoChannelOrder = [DeliveryChannel.whatsapp, DeliveryChannel.telegram, DeliveryChannel.app];

/// اختيار الوكيل: «تلقائي»، أو مجموعة قنوات (واحدة فأكثر).
@immutable
class DeliveryChoice {
  const DeliveryChoice.auto()
      : auto = true,
        channels = const {};
  const DeliveryChoice.only(this.channels) : auto = false;

  final bool auto;
  final Set<DeliveryChannel> channels;

  bool has(DeliveryChannel c) => !auto && channels.contains(c);

  /// للخادم: «auto» أو قائمة أسماء القنوات بترتيبها الثابت.
  Object toJson() => auto ? 'auto' : [for (final c in DeliveryChannel.values) if (channels.contains(c)) c.name];

  /// من الخادم/التخزين: «auto»، اسم قناة، «both» (واتساب + تلغرام القديمة)، أو قائمة. ما لا يُفهم ⇒ تلقائي.
  static DeliveryChoice fromJson(Object? v) {
    if (v is List) {
      final set = <DeliveryChannel>{
        for (final x in v)
          for (final c in DeliveryChannel.values)
            if (c.name == '$x') c,
      };
      return set.isEmpty ? const DeliveryChoice.auto() : DeliveryChoice.only(set);
    }
    final s = '${v ?? ''}'.trim();
    if (s == 'both') return const DeliveryChoice.only({DeliveryChannel.whatsapp, DeliveryChannel.telegram});
    for (final c in DeliveryChannel.values) {
      if (c.name == s) return DeliveryChoice.only({c});
    }
    return const DeliveryChoice.auto();
  }

  /// قناةٌ تُضاف أو تُزال؛ آخر قناةٍ تُزال ⇒ «تلقائي» (لا اختيار فارغ).
  DeliveryChoice toggle(DeliveryChannel c) {
    final next = {...channels};
    if (auto) return DeliveryChoice.only({c});
    if (!next.remove(c)) next.add(c);
    return next.isEmpty ? const DeliveryChoice.auto() : DeliveryChoice.only(next);
  }

  @override
  bool operator ==(Object other) =>
      other is DeliveryChoice && other.auto == auto && other.channels.length == channels.length && other.channels.containsAll(channels);

  @override
  int get hashCode => Object.hash(auto, Object.hashAllUnordered(channels));
}

/// قناةٌ إرسالها جارٍ: كم أُرسل من كم — مقفولةٌ حتى يكتمل.
@immutable
class ChannelLock {
  const ChannelLock({required this.sent, required this.total});
  final int sent;
  final int total;
}

/// سطر الشرح تحت الاختيار — ماذا سيحدث بالضبط.
String deliveryChoiceHint(DeliveryChoice v) {
  // بلا أسهم (⇒): خطّ التطبيق لا يرسمها — مربّعٌ فارغ مكانها
  if (v.auto) return 'رسالة وحدة لكل مشترك: واتساب، وإذا ما عنده أو فشل يروح لتلغرام، وبعدين التطبيق';
  final names = [for (final c in DeliveryChannel.values) if (v.channels.contains(c)) c.label];
  if (names.length == 1) return 'يوصل بـ${names.first} وحده — اللي ما عنده ${names.first} ما يوصله شي';
  final joined = names.length == 2 ? '${names[0]} و${names[1]}' : '${names[0]} و${names[1]} و${names[2]}';
  return 'يوصل بـ$joined — اللي عنده أكثر من قناة يستلمه من كل وحدة';
}

/// «قناة الإرسال» (المالك: «حسن تصميمها»): صفٌّ واحد من أربع بلاطات — «تلقائي» (اختيارٌ وحده) ثمّ واتساب وتلغرام والتطبيق (تُختار معاً
/// أو منفردة) — وتحتها سطر الشرح لما سيحدث بالضبط (وترتيب التلقائيّ فيه)، وسطرٌ للمقفولة. [reach]: كم مشتركاً يصله بكلّ قناة
/// (التبليغات — null بالرسائل التلقائيّة). [locks]: قنواتٌ إرسالها جارٍ (مقفولة، بتقدّمها).
class DeliveryChannelsPicker extends StatelessWidget {
  const DeliveryChannelsPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.reach,
    this.locks = const {},
    this.enabled = true,
  });

  final DeliveryChoice value;
  final ValueChanged<DeliveryChoice> onChanged;
  final Map<DeliveryChannel, int>? reach;
  final Map<DeliveryChannel, ChannelLock> locks;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final locked = [for (final c in DeliveryChannel.values) if (locks[c] != null) c];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _Tile(
                  key: const ValueKey('channel-auto'),
                  icon: LucideIcons.split,
                  color: AppColors.brand,
                  label: 'تلقائي',
                  selected: value.auto,
                  radio: true,
                  onTap: enabled ? () => onChanged(const DeliveryChoice.auto()) : null,
                ),
              ),
              for (final c in DeliveryChannel.values) ...[
                const SizedBox(width: 5),
                Expanded(
                  child: _Tile(
                    key: ValueKey('channel-${c.name}'),
                    icon: c.icon,
                    color: c.color,
                    label: c.label,
                    selected: value.has(c),
                    count: reach?[c],
                    lock: locks[c],
                    onTap: enabled && locks[c] == null ? () => onChanged(value.toggle(c)) : null,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(deliveryChoiceHint(value),
            key: const ValueKey('channel-hint'), style: AppType.muted(color: AppColors.textMid).copyWith(height: 1.5)),
        for (final c in locked)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            // التقدّم بالبلاطة نفسها (120/800) — السطر يقول السبب وحده، فلا يلتفّ على 320
            child: Text('${c.label} مقفول لحد ما يخلص تبليغه الحالي',
                key: ValueKey('channel-lock-${c.name}'), style: AppType.muted(color: AppColors.warning).copyWith(height: 1.5)),
          ),
      ],
    );
  }
}

/// بلاطةٌ واحدة: أيقونة القناة وعلامة الاختيار (دائرةٌ لـ«تلقائي» ومربّعٌ للقنوات) فوق الاسم، وتحته العدد أو «120/800» للمقفولة.
class _Tile extends StatelessWidget {
  const _Tile({
    super.key,
    required this.icon,
    required this.color,
    required this.label,
    required this.selected,
    required this.onTap,
    this.radio = false,
    this.count,
    this.lock,
  });

  final IconData icon;
  final Color color;
  final String label;
  final bool selected;
  final bool radio;
  final int? count;
  final ChannelLock? lock;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final locked = lock != null;
    final on = selected && !locked;
    final fg = locked ? AppColors.textLow : (on ? color : AppColors.textMid);
    final mark = locked
        ? LucideIcons.lock
        : radio
            ? (on ? LucideIcons.circleCheck : LucideIcons.circle)
            : (on ? LucideIcons.squareCheck : LucideIcons.square);
    final sub = locked ? '${lock!.sent}/${lock!.total}' : (count != null ? '$count' : null);
    return Material(
      color: on ? color.withValues(alpha: 0.12) : AppColors.surfaceInput,
      borderRadius: BorderRadius.circular(R.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(R.md),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(7, 7, 7, 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.md),
            border: Border.all(color: on ? color : AppColors.border, width: on ? 1.2 : 0.6),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(icon, size: 15, color: locked ? AppColors.textLow : color),
                const Spacer(),
                Icon(mark, size: 14, color: on ? color : AppColors.textLow),
              ]),
              const SizedBox(height: 5),
              // الاسم لا يُقصّ: يصغر قليلاً إن ضاق (320 × خطّ 1.2)
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(label, maxLines: 1, style: AppType.labelBold(color: fg)),
              ),
              if (sub != null)
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(sub,
                      maxLines: 1,
                      textDirection: TextDirection.ltr,
                      style: AppType.micro(color: locked ? AppColors.warning : AppColors.textMid)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
