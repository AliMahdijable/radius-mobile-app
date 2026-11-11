import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/dashboard_api.dart';
import 'package:rad_mysvcs/api/employees_api.dart';
import 'package:rad_mysvcs/api/payment_voids_api.dart';
import 'package:rad_mysvcs/api/reports_api.dart';
import 'package:rad_mysvcs/api/settlements_api.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/dashboard/widgets/recent_activities.dart';
import 'package:rad_mysvcs/screens/reports/widgets/report_log_tile.dart';
import 'package:rad_mysvcs/screens/settlements/settlements_screen.dart';
import 'package:rad_mysvcs/screens/subscribers/sheets/movements_sheet.dart';
import 'package:rad_mysvcs/services/provider_service.dart';
import 'package:rad_mysvcs/widgets/payment_void_bits.dart';

import 'visual_perm/visual_perm_harness.dart';

/// «إلغاء تسديد» بالتطبيق (١١ نوفمبر ٢٠٢٦ — الخادم 4ed3694 + 30d50ab، والويب fbf277d).
///   • النموذج: الحال وزرّ السطر (يفتح · مقفل «لا صلاحيّة» · لا شيء)، والملغى بلا زرّ، وما لم يكتمل يُفتح ليُحسم.
///   • النداءات للشركة المفتوحة صراحةً، وما يُرسل: رقم السطر وما عُرض (المبلغ والمشترك) — والربط بـmode/add_id وحده.
///   • تسوية الحساب: زرّ الإلغاء على حركة التسديد، والاختيار الإلزاميّ حين وُجدت إضافة دينٍ بعده، والملغى بشارته.
///   • سجل حركات المشترك: الزرّ والشارة، وسطر الإلغاء باسمه، و«الدين بعدها» بإشارته (كان يُعرض «رصيد دائن»).
///   • الموظّف بلا صلاحيّة: الزرّ بمكانه مقفلاً؛ والميزة مطفأة للصفحة ⇒ لا زرّ ولا شارة.
///   • نتيجةٌ لم يؤكّدها الساس تُحسم من النافذة نفسها.
class _PvServer implements HttpClientAdapter {
  _PvServer(this.inner);
  final HttpClientAdapter inner;

  bool enabled = true;
  bool canVoid = true;
  bool canLink = true;
  bool ownOnly = false;

  /// طلب الحال يسقط (500).
  bool statusFails = false;

  /// قيود الإلغاء بأرقام سطور التسديد.
  final voids = <int, Map<String, dynamic>>{};

  /// الردّ القادم للإلغاء/الحسم: (status, body) — null ⇒ نجاح.
  (int, Map<String, dynamic>)? nextRun;
  (int, Map<String, dynamic>)? nextResolve;

  /// إضافات الدين المرشّحة للربط بتسديدٍ برقمه.
  final candidates = <int, List<Map<String, dynamic>>>{
    770745: [
      {'id': 774526, 'amount': 60000, 'at': '2026-11-02T08:10:00Z', 'by': null, 'comment': 'رجّعنا الدين'},
    ],
  };

  final statusCalls = <List<int>>[];
  final previews = <int>[];
  final posts = <(String, Map<String, dynamic>)>[];

  /// كلّ طلبات الإلغاء كما وصلت — لفحص الوجهة (المفتوحة صراحةً).
  final seen = <RequestOptions>[];

  int expected = 950000;
  int currentGets = 0;
  int statementGets = 0;

  /// طلبات «آخر النشاطات» كما وصلت، وما يُردّ لها.
  final feedQueries = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> feed = const [];

  List<Map<String, dynamic>> moves = [
    {
      'source': 'activity', 'id': 770800, 'kind': 'debt_payment', 'direction': 'in', 'amount': 35000,
      'created_at': '2026-11-10T13:40:00Z', 'subscriber': 'sara.net', 'employee_id': null, 'payment_activity_id': 770800,
    },
    {
      'source': 'expense', 'id': 55, 'kind': 'expense', 'direction': 'out', 'amount': 50000,
      'created_at': '2026-11-02T05:00:00Z', 'description': 'وقود المولّدة', 'employee_id': null,
    },
    {
      'source': 'activity', 'id': 770745, 'kind': 'debt_payment', 'direction': 'in', 'amount': 60000,
      'created_at': '2026-11-01T18:45:00Z', 'subscriber': 'ali.kareem', 'employee_id': 3, 'employee_username': 'hussein',
      'employee_name': 'حسين مهدي', 'payment_activity_id': 770745,
    },
    {
      'source': 'activity', 'id': 770700, 'kind': 'cash_activation', 'direction': 'in', 'amount': 31000,
      'created_at': '2026-11-01T10:00:00Z', 'subscriber': 'omar.fiber', 'package_name': 'Fiber 50', 'employee_id': null,
    },
  ];

  List<Map<String, dynamic>> statement = [
    {
      'id': 900001, 'created_at': '2026-11-10T09:12:00Z', 'action_type': 'BALANCE_DEDUCT',
      'description': 'تسديد دين 35,000 د.ع للمشترك ali.kareem', 'amount': 35000, 'balance_after': 0, 'admin_name': 'mahdi',
      'payment_activity_id': 900001,
    },
    {
      'id': 770745, 'created_at': '2026-11-01T18:45:00Z', 'action_type': 'BALANCE_DEDUCT',
      'description': 'تسديد دين 60,000 د.ع للمشترك ali.kareem', 'amount': 60000, 'balance_after': -35000, 'admin_name': 'hussein',
      'payment_activity_id': 770745,
    },
    {
      'id': 770001, 'created_at': '2026-10-28T10:00:00Z', 'action_type': 'SUBSCRIBER_ACTIVATE',
      'description': 'تفعيل مشترك غير نقدي', 'amount': 35000, 'balance_after': -95000, 'admin_name': 'mahdi',
    },
  ];

