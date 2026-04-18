import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../constants/api_constants.dart';

final socketServiceProvider = Provider<SocketService>((ref) {
  return SocketService();
});

class SocketService {
  io.Socket? _socket;
  String? _adminId;
  bool _isConnected = false;

  final _whatsappStatusController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _qrCodeController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _broadcastController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _connectionEventController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _appNotificationController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get whatsappStatus =>
      _whatsappStatusController.stream;
  Stream<Map<String, dynamic>> get qrCode => _qrCodeController.stream;
  Stream<Map<String, dynamic>> get broadcastEvents =>
      _broadcastController.stream;
  Stream<Map<String, dynamic>> get connectionEvents =>
      _connectionEventController.stream;
  Stream<Map<String, dynamic>> get appNotifications =>
      _appNotificationController.stream;

  bool get isConnected => _isConnected;

  void connect(String adminId) {
    _adminId = adminId;

    _socket = io.io(
      ApiConstants.socketUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .enableReconnection()
          .setReconnectionDelay(1000)
          .setReconnectionDelayMax(5000)
          .setReconnectionAttempts(999999)
          .setTimeout(20000)
          .build(),
    );

    _socket!.onConnect((_) {
      _isConnected = true;
      _socket!.emit('join-admin-room', adminId);
      _connectionEventController.add({'event': 'socket_connected'});
    });

    _socket!.onReconnect((_) {
      _socket!.emit('join-admin-room', adminId);
      _connectionEventController.add({'event': 'socket_reconnected'});
    });

    _socket!.onDisconnect((_) {
      _isConnected = false;
      _connectionEventController.add({'event': 'socket_disconnected'});
    });

    _socket!.on('admin-room-joined', (data) {
      _connectionEventController.add({
        'event': 'room_joined',
        'data': data,
      });
    });

    // WhatsApp events
    _socket!.on('qr-code', (data) {
      _qrCodeController.add(Map<String, dynamic>.from(data));
    });

    _socket!.on('connected', (data) {
      _whatsappStatusController.add({
        'event': 'connected',
        ...Map<String, dynamic>.from(data),
      });
    });

    _socket!.on('disconnected', (data) {
      _whatsappStatusController.add({
        'event': 'disconnected',
        ...Map<String, dynamic>.from(data),
      });
    });

    _socket!.on('connection-error', (data) {
      _whatsappStatusController.add({
        'event': 'error',
        ...Map<String, dynamic>.from(data),
      });
    });

    // Broadcast events
    _socket!.on('broadcast-start', (data) {
      _broadcastController.add({
        'event': 'start',
        ...Map<String, dynamic>.from(data),
      });
    });

    _socket!.on('broadcast-progress', (data) {
      _broadcastController.add({
        'event': 'progress',
        ...Map<String, dynamic>.from(data),
      });
    });

    _socket!.on('broadcast-batch-wait', (data) {
      _broadcastController.add({
        'event': 'batch_wait',
        ...Map<String, dynamic>.from(data),
      });
    });

    _socket!.on('broadcast-complete', (data) {
      _broadcastController.add({
        'event': 'complete',
        ...Map<String, dynamic>.from(data),
      });
    });

    _socket!.on('app-notification', (data) {
      _appNotificationController.add(Map<String, dynamic>.from(data));
    });

    _socket!.connect();
  }

  void disconnect() {
    if (_adminId != null && _socket != null) {
      _socket!.emit('leave-admin-room', _adminId);
    }
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    _isConnected = false;
  }

  void dispose() {
    disconnect();
    _whatsappStatusController.close();
    _qrCodeController.close();
    _broadcastController.close();
    _connectionEventController.close();
    _appNotificationController.close();
  }
}
