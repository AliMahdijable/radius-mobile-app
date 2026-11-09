import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:rad_mysvcs/api/account_api.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/company_route.dart';
import 'package:rad_mysvcs/api/employee_merged_api.dart';
import 'package:rad_mysvcs/api/employees_api.dart';
import 'package:rad_mysvcs/services/merged_mode.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';

import '../visual_perm/visual_perm_harness.dart';

// ═══════════════════════════════════════════════════════════════════════
// «كل الصفحات» للموظّف — محاكاة (٩ نوفمبر، المالك: «سوي محاكه لوضع الموظفين الي مسنودين لاكثر من صفحه»).
//
// موظّفٌ واحد («ali.m») مربوطٌ بأربع صفحات — كلّ الأسماء تجريبيّة:
//   ألف  — ساس (الأصل، صفحة توكنه الآن) بكلّ الصلاحيّات، والكتابة منها مفتوحة.
//   باء  — ساسٌ بعيد (code:id) بلا مالٍ ولا أجهزة: التقرير الماليّ والأجهزة 403 والرصيد مقنَّع (null).
//   جيم  — ايرث لنك.
//   دال  — معطّلٌ فيها (status unavailable برسالتها) — تُسمّى ولا تُطلب.
// الخادم وهميّ على ApiClient.dio نفسه بمعترضاته الحقيقيّة: يردّ بالمسار + x-company-key، ويصدي المفتاح كالخادم.
// ═══════════════════════════════════════════════════════════════════════

const kA = 'c0000000000a1';
const kB = 'c0000000000b2';
const kC = 'c0000000000c3';
const kD = 'c0000000000d4';

/// توكن الموظّف كما يزرعه visualSetUp.
const empToken = 'visual-token';

const nameA = 'صفحة ألف';
const nameB = 'صفحة باء';
const nameC = 'صفحة جيم';
const nameD = 'صفحة دال';

const stopText = 'عرض كل صفحاتك معاً متوقّف الآن — تنقّل بينها من «صفحاتي»';
const pausedServerText = 'العمليّات على صفحاتك الأخرى من «كل الصفحات» غير مفتوحةٍ بعد — انتقل إلى الصفحة من «صفحاتي» (لم يُنفَّذ شيء)';
const revokedText = 'انتهت جلستك في هذه الصفحات — سجّل الدخول من جديد';

/// صلاحيّاته في صفحته الحاليّة (ألف): كلّ ما تحتاجه الشاشات هنا.
const empKeys = <String, bool>{
  'subscribers.view': true,
  'subscribers.activate': true,
  'subscribers.extend': true,
  'subscribers.edit': true,
  'subscribers.toggle': true,
  'subscribers.pay_debt': true,
  'subscribers.add_debt': true,
  'subscribers.add_credit': true,
  'subscribers.send_whatsapp': true,
  'subscribers.view_activity': true,
  'reports.financial': true,
  'reports.daily_activations': true,
  'devices.view': true,
  'whatsapp.connect': true,
  'whatsapp.send': true,
};

/// موظّفٌ مباشر على ساس (صفحته الحاليّة ألف).
const empScenario = Scenario(
  id: 'EMP_merged',
  title: 'موظّف بأربع صفحات — «كل الصفحات»',
  actor: Actor.elEmployee,
  provider: null,
  keys: empKeys,
);

final empPages = EmployeePageRef.listFrom(const [
  {'employee_id': 11, 'page_id': '2251', 'page_name': nameA, 'primary': true, 'current': true, 'active': true, 'login_username': 'ali.m'},
  {'employee_id': 12, 'page_id': 'jt:6836', 'page_name': nameB, 'active': true, 'login_username': 'ali.m'},
  {'employee_id': 13, 'page_id': 'earthlink:1025', 'page_name': nameC, 'active': true, 'login_username': 'ali.m'},
  {'employee_id': 14, 'page_id': '9001', 'page_name': nameD, 'active': false, 'login_username': 'ali.m'},
]);

/// صلاحيّاته في كلّ صفحة (ردّ الخادم `permissions` — الافتراضيّة + المحفوظة لصفّه فيها، مفاتيح /me نفسها).
/// ألف: كلّ شيء. باء: يرى المشتركين (وصرفياتها) — بلا مالٍ ولا تفعيلات اليوم ولا واتساب ولا أجهزة ولا تسويات ولا سجلّ حركات.
/// جيم: المشتركون والمال والأجهزة وواتساب.
const permsA = <String, bool>{
  ...empKeys,
  'reports.expenses': true,
  'settlements.view': true,
  'devices.deep_check_vpn': true,
  'subscribers.show_password': true,
};
const permsB = <String, bool>{
  'subscribers.view': true,
  'subscribers.view_activity': false,
  'subscribers.show_password': false,
  'subscribers.pay_debt': true,
  'reports.financial': false,
  'reports.daily_activations': false,
  'reports.expenses': true,
  'settlements.view': false,
  'devices.view': false,
  'whatsapp.connect': false,
  'whatsapp.send': false,
};
const permsC = <String, bool>{
  'subscribers.view': true,
  'reports.financial': true,
  'reports.daily_activations': true,
  'devices.view': true,
  'whatsapp.connect': true,
};

