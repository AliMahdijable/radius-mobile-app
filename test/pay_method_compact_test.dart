import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/bulk_activate_api.dart';
import 'package:rad_mysvcs/api/cards_api.dart';
import 'package:rad_mysvcs/core/widgets/design_sheet.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/national/national_wallet_topup_sheet.dart';
import 'package:rad_mysvcs/screens/subscribers/sheets/activate_sheet.dart';
import 'package:rad_mysvcs/screens/subscribers/sheets/add_subscriber_sheet.dart';
import 'package:rad_mysvcs/screens/subscribers/sheets/bulk_activate_sheet.dart';
import 'package:rad_mysvcs/screens/subscribers/sheets/extend_sheet.dart';
import 'package:rad_mysvcs/services/merged_mode.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:rad_mysvcs/services/provider_service.dart';

import 'sim_el/sim_harness.dart';

/// أزرار «طريقة التفعيل/الدفع» صغيرةٌ كـ«نقدي / دين / جزئي» بكلّ الشيتات (المالك ٢٤ نوفمبر: «الحجم جبير مال الزر نسقه مثل البقية»
/// ثمّ «تمام طبقه» بعد صور قبل/بعد): تفعيل الساس (رصيد | كارت)، الوطنيّ («الدفع للمشروع الوطني»)، ايرث لنك، التمديد (الرصيد |
/// النقاط)، الجماعيّ (لكلّ مشترك)، مشترك جديد بايرث لنك (صفّان)، تعبئة محفظة مشترك الوطنيّ. وتسميةٌ لا تتّسع تنزل سطراً ثانياً لا
/// تُقصّ — قاعدة المالك: لا نصّ يُقصّ من ٣٢٠ إلى ٤٨٠ × ١٫٢ (كانت «محفظة المشترك» و«رصيد أونلاين» تُقصّان بالبلاطات الكبيرة).
const _devices = <(String, double, bool, double)>[
  ('480', 480, true, 1.0),
  ('360', 360, true, 1.0),
  ('320×1.2', 320, false, 1.2),
];

Subscriber _sub(String idx) => Subscriber.fromJson({
      'idx': idx,
      'username': 'demo$idx',
      'firstname': 'مشترك',
      'lastname': 'تجريبيّ',
      'profile_id': 7,
      'profile_name': 'Light',
      'phone': '07700000000',
      'expiration': '2026-11-20 10:00:00',
    });

