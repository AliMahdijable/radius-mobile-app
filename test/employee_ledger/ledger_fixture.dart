import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// ردود «حركات الموظف» التجريبيّة (بعقد server/employeeLedger.js) وخادمٌ وهميّ على ApiClient.dio — للاختبارات واللقطات.
/// بياناتٌ مصطنعة وحدها.

Map<String, dynamic> ledgerAccountJson() => {
      'feature_enabled': true,
      'is_manager': true,
      'installed': true,
      'employee': {'id': 7, 'username': 'emp1', 'name': 'أحمد'},
      'owed': 100000,
      'loans_total': 400000,
      'owes_total': 500000,
      'due_pending': 25000,
      'balance': -475000,
      'loans': [
        {'id': 1, 'principal': 600000, 'installment': 50000, 'remaining': 400000, 'note': null},
      ],
      'salary': {
        'amount': 500000,
        'cycle': 'monthly',
        'pay_day': 28,
        'pay_day_label': null,
        'comp_mode': 'salary',
        'configured': true,
        'due_count': 1,
        'lapsed': 0,
        'next_due': {'key': '2026-11', 'label': 'تشرين الثاني 2026', 'due_date': '2026-11-28'},
      },
      'movements': [
        {
          'id': 11,
          'kind': 'advance',
          'label': 'سلفة',
          'amount': 100000,
          'source': 'hand',
          'note': 'عيد',
          'date': '2026-11-10',
          'status': 'active',
          'loan_id': null,
          'payslip_id': null,
          'created_by': 'admin',
          'by_employee': null,
        },
        {
          'id': 12,
          'kind': 'bonus',
          'label': 'مكافأة',
          'amount': 25000,
          'source': null,
          'note': null,
          'date': '2026-11-09',
          'status': 'active',
          'created_by': 'cashier',
          'by_employee': {'id': 9, 'username': 'cashier'},
        },
        {
          'id': 13,
          'kind': 'deduction',
          'label': 'خصم',
          'amount': 5000,
          'source': null,
          'note': 'تأخّر',
          'date': '2026-11-08',
          'status': 'voided',
          'void': {'at': '2026-11-08T10:00:00.000Z', 'by': 'admin', 'reason': 'سُجّلت خطأً'},
        },
      ],
      'movements_total': 3,
      'payslips': [
        {
          'id': 3,
          'number': 2,
          'status': 'paid',
          'pay_date': '2026-10-28',
          'salary_sum': 500000,
          'commission_sum': 0,
          'commission_ops': 0,
          'bonus_sum': 0,
          'deduction_sum': 0,
          'gross': 500000,
          'recover_sum': 100000,
          'installment_sum': 50000,
          'net': 350000,
          'source': 'box',
          'expense_id': 90,
          'periods': [
            {'key': '2026-10', 'label': 'تشرين الأوّل 2026', 'amount': 500000},
          ],
          'note': null,
        },
        {
          'id': 2,
          'number': 1,
          'status': 'voided',
          'pay_date': '2026-10-01',
          'gross': 500000,
          'recover_sum': 0,
          'installment_sum': 0,
          'net': 500000,
          'source': 'box',
          'periods': [],
          'void': {'reason': 'خطأ'},
        },
      ],
      'payslips_total': 2,
    };

Map<String, dynamic> ledgerPreviewJson() => {
      'employee': {'id': 7, 'username': 'emp1', 'name': 'أحمد'},
      'salary': {'amount': 500000, 'cycle': 'monthly', 'pay_day': 28, 'comp_mode': 'salary', 'configured': true},
      'periods': [
        {'key': '2026-11', 'label': 'تشرين الثاني 2026', 'due_date': '2026-11-28', 'due': true, 'amount': 500000, 'selected': true},
      ],
      'lapsed': 0,
      'salary_sum': 500000,
      'commission': {'enabled': false, 'ops': 0, 'sum': 0, 'unavailable': false},
      'bonuses': [
        {'id': 12, 'kind': 'bonus', 'label': 'مكافأة', 'amount': 25000, 'status': 'active'},
      ],
      'deductions': [],
      'bonus_sum': 25000,
      'deduction_sum': 0,
      'owed': 100000,
      'loans': [
        {'id': 1, 'principal': 600000, 'installment': 50000, 'remaining': 400000, 'take': 50000},
      ],
      'gross': 525000,
      'recover': 100000,
      'installment_sum': 50000,
      'net': 375000,
      'can_pay': true,
      'problem': null,
      'cut': {'ledger_id': 42, 'comm_to': null},
      'expected': {'gross': 525000, 'net': 375000},
    };

