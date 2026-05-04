import 'dart:developer' as dev;

import 'package:dio/dio.dart';

import '../constants/api_constants.dart';
import 'storage_service.dart';

class SessionRefreshResult {
  final String token;
  final String expiresAt;
  final bool refreshed;

  const SessionRefreshResult({
    required this.token,
    required this.expiresAt,
    required this.refreshed,
  });
}

class SessionRefreshService {
  SessionRefreshService._();

  static Future<SessionRefreshResult?>? _ongoingRefresh;

  static Future<SessionRefreshResult?> ensureValidSession(
    StorageService storage, {
    bool forceRefresh = false,
    Duration refreshWindow = const Duration(minutes: 2),
  }) async {
    final token = await storage.getToken();
    final adminId = await storage.getAdminId();
    final expiry = await storage.getTokenExpiry();

    if (token == null || adminId == null) {
      return null;
    }

    final expiryDate = expiry == null ? null : DateTime.tryParse(expiry)?.toUtc();
    final now = DateTime.now().toUtc();
    final shouldRefresh = forceRefresh ||
        expiryDate == null ||
        !expiryDate.isAfter(now.add(refreshWindow));

    if (!shouldRefresh) {
      return SessionRefreshResult(
        token: token,
        expiresAt: expiry!,
        refreshed: false,
      );
    }

    if (_ongoingRefresh != null) {
      return _ongoingRefresh;
    }

    _ongoingRefresh = _refreshSession(storage, adminId);
    try {
      return await _ongoingRefresh;
    } finally {
      _ongoingRefresh = null;
    }
  }

  static Future<SessionRefreshResult?> _refreshSession(
    StorageService storage,
    String adminId,
  ) async {
    try {
      dev.log('Proactive token refresh for adminId: $adminId', name: 'AUTH');
      final dio = Dio(BaseOptions(
        baseUrl: ApiConstants.backendUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        sendTimeout: const Duration(seconds: 10),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ));

      final response = await dio.post(
        ApiConstants.refreshToken,
        data: {'adminId': adminId},
      );
      dio.close();

      if (response.data is! Map || response.data['success'] != true) {
        return null;
      }

      final newToken = response.data['token']?.toString();
      final expiresAt = response.data['expiresAt']?.toString();
      if (newToken == null ||
          newToken.isEmpty ||
          expiresAt == null ||
          expiresAt.isEmpty) {
        return null;
      }

      await storage.saveTokenExpiry(expiresAt);
      // refresh-token يرجّع توكن SAS4 جديد دائماً (لأنه يعيد login بكلمة
      // مرور الأب). للأدمن: token الرئيسي == sas4Token، نحفظه بالاثنين.
      // للموظف: token الرئيسي يبقى JWT (ما نتدخل فيه)، بس نحدّث sas4Token
      // حتى استدعاءات SAS4 المباشرة تستعمل الجديد.
      final isEmployee = await storage.getIsEmployee();
      if (isEmployee) {
        await storage.saveSas4Token(newToken);
      } else {
        await storage.saveToken(newToken);
        await storage.saveSas4Token(newToken);
      }

      // للموظف: refresh-token جدّد توكن SAS4 للأب لكن JWT الموظف هو الـtoken
      // الرئيسي وما يتجدد هنا — نرجع التوكن الحالي للموظف (JWT) كي ما
      // يكسر sessionState/checkAuth، وللأدمن نرجع SAS4 الجديد.
      final returnToken = isEmployee
          ? (await storage.getToken() ?? newToken)
          : newToken;

      return SessionRefreshResult(
        token: returnToken,
        expiresAt: expiresAt,
        refreshed: true,
      );
    } catch (e) {
      dev.log('Session refresh failed: $e', name: 'AUTH');
      return null;
    }
  }
}
