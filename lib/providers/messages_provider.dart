import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../core/constants/api_constants.dart';
import '../core/network/dio_client.dart';
import '../core/services/socket_service.dart';
import '../models/message_log_model.dart';
import '../core/services/storage_service.dart';

class BroadcastProgress {
  final int sent;
  final int failed;
  final int total;
  final String? currentUser;
  final bool isActive;
  final bool isPaused;
  final int? pauseSeconds;
  final String event;

  const BroadcastProgress({
    this.sent = 0,
    this.failed = 0,
    this.total = 0,
    this.currentUser,
    this.isActive = false,
    this.isPaused = false,
    this.pauseSeconds,
    this.event = '',
  });
}

class MessagesState {
  final List<MessageLogModel> messages;
  final MessageStats stats;
  final bool isLoading;
  final String? error;
  final int totalMessages;
  final int currentPage;
  final bool hasMore;
  final String? statusFilter;
  final String? typeFilter;
  final BroadcastProgress? broadcast;

  const MessagesState({
    this.messages = const [],
    this.stats = const MessageStats(),
    this.isLoading = false,
    this.error,
    this.totalMessages = 0,
    this.currentPage = 1,
    this.hasMore = true,
    this.statusFilter,
    this.typeFilter,
    this.broadcast,
  });

  MessagesState copyWith({
    List<MessageLogModel>? messages,
    MessageStats? stats,
    bool? isLoading,
    String? error,
    int? totalMessages,
    int? currentPage,
    bool? hasMore,
    String? statusFilter,
    String? typeFilter,
    BroadcastProgress? broadcast,
  }) {
    return MessagesState(
      messages: messages ?? this.messages,
      stats: stats ?? this.stats,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      totalMessages: totalMessages ?? this.totalMessages,
      currentPage: currentPage ?? this.currentPage,
      hasMore: hasMore ?? this.hasMore,
      statusFilter: statusFilter ?? this.statusFilter,
      typeFilter: typeFilter ?? this.typeFilter,
      broadcast: broadcast ?? this.broadcast,
    );
  }
}

class MessagesNotifier extends StateNotifier<MessagesState> {
  final Dio _dio;
  final SocketService _socket;
  final StorageService _storage;
  StreamSubscription? _broadcastSub;

  MessagesNotifier(this._dio, this._socket, this._storage)
      : super(const MessagesState()) {
    _listenBroadcast();
  }

  void _listenBroadcast() {
    _broadcastSub = _socket.broadcastEvents.listen((data) {
      final event = data['event'] as String?;
      switch (event) {
        case 'start':
          state = state.copyWith(
            broadcast: BroadcastProgress(
              total: data['total'] ?? 0,
              isActive: true,
              event: 'start',
            ),
          );
          break;
        case 'progress':
          state = state.copyWith(
            broadcast: BroadcastProgress(
              sent: data['sent'] ?? 0,
              failed: data['failed'] ?? 0,
              total: data['total'] ?? state.broadcast?.total ?? 0,
              currentUser: data['currentUser']?.toString(),
              isActive: true,
              event: 'progress',
            ),
          );
          break;
        case 'batch_wait':
          state = state.copyWith(
            broadcast: BroadcastProgress(
              sent: data['sent'] ?? state.broadcast?.sent ?? 0,
              total: data['total'] ?? state.broadcast?.total ?? 0,
              isActive: true,
              isPaused: true,
              pauseSeconds: data['pauseSeconds'],
              event: 'batch_wait',
            ),
          );
          break;
        case 'complete':
          state = state.copyWith(
            broadcast: BroadcastProgress(
              sent: data['sent'] ?? 0,
              failed: data['failed'] ?? 0,
              total: data['total'] ?? 0,
              isActive: false,
              event: 'complete',
            ),
          );
          break;
      }
    });
  }

  Future<void> loadMessages({bool refresh = false}) async {
    final _adminId = await _storage.getAdminId();
    if (_adminId == null) return;
    final page = refresh ? 1 : state.currentPage;
    if (!refresh && state.isLoading) return;

    state = state.copyWith(isLoading: true, error: null);

    try {
      String url = '${ApiConstants.waMessageLogs}/$_adminId?page=$page&limit=20';
      if (state.statusFilter != null) url += '&status=${state.statusFilter}';
      if (state.typeFilter != null) url += '&type=${state.typeFilter}';

      final response = await _dio.get(url);

      if (response.data['success'] == true) {
        final list = (response.data['messages'] as List? ?? [])
            .map((e) => MessageLogModel.fromJson(e))
            .toList();
        final stats = MessageStats.fromJson(response.data['stats'] ?? {});
        final total = response.data['total'] ?? 0;

        state = state.copyWith(
          messages: refresh ? list : [...state.messages, ...list],
          stats: stats,
          isLoading: false,
          totalMessages: total,
          currentPage: page + 1,
          hasMore: list.length >= 20,
        );
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'فشل تحميل الرسائل');
    }
  }

  void setFilters({String? status, String? type}) {
    state = state.copyWith(
      statusFilter: status,
      typeFilter: type,
      currentPage: 1,
      messages: [],
      hasMore: true,
    );
    loadMessages(refresh: true);
  }

  Future<bool> retryMessage(int messageId, {String source = 'queue'}) async {
    final _adminId = await _storage.getAdminId();
    if (_adminId == null) return false;
    try {
      final response = await _dio.post(ApiConstants.waRetryMessage, data: {
        'adminId': _adminId,
        'messageId': messageId,
        'source': source,
      });
      return response.data['success'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> startBroadcast({
    required String message,
    required String type,
    List<String>? targetUsernames,
  }) async {
    final _adminId = await _storage.getAdminId();
    if (_adminId == null) return false;
    try {
      final data = <String, dynamic>{
        'adminId': _adminId,
        'message': message,
        'type': type,
      };
      if (targetUsernames != null && targetUsernames.isNotEmpty) {
        data['targetUsernames'] = targetUsernames;
      }
      final response = await _dio.post(ApiConstants.waBroadcast, data: data);
      return response.data['success'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> cancelBroadcast() async {
    final _adminId = await _storage.getAdminId();
    if (_adminId == null) return false;
    try {
      await _dio.post(ApiConstants.waBroadcastCancel, data: {
        'adminId': _adminId,
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() {
    _broadcastSub?.cancel();
    super.dispose();
  }
}

final messagesProvider =
    StateNotifierProvider<MessagesNotifier, MessagesState>((ref) {
  return MessagesNotifier(
    ref.read(backendDioProvider),
    ref.read(socketServiceProvider),
    ref.read(storageServiceProvider),
  );
});