Map<String, Object?> companiesBody({bool writes = true, bool writesB = false, bool fewer = false, bool withPerms = true}) => {
      'success': true,
      'routing': true,
      'writes': writes,
      'generated_at': '2026-11-09T01:00:00Z',
      'companies': fewer
          ? const <Object>[]
          : [
              {'key': kA, 'code': 'supernet', 'username': 'admin@alef', 'name': nameA, 'provider': 'sas4', 'color_index': 0,
                'admin_id': '2251', 'ns': 'nsA', 'currency': 'IQD', 'home': true, 'status': 'ok',
                'employee_id': 11, 'current': true, 'primary': true, 'writes': writes, if (withPerms) 'permissions': permsA},
              {'key': kB, 'code': 'jt', 'username': 'admin@baa', 'name': nameB, 'provider': 'sas4', 'color_index': 1,
                'admin_id': 'jt:6836', 'ns': 'nsB', 'currency': 'IQD', 'status': 'ok',
                'employee_id': 12, 'current': false, 'primary': false, 'writes': writesB, if (withPerms) 'permissions': permsB},
              {'key': kC, 'code': 'earthlink', 'username': 'admin@jeem', 'name': nameC, 'provider': 'earthlink', 'color_index': 2,
                'admin_id': 'earthlink:1025', 'ns': 'nsC', 'currency': 'IQD', 'status': 'ok',
                'employee_id': 13, 'current': false, 'primary': false, 'writes': false, if (withPerms) 'permissions': permsC},
              {'key': kD, 'code': 'x', 'username': 'admin@dal', 'name': nameD, 'provider': 'sas4', 'color_index': 3,
                'admin_id': '9001', 'ns': 'nsD', 'status': 'unavailable', 'reason': 'employee_disabled',
                'message': 'حسابك في «$nameD» معطّل — راجع مديرها', 'employee_id': 14, 'writes': false},
            ],
    };

/// ردّ الصفحات وخريطة باء بدلاً — لحالات صلاحيّةٍ بعينها.
Map<String, Object?> companiesWithB(Map<String, bool> pb) {
  final c = companiesBody();
  final list = [for (final e in c['companies']! as List) Map<String, Object?>.from(e as Map)];
  list[1]['permissions'] = pb;
  return {...c, 'companies': list};
}

Map<String, Object?> subRow(int idx, String parent, {String first = 'مشترك', int debt = 0, bool el = false}) => {
      'idx': idx,
      'username': el ? 'el$idx' : 'u$idx',
      'firstname': first,
      'lastname': '$idx',
      'parent_username': parent,
      'profile_name': el ? 'FTTH 35' : 'Gold',
      'remaining_days': 12,
      'expiration': '2026-12-01 00:00:00',
      'enabled': 1,
      'online_status': idx.isOdd ? 1 : 0,
      if (debt != 0) 'notes': '-$debt',
    };

/// صفوف كلّ صفحة — idx 1 في ساسين مختلفين (ألف وباء) ⇒ صفّان.
final pageRows = <String, List<Map<String, Object?>>>{
  kA: [subRow(1, 'admin@alef'), subRow(2, 'admin@alef', debt: 5000), subRow(3, 'admin@alef')],
  kB: [subRow(1, 'admin@baa'), subRow(9, 'admin@baa', debt: 2500)],
  kC: [subRow(21, 'admin@jeem', el: true), subRow(22, 'admin@jeem', el: true, debt: 7000)],
};

ResponseBody json(int status, Object body, {Map<String, List<String>> headers = const {}}) =>
    ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
      ...headers,
    });

/// خادم «كل الصفحات» الوهميّ: صفحات الموظّف، وكلّ طلبٍ موجَّه برأسه، والباقي للخادم المرئيّ (الصفحة الحاليّة بطلبها العاديّ).
class EmpServer implements HttpClientAdapter {
  EmpServer(this.inner);
  final HttpClientAdapter inner;

  /// كلّ طلبٍ وصل (موجَّهاً أو لا).
  final all = <RequestOptions>[];

