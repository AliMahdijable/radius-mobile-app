import 'dart:async';

class SessionExpiredEvent {
  final String? reason;

  const SessionExpiredEvent({this.reason});
}

class SessionEvents {
  SessionEvents._();

  static final StreamController<SessionExpiredEvent> _controller =
      StreamController<SessionExpiredEvent>.broadcast();

  static Stream<SessionExpiredEvent> get stream => _controller.stream;

  static void emitExpired({String? reason}) {
    if (!_controller.isClosed) {
      _controller.add(SessionExpiredEvent(reason: reason));
    }
  }
}
