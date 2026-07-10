import '../../../services/auth_storage.dart';

/// جالب IDs الـscope للتقارير — **فقط المدير المسجّل دخول**.
///
/// 2026-07-10: كنّا نُضمِّن المدراء الفرعيين لكن المستخدم صرّح أن هذا
/// خطأ — لأدمن super يرى الجميع، والمقصود بالتقارير "حركاتي أنا"
/// وليس "أنا + تحتاني". فالسلوك الآن: **adminId فقط**.
///
/// لو احتجنا لاحقاً "أنا + الفرعيين" نضيف دالة منفصلة `loadScopeWithSubs()`
/// وwidget toggle في كل شاشة.
///
/// يرجع قائمة فيها adminId واحد فقط، أو فارغة لو غير متوفّر (يخلّي الـUI
/// يعرض حالة خطأ صادقة).
Future<List<String>> loadScopeUserIds() async {
  final adminId = await AuthStorage.readAdminId();
  if (adminId == null || adminId.isEmpty) return const [];
  return [adminId];
}
