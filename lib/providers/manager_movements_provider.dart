import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/dio_client.dart';
import '../models/manager_movement.dart';

/// Pulls the unified movements timeline for a single sub-admin from
/// `/api/admin/managers/:targetId/movements`. autoDispose so it
/// invalidates as soon as the bottom sheet closes; the parent
/// invalidates after add/edit/delete to refresh the list.
final managerMovementsProvider = FutureProvider.family
    .autoDispose<List<ManagerMovement>, int>((ref, targetAdminId) async {
  final dio = ref.read(backendDioProvider);
  try {
    final res = await dio.get('/api/admin/managers/$targetAdminId/movements');
    final data = res.data;
    if (data is! Map || data['success'] != true) return const [];
    final list = (data['movements'] as List? ?? const [])
        .whereType<Map>()
        .map((m) => ManagerMovement.fromJson(Map<String, dynamic>.from(m)))
        .toList(growable: false);
    return list;
  } catch (_) {
    return const [];
  }
});

/// Patch a balance-movement audit row. Note and amount are editable;
/// kind is locked. Amount edits do NOT touch SAS4 — caller must warn
/// the admin that the change is audit-only.
Future<bool> updateBalanceMovement(
  WidgetRef ref,
  int id, {
  String? note,
  double? amount,
}) async {
  final dio = ref.read(backendDioProvider);
  try {
    final res = await dio.patch(
      '/api/admin/manager-movements/$id',
      data: {
        if (note != null) 'note': note,
        if (amount != null) 'amount': amount,
      },
    );
    return res.data is Map && res.data['success'] == true;
  } on DioException {
    return false;
  }
}

/// Hard-delete a balance-movement audit row. Does NOT reverse the
/// SAS4-side state — caller must warn the admin before invoking.
Future<bool> deleteBalanceMovement(WidgetRef ref, int id) async {
  final dio = ref.read(backendDioProvider);
  try {
    final res = await dio.delete('/api/admin/manager-movements/$id');
    return res.data is Map && res.data['success'] == true;
  } on DioException {
    return false;
  }
}
