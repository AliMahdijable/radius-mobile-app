import 'package:flutter/material.dart';

/// Wraps modal-bottom-sheet content so SnackBars raised from inside the
/// sheet render **above** it instead of behind.
///
/// Why this exists — without this wrapper, calling
///   `ScaffoldMessenger.of(context).showSnackBar(...)`
/// from inside a sheet walks up the widget tree and finds the app-root
/// `ScaffoldMessenger` (registered by `MaterialApp`). That messenger's
/// overlay sits BELOW the sheet's route in the navigator, so any error
/// snackbar appears behind the sheet and is invisible to the user.
///
/// [SheetScaffold] introduces a nested `ScaffoldMessenger` + `Scaffold`
/// scoped to the sheet route. Descendants that look up
/// `ScaffoldMessenger.of(context)` receive this local one, and its
/// snackbars stack on top of the sheet content.
///
/// Usage:
/// ```dart
/// showModalBottomSheet(
///   context: context,
///   backgroundColor: Colors.transparent,
///   isScrollControlled: true,
///   builder: (_) => const SheetScaffold(child: MyActionSheet()),
/// );
/// ```
///
/// The Scaffold has a transparent background so it doesn't paint over
/// the sheet's own rounded container. `resizeToAvoidBottomInset:false`
/// because sheets already handle keyboard insets themselves via
/// `MediaQuery.viewInsets`.
class SheetScaffold extends StatelessWidget {
  const SheetScaffold({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ScaffoldMessenger(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        resizeToAvoidBottomInset: false,
        body: child,
      ),
    );
  }
}
