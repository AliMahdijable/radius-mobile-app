import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/broadcast_api.dart';
import 'package:rad_mysvcs/api/employees_api.dart';
import 'package:rad_mysvcs/api/message_exclusions_api.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/subscribers/widgets/message_exclusion_card.dart';
import 'package:rad_mysvcs/screens/subscribers/widgets/subscriber_card_v3.dart';
import 'package:rad_mysvcs/screens/whatsapp/message_exclusions_screen.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:rad_mysvcs/services/provider_service.dart';

import 'sim_el/sim_harness.dart';

/// «المستثنون من الرسائل» (المالك ١٤ نوفمبر: «نسوي مثل القسم الريجكتد مسج، يعني ذولا ما تروح لهم رسائل… التفعيل، التنبيهات،
/// التذكير، التبليغات» ثمّ «تقسيم… نعم مستثنى»): الخادم يحجب عند كلّ باب إرسال (server/messageExclusions.js)؛ التطبيق يقرأ
/// قائمة الصفحة مرّةً ([MessageExclusionsState])، يعرض «لا تصله: …» بصفحة المشترك وجرساً مشطوباً بجنب اسمه في القائمة، ويحفظ
/// من ورقة «إيقاف الرسائل» (واحداً أو المحدَّدين) ومن صفحة «المستثنون من الرسائل». الميزة مطفأةٌ للحساب ⇒ لا شيء؛ «كل الشركات»
/// (صفٌّ من شركةٍ أخرى) ⇒ لا شيء؛ من لا يُدير يرى «تعديل» بمكانه مقفلاً.
const _v = SimVariant(390, dark: false);
const _all = MessageExclusionsApi.allPath;
const _path = MessageExclusionsApi.path;
const _bulk = MessageExclusionsApi.bulkPath;

const _groups = [
  {'key': 'all', 'label': 'كلّ الرسائل', 'hint': 'لا تصله أيّ رسالة من النظام — ولا اليدويّة'},
  {'key': 'ops', 'label': 'التفعيل والتسديد', 'hint': 'إشعار التفعيل والتمديد وتأكيد التسديد والترحيب'},
  {'key': 'reminders', 'label': 'التذكيرات', 'hint': 'قرب الانتهاء، انتهاء الاشتراك، وتذكير الدين'},
  {'key': 'broadcast', 'label': 'التبليغات', 'hint': 'التبليغ العامّ بكلّ أنواعه'},
  {'key': 'conn', 'label': 'تنبيهات الاتصال', 'hint': 'تنبيه المشترك عن اتّصاله (الإشارة، الكيبل…)'},
];

Map<String, Object?> _entry(List<String> groups, String label, {String? note, String? name, String idx = '900004'}) => {
      'idx': idx,
      'name': name ?? 'علي حسن',
      'phone': '07701234567',
      'groups': groups,
      'label': label,
      'note': note,
      'by': 'myservices',
      'at': '2026-11-14T18:20:00.000Z',
    };

Map<String, Object?> _reply({Map<String, Object?> exclusions = const {}, bool enabled = true, bool canManage = true}) => {
      'success': true,
      'enabled': enabled,
      'can_manage': canManage,
      'groups': _groups,
      'count': exclusions.length,
      'max': 5000,
      'exclusions': exclusions,
    };

Subscriber _sub({String? companyKey, String username = 'ali.hasan', String idx = '900004', String name = 'علي حسن'}) =>
    Subscriber.fromJson({
      'idx': idx,
      'username': username,
      'firstname': name,
      'phone': '07701234567',
      'expiration': '2026-12-01 18:00:00',
      'remaining_days': 17,
    }).withCompany(companyKey);