Map<String, dynamic> ledgerLimitsStatusJson() => {
      'employee': {'id': 7, 'username': 'emp1', 'name': 'أحمد'},
      'feature_enabled': true,
      'enforcement_off': false,
      'installed': true,
      'limits': {'debt_cap': 200000, 'cash_cap': 500000, 'profit_per_op': 5000},
      'started': true,
      'period': {'start_at': '2026-11-09T05:00:00.000Z'},
      'cash_in': 350000,
      'debt_out': 120000,
      'open_debt': 90000,
      'holds': {'count': 0, 'cash': 0, 'debt': 0},
      'cash_used': 350000,
      'debt_used': 90000,
      'cash_remaining': 150000,
      'debt_remaining': 110000,
      'cash_blocked': false,
      'debt_blocked': false,
      'ops_count': 4,
      'profit': 20000,
      'breakdown': {
        'cash_activations': {'sum': 280000, 'count': 8},
        'debt_payments': {'sum': 50000, 'count': 2},
        'sales_cash': {'sum': 20000, 'count': 1},
      },
      'holds_list': [],
      'settlements': [],
    };

class LedgerDiskLoader extends AssetLoader {
  const LedgerDiskLoader();
  @override
  Future<Map<String, dynamic>?> load(String path, Locale locale) =>
      Future.value(jsonDecode(File('assets/translations/${locale.languageCode}.json').readAsStringSync()) as Map<String, dynamic>);
}

/// خادمٌ وهميّ على ApiClient.dio: يسجّل الطلبات ويردّ بعقد server/employeeLedger.js.
/// «الموظف المتّصل الآن»: قائمة الحال (أحمد متّصل، سارة ظهرت قبل ساعتين، والمعطَّل لم يظهر) — الأوقات نسبةً لـ[now].
Map<String, dynamic> presenceListJson({DateTime? now}) {
  final t = (now ?? DateTime.now()).toUtc();
  String ago(Duration d) => t.subtract(d).toIso8601String();
  return {
    'feature_enabled': true,
    'now': t.toIso8601String(),
    'today': '2026-11-14',
    'online_window_sec': 150,
    'online_count': 1,
    'total': 3,
    'ops_unavailable': false,
    'employees': [
      {
        'employee': {'id': 7, 'username': 'emp1', 'name': 'أحمد'},
        'active': true,
        'online': true,
        'last_seen_at': ago(const Duration(seconds: 40)),
        'platform': 'android',
        'platform_label': 'أندرويد',
        'app_build': '181',
        'last_login_at': ago(const Duration(hours: 5)),
        'first_seen_today_at': ago(const Duration(hours: 4)),
        'minutes_today': 142,
        'ops_today': 12,
        'last_op': {'at': ago(const Duration(minutes: 6)), 'label': 'تفعيل'},
      },
      {
        'employee': {'id': 8, 'username': 'emp2', 'name': 'سارة'},
        'active': true,
        'online': false,
        'last_seen_at': ago(const Duration(hours: 2, minutes: 5)),
        'platform': 'web',
        'platform_label': 'الموقع',
        'app_build': null,
        'last_login_at': ago(const Duration(hours: 6)),
        'first_seen_today_at': ago(const Duration(hours: 5)),
        'minutes_today': 38,
        'ops_today': 3,
        'last_op': {'at': ago(const Duration(hours: 2, minutes: 20)), 'label': 'تسديد دين'},
      },
      {
        'employee': {'id': 9, 'username': 'cashier', 'name': 'صراف'},
        'active': true,
        'online': false,
        'last_seen_at': null,
        'platform': null,
        'platform_label': null,
        'app_build': null,
        'last_login_at': null,
        'first_seen_today_at': null,
        'minutes_today': 0,
        'ops_today': 0,
        'last_op': null,
      },
    ],
  };
}

