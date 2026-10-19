import 'dart:async';

// `hide TextDirection`: الحزمة تصدّر نوع intl الذي يحجب نوع dart:ui.
import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import '../../api/ai_api.dart';
import '../../services/ai_assistant_state.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import 'explain_action.dart';

/// Overlay-based helper to show a floating snack from **inside** a modal
/// bottom sheet without breaking the sheet's own layout.
///
/// Why not use `ScaffoldMessenger.of(context).showSnackBar(...)`?
/// A sheet builder returns a widget that becomes a child of the app-root
/// route's Overlay. Calling `ScaffoldMessenger.of(context)` from that
/// widget walks up the tree and finds the app-root messenger — which
/// paints its snackbars on the root Scaffold layer, BELOW the sheet's
/// route. The user never sees the error.
///
/// Wrapping the sheet in a nested `Scaffold` fixes the layer but breaks
/// the layout (Scaffold expands to fill and pushes `DraggableScrollableSheet`
/// to the top).
///
/// This helper sidesteps both problems: it grabs the top-most `Overlay`
/// (which sits ABOVE all routes including sheets) and inserts a
/// self-dismissing entry there.
///
/// Usage — replace:
///   ScaffoldMessenger.of(context).showSnackBar(SnackBar(
///     content: Text(msg), backgroundColor: AppColors.errorFill));
///
/// with:
///   showSheetSnack(context, msg, isError: true);
///
/// [tag] — إشعارٌ واحدٌ حيّ لكلّ وسم: الجديد يُزيل سابقه بدل أن يتراكم
/// فوقه. للأفعال التي تتكرّر بسرعة (النسخ: عشر معلوماتٍ تُنسخ تباعاً
/// كانت ستُكدّس عشرة إشعاراتٍ في المكان نفسه، وظلالها تتراكب). بلا وسم
/// يبقى السلوك القديم كما هو.
///
/// [explain] — «اشرحلي» (المساعد الذكيّ) على إشعار **الخطأ**: الطلب صريحاً،
/// وبدونه يُستنتج من ردّ الخادم المرفوض الذي يعرضه الإشعار
/// ([AiAssistantState.explainFor] — بالنصّ، أو بعمليّةٍ رُفضت للتوّ). الزرّ لا
/// يظهر إلّا إن قال الخادم إنّ المساعد مفتوح، ومعه تطول المدّة إلى ٦ث؛ وإلّا
/// فالإشعار كما كان حرفيّاً. [autoExplain] `false` يمنع الاستنتاج.
Future<void> showSheetSnack(
  BuildContext context,
  String message, {
  bool isError = false,
  Duration duration = const Duration(seconds: 3),
  Object? tag,
  ExplainRequest? explain,
  bool autoExplain = true,
}) async {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  await showSheetSnackOn(
    overlay,
    message,
    isError: isError,
    duration: duration,
    tag: tag,
    explain: explain,
    autoExplain: autoExplain,
  );
}

/// Same floating snack, but the caller supplies the root [OverlayState]
/// directly instead of a `BuildContext`. Use this when the snack must
/// outlive the widget that triggered it — e.g. a follow-up notice shown
/// *after* a sheet pops, where the sheet's own context is already defunct
/// so `Overlay.maybeOf(context)` would throw. Capture the overlay while
/// the context is still mounted, then show on it later.
Future<void> showSheetSnackOn(
  OverlayState overlay,
  String message, {
  bool isError = false,
  Duration duration = const Duration(seconds: 3),
  Object? tag,
  ExplainRequest? explain,
  bool autoExplain = true,
}) async {
  if (!overlay.mounted) return;
  if (tag != null) _liveByTag.remove(tag)?._dismiss();
  final entry = _SheetSnackEntry(
    message: message,
    isError: isError,
    duration: duration,
    overlayState: overlay,
    explain: isError
        ? (explain ?? (autoExplain ? AiAssistantState.explainFor(message) : null))
        : null,
  );
  if (tag != null) _liveByTag[tag] = entry;
  entry._insertInto(overlay);
  await entry.done;
  if (tag != null && identical(_liveByTag[tag], entry)) _liveByTag.remove(tag);
}

/// الإشعار الحيّ لكلّ وسم — انظر `tag` في [showSheetSnack].
final _liveByTag = <Object, _SheetSnackEntry>{};

class _SheetSnackEntry {
  _SheetSnackEntry({
    required this.message,
    required this.isError,
    required this.duration,
    required this.overlayState,
    this.explain,
  }) {
    overlay = OverlayEntry(builder: _build);
    _timer = Timer(duration, _dismiss);
    _shownAt = DateTime.now();
  }

  final String message;
  final bool isError;
  final Duration duration;

  /// الطبقة التي أُدرج فيها — منها تُفتح نافذة «اشرحلي» بعد زوال الإشعار.
  final OverlayState overlayState;

  /// خطأ الخادم الذي يعرضه الإشعار — لـ«اشرحلي». `null` = لا زرّ أبداً.
  final ExplainRequest? explain;
  late final OverlayEntry overlay;
  late Timer _timer;
  late final DateTime _shownAt;

  /// المدّة مُدّت مرّةً حين ظهر الزرّ ([kExplainSnackDuration]).
  bool _extended = false;
  final Completer<void> _completer = Completer<void>();
  Future<void> get done => _completer.future;

  /// في الطبقة الآن — يُضبط عند الإدراج ويُمحى عند الإزالة.
  bool _inserted = false;