void main() {
  late SimServer server;

  setUpAll(simSetUpAll);

  setUp(() async {
    server = await simSetUp(secure: {'auth.admin_id': '2', 'auth.admin_username': 'myservices'});
    PermissionsService.debugSet(isEmployee: false);
    ProviderService.debugSet(null);
    MessageExclusionsState.reset();
  });

  tearDown(() {
    PermissionsService.debugReset();
    MessageExclusionsState.reset();
  });

  /// يقرأ القائمة داخل اختبار واجهة: الطلب يُطلق ثمّ يُضخّ الوقت (لا انتظار مباشر لشبكةٍ داخل الساعة الوهميّة).
  Future<void> load(WidgetTester t) async {
    unawaited(MessageExclusionsState.ensureFresh(force: true));
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));
    await t.pump();
  }

  /// القائمة كما يقرؤها التطبيق عند فتح المشتركين، ثمّ زرٌّ يفتح ورقة المشترك كما يفتحها «المزيد».
  Future<void> openSheet(WidgetTester t, {Subscriber? sub, SimVariant v = _v}) async {
    await pumpSim(t, v, home: (_) => simLauncher((ctx) => showMessageExclusionSheet(ctx, subject: mxSubjectOf(sub ?? _sub()))));
    await load(t);
    await simOpen(t);
  }

  test('القائمة: تُقرأ مرّةً وتُعرف باليوزر بلا حسّاسيّة أحرف؛ والميزة المطفأة ⇒ لا شيء', () async {
    server.reply('GET', _all, 200, _reply(exclusions: {
      'Ali.Hasan': _entry(['reminders', 'broadcast'], 'التذكيرات، التبليغات', note: 'طلب عدم الإزعاج'),
      'office': _entry(['all'], 'كلّ الرسائل', name: 'مكتب الشركة', idx: '77'),
    }));
    await MessageExclusionsState.ensureFresh();
    await MessageExclusionsState.ensureFresh(); // ضمن المدّة: لا طلب ثانٍ
    expect(server.calls('GET', _all), hasLength(1));
    expect(MessageExclusionsState.enabled && MessageExclusionsState.canManage, isTrue);
    final e = MessageExclusionsState.of('ali.hasan')!;
    expect(e.groups, ['reminders', 'broadcast']);
    expect(e.label, 'التذكيرات، التبليغات');
    expect(e.all, isFalse);
    expect(e.note, 'طلب عدم الإزعاج');
    expect(e.by, 'myservices');
    expect(e.at, isNotNull);
    expect(MessageExclusionsState.of('OFFICE')!.all, isTrue);
    expect(MessageExclusionsState.of('other'), isNull);
    expect(MessageExclusionsState.snapshot.value!.groups.map((g) => g.key), ['all', 'ops', 'reminders', 'broadcast', 'conn']);

    MessageExclusionsState.reset();
    expect(MessageExclusionsState.snapshot.value, isNull, reason: 'الخروج لا يُبقي قائمة المدير السابق');
    server.reply('GET', _all, 200, _reply(exclusions: {'ali.hasan': _entry(['all'], 'كلّ الرسائل')}, enabled: false));
    await MessageExclusionsState.ensureFresh();
    expect(MessageExclusionsState.enabled, isFalse);
    expect(MessageExclusionsState.of('ali.hasan'), isNull);
    expect(MessageExclusionsState.canManage, isFalse);
  });

  test('تعذّر الجلب لا يمحو آخر قائمة، وخروج المدير يمحوها (SessionManager يستدعي reset)', () async {
    server.reply('GET', _all, 200, _reply(exclusions: {'ali.hasan': _entry(['all'], 'كلّ الرسائل')}));
    await MessageExclusionsState.ensureFresh();
    server.reply('GET', _all, 409, {'success': false, 'message': 'تعذّر الآن — حاول بعد قليل'});
    await MessageExclusionsState.ensureFresh(force: true);
    expect(MessageExclusionsState.of('ali.hasan'), isNotNull);
    MessageExclusionsState.reset();
    expect(MessageExclusionsState.snapshot.value, isNull);
    // مسح الجلسة يمرّ بـreset (حارس نصّ — كبقيّة حالات الجلسة في SessionManager.clearAllSessionData)
    final src = File('lib/services/session_manager.dart').readAsStringSync();
    expect(src, contains("_guardSync('MessageExclusionsState.reset', () => MessageExclusionsState.reset());"));
  });

  testWidgets('إيقافٌ جديد: «كلّ الرسائل» مفعّلةٌ ابتداءً ⇒ PUT بالمشترك كاملاً، والحال تُحدَّث فوراً', (t) async {
    server.reply('GET', _all, 200, _reply());
    server.on('PUT', _path, (o) => SimReply(200, {'success': true, 'exclusion': _entry(['all'], 'كلّ الرسائل')}));
    await openSheet(t);
    expect(find.text('إيقاف الرسائل'), findsNWidgets(2), reason: 'العنوان وزرّ الحفظ');
    expect(find.byKey(const ValueKey('mx-group-reminders')), findsNothing, reason: 'الأنواع تظهر حين تُطفأ «كلّ الرسائل»');
    await t.tap(find.text('إيقاف الرسائل').last);
    await t.pumpAndSettle();
    expect(server.bodies('PUT', _path).single,
        {'username': 'ali.hasan', 'idx': '900004', 'name': 'علي حسن', 'phone': '07701234567', 'groups': ['all'], 'note': ''});
    expect(MessageExclusionsState.of('ali.hasan')!.all, isTrue);
    expect(find.byKey(const ValueKey('mx-all')), findsNothing, reason: 'الورقة أُغلقت');
    await simDrain(t);
  });

  testWidgets('أنواعٌ بعينها: التذكيرات والتبليغات مع ملاحظة — وبلا نوعٍ لا حفظ', (t) async {
    server.reply('GET', _all, 200, _reply());
    server.on('PUT', _path,
        (o) => SimReply(200, {'success': true, 'exclusion': _entry(['reminders', 'broadcast'], 'التذكيرات، التبليغات', note: 'طلب عدم الإزعاج')}));
    await openSheet(t);
    await t.tap(find.byKey(const ValueKey('mx-all')));
    await t.pumpAndSettle();
    expect(find.text('اختر نوعاً واحداً على الأقلّ، أو فعّل «كلّ الرسائل».'), findsOneWidget);
    await t.tap(find.text('إيقاف الرسائل').last);
    await t.pumpAndSettle();
    expect(server.calls('PUT', _path), isEmpty, reason: 'لا نوع ⇒ الزرّ معطّل');
    await t.tap(find.byKey(const ValueKey('mx-group-broadcast')));
    await t.tap(find.byKey(const ValueKey('mx-group-reminders')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('mx-note')), ' طلب عدم الإزعاج ');
    await t.pumpAndSettle();
    await t.tap(find.text('إيقاف الرسائل').last);
    await t.pumpAndSettle();
    final b = server.bodies('PUT', _path).single;
    expect(b['groups'], ['reminders', 'broadcast'], reason: 'بترتيب الخادم لا بترتيب النقر');
    expect(b['note'], 'طلب عدم الإزعاج');
    expect(MessageExclusionsState.of('ali.hasan')!.label, 'التذكيرات، التبليغات');
    await simDrain(t);
  });

  testWidgets('تعديل قائم: يفتح بأنواعه، «حفظ» معطّلٌ بلا تغيير، و«السماح بالرسائل» يزيله (DELETE)', (t) async {
    server.reply('GET', _all, 200, _reply(exclusions: {'ali.hasan': _entry(['reminders'], 'التذكيرات', note: 'قريب')}));
    server.reply('DELETE', _path, 200, {'success': true, 'removed': true});
    await openSheet(t);
    expect(find.text('الرسائل الموقوفة'), findsOneWidget);
    expect(find.byKey(const ValueKey('mx-group-reminders')), findsOneWidget);
    expect(t.widget<Checkbox>(find.descendant(of: find.byKey(const ValueKey('mx-group-reminders')), matching: find.byType(Checkbox))).value, isTrue);
    expect(t.widget<Checkbox>(find.descendant(of: find.byKey(const ValueKey('mx-group-ops')), matching: find.byType(Checkbox))).value, isFalse);
    await t.tap(find.text('حفظ'));
    await t.pumpAndSettle();
    expect(server.calls('PUT', _path), isEmpty, reason: 'لا تغيير ⇒ لا حفظ');
    await t.ensureVisible(find.byKey(const ValueKey('mx-allow')));
    await t.tap(find.byKey(const ValueKey('mx-allow')));
    await t.pumpAndSettle();
    expect(server.calls('DELETE', _path).single.queryParameters['username'], 'ali.hasan');
    expect(MessageExclusionsState.of('ali.hasan'), isNull);
    await simDrain(t);
  });

  testWidgets('رفض الخادم: رسالته تظهر والورقة باقية والحال لا تتغيّر', (t) async {
    server.reply('GET', _all, 200, _reply());
    server.reply('PUT', _path, 409, {'success': false, 'code': 'EXCLUSIONS_FULL', 'message': 'بلغت الحدّ الأقصى للمستثنين (5000) — أزِل من لا تحتاجه'});
    await openSheet(t);
    await t.tap(find.text('إيقاف الرسائل').last);
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('بلغت الحدّ الأقصى للمستثنين (5000) — أزِل من لا تحتاجه'), findsOneWidget);
    expect(find.byKey(const ValueKey('mx-all')), findsOneWidget);
    expect(MessageExclusionsState.of('ali.hasan'), isNull);
    await simDrain(t);
  });

  testWidgets('الميزة مطفأةٌ للحساب: لا ورقة', (t) async {
    server.reply('GET', _all, 200, _reply(enabled: false));
    await openSheet(t);
    expect(find.byKey(const ValueKey('mx-all')), findsNothing);
    await simDrain(t);
  });

  testWidgets('الجماعيّ: إيقافٌ عن المحدَّدين بطلبٍ واحد ثمّ تُقرأ القائمة من الخادم؛ و«السماح» لمن أُوقفت عنه منهم', (t) async {
    var listed = <String, Object?>{'omar': _entry(['conn'], 'تنبيهات الاتصال', name: 'عمر', idx: '3')};
    server.on('GET', _all, (_) => SimReply(200, _reply(exclusions: listed)));
    server.on('POST', _bulk, (o) {
      final b = o.data as Map;
      if (b['action'] == 'add') {
        listed = {for (final it in b['items'] as List) (it as Map)['username'] as String: _entry(['all'], 'كلّ الرسائل')};
      } else {
        listed = {};
      }
      return SimReply(200, {'success': true, 'action': b['action'], 'done': (b['items'] as List).length});
    });
    final subjects = [mxSubjectOf(_sub()), mxSubjectOf(_sub(username: 'omar', idx: '3', name: 'عمر'))];
    await pumpSim(t, _v, home: (_) => simLauncher((ctx) => showBulkMessageExclusionSheet(ctx, subjects: subjects)));
    await load(t);
    await simOpen(t);
    expect(find.text('2 مشترك — 1 منهم موقوفةٌ عنه من قبل'), findsOneWidget);
    await t.tap(find.text('إيقاف الرسائل عنهم'));
    await t.pumpAndSettle();
    final add = server.bodies('POST', _bulk).single;
    expect(add['action'], 'add');
    expect(add['groups'], ['all']);
    expect((add['items'] as List).map((x) => (x as Map)['username']), ['ali.hasan', 'omar']);
    expect((add['items'] as List).first, {'username': 'ali.hasan', 'idx': '900004', 'name': 'علي حسن', 'phone': '07701234567'});
    expect(MessageExclusionsState.of('ali.hasan'), isNotNull, reason: 'القائمة أُعيدت قراءتها بعد الجماعيّ');
    expect(MessageExclusionsState.of('omar')!.all, isTrue);
    await simDrain(t);

    await simOpen(t);
    await t.ensureVisible(find.byKey(const ValueKey('mx-allow')));
    await t.tap(find.byKey(const ValueKey('mx-allow')));
    await t.pumpAndSettle();
    expect(server.bodies('POST', _bulk).last['action'], 'remove');
    expect(server.bodies('POST', _bulk).last.containsKey('groups'), isFalse);
    expect(MessageExclusionsState.snapshot.value!.count, 0);
    await simDrain(t);
  });

  testWidgets('كرت صفحة المشترك: «لا تصله: …» بملاحظته ومن أوقفها؛ غير المستثنى و«كل الشركات» والميزة المطفأة ⇒ لا كرت', (t) async {
    server.reply('GET', _all, 200, _reply(exclusions: {'ali.hasan': _entry(['reminders', 'broadcast'], 'التذكيرات، التبليغات', note: 'طلب عدم الإزعاج')}));
    await load(t);
    var edits = 0;
    Widget page(Subscriber s) => Scaffold(body: ListView(children: [MessageExclusionCard(sub: s, onEdit: () => edits++)]));
    for (final v in const [SimVariant(320, dark: false), SimVariant(480, dark: true)]) {
      t.platformDispatcher.textScaleFactorTestValue = 1.2;
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpSim(t, v, home: (_) => page(_sub()));
      expect(find.byKey(const ValueKey('mx-card')), findsOneWidget);
      expect(find.textContaining('لا تصله: ', findRichText: true), findsOneWidget);
      expect(find.textContaining('التذكيرات، التبليغات', findRichText: true), findsOneWidget);
      expect(find.text('طلب عدم الإزعاج'), findsOneWidget);
      expect(find.textContaining('myservices'), findsOneWidget);
      expect(t.takeException(), isNull, reason: 'لا خروج نصّ على ${v.tag} بخطّ ١٫٢');
    }
    await t.tap(find.text('تعديل'));
    expect(edits, 1);

    await pumpSim(t, _v, home: (_) => page(_sub(username: 'someone.else')));
    expect(find.byKey(const ValueKey('mx-card')), findsNothing);
    await pumpSim(t, _v, home: (_) => page(_sub(companyKey: 'c0123456789ab')));
    expect(find.byKey(const ValueKey('mx-card')), findsNothing, reason: '«كل الشركات»: صفٌّ من شركةٍ أخرى');
    MessageExclusionsState.reset();
    await pumpSim(t, _v, home: (_) => page(_sub()));
    expect(find.byKey(const ValueKey('mx-card')), findsNothing, reason: 'لم تُقرأ القائمة');
  });

  testWidgets('من لا يُدير (موظّفٌ بلا صلاحيّتها): يرى الكرت و«تعديل» بمكانه مقفلاً؛ والصفحة الموقوفة كذلك', (t) async {
    server.reply('GET', _all, 200, _reply(exclusions: {'ali.hasan': _entry(['all'], 'كلّ الرسائل')}, canManage: false));
    await load(t);
    var edits = 0;
    await pumpSim(t, _v, home: (_) => Scaffold(body: ListView(children: [MessageExclusionCard(sub: _sub(), onEdit: () => edits++)])));
    expect(find.byKey(const ValueKey('mx-card')), findsOneWidget);
    expect(t.widget<TextButton>(find.ancestor(of: find.text('تعديل'), matching: find.bySubtype<TextButton>())).onPressed, isNull);
    expect(MessageExclusionsState.canManage, isFalse);

    server.reply('GET', _all, 200, _reply(exclusions: {'ali.hasan': _entry(['all'], 'كلّ الرسائل')}));
    await load(t);
    await pumpSim(t, _v,
        home: (_) => Scaffold(body: ListView(children: [MessageExclusionCard(sub: _sub(), pageLocked: true, onEdit: () => edits++)])));
    expect(t.widget<TextButton>(find.ancestor(of: find.text('تعديل'), matching: find.bySubtype<TextButton>())).onPressed, isNull);
    expect(edits, 0);
  });

  testWidgets('القائمة: جرسٌ مشطوب بجنب اسم المستثنى — ولا يخرج نصٌّ من الكرت على ٣٢٠ بخطّ ١٫٢ ولا على ٤٨٠', (t) async {
    final long = _sub(name: 'عبد الرحمن عبد الكريم عبد الواحد الموسوي الحسينيّ');
    Widget page(bool muted) => Scaffold(
          body: ListView(children: [
            SubscriberCardV3(sub: long, selected: false, onTap: () {}, onLongPress: () {}, hasTelegram: true, messagesMuted: muted),
          ]),
        );
    for (final v in const [SimVariant(320, dark: false), SimVariant(390, dark: true), SimVariant(480, dark: false)]) {
      t.platformDispatcher.textScaleFactorTestValue = 1.2;
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpSim(t, v, home: (_) => page(true), settle: false);
      await t.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('mx-muted')), findsOneWidget);
      expect(t.takeException(), isNull, reason: 'لا خروج نصّ على ${v.tag}');
      final withBadge = t.getSize(find.byType(SubscriberCardV3)).height;
      await pumpSim(t, v, home: (_) => page(false), settle: false);
      await t.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('mx-muted')), findsNothing);
      expect(t.getSize(find.byType(SubscriberCardV3)).height, withBadge, reason: 'الكرت لا يكبر بالشارة (${v.tag})');
    }
  });

  testWidgets('صفحة «المستثنون من الرسائل»: العدد والصفوف والبحث، و«السماح بالرسائل» بتأكيدٍ ثمّ DELETE', (t) async {
    final many = <String, Object?>{
      for (var i = 0; i < 8; i++)
        'user$i': _entry(i.isEven ? ['all'] : ['ops', 'conn'], i.isEven ? 'كلّ الرسائل' : 'التفعيل والتسديد، تنبيهات الاتصال',
            name: 'مشترك $i', idx: '$i', note: i == 3 ? 'قريب' : null),
    };
    server.on('GET', _all, (_) => SimReply(200, _reply(exclusions: many)));
    server.on('DELETE', _path, (o) {
      many.remove(o.queryParameters['username']);
      return const SimReply(200, {'success': true, 'removed': true});
    });
    t.platformDispatcher.textScaleFactorTestValue = 1.2;
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpSim(t, const SimVariant(320, dark: false), home: (_) => const MessageExclusionsScreen());
    expect(find.text('8 مستثنى'), findsOneWidget);
    expect(find.byKey(const ValueKey('mx-row-user0')), findsOneWidget);
    expect(t.takeException(), isNull, reason: 'لا خروج نصّ على ٣٢٠ بخطّ ١٫٢');

    await t.enterText(find.byKey(const ValueKey('mx-search')), 'مشترك 3');
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('mx-row-user3')), findsOneWidget);
    expect(find.byKey(const ValueKey('mx-row-user0')), findsNothing);
    expect(find.text('قريب'), findsOneWidget);
    expect(find.text('تنبيهات الاتصال'), findsOneWidget, reason: 'كلّ نوعٍ شريحة');

    await t.tap(find.byKey(const ValueKey('mx-allow-user3')));
    await t.pumpAndSettle();
    expect(find.text('تعود رسائل النظام تصل «مشترك 3»؟'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('mx-allow-confirm')));
    await t.pumpAndSettle();
    expect(server.calls('DELETE', _path).single.queryParameters['username'], 'user3');
    expect(MessageExclusionsState.of('user3'), isNull);
    expect(find.byKey(const ValueKey('mx-row-user3')), findsNothing);
    await simDrain(t);
  });

  testWidgets('صفحة القائمة لمن لا يُدير: الصفوف بلا أزرار', (t) async {
    server.reply('GET', _all, 200, _reply(exclusions: {'ali.hasan': _entry(['all'], 'كلّ الرسائل')}, canManage: false));
    await pumpSim(t, _v, home: (_) => const MessageExclusionsScreen());
    expect(find.byKey(const ValueKey('mx-row-ali.hasan')), findsOneWidget);
    expect(find.byKey(const ValueKey('mx-allow-ali.hasan')), findsNothing);
    await simDrain(t);
  });

  testWidgets('صفحة القائمة والميزة مطفأةٌ للحساب: سطرها وحده', (t) async {
    server.reply('GET', _all, 200, _reply(enabled: false));
    await pumpSim(t, _v, home: (_) => const MessageExclusionsScreen());
    expect(find.text('هذه الميزة لم تُفتح لحسابك بعد.'), findsOneWidget);
    expect(find.byKey(const ValueKey('mx-search')), findsNothing);
    await simDrain(t);
  });

  test('التبليغ: «N ضمن المستثنين» يُقرأ من المعاينة، ونصّ الخادم يُعرض حين يُستثنى أحد', () {
    final pv = BroadcastPreview.fromJson({'count': 10, 'audience': 10, 'excludedByList': 3, 'audienceKey': 'k'});
    expect(pv.excludedByList, 3);
    expect(BroadcastPreview.fromJson({'count': 10, 'audience': 10, 'audienceKey': 'k'}).excludedByList, 0, reason: 'يغيب عن الردّ = صفر');
  });

  test('صلاحيّة الموظّف whatsapp.exclusions: في مفاتيح ايرث لنك وفايبر اكس والشركات المُضافة، خارج الأدوار الجاهزة، وتُسمّى', () {
    const k = 'whatsapp.exclusions';
    expect(ElEmployeePerms.earthlinkKeys, contains(k));
    expect(ElEmployeePerms.fiberxKeys, contains(k));
    expect(ElEmployeePerms.kitKeys, contains(k));
    expect(ElEmployeePerms.roleFreeKeys, contains(k));
    expect(ElEmployeePerms.roleFreeOperations[k], 'المستثنون من الرسائل (إضافة وإزالة)');
  });
}
