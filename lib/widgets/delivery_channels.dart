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

/// «قناة الإرسال»: «تلقائي» بصفٍّ كامل، وتحته القنوات الثلاث تُختار معاً أو منفردة. [reach]: كم مشتركاً يصله بكلّ قناة (التبليغات —
/// null بالرسائل التلقائيّة). [locks]: قنواتٌ إرسالها جارٍ (مقفولة، بتقدّمها).
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _AutoRow(selected: value.auto, onTap: enabled ? () => onChanged(const DeliveryChoice.auto()) : null),
        const SizedBox(height: Sp.sm),
        Text('أو اختر القنوات بنفسك', style: AppType.label(color: AppColors.textMid)),
        const SizedBox(height: 6),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final c in DeliveryChannel.values) ...[
                if (c != DeliveryChannel.whatsapp) const SizedBox(width: 6),
                Expanded(
                  child: _ChannelTile(
                    key: ValueKey('channel-${c.name}'),
                    channel: c,
                    selected: value.has(c),
                    reach: reach?[c],
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
      ],
    );
  }
}

class _AutoRow extends StatelessWidget {
  const _AutoRow({required this.selected, required this.onTap});
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = AppColors.brand;
    return Material(
      color: selected ? AppColors.brandSoftBg : AppColors.surfaceInput,
      borderRadius: BorderRadius.circular(R.md),
      child: InkWell(
        key: const ValueKey('channel-auto'),
        borderRadius: BorderRadius.circular(R.md),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.sm + 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.md),
            border: Border.all(color: selected ? color : AppColors.border, width: selected ? 1.2 : 0.6),
          ),
          child: Row(
            children: [
              Icon(selected ? LucideIcons.circleCheck : LucideIcons.circle,
                  size: 18, color: selected ? color : AppColors.textLow),
              const SizedBox(width: Sp.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('تلقائي', style: AppType.bodyBold(color: selected ? color : AppColors.textHi)),
                    const SizedBox(height: 4),
                    // الترتيب نفسه بأيقوناته: واتساب ← تلغرام ← التطبيق
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        for (var i = 0; i < autoChannelOrder.length; i++) ...[
                          if (i > 0) Icon(LucideIcons.arrowLeft, size: 12, color: AppColors.textLow),
                          _MiniChip(channel: autoChannelOrder[i]),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip({required this.channel});
  final DeliveryChannel channel;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: channel.color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(R.pill),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(channel.icon, size: 11, color: channel.color),
          const SizedBox(width: 3),
          Text(channel.label, style: AppType.microBold(color: channel.color)),
        ]),
      );
}

class _ChannelTile extends StatelessWidget {
  const _ChannelTile({super.key, required this.channel, required this.selected, required this.onTap, this.reach, this.lock});
  final DeliveryChannel channel;
  final bool selected;
  final int? reach;
  final ChannelLock? lock;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final locked = lock != null;
    final c = channel.color;
    final fg = locked ? AppColors.textLow : (selected ? c : AppColors.textMid);
    return Material(
      color: locked ? AppColors.surfaceInput : (selected ? c.withValues(alpha: 0.12) : AppColors.surfaceInput),
      borderRadius: BorderRadius.circular(R.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(R.md),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(Sp.sm, Sp.sm, Sp.sm, Sp.sm),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.md),
            border: Border.all(color: selected && !locked ? c : AppColors.border, width: selected && !locked ? 1.2 : 0.6),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(channel.icon, size: 16, color: locked ? AppColors.textLow : c),
                const Spacer(),
                Icon(
                  locked ? LucideIcons.lock : (selected ? LucideIcons.squareCheck : LucideIcons.square),
                  size: 16,
                  color: locked ? AppColors.textLow : (selected ? c : AppColors.textLow),
                ),
              ]),
              const SizedBox(height: 6),
              Text(channel.label, maxLines: 1, style: AppType.labelBold(color: fg)),
              if (locked) ...[
                const SizedBox(height: 2),
                Text('قيد الإرسال', maxLines: 1, style: AppType.micro(color: AppColors.warning)),
                // «120/800» أرقاماً من اليسار — «120 من 800» كانت تُقصّ على 320 × خطّ 1.2
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text('${lock!.sent}/${lock!.total}',
                      maxLines: 1, textDirection: TextDirection.ltr, style: AppType.micro(color: AppColors.textMid)),
                ),
              ] else if (reach != null) ...[
                const SizedBox(height: 2),
                Text('$reach مشترك', maxLines: 1, style: AppType.micro(color: AppColors.textMid)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