/// نشاط أحمد: اليوم بأنواع عمليّاته وأيّامٌ سابقة.
Map<String, dynamic> presenceDetailJson({DateTime? now}) {
  final t = (now ?? DateTime.now()).toUtc();
  String ago(Duration d) => t.subtract(d).toIso8601String();
  return {
    'feature_enabled': true,
    'now': t.toIso8601String(),
    'today': '2026-11-14',
    'employee': {'id': 7, 'username': 'emp1', 'name': 'أحمد'},
    'active': true,
    'online': true,
    'last_seen_at': ago(const Duration(seconds: 40)),
    'platform': 'android',
    'platform_label': 'أندرويد',
    'app_build': '181',
    'last_login_at': ago(const Duration(hours: 5)),
    'last_op': {'at': ago(const Duration(minutes: 6)), 'label': 'تفعيل'},
    'ops_unavailable': false,
    'today_summary': {
      'first_seen_at': ago(const Duration(hours: 4)),
      'last_seen_at': ago(const Duration(seconds: 40)),
      'minutes': 142,
      'ops': 12,
      'ops_by_type': [
        {'label': 'تفعيل', 'count': 7},
        {'label': 'تسديد دين', 'count': 3},
        {'label': 'إضافة مشترك', 'count': 2},
      ],
    },
    'days': [
      {'day': '2026-11-14', 'first_seen_at': ago(const Duration(hours: 4)), 'last_seen_at': ago(const Duration(seconds: 40)), 'minutes': 142, 'platform_label': 'أندرويد', 'ops': 12},
      {'day': '2026-11-13', 'first_seen_at': ago(const Duration(hours: 30)), 'last_seen_at': ago(const Duration(hours: 25)), 'minutes': 265, 'platform_label': 'أندرويد', 'ops': 31},
      {'day': '2026-11-10', 'first_seen_at': null, 'last_seen_at': null, 'minutes': 0, 'platform_label': null, 'ops': 4},
    ],
    'keep_days': 30,
  };
}

class LedgerServer implements HttpClientAdapter {
  bool ledgerFeature = true;

  /// «الموظف المتّصل الآن» مفتوحةٌ لهذه الصفحة (الافتراض مطفأة: اختبارات الدفتر كما هي).
  bool presenceOn = false;
  bool presenceDetailFails = false;

  /// الموظّف ٩ معطَّل في قائمة الموظفين (شارة «معطّل» بالرأس).
  bool withDisabledEmployee = false;

  /// `/me` يردّ كموظّفٍ بهذا الرقم (صاحب صلاحيّة الرواتب حين [meCanManage]) — null = المدير.
  int? meAsEmployee;
  bool meCanManage = true;
  bool accountFails = false;
  bool listFails = false;
  bool previewFails = false;
  Map<String, dynamic>? preview;
  Map<String, dynamic> settlePreviewExtra = const {};
  (int, Map<String, dynamic>)? salaryReply;
  final List<(int, Map<String, dynamic>)> moveReplies = [];
  final List<(int, Map<String, dynamic>)> payReplies = [];

  /// قيمة `periods` في كلّ طلب معاينة (null = لم تُرسل).
  final List<String?> previewQueries = [];
  final _reqs = <RequestOptions>[];

