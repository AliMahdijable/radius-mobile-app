import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/national_device_api.dart';
import 'package:rad_mysvcs/api/national_portal_api.dart';
import 'package:rad_mysvcs/api/national_sheet_api.dart';
import 'package:rad_mysvcs/screens/national/national_device_sheet.dart';
import 'package:rad_mysvcs/screens/national/national_task_sheet.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:rad_mysvcs/services/provider_service.dart';

import 'sim_el/sim_harness.dart';

/// «تعديل معلومات الجهاز» و«تنصيب الجهاز» للمشروع الوطنيّ في التطبيق (٢ نوفمبر — نسخة الموقع WataniFatEdit/WataniInstall؛ الخادم
/// wataniPortalBeta: subDevice*/subNetwork*/taskInstall*): صفحةٌ واحدة بـ«الحاليّ» وزرّ حفظٍ لكلّ قسم، والرمز الحاليّ نقاطٌ بإظهارٍ ونسخ؛
/// والتنصيب نموذجٌ واحد ⇒ تأكيدٌ ⇒ POST واحد بجسمٍ بالضبط، والكود الخطأ تحت حقله، والموظّف بلا «تعديل المشترك» مقفلٌ بمكانه.
const _v = SimVariant(390, dark: false);
const _sid = '555';
const _task = 'a1b2c3d4-0000-4000-8000-00000000c0de';
const _fdt = '41dc61aa-0000-4c44-aeab-000000000001';
const _fat7 = '85fd9e1b-0000-419e-bc0f-000000000007';
const _zte = 'b0000000-0000-4000-8000-0000000000e2';

Map<String, Object?> _net({bool locked = false}) => {
      'success': true,
      'data': {
        'zone_id': 'FBG2251-2',
        'fdt': {'id': _fdt, 'name': 'FBG2251-2'},
        'fat': {'id': 'f8', 'name': 'FAT8'},
        'locked': locked,
        'fdts': [
          {'id': _fdt, 'name': 'FBG2251-2'},
        ],
        'fats': [
          {'id': _fat7, 'name': 'FAT7'},
          {'id': 'f8', 'name': 'FAT8'},
        ],
      },
    };

Map<String, Object?> _dev({bool hidden = false, bool locked = false, String? lockedMac}) => {
      'success': true,
      'data': {
        'username': 'f0885-555',
        'serial': 'ZTEGC0FFEE01',
        'vendor': {'id': _zte, 'name': 'zte'},
        'mac': '11:22:33:44:55:66',
        'locked_mac': lockedMac,
        'locked': locked,
        'vendors': [
          {'id': 'v-hw', 'name': 'huawei'},
          {'id': _zte, 'name': 'zte'},
        ],
        'password_rule': {'pattern': r'^[a-zA-Z!@#$%^&*()_+{}\[\]:;<>,.?~\-=_|\d]{3,30}$', 'description': 'من ٣ إلى ٣٠ خانة، بلا حروفٍ عربيّة'},
        if (hidden) ...{'password': null, 'password_hidden': true} else 'password': 'Ab12345678',
      },
    };

Map<String, Object?> _install({bool done = false, bool hidden = false}) => {
      'success': true,
      'data': {
        'task': {'id': _task, 'status': done ? 'completed' : 'not started', 'zone': 'FBG2251-2', 'customer': 'حسين علي', 'request_id': null},
        'done': done,
        if (done)
          'saved': {
            'username': 'fbg-user1',
            'password': hidden ? null : 'pw-secret-9',
            if (hidden) 'password_hidden': true,
            'serial': 'ZTEGC0FFEE01',
            'point_supply': '12',
            'vendor': {'id': _zte, 'name': 'zte'},
            'fdt': {'id': _fdt, 'name': 'FBG2251-2'},
            'fat': {'id': _fat7, 'name': 'FAT7'},
          }
        else ...{
          'fdts': [
            {'id': _fdt, 'name': 'FBG2251-2'},
          ],
          'vendors': [
            {'id': 'v-hw', 'name': 'huawei'},
            {'id': _zte, 'name': 'zte'},
          ],
          'username_rule': {'pattern': r'^(?=.*[A-Za-z])(?=.*\d)[A-Za-z\d\-_]{3,30}$', 'description': 'من ٣ إلى ٣٠ خانة: حروفٌ إنكليزيّة وأرقام'},
          'password_rule': {'pattern': r'^[a-zA-Z!@#$%^&*()_+{}\[\]:;<>,.?~\-=_|\d]{3,30}$', 'description': 'من ٣ إلى ٣٠ خانة، بلا حروفٍ عربيّة'},
          'code_required': true,
        },
      },
    };

