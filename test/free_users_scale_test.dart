import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/free_users_api.dart';
import 'package:rad_mysvcs/screens/free_users/free_users_screen.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';

import 'sim_el/sim_harness.dart';

/// «اليوزرات الفري» بذوق المالك («لا نصّ يخرج ولا رقم يُقصّ» — ٣٢٠ إلى ٤٨٠ بخطٍّ ×١٫٢، فاتحاً وداكناً): القائمة كلّها حتى آخر بطاقة،
/// ونوافذ البيع (بالجزئيّ) والتعديل والسجلّ والتسديد — بلا فيضٍ ولا استثناء.

Map<String, dynamic> _item(int id, String state, String name, String user, int price, {int? debt}) => {
      'id': id,
      'idx': '${1000 + id}',
      'username': user,
      'sub_name': name,
      'sub_phone': '07702223333',
      'price': price,
      'state': state,
      'paid_until': state == 'pending' ? null : '2026-12-26 12:33',
      'minutes_left': state == 'expired' ? -300 : 43000,
      'sas_enabled': 1,
      'last_error': null,
      'fail_count': state == 'active' && id == 2 ? 3 : 0,
      'holder_from': '2026-11-26 12:30',
      if (debt != null) 'debt': debt,
      if (debt != null) 'debt_source': 'ledger',
    };

void main() {
  setUpAll(simSetUpAll);
  tearDown(PermissionsService.debugReset);

  for (final w in const [320.0, 360.0, 390.0, 430.0, 480.0]) {
    for (final dark in const [false, true]) {
      testWidgets('@${w.toInt()} ${dark ? 'داكن' : 'فاتح'} ×1.2: القائمة ونوافذها بلا فيض', (t) async {
        t.platformDispatcher.textScaleFactorTestValue = 1.2;
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
        FreeUsersState.reset();
        PermissionsService.debugSet(isEmployee: false);
        final server = await simSetUp(secure: {'auth.admin_id': '2251', 'auth.admin_username': 'admin@poox'});
        server.reply('GET', '/api/v2/free-users', 200, {
          'success': true,
          'enabled': true,
          'family': 'sas4',
          'test': true,
          'summary': {
            'active': 2,
            'expired': 1,
            'pending': 1,
            'ending_soon': 12,
            'last30': {'sales': 148, 'total': 12450000, 'paid': 9870000, 'debt': 2580000},
          },
          'items': [
            _item(1, 'active', 'محمد علي', 'review@poox', 35000, debt: 0),
            _item(2, 'active', 'عبد الرحمن عبد الكريم الموسوي البغدادي', 'admin@laith7-very-long-username', 1250000, debt: 2500000),
            _item(3, 'expired', 'علاء رمح', 'free77@x', 30000),
            _item(4, 'pending', 'ابو بشير', 'free78@x', 25000),
          ],
        });
        server.reply('GET', '/api/v2/free-users/2/debt', 200, {'success': true, 'balance': -2500000, 'source': 'ledger'});
        server.reply('GET', '/api/v2/free-users/2/history', 200, {
          'success': true,
          'sales': [
            {'id': 9, 'months': 12, 'total': 15000000, 'method': 'partial', 'paid': 12500000, 'debt': 2500000,
              'paid_until_after': '2027-11-26 12:33:00', 'created_at': '2026-11-26 12:33:00'},
          ],
          'events': [
            {'kind': 'drift_enabled', 'created_at': '2026-11-26 13:10:00'},
            {'kind': 'ended_notice', 'created_at': '2026-11-26 13:11:00'},
          ],
        });
        await pumpSim(t, SimVariant(w, dark: dark), home: (_) => const FreeUsersScreen());
        await t.pumpAndSettle();
        expect(t.takeException(), isNull, reason: 'أعلى القائمة');
        for (var i = 0; i < 6; i++) {
          await t.drag(find.byType(ListView), const Offset(0, -500));
          await t.pumpAndSettle();
          expect(t.takeException(), isNull, reason: 'التمرير $i');
        }
        // للأعلى ثانيةً: البطاقات البعيدة تُبنى حين تقترب (ListView كسول)
        await t.drag(find.byType(ListView), const Offset(0, 4000));
        await t.pumpAndSettle();
        Future<void> sheet(String key, String name) async {
          final f = find.byKey(ValueKey('free-btn-$key'));
          // البطاقة الثانية قد لا تكون مبنيّةً بعد (أطول بالخطّ ×١٫٢) ⇒ تمريرٌ حتى تظهر
          await t.scrollUntilVisible(f, 250, scrollable: find.byType(Scrollable).first, maxScrolls: 40);
          await t.pumpAndSettle();
          await t.tap(f);
          await t.pumpAndSettle();
          expect(t.takeException(), isNull, reason: name);
        }

        await sheet('sell-2', 'نافذة البيع');
        await t.tap(find.text('جزئي'));
        await t.tap(find.text('12 شهراً'));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull, reason: 'البيع بالجزئيّ ١٢ شهراً');
        Navigator.of(t.element(find.text('المدّة'))).pop();
        await t.pumpAndSettle();
        await sheet('more-2', 'إجراءات أخرى');
        expect(find.text('إجراءات أخرى'), findsOneWidget);
        await t.tap(find.byKey(const ValueKey('free-btn-edit-2')));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull, reason: 'نافذة التعديل');
        Navigator.of(t.element(find.text('اسم المشترك'))).pop();
        await t.pumpAndSettle();
        await sheet('hist-2', 'نافذة السجلّ');
        Navigator.of(t.element(find.text('المبيعات'))).pop();
        await t.pumpAndSettle();
        // بلوك الدين (عليه 2,500,000) بزرّ «تسديد» على البطاقة نفسها
        expect(find.byKey(const ValueKey('free-debt-2')), findsOneWidget);
        await sheet('pay-2', 'نافذة التسديد باسم الحامل');
        expect(find.text('تسديد دين'), findsOneWidget);
        await simDrain(t);
      });
    }
  }
}
