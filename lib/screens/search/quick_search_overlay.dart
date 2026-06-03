import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';

/// Spotlight-style search overlay: TextField at the top, mic button on
/// the trailing side for voice input, suggestion list below.
///
/// Opens via `showQuickSearch(context)`. Wraps the iOS / Android system
/// speech recognizer (Arabic locale ar-IQ when available, falling back
/// to ar_SA then en_US) — no server round-trip.
Future<void> showQuickSearch(BuildContext context) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'QuickSearch',
    barrierColor: Colors.black.withValues(alpha: 0.4),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (_, __, ___) => const QuickSearchOverlay(),
    transitionBuilder: (_, anim, __, child) => FadeTransition(
      opacity: anim,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.96, end: 1).animate(
          CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
        ),
        child: child,
      ),
    ),
  );
}

class QuickSearchOverlay extends StatefulWidget {
  const QuickSearchOverlay({super.key});

  @override
  State<QuickSearchOverlay> createState() => _QuickSearchOverlayState();
}

class _QuickSearchOverlayState extends State<QuickSearchOverlay> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  final _speech = SpeechToText();
  bool _listening = false;
  bool _speechReady = false;
  String _q = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
    _ctrl.addListener(() => setState(() => _q = _ctrl.text));
    _initSpeech();
  }

  Future<void> _initSpeech() async {
    try {
      final ok = await _speech.initialize(
        onStatus: (s) {
          if (s == 'done' || s == 'notListening') {
            if (mounted) setState(() => _listening = false);
          }
        },
        onError: (_) {
          if (mounted) setState(() => _listening = false);
        },
      );
      if (mounted) setState(() => _speechReady = ok);
    } catch (_) {/* speech unavailable — mic button stays disabled */}
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    _speech.stop();
    super.dispose();
  }

  Future<void> _toggleMic() async {
    HapticFeedback.selectionClick();
    if (_listening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }
    if (!_speechReady) {
      _showSnack('التعرّف على الصوت غير متاح على هذا الجهاز');
      return;
    }
    // Pick a locale to listen in. Priority:
    //  1. Iraqi Arabic, then Saudi Arabic (exact match, normalized).
    //  2. Any Arabic dialect the device has installed.
    //  3. English (so search still works on devices without Arabic).
    //  4. null → speech engine's own default.
    //
    // Devices return locale IDs in mixed formats ('ar-IQ', 'ar_IQ',
    // 'ar-iq') so we normalize underscores→dashes and lowercase before
    // comparing. Critically: we NEVER abort here — voice search must
    // still work even when Arabic isn't installed.
    final locales = await _speech.locales();
    final ids = locales.map((l) => l.localeId).toList();
    String norm(String s) => s.toLowerCase().replaceAll('_', '-');
    String? exact(List<String> wants) {
      for (final w in wants) {
        final hit = ids.firstWhere(
          (id) => norm(id) == norm(w),
          orElse: () => '',
        );
        if (hit.isNotEmpty) return hit;
      }
      return null;
    }
    String? prefix(String p) {
      final hit = ids.firstWhere(
        (id) => norm(id).startsWith(p),
        orElse: () => '',
      );
      return hit.isEmpty ? null : hit;
    }
    final localeId = exact(['ar-IQ', 'ar-SA']) ??
        prefix('ar') ??
        exact(['en-US']) ??
        prefix('en');
    // If the device has no usable locale at all we still call listen
    // with localeId=null so the engine falls back to its own default.
    setState(() => _listening = true);
    await _speech.listen(
      onResult: (r) {
        if (!mounted) return;
        setState(() {
          _ctrl.text = r.recognizedWords;
          _ctrl.selection = TextSelection.collapsed(
            offset: _ctrl.text.length,
          );
        });
      },
      localeId: localeId,
      listenOptions: SpeechListenOptions(
        partialResults: true,
        cancelOnError: true,
        listenMode: ListenMode.search,
      ),
    );
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: AppType.button(color: Colors.white)),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(Sp.lg),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(R.md),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Sp.lg,
            Sp.huge,
            Sp.lg,
            Sp.lg,
          ),
          child: Material(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(R.xl),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Sp.md,
                    Sp.sm,
                    Sp.sm,
                    Sp.sm,
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.search_rounded,
                          color: AppColors.textMid, size: 22),
                      const SizedBox(width: Sp.sm),
                      Expanded(
                        child: TextField(
                          controller: _ctrl,
                          focusNode: _focus,
                          style: AppType.input(color: AppColors.textHi),
                          decoration: InputDecoration(
                            hintText: 'ابحث بالاسم، الرقم، أو نطق صوتي...',
                            hintStyle: AppType.input(color: AppColors.textLow),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            filled: false,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: Sp.sm,
                            ),
                          ),
                        ),
                      ),
                      // Mic toggle — pulses while listening.
                      _MicButton(
                        listening: _listening,
                        enabled: _speechReady,
                        onTap: _toggleMic,
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: AppColors.border),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * 0.5,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_listening)
                          Padding(
                            padding: const EdgeInsets.all(Sp.lg),
                            child: Row(
                              children: [
                                const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.brand,
                                  ),
                                ),
                                const SizedBox(width: Sp.sm),
                                Text(
                                  'الاستماع... تكلّم الآن',
                                  style: AppType.subtitle(
                                      color: AppColors.brand),
                                ),
                              ],
                            ),
                          )
                        else
                          _Hints(query: _q),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ).animate().slideY(
          begin: -0.04,
          end: 0,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
  }
}

