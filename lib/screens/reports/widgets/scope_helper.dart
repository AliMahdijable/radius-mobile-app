import '../../../api/managers_api.dart';
import '../../../services/auth_storage.dart';

/// جالب IDs الـscope: المدير الحالي + كل مدراءه الفرعيين.
///
/// يُستعمل كفلتر `user_ids` على تقارير الـactivity_logs (المالي/التفعيلات/…).
/// بدونه الـbackend يرجع كل المدراء في النظام — لا يليق للمدير العادي.
///
/// السلوك:
/// * لو أخفق جلب أي منهما → يرجع بس adminId (كحدّ أدنى — أفضل من فارغ).
/// * لو adminId نفسه غير متوفّر → يرجع فاضي (يخلّي الـUI يعرض حالة خطأ صادقة).
///
/// نتائج مخبأة في-الذاكرة داخل الجلسة (submanagers لا تتغيّر كثيراً).
Future<List<String>> loadScopeUserIds() async {
  final adminId = await AuthStorage.readAdminId();
  if (adminId == null || adminId.isEmpty) return const [];

  final ids = <String>{adminId};
  try {
    final subs = await ManagersApi.lite();
    if (subs != null) {
      for (final m in subs) {
        ids.add(m.id.toString());
      }
    }
  } catch (_) {
    // نتحمّل الفشل — نرجع بس adminId
  }
  return ids.toList();
}
