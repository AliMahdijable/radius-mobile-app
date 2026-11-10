import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/ai_consent.dart';
import '../../services/voice/desktop_voice_session.dart';
import '../../theme/colors.dart';

/// Command dictation through our server: always on Windows; on phones only in the «تلقائي» language mode (the system
/// recognizer hears one language per session — ours detects Arabic/English from the speech itself).
class WindowsVoiceButton extends StatefulWidget {
  const WindowsVoiceButton(
      {super.key,
      required this.controller,
      required this.onFinal,
      this.onFinalAlts,
      this.onListening,
      this.autoStart = false,
      this.language = 'auto',
      this.settingsName = 'ويندوز'});
  final TextEditingController controller;
  final ValueChanged<String> onFinal;

  /// النصّ مع بدائل ما سُمع (الأوّل = ما يُكتب) — يُنادى بدل [onFinal] حين يُعطى.
  final ValueChanged<List<String>>? onFinalAlts;
  final ValueChanged<bool>? onListening;
  final bool autoStart;

  /// auto (العربيّة والإنكليزيّة من النطق) أو ar أو en.
  final String language;

  /// «إعدادات ويندوز» / «إعدادات الهاتف» برسالة صلاحيّة الميكروفون.
  final String settingsName;
  @override
  State<WindowsVoiceButton> createState() => _WindowsVoiceButtonState();
}

class _WindowsVoiceButtonState extends State<WindowsVoiceButton>
    with WidgetsBindingObserver {
  late final DesktopVoiceSession _session;
  bool _asking = false;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    _session = DesktopVoiceSession(
        language: widget.language,
        settingsName: widget.settingsName,
        onText: (_) {},
        onTranscript: (heard) {
          if (!mounted) return;
          final text = heard.text;
          widget.controller.value = TextEditingValue(
              text: text,
              selection: TextSelection.collapsed(offset: text.length));
          final withAlts = widget.onFinalAlts;
          if (withAlts != null) {
            withAlts(heard.alts.isEmpty ? [text] : heard.alts);
          } else {
            widget.onFinal(text);
          }
        },
        onError: (message) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    })
      ..addListener(_changed);
    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _toggle();
      });
    }
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    widget.onListening?.call(_session.phase == DesktopVoicePhase.listening);
  }

  @override
  void didUpdateWidget(covariant WindowsVoiceButton old) {
    super.didUpdateWidget(old);
    if (old.language != widget.language) _session.language = widget.language;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) unawaited(_session.cancel());
  }

  Future<void> _toggle() async {
    if (_asking || !_foreground) return;
    if (_session.phase == DesktopVoicePhase.listening) {
      await _session.stop();
      return;
    }
    if (_session.phase != DesktopVoicePhase.idle) return;
    _asking = true;
    try {
      // Separate consent from the assistant: audio stays with our service and is
      // never sent to Anthropic. The key remains scoped to the current person.
      final key = 'windows.voice.v1.${await AiConsent.currentKey()}';
      final prefs = await SharedPreferences.getInstance();
      if (!mounted || !_foreground) return;
      if (prefs.getBool(key) != true) {
        final accepted = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
                  title: const Text('تحويل الصوت إلى نص'),
                  content: const Text(
                      'يُرسل صوتك إلى خادم MyServices لتحويله إلى نص، من دون حفظ التسجيل. يمكنك مراجعة النص، ولا تُنفّذ أي عملية تلقائياً.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('ليس الآن')),
                    FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('ابدأ'))
                  ],
                ));
        if (accepted != true || !mounted || !_foreground) return;
        await prefs.setBool(key, true);
      }
      // Consent belongs to the person who saw the dialog. Awaiting preferences
      // must not start a microphone after backgrounding or changing accounts.
      final currentKey = 'windows.voice.v1.${await AiConsent.currentKey()}';
      if (mounted && _foreground && currentKey == key) await _session.start();
    } catch (_) {
      if (mounted && _foreground) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content:
                Text('تعذّر بدء الميكروفون — حاول مجدّداً أو اكتب الأمر')));
      }
    } finally {
      _asking = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _session.removeListener(_changed);
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final busy = _session.phase == DesktopVoicePhase.starting ||
        _session.phase == DesktopVoicePhase.transcribing;
    final listening = _session.phase == DesktopVoicePhase.listening;
    return Tooltip(
        message: busy
            ? 'أحوّل الصوت إلى نص…'
            : listening
                ? 'إنهاء التسجيل'
                : switch (widget.language) {
                    'ar' => 'أمر صوتي بالعربي',
                    'en' => 'أمر صوتي بالإنكليزي',
                    _ => 'أمر صوتي — عربي أو إنكليزي',
                  },
        child: InkResponse(
            onTap: busy ? null : _toggle,
            radius: 20,
            child: Padding(
                padding: const EdgeInsets.all(2),
                child: busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(
                        listening ? Icons.stop_rounded : Icons.mic_none_rounded,
                        size: 24,
                        color: listening
                            ? AppColors.error
                            : AppColors.brandOnSoft))));
  }
}
