import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/cards_api.dart';
import 'package:rad_mysvcs/api/el_deposit_password.dart';
import 'package:rad_mysvcs/api/subscribers_api.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/el/deposit_password_sheet.dart';
import 'package:rad_mysvcs/screens/subscribers/sheets/activate_sheet.dart';
import 'package:rad_mysvcs/screens/subscribers/subscribers_screen.dart';
import 'package:rad_mysvcs/screens/subscribers/widgets/sort_sheet.dart';
import 'package:rad_mysvcs/services/active_company.dart';
import 'package:rad_mysvcs/services/provider_service.dart';
import 'package:rad_mysvcs/services/subscriber_usage_store.dart';

import 'sim_harness.dart';

/// محاكاة 160: باسورد إيداع ايرث لنك المحفوظ (التفعيل + الإعدادات) و«عرض
/// الاستهلاك» بقائمة المشتركين. اللقطات في `shots/el_deposit/` و`shots/el_usage/`.
const _deposit = 'el_deposit';
const _usage = 'el_usage';
const _activatePath = '/api/v2/subscribers/55/activate';
const _statusPath = '/api/v2/el/deposit-password';

Subscriber _sub() => Subscriber.fromJson({
      'idx': '55',
      'username': 'ali1@alnoor-net',
      'firstname': 'علي',
      'lastname': 'حسن الموسوي',
      'profile_id': 7,
      'profile_name': 'Economy',
      'expiration': '2026-10-12 10:00:00',
    });

Map<String, Object?> _row(int idx, String user, String first, String last,
        {bool online = false, int remaining = 20}) =>
    {
      'idx': '$idx',
      'username': user,
      'firstname': first,
      'lastname': last,
      'phone': '0770${1000000 + idx}',
      'profile_name': 'Economy',
      'profile_id': 7,
      'expiration': '2026-11-02 10:00:00',
      'remaining_days': remaining,
      'online_status': online ? 1 : 0,
      'enabled': 1,
    };

