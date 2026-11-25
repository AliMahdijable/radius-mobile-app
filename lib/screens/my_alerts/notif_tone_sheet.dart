import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/widgets/app_sheet.dart';
import '../../core/widgets/design_sheet.dart';
import '../../services/notif_sounds.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import 'notif_sound_style.dart';

/// اختيار نغمة فئة — النتيجة: `(tone, device)` أو null إن أُغلقت بلا حفظ.
typedef ToneChoice = ({String tone, DeviceTone? device});

Future<ToneChoice?> showToneSheet(
  BuildContext context, {
  required SoundCategory category,
  required NotifSoundPrefs prefs,
  Future<void> Function(String toneId, SoundCategory c)? onPreview,
  Future<DeviceTone?> Function()? pickFromDevice,
  Future<void> Function(SoundCategory c, ToneChoice choice)? onTest,
}) {
  return showAppSheet<ToneChoice>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.scrim,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => ToneSheet(
      category: category,
      prefs: prefs,
      onPreview: onPreview,
      pickFromDevice: pickFromDevice,
      onTest: onTest,
    ),
  );
}

class ToneSheet extends StatefulWidget {
  const ToneSheet({
    super.key,
    required this.category,
    required this.prefs,
    this.onPreview,
    this.pickFromDevice,
    this.onTest,
  });

  final SoundCategory category;
  final NotifSoundPrefs prefs;
  final Future<void> Function(String toneId, SoundCategory c)? onPreview;
  final Future<DeviceTone?> Function()? pickFromDevice;

  /// «إشعار تجريبي على هاتفي»: يحفظ الاختيار الحاليّ ثمّ يطلب الدفع التجريبيّ.
  final Future<void> Function(SoundCategory c, ToneChoice choice)? onTest;

  @override
  State<ToneSheet> createState() => _ToneSheetState();
}

class _ToneSheetState extends State<ToneSheet> {
  late String _tone = widget.prefs.toneOf(widget.category);
  late DeviceTone? _device = widget.prefs.deviceTones[widget.category.id];
  String? _playing;
  bool _testing = false;

  Future<void> _play(String id) async {
    setState(() => _playing = id);
    try {
      await widget.onPreview?.call(id, widget.category);
    } finally {
      if (mounted) setState(() => _playing = null);
    }
  }

  Future<void> _pickDevice() async {
    final d = await widget.pickFromDevice?.call();
    if (d == null || !mounted) return;
    setState(() {
      _device = d;
      _tone = 'device';
    });
  }

