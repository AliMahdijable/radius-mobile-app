import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/subscribers/sheets/activate_sheet.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:rad_mysvcs/services/provider_service.dart';
import 'package:rad_mysvcs/widgets/package_picker_field.dart';

import 'sim_el/sim_harness.dart';

/// المشروع الوطنيّ — «الباقة القديمة» في نافذة التفعيل (١٤ نوفمبر — الخادم 8639fab، مفتاح watani_legacy؛ المالك: «من يريد يفعل مشترك
/// قديم ع الباقة شون يتبدل بدون ما نحدث التطبيق»). الإصلاح خادميّ وحده، وهذا الاختبار يثبّت ما يعتمد عليه من سلوك التطبيق (نفسه في
/// المنشور 175–181): ردٌّ بلا «حاليّة» (`profile_id` فارغ) ⇒ أوّل باقةٍ معروضة — وهي التي يقول الخادم إنّها تقابل القديمة — تُختار،
/// التنبيه يظهر كاملاً، والتفعيل يرسلها صراحةً بـ`change_type: now`. الأرقام والأسماء والنصّ كما يردّها الخادم الحيّ (قراءة ١٤ نوفمبر).
const _idx = '13293073';
const _proMax = 1866227206, _basic = 46517085, _plus = 1852273845, _turbo = 1493156315;
const _names = {_proMax: 'برو ماكس 500 Mbps', _basic: 'أساسي 60 Mbps', _plus: 'بلس 125 Mbps', _turbo: 'تيربو 250 Mbps'};
const _prices = {_proMax: 100000, _basic: 35000, _plus: 45000, _turbo: 65000};

String _note({required String old, int? successor, bool active = false}) => 'باقته «$old» قديمة لا تُجدَّد في المشروع الوطني'
    '${active ? ' وهو فعّال: التبديل الآن قد يضيّع أيّامه الباقية' : ''}'
    '${successor != null ? ' — تقابلها «${_names[successor]}» (المختارة، ولك تغييرها)' : ' — اختر باقةً حاليّة يتحوّل إليها مع التفعيل'}';

/// ردّ الخادم لمشتركٍ باقته قديمة: المقابلة أوّلاً (إن وُجدت) ثمّ البقيّة بترتيبها، و`profile_id` فارغ.
Map<String, dynamic> _legacy({String old = 'Fiber 150', int? successor = _proMax, bool active = false}) {
  final order = [if (successor != null) successor, for (final id in [_basic, _plus, _turbo, _proMax]) if (id != successor) id];
  final first = order.first;
  return {
    'success': true,
    'data': {
      'provider': 'watani', 'provider_label': 'المشروع الوطني', 'idx': _idx, 'username': 'dev-user',
      'profile_name': old, 'profile_id': null,
      'legacy_plan': {'id': 1665159867, 'name': old, 'successor_id': successor},
      'user_price': _prices[first], 'base_price': _prices[first], 'price_after_discount': _prices[first], 'discount_amount': 0,
      'price_source': 'watani', 'custom_price': null, 'overridden_discount': 0, 'needs_repricing': false,
      'current_balance': 0, 'manager_balance': 478063,
      'expiration': active ? '2026-11-20 10:00:00' : '2026-11-05 10:00:00', 'remaining_days': active ? 6 : -9,
      'packages': [for (final id in order) {'id': id, 'name': _names[id], 'price': _prices[id], 'cost': 0, 'days': null}],
      'package_change_allowed': true, 'card_payment': false,
      'package_change_note': _note(old: old, successor: successor, active: active),
      'package_change_timing': ['now'],
      'subscription_active': active, 'can_change_profile': false, 'can_change_profile_active': false,
      'immediate_keeps_date': true, 'schedule_supported': false, 'profile_change': null,
    },
  };
}