Future<void> _open(WidgetTester t, double width, bool dark, double scale, void Function(BuildContext) open) async {
  if (scale != 1.0) {
    t.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
  }
  await pumpSim(t, SimVariant(width, dark: dark), home: (_) => simLauncher(open), settle: false);
  t.view.physicalSize = Size(width, 1500);
  for (var i = 0; i < 5; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
  await t.tap(find.text(simOpenLabel));
  for (var i = 0; i < 40; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

/// كلّ صفوف الاختيار بالشيت صغيرة، ولا تسمية مقصوصة («…»)، وبعرضٍ يتّسع (٤٨٠ بخطٍّ عاديّ) سطرٌ واحد بارتفاع «نقدي/دين/جزئي».
void _expectCompact(WidgetTester t, String where, {required int rows, required bool oneLine}) {
  final tiles = find.byType(SheetChoiceTiles);
  expect(tiles, findsNWidgets(rows), reason: '$where: صفوف الاختيار');
  for (final w in t.widgetList<SheetChoiceTiles>(tiles)) {
    expect(w.compact, isTrue, reason: '$where: «${w.labels.join(' | ')}» كبيرة — كانت أيقونةً فوق التسمية');
  }
  final cut = <String>[];
  for (final e in find.descendant(of: tiles, matching: find.byType(RichText)).evaluate()) {
    final r = e.renderObject;
    if (r is RenderParagraph && r.didExceedMaxLines) cut.add(r.text.toPlainText());
  }
  expect(cut, isEmpty, reason: '$where: تسمياتٌ مقصوصة');
  if (oneLine) {
    for (final e in tiles.evaluate()) {
      final h = (e.renderObject! as RenderBox).size.height;
      expect(h, lessThan(52), reason: '$where: ارتفاع الصفّ $h (الكبيرة ~٧٠)');
    }
  }
  expect(t.takeException(), isNull, reason: '$where: فيض');
}

Future<void> _done(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 30));
}

void main() {
  setUpAll(simSetUpAll);
  tearDown(() {
    PermissionsService.debugReset();
    ProviderService.debugSet(null);
  });

  for (final (dev, width, dark, scale) in _devices) {
    final oneLine = width >= 480 && scale == 1.0;

    testWidgets('تفعيل الساس @$dev: «طريقة التفعيل» و«طريقة الدفع» صغيرتان', (t) async {
      final server = await simSetUp(secure: {'auth.admin_id': '2', 'auth.admin_username': 'admin'});
      PermissionsService.debugSet(isEmployee: false);
      ProviderService.debugSet(null);
      CardsState.reset();
      server.reply('GET', '/api/v2/subscribers/55/activation-data', 200, {
        'success': true,
        'data': {
          'idx': '55', 'username': 'demo55', 'profile_id': 7, 'profile_name': 'Light', 'profile_duration': '30',
          'user_price': 30000, 'price_after_discount': 30000, 'base_price': 30000, 'manager_cost': 12000,
          'current_balance': 0, 'manager_balance': 2450000, 'reward_points': 1,
          'activation_methods': {'credit': true, 'card': true},
          'cards': {'enabled': true, 'profile_id': 7, 'profile_name': 'Light', 'available': 3},
        },
      });
      await _open(t, width, dark, scale, (c) => showActivateSheet(c, _sub('55')));
      expect(find.text('طريقة التفعيل'), findsOneWidget);
      _expectCompact(t, 'تفعيل الساس $dev', rows: 2, oneLine: oneLine);
      await _done(t);
    });

    testWidgets('تفعيل الوطنيّ @$dev: «الدفع للمشروع الوطني» بثلاثة صغيرة و«محفظة المشترك» كاملة', (t) async {
      final server = await simSetUp(secure: {'auth.admin_id': 'watani:15742', 'auth.admin_username': 'owner'});
      ApiClient.dio.httpClientAdapter = server;
      PermissionsService.debugSet(isEmployee: false);
      ProviderService.debugSet('watani', label: 'المشروع الوطني');
      MergedMode.reset();
      server.reply('GET', '/api/v2/subscribers/555/activation-data', 200, {
        'success': true,
        'data': {
          'idx': '555', 'username': 'demo555', 'profile_name': 'Basic', 'profile_id': 11, 'user_price': 40000,
          'price_after_discount': 40000, 'base_price': 40000, 'current_balance': 0, 'manager_balance': 478000,
          'provider': 'watani', 'provider_label': 'المشروع الوطني',
          'packages': [{'id': 11, 'name': 'Basic', 'price': 40000, 'cost': 35000, 'days': 30}],
          'package_change_allowed': false, 'package_change_timing': ['now'], 'card_payment': true,
          'customer_wallet': {'balance': 50000, 'price': 35000, 'enough': true, 'topup': true},
        },
      });
      await _open(t, width, dark, scale, (c) => showActivateSheet(c, _sub('555')));
      expect(find.text('محفظة المشترك'), findsOneWidget);
      _expectCompact(t, 'تفعيل الوطني $dev', rows: 2, oneLine: oneLine);
      await _done(t);
    });

    testWidgets('تفعيل ايرث لنك @$dev: «رصيد أونلاين | كارت» صغيرة', (t) async {
      final server = await simSetUp(secure: {'auth.admin_id': 'earthlink:5', 'auth.admin_username': 'owner'});
      ProviderService.debugSet('earthlink');
      CardsState.reset();
      server.reply('GET', '/api/v2/subscribers/56/activation-data', 200, {
        'success': true,
        'data': {
          'idx': '56', 'username': 'demo56@el', 'provider': 'earthlink', 'profile_id': 7, 'profile_name': 'Economy',
          'user_price': 35000, 'base_price': 35000, 'price_after_discount': 35000, 'manager_cost': 20000,
          'current_balance': 0, 'manager_balance': 250000, 'reward_points': 0, 'expiration': '2026-11-20 10:00:00',
          'activation_methods': {'credit': true, 'deposit': true, 'card': true},
          'cards': {'enabled': false, 'profile_id': 7, 'profile_name': 'Economy', 'available': null},
          'packages': [
            {'id': 7, 'name': 'Economy', 'price': 35000, 'cost': 20000},
          ],
          'package_change_allowed': true,
        },
      });
      await _open(t, width, dark, scale, (c) => showActivateSheet(c, _sub('56')));
      expect(find.text('رصيد أونلاين'), findsOneWidget);
      _expectCompact(t, 'تفعيل ايرث لنك $dev', rows: 2, oneLine: oneLine);
      await _done(t);
    });

    testWidgets('التمديد @$dev: «الرصيد | النقاط» صغيرة', (t) async {
      final server = await simSetUp(secure: {'auth.admin_id': '2', 'auth.admin_username': 'admin'});
      PermissionsService.debugSet(isEmployee: false);
      ProviderService.debugSet(null);
      server.reply('GET', '/api/v2/subscribers/57/extension-options', 200, {
        'success': true,
        'data': {
          'idx': '57', 'current_profile_id': 7, 'current_profile_name': 'Light', 'manager_balance': 2450000,
          'reward_points_balance': 5,
          'packages': [
            {'id': 9, 'name': 'يوم واحد', 'price': 1000, 'reward_points_required': 1, 'duration': 1},
          ],
        },
      });
      await _open(t, width, dark, scale, (c) => showExtendSheet(c, _sub('57')));
      _expectCompact(t, 'التمديد $dev', rows: 1, oneLine: oneLine);
      await _done(t);
    });

    testWidgets('التجديد الجماعيّ @$dev: «نقدي | دين | جزئي» صغيرة لكلّ مشترك', (t) async {
      final server = await simSetUp(secure: {'auth.admin_id': '2', 'auth.admin_username': 'admin'});
      PermissionsService.debugSet(isEmployee: false);
      ProviderService.debugSet(null);
      BulkActivateApi.reset();
      addTearDown(BulkActivateApi.reset);
      server.reply('GET', BulkActivateApi.path, 200, {
        'success': true,
        'data': {
          'provider': 'sas4', 'supported': true, 'code': 'OK', 'reason': null, 'method': 'credit', 'checked': true,
          'limits': {'max_batch': 100, 'prefetch_concurrency': 4, 'run_concurrency': 1},
        },
      });
      for (final i in ['61', '62', '63']) {
        server.reply('GET', '/api/v2/subscribers/$i/activation-data', 200, {
          'success': true,
          'data': {
            'idx': i, 'username': 'demo$i', 'user_price': 25000, 'price_after_discount': 25000, 'base_price': 25000,
            'current_balance': 0, 'manager_balance': 1000000, 'profile_name': 'Light', 'profile_id': 7,
          },
        });
      }
      await _open(t, width, dark, scale, (c) => showBulkActivateSheet(c, subs: [_sub('61'), _sub('62'), _sub('63')]));
      _expectCompact(t, 'الجماعي $dev', rows: 3, oneLine: oneLine);
      await _done(t);
    });

    testWidgets('مشترك جديد بايرث لنك @$dev: «طريقة الإضافة» و«طريقة الدفع» صغيرتان و«رصيد أونلاين» كاملة', (t) async {
      final server = await simSetUp(secure: {'auth.admin_id': 'earthlink:5', 'auth.admin_username': 'owner'});
      ProviderService.debugSet(null);
      server.reply('GET', '/api/v2/el/create-options', 200, {
        'success': true,
        'data': {
          'user_suffix': '@el',
          'packages': [
            {'id': '7', 'name': 'Economy', 'price': 35000, 'cost_price': 20000},
          ],
          'deposit_balance': 100000,
          'test_count': 2,
          'methods': {'deposit': true, 'card': true, 'test': true},
        },
      });
      await _open(t, width, dark, scale, (c) => showAddSubscriberSheet(c));
      expect(find.text('رصيد أونلاين'), findsOneWidget);
      _expectCompact(t, 'مشترك جديد ايرث لنك $dev', rows: 2, oneLine: oneLine);
      await _done(t);
    });

    testWidgets('تعبئة محفظة مشترك الوطنيّ @$dev: «طريقة دفع المشترك» صغيرة', (t) async {
      final server = await simSetUp(secure: {'auth.admin_id': 'watani:15742', 'auth.admin_username': 'owner'});
      ApiClient.dio.httpClientAdapter = server;
      PermissionsService.debugSet(isEmployee: false);
      ProviderService.debugSet('watani', label: 'المشروع الوطني');
      MergedMode.reset();
      server.reply('GET', '/api/v2/ftth/subscriptions/555/wallet/topup', 200, {
        'success': true,
        'data': {
          'transfer': {'ok': true, 'reason': null},
          'card': {'ok': true, 'reason': null},
          'partner_balance': 1250000,
          'customer_balance': 0,
          'target': {'name': 'مشترك تجريبيّ', 'phone': '•••0000'},
          'limits': {'min': 1000, 'max': 1000000, 'step': 250},
          'recent': null,
        },
      });
      await _open(t, width, dark, scale, (c) => showNationalWalletTopupSheet(c, sid: '555', companyKey: null));
      expect(find.text('طريقة دفع المشترك'), findsOneWidget);
      _expectCompact(t, 'تعبئة محفظة الوطني $dev', rows: 1, oneLine: oneLine);
      await _done(t);
    });
  }
}