  Future<void> _test() async {
    if (widget.onTest == null || _testing) return;
    setState(() => _testing = true);
    try {
      await widget.onTest!(widget.category, (tone: _tone, device: _device));
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Widget _row(NotifTone t, SoundCategory c, bool isRequest) => _ToneRow(
        key: ValueKey('tone-${t.id}'),
        title: t.name,
        sub: t.kind == ToneKind.voice ? '«${keepTogether(c.phrase)}» — تعرف شنو وصلك بدون ما تشوف الموبايل' : t.hint,
        badge: t.kind == ToneKind.voice && isRequest ? 'مقترح' : null,
        icon: t.kind == ToneKind.voice ? LucideIcons.audioLines : (t.kind == ToneKind.phone ? LucideIcons.smartphone : LucideIcons.music),
        selected: _tone == t.id,
        playing: _playing == t.id,
        onTap: () => setState(() => _tone = t.id),
        onPlay: () => _play(t.id),
      );

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final c = widget.category;
    final style = soundCategoryStyle(c);
    final ios = SoundPlatform.isIos();
    final isRequest = c.family == SoundFamily.requests;
    final voice = kTones.firstWhere((t) => t.kind == ToneKind.voice);
    final builtin = kTones.where((t) => t.kind == ToneKind.builtin);
    final phone = kTones.firstWhere((t) => t.kind == ToneKind.phone);
    return DesignSheet(
      header: SheetHeaderBar(
        icon: c.icon,
        title: c.title,
        subtitle: 'اسمع النغمة قبل ما تختارها',
        subtitleMaxLines: 2,
        tint: style.fg,
        tintBg: style.bg,
        onClose: () => Navigator.of(context).pop(),
      ),
      footer: SheetFooterBar(
        label: 'حفظ',
        icon: LucideIcons.check,
        above: _TestButton(
          key: const ValueKey('tone-test'),
          busy: _testing,
          onTap: widget.onTest == null ? null : _test,
        ),
        onPressed: () => Navigator.of(context).pop((tone: _tone, device: _device)),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _row(voice, c, isRequest),
          const _GroupLabel('نغمات البرنامج'),
          for (final t in builtin) _row(t, c, isRequest),
          const _GroupLabel('من هاتفك'),
          _row(phone, c, isRequest),
          if (!ios)
            _ToneRow(
              key: const ValueKey('tone-device'),
              title: _device == null ? 'من جهازك…' : _device!.name,
              sub: _device == null ? 'اختار أي نغمة من نغمات هاتفك' : 'من نغمات هاتفك — اضغط القلم حتى تغيّرها',
              icon: LucideIcons.folderOpen,
              selected: _tone == 'device',
              playing: _playing == 'device',
              onTap: _device == null ? _pickDevice : () => setState(() => _tone = 'device'),
              onPlay: _device == null ? null : () => _play('device'),
              trailingEdit: _device != null ? _pickDevice : null,
            ),
          const SizedBox(height: Sp.xs),
          Text(
            ios
                ? 'بالآيفون تختار من نغمات البرنامج. وإذا مفتاح الصامت مشغّل ما يرن أي تطبيق.'
                : 'النغمة تخصّ هذا الهاتف بس — كل جهاز يختار نغماته.',
            style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 11.5, height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, Sp.sm, 4, Sp.sm),
      child: Text(
        text,
        style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.6),
      ),
    );
  }
}

class _TestButton extends StatelessWidget {
  const _TestButton({super.key, required this.onTap, this.busy = false});
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Padding(
      padding: const EdgeInsets.only(bottom: Sp.sm),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.md),
        child: InkWell(
          onTap: busy ? null : onTap,
          borderRadius: BorderRadius.circular(R.md),
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.sm),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(R.md),
              border: Border.all(color: AppColors.borderStrong),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (busy)
                  SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brand))
                else
                  Icon(LucideIcons.bellRing, size: 16, color: AppColors.brand),
                const SizedBox(width: Sp.sm),
                Flexible(
                  child: Text(
                    'إشعار تجريبي على هاتفي',
                    textAlign: TextAlign.center,
                    style: AppType.label(color: AppColors.textHi).copyWith(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ToneRow extends StatelessWidget {
  const _ToneRow({
    super.key,
    required this.title,
    required this.sub,
    required this.icon,
    required this.selected,
    required this.playing,
    required this.onTap,
    required this.onPlay,
    this.badge,
    this.trailingEdit,
  });

  final String title;
  final String sub;
  final IconData icon;
  final bool selected;
  final bool playing;
  final VoidCallback onTap;
  final VoidCallback? onPlay;
  final String? badge;
  final VoidCallback? trailingEdit;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Padding(
      padding: const EdgeInsets.only(bottom: Sp.sm),
      child: Material(
        color: selected ? AppColors.brandSoftBg : AppColors.surface,
        borderRadius: BorderRadius.circular(R.md),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(R.md),
          child: Container(
            padding: const EdgeInsetsDirectional.fromSTEB(Sp.md, Sp.sm, Sp.sm, Sp.sm),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(R.md),
              border: Border.all(color: selected ? AppColors.brandSoftBorder : AppColors.border),
            ),
            child: Row(
              children: [
                Icon(selected ? LucideIcons.circleCheck : LucideIcons.circle,
                    size: 18, color: selected ? AppColors.brand : AppColors.textHint),
                const SizedBox(width: Sp.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 6,
                        runSpacing: 2,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(title, style: AppType.label(color: AppColors.textHi).copyWith(fontWeight: FontWeight.w700)),
                          if (badge != null)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                              decoration: BoxDecoration(
                                color: AppColors.brand,
                                borderRadius: BorderRadius.circular(R.pill),
                              ),
                              child: Text(badge!,
                                  style: AppType.muted(color: AppColors.onBrand)
                                      .copyWith(fontSize: 10.5, fontWeight: FontWeight.w700, height: 1.5)),
                            ),
                        ],
                      ),
                      const SizedBox(height: Sp.xxs),
                      Text(sub, style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 11.5, height: 1.4)),
                    ],
                  ),
                ),
                if (trailingEdit != null)
                  IconButton(
                    tooltip: 'غيّر',
                    onPressed: trailingEdit,
                    icon: Icon(LucideIcons.pencil, size: 16, color: AppColors.textMid),
                  ),
                if (onPlay != null) _PlayButton(playing: playing, onTap: onPlay!),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.playing, required this.onTap});
  final bool playing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Semantics(
      button: true,
      label: playing ? 'يشتغل' : 'اسمع',
      child: InkResponse(
        onTap: onTap,
        radius: 24,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: playing ? AppColors.brand : AppColors.surfaceInput,
                shape: BoxShape.circle,
                border: Border.all(color: playing ? AppColors.brand : AppColors.border),
              ),
              alignment: Alignment.center,
              child: Icon(
                playing ? LucideIcons.volume2 : LucideIcons.play,
                size: 15,
                color: playing ? AppColors.onBrand : AppColors.textHi,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
