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
Future<void> showSheetSnack(
  BuildContext context,
  String message, {
  bool isError = false,
  Duration duration = const Duration(seconds: 3),
}) async {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  final entry = _SheetSnackEntry(
    message: message,
    isError: isError,
    duration: duration,
  );
  overlay.insert(entry.overlay);
  await entry.done;
}

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

  void _dismiss() {
    _timer.cancel();
    if (overlay.mounted) overlay.remove();
    if (!_completer.isCompleted) _completer.complete();
  }

  Widget _build(BuildContext context) {
    final safeBottom = MediaQuery.of(context).padding.bottom;
    return Positioned(
      left: 16,
      right: 16,
      bottom: safeBottom + 24,
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
                        fontSize: 13,
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