Map<String, Object?> _taskDetail({String? install = 'open', String status = 'not started'}) => {
      'success': true,
      'data': {
        'id': _task,
        'title': 'Connect Customer',
        'type': 'connect customer',
        'status': status,
        'customer': {'id': '7', 'name': 'حسين علي'},
        'zone': {'id': 'FBG2251-2', 'name': 'FBG2251-2'},
        'comments': [],
        'comments_total': 0,
        'comments_locked': false,
        'can': {'comment': true, 'install': install},
      },
      'fetched_at': '2026-11-02T09:00:00Z',
    };

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 120));
  }
  await t.pumpAndSettle();
}

/// يكتب في حقل النافذة بتسميته (Semantics label) — كلّ حقلٍ لاتينيّ يحملها.
Future<void> _type(WidgetTester t, String label, String text) async {
  final f = find.descendant(of: find.byWidgetPredicate((w) => w is Semantics && w.properties.label == label), matching: find.byType(TextField));
  await t.ensureVisible(f.first);
  await t.enterText(f.first, text);
  await t.pump();
}

Future<void> _pick(WidgetTester t, String fieldText, String option) async {
  final f = find.text(fieldText).last;
  await t.ensureVisible(f);
  await t.tap(f);
  await t.pumpAndSettle();
  await t.tap(find.text(option).last);
  await t.pumpAndSettle();
}

