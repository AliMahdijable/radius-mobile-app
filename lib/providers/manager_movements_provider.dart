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