  /// الموجَّهة وحدها (تحمل x-company-key).
  final routed = <RequestOptions>[];

  /// مفتاح الإيقاف: صفحاته وكلّ موجَّهٍ ⇒ 409 COMPANY_ROUTE_DISABLED.
  bool killSwitch = false;

  /// جلسته انتهت عند وسيط الموظّفين ⇒ 401 بلا صدى.
  bool sessionEnded = false;

  /// ردٌّ موجَّه بلا صدى (وسيطٌ يُسقط الرأس).
  bool dropEcho = false;

  /// الكتابة على صفحته الحاليّة موقوفةٌ بالخادم (لا قفل مسبق إن قال ردّ الصفحات غير ذلك — «فُرضت»).
  bool pausedWrites = false;

  /// ردّ الصفحات (يُبدَّل بالاختبار).
  Map<String, Object?> companies = companiesBody();

  /// قائمة باء ترفض الصلاحيّة (لاختبار تسمية الرفض في القائمة).
  bool listDeniedB = false;

  /// صفحةٌ تردّ 401 SESSION_REQUIRED **بصداها** (رفض الصفحة نفسها — لا جلسته).
  String? sessionRequiredFor;

  /// صفحةٌ تردّ 403 EMPLOYEE_DISABLED (معطّلٌ فيها) — بلا صدى إن [dropEcho].
  String? disabledFor;

