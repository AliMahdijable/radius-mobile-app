import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/screens/el/transfer_screen.dart';
import 'package:rad_mysvcs/services/provider_service.dart';

import 'sim_harness.dart';

/// محاكاة «تحويل الرصيد + كشف الحساب» لايرث لنك (`el/transfer_screen.dart`).
///
/// ما يُحرس فوق الرسم:
///   • التحويل: أدنى ٥٬٠٠٠، والحقول كلّها، والنجاح يمسح المبلغ ويُحدّث الرصيد.
///   • كشف الحساب: `POST /api/v2/el/account-statement` وباسورد الإيداع في
///     **الجسم** — لا GET، ولا كلمة السرّ في الرابط أو الاستعلام (سجلّات
///     nginx/كلاودفلير تحفظ الروابط نصّاً صريحاً).
///   • صفوف الكشف بأطوالها الحقيقيّة على ٣٢٠، وبنصوص ايرث لنك كما تصل.
const _screen = 'el_transfer';
const _statementPath = '/api/v2/el/account-statement';
const _transferPath = '/api/v2/el/transfer';
const _secret = 'Dep#4417secret';

/// صفوف الكشف بعد تعريب الخادم (الحالة المثاليّة) — أطوالٌ حقيقيّة.
const _statementRows = [
  {
    'id': 90011,
    'description': 'تجديد المشترك ali1@alnoor-net — Economy',
    'user_id': 'ali1@alnoor-net',
    'display_name': 'علي حسن الموسوي',
    'operation': 'Withdraw',
    'deposit': 0,
    'withdrawal': 20000,
    'balance': 1230000,
    'date': '2026-10-13 14:22:05',
    'serials': '',
    'reseller_user': 'alnoor-net',
  },
  {
    'id': 90010,
    'description': 'إيداع رصيد من الشركة',
    'user_id': '',
    'display_name': '',
    'operation': 'Deposit',
    'deposit': 500000,
    'withdrawal': 0,
    'balance': 1250000,
    'date': '2026-10-12 09:00:41',
    'serials': '',
    'reseller_user': 'alnoor-net',
  },
  {
    'id': 90009,
    'description': 'تحويل رصيد إلى وكيل الكرادة الشرقيّة — حسين علي عبد الأمير',
    'user_id': '',
    'display_name': 'وكيل الكرادة الشرقيّة — حسين علي عبد الأمير الموسوي',
    'operation': 'Withdraw',
    'deposit': 0,
    'withdrawal': 150000,
    'balance': 750000,
    'date': '2026-10-11 18:45:30',
    'serials': '',
    'reseller_user': 'alnoor-net',
  },
];

/// الصفوف كما يمرّرها الخادم من ايرث لنك حرفيّاً (EARTHLINK_RESELLER_API.md:
/// `description("Refill user")`، `operation("Withdraw"/"Deposit")`، والوصف قد
/// يصل فارغاً — earthlinkAdapter.getAccountStatement: `t.description || ''`).
const _providerRows = [
  {
    'id': 90021,
    'description': 'Refill user',
    'user_id': 'ehab@najaf40',
    'display_name': 'ايهاب كاظم',
    'operation': 'Withdraw',
    'deposit': 0,
    'withdrawal': 20000,
    'balance': 980000,
    'date': '2026-10-11 22:23:52',
    'serials': '',
    'reseller_user': 'najaf40',
  },
  {
    'id': 90020,
    'description': '',
    'user_id': '',
    'display_name': '',
    'operation': 'Deposit',
    'deposit': 250000,
    'withdrawal': 0,
    'balance': 1000000,
    'date': '2026-10-11 09:10:00',
    'serials': '',
    'reseller_user': 'najaf40',
  },
];

