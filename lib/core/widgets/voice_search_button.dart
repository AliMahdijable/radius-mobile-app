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
  });

  final TextEditingController controller;
  final double size;

  /// يُستدعى بعد كتابة النصّ — لمن يحتاج تشغيل بحث فوري.
  final ValueChanged<String>? onResult;

  @override
  State<VoiceSearchButton> createState() => _VoiceSearchButtonState();
}

class _VoiceSearchButtonState extends State<VoiceSearchButton> {
  final _speech = SpeechToText();
  bool _listening = false;
  bool _ready = false;

  /// أفضل لغة عربيّة يُعلنها الجهاز فعلاً — لا 'ar' مفترضة.
  String? _arLocale;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _speech.stop();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final ok = await _speech.initialize(
        onStatus: (s) {
          // ثلاث حالات تُطلَق؛ `listening` تأكيد تسجيل لا تغيير واجهة.
          if (s == 'done' || s == 'notListening') {
            if (mounted) setState(() => _listening = false);
          }
        },
        onError: (err) {
          if (!mounted) return;
          // ⚠️ إعادة الضبط أوّلاً دائماً: بعض الأخطاء (error_unknown 300
          // و error_no_match) تعود **بلا** status='done' مقابل، فيبقى
          // الزرّ عالقاً على «إيقاف» إلى الأبد — بلاغ مستخدم.
          setState(() => _listening = false);
          _snack(_messageFor(err.errorMsg));
        },
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
      return 'العربية غير مدعومة في المحرّك الحالي. الحلّ:\n'
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
    } catch (_) {
      _arLocale = null;
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
      if (mounted) setState(() => _listening = false);
      return;
    }
    if (!_ready) {
      _snack('التعرّف على الصوت غير متاح على هذا الجهاز');
      return;
    }
    setState(() => _listening = true);
    // 'ar' احتياطاً حين يفشل الاستكشاف: أجهزة بمحرّك خاصّ تشترط
    // localeId وترفض null، ومعظمها يقبل الرمز العامّ.
    final locale = _arLocale ?? 'ar';
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
        },
        listenOptions: SpeechListenOptions(
          localeId: locale,
          partialResults: true,
          cancelOnError: true,
          listenMode: ListenMode.dictation,
          onDevice: false,
        ),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('🎙️ listen() threw: $e');
      if (mounted) setState(() => _listening = false);
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
          color: _listening ? AppColors.error : AppColors.textLow,
        ),
      ),
    );
  }
}
