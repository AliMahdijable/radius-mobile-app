import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'company_route.dart';

/// «كل الصفحات» للموظّف (٩ نوفمبر — المالك: «الموظف… يشوف كل الصفحات مثل المدير… قابل يتنقل بين الصفحات»): صفحاته معاً —
/// `GET /api/v2/employee-merged/companies` بتوكنه هو (ApiClient — لا توكن حساب)، بشكل ردّ «كل الشركات» للمالك
/// (`/api/account/merged/companies`) + لكلّ صفحة employee_id/current/primary/writes. أقلّ من صفحتين ⇒ companies:[].
class EmployeeMergedApi {
  EmployeeMergedApi._();

  static const path = '/api/v2/employee-merged/companies';

  /// نصّ مفتاح الإيقاف إن لم يرسل الخادم رسالته.
  static const stoppedText = 'عرض كل صفحاتك معاً متوقّف الآن — تنقّل بينها من «صفحاتي»';

  /// الردّ كما وصل (200)، أو حكمٌ قاطع بلا صفحات بشكل الردّ نفسه:
  ///  • 409 COMPANY_ROUTE_DISABLED (مفتاح الإيقاف) ⇒ `{routing:false, stopped:true, message}` — يعود لصفحته بالرسالة؛
  ///  • 403 EMPLOYEE_ONLY (ليس موظّفاً) أو أيّ رفضٍ صريحٍ آخر ⇒ `{routing:false}`.
  /// null = تعذّرٌ عابر (503 TRY_LATER، الشبكة) ⇒ يبقى آخر ما عُرف.
  static Future<Map<String, dynamic>?> companiesRaw() async {
    try {
      // المفتوحة صراحةً: لا يأخذ وجهة قسمٍ مفتوح ولا نطاقاً موجَّهاً
      final r = await CompanyRoute.runOpen(() => ApiClient.dio.get<Map<String, dynamic>>(path));
      final b = r.data;
      final status = r.statusCode ?? 0;
      if (status == 200 && b != null && b['success'] != false) return b;
      final code = b?['code'];
      if (status == 409 && code == CompanyRouteCodes.disabled) {
        final m = '${b?['message'] ?? ''}'.trim();
        return {
          'routing': false,
          'writes': false,
          'companies': const <Object>[],
          'stopped': true,
          'message': m.isEmpty ? stoppedText : m,
        };
      }
      if (status == 503 || status == 429 || status == 0) return null;
      if (status == 401) return null; // جلسته انتهت — المعترض يطرده بسببه، ولا يُمحى ما عُرف قبله هنا
      return const {'routing': false, 'writes': false, 'companies': <Object>[]};
    } on DioException catch (e) {
      if (kDebugMode) debugPrint('🟡 employee-merged companies: ${e.type}');
      return null;
    } catch (e) {
      if (kDebugMode) debugPrint('🟡 employee-merged companies: $e');
      return null;
    }
  }
}