void main() {
  late SimServer server;

  setUpAll(simSetUpAll);

  setUp(() async {
    server = await simSetUp(secure: {'auth.admin_id': 'watani:2963757', 'auth.admin_username': 'owner'});
    NationalSheetApi.debugReset();
    PermissionsService.debugSet(isEmployee: false);
    ProviderService.debugSet('watani', label: 'المشروع الوطني');
  });

  tearDown(() {
    NationalSheetApi.debugReset();
    PermissionsService.debugReset();
    ProviderService.debugSet(null);
  });

  group('النماذج', () {
    test('ردّ الحفظ: 202 «لم يتأكّد»، والنجاح بنتيجته، والرفض بنصّ البوّابة ومرجعها، والقفل لا يُعدّ حفظاً', () {
      final u = NationalDeviceApi.editOf({'success': false, 'code': 'UNCONFIRMED', 'message': 'لم يتأكّد'}, status: 202);
      expect((u.unconfirmed, u.message), (true, 'لم يتأكّد'));
      final a = NationalDeviceApi.editOf({'success': true, 'outcome': 'applied', 'message': 'تمّ'});
      expect((a.ok, a.applied, a.outcome), (true, true, 'applied'));
      expect(NationalDeviceApi.editOf({'success': true}).outcome, 'accepted');
      final c = NationalDeviceApi.editOf(
          {'success': false, 'code': 'INVALID_CODE', 'message': 'كود التفعيل غير صحيح', 'portal_message': 'Invalid installation code', 'request_ref': 'req-77'});
      expect((c.ok, c.code, c.text), (false, 'INVALID_CODE', 'كود التفعيل غير صحيح\nInvalid installation code\nreq-77'));
      final l = NationalDeviceApi.editOf({'success': false, 'code': 'FTTH_FORBIDDEN', 'locked': true, 'title': 'لا صلاحيّة', 'message': 'لا صلاحيّة «تنصيب الجهاز»'});
      expect((l.ok, l.unconfirmed, l.message), (false, false, 'لا صلاحيّة «تنصيب الجهاز»'));
    });

    test('القراءة: pending ⇒ ok(null)، والقفل قفلٌ، والمطفأ فشلٌ برمزه', () {
      expect(NationalDeviceApi.readOf({'success': true, 'pending': true}).data, isNull);
      expect(NationalDeviceApi.readOf({'success': true, 'pending': true}).ok, isTrue);
      expect(NationalDeviceApi.readOf({'success': false, 'locked': true, 'message': 'x'}).locked, isTrue);
      final off = NationalDeviceApi.readOf({'success': false, 'code': 'INSTALL_OFF', 'message': 'غير مفعّل'});
      expect((off.ok, off.code, off.error), (false, 'INSTALL_OFF', 'غير مفعّل'));
    });

    test('lookups: fat_edit وdevice_edit وinstall_edit، وcan.install للمهمّة', () {
      final b = NationalBeta.fromJson({'beta': true, 'fat_edit': true, 'device_edit': false, 'install_edit': true});
      expect((b.fatEdit, b.deviceEdit, b.installEdit), (true, false, true));
      expect(NationalTaskDetail.fromJson(Map<String, dynamic>.from(_taskDetail()['data'] as Map)).install, 'open');
      expect(NationalTaskDetail.fromJson(Map<String, dynamic>.from(_taskDetail(install: 'done')['data'] as Map)).install, 'done');
      expect(NationalTaskDetail.fromJson({'title': 'x', 'status': 'x', 'can': {'install': 'weird'}}).install, isNull);
    });

    test('الشرط: نمط البوّابة، والاحتياط حين لا نمط، والنمط الذي لا يفهمه Dart يمرّ', () {
      final r = NationalRule.from({'pattern': r'^(?=.*[A-Za-z])(?=.*\d)[A-Za-z\d\-_]{3,30}$'})!;
      expect((r.passes('fbg-user1'), r.passes('ab'), r.passes('ابن-1')), (true, false, false));
      expect(const NationalRule().passes('x', fallback: RegExp(r'^\d+$')), isFalse);
      expect(const NationalRule(pattern: '(?<bad').passes('x'), isTrue);
    });
  });

  group('«تعديل معلومات الجهاز»', () {
    Future<void> open(WidgetTester t, {bool fatOn = true, bool devOn = true}) async {
      await pumpSim(t, _v,
          home: (_) => simLauncher((c) => showNationalDeviceSheet(c, sid: _sid, name: 'مريم', fatOn: fatOn, devOn: devOn)));
      await simOpen(t);
      await _settle(t);
    }

    testWidgets('صفحةٌ واحدة: الفات والسيريال والماك والرمز والنوع بـ«الحاليّ»، والرمز نقاطٌ يظهر بالعين', (t) async {
      server.reply('GET', '/api/v2/ftth/subscriptions/$_sid/network', 200, _net());
      server.reply('GET', '/api/v2/ftth/subscriptions/$_sid/device', 200, _dev());
      await open(t);
      expect(find.text('تعديل معلومات الجهاز'), findsOneWidget);
      expect(find.text('f0885-555'), findsOneWidget);
      for (final s in ['الفات', 'السيريال', 'الماك', 'الرمز', 'نوع الجهاز']) {
        expect(find.text(s), findsWidgets, reason: s);
      }
      expect(find.text('FBG2251-2 ← FAT8'), findsOneWidget);
      expect(find.text('ZTEGC0FFEE01'), findsWidgets); // الحاليّ + الحقل يبدأ به
      expect(find.text('Ab12345678'), findsNothing);
      expect(find.text('••••••••'), findsOneWidget);
      await t.ensureVisible(find.byTooltip('إظهار الرمز'));
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('إظهار الرمز'));
      await t.pump();
      expect(find.text('Ab12345678'), findsOneWidget);
      // النسخ إلى الحافظة
      final copied = <String>[];
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied.add(((call.arguments as Map)['text']).toString());
        return null;
      });
      await t.tap(find.byTooltip('نسخ الرمز'));
      await t.pump();
      expect(copied, ['Ab12345678']);
      await simDrain(t);
    });

    testWidgets('حفظ السيريال: PUT {field, value} مرّةً ثمّ تُقرأ المعلومات ثانيةً؛ والسيريال الحاليّ نفسه لا يُرسل', (t) async {
      server.reply('GET', '/api/v2/ftth/subscriptions/$_sid/network', 200, _net());
      server.reply('GET', '/api/v2/ftth/subscriptions/$_sid/device', 200, _dev());
      server.reply('PUT', '/api/v2/ftth/subscriptions/$_sid/device', 200, {'success': true, 'outcome': 'applied'});
      await open(t);
      final save = find.text('حفظ السيريال');
      await t.ensureVisible(save);
      await t.tap(save);
      await t.pump();
      expect(server.calls('PUT', '/api/v2/ftth/subscriptions/$_sid/device'), isEmpty, reason: 'الحاليّ نفسه');
      await _type(t, 'السيريال الجديد', 'zteg12345678');
      expect(find.text('ZTEG12345678'), findsOneWidget, reason: 'حروفٌ كبيرة');
      final before = server.calls('GET', '/api/v2/ftth/subscriptions/$_sid/device').length;
      await t.ensureVisible(save);
      await t.tap(save);
      await _settle(t);
      expect(server.bodies('PUT', '/api/v2/ftth/subscriptions/$_sid/device').single, {'field': 'serial', 'value': 'ZTEG12345678'});
      expect(server.calls('GET', '/api/v2/ftth/subscriptions/$_sid/device').length, before + 1);
      await simDrain(t);
    });

    testWidgets('حفظ الرمز والفات: جسم البوّابة بالضبط، والرمز يُمسح بعد الحفظ', (t) async {
      server.reply('GET', '/api/v2/ftth/subscriptions/$_sid/network', 200, _net());
      server.reply('GET', '/api/v2/ftth/subscriptions/$_sid/device', 200, _dev());
      server.reply('PUT', '/api/v2/ftth/subscriptions/$_sid/device', 200, {'success': true, 'outcome': 'accepted', 'message': 'قبلت البوّابة الرمز الجديد'});
      server.reply('PUT', '/api/v2/ftth/subscriptions/$_sid/network', 200, {'success': true, 'outcome': 'applied'});
      await open(t);
      await _type(t, 'الرمز الجديد', 'NewPass99');
      final savePw = find.text('حفظ الرمز');
      await t.ensureVisible(savePw);
      await t.tap(savePw);
      await _settle(t);
      expect(server.bodies('PUT', '/api/v2/ftth/subscriptions/$_sid/device').single, {'field': 'password', 'value': 'NewPass99'});
      expect(find.text('NewPass99'), findsNothing, reason: 'يُمسح الحقل بعد الحفظ');
      await _pick(t, 'FAT8', 'FAT7');
      final saveFat = find.text('حفظ الفات');
      await t.ensureVisible(saveFat);
      await t.tap(saveFat);
      await _settle(t);
      expect(server.bodies('PUT', '/api/v2/ftth/subscriptions/$_sid/network').single, {'fdt_id': _fdt, 'fat_id': _fat7});
      await simDrain(t);
    });

    testWidgets('الموظّف بلا «تعديل المشترك»: الرمز «محجوب»؛ وعناصر الشبكة المقفلة تُقال ولا زرّ للسيريال', (t) async {
      server.reply('GET', '/api/v2/ftth/subscriptions/$_sid/device', 200, _dev(hidden: true, locked: true));
      await open(t, fatOn: false);
      expect(find.textContaining('محجوب'), findsOneWidget);
      expect(find.textContaining('البوّابة تمنع تغيير السيريال'), findsOneWidget);
      expect(find.text('حفظ السيريال'), findsNothing);
      expect(server.calls('GET', '/api/v2/ftth/subscriptions/$_sid/network'), isEmpty, reason: 'الفات غير مفتوح');
      await simDrain(t);
    });
  });

  group('«تنصيب الجهاز»', () {
    Future<void> openTask(WidgetTester t) async {
      await pumpSim(t, _v,
          home: (_) => simLauncher((c) => showNationalTaskSheet(c, const NationalTask(id: _task, title: 'Connect Customer', status: 'not started'))));
      await simOpen(t);
      await _settle(t);
    }

    Future<void> fill(WidgetTester t, {String code = 'AB12CD'}) async {
      await _type(t, 'اسم مستخدم الجهاز', 'fbg-user1');
      await t.pump(const Duration(milliseconds: 800)); // فحص الاسم بعد التوقّف عن الكتابة
      await _settle(t);
      await _type(t, 'رمز الجهاز', 'Pw12345');
      await _type(t, 'رقم توريد النقطة', '12');
      await _pick(t, 'اختر الفات', 'FAT7');
      await _type(t, 'سيريال الجهاز', 'ztegc0ffee01');
      await _pick(t, 'اختر نوع الجهاز', 'zte');
      await _type(t, 'كود التفعيل', code);
    }

    void routes({Object? postReply}) {
      server.reply('GET', '/api/v2/ftth/tasks/$_task', 200, _taskDetail());
      server.reply('GET', '/api/v2/ftth/tasks/$_task/install', 200, _install());
      server.reply('GET', '/api/v2/ftth/tasks/$_task/install/fats', 200, {
        'success': true,
        'data': [
          {'id': _fat7, 'name': 'FAT7'},
          {'id': 'f8', 'name': 'FAT8'},
        ],
      });
      server.reply('GET', '/api/v2/ftth/tasks/$_task/install/username', 200, {'success': true, 'username': 'fbg-user1', 'valid': true, 'taken': false});
      server.reply('POST', '/api/v2/ftth/tasks/$_task/install', postReply == null ? 200 : 409,
          postReply ?? {'success': true, 'outcome': 'applied', 'message': 'تمّ التنصيب — المهمّة مكتملة'});
    }

    testWidgets('المهمّة المفتوحة: «تنصيب الجهاز» ⇒ النموذج ⇒ تأكيدٌ بملخّص ⇒ POST واحد بجسمٍ بالضبط ⇒ تُقرأ المهمّة ثانيةً', (t) async {
      routes();
      await openTask(t);
      expect(find.text('تنصيب الجهاز'), findsOneWidget);
      await t.tap(find.text('تنصيب الجهاز'));
      await _settle(t);
      expect(find.text('رقم توريد النقطة (HTWC)'), findsOneWidget);
      expect(find.text('FBG2251-2'), findsWidgets, reason: 'FDT الوحيد يُختار تلقائيّاً');
      await fill(t);
      expect(find.text('الاسم متاح'), findsOneWidget);
      final before = server.calls('GET', '/api/v2/ftth/tasks/$_task').length;
      await t.tap(find.text('تأشير كمكتمل'));
      await t.pumpAndSettle();
      expect(find.text('تأكيد التنصيب'), findsOneWidget);
      expect(find.textContaining('ZTEGC0FFEE01'), findsWidgets);
      expect(server.calls('POST', '/api/v2/ftth/tasks/$_task/install'), isEmpty, reason: 'لا شيء قبل التأكيد');
      await t.tap(find.text('تأكيد وإرسال'));
      await _settle(t);
      expect(server.bodies('POST', '/api/v2/ftth/tasks/$_task/install').single, {
        'username': 'fbg-user1',
        'password': 'Pw12345',
        'point_supply': '12',
        'serial': 'ZTEGC0FFEE01',
        'vendor_id': _zte,
        'fdt_id': _fdt,
        'fat_id': _fat7,
        'code': 'AB12CD',
      });
      expect(find.text('رمز الجهاز'), findsNothing, reason: 'أُغلقت نافذة التنصيب');
      expect(server.calls('GET', '/api/v2/ftth/tasks/$_task').length, greaterThan(before));
      await simDrain(t);
    });

    testWidgets('كود التفعيل الخطأ: الرسالة تحت حقله ونصّ البوّابة، والنافذة باقية بقيمها', (t) async {
      routes(postReply: {
        'success': false,
        'code': 'INVALID_CODE',
        'message': 'كود التفعيل غير صحيح — لم يُسجَّل شيء',
        'portal_message': 'Invalid installation code',
        'request_ref': 'req-77',
      });
      await openTask(t);
      await t.tap(find.text('تنصيب الجهاز'));
      await _settle(t);
      await fill(t, code: 'BAD1');
      await t.tap(find.text('تأشير كمكتمل'));
      await t.pumpAndSettle();
      await t.tap(find.text('تأكيد وإرسال'));
      await _settle(t);
      expect(server.calls('POST', '/api/v2/ftth/tasks/$_task/install').length, 1);
      expect(find.textContaining('كود التفعيل غير صحيح'), findsWidgets);
      expect(find.textContaining('Invalid installation code'), findsWidgets);
      expect(find.text('BAD1'), findsOneWidget, reason: 'القيم باقية للتصحيح');
      await simDrain(t);
    });

    testWidgets('النموذج الناقص لا يُرسل: «تأشير كمكتمل» يبيّن الحقول ولا تأكيد', (t) async {
      routes();
      await openTask(t);
      await t.tap(find.text('تنصيب الجهاز'));
      await _settle(t);
      await t.tap(find.text('تأشير كمكتمل'));
      await t.pumpAndSettle();
      expect(find.text('تأكيد التنصيب'), findsNothing);
      expect(find.text('اكتب اسم مستخدم الجهاز'), findsOneWidget);
      expect(find.text('اكتب كود التفعيل (بلا مسافات)'), findsOneWidget);
      expect(server.calls('POST', '/api/v2/ftth/tasks/$_task/install'), isEmpty);
      await simDrain(t);
    });

    testWidgets('الاسم المستخدم من قبل يُقال تحت حقله', (t) async {
      routes();
      server.reply('GET', '/api/v2/ftth/tasks/$_task/install/username', 200,
          {'success': true, 'username': 'taken-1', 'valid': false, 'taken': true, 'message': 'اسم مستخدم الجهاز هذا مستخدمٌ من قبل — اختر غيره'});
      await openTask(t);
      await t.tap(find.text('تنصيب الجهاز'));
      await _settle(t);
      await _type(t, 'اسم مستخدم الجهاز', 'taken-1');
      await t.pump(const Duration(milliseconds: 800));
      await _settle(t);
      expect(find.textContaining('مستخدمٌ من قبل'), findsOneWidget);
      await simDrain(t);
    });

    testWidgets('الموظّف بلا «تعديل المشترك»: الزرّ مقفلٌ بمكانه ولا نافذة', (t) async {
      PermissionsService.debugSet(isEmployee: true, permissions: {'subscribers.view': true});
      routes();
      await openTask(t);
      await t.tap(find.text('تنصيب الجهاز'));
      await _settle(t);
      expect(server.calls('GET', '/api/v2/ftth/tasks/$_task/install'), isEmpty);
      await simDrain(t);
    });

    testWidgets('المكتملة: «معلومات التنصيب» ⇒ ما سُجّل، والرمز نقاط', (t) async {
      server.reply('GET', '/api/v2/ftth/tasks/$_task', 200, _taskDetail(install: 'done', status: 'completed'));
      server.reply('GET', '/api/v2/ftth/tasks/$_task/install', 200, _install(done: true));
      await openTask(t);
      await t.tap(find.text('معلومات التنصيب'));
      await _settle(t);
      expect(find.text('المهمّة مكتملة — هذا ما سُجّل بالتنصيب'), findsOneWidget);
      expect(find.text('fbg-user1'), findsOneWidget);
      expect(find.text('FBG2251-2 ← FAT7'), findsOneWidget);
      expect(find.text('pw-secret-9'), findsNothing);
      expect(find.text('••••••••'), findsOneWidget);
      expect(find.text('تأشير كمكتمل'), findsNothing);
      await simDrain(t);
    });
  });
}