void main() {
  late SimServer server;

  setUpAll(simSetUpAll);

  setUp(() async {
    server = await simSetUp(secure: {'auth.admin_id': 'watani:2963757', 'auth.admin_username': 'owner'});
    PermissionsService.debugSet(isEmployee: false);
    ProviderService.debugSet('watani', label: 'المشروع الوطني');
  });

  tearDown(() {
    PermissionsService.debugReset();
    ProviderService.debugSet(null);
  });

  Future<void> open(WidgetTester t, {SimVariant v = const SimVariant(390, dark: false), String old = 'Fiber 150'}) async {
    // صفّ القائمة ما زال على الباقة القديمة (رقمها ليس من الباقات المعروضة)
    final sub = Subscriber.fromJson({'idx': _idx, 'username': 'dev-user', 'firstname': 'مشترك', 'profile_id': 1665159867, 'profile_name': old});
    await pumpSim(t, v, home: (_) => Scaffold(
          body: Builder(builder: (c) => Center(child: TextButton(onPressed: () => showActivateSheet(c, sub), child: const Text('open')))),
        ));
    await t.tap(find.text('open'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    await t.pumpAndSettle();
  }

  PackagePickerField picker(WidgetTester t) => t.widget<PackagePickerField>(find.byType(PackagePickerField));

  testWidgets('النافذة تفتح والمقابلة «برو ماكس» مختارة بسعرها والتنبيه كامل ⇒ «تجديد الآن» يرسلها صراحةً بـchange_type now', (t) async {
    server.reply('GET', '/api/v2/subscribers/$_idx/activation-data', 200, _legacy());
    server.reply('POST', '/api/v2/subscribers/$_idx/activate', 200, {
      'success': true, 'outcome': 'applied', 'amount': 100000,
      'data': {'new_balance': 0, 'updated': {'idx': _idx, 'username': 'dev-user', 'expiration': '2026-12-14 17:00:00', 'remaining_days': 30, 'notes': '0',
        'enabled': 1, 'profile_id': _proMax, 'profile_name': _names[_proMax]}},
    });
    await open(t);
    expect(find.textContaining('لا سعر بيع'), findsNothing);
    final p = picker(t);
    expect((p.selectedId, p.currentId, p.enabled), ('$_proMax', null, true), reason: 'المقابلة أوّل القائمة ⇒ هي المختارة، ولا «حاليّة»');
    expect(p.options.map((o) => o.id).toList(), ['$_proMax', '$_basic', '$_plus', '$_turbo']);
    expect(find.text(_note(old: 'Fiber 150', successor: _proMax)), findsOneWidget, reason: 'التنبيه ظاهر بنصّ الخادم');
    await t.ensureVisible(find.text('تجديد الآن'));
    await t.pumpAndSettle();
    await t.tap(find.text('تجديد الآن'));
    await t.pump();
    await t.pumpAndSettle();
    final body = server.bodies('POST', '/api/v2/subscribers/$_idx/activate').single;
    expect((body['profile_id'], body['change_type']), (_proMax, 'now'));
    expect(body.containsKey('months'), isFalse);
    await simDrain(t);
  });

  testWidgets('الوكيل يغيّر المختارة إلى «أساسي» ⇒ تُرسل هي لا المقابلة', (t) async {
    server.reply('GET', '/api/v2/subscribers/$_idx/activation-data', 200, _legacy());
    server.reply('POST', '/api/v2/subscribers/$_idx/activate', 200, {'success': true, 'outcome': 'applied', 'amount': 35000, 'data': {'new_balance': 0}});
    await open(t);
    final pf = find.byType(PackagePickerField);
    await t.ensureVisible(pf);
    await t.pumpAndSettle();
    await t.tap(pf);
    await t.pumpAndSettle();
    await t.tap(find.textContaining('أساسي 60').last);
    await t.pumpAndSettle();
    expect(picker(t).selectedId, '$_basic');
    expect(find.textContaining('قديمة لا تُجدَّد'), findsOneWidget, reason: 'التنبيه باقٍ لأيّ باقةٍ مختارة');
    await t.ensureVisible(find.text('تجديد الآن'));
    await t.pumpAndSettle();
    await t.tap(find.text('تجديد الآن'));
    await t.pump();
    await t.pumpAndSettle();
    final body = server.bodies('POST', '/api/v2/subscribers/$_idx/activate').single;
    expect((body['profile_id'], body['change_type']), (_basic, 'now'));
    await simDrain(t);
  });

  testWidgets('بلا مقابلٍ معلَن («Fiber 40»): أوّل القائمة مختارة والتنبيه يطلب الاختيار', (t) async {
    server.reply('GET', '/api/v2/subscribers/$_idx/activation-data', 200, _legacy(old: 'Fiber 40', successor: null));
    await open(t, old: 'Fiber 40');
    expect(picker(t).selectedId, '$_basic');
    expect(find.text(_note(old: 'Fiber 40')), findsOneWidget);
    await simDrain(t);
  });

  testWidgets('الفعّال على باقةٍ قديمة: التحذير من ضياع أيّامه ظاهر قبل التأكيد', (t) async {
    server.reply('GET', '/api/v2/subscribers/$_idx/activation-data', 200, _legacy(active: true));
    await open(t);
    expect(find.text(_note(old: 'Fiber 150', successor: _proMax, active: true)), findsOneWidget);
    expect(find.textContaining('التبديل الآن قد يضيّع أيّامه الباقية'), findsOneWidget);
    expect(picker(t).selectedId, '$_proMax');
    await simDrain(t);
  });

  // قاعدة المالك: لا نصّ يخرج من كرت — أطول تنبيه (فعّال + أطول اسمين) يظهر كاملاً في كرت الأربعة أسطر على كلّ عرض.
  for (final v in const [SimVariant(320, dark: false), SimVariant(360, dark: false), SimVariant(390, dark: true)]) {
    testWidgets('أطول تنبيهٍ لا يُقصّ ولا يفيض ($v)', (t) async {
      server.reply('GET', '/api/v2/subscribers/$_idx/activation-data', 200, _legacy(active: true));
      await open(t, v: v);
      final note = find.text(_note(old: 'Fiber 150', successor: _proMax, active: true));
      await t.ensureVisible(note);
      await t.pumpAndSettle();
      final para = t.renderObject<RenderParagraph>(find.descendant(of: note, matching: find.byType(RichText)).first);
      expect(para.didExceedMaxLines, isFalse, reason: 'التنبيه كاملٌ بلا «…»');
      expect(t.takeException(), isNull);
      await simDrain(t);
    });
  }
}
