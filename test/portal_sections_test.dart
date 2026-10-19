import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:rad_mysvcs/api/portal_settings_api.dart';
import 'package:rad_mysvcs/core/widgets/permission_locked.dart';
import 'package:rad_mysvcs/screens/portal_settings/portal_settings_screen.dart';
import 'package:rad_mysvcs/screens/portal_settings/widgets/portal_switch_tile.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:rad_mysvcs/services/provider_service.dart';

import 'sim_el/sim_harness.dart';

/// «ما يراه مشتركوك» في «بوابة المشترك» — مفتاحا «حالة الاتصال»
/// و«الاستهلاك» (وسيط البوّابة §11)، أمام خادمٍ وهميّ بالعقد:
///
///   GET /api/v2/portal/settings
///       → {success, enabled, agent_code, sections:{connection, usage, device}}
///   PUT /api/v2/portal/settings {sections:{<المفتاح المنقور وحده>}}
///       → {success, sections (كاملةً كما حُفظت)} · ٤٠٣ PERMISSION_DENIED ·
///         ٤٠٠ برسالة · ٥٠٣
///
/// السلوك المطلوب: النقرة تُحفظ فوراً بلا سؤال وترجع عند الرفض؛ كلّ طلبٍ
/// يحمل قسمه وحده (فلا يُعيد ما غيّره الويب أو جهازٌ آخر) والحفظ بالدور؛
/// المعروض بعده ما ردّه الخادم كاملاً؛ الجهاز (بلا مفتاح بعد) لا يُرسل
/// أبداً؛ الموظّف بلا `settings.edit` يراهما بمكانهما مقفلَين؛ وخادمٌ لا يرسل
/// `sections` لا مفاتيح له.
const _settings = '/api/v2/portal/settings';
const _logins = '/api/v2/portal/logins';

const _v = SimVariant(360, dark: false);

const _portal = 'تفعيل بوابة مشتركيّ';
// النصوص نفسها في ويب /v2 (client-v2/src/components/portal/agent-portal.ts).
const _title = 'ما يراه مشتركوك';
const _connection = 'حالة الاتصال';
const _usage = 'الاستهلاك';
const _connectionHint = 'متصل أو لا، ومن متى، وتحميل ورفع الجلسة، وآخر اتصال';
const _usageHint = 'التحميل والرفع لكل يوم وكل شهر';
const _hiddenHint = 'مخفي عن مشتركيك';
const _failed = 'تعذّر الحفظ — حاول لاحقاً';
const _askManager = 'ليس لديك صلاحيّة لهذا الإجراء — اطلبها من مديرك';
const _ownerOnly = 'إظهار الأقسام وإخفاؤها لصاحب الحساب';

const _allOn = {'connection': true, 'usage': true, 'device': false};

