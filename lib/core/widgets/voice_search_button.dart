import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../theme/colors.dart';
import '../../theme/typography.dart';

/// زرّ الإملاء الصوتي — يكتب ما يُقال في `controller`.
///
/// ⚠️ هذا المنطق مستخرَج لا مكتوب من جديد: كان يعيش داخل شاشة البحث
/// السريع، وأغلبه معالجة أعطال أجهزة بعينها تراكمت من بلاغات مستخدمين
/// (Tecno/Huawei/Xiaomi تشغّل محرّك تعرّف خاصّاً لا يُعلن العربيّة،
/// وiOS يضيف ترقيماً يُفشل البحث بـcontains). نسخه لشاشة ثانية كان
/// يعني أن يصل أيّ إصلاح لاحق إلى نصف الأماكن.
class VoiceSearchButton extends StatefulWidget {
  const VoiceSearchButton({
    super.key,
    required this.controller,
    this.size = 20,
    this.onResult,
    this.onFinal,
    this.onFinalAlts,
    this.onListening,
    this.autoStart = false,
    this.idleColor,
    this.language = 'ar',
  });

  final TextEditingController controller;
  final double size;

  /// يُستدعى بعد كتابة النصّ — لمن يحتاج تشغيل بحث فوري.
  final ValueChanged<String>? onResult;

  /// النصّ النهائيّ وحده (انتهى الكلام) — «الأمر الصوتيّ» ينفّذ عنده لا مع كلّ كلمة.
  final ValueChanged<String>? onFinal;

  /// النصّ النهائيّ مع بدائل المحرّك لما سمع (الأوّل = ما يُكتب) — «الأمر الصوتيّ» يختار منها ما يطابق مشتركاً. يُنادى بدل
  /// [onFinal] حين يُعطى.
  final ValueChanged<List<String>>? onFinalAlts;

  /// لغة الإملاء: ar (كما كان) أو en — محرّك الهاتف يسمع لغةً واحدة في الجلسة (١٠ نوفمبر: «الأمر الصوتي ٢»).
  final String language;

  /// بدأ/توقّف الاستماع — لشاشةٍ تعرض «أسمعك…».
  final ValueChanged<bool>? onListening;

  /// يبدأ الاستماع بنفسه بعد أوّل إطار (الإذن في سياقه: الوكيل فتح «أمر صوتي» بنفسه).
  final bool autoStart;

  /// لون الأيقونة وهو لا يسمع (الافتراضيّ رماديّ).
  final Color? idleColor;

  @override
  State<VoiceSearchButton> createState() => _VoiceSearchButtonState();
}

class _VoiceSearchButtonState extends State<VoiceSearchButton> {
  final _speech = SpeechToText();
  bool _listening = false;
  bool _ready = false;

  /// أفضل لغة عربيّة يُعلنها الجهاز فعلاً — لا 'ar' مفترضة.
  String? _arLocale;

  /// أفضل إنكليزيّة يُعلنها الجهاز (en-US ثمّ en-GB ثمّ أيّ en) — للأمر بالإنكليزيّة.
  String? _enLocale;

  bool get _command => widget.onFinal != null || widget.onFinalAlts != null;

  /// التهيئة تطلب إذنَي الميكروفون والتعرّف على الكلام، فتؤجَّل إلى أوّل ضغطةٍ
  /// على الزرّ: كانت في initState فيظهر الطلب بمجرّد فتح شاشة المشتركين قبل
  /// أيّ نيّةٍ للبحث الصوتيّ (App Store 5.1.1 — الإذن في سياقه).
  Future<void>? _initFuture;