  static ResponseBody _json(int status, Object body) => ResponseBody.fromString(jsonEncode(body), status, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      });

  Map<String, dynamic> _voidItem(int paymentId, num amount, {String mode = 'restore', String status = 'done'}) => {
        'void_id': 10 + voids.length,
        'payment_id': paymentId,
        'mode': mode,
        'status': status,
        'amount': amount,
        'by': 'mahdi',
        'by_employee_id': null,
        'reason': null,
        'at': '2026-11-11T12:30:00Z',
      };

  num _amountOf(int paymentId) {
    for (final m in moves) {
      if (m['payment_activity_id'] == paymentId) return m['amount'] as num;
    }
    for (final t in statement) {
      if (t['payment_activity_id'] == paymentId) return t['amount'] as num;
    }
    return 0;
  }

  String _subOf(int paymentId) {
    for (final m in moves) {
      if (m['payment_activity_id'] == paymentId) return m['subscriber'] as String;
    }
    return 'ali.kareem';
  }

  /// ما يفعله الخادم بعد إلغاءٍ تمّ: القيد، وحركةٌ خارجة في الصندوق، وسطرٌ بمبلغٍ سالب في كشف المشترك.
  void _applyVoid(int paymentId, {required String mode}) {
    final amount = _amountOf(paymentId);
    voids[paymentId] = _voidItem(paymentId, amount, mode: mode);
    expected -= amount.toInt();
    // كالخادم: حركة الإلغاء منسوبةٌ لمن استلم التسديد (من حصّته يخرج المبلغ)
    final paid = moves.firstWhere((m) => m['payment_activity_id'] == paymentId, orElse: () => const {});
    moves = [
      {
        'source': 'activity', 'id': 990000 + voids.length, 'kind': 'debt_payment_void', 'direction': 'out', 'amount': amount,
        'created_at': '2026-11-11T12:30:00Z', 'subscriber': _subOf(paymentId), 'employee_id': paid['employee_id'],
        'employee_username': paid['employee_username'], 'employee_name': paid['employee_name'],
      },
      ...moves,
    ];
    if (mode == 'restore') {
      statement = [
        {
          'id': 990000 + voids.length, 'created_at': '2026-11-11T12:30:00Z', 'action_type': 'BALANCE_DEDUCT',
          'description': 'إلغاء تسديد دين ${amount.toInt()} د.ع للمشترك ali.kareem — ألغاه المدير mahdi', 'amount': -amount,
          'balance_after': -amount, 'admin_name': 'mahdi',
        },
        ...statement,
      ];
    }
  }

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final get = o.method.toUpperCase() == 'GET';
    final p = o.path;

    if (p.startsWith('/api/v2/payment-voids')) seen.add(o);

    if (get && p == '/api/v2/payment-voids/status') {
      final ids = (o.queryParameters['ids'] ?? '').toString().split(',').map(int.tryParse).whereType<int>().toList();
      statusCalls.add(ids);
      if (statusFails) return _json(500, {'success': false, 'message': 'خطأ'});
      return _json(200, {
        'success': true,
        'enabled': enabled,
        'can_void': enabled && canVoid,
        'can_link': enabled && canLink,
        'own_only': ownOnly,
        'items': [
          for (final id in ids)
            if (voids[id] != null) voids[id],
        ],
      });
    }
    final pm = RegExp(r'^/api/v2/payment-voids/preview/(\d+)$').firstMatch(p);
    if (get && pm != null) {
      final id = int.parse(pm.group(1)!);
      previews.add(id);
      final collector = id == 770745 ? {'employee_id': 3, 'username': 'hussein'} : {'employee_id': null, 'username': null};
      final cands = canLink ? (candidates[id] ?? const <Map<String, dynamic>>[]) : const <Map<String, dynamic>>[];
      final v = voids[id];
      final blocked = v != null && v['status'] == 'done';
      return _json(200, {
        'success': true,
        'data': {
          'payment': {'id': id, 'amount': _amountOf(id), 'subscriber': _subOf(id), 'idx': '132076', 'at': '2026-11-01T18:45:00Z', 'collector': collector},
          'can_void': !blocked,
          if (blocked) 'blocked': {'code': 'ALREADY_VOIDED', 'message': 'هذا التسديد ملغى سابقاً'},
          'void': v,
          'settlement_number': id == 900001 ? 3 : null,
          'candidates': cands,
          'can_link': cands.isNotEmpty,
        },
      });
    }
    if (!get && p == '/api/v2/payment-voids') {
      final body = Map<String, dynamic>.from((o.data as Map?) ?? const {});
      posts.add((p, body));
      final r = nextRun;
      nextRun = null;
      if (r != null) {
        if (r.$2['code'] == 'OUTCOME_UNKNOWN') {
          final id = body['payment_id'] as int;
          voids[id] = {..._voidItem(id, _amountOf(id), status: 'unknown'), 'void_id': r.$2['void_id']};
        }
        return _json(r.$1, r.$2);
      }
      final id = body['payment_id'] as int;
      final mode = body['mode'] == 'link' ? 'link' : 'restore';
      _applyVoid(id, mode: mode);
      return _json(200, {'success': true, 'data': voids[id]});
    }
    final rm = RegExp(r'^/api/v2/payment-voids/(\d+)/resolve$').firstMatch(p);
    if (!get && rm != null) {
      final body = Map<String, dynamic>.from((o.data as Map?) ?? const {});
      posts.add((p, body));
      final r = nextResolve;
      nextResolve = null;
      if (r != null) return _json(r.$1, r.$2);
      final voidId = int.parse(rm.group(1)!);
      final entry = voids.entries.firstWhere((e) => e.value['void_id'] == voidId);
      if (body['applied'] == true) {
        _applyVoid(entry.key, mode: 'restore');
        return _json(200, {'success': true, 'data': voids[entry.key]});
      }
      voids.remove(entry.key);
      return _json(200, {'success': true, 'data': {'void_id': voidId, 'payment_id': entry.key, 'status': 'released'}});
    }

    // ── تسوية الحساب ──
    if (get && p == '/api/v2/settlements/current') {
      currentGets += 1;
      return _json(200, {
        'success': true,
        'data': {
          'started': true,
          'head': {'id': 3, 'kind': 'settlement', 'number': 3, 'status': 'active', 'cut_at': '2026-10-31T12:51:00Z'},
          'period': {'start_at': '2026-10-31T12:51:00Z'},
          'cut': {'head_id': 3, 'activity_id': 999999, 'expense_id': 99},
          'totals': {
            'opening_balance': 0,
            'cash_activations': {'sum': 310000, 'count': 10},
            'debt_payments': {'sum': expected - 310000 + 390000, 'count': 24 - voids.values.where((v) => v['status'] == 'done').length},
            'cash_in': expected + 390000,
            'expenses': {'sum': 390000, 'count': 8},
            'new_debts': {'sum': 60000, 'count': 1},
            'expected_amount': expected,
          },
          'collectors': const [],
          'can_settle': true,
          'can_void': true,
        },
      });
    }
    if (get && p == '/api/v2/settlements/movements') {
      return _json(200, {'success': true, 'data': {'items': moves, 'has_more': false}});
    }
    if (get && p == '/api/v2/settlements') {
      return _json(200, {'success': true, 'data': {'items': const [], 'total': 0}});
    }

    // ── «آخر النشاطات» بالرئيسيّة ──
    if (get && p == '/api/activities/daily-activations') {
      feedQueries.add(Map<String, dynamic>.from(o.queryParameters));
      return _json(200, {'success': true, 'counts': {'activate': 0, 'extend': 0, 'total': feed.length}, 'data': feed});
    }

    // ── كشف المشترك ──
    if (get && p == '/api/reports/account-statement') {
      statementGets += 1;
      return _json(200, {'success': true, 'data': {'subscriber': {'username': 'ali.kareem'}, 'transactions': statement}});
    }
    return inner.fetch(o, requestStream, cancelFuture);
  }

  @override
  void close({bool force = false}) => inner.close(force: force);
}

/// موظّف ايرث لنك يرى التسويات والمشتركين — بلا صلاحيّة إلغاء التسديد.
const _elEmployee = Scenario(
  id: 'PV_el_employee',
  title: 'موظّف ايرث لنك — بلا subscribers.void_payment',
  actor: Actor.elEmployee,
  provider: 'earthlink',
  keys: {'settlements.view': true, 'subscribers.view': true, 'subscribers.view_activity': true},
);

/// أضيق هاتفٍ ندعمه — لا فيض ولا كرت يكبر. طويلٌ ليُرى الصندوق وحركاته في لقطةٍ واحدة.
const _narrow = VisualDevice('_320', Size(320, 1100), 2);

