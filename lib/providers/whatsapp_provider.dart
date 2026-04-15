import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../core/constants/api_constants.dart';
import '../core/network/dio_client.dart';
import '../core/services/socket_service.dart';
import '../core/services/storage_service.dart';
import '../models/whatsapp_status_model.dart';

class WhatsAppState {
  final WhatsAppStatusModel status;
  final String? qrCode;
  final bool isConnecting;
  final String? error;

  const WhatsAppState({
    this.status = const WhatsAppStatusModel(),
    this.qrCode,
    this.isConnecting = false,
    this.error,
  });

  WhatsAppState copyWith({
    WhatsAppStatusModel? status,
    String? qrCode,
    bool? isConnecting,
    String? error,
  }) {
    return WhatsAppState(
      status: status ?? this.status,
      qrCode: qrCode ?? this.qrCode,
      isConnecting: isConnecting ?? this.isConnecting,
      error: error,
    );
  }
}

class WhatsAppNotifier extends StateNotifier<WhatsAppState> {
  final Dio _dio;
  final SocketService _socket;
  final StorageService _storage;
  StreamSubscription? _statusSub;
  StreamSubscription? _qrSub;

  WhatsAppNotifier(this._dio, this._socket, this._storage)
      : super(const WhatsAppState()) {
    _listenToSocket();
  }

  void _listenToSocket() {
    _statusSub = _socket.whatsappStatus.listen((data) {
      final event = data['event'] as String?;
      if (event == 'connected') {
        state = state.copyWith(
          status: WhatsAppStatusModel(
            connected: true,
            phone: data['phone']?.toString(),
            pushname: data['pushname']?.toString(),
            platform: data['platform']?.toString(),
          ),
          isConnecting: false,
          qrCode: null,
        );
      } else if (event == 'disconnected') {
        state = state.copyWith(
          status: const WhatsAppStatusModel(connected: false),
          isConnecting: false,
        );
      } else if (event == 'error') {
        state = state.copyWith(
          error: data['message']?.toString(),
          isConnecting: false,
        );
      }
    });

    _qrSub = _socket.qrCode.listen((data) {
      state = state.copyWith(
        qrCode: data['qrCode']?.toString(),
        isConnecting: true,
      );
    });
  }

  Future<String?> _getAdminId() => _storage.getAdminId();
  Future<String?> _getUsername() => _storage.getAdminUsername();

  Future<void> fetchStatus() async {
    final adminId = await _getAdminId();
    if (adminId == null) return;
    try {
      final response = await _dio.get(
        '${ApiConstants.waConnectionStatus}/$adminId?live=true',
      );
      if (response.data['success'] == true) {
        final s = WhatsAppStatusModel.fromJson(response.data);
        state = state.copyWith(
          status: s,
          qrCode: s.connected ? null : state.qrCode,
        );
      }
    } catch (_) {}
  }

  Future<void> startSession() async {
    final adminId = await _getAdminId();
    final username = await _getUsername();
    if (adminId == null) return;
    state = state.copyWith(isConnecting: true, error: null, qrCode: null);
    try {
      await _dio.post(ApiConstants.waStartSession, data: {
        'adminId': adminId,
        'adminUsername': username ?? '',
      });
    } catch (e) {
      state = state.copyWith(isConnecting: false, error: 'فشل بدء الجلسة');
    }
  }

  Future<void> reconnect() async {
    final adminId = await _getAdminId();
    final username = await _getUsername();
    if (adminId == null) return;
    state = state.copyWith(isConnecting: true, error: null);
    try {
      await _dio.post(ApiConstants.waReconnect, data: {
        'adminId': adminId,
        'adminUsername': username ?? '',
      });
    } catch (e) {
      state = state.copyWith(isConnecting: false, error: 'فشل إعادة الاتصال');
    }
  }

  Future<void> disconnect() async {
    final adminId = await _getAdminId();
    if (adminId == null) return;
    try {
      await _dio.post(ApiConstants.waDisconnect, data: {
        'adminId': adminId,
      });
      state = state.copyWith(
        status: const WhatsAppStatusModel(connected: false),
        qrCode: null,
      );
    } catch (e) {
      state = state.copyWith(error: 'فشل قطع الاتصال');
    }
  }

  Future<bool> sendMessage(String to, String message) async {
    final adminId = await _getAdminId();
    if (adminId == null) return false;
    try {
      final response = await _dio.post(ApiConstants.waSendMessage, data: {
        'adminId': adminId,
        'to': to,
        'message': message,
      });
      return response.data['success'] == true;
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    _qrSub?.cancel();
    super.dispose();
  }
}

final whatsappProvider =
    StateNotifierProvider<WhatsAppNotifier, WhatsAppState>((ref) {
  return WhatsAppNotifier(
    ref.read(backendDioProvider),
    ref.read(socketServiceProvider),
    ref.read(storageServiceProvider),
  );
});
