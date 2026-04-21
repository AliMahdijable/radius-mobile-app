import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants/api_constants.dart';
import '../core/network/dio_client.dart';

class AnnouncementModel {
  final int id;
  final String title;
  final String body;
  final String? actionUrl;
  final String? actionLabel;

  const AnnouncementModel({
    required this.id,
    required this.title,
    required this.body,
    this.actionUrl,
    this.actionLabel,
  });

  factory AnnouncementModel.fromJson(Map<String, dynamic> json) {
    return AnnouncementModel(
      id: json['id'] is int ? json['id'] : int.tryParse(json['id']?.toString() ?? '0') ?? 0,
      title: (json['title'] ?? '').toString(),
      body: (json['body'] ?? '').toString(),
      actionUrl: (json['action_url']?.toString().isEmpty ?? true) ? null : json['action_url'].toString(),
      actionLabel: (json['action_label']?.toString().isEmpty ?? true) ? null : json['action_label'].toString(),
    );
  }
}

class AnnouncementState {
  final AnnouncementModel? pending;
  final bool isLoading;

  const AnnouncementState({this.pending, this.isLoading = false});

  AnnouncementState copyWith({AnnouncementModel? pending, bool? isLoading, bool clearPending = false}) {
    return AnnouncementState(
      pending: clearPending ? null : (pending ?? this.pending),
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class AnnouncementNotifier extends StateNotifier<AnnouncementState> {
  final Dio _backendDio;
  static const String _prefsKey = 'announcement_last_seen_id';

  AnnouncementNotifier(this._backendDio) : super(const AnnouncementState());

  /// Fetches the current active announcement. If it's newer than what the
  /// user has already dismissed (per SharedPreferences), expose it in state
  /// so the UI can show the modal.
  Future<void> checkForPending() async {
    if (state.isLoading) return;
    state = state.copyWith(isLoading: true);
    try {
      final res = await _backendDio.get(ApiConstants.announcementsCurrent);
      final data = res.data;
      if (data is! Map || data['success'] != true) {
        state = state.copyWith(isLoading: false, clearPending: true);
        return;
      }
      final payload = data['announcement'];
      if (payload is! Map) {
        state = state.copyWith(isLoading: false, clearPending: true);
        return;
      }
      final ann = AnnouncementModel.fromJson(Map<String, dynamic>.from(payload));
      final prefs = await SharedPreferences.getInstance();
      final lastSeen = prefs.getInt(_prefsKey) ?? 0;
      if (ann.id > lastSeen) {
        state = AnnouncementState(pending: ann, isLoading: false);
      } else {
        state = state.copyWith(isLoading: false, clearPending: true);
      }
    } catch (_) {
      state = state.copyWith(isLoading: false);
    }
  }

  /// Called when the user dismisses the popup. Persists the id so the
  /// same announcement doesn't re-appear on next launch, and reports
  /// the view to the server so super-admin can see who saw it.
  Future<void> markSeen() async {
    final current = state.pending;
    if (current == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsKey, current.id);
    state = state.copyWith(clearPending: true);
    // fire-and-forget report — a missed report just means this admin
    // won't appear in the views list, not a data corruption.
    _reportView(current.id);
  }

  Future<void> _reportView(int id) async {
    try {
      await _backendDio.post('/api/announcements/$id/seen');
    } catch (_) { /* ignore */ }
  }
}

final announcementProvider =
    StateNotifierProvider<AnnouncementNotifier, AnnouncementState>((ref) {
  return AnnouncementNotifier(ref.read(backendDioProvider));
});