void main() {
  late SimServer server;

  setUpAll(simSetUpAll);

  setUp(() async {
    server = await simSetUp(secure: {'auth.admin_id': '2251'});
    PermissionsService.debugSet(isEmployee: false);
    ProviderService.debugSet(null);
  });

  tearDown(() {
    PermissionsService.debugReset();
    ProviderService.debugSet(null);
  });

  /// الاهتزاز (قناة المنصّة) بلا محرّك في `flutter test`.
  void mockPlatform(WidgetTester t) {
    t.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
    addTearDown(() => t.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
  }

  /// [sections] `null` = خادمٌ قبل §11 (لا مفتاح `sections` في الردّ).
  void settings({Object? sections = _allOn}) {
    server.reply('GET', _settings, 200, {
      'success': true,
      'enabled': true,
      'agent_code': '402917',
      if (sections != null) 'sections': sections,
    });
    server.reply('GET', _logins, 200, {'success': true, 'data': []});
  }

  /// خادمٌ يدمج ما يصله في المخزَّن ويردّه كاملاً.
  Map<String, bool> mergingServer([Map<String, bool> start = _allOn]) {
    final stored = Map<String, bool>.from(start);
    server.on('PUT', _settings, (req) {
      final s = (req.data as Map)['sections'] as Map;
      s.forEach((k, v) => stored[k as String] = v as bool);
      return SimReply(200, {'success': true, 'sections': Map.of(stored)});
    });
    return stored;
  }

  /// الشاشة كاملةً بطولٍ يبني كلّ عناصر التبويب الأوّل.
  Future<void> open(WidgetTester t) async {
    mockPlatform(t);
    await pumpSim(t, _v, home: (_) => const PortalSettingsScreen());
    t.view.physicalSize = const Size(400, 2000);
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  }

  /// يترك الطلب يبلغ الخادم الوهميّ (والدوّارة تدور — فلا `pumpAndSettle`).
  Future<void> flush(WidgetTester t) async {
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));
  }

  Finder tile(String title) => find.ancestor(
      of: find.text(title), matching: find.byType(PortalSwitchTile));
  Finder switchOf(String title) =>
      find.descendant(of: tile(title), matching: find.byType(Switch));
  Finder spinnerOf(String title) => find.descendant(
      of: tile(title), matching: find.byType(CircularProgressIndicator));
  bool valueOf(WidgetTester t, String title) =>
      t.widget<Switch>(switchOf(title)).value;

  List<Object?> sentSections() =>
      [for (final b in server.bodies('PUT', _settings)) b['sections']];

  // ═════════════════════════ العقد ═════════════════════════

  group('العقد', () {
    test('PortalSections: الافتراض، و1/0 ونصّهما، والناقص من الاحتياط', () {
      const d = PortalSections();
      expect([d.connection, d.usage, d.device], [true, true, false],
          reason: 'الاتصال والاستهلاك ظاهران افتراضاً، والجهاز مطفأ');
      expect(PortalSections.fromJson(const {}), d);
      expect(
        PortalSections.fromJson(
            const {'connection': false, 'usage': 0, 'device': 1}),
        const PortalSections(connection: false, usage: false, device: true),
      );
      expect(
        PortalSections.fromJson(
            const {'connection': '0', 'usage': 'false', 'device': 'TRUE'}),
        const PortalSections(connection: false, usage: false, device: true),
      );
      expect(
          PortalSections.fromJson(const {'connection': 'x', 'usage': null}), d,
          reason: 'غير المفهوم يأخذ الافتراض');
      const sent = PortalSections(connection: false, usage: false);
      expect(
        PortalSections.fromJson(const {'connection': true}, fallback: sent),
        const PortalSections(connection: true, usage: false),
        reason: 'ردٌّ جزئيّ لا يقلب قسماً لم يُلمس',
      );
      expect(sent.toJson(),
          {'connection': false, 'usage': false, 'device': false});
      expect(sent.withValue(PortalSection.usage, true),
          const PortalSections(connection: false));
      expect(sent.of(PortalSection.connection), isFalse);
      expect(sent.of(PortalSection.device), isFalse);
    });

    test('PortalAccess: بلا sections ← null (لا مفاتيح)، ومعها مقروءة', () {
      expect(
          PortalAccess.fromJson(const {'success': true, 'enabled': true})
              .sections,
          isNull);
      expect(PortalAccess.fromJson(const {'sections': 'connection'}).sections,
          isNull);
      expect(PortalAccess.fromJson(const {'sections': {}}).sections,
          const PortalSections());
      final a = PortalAccess.fromJson(const {
        'enabled': true,
        'agent_code': '402917',
        'sections': {'usage': false},
      });
      expect(a.sections, const PortalSections(usage: false));
      expect(a.copyWith(enabled: false).sections, a.sections,
          reason: 'مفتاح البوّابة لا يمسّ الأقسام');
      expect(a.copyWith(sections: const PortalSections()).agentCode, '402917');
      expect(a.copyWith(sections: null).sections, isNull);
    });
  });

  // ═════════════════════════ الواجهة البرمجيّة ═════════════════════════

  group('PortalSettingsApi.setPortalSections', () {
    test('🚨 الجسم: المفتاح المنقور وحده · ردّ الخادم (كاملاً) هو المحفوظ',
        () async {
      server.reply('PUT', _settings, 200, {
        'success': true,
        // الويب أخفى الاستهلاك قبلها: الردّ يحمله ولو لم يُرسَل.
        'sections': {'connection': 0, 'usage': 0, 'device': 0},
      });
      final r = await PortalSettingsApi.setPortalSections(
          PortalSection.connection, false,
          current: const PortalSections());
      expect(server.bodies('PUT', _settings).single, {
        'sections': {'connection': false},
      });
      expect(r.ok, isTrue);
      expect(r.denied, isFalse);
      expect(r.sections, const PortalSections(connection: false, usage: false));
    });

    test('ردٌّ بلا sections ← null (المُستدعي يبني) · وجزئيّ ← الناقص من current',
        () async {
      server.reply('PUT', _settings, 200, {'success': true});
      expect(
        (await PortalSettingsApi.setPortalSections(PortalSection.usage, false,
                current: const PortalSections()))
            .sections,
        isNull,
      );
      expect(server.bodies('PUT', _settings).last, {
        'sections': {'usage': false},
      });
      server.reply('PUT', _settings, 200, {
        'success': true,
        'sections': {'connection': false},
      });
      expect(
        (await PortalSettingsApi.setPortalSections(PortalSection.usage, false,
                current: const PortalSections(device: true)))
            .sections,
        const PortalSections(connection: false, usage: false, device: true),
      );
      for (final b in server.bodies('PUT', _settings)) {
        expect((b['sections'] as Map).keys, hasLength(1),
            reason: 'مفتاحٌ واحد لكلّ طلب — لا الثلاثة');
      }
    });

    test('٤٠٣ «لا صلاحيّة» · ٤٠٠ برسالته العربيّة وحدها · ٥٠٣ · مهلة',
        () async {
      server.reply('PUT', _settings, 403, {
        'success': false,
        'code': 'PERMISSION_DENIED',
        'message': 'لا تملك صلاحية: settings.edit',
      });
      final denied = await PortalSettingsApi.setPortalSections(
          PortalSection.usage, false);
      expect(denied.ok, isFalse);
      expect(denied.denied, isTrue);
      expect(denied.message, isNull, reason: 'لا مفتاح صلاحيّةٍ خامّ للمدير');

      server.reply('PUT', _settings, 400,
          {'success': false, 'message': 'أقسام البوّابة غير صالحة'});
      final bad = await PortalSettingsApi.setPortalSections(
          PortalSection.usage, false);
      expect(bad.ok, isFalse);
      expect(bad.denied, isFalse);
      expect(bad.message, 'أقسام البوّابة غير صالحة');

      server.reply('PUT', _settings, 400,
          {'success': false, 'message': 'sections must be an object'});
      expect(
          (await PortalSettingsApi.setPortalSections(
                  PortalSection.usage, false))
              .message,
          isNull,
          reason: 'أثرٌ تقنيّ لا يُعرض');

      server.reply('PUT', _settings, 503,
          {'success': false, 'message': 'إعدادات البوّابة غير متاحة بعد'});
      final down = await PortalSettingsApi.setPortalSections(
          PortalSection.usage, false);
      expect(down.ok, isFalse);
      expect(down.denied, isFalse);
      expect(down.sections, isNull);

      server.on('PUT', _settings, simTimeout);
      final slow = await PortalSettingsApi.setPortalSections(
          PortalSection.usage, false);
      expect(slow.ok, isFalse);
      expect(slow.message, isNull);
    });
  });

  // ═════════════════════════ المالك ═════════════════════════

  group('المالك', () {
    testWidgets('🚨 المفتاحان تحت مفتاح البوّابة بحالتهما من الخادم',
        (t) async {
      settings(sections: const {'connection': true, 'usage': false});
      await open(t);
      expect(find.text(_title), findsOneWidget);
      expect(find.byType(Switch), findsNWidgets(3));
      expect(valueOf(t, _connection), isTrue);
      expect(valueOf(t, _usage), isFalse);
      expect(find.text(_connectionHint), findsOneWidget);
      expect(find.text(_usageHint), findsNothing,
          reason: 'المخفيّ يقول إنّه مخفي');
      expect(
          find.descendant(of: tile(_usage), matching: find.text(_hiddenHint)),
          findsOneWidget);
      expect(find.byIcon(LucideIcons.wifi), findsOneWidget);
      expect(find.byIcon(LucideIcons.eyeOff), findsOneWidget);
      // الترتيب: مفتاح البوّابة ← الاتصال ← الاستهلاك ← السجلّ.
      double y(String s) => t.getTopLeft(find.text(s)).dy;
      expect(y(_portal), lessThan(y(_title)));
      expect(y(_title), lessThan(y(_connection)));
      expect(y(_connection), lessThan(y(_usage)));
      expect(y(_usage), lessThan(y('آخر دخول المشتركين')));
      expect(server.calls('PUT', _settings), isEmpty);
    });

    testWidgets(
        '🚨 خادمٌ لا يرسل sections: لا مفاتيح أقسام (حفظٌ لا يقرؤه أحد)',
        (t) async {
      settings(sections: null);
      await open(t);
      expect(find.text(_title), findsNothing);
      expect(find.text(_connection), findsNothing);
      expect(find.text(_usage), findsNothing);
      expect(find.byType(Switch), findsOneWidget,
          reason: 'مفتاح البوّابة وحده');
    });

    testWidgets(
        '🚨 النقرة تُحفظ فوراً بلا سؤال: PUT {sections:{مفتاحها}} — دوّارةٌ ثمّ الحالة',
        (t) async {
      settings();
      mergingServer();
      server.hold('PUT', _settings);
      await open(t);

      await t.tap(switchOf(_connection));
      await flush(t);
      expect(find.byType(BottomSheet), findsNothing,
          reason: 'الإخفاء بلا سؤال');
      expect(sentSections(), [
        {'connection': false},
      ]);
      // أثناء الحفظ: دوّارةٌ مكان المفتاح، والتلميح بالحالة الجديدة.
      expect(spinnerOf(_connection), findsOneWidget);
      expect(switchOf(_connection), findsNothing);
      expect(
          find.descendant(
              of: tile(_connection), matching: find.text(_hiddenHint)),
          findsOneWidget);

      server.release('PUT', _settings);
      await t.pumpAndSettle();
      expect(valueOf(t, _connection), isFalse);
      expect(valueOf(t, _usage), isTrue);
      expect(find.byType(SnackBar), findsNothing,
          reason: 'النجاح بلا إشعار — كمفتاح البوّابة');

      // والإظهار بنقرةٍ مثلها.
      await t.tap(switchOf(_connection));
      await t.pumpAndSettle();
      expect(sentSections().last, {'connection': true});
      expect(valueOf(t, _connection), isTrue);
      expect(find.text(_connectionHint), findsOneWidget);
    });

    testWidgets('🚨 حفظٌ تعذّر (٥٠٣): المفتاح يرجع كما كان + رسالة', (t) async {
      settings();
      server.reply('PUT', _settings, 503,
          {'success': false, 'message': 'إعدادات البوّابة غير متاحة بعد'});
      await open(t);
      await t.tap(switchOf(_usage));
      await t.pumpAndSettle();
      expect(server.calls('PUT', _settings), hasLength(1));
      expect(valueOf(t, _usage), isTrue, reason: 'لم يُحفظ — لا تفاؤلٌ باقٍ');
      expect(find.text(_usageHint), findsOneWidget);
      expect(find.text(_failed), findsOneWidget);
      await simDrain(t);
    });

    testWidgets('رفضٌ برسالةٍ عربيّة: يرجع وتُعرض رسالته', (t) async {
      settings();
      server.reply('PUT', _settings, 400,
          {'success': false, 'message': 'أقسام البوّابة غير متاحة لحسابك'});
      await open(t);
      await t.tap(switchOf(_connection));
      await t.pumpAndSettle();
      expect(valueOf(t, _connection), isTrue);
      expect(find.text('أقسام البوّابة غير متاحة لحسابك'), findsOneWidget);
      await simDrain(t);
    });

    testWidgets('ما خزّنه الخادم هو ما يُعرض', (t) async {
      settings();
      server.reply('PUT', _settings, 200, {
        'success': true,
        'sections': {'connection': false, 'usage': false, 'device': false},
      });
      await open(t);
      await t.tap(switchOf(_connection));
      await t.pumpAndSettle();
      expect(valueOf(t, _connection), isFalse);
      expect(valueOf(t, _usage), isFalse, reason: 'المخزَّن لا المتوقَّع');
    });

    testWidgets(
        '🚨 نقرتان على القسمين: الحفظ بالدور، وكلٌّ بمفتاحه وحده',
        (t) async {
      settings();
      final stored = mergingServer();
      server.hold('PUT', _settings);
      await open(t);

      await t.tap(switchOf(_connection));
      await flush(t);
      await t.tap(switchOf(_usage));
      await flush(t);
      expect(server.calls('PUT', _settings), hasLength(1),
          reason: 'الثاني ينتظر دوره');
      expect(spinnerOf(_connection), findsOneWidget);
      expect(spinnerOf(_usage), findsOneWidget);

      server.release('PUT', _settings);
      await t.pumpAndSettle();
      expect(sentSections(), [
        {'connection': false},
        {'usage': false},
      ]);
      expect(stored, {'connection': false, 'usage': false, 'device': false});
      expect(valueOf(t, _connection), isFalse);
      expect(valueOf(t, _usage), isFalse);
    });

    testWidgets(
        '🚨 الأوّل رُفض والثاني بالدور: الثاني لا يحمل قيمة الأوّل المتفائلة',
        (t) async {
      settings();
      var n = 0;
      server.on('PUT', _settings, (req) {
        n++;
        if (n == 1) {
          return const SimReply(
              400, {'success': false, 'message': 'تعذّر حفظ القسم'});
        }
        // خادمٌ يردّ ما وصله وحده (جزئيّاً): الناقص يبقى كما عُرف.
        return SimReply(
            200, {'success': true, 'sections': (req.data as Map)['sections']});
      });
      server.hold('PUT', _settings);
      await open(t);

      await t.tap(switchOf(_connection));
      await flush(t);
      await t.tap(switchOf(_usage));
      await flush(t);
      server.release('PUT', _settings);
      await t.pumpAndSettle();
      expect(sentSections(), [
        {'connection': false},
        {'usage': false},
      ]);
      expect(valueOf(t, _connection), isTrue, reason: 'رجع بعد رفضه');
      expect(valueOf(t, _usage), isFalse);
      expect(find.text('تعذّر حفظ القسم'), findsOneWidget);
      await simDrain(t);
    });

    testWidgets('الجهاز بلا مفتاحٍ بعد — ولا يُرسل أبداً (يبقى كما اختير)',
        (t) async {
      settings(
          sections: const {'connection': true, 'usage': true, 'device': true});
      final stored = mergingServer(
          const {'connection': true, 'usage': true, 'device': true});
      await open(t);
      expect(find.byType(Switch), findsNWidgets(3), reason: 'لا مفتاح للجهاز');
      await t.tap(switchOf(_usage));
      await t.pumpAndSettle();
      expect(sentSections().single, {'usage': false});
      expect(stored['device'], isTrue);
    });

    testWidgets(
        '🚨 الويب أخفى قسماً والشاشة مفتوحة بنسخةٍ قديمة: النقرة ترسل مفتاحها '
        'وحده، فلا يعود ما أخفاه الويب — والمعروض بعدها ردّ الخادم', (t) async {
      settings(); // الشاشة فُتحت والاستهلاك ظاهر
      final stored = mergingServer();
      await open(t);
      expect(valueOf(t, _usage), isTrue);
      stored['usage'] = false; // الويب /v2 أخفاه بعد فتح الشاشة (PUT {usage:false})

      await t.tap(switchOf(_connection));
      await t.pumpAndSettle();
      expect(sentSections().single, {'connection': false},
          reason: 'لا «usage: true» من النسخة القديمة');
      expect(stored, {'connection': false, 'usage': false, 'device': false},
          reason: 'إخفاء الويب باقٍ');
      expect(valueOf(t, _connection), isFalse);
      expect(valueOf(t, _usage), isFalse,
          reason: 'الشاشة تأخذ الأقسام كاملةً من ردّ الحفظ');
    });

    testWidgets('مفتاح البوّابة لا يمسّ الأقسام: {enabled} وحده', (t) async {
      settings(sections: const {'connection': false, 'usage': true});
      server.on(
          'PUT',
          _settings,
          (req) => SimReply(200, {
                'success': true,
                'enabled': (req.data as Map)['enabled'],
              }));
      await open(t);
      await t.tap(switchOf(_portal));
      await t.pumpAndSettle();
      await t.tap(find.descendant(
          of: find.byType(BottomSheet), matching: find.text('إيقاف البوابة')));
      await t.pumpAndSettle();
      expect(server.bodies('PUT', _settings).single, {'enabled': false});
      expect(valueOf(t, _portal), isFalse);
      expect(valueOf(t, _connection), isFalse);
      expect(valueOf(t, _usage), isTrue);
    });

    testWidgets(
        '🚨 سحبٌ للتحديث بدأ قبل الحفظ ووصل بعده: لا يعيد المفتاح لقيمته القديمة',
        (t) async {
      settings(); // يردّ الاستهلاك ظاهراً — ولو بعد إخفائه (جلبٌ سبق الحفظ)
      mergingServer();
      await open(t);
      server.hold('GET', _settings);
      unawaited(t
          .widget<RefreshIndicator>(find.byType(RefreshIndicator).first)
          .onRefresh());
      await flush(t);
      expect(server.calls('GET', _settings), hasLength(2));

      await t.tap(switchOf(_usage));
      await t.pumpAndSettle();
      expect(valueOf(t, _usage), isFalse);

      server.release('GET', _settings);
      await t.pumpAndSettle();
      expect(valueOf(t, _usage), isFalse,
          reason: 'الجلب أقدم من الحفظ — لا يكتب فوقه');
      expect(valueOf(t, _connection), isTrue);
    });

    testWidgets('ايرث لنك: المفتاحان للمالك على المسار نفسه', (t) async {
      ProviderService.debugSet('earthlink');
      settings();
      mergingServer();
      await open(t);
      expect(find.byType(Switch), findsNWidgets(3));
      await t.tap(switchOf(_connection));
      await t.pumpAndSettle();
      expect(sentSections().single, {'connection': false});
      expect(valueOf(t, _connection), isFalse);
    });
  });

  // ═════════════════════════ الموظّف ═════════════════════════

  group('الموظّف', () {
    testWidgets(
        '🚨 موظّف ساس بلا settings.edit: المفتاحان بمكانهما مقفلَين بحالتهما — والنقر لا يحفظ',
        (t) async {
      PermissionsService.debugSet(isEmployee: true);
      settings(sections: const {'connection': true, 'usage': false});
      await open(t);
      expect(find.text(_title), findsOneWidget);
      expect(find.text(_connection), findsOneWidget);
      expect(find.text(_usage), findsOneWidget);
      expect(find.byType(Switch), findsNothing);
      expect(
          find.descendant(of: tile(_connection), matching: find.text('يظهر')),
          findsOneWidget);
      expect(find.descendant(of: tile(_usage), matching: find.text('مخفي')),
          findsOneWidget);
      expect(
          find.descendant(
              of: tile(_connection), matching: find.byType(PermLockIcon)),
          findsOneWidget);
      expect(
          find.descendant(
              of: tile(_usage), matching: find.byType(PermLockIcon)),
          findsOneWidget);

      await t.tap(find.text(_usage));
      await t.pump();
      expect(find.text(_askManager), findsOneWidget);
      expect(server.calls('PUT', _settings), isEmpty);
      await simDrain(t);
    });

    testWidgets('موظّف ساس بـsettings.edit: المفتاحان له', (t) async {
      PermissionsService.debugSet(
          isEmployee: true, permissions: const {'settings.edit': true});
      settings();
      mergingServer();
      await open(t);
      expect(find.byType(Switch), findsNWidgets(3));
      expect(find.byType(PermLockIcon), findsWidgets,
          reason: 'السجلّ وحده مقفل (بلا subscribers.view)');
      expect(
          find.descendant(
              of: tile(_connection), matching: find.byType(PermLockIcon)),
          findsNothing);
      await t.tap(switchOf(_usage));
      await t.pumpAndSettle();
      expect(sentSections().single, {'usage': false});
    });

    testWidgets('🚨 موظّف ايرث لنك: مقفلان، وقفلهما «لصاحب الحساب»', (t) async {
      ProviderService.debugSet('earthlink');
      PermissionsService.debugSet(
          isEmployee: true, permissions: const {'subscribers.view': true});
      settings();
      await open(t);
      expect(find.byType(TabBar), findsNothing);
      expect(find.text(_connection), findsOneWidget);
      expect(find.byType(Switch), findsNothing);
      await t.tap(find.text(_connection));
      await t.pump();
      expect(find.text(_ownerOnly), findsOneWidget,
          reason: 'لا «اطلبها من مديرك» لما لا يملك مديره منحه');
      expect(find.text(_askManager), findsNothing);
      expect(server.calls('PUT', _settings), isEmpty);
      await simDrain(t);
    });
  });
}
