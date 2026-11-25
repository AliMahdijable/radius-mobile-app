import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../services/notif_sound_engine.dart';
import '../../services/notif_sounds.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../desktop/desk_widgets.dart';
import 'notif_sound_style.dart';
import 'notif_tone_sheet.dart';

/// منافذ الشاشة — المحرّك الحقيقيّ افتراضاً، والاختبار يبدّلها.
class NotifSoundsHooks {
  NotifSoundsHooks._();
  static Future<PhoneSoundStatus?> Function() readStatus = () => NotifSoundEngine.instance.status();
  static Future<void> Function(String toneId, SoundCategory c) preview = (t, c) => NotifSoundEngine.instance.preview(t, c);
  static Future<DeviceTone?> Function() pickFromDevice = () => NotifSoundEngine.instance.pickFromDevice();
  static Future<String?> Function(SoundCategory c) sendTest = (c) => NotifSoundEngine.instance.sendTest(c);
  static Future<void> Function(String? channel) openPhoneSettings = (ch) => NotifSoundEngine.instance.openPhoneSettings(channel: ch);
  static Future<void> Function(NotifSoundPrefs p) onSaved = (p) => NotifSoundEngine.instance.apply(p);
  static Future<NotifSoundPrefs> Function() loadPrefs = () => NotifSoundEngine.instance.prefs();

  @visibleForTesting
  static void reset() {
    readStatus = () => NotifSoundEngine.instance.status();
    preview = (t, c) => NotifSoundEngine.instance.preview(t, c);
    pickFromDevice = () => NotifSoundEngine.instance.pickFromDevice();
    sendTest = (c) => NotifSoundEngine.instance.sendTest(c);
    openPhoneSettings = (ch) => NotifSoundEngine.instance.openPhoneSettings(channel: ch);
    onSaved = (p) => NotifSoundEngine.instance.apply(p);
    loadPrefs = () => NotifSoundEngine.instance.prefs();
  }
}

/// «أصوات الإشعارات» — من «إشعاراتي». نغمةٌ لكلّ نوع ومفتاح صوتٍ لكلّ نوع، وفحص الهاتف أعلاها.
class NotifSoundsScreen extends StatefulWidget {
  const NotifSoundsScreen({super.key, this.initial});

  /// للاختبار: تفضيلاتٌ بدل المحفوظة.
  final NotifSoundPrefs? initial;

  @override
  State<NotifSoundsScreen> createState() => _NotifSoundsScreenState();
}