void main() {
  late SimServer server;

  setUpAll(simSetUpAll);

  void status({required bool saved, bool manage = true}) =>
      server.reply('GET', _statusPath, 200, {
        'success': true,
        'data': {
          'saved': saved,
          'updated_at': saved ? '2026-10-16T08:00:00.000Z' : null,
          'can_manage': manage,
        },
      });

  void activationData() =>
      server.reply('GET', '/api/v2/subscribers/55/activation-data', 200, {
        'success': true,
        'data': {
          'idx': '55',
          'username': 'ali1@alnoor-net',
          'provider': 'earthlink',
          'profile_id': 7,
          'profile_name': 'Economy',
          'user_price': 35000,
          'base_price': 35000,
          'discount_amount': 0,
          'price_after_discount': 35000,
          'price_source': 'normal',
          'needs_repricing': false,
          'manager_cost': 20000,
          'current_balance': 0,
          'manager_balance': 250000,
          'reward_points': 0,
          'expiration': '2026-10-12 10:00:00',
          'activation_methods': {'credit': true, 'deposit': true, 'card': true},
          'cards': {'enabled': false, 'profile_id': 7, 'available': null},
          'packages': const [
            {'id': 7, 'name': 'Economy', 'price': 35000, 'cost': 20000},
          ],
          'package_change_allowed': true,
        },
      });

  setUp(() async {
    server = await simSetUp();
    ProviderService.debugSet('earthlink');
    CardsState.reset();
    ElDepositPassword.reset();
    SubscriberUsageStore.reset();
    activationData();
  });

  Future<void> openActivate(WidgetTester t, SimVariant v) async {
    await pumpSim(t, v,
        home: (_) => simLauncher((c) => showActivateSheet(c, _sub())));
    await simOpen(t);
    expect(find.text('تجديد اشتراك'), findsOneWidget);
  }

  Future<void> reveal(WidgetTester t, Finder f) async {
    await t.ensureVisible(f);
    await t.pumpAndSettle();
  }

  bool footerEnabled(WidgetTester t, String label) {
    final ink = t.widget<InkWell>(find
        .ancestor(of: find.text(label), matching: find.byType(InkWell))
        .first);
    return ink.onTap != null;
  }

  Finder field(String hint) => find.widgetWithText(TextField, hint);
  const savedText = 'باسورد الإيداع محفوظ — لا حاجة لإدخاله';

  // ═══════════════════════════ التفعيل ═══════════════════════════

  simCase(_deposit, 'activate_saved', (t, v) async {
    status(saved: true);
    server.reply('POST', _activatePath, 200, {'success': true, 'deposit_password_saved': true});
    await openActivate(t, v);
    expect(find.text(savedText), findsOneWidget);
    expect(find.text('تغيير'), findsOneWidget);
    expect(field('باسورد الإيداع'), findsNothing);
    expect(footerEnabled(t, 'تجديد الآن'), isTrue, reason: 'المحفوظ يكفي');
    await reveal(t, find.text(savedText));
    await simCheck(t, v, _deposit, 'activate_saved');
    await t.tap(find.text('تجديد الآن'));
    await t.pumpAndSettle();
    final body = server.bodies('POST', _activatePath).single;
    expect(body['method'], 'deposit');
    expect(body.containsKey('depositPassword'), isFalse,
        reason: 'المحفوظ يضيفه الخادم — لا نصّ من التطبيق');
    expect(body.containsKey('rememberDepositPassword'), isFalse);
    await simDrain(t);
  });

  simCase(_deposit, 'activate_owner_input', (t, v) async {
    status(saved: false);
    server.reply('POST', _activatePath, 200, {'success': true, 'deposit_password_saved': true});
    await openActivate(t, v);
    expect(find.text('احفظه فلا يُطلب مرّة أخرى'), findsOneWidget);
    expect(footerEnabled(t, 'تجديد الآن'), isFalse);
    await t.enterText(field('باسورد الإيداع'), 'dep-pass');
    await t.pumpAndSettle();
    expect(footerEnabled(t, 'تجديد الآن'), isTrue);
    await reveal(t, find.text('احفظه فلا يُطلب مرّة أخرى'));
    await simCheck(t, v, _deposit, 'activate_owner_input');
    await t.tap(find.text('تجديد الآن'));
    await t.pumpAndSettle();
    final body = server.bodies('POST', _activatePath).single;
    expect(body['depositPassword'], 'dep-pass');
    expect(body['rememberDepositPassword'], isTrue);
    expect(ElDepositPassword.status.value?.saved, isTrue,
        reason: 'حُفظ مع العمليّة');
    await simDrain(t);
  });

  simCase(_deposit, 'activate_change', (t, v) async {
    status(saved: true);
    await openActivate(t, v);
    await reveal(t, find.text('تغيير'));
    await t.tap(find.text('تغيير'));
    await t.pumpAndSettle();
    expect(field('باسورد الإيداع'), findsOneWidget);
    expect(find.text('احفظ الجديد بدل المحفوظ'), findsOneWidget);
    expect(find.text('استعمال المحفوظ'), findsOneWidget);
    expect(footerEnabled(t, 'تجديد الآن'), isFalse, reason: 'تغييرٌ بلا نصّ');
    await reveal(t, find.text('استعمال المحفوظ'));
    await simCheck(t, v, _deposit, 'activate_change');
    await t.tap(find.text('استعمال المحفوظ'));
    await t.pumpAndSettle();
    expect(find.text(savedText), findsOneWidget);
  });

  simCase(_deposit, 'activate_saved_rejected', (t, v) async {
    status(saved: true);
    const msg = 'باسورد الإيداع المحفوظ لم يعد صحيحاً — أدخله من جديد';
    server.reply('POST', _activatePath, 400, {
      'success': false,
      'code': 'DEPOSIT_PASSWORD',
      'saved_cleared': true,
      'message': msg,
    });
    await openActivate(t, v);
    await t.tap(find.text('تجديد الآن'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text(msg), findsOneWidget);
    await t.pumpAndSettle();
    expect(find.text(savedText), findsNothing, reason: 'مُسح بالخادم');
    expect(field('باسورد الإيداع'), findsOneWidget, reason: 'يعود للإدخال');
    expect(footerEnabled(t, 'تجديد الآن'), isFalse);
    await reveal(t, field('باسورد الإيداع'));
    await simCheck(t, v, _deposit, 'activate_saved_rejected');
    await simDrain(t);
  });

  simCase(_deposit, 'activate_employee_saved', (t, v) async {
    status(saved: true, manage: false);
    await openActivate(t, v);
    expect(find.text(savedText), findsOneWidget);
    expect(find.text('تغيير'), findsNothing, reason: 'الموظّف لا يغيّره');
    await reveal(t, find.text(savedText));
    await simCheck(t, v, _deposit, 'activate_employee_saved');
  });

  simCase(_deposit, 'activate_employee_not_saved', (t, v) async {
    status(saved: false, manage: false);
    await openActivate(t, v);
    expect(find.text('احفظه فلا يُطلب مرّة أخرى'), findsNothing);
    expect(find.text('يستطيع صاحب الحساب حفظه من الإعدادات فلا يُطلب منك.'),
        findsOneWidget);
    await reveal(t, field('باسورد الإيداع'));
    await simCheck(t, v, _deposit, 'activate_employee_not_saved');
  });

  // ═══════════════════════════ الإعدادات ═══════════════════════════

  simCase(_deposit, 'settings_sheet_not_saved', (t, v) async {
    status(saved: false);
    server.reply('PUT', _statusPath, 200, {'success': true, 'message': 'حُفظ باسورد الإيداع'});
    await pumpSim(t, v, home: (_) => simLauncher(showElDepositPasswordSheet));
    await simOpen(t);
    expect(find.text('غير محفوظ — يُطلب في كلّ عمليّة رصيد'), findsOneWidget);
    await t.enterText(find.byType(TextField), 'dep-pass');
    await t.pumpAndSettle();
    await simCheck(t, v, _deposit, 'settings_sheet_not_saved');
    await t.tap(find.text('حفظ'));
    await t.pumpAndSettle();
    expect(server.bodies('PUT', _statusPath).single['depositPassword'], 'dep-pass');
    expect(find.text('محفوظ — يُستعمل تلقائيّاً'), findsOneWidget);
    await simDrain(t);
  });

  simCase(_deposit, 'settings_sheet_saved', (t, v) async {
    status(saved: true);
    await pumpSim(t, v, home: (_) => simLauncher(showElDepositPasswordSheet));
    await simOpen(t);
    expect(find.text('محفوظ — يُستعمل تلقائيّاً'), findsOneWidget);
    expect(find.text('تغيير'), findsOneWidget);
    expect(find.text('مسح'), findsOneWidget);
    await simCheck(t, v, _deposit, 'settings_sheet_saved');
  });

  // ═══════════════════════════ الاستهلاك ═══════════════════════════

  group('عرض الاستهلاك', () {
    setUp(() async {
      SubscribersApi.clearAllCaches();
      await ActiveCompany.saveFromLogin(
        sasUrl: '',
        adminId: 'earthlink:5',
        loginUsername: 'mahdi.el',
        adminUsername: 'mahdi.el',
        isEmployee: false,
        label: 'ايرث لنك (Earthlink)',
        sasCode: 'earthlink',
      );
      server.reply('GET', '/api/v2/subscribers', 200, {
        'success': true,
        'data': [
          _row(1, 'ali1@alnoor-net', 'علي', 'حسن الموسوي', online: true),
          _row(2, 'zainab.k@alnoor-net', 'زينب', 'كاظم', online: true),
          _row(3, 'hussein77@alnoor-net', 'حسين', 'عبد الأمير', remaining: 3),
        ],
      });
      server.reply('GET', '/api/v2/subscribers-usage', 200, {
        'success': true,
        'month': '2026-10',
        'errors': 0,
        'data': {
          '1': {'today': 56695988224, 'month': 1715175661158},
          '2': {'today': 873463808, 'month': 41875931136},
          '3': {'today': 0, 'month': 307232768},
        },
      });
    });
    tearDown(() async {
      await UsagePrefs.setEnabled(false);
      await ActiveCompany.clear();
    });

    Future<void> close(WidgetTester t) async {
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 2));
    }

    simCase(_usage, 'list_usage_on', (t, v) async {
      await UsagePrefs.setEnabled(true);
      await pumpSim(t, v,
          home: (_) => SubscribersScreen(isActive: ValueNotifier<bool>(true)));
      await t.pump(const Duration(seconds: 1));
      await t.pumpAndSettle();
      expect(find.textContaining('52.8 GB'), findsOneWidget);
      expect(find.textContaining('1.56 TB'), findsOneWidget);
      final calls = server.calls('GET', '/api/v2/subscribers-usage');
      expect(calls, hasLength(1), reason: 'دفعةٌ واحدة للصفوف الظاهرة');
      expect(calls.single.queryParameters['ids'], '1,2,3');
      await simCheck(t, v, _usage, 'list_usage_on');
      await close(t);
    });

    simCase(_usage, 'list_usage_off', (t, v) async {
      await pumpSim(t, v,
          home: (_) => SubscribersScreen(isActive: ValueNotifier<bool>(true)));
      await t.pump(const Duration(seconds: 1));
      await t.pumpAndSettle();
      expect(find.textContaining('52.8 GB'), findsNothing);
      expect(server.calls('GET', '/api/v2/subscribers-usage'), isEmpty,
          reason: 'مخفيٌّ افتراضاً — لا نداء');
      await close(t);
    });

    simCase(_usage, 'sort_sheet_toggle', (t, v) async {
      await pumpSim(t, v,
          home: (_) => simLauncher((c) => showSortSheet(c,
              currentField: SortField.remainingDays,
              currentDirection: SortDirection.asc)));
      await simOpen(t);
      expect(find.text('عرض الاستهلاك'), findsOneWidget);
      await t.ensureVisible(find.text('عرض الاستهلاك'));
      await t.tap(find.text('عرض الاستهلاك'));
      await t.pumpAndSettle();
      expect(UsagePrefs.enabled.value, isTrue);
      await simCheck(t, v, _usage, 'sort_sheet_toggle');
    });
  });
}
