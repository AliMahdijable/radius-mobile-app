import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../api/subscribers_api.dart';
import '../../core/util/format.dart';
import '../../models/subscriber.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../subscribers/subscriber_detail_screen.dart';

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
    barrierColor: AppColors.scrim,
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

/// Marker thrown internally when locales() returns nothing — caught
/// in [_QuickSearchOverlayState._probeArLocale] to drop into the
/// 'no Arabic available' branch instead of crashing on firstWhere.
class _NoLocales implements Exception {
  const _NoLocales();
}

class _QuickSearchOverlayState extends State<QuickSearchOverlay> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  final _speech = SpeechToText();
  bool _listening = false;
  bool _speechReady = false;
  String _q = '';

  /// Arabic localeId picked from whatever the device actually exposes
  /// (ar-IQ → ar-SA → first 'ar*' → null fallback). Probed once on
  /// init so a tap on the mic doesn't have to await locales() and risk
  /// the user double-tapping. null = no Arabic locale available; we
  /// surface a snackbar instead of starting a session that will fail
  /// with error_unknown.
  String? _arLocale;

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
          if (kDebugMode) debugPrint('🎙️ status: $s');
          // notListening + done + listening — all three fire; only
          // the first two should clear our spinner. The 'listening'
          // status is just confirmation we're recording, no UI flip.
          if (s == 'done' || s == 'notListening') {
            if (mounted) setState(() => _listening = false);
          }
        },
        onError: (err) {
          if (kDebugMode) debugPrint('🎙️ error: ${err.errorMsg}');
          if (!mounted) return;
          // Always reset the button state so it can't get stuck. Some
          // error codes (error_unknown 300, error_no_match) come back
          // WITHOUT a matching status='done', leaving _listening=true
          // and the mic icon as 'stop' forever — user reported this.
          setState(() => _listening = false);
          // 2026-07-14: أجهزة Tecno/Huawei/Xiaomi غالباً تشغّل محرّك
          // تعرّف صوتي خاص (HiOS/HMS/Baidu) بدل Google، فحتى بعد تحميل
          // اللغة في Google Voice يبقى المحرّك النشط لا يعرفها. الحلّ
          // الفعلي = تغيير المحرّك الافتراضي من إعدادات النظام.
          if (err.errorMsg.contains('language-not-supported') ||
              err.errorMsg.contains('error_language_not_supported')) {
            _showSnack(
              'العربية غير مدعومة في المحرّك الحالي. الحلّ:\n'
              'Settings → Apps → Default apps → Digital assistant → Google\n'
              'أو: Settings → General → Voice input → Google',
            );
          } else if (err.errorMsg.contains('error_client') ||
              err.errorMsg.contains('error_no_match') ||
              err.errorMsg.contains('error_speech_timeout')) {
            _showSnack('لم يُلتقط أي كلام — حاول مجدّداً بصوت أعلى');
          } else if (err.errorMsg.contains('error_network')) {
            _showSnack('الميكروفون يحتاج اتصال إنترنت لهذا المحرّك');
          } else if (err.errorMsg.contains('insufficient-permissions') ||
              err.errorMsg.contains('permission')) {
            _showSnack('صلاحية الميكروفون مرفوضة — فعّلها من إعدادات النظام');
          } else if (err.errorMsg.contains('error_unknown') ||
              err.errorMsg.contains('300')) {
            // 2026-07-14: Tecno/Huawei/Xiaomi غالباً — المحرّك النشط
            // ليس Google. اقتراح مباشر لتغييره.
            _showSnack(
              'محرّك الصوت الحالي لا يعمل. غيّره من:\n'
              'Settings → Apps → Default apps → Digital assistant → Google',
            );
          }
        },
      );
      if (!mounted) return;
      setState(() => _speechReady = ok);
      if (ok) await _probeArLocale();
    } catch (_) {/* speech unavailable — mic button stays disabled */}
  }

  /// Picks the best Arabic localeId the device actually advertises.
  /// Hardcoding 'ar' (language-only) sometimes works on Android but
  /// breaks on devices where the recognizer only lists full BCP-47
  /// tags (e.g. ar-SA) — those raise error_unknown (300) when asked
  /// for 'ar' (user's TECNO log). Priority order:
  ///   1. ar-IQ (Iraqi — closest to subscriber names)
  ///   2. ar-SA (Saudi — most common Arabic locale Google ships)
  ///   3. any 'ar*' the device exposes
  ///   4. null → fall back to device default at listen() time so at
  ///      least SOMETHING works
  Future<void> _probeArLocale() async {
    try {
      final locales = await _speech.locales();
      if (kDebugMode) {
        final ids = locales.map((l) => l.localeId).join(', ');
        debugPrint('🎙️ available locales: [$ids]');
      }
      String? pick;
      for (final l in locales) {
        if (l.localeId.toLowerCase() == 'ar-iq') {
          pick = l.localeId;
          break;
        }
      }
      pick ??= locales
          .firstWhere(
            (l) => l.localeId.toLowerCase() == 'ar-sa',
            orElse: () => locales.firstWhere(
              (l) => l.localeId.toLowerCase().startsWith('ar'),
              orElse: () =>
                  locales.isEmpty ? throw _NoLocales() : locales.first,
            ),
          )
          .localeId;
      // If the firstWhere fell to "first" (no 'ar*' match) we DO NOT
      // want to use it — that would mean dictating Spanish for an
      // Iraqi subscriber. Filter back out.
      if (pick.toLowerCase().startsWith('ar')) {
        _arLocale = pick;
      } else {
        _arLocale = null;
      }
      if (kDebugMode) debugPrint('🎙️ picked ar locale: $_arLocale');
    } on _NoLocales {
      _arLocale = null;
    } catch (e) {
      if (kDebugMode) debugPrint('🎙️ locale probe failed: $e');
      _arLocale = null;
    }
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
    // 2026-07-14: قبل، كنّا نرفض التسجيل إذا ما لقينا `ar-*` في قائمة
    // اللغات المُعلَنة. المشكلة: أجهزة Tecno/Huawei/Xiaomi تستعمل محرّك
    // خاص لا يعلن Arabic حتى لو النظام عربي. نحاول ونمرّر localeId=null
    // فيلتقط اللغة من إعداد النظام؛ إن فشل، الـonError يعرض رسالة
    // إرشاديّة تحدّد الحلّ (تغيير المحرّك الافتراضي إلى Google).
    setState(() => _listening = true);
    // 2026-07-14: fallback ترتيبي للـlocale:
    //   1. الـprobe لقى ar-IQ / ar-SA / ar-* → استعمله (الأفضل).
    //   2. probe فشل → 'ar' (bare code) — أجهزة Tecno/Huawei/Xiaomi
    //      كانت تعطي error_unknown (300) مع null لأن محرّكها الخاص
    //      يشترط localeId. 'ar' يقبله معظم المحرّكات كقيمة عامّة.
    //   3. لو المحرّك يرفض 'ar' نفسه، الـonError يعرض رسالة تدلّ
    //      المستخدم على تغيير الافتراضي إلى Google.
    final effectiveLocale = _arLocale ?? 'ar';
    if (kDebugMode) debugPrint('🎙️ listen with locale="$effectiveLocale"');
    try {
      await _speech.listen(
        localeId: effectiveLocale,
        onResult: (r) {
          if (!mounted) return;
          // 2026-07-14: تنظيف نتيجة الصوت قبل ما تدخل الحقل:
          //  (1) لو رجعت فارغة (المستخدم ضغط إيقاف مبكراً) — نتجاهلها
          //      ونبقي النصّ الجزئي الي عُرض.
          //  (2) trim للمسافات ابتداءً وانتهاءً — Google أحياناً يرجع
          //      " كلمة".
          //  (3) iOS Speech Recognition يضيف علامات ترقيم تلقائياً
          //      ("Ahmed." "علي؟") — البحث بـcontains ما يطابق
          //      "ahmed@popq" مع النقطة، فالمستخدم يشوف "0 نتائج"
          //      رغم أن الصوت انترجم صح. نقصّ الترقيم النهائيّ.
          var txt = r.recognizedWords.trim();
          txt = txt.replaceAll(RegExp(r'''[.,;:!?،؛؟"']+$'''), '').trim();
          if (txt.isEmpty) return;
          setState(() {
            _ctrl.text = txt;
            _ctrl.selection = TextSelection.collapsed(
              offset: _ctrl.text.length,
            );
          });
        },
        // 2026-07-14 (تحديث): partialResults=true حتى النصّ يظهر أثناء
        // الكلام (تجربة أفضل — بحث لحظي بدون انتظار الضغط على إيقاف).
        // كان false لتفادي error_unknown 300 على Android، لكن اتّضح
        // لاحقاً أن ذاك الخطأ كان من الـSimulator فقط.
        // listenMode=dictation + onDevice=false نبقيهما — أكثر توافقاً
        // ولا يؤثّران على iOS.
        listenOptions: SpeechListenOptions(
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

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: AppType.button(color: AppColors.onBrand)),
        backgroundColor: AppColors.errorFill,
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
    Theme.of(context); // theme-dep (dark-mode)
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
                      Icon(Icons.search_rounded,
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
                Divider(height: 1, color: AppColors.border),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    // 2026-07-14: كان 0.5 من الشاشة. بعد إضافة شارات
                    // IP/DL/UL/الجهاز صار كل صف أطول، فتظهر 4 نتائج
                    // فقط من أصل 12 والباقي يبدو "مقطوع". 0.75 يعطي
                    // مساحة كافية لـ~10 نتائج مباشرة مع القابليّة للتمرير
                    // إن تجاوزت.
                    maxHeight: MediaQuery.sizeOf(context).height * 0.75,
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
                                SizedBox(
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
                                  style:
                                      AppType.subtitle(color: AppColors.brand),
                                ),
                              ],
                            ),
                          )
                        else
                          _Results(query: _q),
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
    Theme.of(context); // theme-dep (dark-mode)
    final bg = listening
        ? AppColors.error
        : (enabled ? AppColors.brandSoftBg : AppColors.surfaceInput);
    final fg = listening
        ? AppColors.onBrand
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

/// Subscriber search results panel — pulls the shared cached list
/// from SubscribersApi.loadAll (45s TTL, same source as the
/// subscribers tab and dashboard so we don't trigger an extra fetch)
/// and filters client-side. Matches by:
///   • username substring (case-insensitive)
///   • firstname OR lastname substring (case-insensitive Arabic)
///   • phone digits — strips formatting from BOTH the query and the
///     stored phone/mobile so '07712' matches '0771 234 5678'
///
/// Up to [_maxResults] rows are rendered as cards. Tap → pops the
/// overlay and pushes the same SubscriberDetailScreen the list tab
/// uses, with all its operations live (activate / extend / pay-debt /
/// toggle / disconnect).
class _Results extends StatelessWidget {
  const _Results({required this.query});
  final String query;

  static const _maxResults = 12;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const _EmptyHints();
    return FutureBuilder<List<Subscriber>?>(
      future: SubscribersApi.loadAllWithOnline(),
      builder: (_, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Padding(
            padding: EdgeInsets.symmetric(vertical: Sp.huge),
            child: Center(
              child: CircularProgressIndicator(color: AppColors.brand),
            ),
          );
        }
        final all = snapshot.data;
        if (all == null) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: Sp.huge),
            child: Center(
              child: Text(
                'تعذّر جلب قائمة المشتركين',
                style: AppType.subtitle(color: AppColors.error),
              ),
            ),
          );
        }
        final matches = _filter(all, trimmed);
        if (matches.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(
              vertical: Sp.huge,
              horizontal: Sp.lg,
            ),
            child: Center(
              child: Column(
                children: [
                  Icon(LucideIcons.searchX, color: AppColors.textLow, size: 32),
                  const SizedBox(height: Sp.sm),
                  Text(
                    'لا يوجد مشترك يطابق "$trimmed"',
                    style: AppType.subtitle(color: AppColors.textMid),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }
        final clipped = matches.take(_maxResults).toList();
        return Padding(
          padding: const EdgeInsets.fromLTRB(Sp.sm, Sp.xs, Sp.sm, Sp.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(Sp.sm, Sp.sm, Sp.sm, 4),
                child: Text(
                  matches.length > _maxResults
                      ? 'أول $_maxResults من ${matches.length} نتيجة'
                      : '${matches.length} نتيجة',
                  style: AppType.muted(color: AppColors.textLow)
                      .copyWith(fontSize: 10.5, letterSpacing: 0.4),
                ),
              ),
              for (final s in clipped) _ResultRow(sub: s),
            ],
          ),
        );
      },
    );
  }

  /// Score-and-filter — exact prefix matches rank above contains
  /// matches so 'ahmed' finds 'ahmed@x' before 'mohammed@x'.
  static List<Subscriber> _filter(List<Subscriber> all, String raw) {
    final q = _normalizeArabic(raw.toLowerCase().trim());
    final qPhone = _normalizeIraqPhone(raw);
    final scored = <(int, Subscriber)>[];
    for (final s in all) {
      final score = _scoreOne(s, q, qPhone);
      if (score > 0) scored.add((score, s));
    }
    scored.sort((a, b) => b.$1.compareTo(a.$1));
    return scored.map((e) => e.$2).toList();
  }

  /// 2026-07-14: تطبيع نصّ عربي قبل المقارنة. iOS Speech Recognition
  /// (وأحياناً Google) يحقن أحرفاً غير مرئيّة تكسر contains-match:
  ///
  /// • علامات BiDi (‎ LRM, ‏ RLM, ‪-‮) — اتّجاه النصّ.
  /// • NBSP ( ) بدل المسافة العاديّة.
  /// • تشكيل (فتحة/كسرة/ضمّة/شدّة/سكون: ً-ٟ, ٰ).
  /// • تطويل (ـ: ـ) — أحياناً يُستخدم للتنسيق البصري.
  /// • ZWJ/ZWNJ (‌, ‍) — روابط الأحرف.
  ///
  /// كما نوحّد أشكال الأحرف المتشابهة (أ/إ/آ → ا، ى → ي، ة → ه) — الاسم
  /// المُخزَّن قد يكون بشكل، والمنطوق يُترجم بشكل آخر.
  static String _normalizeArabic(String s) {
    if (s.isEmpty) return s;
    var t = s;
    // 1) شيل الأحرف غير المرئيّة + التشكيل + التطويل (\u escapes صريحة):
    //    ​-\u200F  ZWSP, ZWNJ, ZWJ, LRM, RLM
    //    \u202A-\u202E  LRE, RLE, PDF, LRO, RLO
    //    \u2066-\u2069  LRI, RLI, FSI, PDI
    //    ً-ٟ  التشكيل العربيّ (فتحة/ضمّة/كسرة/شدّة/سكون/تنوين)
    //    ٰ          الألف الخنجريّة العلويّة
    //    ـ          التطويل (ـ)
    t = t.replaceAll(
      RegExp(r'[​-\u200F\u202A-\u202E\u2066-\u2069ً-ٰٟـ]'),
      '',
    );
    // 2) NBSP + غيرها من المسافات الخاصّة → مسافة عاديّة.
    t = t.replaceAll(RegExp(r'[  -   　]'), ' ');
    // 3) توحيد أحرف عربيّة متبادلة (المتحدّث/المُخزَّن قد يستخدم أشكالاً
    //    مختلفة لنفس الحرف — أشكال أسفل تنقص التطابق بلا سبب).
    t = t
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('آ', 'ا')
        .replaceAll('ى', 'ي')
        .replaceAll('ئ', 'ي')
        .replaceAll('ة', 'ه');
    // 4) دمج المسافات المتعدّدة.
    t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
    return t;
  }

  /// Normalize Iraqi phone numbers to a canonical core so the same
  /// subscriber matches regardless of whether the number is stored as
  /// '+9647712345678' / '009647712345678' / '07712345678' /
  /// '7712345678'. Admin typing '77', '077', '964...', '+964...' all
  /// reduce to the same digits and contains-match against the same
  /// canonical store value (مطلب 2026-06-07).
  ///
  /// Stripping rules (applied in order on the digits-only form):
  ///   1. drop leading '00' (international dial-out prefix)
  ///   2. drop leading '964' (Iraqi country code)
  ///   3. drop a single leading '0' (Iraqi national trunk)
  /// What remains is the bare 10-digit mobile (7xxxxxxxxx) or
  /// shorter prefix the admin typed.
  static String _normalizeIraqPhone(String raw) {
    var d = raw.replaceAll(RegExp(r'\D'), '');
    if (d.startsWith('00')) d = d.substring(2);
    if (d.startsWith('964')) d = d.substring(3);
    if (d.startsWith('0')) d = d.substring(1);
    return d;
  }

  static int _scoreOne(Subscriber s, String q, String qPhone) {
    var score = 0;
    // نطبّع الاثنين — الحقول المُخزَّنة قد يكون فيها أحرف عربيّة مختلفة
    // الشكل عن ما ينطق المستخدم. مثلاً "عمّي" (بشدّة) vs "عمي"، أو
    // "أحمد" vs "احمد". بلا تطبيع، voice-typed لن يطابق stored-typed.
    final username = _normalizeArabic(s.username.toLowerCase());
    final fname = _normalizeArabic(s.firstname.trim());
    final lname = _normalizeArabic(s.lastname.trim());
    final full = '$fname $lname'.trim();
    if (q.isNotEmpty) {
      if (username == q) {
        score += 100;
      } else if (username.startsWith(q)) {
        score += 60;
      } else if (username.contains(q)) {
        score += 30;
      }
      if (fname.contains(q) || lname.contains(q)) score += 40;
      if (full.contains(q)) score += 20;
    }
    // Phone: normalize the stored value with the same Iraqi rules
    // as the query so '07712345678' (stored), '+9647712345678'
    // (stored), and '7712345678' (typed) all collapse to the same
    // core for contains-match. >= 2 digits is enough to start
    // filtering — admin types '77' and sees their 077 numbers.
    if (qPhone.length >= 2) {
      final phoneCore = _normalizeIraqPhone(s.phone ?? '');
      final mobileCore = _normalizeIraqPhone(s.mobile ?? '');
      if (phoneCore.contains(qPhone) || mobileCore.contains(qPhone)) {
        // Prefix > middle match — 077 typed should rank 07712xxx
        // above 0xxxx77yyy.
        if (phoneCore.startsWith(qPhone) || mobileCore.startsWith(qPhone)) {
          score += 70;
        } else {
          score += 45;
        }
      }
    }
    return score;
  }
}