class _NotifSoundsScreenState extends State<NotifSoundsScreen> {
  NotifSoundPrefs? _p;
  PhoneSoundStatus? _status;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final p = widget.initial ?? await NotifSoundsHooks.loadPrefs();
    final s = await NotifSoundsHooks.readStatus();
    if (!mounted) return;
    setState(() {
      _p = p;
      _status = s;
    });
  }

  Future<void> _set(NotifSoundPrefs next) async {
    setState(() => _p = next);
    await NotifSoundsHooks.onSaved(next);
  }

  Future<void> _openTone(SoundCategory c) async {
    final p = _p;
    if (p == null) return;
    final r = await showToneSheet(
      context,
      category: c,
      prefs: p,
      onPreview: NotifSoundsHooks.preview,
      pickFromDevice: NotifSoundsHooks.pickFromDevice,
      onTest: (cat, choice) async {
        final cur = _p;
        if (cur != null) await _set(cur.withTone(cat.id, choice.tone, device: choice.device).withOn(cat.id, true));
        final err = await NotifSoundsHooks.sendTest(cat);
        if (!mounted) return;
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
          content: Text(err ?? 'يوصلك بعد ٥ ثواني — قفّل الشاشة إذا تريد تسمعه مثل الحقيقي'),
          duration: const Duration(seconds: 4),
        ));
      },
    );
    if (r == null || !mounted) return;
    await _set(_p!.withTone(c.id, r.tone, device: r.device).withOn(c.id, true));
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final p = _p;
    final ios = SoundPlatform.isIos();
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: deskPageBar(
        context,
        mobile: AppBar(
          backgroundColor: AppColors.bg,
          elevation: 0,
          scrolledUnderElevation: 0,
          title: Text('أصوات الإشعارات', style: AppType.title(color: AppColors.textHi).copyWith(fontSize: 16)),
          iconTheme: IconThemeData(color: AppColors.textHi),
        ),
      ),
      body: p == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              key: const ValueKey('sounds-list'),
              padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.xs, Sp.lg, Sp.huge),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, Sp.md),
                  child: Text(
                    'كل نوع بنغمته، حتى تعرف شنو وصلك من صوته. الطلبات تنطق نوعها.',
                    style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 12.5, height: 1.5),
                  ),
                ),
                if (_status != null) ...[
                  _PhoneCheck(status: _status!, ios: ios, onFix: () => NotifSoundsHooks.openPhoneSettings(_status!.fixChannel)),
                  const SizedBox(height: Sp.md),
                ],
                for (final f in SoundFamily.values) ...[
                  _SectionLabel(kSoundFamilyTitles[f]!),
                  _Group(children: [
                    for (final c in kSoundCategories.where((c) => c.family == f))
                      _CategoryRow(
                        key: ValueKey('sound-${c.id}'),
                        category: c,
                        prefs: p,
                        onTap: () => _openTone(c),
                        onToggle: (v) => _set(p.withOn(c.id, v)),
                      ),
                  ]),
                  const SizedBox(height: Sp.md),
                ],
                if (!ios)
                  _LoudCard(
                    key: const ValueKey('sounds-loud'),
                    value: p.loudRequests,
                    onChanged: (v) => _set(p.withLoud(v)),
                  )
                else
                  const _IosNote(key: ValueKey('sounds-ios-note')),
                const SizedBox(height: Sp.sm),
                Center(
                  child: TextButton.icon(
                    key: const ValueKey('sounds-reset'),
                    onPressed: () => _set(NotifSoundPrefs.defaults),
                    icon: Icon(LucideIcons.rotateCcw, size: 15, color: AppColors.textMid),
                    label: Text('رجّع الأصوات الافتراضيّة',
                        style: AppType.label(color: AppColors.textMid).copyWith(fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);
  final String label;
  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, Sp.xs, 4, 6),
      child: Text(
        label,
        style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.6),
      ),
    );
  }
}

