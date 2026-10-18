import 'dart:async';

import 'package:flutter/material.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';

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
Future<void> showSheetSnack(
  BuildContext context,
  String message, {
  bool isError = false,
  Duration duration = const Duration(seconds: 3),
  Object? tag,
}) async {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  await showSheetSnackOn(
    overlay,
    message,
    isError: isError,
    duration: duration,
    tag: tag,
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
}) async {
  if (!overlay.mounted) return;
  if (tag != null) _liveByTag.remove(tag)?._dismiss();
  final entry = _SheetSnackEntry(
    message: message,
    isError: isError,
    duration: duration,
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
  }) {
    overlay = OverlayEntry(builder: _build);
    _timer = Timer(duration, _dismiss);
  }

  final String message;
  final bool isError;
  final Duration duration;
  late final OverlayEntry overlay;
  late final Timer _timer;
  final Completer<void> _completer = Completer<void>();
  Future<void> get done => _completer.future;

  /// في الطبقة الآن — يُضبط عند الإدراج ويُمحى عند الإزالة.
  bool _inserted = false;

  void _insertInto(OverlayState state) {
    state.insert(overlay);
    _inserted = true;
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
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(
                    isError ? Icons.error_outline : Icons.check_circle_outline,
                    color: AppColors.onBrand,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      message,
                      style: const TextStyle(
                        color: AppColors.onBrand,
                        fontSize: 13, height: 1.35,
                        fontWeight: FontWeight.w600,
                      ),
                      textDirection: TextDirection.rtl,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