void main() {
  late SimServer server;

  setUpAll(simSetUpAll);

  setUp(() async {
    server = await simSetUp();
    ProviderService.debugSet('earthlink');
    server.reply('GET', '/api/v2/admin-widgets', 200, {
      'success': true,
      'balance': 1250000,
      'points': 3,
      'cards': {'remaining': null},
    });
    server.reply('GET', '/api/v2/el/transfer-targets', 200, {
      'success': true,
      'data': [
        {'affiliateIndex': 201, 'affiliateName': 'najaf40'},
        {'affiliateIndex': 202, 'affiliateName': 'وكيل الكرادة الشرقيّة — حسين علي'},
        {'affiliateIndex': 203, 'affiliateName': 'alnoor-karbala'},
        {'affiliateIndex': 204, 'affiliateName': 'مكتب الحلّة'},
        {'affiliateIndex': 205, 'affiliateName': 'basra-ashar'},
        {'affiliateIndex': 206, 'affiliateName': 'وكيل الديوانية'},
        {'affiliateIndex': 207, 'affiliateName': 'kut-net'},
        {'affiliateIndex': 208, 'affiliateName': 'وكيل السماوة الجديد'},
      ],
    });
    server.reply('POST', _transferPath, 200, {
      'success': true,
      'message': 'تمّ تحويل 10,000 د.ع إلى najaf40',
    });
    server.reply('POST', _statementPath, 200, {
      'success': true,
      'data': _statementRows,
      'total': _statementRows.length,
    });
  });

  Future<void> open(WidgetTester t, SimVariant v) async {
    await pumpSim(t, v, home: (_) => const ElTransferScreen());
    expect(find.text('تحويل الرصيد'), findsOneWidget);
  }

  Future<void> reveal(WidgetTester t, Finder f) async {
    await t.ensureVisible(f);
    await t.pumpAndSettle();
  }

  /// الحقلان «كلمة سرّ الإيداع» بنفس التلميح: الأوّل للتحويل والثاني للكشف.
  Finder pass(int i) => find.widgetWithText(TextField, '••••••').at(i);

  Finder amountField() => find.byType(TextField).first;

  bool buttonEnabled(WidgetTester t, String label) {
    final ink = t.widget<InkWell>(find
        .ancestor(of: find.text(label), matching: find.byType(InkWell))
        .first);
    return ink.onTap != null;
  }

  Future<void> pickTarget(WidgetTester t, String name) async {
    await reveal(t, find.text('اختر الموزّع'));
    await t.tap(find.text('اختر الموزّع'));
    await t.pumpAndSettle();
    await t.tap(find.text(name).last);
    await t.pumpAndSettle();
  }

  Future<void> fillTransfer(WidgetTester t, {String amount = '10000'}) async {
    await t.enterText(amountField(), amount);
    await t.pumpAndSettle();
    await pickTarget(t, 'najaf40');
    await t.enterText(pass(0), 'dep-pass');
    await t.pumpAndSettle();
  }

  Future<void> showStatement(WidgetTester t, {String password = _secret}) async {
    await reveal(t, pass(1));
    await t.enterText(pass(1), password);
    await t.pumpAndSettle();
    await reveal(t, find.text('عرض كشف الحساب'));
    await t.tap(find.text('عرض كشف الحساب'));
    await t.pumpAndSettle();
  }

  // ─────────────────────────── التحويل ───────────────────────────

  simCase(_screen, 'loaded', (t, v) async {
    await open(t, v);
    expect(find.text('1,250,000'), findsOneWidget);
    expect(find.text('اختر الموزّع'), findsOneWidget);
    expect(buttonEnabled(t, 'تحويل'), isFalse);
    await simCheck(t, v, _screen, 'loaded');
  });

  simCase(_screen, 'target_picker', (t, v) async {
    await open(t, v);
    await reveal(t, find.text('اختر الموزّع'));
    await t.tap(find.text('اختر الموزّع'));
    await t.pumpAndSettle();
    expect(find.text('بحث'), findsOneWidget, reason: 'أكثر من ستّ ⇒ بحث');
    await simCheck(t, v, _screen, 'target_picker');
    await t.enterText(find.widgetWithText(TextField, 'بحث'), 'وكيل');
    await t.pumpAndSettle();
    expect(find.text('najaf40'), findsNothing);
    expect(find.text('وكيل الديوانية'), findsOneWidget);
  });

  simCase(_screen, 'filled_ready', (t, v) async {
    await open(t, v);
    await fillTransfer(t);
    expect(find.text('10,000'), findsOneWidget);
    expect(buttonEnabled(t, 'تحويل'), isTrue);
    await reveal(t, find.text('تحويل'));
    await simCheck(t, v, _screen, 'filled_ready');
  });

  simCase(_screen, 'amount_below_min', (t, v) async {
    await open(t, v);
    await fillTransfer(t, amount: '4000');
    expect(buttonEnabled(t, 'تحويل'), isFalse, reason: 'أدنى ٥٬٠٠٠');
    expect(find.text('أدنى مبلغ للتحويل 5,000 د.ع'), findsOneWidget);
    await reveal(t, find.text('تحويل'));
    await simCheck(t, v, _screen, 'amount_below_min');
  });

  simCase(_screen, 'transfer_ok', (t, v) async {
    await open(t, v);
    await fillTransfer(t);
    await reveal(t, find.text('تحويل'));
    await t.tap(find.text('تحويل'));
    await t.pumpAndSettle();
    final body = server.bodies('POST', _transferPath).single;
    expect(body, {
      'amount': 10000,
      'targetAffiliateIndex': 201,
      'depositPassword': 'dep-pass',
    });
    final req = server.calls('POST', _transferPath).single;
    expect(req.uri.query, isEmpty);
    expect(Uri.decodeFull(req.uri.toString()), isNot(contains('dep-pass')));
    expect(find.text('تمّ تحويل 10,000 د.ع إلى najaf40'), findsOneWidget);
    expect(find.text('10,000'), findsNothing, reason: 'المبلغ مُسح');
    expect(server.calls('GET', '/api/v2/admin-widgets'), hasLength(2),
        reason: 'الرصيد أُعيد جلبه');
    await simCheck(t, v, _screen, 'transfer_ok');
    await simDrain(t);
  });

  simCase(_screen, 'transfer_failed', (t, v) async {
    server.reply('POST', _transferPath, 400, {
      'success': false,
      'message': 'فشل التحويل: باسورد الإيداع غير صحيح',
    });
    await open(t, v);
    await fillTransfer(t);
    await reveal(t, find.text('تحويل'));
    await t.tap(find.text('تحويل'));
    await t.pumpAndSettle();
    expect(find.text('فشل التحويل: باسورد الإيداع غير صحيح'), findsOneWidget);
    expect(find.text('10,000'), findsOneWidget, reason: 'المبلغ باقٍ');
    await simCheck(t, v, _screen, 'transfer_failed');
    await simDrain(t);
  });

  simCase(_screen, 'targets_failed', (t, v) async {
    server.reply('GET', '/api/v2/el/transfer-targets', 503,
        {'success': false, 'message': 'توكن EarthLink غير متوفر'});
    await open(t, v);
    expect(find.text('لا وجهات متاحة'), findsOneWidget);
    expect(find.text('توكن EarthLink غير متوفر'), findsOneWidget);
    await simCheck(t, v, _screen, 'targets_failed');
    await simDrain(t);
  });

  simCase(_screen, 'balance_unavailable', (t, v) async {
    server.reply('GET', '/api/v2/admin-widgets', 503, {'success': false});
    await open(t, v);
    expect(find.text('—'), findsOneWidget);
    await simCheck(t, v, _screen, 'balance_unavailable');
  });

  // ─────────────────────────── كشف الحساب ───────────────────────────

  /// العقد وحده (كشفٌ فارغ — بمعزلٍ عن تخطيط الصفوف): POST، والباسورد في
  /// الجسم، ولا أثر له في أيّ رابطٍ أو استعلام.
  simCase(_screen, 'statement_post_contract', (t, v) async {
    server.reply('POST', _statementPath, 200,
        {'success': true, 'data': <Object>[], 'total': 0});
    await open(t, v);
    await showStatement(t);
    final calls = server.calls('POST', _statementPath);
    expect(calls, hasLength(1));
    final req = calls.single;
    expect(req.method, 'POST');
    expect(req.uri.path, _statementPath);
    expect(req.uri.query, isEmpty);
    expect(req.queryParameters, isEmpty);
    final body = Map<String, dynamic>.from(req.data as Map);
    expect(body['depositPassword'], _secret);
    expect(body['startIndex'], 0);
    expect(body['rowCount'], 50);
    expect(server.calls('GET', _statementPath), isEmpty, reason: 'لا GET');
    for (final r in server.requests) {
      final url = Uri.decodeFull(r.uri.toString());
      expect(url, isNot(contains(_secret)),
          reason: 'كلمة السرّ في رابط ${r.method} ${r.path}');
      expect(r.headers.values.map((h) => '$h').join(' '),
          isNot(contains(_secret)),
          reason: 'كلمة السرّ في ترويسة ${r.method} ${r.path}');
    }
    await reveal(t, find.text('لا توجد حركات في كشف الحساب'));
    await simCheck(t, v, _screen, 'statement_post_contract');
  });

  simCase(_screen, 'statement_rows', (t, v) async {
    await open(t, v);
    await showStatement(t);
    // العقد: POST وباسورد الإيداع في الجسم — لا في الرابط ولا الاستعلام.
    final req = server.calls('POST', _statementPath).single;
    expect(req.method, 'POST');
    expect(req.uri.query, isEmpty);
    expect(req.queryParameters, isEmpty);
    expect(req.uri.toString(), isNot(contains(_secret)));
    expect(Uri.decodeFull(req.uri.toString()), isNot(contains(_secret)));
    expect((req.data as Map)['depositPassword'], _secret);
    expect(server.calls('GET', _statementPath), isEmpty, reason: 'لا GET');
    for (final r in server.requests) {
      expect(Uri.decodeFull(r.uri.toString()), isNot(contains(_secret)),
          reason: 'كلمة السرّ لا تظهر في أيّ رابط (${r.method} ${r.path})');
    }
    expect(find.text('تجديد المشترك ali1@alnoor-net — Economy'), findsOneWidget);
    expect(find.text('+500,000'), findsOneWidget);
    expect(find.text('-150,000'), findsOneWidget);
    await reveal(t, find.text('+500,000'));
    await simCheck(t, v, _screen, 'statement_rows');
    // الطرف (اسم المشترك) هو ما يُقرأ في الكشف: اسمٌ قصير يجب أن يظهر كاملاً.
    final party = t.renderObject<RenderParagraph>(find.text('علي حسن الموسوي'));
    expect(party.didExceedMaxLines, isFalse,
        reason: 'اسم المشترك في صفّ الكشف مقصوصٌ إلى «…» '
            '(عرضه ${party.size.width.toStringAsFixed(0)}px)');
  });

  simCase(_screen, 'statement_provider_text', (t, v) async {
    server.reply('POST', _statementPath, 200, {
      'success': true,
      'data': _providerRows,
      'total': _providerRows.length,
    });
    await open(t, v);
    await showStatement(t);
    await reveal(t, find.text('+250,000'));
    await simCheck(t, v, _screen, 'statement_provider_text');
    // نصوص ايرث لنك الإنجليزيّة كما تصل — لا يجوز أن تُعرض خاماً.
    final raw = simVisibleTexts()
        .where((s) => const ['Refill user', 'Withdraw', 'Deposit'].contains(s))
        .toList();
    expect(raw, isEmpty,
        reason: 'وصف/نوع حركة ايرث لنك يُعرض إنجليزيّاً خاماً في الكشف: $raw');
  });

  simCase(_screen, 'statement_empty', (t, v) async {
    server.reply('POST', _statementPath, 200,
        {'success': true, 'data': <Object>[], 'total': 0});
    await open(t, v);
    await showStatement(t);
    expect(find.text('لا توجد حركات في كشف الحساب'), findsOneWidget);
    await reveal(t, find.text('لا توجد حركات في كشف الحساب'));
    await simCheck(t, v, _screen, 'statement_empty');
  });

  simCase(_screen, 'statement_error', (t, v) async {
    const msg = 'تعذّر جلب كشف الحساب — تحقّق من باسورد الإيداع';
    server.reply('POST', _statementPath, 400, {'success': false, 'message': msg});
    await open(t, v);
    await showStatement(t, password: 'wrong');
    expect(find.text(msg), findsNWidgets(2), reason: 'السطر + الإشعار');
    await reveal(t, find.text(msg).first);
    await simCheck(t, v, _screen, 'statement_error');
    await simDrain(t);
  });

  simCase(_screen, 'statement_no_password', (t, v) async {
    await open(t, v);
    await reveal(t, find.text('عرض كشف الحساب'));
    await t.tap(find.text('عرض كشف الحساب'));
    await t.pumpAndSettle();
    expect(find.text('أدخل كلمة سرّ الإيداع أوّلاً'), findsOneWidget);
    expect(server.calls('POST', _statementPath), isEmpty);
    await simCheck(t, v, _screen, 'statement_no_password');
    await simDrain(t);
  });
}