/// بطاقةٌ واحدة لصفوف العائلة، بفواصل بينها.
class _Group extends StatelessWidget {
  const _Group({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) Divider(height: 1, thickness: 1, indent: 58, color: AppColors.divider),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({super.key, required this.category, required this.prefs, required this.onTap, required this.onToggle});
  final SoundCategory category;
  final NotifSoundPrefs prefs;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final c = category;
    final on = prefs.isOn(c);
    final style = soundCategoryStyle(c);
    final voice = on && prefs.toneOf(c) == 'voice';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(Sp.md, 10, Sp.sm, 10),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: on ? style.bg : AppColors.surfaceInput,
                  borderRadius: BorderRadius.circular(R.sm),
                ),
                alignment: Alignment.center,
                child: Icon(c.icon, size: 16, color: on ? style.fg : AppColors.textLow),
              ),
              const SizedBox(width: Sp.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.title, style: AppType.label(color: AppColors.textHi).copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 3),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Icon(
                            !on ? LucideIcons.volumeX : (voice ? LucideIcons.audioLines : LucideIcons.volume2),
                            size: 13,
                            color: !on ? AppColors.textLow : (voice ? AppColors.brand : AppColors.textMid),
                          ),
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            toneLine(c, prefs),
                            style: AppType.muted(color: voice ? AppColors.brandOnSoft : AppColors.textMid)
                                .copyWith(fontSize: 12.5, height: 1.4, fontWeight: voice ? FontWeight.w600 : null),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Sp.xs),
              Switch.adaptive(value: on, onChanged: onToggle),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhoneCheck extends StatelessWidget {
  const _PhoneCheck({required this.status, required this.ios, required this.onFix});
  final PhoneSoundStatus status;
  final bool ios;
  final Future<void> Function() onFix;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final rows = <(bool, String)>[
      (status.notificationsOn, status.notificationsOn ? 'الإشعارات مسموحة' : 'الإشعارات ممنوعة للتطبيق'),
      (status.soundOn, status.soundOn ? 'صوت إشعارات التطبيق شغّال' : 'صوت إشعارات التطبيق مطفي بإعدادات الهاتف'),
      if (status.breaksThrough != null)
        (
          status.breaksThrough!,
          ios
              ? (status.breaksThrough! ? 'الطلبات تعبر وضع «التركيز»' : 'الطلبات ما تعبر وضع «التركيز»')
              : (status.breaksThrough! ? 'الطلبات تعبر وضع «عدم الإزعاج»' : 'الطلبات ما تعبر وضع «عدم الإزعاج»'),
        ),
    ];
    final allGood = rows.every((r) => r.$1);
    return Container(
      key: const ValueKey('sounds-phone-check'),
      padding: const EdgeInsets.fromLTRB(Sp.md, Sp.md, Sp.md, Sp.sm),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: allGood ? AppColors.border : AppColors.warningSoftBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: allGood ? AppColors.successSoftBg : AppColors.warningSoftBg,
                  borderRadius: BorderRadius.circular(R.sm),
                ),
                alignment: Alignment.center,
                child: Icon(allGood ? LucideIcons.shieldCheck : LucideIcons.shieldAlert,
                    size: 16, color: allGood ? AppColors.success : AppColors.warning),
              ),
              const SizedBox(width: Sp.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('فحص هاتفك', style: AppType.label(color: AppColors.textHi).copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(
                      allGood ? 'كلشي جاهز حتى ترن الإشعارات' : 'شغلة بالهاتف تمنع الصوت — صلّحها من هنا',
                      style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 11.5, height: 1.4),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Sp.sm),
          for (final (ok, text) in rows) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(width: 9),
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(ok ? LucideIcons.circleCheck : LucideIcons.circleAlert,
                        size: 16, color: ok ? AppColors.success : AppColors.warning),
                  ),
                  const SizedBox(width: Sp.sm),
                  Expanded(
                    child: Text(text,
                        style: AppType.label(color: ok ? AppColors.textBody : AppColors.warningOnSoft)
                            .copyWith(fontSize: 12.5, fontWeight: ok ? FontWeight.w500 : FontWeight.w700, height: 1.4)),
                  ),
                ],
              ),
            ),
            // «صلّح» بسطرٍ مستقلّ تحت السبب — لا يزاحم النصّ بالعرض الضيّق
            if (!ok)
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton(
                      onPressed: onFix,
                      style: TextButton.styleFrom(
                        minimumSize: const Size(56, 36),
                        padding: const EdgeInsets.symmetric(horizontal: Sp.md),
                        backgroundColor: AppColors.warningSoftBg,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.pill)),
                      ),
                      child: Text('صلّح',
                          style: AppType.label(color: AppColors.warningOnSoft).copyWith(fontWeight: FontWeight.w700, fontSize: 12.5)),
                    ),
              ),
          ],
        ],
      ),
    );
  }
}

class _LoudCard extends StatelessWidget {
  const _LoudCard({super.key, required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(Sp.md, Sp.md, Sp.sm, Sp.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: value ? AppColors.brandSoftBg : AppColors.surfaceInput,
              borderRadius: BorderRadius.circular(R.sm),
            ),
            alignment: Alignment.center,
            child: Icon(LucideIcons.bellRing, size: 16, color: value ? AppColors.brand : AppColors.textLow),
          ),
          const SizedBox(width: Sp.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('الطلبات ترن حتى والموبايل صامت',
                    style: AppType.label(color: AppColors.textHi).copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(
                  'ترن بصوت المنبّه، فتسمعها حتى لو الهاتف صامت. شغّلها إذا الموبايل يبقى بعيد عنك.',
                  style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 11.5, height: 1.45),
                ),
              ],
            ),
          ),
          const SizedBox(width: Sp.xs),
          Switch.adaptive(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _IosNote extends StatelessWidget {
  const _IosNote({super.key});

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.infoSoftBg,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.infoSoftBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.info, size: 16, color: AppColors.info),
          const SizedBox(width: Sp.sm),
          Expanded(
            child: Text(
              'بالآيفون: إذا مفتاح الصامت مشغّل ما يرن أي تطبيق، حتى الواتساب. والطلبات تنطق نوعها بأوّل ما توصل.',
              style: AppType.muted(color: AppColors.textBody).copyWith(fontSize: 12.5, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}