final _sub = Subscriber(idx: '132076', username: 'ali.kareem', firstname: 'علي', lastname: 'كريم');

void main() {
  setUpAll(visualSetUpAll);

  group('النموذج', () {
    test('الحال: enabled منطقيّةٌ شرط، والقيود بأرقام سطورها، وما بلا رقمٍ يُسقط', () {
      expect(PaymentVoidStatus.fromJson({'success': false, 'code': 'PERMISSION_DENIED'}), isNull, reason: 'رفضٌ ليس حالاً');
      expect(PaymentVoidStatus.fromJson({'enabled': 'true'}), isNull);
      final off = PaymentVoidStatus.fromJson({'enabled': false, 'can_void': true, 'can_link': true})!;
      expect((off.enabled, off.canVoid, off.canLink), (false, false, false), reason: 'مطفأة ⇒ لا شيء يحقّ');
      final st = PaymentVoidStatus.fromJson({
        'success': true,
        'enabled': true,
        'can_void': true,
        'can_link': false,
        'own_only': true,
        'items': [
          {'void_id': 4, 'payment_id': 770745, 'mode': 'link', 'status': 'done', 'amount': '60000', 'by': 'mahdi', 'at': '2026-11-11T12:30:00Z'},
          {'void_id': 5, 'payment_id': 900001, 'status': 'unknown', 'amount': 35000},
          {'payment_id': 1},
          'x',
        ],
      })!;
      expect((st.enabled, st.canVoid, st.canLink, st.ownOnly), (true, true, false, true));
      expect(st.items.keys, [770745, 900001]);
      expect(st.of(770745)!.isDone, isTrue);
      expect(st.of(770745)!.amount, 60000);
      expect(st.of(770745)!.mode, 'link');
      expect(st.of(900001)!.isUnknown, isTrue);
      expect(st.of(900001)!.mode, 'restore');
      expect(st.of(null), isNull);
    });

    test('زرّ السطر: يفتح · مقفل «لا صلاحيّة» · لا شيء — والملغى بلا زرّ، وما لم يكتمل يُفتح ليُحسم', () {
      PaymentVoidStatus st({bool enabled = true, bool canVoid = true, Map<int, String> items = const {}}) => PaymentVoidStatus(
            enabled: enabled,
            canVoid: canVoid,
            canLink: false,
            ownOnly: !canVoid,
            items: {
              for (final e in items.entries)
                e.key: PaymentVoidItem(voidId: 1, paymentId: e.key, mode: 'restore', status: e.value, amount: 1000),
            },
          );
      expect(PaymentVoidStatus.off.actionFor(5), PaymentVoidAction.none);
      expect(st(enabled: false).actionFor(5), PaymentVoidAction.none);
      expect(st().actionFor(null), PaymentVoidAction.none, reason: 'سطرٌ بلا رقم تسديد');
      expect(st().actionFor(0), PaymentVoidAction.none);
      expect(st().actionFor(5), PaymentVoidAction.open);
      expect(st(items: {5: 'done'}).actionFor(5), PaymentVoidAction.none, reason: 'الملغى لا يُلغى ثانيةً');
      expect(st(items: {5: 'unknown'}).actionFor(5), PaymentVoidAction.open, reason: 'بانتظار حسم ⇒ يُفتح ليُحسم');
      expect(st(items: {5: 'pending'}).actionFor(5), PaymentVoidAction.open);
      expect(st(items: {5: 'restored'}).actionFor(5), PaymentVoidAction.open);
      // موظّفٌ بلا الصلاحيّة: مقفلٌ بمكانه — ولا قفل على ما له شارة
      expect(st(canVoid: false).actionFor(5), PaymentVoidAction.locked);
      expect(st(canVoid: false, items: {5: 'unknown'}).actionFor(5), PaymentVoidAction.none);
      expect(st(canVoid: false, items: {5: 'done'}).actionFor(5), PaymentVoidAction.none);
    });

    test('سطر الكشف: «إلغاء تسديد» = تسديدٌ بمبلغٍ سالب أو معلَّمٌ pay_void — ورقم السطر لسطور التسديد وحدها', () {
      expect(PaymentVoidsApi.isVoidRow({'action_type': 'BALANCE_DEDUCT', 'amount': -60000}), isTrue);
      expect(PaymentVoidsApi.isVoidRow({'action_type': 'debt_pay', 'amount': '-60,000'}), isTrue);
      expect(PaymentVoidsApi.isVoidRow({'action_type': 'BALANCE_ADD', 'amount': 60000, 'pay_void': true}), isTrue, reason: 'دفتر ايرث لنك');
      expect(PaymentVoidsApi.isVoidRow({'action_type': 'BALANCE_DEDUCT', 'amount': 60000}), isFalse);
      expect(PaymentVoidsApi.isVoidRow({'action_type': 'BALANCE_ADD', 'amount': -60000}), isFalse, reason: 'إنقاص دين لا إلغاء تسديد');
      expect(PaymentVoidsApi.isVoidRow({'action_type': 'SUBSCRIBER_ACTIVATE', 'amount': -1}), isFalse);
      expect(PaymentVoidsApi.isVoidRow({'action_type': 'BALANCE_DEDUCT'}), isFalse);
      expect(PaymentVoidsApi.paymentIdOf({'payment_activity_id': 770745}), 770745);
      expect(PaymentVoidsApi.paymentIdOf({'payment_activity_id': '770745'}), 770745);
      expect(PaymentVoidsApi.paymentIdOf({'payment_activity_id': 0}), isNull);
      expect(PaymentVoidsApi.paymentIdOf({'id': 5}), isNull);
      // وسم الإلغاء الداخليّ في ملاحظة الدفتر لا يُعرض
      expect(PaymentVoidsApi.cleanNote('إلغاء تسديد 60,000 د.ع — حركة #770745 - سُجّل خطأً [pv:770745]'), 'إلغاء تسديد 60,000 د.ع — حركة #770745 - سُجّل خطأً');
      expect(PaymentVoidsApi.cleanNote('تسديد دين [مرجع]'), 'تسديد دين [مرجع]');
      expect(PaymentVoidsApi.cleanNote(''), '');
    });

    test('حركة الصندوق: رقم سطر التسديد لحركة debt_payment وحدها، وحركة الإلغاء خارجةٌ بنوعها', () {
      final pay = BoxMovement.fromJson({'id': 12, 'kind': 'debt_payment', 'direction': 'in', 'amount': 60000, 'payment_activity_id': 770745})!;
      expect(pay.paymentActivityId, 770745, reason: 'ايرث لنك: رقم الحركة رقم دفتر، والزرّ برقم سطر السجلّ');
      expect(BoxMovement.fromJson({'id': 12, 'kind': 'debt_payment', 'amount': 1})!.paymentActivityId, isNull, reason: 'خادمٌ أقدم');
      expect(BoxMovement.fromJson({'id': 12, 'kind': 'cash_activation', 'amount': 1, 'payment_activity_id': 9})!.paymentActivityId, isNull);
      final v = BoxMovement.fromJson({'id': 13, 'kind': 'debt_payment_void', 'direction': 'out', 'amount': 60000, 'payment_activity_id': 13})!;
      expect((v.kind, v.isIn, v.amount, v.paymentActivityId), ('debt_payment_void', false, 60000, null));
    });

    test('المعاينة: التسديد ومن استلمه، وسبب المنع، والمرشّحون للربط', () {
      final p = PaymentVoidPreview.fromJson({
        'payment': {'id': 770745, 'amount': 60000, 'subscriber': 'ali.kareem', 'idx': '132076', 'at': '2026-11-01T18:45:00Z', 'collector': {'employee_id': 3, 'username': 'hussein'}},
        'can_void': true,
        'void': null,
        'settlement_number': 3,
        'candidates': [
          {'id': 774526, 'amount': 60000, 'at': '2026-11-02T08:10:00Z', 'by': null, 'comment': 'رجّعنا الدين'},
          {'amount': 1},
        ],
        'can_link': true,
      })!;
      expect((p.paymentId, p.amount, p.subscriber, p.collectorEmployeeId, p.collectorUsername), (770745, 60000, 'ali.kareem', 3, 'hussein'));
      expect((p.canVoid, p.blockedMessage, p.settlementNumber, p.canLink), (true, null, 3, true));
      expect(p.candidates.map((c) => c.id), [774526]);
      expect(p.candidates.single.comment, 'رجّعنا الدين');
      final b = PaymentVoidPreview.fromJson({
        'payment': {'id': 5, 'amount': null, 'subscriber': 'x', 'collector': null},
        'can_void': false,
        'blocked': {'code': 'NOT_YOUR_PAYMENT', 'message': 'هذا التسديد سجّله غيرك'},
        'void': {'void_id': 2, 'payment_id': 5, 'status': 'done', 'amount': 1000},
      })!;
      expect((b.canVoid, b.blockedMessage, b.amount, b.collectorEmployeeId), (false, 'هذا التسديد سجّله غيرك', null, null));
      expect(b.existing!.isDone, isTrue);
      expect(PaymentVoidPreview.fromJson({'payment': {}}), isNull);
      expect(PaymentVoidPreview.fromJson(null), isNull);
    });

    test('محرّر الموظّفين: المفتاح في قوائم الشركات الثلاث، خارج كلّ دورٍ جاهز، ولا يُرسل إلّا إن عرضه الكتالوج', () {
      const key = 'subscribers.void_payment';
      expect(ElEmployeePerms.voidPaymentKey, key);
      expect(ElEmployeePerms.earthlinkKeys, contains(key));
      expect(ElEmployeePerms.fiberxKeys, contains(key));
      expect(ElEmployeePerms.kitKeys, contains(key));
      for (final p in ElEmployeePerms.presets) {
        expect(p.keys, isNot(contains(key)), reason: '${p.label}: يُمنح وحده');
      }
      expect(ElEmployeePerms.hints[key], contains('سجّله هو فقط'));
      ProviderService.debugSet('earthlink');
      addTearDown(() => ProviderService.debugSet(null));
      // الكتالوج لا يعرضه (الميزة مطفأةٌ للحساب) ⇒ لا يُرسل — والخادم يُبقيه على المحفوظ
      expect(ElEmployeePerms.outgoing(['subscribers.view', 'subscribers.pay_debt'], {key: true}), isNot(contains(key)));
      // يعرضه ⇒ يُرسل كما اختاره المدير
      expect(ElEmployeePerms.outgoing(['subscribers.view', key], {key: true})[key], isTrue);
      expect(ElEmployeePerms.outgoing(['subscribers.view', key], const {})[key], isFalse);
      // ممنوحاً ⇒ الدور «مخصّص» (ليس من أيّ دورٍ جاهز)
      final general = {for (final k in ElEmployeePerms.presets.first.keys) k: true};
      final catalog = [...ElEmployeePerms.earthlinkKeys];
      expect(ElEmployeePerms.matching(general, catalogKeys: catalog)?.id, 'general');
      expect(ElEmployeePerms.matching({...general, key: true}, catalogKeys: catalog), isNull);
      // والكتالوج الذي لا يعرضه لا يحسبه: «موظّف عام» يبقى «موظّف عام»
      expect(ElEmployeePerms.matching({...general, key: true}, catalogKeys: catalog.where((k) => k != key))?.id, 'general');
    });
  });

  group('النداءات', () {
    testWidgets('كلّها للشركة المفتوحة صراحةً — والإلغاء يرسل رقم السطر وما عُرض، والربط بـmode/add_id وحده', (t) async {
      final server = _PvServer(await visualSetUp(s1bSasOwner));
      ApiClient.dio.httpClientAdapter = server;
      addTearDown(visualTearDown);

      final st = await t.runAsync(() => PaymentVoidsApi.status([770745, 0, -4, 770745, 900001]));
      expect(server.statusCalls.single, [900001, 770745], reason: 'بلا تكرار ولا غير الموجب، والأحدث أوّلاً');
      expect((st!.enabled, st.canVoid, st.canLink), (true, true, true));
      expect((await t.runAsync(() => PaymentVoidsApi.status(const [])))!.enabled, isFalse);
      expect(server.statusCalls.length, 1, reason: 'بلا أرقام لا نداء');

      final pv = await t.runAsync(() => PaymentVoidsApi.preview(770745));
      expect(pv!.data!.candidates.single.id, 774526);

      var r = await t.runAsync(() => PaymentVoidsApi.run(paymentId: 900001, expectAmount: 35000.0, expectSubscriber: 'ali.kareem', reason: '  '));
      expect((r!.ok, r.duplicate, r.code), (true, false, null));
      expect(server.posts.last.$2, {'payment_id': 900001, 'expect_amount': 35000, 'expect_subscriber': 'ali.kareem'},
          reason: 'إرجاع الدين: بلا mode، والسبب الفارغ لا يُرسل، والمبلغ الصحيح عدداً صحيحاً');
      r = await t.runAsync(() => PaymentVoidsApi.run(
          paymentId: 770745, expectAmount: 60000, expectSubscriber: 'ali.kareem', linkAddId: 774526, reason: ' سُجّل خطأً '));
      expect(r!.ok, isTrue);
      expect(server.posts.last.$2,
          {'payment_id': 770745, 'expect_amount': 60000, 'expect_subscriber': 'ali.kareem', 'mode': 'link', 'add_id': 774526, 'reason': 'سُجّل خطأً'});

      // ردود 4xx تصل ردّاً عاديّاً: رمزها ورسالتها ورقم القيد
      server.nextRun = (409, {'success': false, 'code': 'OUTCOME_UNKNOWN', 'message': 'لم يتأكّد إرجاع الدين', 'void_id': 7, 'payment_id': 770800});
      r = await t.runAsync(() => PaymentVoidsApi.run(paymentId: 770800, expectAmount: 35000, expectSubscriber: 'sara.net'));
      expect((r!.ok, r.code, r.voidId, r.message), (false, 'OUTCOME_UNKNOWN', 7, 'لم يتأكّد إرجاع الدين'));
      server.nextRun = (403, {'success': false, 'code': 'NOT_YOUR_PAYMENT', 'message': 'هذا التسديد سجّله غيرك'});
      r = await t.runAsync(() => PaymentVoidsApi.run(paymentId: 770800, expectAmount: 35000, expectSubscriber: 'sara.net'));
      expect((r!.ok, r.code, r.message), (false, 'NOT_YOUR_PAYMENT', 'هذا التسديد سجّله غيرك'));
      // 5xx: لا نعرف هل نُفّذ — رمز NETWORK ليُقرأ الحال قبل أيّ إعادة
      server.nextRun = (502, {'success': false});
      r = await t.runAsync(() => PaymentVoidsApi.run(paymentId: 770800, expectAmount: 35000, expectSubscriber: 'sara.net'));
      expect((r!.ok, r.code), (false, 'NETWORK'));

      server.nextResolve = (200, {'success': true, 'data': {'void_id': 7, 'payment_id': 770800, 'status': 'done', 'corrected': true}});
      r = await t.runAsync(() => PaymentVoidsApi.resolve(7, applied: false));
      expect((r!.ok, r.corrected), (true, true));
      expect(server.posts.last.$1, '/api/v2/payment-voids/7/resolve');
      expect(server.posts.last.$2, {'applied': false});

      expect(server.seen.length, greaterThanOrEqualTo(8));
      for (final o in server.seen) {
        expect(o.extra['companyOpen'], isTrue, reason: '${o.method} ${o.path}: للمفتوحة صراحةً');
        expect(o.extra.containsKey('companyKey'), isFalse);
        expect(o.headers.containsKey('x-company-key'), isFalse);
      }
    });

    testWidgets('الحال: ما زاد على سقف الخادم بطلبٍ ثانٍ، وتعذّره ⇒ مطفأة (لا زرّ ولا شارة)', (t) async {
      final server = _PvServer(await visualSetUp(s1bSasOwner));
      ApiClient.dio.httpClientAdapter = server;
      addTearDown(visualTearDown);

      server.voids[5] = server._voidItem(5, 1000);
      server.voids[640] = server._voidItem(640, 2000);
      final st = await t.runAsync(() => PaymentVoidsApi.status([for (var i = 1; i <= 650; i++) i]));
      expect(server.statusCalls.map((c) => c.length), [300, 300, 50]);
      expect(server.statusCalls.first.first, 650, reason: 'الأحدث أوّلاً');
      expect(server.statusCalls.last.last, 1);
      expect(st!.items.keys.toSet(), {5, 640}, reason: 'الطلبات تُدمج');
      expect(st.canVoid, isTrue);

      server.statusFails = true;
      final off = await t.runAsync(() => PaymentVoidsApi.status([1, 2]));
      expect((off!.enabled, off.actionFor(1)), (false, PaymentVoidAction.none));
    });
  });

  group('تسوية الحساب', () {
    tearDown(visualTearDown);

    Future<_PvServer> open(WidgetTester t, Scenario s, {VisualDevice d = phone, void Function(_PvServer)? prep}) async {
      final server = _PvServer(await visualSetUp(s));
      prep?.call(server);
      ApiClient.dio.httpClientAdapter = server;
      await pumpVisual(t, d, home: (_) => const SettlementsScreen());
      await settle(t, seconds: 2);
      return server;
    }

    testWidgets('المالك: زرّ على كلّ تسديد، والاختيار إلزاميّ حين وُجدت إضافة دينٍ بعده — ثمّ «ملغى» والصندوق ينقص', (t) async {
      final server = await open(t, s1bSasOwner);
      expect(server.statusCalls.single.toSet(), {770800, 770745}, reason: 'أرقام سطور التسديد وحدها');
      expect(find.byType(PaymentVoidRowButton), findsNWidgets(2), reason: 'تسديدان — لا زرّ على الصرفية والتفعيل');
      expect(find.byType(PaymentVoidBadge), findsNothing);
      expect(find.textContaining('950,000'), findsOneWidget);
      await shoot(t, s1bSasOwner, 'pay_void_settlements', phone, server.inner as VisualServer);

      // تسديد ali.kareem (60,000 — استلمه الموظّف hussein)
      await t.tap(find.byType(PaymentVoidRowButton).last);
      await settle(t, seconds: 1);
      expect(server.previews, [770745]);
      expect(find.text('إلغاء تسديد'), findsOneWidget);
      expect(find.text('hussein'), findsOneWidget, reason: 'من استلمه');
      expect(find.text('ماذا صار بدين المشترك بعد هذا التسديد؟'), findsOneWidget);
      await shoot(t, s1bSasOwner, 'pay_void_sheet_choice', phone, server.inner as VisualServer);

      // بلا اختيار: التأكيد لا يرسل شيئاً
      await t.tap(find.text('تأكيد الإلغاء'));
      await settle(t, seconds: 1);
      expect(server.posts, isEmpty);

      await t.tap(find.text('رجّعناه يدويّاً بإضافة دين'));
      await t.pump();
      await shoot(t, s1bSasOwner, 'pay_void_sheet_chosen', phone, server.inner as VisualServer);
      await t.tap(find.text('تأكيد الإلغاء'));
      await settle(t, seconds: 2);
      expect(server.posts.single.$2, {
        'payment_id': 770745,
        'expect_amount': 60000,
        'expect_subscriber': 'ali.kareem',
        'mode': 'link',
        'add_id': 774526,
      });
      expect(find.textContaining('دين المشترك كما هو'), findsOneWidget, reason: 'إشعار الربط');
      expect(find.text('تأكيد الإلغاء'), findsNothing, reason: 'النافذة أُغلقت');

      // القائمة من جديد: الصندوق ينقص، وحركة الإلغاء، والتسديد بشارته بلا زرّ
      expect(server.currentGets, 2);
      expect(find.textContaining('890,000'), findsOneWidget);
      expect(find.textContaining('950,000'), findsNothing);
      expect(find.byType(PaymentVoidBadge), findsOneWidget);
      expect(find.text('ملغى'), findsOneWidget);
      expect(find.byType(PaymentVoidRowButton), findsOneWidget, reason: 'الملغى بلا زرّ');
      expect(find.textContaining('إلغاء تسديد'), findsWidgets, reason: 'حركة الإلغاء باسمها');
      // الحركة منسوبةٌ لمن استلم التسديد (من حصّته يخرج المبلغ) — «من حصّة فلان» لا «فلان» (فلا يُقرأ «فلان ألغى»)
      expect(find.textContaining('من حصّة'), findsOneWidget);
      expect(find.textContaining('حسين مهدي'), findsNWidgets(2), reason: 'التسديد باسمه، والإلغاء من حصّته');
      await settle(t, seconds: 4); // الإشعار يزول
      await shoot(t, s1bSasOwner, 'pay_void_settlements_after', phone, server.inner as VisualServer);
    });

    testWidgets('الداكن: القائمة بعد الإلغاء، ونافذة تسديدٍ بلا اختيار — بلا استثناء', (t) async {
      final server = await open(t, s1bSasOwner, d: phoneDark, prep: (s) => s._applyVoid(770745, mode: 'link'));
      await shoot(t, s1bSasOwner, 'pay_void_settlements_after', phoneDark, server.inner as VisualServer);
      await t.tap(find.byType(PaymentVoidRowButton).first);
      await settle(t, seconds: 1);
      expect(find.text('يرجع الدين 35,000 د.ع على المشترك.'), findsOneWidget);
      await shoot(t, s1bSasOwner, 'pay_void_sheet_plain', phoneDark, server.inner as VisualServer);
    });

    testWidgets('أضيق هاتف: اسمٌ طويل ومبلغٌ بالملايين وشارة «بانتظار حسم» — بلا فيض، والزرّ يفتح الحسم', (t) async {
      final server = await open(t, s1bSasOwner, d: _narrow, prep: (s) {
        s._applyVoid(770745, mode: 'link');
        // أطول ما يكون: اسمٌ طويل، مبلغٌ بالملايين، وشارة «بانتظار حسم»
        s.moves = [
          for (final m in s.moves)
            if (m['id'] == 770800) {...m, 'subscriber': 'abdulrahman.alkhafaji@najaf-center', 'amount': 1250000} else m,
        ];
        s.voids[770800] = s._voidItem(770800, 1250000, status: 'unknown');
      });
      expect(find.text('بانتظار حسم'), findsOneWidget);
      await shoot(t, s1bSasOwner, 'pay_void_settlements', _narrow, server.inner as VisualServer);
      await t.tap(find.byType(PaymentVoidRowButton).first);
      await settle(t, seconds: 1);
      expect(find.text('الدين رجع — سجّل الإلغاء'), findsOneWidget, reason: 'بانتظار حسم ⇒ النافذة تحسم');
      await shoot(t, s1bSasOwner, 'pay_void_sheet_resolve', _narrow, server.inner as VisualServer);
    });

    testWidgets('الموظّف بلا صلاحيّة: الزرّ بمكانه مقفلاً — النقر رسالةٌ لا نافذة', (t) async {
      final server = await open(t, _elEmployee, prep: (s) {
        s.canVoid = false;
        s.canLink = false;
        s.ownOnly = true;
      });
      expect(find.byType(PaymentVoidRowButton), findsNWidgets(2));
      expect(find.descendant(of: find.byType(PaymentVoidRowButton), matching: find.byIcon(LucideIcons.lock)), findsNWidgets(2));
      expect(find.descendant(of: find.byType(PaymentVoidRowButton), matching: find.byIcon(LucideIcons.undo2)), findsNothing);
      await shoot(t, _elEmployee, 'pay_void_settlements_locked', phone, server.inner as VisualServer);
      await t.tap(find.byType(PaymentVoidRowButton).first);
      await t.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('ليس لديك صلاحيّة لهذا الإجراء'), findsOneWidget);
      expect(server.previews, isEmpty);
      expect(server.posts, isEmpty);
      await settle(t, seconds: 3);
    });

    testWidgets('الميزة مطفأةٌ للصفحة ⇒ لا زرّ ولا شارة — والقائمة كما كانت', (t) async {
      final server = await open(t, s1bSasOwner, prep: (s) => s.enabled = false);
      expect(server.statusCalls.length, 1);
      expect(find.byType(PaymentVoidRowButton), findsNothing);
      expect(find.byType(PaymentVoidBadge), findsNothing);
      expect(find.text('sara.net'), findsOneWidget);
    });

    testWidgets('تعذّرت قراءة الحال ⇒ لا زرّ — والصندوق وحركاته كما هي', (t) async {
      await open(t, s1bSasOwner, prep: (s) => s.statusFails = true);
      expect(find.byType(PaymentVoidRowButton), findsNothing);
      expect(find.text('sara.net'), findsOneWidget);
      expect(find.textContaining('950,000'), findsOneWidget);
    });
  });

  group('سجل حركات المشترك', () {
    tearDown(visualTearDown);

    Future<_PvServer> open(WidgetTester t, Scenario s, {VisualDevice d = phone, void Function(_PvServer)? prep}) async {
      final server = _PvServer(await visualSetUp(s));
      prep?.call(server);
      ApiClient.dio.httpClientAdapter = server;
      await pumpVisual(t, d,
          home: (_) => Builder(
              builder: (c) => Scaffold(
                  body: Center(child: TextButton(onPressed: () => showMovementsSheet(c, _sub), child: const Text('افتح'))))));
      await settle(t, seconds: 1);
      await t.tap(find.text('افتح'));
      await settle(t, seconds: 2);
      return server;
    }

    testWidgets('الزرّ على سطر التسديد وحده، و«الدين بعدها» بإشارته — ثمّ الإلغاء يرجّع الدين وسطره باسمه', (t) async {
      final server = await open(t, s1bSasOwner);
      expect(server.statusCalls.single.toSet(), {900001, 770745});
      expect(find.byType(PaymentVoidRowButton), findsNWidgets(2), reason: 'تسديدان — لا زرّ على التفعيل');
      // 🐛 الدين سالبٌ عند الخادم — كان يُعرض «رصيد دائن» أخضر
      expect(find.text('الدين بعدها: 35,000 د.ع'), findsOneWidget);
      expect(find.text('الدين بعدها: 95,000 د.ع'), findsOneWidget);
      expect(find.text('لا دين بعدها'), findsOneWidget);
      expect(find.textContaining('رصيد دائن'), findsNothing);
      await shoot(t, s1bSasOwner, 'pay_void_movements', phone, server.inner as VisualServer);

      // تسديد 35,000 (لا إضافة دينٍ بعده): لا اختيار — إرجاع الدين
      await t.tap(find.byType(PaymentVoidRowButton).first);
      await settle(t, seconds: 1);
      expect(server.previews, [900001]);
      expect(find.text('ماذا صار بدين المشترك بعد هذا التسديد؟'), findsNothing);
      expect(find.text('يرجع الدين 35,000 د.ع على المشترك.'), findsOneWidget);
      expect(find.textContaining('من حساب'), findsOneWidget);
      expect(find.textContaining('ضمن تسوية #3'), findsOneWidget);
      await shoot(t, s1bSasOwner, 'pay_void_sheet_plain', phone, server.inner as VisualServer);
      await t.tap(find.text('تأكيد الإلغاء'));
      await settle(t, seconds: 2);
      expect(server.posts.single.$2, {'payment_id': 900001, 'expect_amount': 35000, 'expect_subscriber': 'ali.kareem'},
          reason: 'اليوزر والمبلغ المعروضان — وبلا mode');
      expect(find.textContaining('رجع الدين 35,000 د.ع'), findsOneWidget);

      // الكشف من جديد: سطر الإلغاء باسمه ودينه بعده، والتسديد بشارته بلا زرّ
      expect(server.statementGets, 2);
      expect(find.text('إلغاء تسديد'), findsOneWidget);
      expect(find.text('ملغى'), findsOneWidget);
      expect(find.text('الدين بعدها: 35,000 د.ع'), findsNWidgets(2));
      expect(find.byType(PaymentVoidRowButton), findsOneWidget);
      await settle(t, seconds: 4);
      await shoot(t, s1bSasOwner, 'pay_void_movements_after', phone, server.inner as VisualServer);

      // الفلتر: سطر الإلغاء مع «إضافة دين» لا مع «تسديد»
      await t.tap(find.text('تسديد'));
      await t.pump();
      expect(find.text('إلغاء تسديد'), findsNothing);
      expect(find.text('تسديد دين'), findsNWidgets(2));
      await t.tap(find.text('إضافة دين'));
      await t.pump();
      expect(find.text('إلغاء تسديد'), findsOneWidget);
      expect(find.text('تسديد دين'), findsNothing);
    });

    testWidgets('لم يؤكّد الساس إرجاع الدين: لا «فشل» ولا «نجح» — المدير يحسم من النافذة («رجع» · «ما رجع»)', (t) async {
      final server = await open(t, s1bSasOwner);
      server.nextRun = (409, {'success': false, 'code': 'OUTCOME_UNKNOWN', 'message': 'لم يتأكّد إرجاع الدين', 'void_id': 7, 'payment_id': 900001});
      await t.tap(find.byType(PaymentVoidRowButton).first);
      await settle(t, seconds: 1);
      await t.tap(find.text('تأكيد الإلغاء'));
      await settle(t, seconds: 1);
      expect(find.textContaining('الساس لم يؤكّد إرجاع الدين'), findsOneWidget);
      expect(find.text('تأكيد الإلغاء'), findsNothing, reason: 'لا إعادة قبل الحسم');
      expect(find.text('الدين رجع — سجّل الإلغاء'), findsOneWidget);
      expect(find.text('ما رجع — التسديد كما كان'), findsOneWidget);
      await shoot(t, s1bSasOwner, 'pay_void_sheet_resolve', phone, server.inner as VisualServer);

      await t.tap(find.text('الدين رجع — سجّل الإلغاء'));
      await settle(t, seconds: 2);
      expect(server.posts.last.$1, '/api/v2/payment-voids/7/resolve');
      expect(server.posts.last.$2, {'applied': true});
      expect(find.textContaining('سُجّل الإلغاء'), findsOneWidget);
      expect(find.text('ملغى'), findsOneWidget);
      await settle(t, seconds: 4);
    });

    testWidgets('«بانتظار حسم» من جلسةٍ سابقة: الشارة على السطر، وزرّه يفتح الحسم — و«ما رجع» يُسقط القيد', (t) async {
      final server = await open(t, s1bSasOwner, prep: (s) => s.voids[900001] = {...s._voidItem(900001, 35000, status: 'unknown'), 'void_id': 9});
      expect(find.text('بانتظار حسم'), findsOneWidget);
      expect(find.byType(PaymentVoidRowButton), findsNWidgets(2));
      await t.tap(find.byType(PaymentVoidRowButton).first);
      await settle(t, seconds: 1);
      expect(find.text('ما رجع — التسديد كما كان'), findsOneWidget);
      await t.tap(find.text('ما رجع — التسديد كما كان'));
      await settle(t, seconds: 2);
      expect(server.posts.single.$1, '/api/v2/payment-voids/9/resolve');
      expect(server.posts.single.$2, {'applied': false});
      expect(find.textContaining('التسديد كما كان'), findsOneWidget);
      expect(find.text('بانتظار حسم'), findsNothing);
      expect(find.byType(PaymentVoidBadge), findsNothing);
      await settle(t, seconds: 4);
    });

    testWidgets('أضيق هاتف: الشارة والزرّ في سطر النوع بلا فيض', (t) async {
      final server = await open(t, s1bSasOwner, d: _narrow, prep: (s) {
        s.voids[900001] = {...s._voidItem(900001, 35000, status: 'unknown'), 'void_id': 9};
        s.statement = [
          for (final x in s.statement)
            if (x['id'] == 900001) {...x, 'amount': 1250000} else x,
        ];
      });
      expect(find.text('بانتظار حسم'), findsOneWidget);
      await shoot(t, s1bSasOwner, 'pay_void_movements', _narrow, server.inner as VisualServer);
    });

    testWidgets('الداكن: الكشف بعد الإلغاء — بلا استثناء', (t) async {
      final server = await open(t, s1bSasOwner, d: phoneDark, prep: (s) => s._applyVoid(900001, mode: 'restore'));
      expect(find.text('إلغاء تسديد'), findsOneWidget);
      await shoot(t, s1bSasOwner, 'pay_void_movements_after', phoneDark, server.inner as VisualServer);
    });

    testWidgets('الموظّف بلا صلاحيّة: القفل بمكانه — النقر رسالةٌ لا نافذة', (t) async {
      final server = await open(t, _elEmployee, prep: (s) {
        s.canVoid = false;
        s.ownOnly = true;
      });
      expect(find.descendant(of: find.byType(PaymentVoidRowButton), matching: find.byIcon(LucideIcons.lock)), findsNWidgets(2));
      await shoot(t, _elEmployee, 'pay_void_movements_locked', phone, server.inner as VisualServer);
      await t.tap(find.byType(PaymentVoidRowButton).first);
      await t.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('ليس لديك صلاحيّة لهذا الإجراء'), findsOneWidget);
      expect(server.previews, isEmpty);
      await settle(t, seconds: 3);
    });

    testWidgets('الميزة مطفأةٌ للصفحة ⇒ الكشف كما كان: لا زرّ ولا شارة', (t) async {
      await open(t, s1bSasOwner, prep: (s) => s.enabled = false);
      expect(find.byType(PaymentVoidRowButton), findsNothing);
      expect(find.byType(PaymentVoidBadge), findsNothing);
      expect(find.text('تسديد دين'), findsNWidgets(2));
    });
  });

  group('الحركات (السجلّ وآخر النشاطات)', () {
    test('المنفّذ المعروض من ألغى: السطر منسوبٌ لمن استلم التسديد، وصاحب الصفحة هو من ألغاه', () {
      // صاحب الصفحة ألغى تسديد الموظّف (voided_by_employee_id: null)
      final byOwner = {
        'id': 830142, 'action_type': 'BALANCE_DEDUCT', 'created_at': '2026-11-11T14:22:34Z', 'amount': -60000,
        'action_description': 'إلغاء تسديد دين 60,000 د.ع للمشترك ali.kareem — ألغاه المدير mahdi، استلمه الموظّف hussein',
        'admin_username': 'mahdi', 'acting_employee_full_name': 'حسين مهدي', 'acting_employee_username': 'hussein',
        'pay_void': true, 'voided_by': 'mahdi', 'voided_by_employee_id': null,
      };
      expect(voidedByManager(byOwner), isTrue);
      final f = FinanceLog.fromJson(byOwner)!;
      expect((f.actingEmployeeFullName, f.actingEmployeeUsername, f.adminUsername, f.amount), (null, null, 'mahdi', -60000));
      final a = ActivityRow.fromJson(byOwner)!;
      expect((a.actingEmployeeFullName, a.adminUsername), (null, 'mahdi'));
      // سطر تسوية الربط كذلك (الخادم يعلّمه pay_void_link)
      expect(voidedByManager({'pay_void_link': 1, 'voided_by_employee_id': null}), isTrue);
      // الموظّف ألغى تسديده هو: المنفّذ هو
      final own = {...byOwner, 'voided_by': 'hussein', 'voided_by_employee_id': 3};
      expect(voidedByManager(own), isFalse);
      expect(FinanceLog.fromJson(own)!.actingEmployeeFullName, 'حسين مهدي');
      expect(ActivityRow.fromJson(own)!.actingEmployeeFullName, 'حسين مهدي');
      // سطرٌ عاديّ (وخادمٌ أقدم لا يرسل الحقول): كما كان
      final pay = {...byOwner, 'amount': 60000}..remove('pay_void')..remove('voided_by')..remove('voided_by_employee_id');
      expect(voidedByManager(pay), isFalse);
      expect(FinanceLog.fromJson(pay)!.actingEmployeeFullName, 'حسين مهدي');
      expect(FinanceLog.fromJson(pay)!.actingEmployeeUsername, 'hussein');
    });

    testWidgets('«آخر النشاطات» تطلب سطر الإلغاء صراحةً (include_voids) — الخادم لا يعيده لتطبيقٍ لا يعرفه', (t) async {
      final server = _PvServer(await visualSetUp(s1bSasOwner));
      ApiClient.dio.httpClientAdapter = server;
      addTearDown(visualTearDown);
      final r = await t.runAsync(DashboardApi.fetchDailyActivations);
      expect(r, isNotNull);
      expect(server.feedQueries.single['include_payments'], '1');
      expect(server.feedQueries.single['include_voids'], '1');
    });

    testWidgets('«آخر النشاطات»: الإلغاء باسمه ومبلغه ومن ألغاه — لا «تسديد دين» بمبلغه باسم الموظّف', (t) async {
      final server = await visualSetUp(s1bSasOwner);
      addTearDown(visualTearDown);
      final items = <Map<String, dynamic>>[
        // صاحب الصفحة ألغى تسديداً استلمه الموظّف حسين (السطر منسوبٌ لحسين)
        {
          'id': 830142, 'action_type': 'BALANCE_DEDUCT', 'created_at': DateTime.now().toUtc().toIso8601String(),
          'action_description': 'إلغاء تسديد دين 60,000 د.ع للمشترك ali.kareem — ألغاه المدير mahdi، استلمه الموظّف hussein',
          'target_name': 'ali.kareem', 'user_username': 'ali.kareem', 'user_firstname': 'علي', 'user_lastname': 'كريم',
          'admin_username': 'mahdi', 'acting_employee_id': 3, 'acting_employee_username': 'hussein', 'acting_employee_full_name': 'حسين مهدي',
          'pay_void': true, 'void_amount': 60000, 'voided_by': 'mahdi', 'voided_by_employee_id': null,
        },
        // موظّفٌ ألغى تسديده هو
        {
          'id': 830150, 'action_type': 'BALANCE_DEDUCT', 'created_at': DateTime.now().toUtc().toIso8601String(),
          'action_description': 'إلغاء تسديد دين 25,000 د.ع للمشترك sara.net — ألغاه الموظّف hussein',
          'target_name': 'sara.net', 'user_username': 'sara.net', 'admin_username': 'mahdi',
          'acting_employee_id': 3, 'acting_employee_username': 'hussein', 'acting_employee_full_name': 'حسين مهدي',
          'pay_void': 1, 'void_amount': '25000.00', 'voided_by': 'hussein', 'voided_by_employee_id': 3,
        },
        // تسديدٌ عاديّ — كما كان
        {
          'id': 830100, 'action_type': 'BALANCE_DEDUCT', 'created_at': DateTime.now().toUtc().toIso8601String(),
          'action_description': 'تسديد دين 35,000 د.ع للمشترك omar.fiber', 'target_name': 'omar.fiber', 'user_username': 'omar.fiber',
          'admin_username': 'mahdi', 'acting_employee_id': null,
        },
      ];
      await pumpVisual(t, phone, home: (_) => Scaffold(body: SafeArea(child: SingleChildScrollView(child: RecentActivities(items: items)))));
      await settle(t, seconds: 1);
      expect(find.text('إلغاء تسديد'), findsNWidgets(2));
      expect(find.text('60,000 د.ع'), findsOneWidget);
      expect(find.text('25,000 د.ع'), findsOneWidget);
      expect(find.text('المدير: mahdi'), findsNWidgets(2), reason: 'إلغاء صاحب الصفحة، والتسديد العاديّ له');
      expect(find.text('الموظف: حسين مهدي'), findsOneWidget, reason: 'إلغاء الموظّف لتسديده هو فقط');
      expect(find.text('تسديد دين'), findsOneWidget, reason: 'التسديد العاديّ وحده');
      expect(find.text('35,000 د.ع'), findsOneWidget);
      await shoot(t, s1bSasOwner, 'pay_void_home_feed', phone, server);
    });
  });

  group('التقارير', () {
    testWidgets('سطر السجلّ: تسديدٌ بمبلغٍ سالب «إلغاء تسديد» أحمر بسالبه، وسطر الربط «تسوية إلغاء تسديد»', (t) async {
      await visualSetUp(s1bSasOwner);
      addTearDown(visualTearDown);
      await pumpVisual(t, phone,
          home: (_) => const Scaffold(
                body: Column(children: [
                  ReportLogTile(
                      actionType: 'BALANCE_DEDUCT',
                      description: 'إلغاء تسديد دين 60,000 د.ع للمشترك ali.kareem',
                      amount: -60000,
                      createdAt: '2026-11-11T12:30:00Z'),
                  ReportLogTile(
                      actionType: 'BALANCE_ADD',
                      description: 'تسوية إلغاء تسديد 60,000 د.ع للمشترك ali.kareem',
                      amount: -60000,
                      createdAt: '2026-11-11T12:30:00Z'),
                  ReportLogTile(
                      actionType: 'BALANCE_DEDUCT',
                      description: 'تسديد دين 35,000 د.ع للمشترك sara.net',
                      amount: 35000,
                      createdAt: '2026-11-10T13:40:00Z'),
                  ReportLogTile(
                      actionType: 'DEBT_PAY', description: 'من دفتر الشركة', amount: -15000, createdAt: '2026-11-10T13:40:00Z'),
                  // كشف دفتر ايرث لنك: حركة الإرجاع «إضافة دين» بمبلغها، ووصفها ملاحظة الدفتر بوسمها الداخليّ
                  ReportLogTile(
                      actionType: 'BALANCE_ADD',
                      description: 'إلغاء تسديد 25,000 د.ع — حركة #900001 [pv:900001]',
                      amount: 25000,
                      createdAt: '2026-11-10T13:40:00Z'),
                ]),
              ));
      await settle(t, seconds: 1);
      expect(find.text('إلغاء تسديد'), findsNWidgets(3));
      expect(find.text('-25,000 د.ع'), findsOneWidget, reason: 'ايرث لنك: بمبلغه الموجب سالباً أحمر');
      expect(find.text('إلغاء تسديد 25,000 د.ع — حركة #900001'), findsOneWidget, reason: 'بلا الوسم الداخليّ');
      expect(find.textContaining('[pv:'), findsNothing);
      expect(find.text('-60,000 د.ع'), findsOneWidget);
      expect(find.text('-15,000 د.ع'), findsOneWidget);
      expect(find.text('تسوية إلغاء تسديد'), findsOneWidget);
      expect(find.text('60,000 د.ع'), findsOneWidget, reason: 'التسوية بلا سالب');
      expect(find.text('تسديد دين'), findsOneWidget);
      expect(find.text('35,000 د.ع'), findsOneWidget);
    });
  });
}
