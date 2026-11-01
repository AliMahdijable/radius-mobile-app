import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/national_more_api.dart';
import 'package:rad_mysvcs/api/national_portal_api.dart';
import 'package:rad_mysvcs/screens/app_modules.dart';
import 'package:rad_mysvcs/screens/national/national_more_widgets.dart';
import 'package:rad_mysvcs/screens/national/national_notes_screen.dart';
import 'package:rad_mysvcs/screens/national/national_reports_screen.dart';
import 'package:rad_mysvcs/screens/national/national_sessions_screen.dart';
import 'package:rad_mysvcs/screens/national/national_team_screen.dart';
import 'package:rad_mysvcs/screens/national/national_wallet_screen.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:rad_mysvcs/services/provider_service.dart';

import 'sim_el/sim_harness.dart';

/// أقسام بوّابة الوطنيّ الباقية بالتطبيق (١ نوفمبر — المالك: «اقسام البوابة البقية افضل تمضي بيها وتكملها»؛ العقد
/// release_work/national_rest/contract.md v1): «الجلسات» و«فريقي» و«تقارير البوّابة» و«الإشعارات والإعلانات» خلف المفتاح التجريبيّ
/// (`lookups.data.beta`)، وقفل البوّابة (`portal_locks`/`caps`) يقفل «الإيرادات» والأقسام بمكانها بسببها، والموظّف بلا مفتاحه يراها
/// مقفلةً لا مخفيّة. لا هاتف ولا بريد في «فريقي»، ولا «مقروء» يُرسل للبوّابة أبداً، و«المنفّذ» باسم عضو الفريق في «محفظتي».
const _v = SimVariant(390, dark: false);

const _allCaps = {
  'wallet': true,
  'revenue': true,
  'sessions': true,
  'team': true,
  'reports': true,
  'notifications': true,
  'announcements': true,
};

/// القدرات كلّها مسموحة إلّا ما يُبدَّل (خريطةٌ غير ثابتة: المفتاح المكرَّر يحلّ محلّ سابقه).
Map<String, bool> _capsWith(Map<String, bool> o) => {..._allCaps, ...o};

/// ردّ «مقفل» من الخادم (العقد §1).
Map<String, Object?> _lockedReply(String what) => {
      'success': true,
      'locked': true,
      'reason': 'no_permission',
      'title': 'لا صلاحيّة في البوّابة',
      'message': 'المستخدم الذي دخلت به في المشروع الوطني لا يملك صلاحيّة «$what» في البوّابة — اطلبها من الشركة أو ادخل بالمستخدم الرئيسيّ للشريك',
      'data': null,
    };

/// صفّ جلسة كما في العقد §4.
Map<String, Object?> _session(int n, {bool online = true}) => {
      'username': 'FBG885F15P$n',
      'customer': {'id': '$n', 'name': 'مريم عبد الله $n'},
      'zone': {'id': 'FBG885-3', 'name': 'FBG885-3'},
      'subscription': {'id': '1329$n', 'name': 'BASIC', 'expired': !online && n.isEven},
      'started_at': online ? '2026-11-01 07:15:00' : null,
      'ip': online ? '10.20.30.$n' : null,
      'mac': online ? 'AA:BB:CC:DD:EE:0$n' : null,
      'session_time': online ? 3 * 3600 + 12 * 60 : null,
      'download_bytes': 5 * 1024 * 1024 * 1024,
      'upload_bytes': 300 * 1024 * 1024,
    };

Map<String, Object?> _sessionsReply(List<Map<String, Object?>> rows, {required String status, int? total, bool inPage = false}) => {
      'success': true,
      'status': status,
      'data': rows,
      'total': total ?? rows.length,
      'page': 1,
      'size': 25,
      'page_count': 1,
      'filtered_in_page': inPage,
      'fetched_at': '2026-11-01T06:40:00.000Z',
      'stale': false,
    };