class _MicButton extends StatelessWidget {
  const _MicButton({
    required this.listening,
    required this.enabled,
    required this.onTap,
  });
  final bool listening;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = listening
        ? AppColors.error
        : (enabled ? AppColors.brand.withValues(alpha: 0.12) : AppColors.surfaceInput);
    final fg = listening
        ? Colors.white
        : (enabled ? AppColors.brand : AppColors.textLow);

    final btn = Material(
      color: bg,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? onTap : null,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 38,
          height: 38,
          child: Icon(
            listening ? Icons.stop_rounded : Icons.mic_rounded,
            color: fg,
            size: 18,
          ),
        ),
      ),
    );

    if (!listening) return btn;
    return btn
        .animate(onPlay: (c) => c.repeat())
        .scale(
          begin: const Offset(1, 1),
          end: const Offset(1.08, 1.08),
          duration: const Duration(milliseconds: 600),
        )
        .then()
        .scale(
          begin: const Offset(1.08, 1.08),
          end: const Offset(1, 1),
          duration: const Duration(milliseconds: 600),
        );
  }
}

class _Hints extends StatelessWidget {
  const _Hints({required this.query});
  final String query;

  @override
  Widget build(BuildContext context) {
    final empty = query.trim().isEmpty;
    return Padding(
      padding: const EdgeInsets.all(Sp.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (empty) ...[
            Text(
              'الإجراءات السريعة',
              style: AppType.muted(color: AppColors.textLow)
                  .copyWith(fontSize: 11, letterSpacing: 0.6),
            ),
            const SizedBox(height: Sp.sm),
            _HintRow(icon: Icons.bolt_rounded, label: 'تفعيل مشترك'),
            _HintRow(icon: Icons.payments_rounded, label: 'تسديد دين'),
            _HintRow(icon: Icons.person_add_rounded, label: 'مشترك جديد'),
            _HintRow(icon: Icons.chat_bubble_rounded, label: 'إرسال رسالة'),
            _HintRow(icon: Icons.print_rounded, label: 'طباعة وصل'),
          ] else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Sp.lg),
              child: Center(
                child: Text(
                  'سيتم ربط البحث الفعلي بقاعدة بيانات المشتركين قريباً',
                  style: AppType.subtitle(color: AppColors.textMid)
                      .copyWith(height: 1.55),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _HintRow extends StatelessWidget {
  const _HintRow({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.of(context).pop(),
      borderRadius: BorderRadius.circular(R.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Sp.sm,
          vertical: Sp.md,
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.brand, size: 20),
            const SizedBox(width: Sp.md),
            Expanded(
              child: Text(label,
                  style: AppType.label(color: AppColors.textHi)),
            ),
            const Icon(Icons.keyboard_return_rounded,
                color: AppColors.textLow, size: 14),
          ],
        ),
      ),
    );
  }
}