  void _insertInto(OverlayState state) {
    state.insert(overlay);
    _inserted = true;
  }

  /// ظهر «اشرحلي» (الحالة قد تصل بعد الإشعار بلحظة) ⇒ لا يزول قبل ٦ث من
  /// ظهوره، ليُقرأ الخطأ ويُضغط الزرّ.
  void _extendForExplain() {
    if (_extended || !_inserted || duration >= kExplainSnackDuration) return;
    _extended = true;
    final left = kExplainSnackDuration - DateTime.now().difference(_shownAt);
    if (left <= Duration.zero) return;
    _timer.cancel();
    _timer = Timer(left, _dismiss);
  }

  void _openExplain() {
    final req = explain;
    final ov = overlayState;
    _dismiss();
    if (req == null || !ov.mounted) return;
    openExplain(ov.context, req);
  }

  void _dismiss() {
    _timer.cancel();
    // ⚠️ «مُدرَج» لا `overlay.mounted`: إشعارٌ أُدرج ولم يُبنَ بعد (وسمٌ
    // يُزيل سابقه في الإطار نفسه) ليس mounted لكنّه في الطبقة — وفحصُ
    // mounted كان يتركه مرسوماً تحت خلفه إلى أن ينقضي مؤقّته.
    if (_inserted) {
      _inserted = false;
      overlay.remove();
    }
    if (!_completer.isCompleted) _completer.complete();
  }

  Widget _build(BuildContext context) {
    final mq = MediaQuery.of(context);
    // ⚠️ فوق لوحة المفاتيح لا تحتها: الطبقة الجذريّة تمتدّ تحت اللوحة،
    // فإشعارٌ على بُعد ٢٤ من القاع وحده يُرسَم خلفها ولا يُرى — وهو
    // بالضبط حين يكتب المدير في شيتٍ ويُخطئ («أدخل المبلغ»). واللوحة
    // مغلقةً `viewInsets` صفر فلا يتغيّر شيء.
    return Positioned(
      left: 16,
      right: 16,
      bottom: mq.padding.bottom + mq.viewInsets.bottom + 24,
      child: SafeArea(
        top: false,
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(R.sm),
          color: isError ? AppColors.errorFill : AppColors.successFill,
          child: InkWell(
            borderRadius: BorderRadius.circular(R.sm),
            onTap: _dismiss,
            child: explain == null
                ? _plain()
                // «اشرحلي» يتبع حالة المساعد: الاستماع يطلبها إن كانت قديمة،
                // والزرّ يظهر متى قال الخادم إنّه مفتوح — وإلّا الإشعار كما كان.
                : ValueListenableBuilder<AiStatus?>(
                    valueListenable: AiAssistantState.gate,
                    builder: (context, s, _) {
                      if (!(s?.canExplain ?? false)) return _plain();
                      WidgetsBinding.instance
                          .addPostFrameCallback((_) => _extendForExplain());
                      return _withExplain(context);
                    },
                  ),
          ),
        ),
      ),
    );
  }

  static const _textStyle = TextStyle(
    color: AppColors.onBrand,
    fontSize: 13, height: 1.35,
    fontWeight: FontWeight.w600,
  );

  Widget get _icon => Icon(
        isError ? Icons.error_outline : Icons.check_circle_outline,
        color: AppColors.onBrand,
        size: 20,
      );

  Widget _plain() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            _icon,
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: _textStyle,
                textDirection: TextDirection.rtl,
              ),
            ),
          ],
        ),
      );

  /// النصّ و«اشرحلي» في سطرٍ واحد إن وسعهما سطران، وإلّا الزرّ تحت النصّ —
  /// فلا تُقصّ رسالة الخطأ لتتّسع للزرّ (٣٢٠ نقطة).
  Widget _withExplain(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final scaler = MediaQuery.textScalerOf(context);
      final label = TextPainter(
        text: TextSpan(text: 'ai.explain'.tr(), style: AppType.bodyBold()),
        textDirection: TextDirection.rtl,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      // الحبّة: حشوة ١٢×٢ + أيقونة ١٤ + فراغ ٤ + حدّ.
      final pill = label.width + Sp.md * 2 + 14 + Sp.xs + 2;
      label.dispose();
      final inlineWidth = c.maxWidth - 16 - Sp.sm - 20 - 10 - Sp.sm - pill;
      var fits = inlineWidth >= 96;
      if (fits) {
        // القياس بالنمط الفعليّ (خطّ التطبيق من الثيم) لا بالخطّ الافتراضيّ.
        final text = TextPainter(
          text: TextSpan(
            text: message,
            style: DefaultTextStyle.of(context).style.merge(_textStyle),
          ),
          textDirection: TextDirection.rtl,
          textScaler: scaler,
          maxLines: 2,
        )..layout(maxWidth: inlineWidth);
        fits = !text.didExceedMaxLines;
        text.dispose();
      }
      if (fits) {
        return Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, Sp.xs, Sp.sm, Sp.xs),
          child: Row(
            children: [
              _icon,
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: _textStyle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textDirection: TextDirection.rtl,
                ),
              ),
              const SizedBox(width: Sp.sm),
              ExplainPill(onTap: _openExplain),
            ],
          ),
        );
      }
      return Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 12, Sp.sm, Sp.xxs),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                _icon,
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    message,
                    style: _textStyle,
                    textDirection: TextDirection.rtl,
                  ),
                ),
              ],
            ),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: ExplainPill(onTap: _openExplain),
            ),
          ],
        ),
      );
    });
  }
}