void main() {
  late SimServer server;

  setUpAll(simSetUpAll);

  setUp(() async {
    server = await simSetUp(secure: {'auth.admin_id': 'watani:2963757', 'auth.admin_username': 'owner'});
    PermissionsService.debugSet(isEmployee: false);
    ProviderService.debugSet('watani', label: 'المشروع الوطني');
    NationalMoreState.debugSet(const NationalCaps(beta: true, caps: {..._allCaps}));
    server.reply('GET', '/api/v2/ftth/lookups', 200, {
      'success': true,
      'data': {
        'zones': [
          {'id': 'FBG885-3', 'name': 'FBG885-3'},
          {'id': 'FBG2260-5', 'name': 'FBG2260-5'},
        ],
        'beta': true,
        'caps': _allCaps,
        'portal_locks': {'revenue': null, 'sessions': null},
      },
    });
  });

  tearDown(() {
    PermissionsService.debugReset();
    ProviderService.debugSet(null);
    NationalMoreState.debugSet(null);
  });

  group('القدرات والمفتاح', () {
    test('beta والقدرات وأسباب القفل كما في العقد — المجهول (null) لا يقفل', () {
      final c = NationalCaps.fromJson({
        'beta': true,
        'can_write': true,
        'caps': {'revenue': false, 'sessions': true, 'team': 'false', 'reports': null, 'notifications': false, 'announcements': false},
        'portal_locks': {'revenue': 'نصّ الخادم للإيرادات', 'notifications': 'نصّ', 'announcements': 'نصّ', 'sessions': null, 'team': null},
      });
      expect(c.beta, isTrue);
      expect(c.canWrite, isTrue);
      expect(c.denies('revenue'), isTrue);
      expect(c.cap('sessions'), isTrue);
      expect(c.denies('team'), isTrue);
      expect(c.cap('reports'), isNull, reason: 'null = مجهول');
      expect(c.locks.containsKey('sessions'), isFalse, reason: 'null في portal_locks = متاحٌ أو مجهول');
      expect(c.lockText(const ['revenue']), 'نصّ الخادم للإيرادات');
      expect(NationalCaps.fromJson(const {}).beta, isFalse);
      expect(NationalCaps.fromJson(const {'beta': 'true'}).beta, isFalse, reason: 'boolean وحده');
      expect(NationalCaps.fromJson(const {'caps': null}).caps, isEmpty, reason: 'caps null أوّل الثواني ⇒ لا قفل');
    });

    test('القفل: كلّ مفاتيح القسم مقفلةٌ صراحةً وحدها — المجهول والجزئيّ لا يقفلان', () {
      const c = NationalCaps(caps: {'revenue': false, 'notifications': false}, locks: {'announcements': 'نصّ'});
      expect(c.lockOf(const ['revenue']), contains('لا صلاحيّة في البوّابة'));
      expect(c.lockOf(const ['notifications', 'announcements']), isNotNull, reason: 'caps false + portal_locks');
      expect(c.lockOf(const ['sessions']), isNull, reason: 'مجهول');
      const half = NationalCaps(caps: {'notifications': false, 'announcements': true});
      expect(half.lockOf(const ['notifications', 'announcements']), isNull, reason: 'الإعلانات مسموحة ⇒ مفتوح');
    });

    test('الحالة: لا نداء لغير الوطنيّ، ونداءٌ واحد للوطنيّ ثمّ المهلة، والخروج يمسحها', () async {
      NationalMoreState.reset();
      ProviderService.debugSet('nabd', label: 'نبض');
      await NationalMoreState.ensureFresh();
      expect(server.calls('GET', '/api/v2/ftth/lookups'), isEmpty);
      expect(NationalMoreState.gate.value, isNull);

      ProviderService.debugSet('watani', label: 'المشروع الوطني');
      await NationalMoreState.ensureFresh();
      await NationalMoreState.ensureFresh();
      expect(server.calls('GET', '/api/v2/ftth/lookups'), hasLength(1));
      expect(NationalMoreState.beta, isTrue);
      NationalMoreState.reset();
      expect(NationalMoreState.gate.value, isNull);
      expect(NationalMoreState.beta, isFalse);
    });
  });

  group('الأقسام بالقائمة', () {
    Map<String, AppModule> mods() => {for (final m in buildAppModules()) m.id: m};
    const fresh = {'national_sessions', 'national_team', 'national_reports', 'national_notes'};

    test('المفتاح التجريبيّ مطفأ (أو لم يصل ردّ) ⇒ لا أقسام جديدة، والقائمة الوطنيّة كما كانت', () {
      NationalMoreState.debugSet(const NationalCaps(beta: false));
      final m = mods();
      expect(m.keys.toSet().intersection(fresh), isEmpty);
      expect(m['national_money']?.isLocked, isFalse);
      expect(m['national_tickets'], isNotNull);
      NationalMoreState.debugSet(null);
      expect(mods().keys.toSet().intersection(fresh), isEmpty, reason: 'لم يصل ردّ ⇒ لا تظهر');
    });

    test('مفعّل ⇒ الأقسام الأربعة مفتوحة بمجموعاتها، والوطنيّ وحده', () {
      final m = mods();
      for (final id in fresh) {
        expect(m[id], isNotNull, reason: id);
        expect(m[id]!.isLocked, isFalse, reason: id);
      }
      expect(m['national_sessions']!.title, 'الجلسات');
      expect(m['national_team']!.title, 'فريقي');
      expect(m['national_reports']!.group, AppModuleGroup.finance);
      expect(m['national_notes']!.group, AppModuleGroup.comms);
      ProviderService.debugSet('nabd', label: 'نبض');
      expect(mods().keys.toSet().intersection({...fresh, 'national_money'}), isEmpty);
    });

    test('portal_locks ⇒ «الإيرادات» والجرس بمكانهما مقفلين بسببهما (حساب المالك اليوم) — ولو كان التجريبيّ مطفأً', () {
      NationalMoreState.debugSet(const NationalCaps(beta: false, locks: {'revenue': 'نصّ الخادم'}));
      var m = mods()['national_money']!;
      expect(m.isLocked, isTrue);
      expect(m.unavailable, 'لا صلاحيّة في البوّابة — اطلبها من الشركة', reason: 'سطرٌ واحد — الكرت لا يكبر');
      NationalMoreState.debugSet(NationalCaps(
        beta: true,
        caps: _capsWith(const {'revenue': false, 'notifications': false, 'announcements': false, 'reports': false}),
        locks: const {'revenue': 'x', 'notifications': 'x', 'announcements': 'x', 'reports_sessions': 'x'},
      ));
      final all = mods();
      expect(all['national_money']!.isLocked, isTrue);
      expect(all['national_notes']!.unavailable, contains('لا صلاحيّة في البوّابة'));
      expect(all['national_sessions']!.isLocked, isFalse);
      expect(all['national_team']!.isLocked, isFalse);
      expect(all['national_reports']!.isLocked, isFalse, reason: 'المشتركون حسب الزون من قائمتنا — تقرير الجلسات يُقفل داخل الصفحة');
      // الإشعارات ممنوعة والإعلانات مسموحة ⇒ القسم مفتوح (الإعلانات فيه)
      NationalMoreState.debugSet(NationalCaps(beta: true, caps: _capsWith(const {'notifications': false})));
      m = mods()['national_notes']!;
      expect(m.isLocked, isFalse);
    });

    test('الموظّف بلا مفتاح القسم يراه بمكانه مقفلاً لا مخفيّاً (مفاتيح العقد §9)', () {
      PermissionsService.debugSet(isEmployee: true, permissions: const {'subscribers.view': true, 'reports.packages': true});
      final m = mods();
      for (final id in const ['national_sessions', 'national_team', 'national_notes']) {
        expect(m[id], isNotNull, reason: '$id مقفلٌ لا مخفيّ');
        expect(m[id]!.isLocked, isTrue, reason: id);
      }
      expect(m['national_reports']!.isLocked, isFalse, reason: 'reports.packages يفتح «المشتركون حسب الزون»');
      PermissionsService.debugSet(
          isEmployee: true, permissions: const {'reports.sessions': true, 'reports.financial': true, 'notifications.view': true});
      final n = mods();
      for (final id in fresh) {
        expect(n[id]!.isLocked, isFalse, reason: id);
      }
    });
  });

  group('التحليل', () {
    test('الجلسة: صفّ العقد، وغير المتّصل بلا آيبي ولا مدّة (null لا صفر)', () {
      final a = NationalSession.fromJson(_session(1));
      expect((a.username, a.customer?.name, a.zone, a.plan, a.ip, a.subscriptionId), ('FBG885F15P1', 'مريم عبد الله 1', 'FBG885-3', 'BASIC', '10.20.30.1', '13291'));
      expect(nationalDuration(a.durationSec), '3س 12د');
      expect(nationalBytes(a.download), '5.0 GB');
      final o = NationalSession.fromJson(_session(2, online: false));
      expect((o.ip, o.mac, o.durationSec, o.startedAt, o.expired), (null, null, null, null, true));
      expect(nationalDuration(null), '—');
      expect(nationalBytes(null), '—');
      expect(nationalCount(null), '—');
      expect(nationalCount(12345), '12,345');
    });

    test('عضو الفريق: الوظيفة من الخادم، و«غير محدود»/الحدّ/المجهول، واليوزر المقنّع', () {
      final m = NationalTeamMember.fromJson({
        'id': '1',
        'name': 'علي حسن',
        'username': 'ali.support',
        'username_masked': null,
        'role': {'code': 'SupportTeamMember', 'label': 'عضو فريق الدعم'},
        'is_main': false,
        'wallet_limit': {'limited': true, 'amount': 200000},
        'last_login_at': null,
      });
      expect((m.name, m.login, m.role, m.main, m.limited, m.walletLimit, m.lastLogin), ('علي حسن', 'ali.support', 'عضو فريق الدعم', false, true, 200000, null));
      final p = NationalTeamMember.fromJson({
        'name': 'كاشير',
        'username': null,
        'username_masked': '•••4567',
        'role': {'code': 'Cashier'},
        'wallet_limit': {'limited': null, 'amount': null},
      });
      expect((p.login, p.role, p.limited), ('•••4567', 'كاشير', null));
      expect(NationalTeamMember.fromJson({'name': 'x', 'wallet_limit': {'limited': false, 'amount': null}}).limited, isFalse);
      expect(nationalTeamRole('FieldWorker'), 'عامل ميداني');
      expect(nationalTeamRole('Mystery'), 'Mystery');
    });

    test('الإشعار: الرابط http(s) وحده، و«غير مقروء» من البوّابة، ونوعه بالعربيّ', () {
      final n = NationalNote.fromJson({'id': 'n1', 'title': 'تنبيه', 'body': 'نصّ', 'read': false, 'type': 'PlanExpiry', 'link': 'javascript:alert(1)'});
      expect((n.unread, n.link, n.body, nationalNoteType(n.type)), (true, null, 'نصّ', 'انتهاء باقة'));
      final a = NationalNote.fromJson({'title': 'إعلان', 'body': 'x', 'link': 'https://ftth.iq/news/1', 'pinned': true});
      expect((a.link, a.pinned, a.unread), ('https://ftth.iq/news/1', true, false));
      expect(nationalNoteType('Unknown'), isNull);
    });

    test('التقرير: صفوف الزونات والإجماليّات كما في العقد (المجهول null)', () {
      final r = NationalReport.fromJson({
        'success': true,
        'data': [
          {'zone_id': 'FBG0885-3', 'zone': 'FBG0885-3', 'total': 120, 'active': 98, 'expired': 20, 'suspended': 2, 'other': 2},
          {'zone_id': 'FBG2260-5', 'zone': null, 'total': 70, 'active': 52, 'expired': 16, 'suspended': 1, 'other': 2},
        ],
        'totals': {'total': 190, 'active': 150, 'expired': 36, 'suspended': 3, 'other': null},
        'source': 'list',
        'partial': true,
      });
      expect(r.zones.map((z) => z.zone), ['FBG0885-3', 'FBG2260-5'], reason: 'zone null ⇒ zone_id');
      expect((r.total('active'), r.total('other'), r.total('missing'), r.partial), (150, null, null, true));
      final s = NationalReport.fromJson({
        'data': [
          {'zone_id': 'Z1', 'online': 40, 'offline': 3, 'total': 43},
        ],
        'totals': {'online': 40, 'offline': 3, 'total': 43},
      });
      expect((s.zones.single.online, s.zones.single.offline, s.total('total')), (40, 3, 43));
    });

    test('«المنفّذ» باسم عضو الفريق — وحركاتك «أنت» بلا اسم', () {
      final t = NationalMoneyRow.fromJson({'type': 'PLAN_RENEW', 'amount': -35000, 'by': 'team', 'by_name': 'علي حسن'});
      expect((t.by, t.byName), ('team', 'علي حسن'));
      final me = NationalMoneyRow.fromJson({'type': 'PLAN_RENEW', 'amount': -35000, 'by': 'me', 'by_name': 'أنا'});
      expect(me.byName, isNull);
    });
  });

  group('الشاشات', () {
    testWidgets('«الجلسات»: المتّصلون أوّلاً (٢٥)، والتبديل وغير المتّصلين، والبحث، والتفاصيل بالنقر', (t) async {
      server.on('GET', '/api/v2/ftth/sessions', (req) {
        final online = req.queryParameters['status'] == 'online';
        return SimReply(
            200,
            _sessionsReply([_session(1, online: online), _session(2, online: online)],
                status: online ? 'online' : 'offline', total: online ? 103 : 11));
      });
      await pumpSim(t, _v, home: (_) => const NationalSessionsScreen());
      var q = server.calls('GET', '/api/v2/ftth/sessions').last.queryParameters;
      expect((q['status'], q['size'], q['page']), ('online', 25, 1));
      expect(find.text('متّصل الآن: 103'), findsOneWidget);
      expect(find.textContaining('3س 12د'), findsWidgets);

      await t.tap(find.text('مريم عبد الله 1'));
      await t.pumpAndSettle();
      expect(find.text('10.20.30.1'), findsOneWidget, reason: 'الآيبي في التفاصيل');
      expect(find.text('AA:BB:CC:DD:EE:01'), findsOneWidget);
      await t.tapAt(const Offset(20, 20));
      await t.pumpAndSettle();

      await t.tap(find.text('غير متّصل').first);
      await t.pumpAndSettle();
      q = server.calls('GET', '/api/v2/ftth/sessions').last.queryParameters;
      expect(q['status'], 'offline');
      expect(find.text('منتهي'), findsOneWidget, reason: 'اشتراكٌ منتهٍ بين غير المتّصلين');

      await t.enterText(find.byType(TextField).first, 'FBG885');
      await t.pump(const Duration(milliseconds: 500));
      await t.pumpAndSettle();
      expect(server.calls('GET', '/api/v2/ftth/sessions').last.queryParameters['q'], 'FBG885');
      await simDrain(t);
    });

    testWidgets('«الجلسات»: البحث بالاسم داخل الصفحة يُقال، والزون من الفلاتر ⇒ zone=', (t) async {
      server.on('GET', '/api/v2/ftth/sessions', (req) => SimReply(
          200, _sessionsReply([_session(1)], status: 'online', inPage: (req.queryParameters['q'] ?? '').toString().isNotEmpty)));
      await pumpSim(t, _v, home: (_) => const NationalSessionsScreen());
      await t.enterText(find.byType(TextField).first, 'مريم');
      await t.pump(const Duration(milliseconds: 500));
      await t.pumpAndSettle();
      expect(find.textContaining('داخل الصفحة المعروضة وحدها'), findsOneWidget);
      await t.tap(find.text('الفلاتر'));
      await t.pumpAndSettle();
      await t.tap(find.descendant(of: find.byType(BottomSheet), matching: find.text('FBG2260-5')));
      await t.tap(find.text('تطبيق'));
      await t.pumpAndSettle();
      expect(server.calls('GET', '/api/v2/ftth/sessions').last.queryParameters['zone'], 'FBG2260-5');
      await simDrain(t);
    });

    testWidgets('«الجلسات» مقفلة من البوّابة (ردّ 200 locked) ⇒ قفلٌ هادئ بنصّ الخادم، لا «إعادة المحاولة» ولا قائمة فارغة', (t) async {
      server.reply('GET', '/api/v2/ftth/sessions', 200, {..._lockedReply('الجلسات'), 'status': 'online', 'page': 1, 'size': 25});
      await pumpSim(t, _v, home: (_) => const NationalSessionsScreen());
      expect(find.byType(NationalLockedBox), findsOneWidget);
      expect(find.text('لا صلاحيّة في البوّابة'), findsOneWidget);
      expect(find.textContaining('لا يملك صلاحيّة «الجلسات»'), findsOneWidget);
      expect(find.text('إعادة المحاولة'), findsNothing);
      expect(find.text('لا أحد متّصلٌ الآن'), findsNothing);
      await simDrain(t);
    });

    testWidgets('قسمٌ تجريبيّ لم يُفتح للحساب (409 BETA_OFF) ⇒ قفلٌ بعنوانه لا «تعذّر»', (t) async {
      server.reply('GET', '/api/v2/ftth/team', 409, {
        'success': false,
        'code': 'BETA_OFF',
        'message': 'هذا القسم تجريبيّ ولم يُفتح لحسابك بعد — سيُفتح قريباً',
      });
      await pumpSim(t, _v, home: (_) => const NationalTeamScreen());
      expect(find.text('قسمٌ تجريبيّ'), findsOneWidget);
      expect(find.textContaining('سيُفتح قريباً'), findsOneWidget);
      expect(find.text('إعادة المحاولة'), findsNothing);
      await simDrain(t);
    });

    testWidgets('«فريقي»: الوظيفة والحدّ و«غير محدود» و«—» والمقنّع وإجماليّ الحدود — ولا هاتف', (t) async {
      server.reply('GET', '/api/v2/ftth/team', 200, {
        'success': true,
        'data': [
          {'id': '1', 'name': 'حسين الوكيل', 'username': 'owner77', 'role': {'code': 'Contractor', 'label': 'الوكيل الرئيسيّ'}, 'is_main': true, 'wallet_limit': {'limited': null, 'amount': null}, 'last_login_at': null},
          {'id': '2', 'name': 'علي حسن', 'username': 'ali_fw', 'role': {'code': 'FieldWorker', 'label': 'عامل ميداني'}, 'is_main': false, 'wallet_limit': {'limited': true, 'amount': 250000}, 'last_login_at': '2026-10-31 20:05:00'},
          {'id': '3', 'name': 'زينب', 'username': 'zainab88', 'role': {'code': 'SupportTeamMember', 'label': 'عضو فريق الدعم'}, 'is_main': false, 'wallet_limit': {'limited': false, 'amount': null}, 'last_login_at': null},
          {'id': '4', 'name': 'مصطفى', 'username': null, 'username_masked': '•••4567', 'role': {'code': 'SupportTeamMember', 'label': 'عضو فريق الدعم'}, 'is_main': false, 'wallet_limit': {'limited': null, 'amount': null}, 'last_login_at': null},
        ],
        'total': 4,
        'page': 1,
        'size': 25,
        'page_count': 1,
        'limits_total': 250000,
        'fetched_at': '2026-11-01T06:50:00.000Z',
        'stale': false,
      });
      await pumpSim(t, _v, home: (_) => const NationalTeamScreen());
      expect(find.text('الوكيل الرئيسيّ'), findsOneWidget);
      expect(find.text('عامل ميداني'), findsOneWidget);
      expect(find.text('عضو فريق الدعم'), findsNWidgets(2));
      expect(find.textContaining('غير محدود'), findsOneWidget);
      expect(find.textContaining('حدّ المحفظة: —'), findsOneWidget, reason: 'walletSetup null ⇒ «—» لا «غير محدود»');
      expect(find.textContaining('250,000'), findsWidgets);
      expect(find.text('•••4567'), findsOneWidget);
      expect(find.textContaining('2026-10-31 20:05'), findsOneWidget);
      expect(find.textContaining('077'), findsNothing);
      expect(server.calls('GET', '/api/v2/ftth/team').last.queryParameters['size'], 25);
      await simDrain(t);
    });

    testWidgets('«الإشعارات والإعلانات»: القراءة وحدها — tab= بمسارٍ واحد، ولا نداء غير GET أبداً', (t) async {
      server.on('GET', '/api/v2/ftth/notifications', (req) {
        if (req.queryParameters['tab'] == 'announcements') {
          return const SimReply(200, {
            'success': true,
            'tab': 'announcements',
            'data': [
              {'id': 'a1', 'title': 'صيانة مجدولة', 'body': 'صيانة ليلة الجمعة', 'at': '2026-10-30 10:00:00', 'pinned': true, 'link': 'https://ftth.iq/m'},
            ],
            'total': 1,
            'page': 1,
            'size': 20,
            'page_count': 1,
          });
        }
        return const SimReply(200, {
          'success': true,
          'tab': 'notifications',
          'data': [
            {'id': 'n1', 'title': 'تمّ تفعيل اشتراك', 'body': 'اشتراك FBG885F15P1 فُعّل', 'at': '2026-11-01 08:00:00', 'read': false, 'type': 'ServiceActivation', 'link': null},
            {'id': 'n2', 'title': 'تذكرة جديدة', 'body': 'cc-26112', 'at': '2026-10-31 18:00:00', 'read': true, 'type': '', 'link': null},
          ],
          'total': 2,
          'page': 1,
          'size': 20,
          'page_count': 1,
        });
      });
      await pumpSim(t, _v, home: (_) => const NationalNotesScreen());
      expect(server.calls('GET', '/api/v2/ftth/notifications').last.queryParameters['tab'], 'notifications');
      expect(find.text('تمّ تفعيل اشتراك'), findsOneWidget);
      expect(find.text('غير مقروء'), findsOneWidget);
      expect(find.text('تفعيل خدمة'), findsOneWidget);
      await t.tap(find.text('الإعلانات').first);
      await t.pumpAndSettle();
      expect(server.calls('GET', '/api/v2/ftth/notifications').last.queryParameters['tab'], 'announcements');
      expect(find.text('صيانة مجدولة'), findsOneWidget);
      expect(find.text('مثبّت'), findsOneWidget);
      expect(find.text('اقرأ المقال كاملاً'), findsOneWidget);
      expect(server.requests.where((r) => r.method != 'GET'), isEmpty, reason: 'لا «مقروء» يُرسل للبوّابة أبداً');
      await simDrain(t);
    });

    testWidgets('الجرس مقفلٌ من البوّابة (حساب المالك اليوم) ⇒ قفلٌ هادئ في التبويبين', (t) async {
      server.on('GET', '/api/v2/ftth/notifications',
          (req) => SimReply(200, {..._lockedReply(req.queryParameters['tab'] == 'announcements' ? 'الإعلانات' : 'الإشعارات'), 'tab': req.queryParameters['tab']}));
      await pumpSim(t, _v, home: (_) => const NationalNotesScreen());
      expect(find.textContaining('«الإشعارات»'), findsOneWidget);
      await t.tap(find.text('الإعلانات').first);
      await t.pumpAndSettle();
      expect(find.textContaining('«الإعلانات»'), findsOneWidget);
      expect(find.byType(NationalLockedBox), findsOneWidget);
      await simDrain(t);
    });

    testWidgets('«تقارير البوّابة»: المشتركون حسب الزون بالأرقام، و«جارٍ» ثمّ الوصول، وتقرير الجلسات مقفلٌ بسببه', (t) async {
      var zoneCalls = 0;
      server.on('GET', '/api/v2/ftth/reports/zones', (_) {
        zoneCalls++;
        if (zoneCalls == 1) return const SimReply(200, {'success': true, 'pending': true});
        return const SimReply(200, {
          'success': true,
          'data': [
            {'zone_id': 'FBG885-3', 'zone': 'FBG885-3', 'total': 150, 'active': 120, 'expired': 30, 'suspended': 2, 'other': 0},
            {'zone_id': 'FBG2260-5', 'zone': 'FBG2260-5', 'total': 50, 'active': 40, 'expired': 10, 'suspended': 0, 'other': 0},
          ],
          'totals': {'total': 200, 'active': 160, 'expired': 40, 'suspended': 2, 'other': 0},
          'source': 'list',
          'partial': false,
          'fetched_at': '2026-11-01 09:40:00',
          'stale': false,
        });
      });
      server.reply('GET', '/api/v2/ftth/reports/sessions', 200, _lockedReply('تقرير الجلسات'));
      await pumpSim(t, _v, home: (_) => const NationalReportsScreen(), settle: false);
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      expect(find.text('جارٍ تجهيز التقرير…'), findsOneWidget);
      expect(zoneCalls, 1);
      await t.pump(const Duration(seconds: 5));
      await t.pumpAndSettle();
      expect(zoneCalls, 2, reason: '«جارٍ» ⇒ يُسأل ثانيةً');
      expect(find.text('160'), findsOneWidget);
      expect(find.text('200'), findsOneWidget);
      expect(find.textContaining('منهم موقوف: 2'), findsOneWidget);
      expect(find.textContaining('لا يملك صلاحيّة «تقرير الجلسات»'), findsOneWidget);
      await simDrain(t);
    });

    testWidgets('«تقارير البوّابة» لموظّفٍ بمفتاح المشتركين وحده ⇒ تقرير الجلسات مقفلٌ بلا نداء', (t) async {
      PermissionsService.debugSet(isEmployee: true, permissions: const {'reports.packages': true});
      server.reply('GET', '/api/v2/ftth/reports/zones', 200, {
        'success': true,
        'data': const [],
        'totals': {'total': 0, 'active': 0, 'expired': 0},
      });
      await pumpSim(t, _v, home: (_) => const NationalReportsScreen());
      expect(server.calls('GET', '/api/v2/ftth/reports/sessions'), isEmpty);
      expect(find.text('لا صلاحيّة — اطلبها من مديرك'), findsOneWidget);
      await simDrain(t);
    });

    testWidgets('«محفظتي»: «المنفّذ» باسم عضو الفريق حين يعرفه الخادم', (t) async {
      server.reply('GET', '/api/v2/ftth/wallet', 200, {
        'success': true,
        'data': [
          {'id': '1', 'at': '2026-10-31 11:15:00', 'type': 'PLAN_RENEW', 'amount': -35000, 'wallet_type': 'Main', 'direction': 'out', 'by': 'team', 'by_name': 'علي حسن'},
        ],
        'total': 1,
        'page': 1,
        'page_count': 1,
        'balance': {'balance': 1250000, 'commission': 0, 'currency': 'IQD', 'limit': null},
        'range_default': false,
        'wallet': 'all',
        'caps': {'transfers': false},
      });
      await pumpSim(t, _v, home: (_) => const NationalWalletScreen());
      expect(find.textContaining('المنفّذ: علي حسن'), findsOneWidget);
      await simDrain(t);
    });
  });
}
