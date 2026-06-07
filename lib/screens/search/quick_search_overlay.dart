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
        onError: (err) {
          if (kDebugMode) debugPrint('🎙️ error: ${err.errorMsg}');
          if (!mounted) return;
          setState(() => _listening = false);
          // 'language-not-supported' = the Arabic locale isn't installed
          // on the device's recognizer. Tell the user where to get it.
          if (err.errorMsg.contains('language-not-supported') ||
              err.errorMsg.contains('error_language_not_supported')) {
            _showSnack(
              'العربية غير منزّلة. ادخل: Settings → Apps → Google →\n'
              'Voice → Offline speech recognition → نزّل العربية',
            );
          }
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
    // Force Arabic — Android's SpeechRecognizer accepts BCP-47 tags
    // even when locales() doesn't list them, and the device-default
    // fallback (English on most TECNO/MediaTek units) is exactly what
    // we DON'T want. We pass 'ar' (the language-only tag) because that
    // matches whichever Arabic dialect is installed without requiring
    // an exact country code. If Arabic truly isn't available, the
    // recognizer raises an error which our onError clears _listening.
    final locales = await _speech.locales();
    if (kDebugMode) {
      final ids = locales.map((l) => l.localeId).join(', ');
      debugPrint('🎙️ available locales: [$ids]');
    }
    const localeId = 'ar';
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
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const _EmptyHints();
    return FutureBuilder<List<Subscriber>?>(
      future: SubscribersApi.loadAll(),
      builder: (_, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
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
                  const Icon(LucideIcons.searchX,
                      color: AppColors.textLow, size: 32),
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
                padding:
                    const EdgeInsets.fromLTRB(Sp.sm, Sp.sm, Sp.sm, 4),
                child: Text(
                  matches.length > _maxResults
                      ? 'أول $_maxResults من ${matches.length} نتيجة'
                      : '${matches.length} نتيجة',
                  style: AppType.muted(color: AppColors.textLow)
                      .copyWith(fontSize: 10, letterSpacing: 0.4),
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
    final q = raw.toLowerCase().trim();
    final qDigits = raw.replaceAll(RegExp(r'\D'), '');
    final scored = <(int, Subscriber)>[];
    for (final s in all) {
      final score = _scoreOne(s, q, qDigits);
      if (score > 0) scored.add((score, s));
    }
    scored.sort((a, b) => b.$1.compareTo(a.$1));
    return scored.map((e) => e.$2).toList();
  }

  static int _scoreOne(Subscriber s, String q, String qDigits) {
    var score = 0;
    final username = s.username.toLowerCase();
    final fname = s.firstname.trim();
    final lname = s.lastname.trim();
    final full = '$fname $lname'.trim();
    // Username: prefix > contains. Username is usually short so we
    // weight prefix heavily — the admin typing 'ahm' wants ahmed@x.
    if (q.isNotEmpty) {
      if (username == q) {
        score += 100;
      } else if (username.startsWith(q)) {
        score += 60;
      } else if (username.contains(q)) {
        score += 30;
      }
      // Arabic name: contains on either name part.
      if (fname.contains(q) || lname.contains(q)) score += 40;
      if (full.contains(q)) score += 20;
    }
    // Phone: digits-only match against phone OR mobile.
    if (qDigits.isNotEmpty && qDigits.length >= 3) {
      final phoneDigits = (s.phone ?? '').replaceAll(RegExp(r'\D'), '');
      final mobileDigits = (s.mobile ?? '').replaceAll(RegExp(r'\D'), '');
      if (phoneDigits.contains(qDigits) ||
          mobileDigits.contains(qDigits)) {
        score += 45;
      }
    }
    return score;
  }
}

class _EmptyHints extends StatelessWidget {
  const _EmptyHints();

  @override
  Widget build(BuildContext context) {
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
                  color: AppColors.brand.withValues(alpha: 0.7), size: 16),
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
          padding: const EdgeInsets.symmetric(
              horizontal: Sp.sm, vertical: Sp.sm),
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
                      border: Border.all(
                          color: statusColor.withValues(alpha: 0.3)),
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
                          border: Border.all(
                              color: AppColors.surface, width: 1.5),
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
                            style: AppType.label(color: AppColors.textHi)
                                .copyWith(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
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
                            style: AppType.muted(color: statusColor)
                                .copyWith(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
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
                              color:
                                  AppColors.error.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(R.pill),
                              border: Border.all(
                                color: AppColors.error
                                    .withValues(alpha: 0.25),
                              ),
                            ),
                            child: Text(
                              'دين ${formatIQD(sub.debtAbs.round())}',
                              style:
                                  AppType.muted(color: AppColors.error)
                                      .copyWith(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
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
                          const Icon(LucideIcons.phone,
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
                  ],
                ),
              ),
              const Icon(LucideIcons.chevronLeft,
                  color: AppColors.textLow, size: 16),
            ],
          ),
        ),
      ),
    );
  }

  static Color _statusColor(Subscriber s) {
    if (s.isDisabled) return const Color(0xFF94A3B8);
    if (s.isOnline) {
      if (s.isExpired) return const Color(0xFF8B5CF6);
      if (s.isNearExpiry) return const Color(0xFFF59E0B);
      return const Color(0xFF2563EB);
    }
    if (s.isExpired) return AppColors.error;
    if (s.isNearExpiry) return const Color(0xFFF59E0B);
    return const Color(0xFF10B981);
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