  @override
  void initState() {
    super.initState();
    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_listening) _toggle();
      });
    }
  }

  @override
  void didUpdateWidget(covariant VoiceSearchButton old) {
    super.didUpdateWidget(old);
    // تبدّلت اللغة والمايك يسمع بالقديمة ⇒ يُلغى (لا نصّ بلغةٍ لم تُطلب)
    if (old.language != widget.language && _listening) {
      _speech.cancel();
      _setListening(false);
    }
  }

  @override
  void dispose() {
    // Leaving the sheet must not turn an unfinished command into a result.
    _speech.cancel();
    super.dispose();
  }

  void _setListening(bool v) {
    if (_listening == v) return;
    setState(() => _listening = v);
    widget.onListening?.call(v);
  }

  void _attachSpeechListeners() {
    // SpeechToText is shared; initialize() keeps the first widget's callbacks.
    // Rebind them when this button starts a new session (including after search).
    _speech.statusListener = (s) {
      // ثلاث حالات تُطلَق؛ `listening` تأكيد تسجيل لا تغيير واجهة.
      if (s == 'done' || s == 'notListening') {
        if (mounted) _setListening(false);
      }
    };
    _speech.errorListener = (err) {
      if (!mounted) return;
      // ⚠️ إعادة الضبط أوّلاً دائماً: بعض الأخطاء (error_unknown 300
      // و error_no_match) تعود **بلا** status='done' مقابل، فيبقى
      // الزرّ عالقاً على «إيقاف» إلى الأبد — بلاغ مستخدم.
      _setListening(false);
      _snack(_messageFor(err.errorMsg));
    };
  }

  Future<void> _init() async {
    try {
      _attachSpeechListeners();
      final ok = await _speech.initialize(
        onStatus: _speech.statusListener,
        onError: _speech.errorListener,
      );
      if (!mounted) return;
      setState(() => _ready = ok);
      if (ok) await _probeArLocale();
    } catch (_) {
      // التعرّف غير متاح — الزرّ يبقى معطّلاً بلا ضجيج.
    }
  }

  /// رسالة إرشاديّة لكلّ عطل معروف. الحلّ الفعلي لأكثرها ليس في
  /// التطبيق بل في إعدادات النظام، فالرسالة تدلّ على المسار نصّاً.
  String? _messageFor(String msg) {
    if (msg.contains('language-not-supported') ||
        msg.contains('error_language_not_supported')) {
      return '${widget.language == 'en' ? 'الإنكليزية' : 'العربية'} غير مدعومة في المحرّك الحالي. الحلّ:\n'
          'Settings → Apps → Default apps → Digital assistant → Google';
    }
    if (msg.contains('error_client') ||
        msg.contains('error_no_match') ||
        msg.contains('error_speech_timeout')) {
      return 'لم يُلتقط أي كلام — حاول مجدّداً بصوت أعلى';
    }
    if (msg.contains('error_network')) {
      return 'الميكروفون يحتاج اتصال إنترنت لهذا المحرّك';
    }
    if (msg.contains('insufficient-permissions') ||
        msg.contains('permission')) {
      return 'صلاحية الميكروفون مرفوضة — فعّلها من إعدادات النظام';
    }
    if (msg.contains('error_unknown') || msg.contains('300')) {
      return 'محرّك الصوت الحالي لا يعمل. غيّره من:\n'
          'Settings → Apps → Default apps → Digital assistant → Google';
    }
    return null;
  }

  /// ترتيب الأفضليّة: ar-IQ (أقرب لأسماء المشتركين) ثمّ ar-SA ثمّ أيّ
  /// `ar*`. تثبيت 'ar' وحدها يكسر أجهزةً لا تُعلن إلّا وسوم BCP-47
  /// كاملة — تعطي error_unknown (300).
  Future<void> _probeArLocale() async {
    try {
      final locales = await _speech.locales();
      final ids = locales.map((l) => l.localeId).toList();
      String? pick;
      for (final want in ['ar-iq', 'ar-sa']) {
        for (final id in ids) {
          if (id.toLowerCase() == want) {
            pick = id;
            break;
          }
        }
        if (pick != null) break;
      }
      pick ??= ids.cast<String?>().firstWhere(
            (id) => id!.toLowerCase().startsWith('ar'),
            orElse: () => null,
          );
      _arLocale = pick;
      // الإنكليزيّة: الوسم قد يأتي en_US أو en-US حسب المنصّة
      String? en;
      for (final want in ['en-us', 'en-gb']) {
        for (final id in ids) {
          if (id.toLowerCase().replaceAll('_', '-') == want) {
            en = id;
            break;
          }
        }
        if (en != null) break;
      }
      en ??= ids.cast<String?>().firstWhere(
            (id) => id!.toLowerCase().startsWith('en'),
            orElse: () => null,
          );
      _enLocale = en;
    } catch (_) {
      _arLocale = null;
      _enLocale = null;
    }
  }

  void _snack(String? msg) {
    if (msg == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: AppType.body(color: AppColors.onBrand)),
      backgroundColor: AppColors.textHi,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 5),
    ));
  }

  Future<void> _toggle() async {
    HapticFeedback.selectionClick();
    if (_listening) {
      await _speech.stop();
      if (mounted) _setListening(false);
      return;
    }
    if (!_ready) {
      await (_initFuture ??= _init());
      if (!mounted) return;
      if (!_ready) {
        _initFuture = null; // تُعاد المحاولة في الضغطة التالية
        final denied = !(await _speech.hasPermission.catchError((_) => false));
        _snack(denied
            ? 'صلاحية الميكروفون مرفوضة — فعّلها من إعدادات النظام'
            : 'التعرّف على الصوت غير متاح على هذا الجهاز');
        return;
      }
    }
    _attachSpeechListeners();
    _setListening(true);
    // 'ar' احتياطاً حين يفشل الاستكشاف: أجهزة بمحرّك خاصّ تشترط
    // localeId وترفض null، ومعظمها يقبل الرمز العامّ.
    final locale = widget.language == 'en' ? (_enLocale ?? 'en-US') : (_arLocale ?? 'ar');
    try {
      await _speech.listen(
        onResult: (r) {
          if (!mounted) return;
          // ⚠️ قصّ الترقيم النهائي ليس تجميلاً: iOS يضيف نقطةً
          // تلقائيّاً («علي.») والبحث بـ`contains` لا يطابق عندها،
          // فيرى المستخدم «لا نتائج» رغم أنّ الإملاء صحيح.
          var txt = r.recognizedWords.trim();
          txt = txt.replaceAll(RegExp(r'''[.,;:!?،؛؟"']+$'''), '').trim();
          if (txt.isEmpty) return;
          widget.controller.text = txt;
          widget.controller.selection =
              TextSelection.collapsed(offset: txt.length);
          widget.onResult?.call(txt);
          if (r.finalResult) {
            _setListening(false);
            final withAlts = widget.onFinalAlts;
            if (withAlts != null) {
              // بدائل المحرّك لما سمع — بلا ترقيمها الأخير وبلا تكرار، وما كُتب أوّلها
              final alts = <String>[txt];
              for (final a in r.alternates) {
                final t = a.recognizedWords.trim().replaceAll(RegExp(r'''[.,;:!?،؛؟"']+$'''), '').trim();
                if (t.isNotEmpty && !alts.contains(t)) alts.add(t);
              }
              withAlts(alts.take(4).toList());
            } else {
              widget.onFinal?.call(txt);
            }
          } else if (_command && _speech.isListening) {
            // iOS dictation can keep producing partial text without isFinal.
            // Stop after a short pause; the package then delivers its final
            // result (or its existing last-partial fallback). Give the first
            // word more time so a slow recognizer is not cut off at startup.
            _speech.changePauseFor(const Duration(seconds: 2));
          }
        },
        listenOptions: SpeechListenOptions(
          localeId: locale,
          partialResults: true,
          cancelOnError: true,
          listenMode: ListenMode.dictation,
          onDevice: false,
          pauseFor: _command ? const Duration(seconds: 8) : null,
          listenFor: _command ? const Duration(seconds: 15) : null,
        ),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('🎙️ listen() threw: $e');
      if (mounted) _setListening(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return InkResponse(
      radius: 20,
      onTap: _toggle,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Icon(
          _listening ? Icons.stop_rounded : Icons.mic_none_rounded,
          size: widget.size,
          color: _listening
              ? AppColors.error
              : (widget.idleColor ?? AppColors.textLow),
        ),
      ),
    );
  }
}