  List<String> get paths => _reqs.map((r) => r.path).toList();
  List<Map<String, dynamic>> bodiesOf(String method, String path) => _reqs
      .where((r) => r.method == method && r.path == path)
      .map((r) => Map<String, dynamic>.from(r.data as Map))
      .toList();

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    _reqs.add(o);
    const base = '/api/v2/employee-ledger';
    (int, Map<String, dynamic>) reply = (404, {'success': false});
    final p = o.path;
    final m = o.method;
    if (p == '$base/me') {
      reply = meAsEmployee == null
          ? (200, {'success': true, 'data': {'is_employee': false, 'feature_enabled': ledgerFeature, 'can_manage': true}})
          : (200, {
              'success': true,
              'data': {
                'is_employee': true,
                'feature_enabled': ledgerFeature,
                'can_manage': meCanManage,
                if (ledgerFeature) ...(ledgerAccountJson()..['employee'] = {'id': meAsEmployee, 'username': 'cashier', 'name': 'صراف'}),
              },
            });
    } else if (p == base && m == 'GET') {
      reply = listFails
          ? (409, {'success': false, 'message': 'تعذّر'})
          : (200, {
              'success': true,
              'data': {
                'feature_enabled': true,
                'is_manager': true,
                'employees': [
                  {
                    'employee': {'id': 7, 'username': 'emp1', 'name': 'أحمد'},
                    'active': true,
                    'owed': 100000,
                    'loans_total': 400000,
                    'owes_total': 500000,
                    'due_pending': 0,
                    'balance': -500000,
                    'salary': {'amount': 500000, 'cycle': 'monthly', 'pay_day': 28, 'comp_mode': 'salary', 'configured': true, 'due_count': 1},
                  },
                  {
                    'employee': {'id': 8, 'username': 'emp2', 'name': 'سارة'},
                    'active': true,
                    'owed': 0,
                    'loans_total': 0,
                    'owes_total': 0,
                    'due_pending': 0,
                    'balance': 0,
                    'salary': {'amount': null, 'cycle': 'monthly', 'pay_day': 1, 'comp_mode': 'salary', 'configured': false},
                  },
                  {
                    'employee': {'id': 9, 'username': 'cashier', 'name': 'صراف'},
                    'active': true,
                    'owed': 0,
                    'loans_total': 0,
                    'owes_total': 0,
                    'due_pending': 0,
                    'balance': 0,
                    'salary': {'amount': null, 'cycle': 'monthly', 'pay_day': 1, 'comp_mode': 'salary', 'configured': false},
                  },
                ],
                'totals': {'owes_total': 500000, 'due_pending': 0},
              },
            });
    } else if (p == '$base/7' && m == 'GET') {
      reply = accountFails ? (409, {'success': false, 'message': 'تعذّر تحميل حساب الموظف الآن'}) : (200, {'success': true, 'data': ledgerAccountJson()});
    } else if (p == '$base/9' && m == 'GET') {
      reply = (200, {'success': true, 'data': ledgerAccountJson()..['employee'] = {'id': 9, 'username': 'cashier', 'name': 'صراف'}});
    } else if (p == '/api/v2/employees' && m == 'GET') {
      reply = (200, {
        'success': true,
        'data': [
          {'id': 7, 'username': 'emp1', 'full_name': 'أحمد', 'is_active': true, 'permissions': {'subscribers.view': true}},
          {'id': 8, 'username': 'emp2', 'full_name': 'سارة', 'is_active': true, 'permissions': {}},
          {'id': 9, 'username': 'cashier', 'full_name': 'صراف', 'is_active': !withDisabledEmployee, 'permissions': {}},
        ],
      });
    } else if (p == '/api/v2/employees/permissions-catalog') {
      reply = (200, {
        'success': true,
        'data': {
          'permissions': {
            'subscribers.view': {'label': 'عرض المشتركين', 'category': 'subscribers'},
          },
          'categories': {
            'subscribers': {'label': 'المشتركون'},
          },
          'defaults': {'subscribers.view': true},
          'presets': <String, Object>{},
        },
      });
    } else if (p == '$base/7/movements' && m == 'POST') {
      reply = moveReplies.isNotEmpty ? moveReplies.removeAt(0) : (200, {'success': true, 'duplicate': false, 'movements': [], 'data': ledgerAccountJson()});
    } else if (p == '$base/7/movements/11/void' && m == 'POST') {
      reply = (200, {'success': true, 'data': ledgerAccountJson()});
    } else if (p == '$base/7/salary' && m == 'PUT') {
      reply = salaryReply ?? (200, {'success': true, 'salary': {}, 'data': ledgerAccountJson()});
    } else if (p == '$base/7/payslip/preview') {
      previewQueries.add(o.queryParameters.containsKey('periods') ? '${o.queryParameters['periods']}' : null);
      reply = previewFails ? (409, {'success': false, 'message': 'تعذّر تجهيز الكشف الآن'}) : (200, {'success': true, 'data': preview ?? ledgerPreviewJson()});
    } else if (p == '$base/7/payslip' && m == 'POST') {
      reply = payReplies.isNotEmpty ? payReplies.removeAt(0) : (200, {'success': true, 'duplicate': false, 'payslip': {}, 'data': ledgerAccountJson()});
    } else if (p == '$base/7/payslips/3/void' && m == 'POST') {
      reply = (200, {'success': true, 'data': ledgerAccountJson()});
    } else if (p.startsWith('$base/7/periods/') && m == 'POST') {
      reply = (200, {'success': true, 'data': ledgerAccountJson()});
    } else if (p == '/api/v2/employee-presence' && m == 'GET') {
      reply = meAsEmployee != null
          ? (403, {'success': false, 'code': 'MANAGER_ONLY', 'message': 'هذا القسم لمدير الصفحة وحده'})
          : presenceOn
              ? (200, {'success': true, 'data': presenceListJson()})
              : (200, {'success': true, 'data': {'feature_enabled': false, 'online_count': 0, 'total': 0, 'employees': []}});
    } else if (p == '/api/v2/employee-presence/7' && m == 'GET') {
      reply = presenceDetailFails
          ? (409, {'success': false, 'code': 'EMPLOYEE_PRESENCE_UNAVAILABLE', 'message': 'تعذّر التحميل الآن — حاول بعد قليل'})
          : (200, {'success': true, 'data': presenceDetailJson()});
    } else if (p == '/api/v2/employee-presence/beat' && m == 'POST') {
      reply = (200, {'success': true, 'data': {'feature_enabled': presenceOn, 'beat_every_sec': 60}});
    } else if (p == '/api/admin/expenses' && m == 'GET') {
      reply = (200, {
        'success': true,
        'total': 600000,
        'expenses': [
          {
            'id': 90,
            'amount': 525000,
            'expense_date': '2026-11-13',
            'note': 'راتب أحمد — تشرين الثاني 2026',
            'payslip': {'id': 3, 'number': 2, 'employee_id': 7, 'employee_name': 'أحمد'},
          },
          {'id': 89, 'amount': 75000, 'expense_date': '2026-11-12', 'note': 'وقود المولّد'},
        ],
      });
    } else if (p == '/api/reports/finance') {
      reply = (200, {
        'success': true,
        'data': {
          'kpis': {
            'activate_cash_sum': 1450000,
            'debt_pay_sum': 250000,
            'balance_add_sum': 120000,
            'activate_non_cash_sum': 90000,
            'expenses_sum': 600000,
            'expenses_count': 2,
            'activations_count': 41,
            'extend_count': 3,
            'emp_salaries_sum': 525000,
            'emp_salaries_count': 1,
            'emp_given_sum': 200000,
            'emp_recovered_sum': 150000,
            'emp_repaid_sum': 0,
            'emp_receivable_change': 50000,
            'emp_receivable_outstanding': 500000,
          },
          'recentLogs': [
            {
              'id': 'emp_11',
              'action_type': 'EMPLOYEE_MOVE',
              'action_description': 'سلفة: أحمد (من النقد الذي بيده) — عيد',
              'amount': 100000,
              'admin_username': 'admin',
              'target_name': 'أحمد',
              'created_at': '2026-11-13T09:10:00.000Z',
            },
            {
              'id': 'emp_12',
              'action_type': 'EMPLOYEE_MOVE',
              'action_description': 'مكافأة: أحمد',
              'amount': 25000,
              'admin_username': 'admin',
              'target_name': 'أحمد',
              'created_at': '2026-11-13T08:40:00.000Z',
            },
            {
              'id': 'expense_90',
              'action_type': 'ADMIN_EXPENSE',
              'action_description': 'راتب أحمد — تشرين الثاني 2026',
              'amount': 525000,
              'admin_username': 'admin',
              'created_at': '2026-11-13T08:00:00.000Z',
            },
            {
              'id': 'emp_14',
              'action_type': 'EMPLOYEE_MOVE',
              'action_description': 'تسديد: سارة',
              'amount': 30000,
              'admin_username': 'admin',
              'target_name': 'سارة',
              'created_at': '2026-11-12T12:00:00.000Z',
            },
          ],
        },
      });
    } else if (p == '/api/v2/settlements/current') {
      reply = (200, {
        'success': true,
        'data': {
          'started': true,
          'head': {'id': 4, 'kind': 'settlement', 'number': 3, 'status': 'active', 'cut_at': '2026-11-10T18:00:00.000Z', 'carried_amount': 50000},
          'period': {'start_at': '2026-11-10T18:00:00.000Z'},
          'cut': {'activity_id': 900, 'expense_id': 90, 'emp_ledger_id': 42},
          'totals': {
            'opening_balance': 50000,
            'cash_activations': {'sum': 1450000, 'count': 41},
            'debt_payments': {'sum': 250000, 'count': 9},
            'cash_in': 1700000,
            'expenses': {'sum': 600000, 'count': 2},
            'new_debts': {'sum': 120000, 'count': 4},
            'employee_moves': {'sum': -50000, 'count': 3},
            'expected_amount': 1100000,
          },
          'collectors': [
            {
              'employee_id': null,
              'cash_activations': {'sum': 1450000, 'count': 41},
              'debt_payments': {'sum': 250000, 'count': 9},
              'expenses': {'sum': 600000, 'count': 2},
              'employee_moves': {'sum': -50000, 'count': 3},
              'net_amount': 1050000,
            },
          ],
          'can_settle': true,
          'can_void': true,
          'today': '2026-11-13',
          'month_start': '2026-11-01',
        },
      });
    } else if (p == '/api/v2/settlements/movements') {
      reply = (200, {
        'success': true,
        'data': {
          'has_more': false,
          'items': [
            {
              'source': 'employee',
              'id': 3,
              'kind': 'emp_payslip_recover',
              'direction': 'in',
              'amount': 150000,
              'created_at': '2026-11-13T08:00:00.000Z',
              'description': 'استقطاع سلف وأقساط من كشف راتب رقم 2: أحمد',
            },
            {
              'source': 'expense',
              'id': 90,
              'kind': 'expense',
              'direction': 'out',
              'amount': 525000,
              'created_at': '2026-11-13T08:00:00.000Z',
              'description': 'راتب أحمد — تشرين الثاني 2026',
              'expense_date': '2026-11-13',
            },
            {
              'source': 'employee',
              'id': 15,
              'kind': 'emp_loan',
              'direction': 'out',
              'amount': 200000,
              'created_at': '2026-11-12T10:00:00.000Z',
              'description': 'قرض: سارة — تجهيز بيت',
            },
            {
              'source': 'activity',
              'id': 800,
              'kind': 'cash_activation',
              'direction': 'in',
              'amount': 35000,
              'created_at': '2026-11-12T09:00:00.000Z',
              'subscriber': 'علي حسين',
              'package_name': 'فايبر 35',
            },
          ],
        },
      });
    } else if (p == '/api/v2/settlements' && m == 'GET') {
      reply = (200, {'success': true, 'data': {'items': [], 'total': 0}});
    } else if (p == '/api/v2/employee-limits/me') {
      reply = (200, {'success': true, 'data': {'is_employee': false, 'feature_enabled': true, 'enforcement_off': false}});
    } else if (p == '/api/v2/employee-limits/7' && m == 'GET') {
      reply = (200, {'success': true, 'data': ledgerLimitsStatusJson()});
    } else if (p == '/api/v2/employee-limits/7' && m == 'PUT') {
      reply = (200, {'success': true, 'data': ledgerLimitsStatusJson()});
    } else if (p == '/api/v2/employees/7' && m == 'PUT') {
      reply = (200, {'success': true, 'data': {'id': 7, 'username': 'emp1'}});
    } else if (p == '/api/v2/employee-limits/7/settlement/preview') {
      reply = (200, {
        'success': true,
        'data': {
          'cut': {'head_id': 3, 'activity_id': 900},
          'period': {'start_at': '2026-11-09T05:00:00.000Z'},
          'cash_in': 350000,
          'debt_out': 120000,
          'open_debt': 90000,
          'holds': {'count': 0, 'cash': 0, 'debt': 0},
          'ops_count': 4,
          'profit': 20000,
          'breakdown': ledgerLimitsStatusJson()['breakdown'],
          ...settlePreviewExtra,
        },
      });
    } else if (p == '/api/v2/employee-limits/7/settlement' && m == 'POST') {
      reply = (200, {'success': true, 'data': {'id': 5, 'number': 1, 'status': 'active', 'cash_in': 350000}});
    }
    return ResponseBody.fromString(jsonEncode(reply.$2), reply.$1, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}