class _EmptyHints extends StatelessWidget {
  const _EmptyHints();

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Padding(
      padding: const EdgeInsets.all(Sp.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ابحث بالاسم العربي، اسم المستخدم، أو رقم الهاتف',
            style: AppType.muted(color: AppColors.textLow)
                .copyWith(fontSize: 11, letterSpacing: 0.4, height: 1.6),
          ),
          const SizedBox(height: Sp.sm),
          Row(
            children: [
              Icon(Icons.mic_rounded,
                  color: AppColors.brandSoftBorder, size: 16),
              const SizedBox(width: 6),
              Text(
                'أو اضغط الميكروفون للبحث الصوتي',
                style: AppType.muted(color: AppColors.textMid).copyWith(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.sub});
  final Subscriber sub;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final statusColor = _statusColor(sub);
    final statusLabel = _statusLabel(sub);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          // Pop the overlay FIRST so we don't push the detail screen
          // on top of a dialog (otherwise the navigation stack ends
          // up as Home > Dialog > Detail and back goes to Dialog
          // briefly).
          Navigator.of(context).pop();
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => SubscriberDetailScreen(sub: sub),
              fullscreenDialog: true,
            ),
          );
        },
        borderRadius: BorderRadius.circular(R.md),
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: Sp.sm, vertical: Sp.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Status avatar — same 7-state color as the list card.
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.14),
                      shape: BoxShape.circle,
                      border:
                          Border.all(color: statusColor.withValues(alpha: 0.3)),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      sub.isOnline ? LucideIcons.wifi : LucideIcons.wifiOff,
                      color: statusColor,
                      size: 16,
                    ),
                  ),
                  if (sub.isOnline)
                    Positioned(
                      bottom: -1,
                      right: -1,
                      child: Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: AppColors.brand,
                          shape: BoxShape.circle,
                          border:
                              Border.all(color: AppColors.surface, width: 1.5),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: Sp.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            sub.fullName,
                            style:
                                AppType.label(color: AppColors.textHi).copyWith(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (sub.username.isNotEmpty &&
                            sub.username != sub.fullName) ...[
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              '(${sub.username})',
                              style: AppType.muted(color: AppColors.textLow)
                                  .copyWith(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(R.pill),
                          ),
                          child: Text(
                            statusLabel,
                            style: AppType.muted(color: statusColor).copyWith(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if ((sub.profileName?.isNotEmpty ?? false)) ...[
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              sub.profileName!,
                              style: AppType.muted(color: AppColors.textMid)
                                  .copyWith(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                        if (sub.hasDebt) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: AppColors.dangerSoftBg,
                              borderRadius: BorderRadius.circular(R.pill),
                              border: Border.all(
                                color: AppColors.dangerSoftBorder,
                              ),
                            ),
                            child: Text(
                              'دين ${formatIQD(sub.debtAbs.round())}',
                              style: AppType.muted(color: AppColors.error)
                                  .copyWith(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (sub.displayPhone.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(LucideIcons.phone,
                              size: 10, color: AppColors.textLow),
                          const SizedBox(width: 4),
                          Text(
                            sub.displayPhone,
                            style: AppType.muted(color: AppColors.textLow)
                                .copyWith(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                    // 2026-07-16: آخر اتصال للأوف لاين فقط (SAS4 last_online).
                    if (!sub.isOnline &&
                        (sub.lastOnline?.isNotEmpty ?? false)) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(LucideIcons.history,
                              size: 10, color: AppColors.textLow),
                          const SizedBox(width: 4),
                          Text(
                            _formatLastOnlineShort(sub.lastOnline!),
                            style: AppType.muted(color: AppColors.textLow)
                                .copyWith(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                    // معلومات الجلسة الحيّة (تظهر فقط لو المشترك online + عندنا
                    // البيانات من /api/v2/online-users). قبل 2026-07-14 كانت
                    // مخفيّة لأن الشاشة تستدعي loadAll فقط بدون enrichment.
                    if (sub.isOnline &&
                        ((sub.downloadBytes ?? 0) > 0 ||
                            (sub.uploadBytes ?? 0) > 0 ||
                            (sub.ipAddress?.isNotEmpty ?? false) ||
                            (sub.deviceVendor?.isNotEmpty ?? false))) ...[
                      const SizedBox(height: 3),
                      Wrap(
                        spacing: 6,
                        runSpacing: 2,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if ((sub.downloadBytes ?? 0) > 0 ||
                              (sub.uploadBytes ?? 0) > 0)
                            _InfoChip(
                              icon: LucideIcons.arrowDownUp,
                              text:
                                  '${_fmtBytes(sub.downloadBytes ?? 0)} ↓ / ${_fmtBytes(sub.uploadBytes ?? 0)} ↑',
                            ),
                          if (sub.ipAddress?.isNotEmpty ?? false)
                            _InfoChip(
                              icon: LucideIcons.globe,
                              text: sub.ipAddress!,
                            ),
                          if (sub.deviceVendor?.isNotEmpty ?? false)
                            _InfoChip(
                              icon: LucideIcons.router,
                              text: sub.deviceVendor!,
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              Icon(LucideIcons.chevronLeft, color: AppColors.textLow, size: 16),
            ],
          ),
        ),
      ),
    );
  }

  static Color _statusColor(Subscriber s) {
    if (s.isDisabled) return AppColors.textLabel;
    if (s.isOnline) {
      if (s.isExpired) return AppColors.brandAccent;
      if (s.isNearExpiry) return AppColors.warning;
      return AppColors.brandAccent;
    }
    if (s.isExpired) return AppColors.error;
    if (s.isNearExpiry) return AppColors.warning;
    return AppColors.success;
  }

  static String _statusLabel(Subscriber s) {
    if (s.isDisabled) return 'معطّل';
    if (s.isOnline) {
      if (s.isExpired) return 'متصل / منتهي';
      if (s.isNearExpiry) return 'متصل / قارب';
      return 'متصل';
    }
    if (s.isExpired) return 'منتهي';
    if (s.isNearExpiry) return 'قارب الانتهاء';
    return 'نشط';
  }
}

/// 2026-07-16: تنسيق مختصر لـSAS4 last_online — "قبل X" بأسلوب طبيعي.
/// يُعرَض في بطاقة البحث السريع للمشتركين غير المتّصلين فقط.
String _formatLastOnlineShort(String raw) {
  final t = DateTime.tryParse(raw) ?? DateTime.tryParse(raw.split(' ').first);
  if (t == null) return raw.split(' ').first;
  final diff = DateTime.now().difference(t);
  if (diff.inMinutes < 1) return 'الآن';
  if (diff.inMinutes < 60) return 'قبل ${diff.inMinutes} د';
  if (diff.inHours < 24) return 'قبل ${diff.inHours} س';
  if (diff.inDays < 30) return 'قبل ${diff.inDays} يوم';
  if (diff.inDays < 365) return 'قبل ${(diff.inDays / 30).round()} شهر';
  return 'قبل سنة+';
}

String _fmtBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var i = 0;
  var v = bytes.toDouble();
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(v >= 100 ? 0 : 1)} ${units[i]}';
}

/// شارة معلومة صغيرة (أيقونة + نصّ) — تُستعمل لعرض الاستهلاك/IP/الجهاز
/// على صفوف الجلسات المتّصلة في البحث السريع وInbox.
class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: AppColors.brandSoftBg,
        borderRadius: BorderRadius.circular(R.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 9, color: AppColors.brand),
          const SizedBox(width: 3),
          Text(
            text,
            style: AppType.muted(color: AppColors.brand).copyWith(
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