  /// رصيد باء مقنَّعٌ (null) بدل رقمه.
  bool maskB = false;

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? rs, Future<void>? cf) async {
    all.add(o);
    final key = o.headers['x-company-key'] as String?;
    final path = o.uri.path;
    if (key == null) {
      // صفحته الحاليّة (ألف) بطلبها العاديّ: صرفياتها
      if (o.method == 'GET' && path == '/api/admin/expenses') {
        return json(200, {
          'success': true,
          'expenses': [
            {'id': 11, 'amount': 15000, 'note': 'إيجار ألف', 'expense_date': '2026-11-05'},
          ],
          'total': 15000,
        });
      }
      if (path == '/api/v2/employee-merged/companies') {
        if (killSwitch) {
          return json(409, {'success': false, 'code': 'COMPANY_ROUTE_DISABLED', 'message': stopText});
        }
        return json(200, companies);
      }
      // صفحته الحاليّة (ألف) بطلبها العاديّ: أجهزتها
      if (o.method == 'GET' && path == '/api/v2/admin/devices') {
        return json(200, {
          'success': true,
          'data': [
            {'id': 501, 'admin_id': '2251', 'name': 'سكتر ألف 1', 'type': 'sector', 'brand': 'ubnt', 'ip': '10.10.1.2'},
          ],
        });
      }
      return inner.fetch(o, rs, cf);
    }
    routed.add(o);
    if (sessionEnded) {
      return json(401, {'success': false, 'code': 'EMPLOYEE_SESSION_REVOKED', 'message': revokedText});
    }
    final h = <String, List<String>>{if (!dropEcho) 'x-company-key': [key]};
    if (sessionRequiredFor == key) {
      return json(401, {'success': false, 'code': 'SESSION_REQUIRED', 'message': 'جلسة «$nameB» تحتاج دخول مديرها'}, headers: h);
    }
    if (disabledFor == key) {
      return json(403, {'success': false, 'code': 'EMPLOYEE_DISABLED', 'message': 'حسابك في هذه الصفحة معطّل — راجع مديرها'},
          headers: h);
    }
    if (killSwitch) {
      return json(409, {'success': false, 'code': 'COMPANY_ROUTE_DISABLED', 'message': stopText}, headers: h);
    }
    final denied = json(403, {'success': false, 'code': 'PERMISSION_DENIED', 'message': 'ليس لديك صلاحيّة'}, headers: h);
    final get = o.method == 'GET';
    if (get && path == '/api/v2/subscribers') {
      if (key == kB && listDeniedB) return denied;
      if (o.queryParameters['page'] != null) {
        return json(200, {'success': true, 'paged': true, 'total': pageRows[key]?.length ?? 0, 'data': const []}, headers: h);
      }
      return json(200, {'success': true, 'data': pageRows[key] ?? const []}, headers: h);
    }
    if (get && RegExp(r'^/api/v2/subscribers/\d+$').hasMatch(path)) {
      return json(200, {'success': true, 'data': {'idx': path.split('/').last}},
          headers: {...h, 'x-company-ref': ['r_${'S' * 22}']});
    }
    if (!get && RegExp(r'^/api/v2/subscribers/\d+/pay-debt$').hasMatch(path)) {
      final cur = key == kA;
      if (!cur || pausedWrites) {
        return json(409, {'success': false, 'code': 'COMPANY_ROUTE_WRITES_PAUSED', 'message': pausedServerText}, headers: h);
      }
      if (o.headers['x-company-ref'] == null) {
        return json(409, {'success': false, 'code': 'COMPANY_REF_REQUIRED', 'message': 'افتح المشترك من جديد (لم يُنفَّذ شيء)'},
            headers: h);
      }
      return json(200, {'success': true, 'message': 'تم التسديد', 'data': {'new_balance': 0}}, headers: h);
    }
    if (get && path == '/api/v2/admin-widgets') {
      // ساس الخادم لا يقنّع رصيد الموظّف (ايرث لنك/فايبر اكس/المُضافة وحدها) — باء يردّ رقماً حقيقيّاً، والتطبيق لا يعرضه بلا
      // reports.financial في خريطتها. [maskB]: خادمٌ يقنّعه (null) كمزوّدٍ يفعل.
      final bal = {kA: 150000, kB: maskB ? null : 77000, kC: 90000}[key];
      return json(200, {'success': true, 'balance': bal, 'points': bal == null ? null : 0}, headers: h);
    }
    if (get && path == '/api/reports/finance') {
      if (key == kB) return denied;
      return json(200, {
        'success': true,
        'data': {
          'kpis': {'activate_cash_sum': key == kA ? 30000 : 12000, 'debt_pay_sum': key == kA ? 5000 : 0},
          'totals': {'total_payments': key == kA ? 35000 : 12000},
          'recentLogs': const [],
        },
      }, headers: h);
    }
    if (get && path == '/api/activities/daily-activations') {
      if (key == kB) return denied;
      return json(200, {'success': true, 'counts': {'activations': 2, 'extensions': 1}, 'data': const []}, headers: h);
    }
    if (get && path.startsWith('/api/whatsapp/connection-status/')) {
      if (key == kB) return denied;
      return json(200, {'success': true, 'connected': key == kA, 'phone': key == kA ? '+9647700000001' : null}, headers: h);
    }
    if (get && path == '/api/v2/admin/devices') {
      if (key == kB) return denied;
      return json(200, {
        'success': true,
        'data': [
          {'id': 702, 'admin_id': 'earthlink:1025', 'name': 'برج جيم', 'type': 'router', 'brand': 'mikrotik', 'ip': '10.30.0.1'},
        ],
      }, headers: h);
    }
    if (get && path == '/api/admin/expenses') {
      // باء: مالكها فتح كتابة الصرفيات الموجَّهة (routed_writes) — والموظّف يبقى للعرض: صفحته الحاليّة وحدها تُكتب من هنا
      return json(200, {
        'success': true,
        'expenses': [
          {'id': 91, 'amount': 7000, 'note': 'كهرباء باء', 'expense_date': '2026-11-05'},
        ],
        'total': 7000,
        'routed_writes': true,
      }, headers: h);
    }
    if (get && path == '/api/v2/settlements/current') {
      return json(200, {'success': true, 'data': {'cash': 1000, 'can_settle': false}}, headers: h);
    }
    if (get && path == '/api/v2/online-users') return json(200, {'success': true, 'data': const []}, headers: h);
    if (get && path == '/api/v2/subscribers-usage') return json(200, {'success': true, 'data': const {}}, headers: h);
    return json(200, {'success': true, 'data': const []}, headers: h);
  }

  @override
  void close({bool force = false}) {}
}

/// عدّاد نداءات توكن الحساب — الموظّف لا حساب له: لا يُسأل ولا يُرسل أبداً.
int accountTokenAsked = 0;

/// يضبط جلسة الموظّف (صفحته الحاليّة ألف) والخادم الوهميّ.
Future<EmpServer> empUp({Map<String, Object?>? companies}) async {
  final inner = await visualSetUp(empScenario);
  PermissionsService.debugSet(isEmployee: true, permissions: empKeys, pages: empPages);
  final srv = EmpServer(inner);
  if (companies != null) srv.companies = companies;
  ApiClient.dio.httpClientAdapter = srv;
  accountTokenAsked = 0;
  AccountApi.tokenSource = ({bool force = false}) async {
    accountTokenAsked++;
    return 'acct-must-not-be-sent';
  };
  MergedMode.reset();
  // الجلب الحقيقيّ (EmployeeMergedApi عبر ApiClient ومعترضاته) — لا بديل
  MergedMode.fetchEmployeeRaw = EmployeeMergedApi.companiesRaw;
  return srv;
}

Future<void> empDown() async {
  MergedMode.reset();
  CompanyRefs.reset();
  await visualTearDown();
}
