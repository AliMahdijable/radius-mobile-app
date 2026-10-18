import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/el_card_order_gate.dart';
import 'package:rad_mysvcs/services/employee_session.dart';

import 'sim_el/sim_harness.dart';

/// جلسة موظّفٍ أنهاها الخادم ⇒ سببه لا «انتهت الجلسة».
///
/// الخادم (05d47d3، ١٨ أكتوبر) يطرد الموظّف المعطَّل أو المحذوف فوراً بدل أن يبقى
/// ٢٤ ساعة: كلّ طلبٍ منه 401 `{code, message}`. قبل الإصلاح كان المعترض يحفظ
/// رسالة `SESSION_SUPERSEDED` وحدها، فالمعطَّل يُطرد بـ«انتهت الجلسة» العامّة ولا
/// يعرف السبب إلّا حين يحاول الدخول ثانيةً.
void main() {
  late SimServer server;
  const path = '/api/v2/subscribers';

  setUpAll(simSetUpAll);

  setUp(() async {
    // جلسة موظّف (التجديد مرفوضٌ له ⇒ المعترض يمسح ويطرد).
    server = await simSetUp(secure: {'auth.admin_id': '2251', 'auth.is_employee': '1'});
    // يبدأ كلّ اختبارٍ بلا سببٍ معلّق (ما يفعله أيّ دخولٍ جديد).
    await EmployeeSession.clear(newSession: true);
  });

  Future<int> kick(Map<String, Object?> body) async {
    server.reply('GET', path, 401, body);
    final before = authExpiredSignal.value;
    final r = await ApiClient.dio.get<Object?>(path);
    expect(r.statusCode, 401);
    return authExpiredSignal.value - before;
  }

  test('🚨 عطّله المدير (EMPLOYEE_DISABLED): نصّ الخادم يُحفظ للطرد', () async {
    final kicked = await kick({
      'success': false,
      'code': 'EMPLOYEE_DISABLED',
      'message': 'حساب الموظف معطّل — راجع المدير',
    });
    expect(kicked, 1, reason: 'طُرد');
    expect(EmployeeSession.kickMessage, 'حساب الموظف معطّل — راجع المدير');
  });

  test('🚨 حُذف أو تغيّر مديره (EMPLOYEE_SESSION_REVOKED)', () async {
    await kick({
      'success': false,
      'code': 'EMPLOYEE_SESSION_REVOKED',
      'message': 'انتهت جلسة الموظف — سجّل الدخول من جديد',
    });
    expect(EmployeeSession.kickMessage, 'انتهت جلسة الموظف — سجّل الدخول من جديد');
  });

  test('دخولٌ من جهازٍ آخر (SESSION_SUPERSEDED) كما كان', () async {
    await kick({
      'success': false,
      'code': 'SESSION_SUPERSEDED',
      'message': 'تم الدخول بهذا الحساب من جهازٍ آخر — سجّل الدخول من جديد',
    });
    expect(EmployeeSession.kickMessage,
        'تم الدخول بهذا الحساب من جهازٍ آخر — سجّل الدخول من جديد');
  });

  test('بلا رسالة: نصّ الرمز نفسه — لا «جهازٌ آخر» لموظّفٍ معطَّل', () async {
    await kick({'success': false, 'code': 'EMPLOYEE_DISABLED'});
    expect(EmployeeSession.kickMessage, 'حساب الموظف معطّل — راجع المدير');
    await EmployeeSession.clear(newSession: true);
    await kick({'success': false, 'code': 'SESSION_SUPERSEDED', 'message': ' '});
    expect(EmployeeSession.kickMessage, EmployeeSession.supersededMessage);
  });

  test('401 بلا رمز (انتهاءٌ عاديّ): لا سبب — «انتهت الجلسة» كما كان', () async {
    final kicked = await kick({'success': false, 'message': 'Unauthorized'});
    expect(kicked, 1);
    expect(EmployeeSession.kickMessage, isNull);
  });

  test('الطرد يمسح حال «طلب الكارتات» مع بقيّة الجلسة', () async {
    ElCardOrderGate.debugSet(true);
    await kick({'success': false, 'code': 'EMPLOYEE_DISABLED'});
    expect(ElCardOrderGate.open.value, isNull);
  });
}
