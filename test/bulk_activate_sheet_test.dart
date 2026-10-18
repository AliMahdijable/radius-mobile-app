import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/bulk_activate_api.dart';
import 'package:rad_mysvcs/core/widgets/design_sheet.dart' show SheetCloseButton;
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/subscribers/sheets/bulk_activate_sheet.dart';
import 'package:rad_mysvcs/screens/subscribers/subscribers_screen.dart';
import 'package:rad_mysvcs/theme/colors.dart';

import 'sim_el/sim_harness.dart' show simText;
import 'visual_perm/visual_perm_harness.dart';

/// حارس التجديد الجماعيّ — جهة التطبيق (١٨ أكتوبر).
///
/// ما يحرسه هذا الملفّ (والمنطق في `bulk_activate_guard_test.dart`):
/// - «تجديد» الجماعيّ مقفلٌ **بسبب الخادم** حين لا يقدر حساب الساس (كارت فقط،
///   بلا تفعيلٍ من الرصيد) — بمكانه، ولا يفتح الورقة ولا يجلب شيئاً.
/// - الحكم المجهول (خادمٌ أقدم) لا يقفل.
/// - الدفعة تقف عند أوّل رفضٍ قاطع ولا ترسل بعده، والحصيلة واضحة
///   (تمّ · رُفض · لم يُنفَّذ)، والمتمّ لا يُعاد أبداً.
/// - الفحص المسبق للرصيد يقصر الدفعة على ما يكفيه.
/// - الجلب المسبق محدود التزامن ويقف عند 403 — بلا «تعذّر الجلب» لصلاحيّة.
/// - (مراجعة ١٨ أكتوبر) الرفض الذي يخصّ صفّاً لا يحبس «تجديد الباقين»؛ ومن
///   لم يُفعَّل يبقى محدّداً بعد الإغلاق (كالويب) أيّاً كان طريق الإغلاق؛
///   وتحديدٌ أكبر من حدّ الدفعة يُجدَّد أوّله لا يُرفض؛ وجلسة الساس المنتهية
///   تُجدَّد ويُعاد الصفّ مرّةً؛ والضغط على المقفل يعيد سؤال الخادم.
///
/// ⚠️ لا تفعيل حقيقيّ: الخادم وهميّ على `ApiClient.dio`.

const _cardOnlyReason =
    'هذا الحساب في الساس يفعّل بالكارت فقط، والتفعيل الجماعيّ يخصم من الرصيد — فعّل كلّ مشترك من نافذته';

const _phone320Dark = VisualDevice('_320d', Size(320, 640), 2, dark: true);

Map<String, Object?> _capBody({
  required bool supported,
  String code = 'OK',
  String? reason,
  int maxBatch = 100,
}) =>
    {
      'success': true,
      'data': {
        'provider': 'sas4',
        'supported': supported,
        'code': code,
        'reason': reason,
        'method': supported ? 'credit' : null,
        'checked': true,
        'limits': {
          'max_batch': maxBatch,
          'prefetch_concurrency': 4,
          'run_concurrency': 1,
        },
      },
    };

/// خادم الدفعة الوهميّ — يغلّف [VisualServer] ويأخذ مسارات الحارس والتفعيل.
class _BulkServer implements HttpClientAdapter {
  _BulkServer(this.inner);
  final VisualServer inner;

  /// جسم مسار القدرة — `null` ⇒ ما يردّه [VisualServer] (فارغٌ ناجح = مجهول).
  Map<String, Object?>? capability;

  /// بيانات التفعيل لكلّ idx (ناجحة)، أو [activationError] لكلّها.
  Map<String, Object?> Function(String idx) activationData = (idx) => {
        'idx': idx,
        'username': 'u$idx',
        'user_price': 25000,
        'price_after_discount': 25000,
        'discount_amount': 0,
        'base_price': 25000,
        'current_balance': 0,
        'manager_cost': 10000,
        'manager_balance': 1000000,
        'profile_name': 'Economy',
        'units': 1,
      };
  (int, Map<String, Object?>)? activationError;

  /// ردّ التفعيل لكلّ idx.
  FutureOr<(int, Map<String, Object?>)> Function(String idx) activate =
      (_) => (200, {'success': true});

  final capabilityCalls = <String>[];
  final activationCalls = <String>[];
  final activateCalls = <String>[];
  final activateBodies = <Map<String, dynamic>>[];
  int _inFlightData = 0;
  int peakDataInFlight = 0;

  static final _dataRe =
      RegExp(r'^/api/v2/subscribers/([^/]+)/activation-data$');
  static final _activateRe = RegExp(r'^/api/v2/subscribers/([^/]+)/activate$');

  static ResponseBody _json(int status, Object body) =>
      ResponseBody.fromString(jsonEncode(body), status, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      });

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final p = o.path;
    final get = o.method.toUpperCase() == 'GET';
    if (get && p == BulkActivateApi.path) {
      capabilityCalls.add(p);
      final c = capability;
      if (c != null) return _json(200, c);
    }
    final dm = _dataRe.firstMatch(p);
    if (get && dm != null) {
      final idx = dm.group(1)!;
      activationCalls.add(idx);
      _inFlightData++;
      if (_inFlightData > peakDataInFlight) peakDataInFlight = _inFlightData;
      await Future<void>.delayed(const Duration(milliseconds: 30));
      _inFlightData--;
      final err = activationError;
      if (err != null) return _json(err.$1, err.$2);
      return _json(200, {'success': true, 'data': activationData(idx)});
    }
    final am = _activateRe.firstMatch(p);
    if (!get && am != null) {
      final idx = am.group(1)!;
      activateCalls.add(idx);
      activateBodies.add(Map<String, dynamic>.from(o.data as Map));
      final (status, body) = await activate(idx);
      return _json(status, body);
    }
    return inner.fetch(o, requestStream, cancelFuture);
  }

  @override
  void close({bool force = false}) {}
}

String _sasTime(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)} '
      '${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
}

List<Subscriber> _subs(int n) => [
      for (var i = 1; i <= n; i++)
        Subscriber.fromJson({
          'idx': '$i',
          'username': 'user$i@najaf',
          'firstname': 'مشترك',
          'lastname': 'رقم $i',
          'profile_name': 'Economy',
          'profile_id': 7,
          'expiration':
              _sasTime(DateTime.now().subtract(const Duration(days: 2))),
          'enabled': 1,
        }),
    ];

/// صفحةٌ بزرّ «افتح» يفتح الورقة — و[onResult] بما تعيده (من يبقى محدّداً).
Widget _launcher(List<Subscriber> subs,
        {void Function(Set<String>? keep)? onResult}) =>
    Scaffold(
      backgroundColor: AppColors.bg,
      body: Builder(
        builder: (c) => Center(
          child: TextButton(
            onPressed: () async {
              final keep = await showBulkActivateSheet(c, subs: subs);
              onResult?.call(keep);
            },
            child: const Text('افتح'),
          ),
        ),
      ),
    );

Future<_BulkServer> _setUp(Scenario s) async {
  final inner = await visualSetUp(s);
  BulkActivateApi.reset();
  final server = _BulkServer(inner);
  ApiClient.dio.httpClientAdapter = server;
  return server;
}

Future<void> _openSheet(WidgetTester t, List<Subscriber> subs,
    {VisualDevice device = phone,
    void Function(Set<String>? keep)? onResult}) async {
  await pumpVisual(t, device,
      home: (_) => _launcher(subs, onResult: onResult));
  await settle(t, seconds: 1);
  await t.tap(find.text('افتح'));
  await settle(t, seconds: 2);
}

Future<void> _drain(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 8));
  BulkActivateApi.reset();
  bulkSessionRefresher = _defaultRefresher;
  await visualTearDown();
}

/// المجدِّد الأصليّ — يُعاد بعد كلّ اختبارٍ يستبدله.
final Future<bool> Function() _defaultRefresher = bulkSessionRefresher;

Finder _footer(String label) => find.text(label);

/// نصٌّ داخل شريط الحصيلة وحده (الإشعار الطافي يحمل العدّ نفسه).
Finder _inReport(String text) => find.descendant(
    of: find.byKey(const ValueKey('bulk-report')), matching: simText(text));

/// يضغط زرّ الورقة ثمّ زرّ التأكيد في الحوار.
Future<void> _submit(WidgetTester t, String footer, String confirm) async {
  await t.tap(_footer(footer));
  await settle(t, seconds: 1);
  expect(find.byType(AlertDialog), findsOneWidget);
  await t.tap(find.text(confirm));
  await settle(t, seconds: 3);
}

void main() {
  setUpAll(visualSetUpAll);

  // ═══════════════════════ الزرّ في شريط التحديد ═══════════════════════
  group('«تجديد» الجماعيّ — حكم الخادم في الشريط', () {
    void tolerateRowNoise() {
      // فيضان نصف بكسلٍ قائمٌ في صفّ المشترك بخطّ الاختبار (انظر
      // `subscribers_tab_locked_test`) — ليس موضوع هذا الملفّ.
      final prev = FlutterError.onError;
      FlutterError.onError = (d) {
        if (d.exceptionAsString().contains('overflowed')) return;
        prev?.call(d);
      };
      addTearDown(() => FlutterError.onError = prev);
    }

    Future<_BulkServer> openList(WidgetTester t,
        {Map<String, Object?>? capability}) async {
      tolerateRowNoise();
      final server = await _setUp(s1bSasOwner);
      server.capability = capability;
      await pumpVisual(t, phone, home: (_) => const SubscribersScreen());
      await settle(t, seconds: 2);
      await t.longPress(simText('علي حسن الموسوي').first);
      await settle(t, seconds: 1);
      return server;
    }

    Finder renewPill() => find.ancestor(
          of: find.text('تجديد (1)'),
          matching: find.byWidgetPredicate(
              (w) => w.runtimeType.toString() == '_PrimaryPill'),
        );

    testWidgets(
        '🚨 حساب الساس يفعّل بالكارت فقط: «تجديد» بمكانه مقفلٌ بسبب الخادم ولا يفتح الورقة',
        (t) async {
      final server = await openList(t,
          capability: _capBody(
              supported: false, code: 'CARD_ONLY', reason: _cardOnlyReason));
      expect(server.capabilityCalls, hasLength(1),
          reason: 'يُسأل لحظة دخول التحديد');
      expect(renewPill(), findsOneWidget, reason: 'بمكانه لا مخفيّ');
      expect(
          find.descendant(
              of: renewPill(), matching: find.byIcon(LucideIcons.lock)),
          findsOneWidget);

      await t.tap(renewPill());
      await t.pump();
      expect(find.text(_cardOnlyReason), findsOneWidget,
          reason: 'سبب الخادم لا «اطلبها من مديرك»');
      expect(find.byType(BottomSheet), findsNothing);
      await t.pump(const Duration(seconds: 3));
      expect(server.activationCalls, isEmpty, reason: 'لا ورقة ولا جلب');
      await _drain(t);
    });

    testWidgets(
        '🚨 أكثر من حدّ الدفعة: تُفتح بأوّلهم (لا رفض)، والإغلاق بلا تجديد يُبقي التحديد كلّه',
        (t) async {
      final server =
          await openList(t, capability: _capBody(supported: true, maxBatch: 1));
      await t.tap(simText('حيدر سالم').first);
      await settle(t, seconds: 1);
      final pill2 = find.ancestor(
        of: find.text('تجديد (2)'),
        matching: find.byWidgetPredicate(
            (w) => w.runtimeType.toString() == '_PrimaryPill'),
      );
      expect(pill2, findsOneWidget);
      await t.tap(pill2);
      await settle(t, seconds: 2);
      expect(find.byType(BottomSheet), findsOneWidget, reason: 'لا رفضٌ للتحديد كلّه');
      expect(server.activationCalls, hasLength(1), reason: 'الدفعة أوّلهم وحده');
      expect(find.byKey(const ValueKey('bulk-deferred')), findsOneWidget);
      expect(
          simText(
              'تُجدَّد في هذه الدفعة أوّل 1 من 2 المحدَّدين — الباقون (1) يبقون محدّدين للدفعة التالية'),
          findsOneWidget);
      await t.tap(find.byType(SheetCloseButton));
      await settle(t, seconds: 1);
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('تجديد (2)'), findsOneWidget,
          reason: 'لم يُجدَّد أحد ⇒ التحديد كما هو');
      await _drain(t);
    });

    testWidgets(
        '🚨 قفلٌ بحكمٍ قديم: الضغط يعيد سؤال الخادم، ومنحُ الصلاحيّة يفتح «تجديد» بلا خروج',
        (t) async {
      final server = await openList(t,
          capability: _capBody(
              supported: false, code: 'CARD_ONLY', reason: _cardOnlyReason));
      expect(server.capabilityCalls, hasLength(1));
      // الشركة منحت «التفعيل من الرصيد» بعد أن كوشت «كارت فقط».
      server.capability = _capBody(supported: true);
      await t.tap(renewPill());
      await t.pump();
      expect(find.text(_cardOnlyReason), findsOneWidget,
          reason: 'السبب يُعرض أوّلاً');
      await settle(t, seconds: 3);
      expect(server.capabilityCalls, hasLength(2), reason: 'سؤالٌ طازج');
      expect(
          find.descendant(
              of: renewPill(), matching: find.byIcon(LucideIcons.lock)),
          findsNothing,
          reason: 'انفتح الزرّ بالحكم الجديد');
      await _drain(t);
    });

    testWidgets('حكمٌ مجهول (خادمٌ أقدم بلا المسار): «تجديد» مفتوحٌ كما كان',
        (t) async {
      await openList(t); // VisualServer يردّ فارغاً ناجحاً ⇒ مجهول
      expect(renewPill(), findsOneWidget);
      expect(
          find.descendant(
              of: renewPill(), matching: find.byIcon(LucideIcons.lock)),
          findsNothing);
      expect(
          find.descendant(
              of: renewPill(), matching: find.byIcon(LucideIcons.calendarPlus)),
          findsOneWidget);
      await _drain(t);
    });
  });

  // ═══════════════════════ الورقة ═══════════════════════
  group('ورقة التجديد الجماعيّ', () {
    testWidgets(
        '🚨 رصيدٌ ينفد في المنتصف: تقف عند أوّل رفض، والحصيلة واضحة، والمتمّ لا يُعاد',
        (t) async {
      final server = await _setUp(s1bSasOwner);
      server.capability = _capBody(supported: true);
      server.activate = (idx) => idx == '2'
          ? (
              422,
              {
                'success': false,
                'code': 'INSUFFICIENT_BALANCE',
                'message': 'رصيد المدير غير كافٍ لإتمام العملية',
                'sas4_code': 'rsp_insufficient_balance',
              }
            )
          : (200, {'success': true});
      await _openSheet(t, _subs(3));
      expect(server.activationCalls.toSet(), {'1', '2', '3'});
      expect(find.byKey(const ValueKey('bulk-preflight')), findsNothing,
          reason: 'الرصيد يكفي ⇒ لا تحذير فوق الزرّ');

      await t.tap(_footer('تجديد 3 اشتراك'));
      await settle(t, seconds: 1);
      expect(
          find.descendant(
              of: find.byType(AlertDialog),
              matching: simText(
                  'رصيدك 1,000,000 د.ع · الكلفة عليك 30,000 د.ع')),
          findsOneWidget,
          reason: 'الرصيد والكلفة معروفان ⇒ يُقالان قبل التأكيد');
      await t.tap(find.text('تجديد الآن'));
      await settle(t, seconds: 3);
      expect(server.activateCalls, ['1', '2'], reason: 'لا شيء بعد الرفض القاطع');
      for (final b in server.activateBodies) {
        expect(b['bulk'], isTrue, reason: 'الخادم يعرف أنّها دفعة');
        expect(b.containsKey('method'), isFalse, reason: 'رصيدٌ ضمناً');
      }
      expect(find.byKey(const ValueKey('bulk-report')), findsOneWidget);
      expect(_inReport('تمّ 1 · رُفض 1 · لم يُنفَّذ 1'), findsOneWidget);
      expect(
          _inReport('توقّف التجديد: رصيد المدير غير كافٍ لإتمام العملية'),
          findsOneWidget);
      expect(simText('لم يُنفَّذ — توقّف التجديد قبله'), findsOneWidget);
      expect(find.byType(BottomSheet), findsOneWidget,
          reason: 'تبقى مفتوحةً بالحصيلة');
      // «تجديد الباقين»: المرفوض والذي لم يُنفَّذ وحدهما — لا الأوّل المتمّ.
      server.activate = (_) => (200, {'success': true});
      await t.tap(_footer('تجديد الباقين (2)'));
      await settle(t, seconds: 1);
      expect(find.byKey(const ValueKey('bulk-preflight')), findsNothing,
          reason: 'الساس قال «لا يكفي» ⇒ الرقم المقروء لم يعد يُصدَّق');
      await t.tap(find.text('تجديد الآن'));
      await settle(t, seconds: 3);
      expect(server.activateCalls, ['1', '2', '2', '3']);
      expect(find.byType(BottomSheet), findsNothing, reason: 'اكتملت ⇒ تُغلق');
      await _drain(t);
    });

    Map<String, Object?> Function(String) shortData({
      required int balance,
      required int cost,
    }) =>
        (idx) => {
              'idx': idx,
              'user_price': cost,
              'price_after_discount': cost,
              'current_balance': 0,
              'manager_cost': cost,
              'manager_balance': balance,
              'units': 1,
            };

    testWidgets(
        '🚨 الفحص المسبق: رصيدٌ يكفي اثنين من ثلاثة ⇒ «جدّد 2 فقط» ويُرسَل اثنان',
        (t) async {
      final server = await _setUp(s1bSasOwner);
      server.capability = _capBody(supported: true);
      server.activationData = shortData(balance: 25000, cost: 10000);
      await _openSheet(t, _subs(3));
      // السطر فوق الزرّ يقولها قبل الضغط.
      expect(find.byKey(const ValueKey('bulk-preflight')), findsOneWidget);
      expect(
          simText(
              'رصيدك لا يكفي الكلّ — يكفي 2 من 3، وينقصك 5,000 د.ع'),
          findsOneWidget);

      await t.tap(_footer('تجديد 3 اشتراك'));
      await settle(t, seconds: 1);
      expect(find.text('جرّب الكلّ (3)'), findsOneWidget,
          reason: 'تنبيهٌ لا منع — بعض الساسات تسمح برصيدٍ سالب');
      await t.tap(find.text('جدّد 2 فقط'));
      await settle(t, seconds: 3);
      expect(server.activateCalls, ['1', '2']);
      expect(simText('لم يُنفَّذ — رصيدك لا يكفيه'), findsOneWidget);
      expect(_inReport('تمّ 2 · رُفض 0 · لم يُنفَّذ 1'), findsOneWidget);
      await _drain(t);
    });

    testWidgets('«جرّب الكلّ»: ساسٌ يسمح بالرصيد السالب يجدّد الثلاثة', (t) async {
      final server = await _setUp(s1bSasOwner);
      server.capability = _capBody(supported: true);
      server.activationData = shortData(balance: 25000, cost: 10000);
      await _openSheet(t, _subs(3));
      await _submit(t, 'تجديد 3 اشتراك', 'جرّب الكلّ (3)');
      expect(server.activateCalls, ['1', '2', '3']);
      expect(find.byType(BottomSheet), findsNothing, reason: 'اكتملت ⇒ تُغلق');
      await _drain(t);
    });

    testWidgets(
        '🚨 رصيدٌ صفر (مديرٌ بالكارت): لا «تجديد الآن» — «جرّب الكلّ» وحده، ويقف عند أوّل رفض',
        (t) async {
      final server = await _setUp(s1bSasOwner);
      server.capability = _capBody(supported: true);
      server.activationData = shortData(balance: 0, cost: 46000);
      server.activate = (_) => (
            403,
            {'success': false, 'message': 'فشل التفعيل', 'sas4_code': ''}
          );
      await _openSheet(t, _subs(3));
      await t.tap(_footer('تجديد 3 اشتراك'));
      await settle(t, seconds: 1);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
          find.descendant(
              of: find.byType(AlertDialog),
              matching: simText(
                  'رصيدك لا يكفي ولا تجديداً واحداً — اشحن رصيدك في الساس أوّلاً')),
          findsOneWidget);
      expect(find.text('تجديد الآن'), findsNothing);
      expect(find.textContaining('فقط'), findsNothing);
      await t.tap(find.text('إلغاء'));
      await settle(t, seconds: 1);
      expect(server.activateCalls, isEmpty, reason: 'الإلغاء لا يرسل شيئاً');

      // «جرّب الكلّ»: الساس يرفض الأوّل (403 فارغ) ⇒ تقف، ولا ثاني.
      await _submit(t, 'تجديد 3 اشتراك', 'جرّب الكلّ (3)');
      expect(server.activateCalls, ['1']);
      expect(_inReport('تمّ 0 · رُفض 1 · لم يُنفَّذ 2'), findsOneWidget);
      expect(
          _inReport(
              'توقّف التجديد: الساس رفض التفعيل لهذا الحساب — تأكّد من صلاحيّته ورصيده'),
          findsOneWidget,
          reason: '«فشل التفعيل» العامّة ⇒ جملتنا');
      await _drain(t);
    });

    testWidgets(
        '🚨 جلبٌ يُرفض بـ403: يقف الجلب بتزامنٍ محدود، وبلا «تعذّر الجلب» لصلاحيّة',
        (t) async {
      final server = await _setUp(s1bSasOwner);
      server.capability = _capBody(supported: true);
      server.activationError = (
        403,
        {
          'success': false,
          'code': 'PERMISSION_DENIED',
          'message': 'ليس لديك صلاحيّة لهذا الإجراء — اطلبها من مديرك',
        }
      );
      await _openSheet(t, _subs(12));
      expect(server.peakDataInFlight, lessThanOrEqualTo(4));
      expect(server.activationCalls.length, lessThanOrEqualTo(4),
          reason: 'رفضٌ قاطع ⇒ لا جلب جديد');
      expect(_inReport('توقّف جلب بيانات التفعيل'), findsOneWidget);
      expect(find.textContaining('تعذّر جلب'), findsNothing);
      expect(server.activateCalls, isEmpty);
      await _drain(t);
    });

    testWidgets('حكمٌ لم يكن في الكاش يصل بعد الفتح: السبب وحده بلا جلب',
        (t) async {
      final server = await _setUp(s1bSasOwner);
      server.capability = _capBody(
          supported: false, code: 'CARD_ONLY', reason: _cardOnlyReason);
      await _openSheet(t, _subs(3));
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.text(_cardOnlyReason), findsOneWidget);
      expect(server.activationCalls, isEmpty);
      expect(find.text('إغلاق'), findsOneWidget);
      await t.tap(find.text('إغلاق'));
      await settle(t, seconds: 1);
      expect(find.byType(BottomSheet), findsNothing);
      await _drain(t);
    });

    testWidgets(
        '🚨 أكثر من حدّ الدفعة: يُجدَّد أوّل 2، والثالث خارجها يبقى محدّداً للدفعة التالية',
        (t) async {
      final server = await _setUp(s1bSasOwner);
      server.capability = _capBody(supported: true, maxBatch: 2);
      Set<String>? keep = {'unset'};
      await _openSheet(t, _subs(3), onResult: (k) => keep = k);
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(server.activationCalls.toSet(), {'1', '2'}, reason: 'لا جلب خارج الدفعة');
      expect(find.byKey(const ValueKey('bulk-deferred')), findsOneWidget);
      await _submit(t, 'تجديد 2 اشتراك', 'تجديد الآن');
      expect(server.activateCalls, ['1', '2']);
      // اكتملت الدفعة ⇒ تُغلق، ويبقى الثالث وحده محدّداً.
      expect(find.byType(BottomSheet), findsNothing);
      expect(keep, {'3'});
      await _drain(t);
    });

    testWidgets(
        '🚨 بلا حدّ من الخادم (حكمٌ مجهول/خادمٌ أقدم): الحدّ الافتراضيّ 100 كالويب',
        (t) async {
      final server = await _setUp(s1bSasOwner);
      // capability = null ⇒ VisualServer يردّ فارغاً ناجحاً ⇒ مجهولٌ بلا حدود.
      await _openSheet(t, _subs(101));
      await settle(t, seconds: 6);
      expect(server.activationCalls, hasLength(100));
      expect(server.activationCalls, isNot(contains('101')));
      expect(find.byKey(const ValueKey('bulk-deferred')), findsOneWidget);
      await _drain(t);
    });

    testWidgets(
        '🚨 رفضٌ يخصّ صفوفاً بعينها لا يحبس «تجديد الباقين»، والإغلاق يُبقي المرفوض محدّداً',
        (t) async {
      final server = await _setUp(s1bSasOwner);
      server.capability = _capBody(supported: true);
      const refused = {
        'success': false,
        'message': 'الباقة غير مسموحة لهذا المشترك',
        'sas4_code': 'rsp_profile_not_allowed',
      };
      // الثلاثة الأولى مرفوضةٌ لسببها، والأخيران يتجدّدان.
      server.activate = (idx) =>
          int.parse(idx) <= 3 ? (422, refused) : (200, {'success': true});
      Set<String>? keep = {'unset'};
      await _openSheet(t, _subs(5), onResult: (k) => keep = k);
      await _submit(t, 'تجديد 5 اشتراك', 'تجديد الآن');
      expect(server.activateCalls, ['1', '2', '3', '4', '5'],
          reason: 'ثلاثة رفوضٍ متتالية لا توقف الباقين');
      expect(_inReport('تمّ 2 · رُفض 3 · لم يُنفَّذ 0'), findsOneWidget);
      // «تجديد الباقين»: المرفوضون وحدهم — يُرفضون ثانيةً ولا يوقف شيءٌ شيئاً.
      await _submit(t, 'تجديد الباقين (3)', 'تجديد الآن');
      expect(server.activateCalls, ['1', '2', '3', '4', '5', '1', '2', '3']);
      expect(_inReport('تمّ 0 · رُفض 3 · لم يُنفَّذ 0'), findsOneWidget);
      await t.tap(find.byType(SheetCloseButton));
      await settle(t, seconds: 1);
      expect(keep, {'1', '2', '3'}, reason: 'المرفوض يبقى محدّداً — المتمّ لا');
      await _drain(t);
    });

    testWidgets(
        '🚨 جلسة الساس انتهت في المنتصف (409 SAS_SESSION_EXPIRED): تُجدَّد ويُعاد الصفّ مرّةً وتكمل الدفعة',
        (t) async {
      final server = await _setUp(s1bSasOwner);
      server.capability = _capBody(supported: true);
      var refreshes = 0;
      bulkSessionRefresher = () async {
        refreshes++;
        return true;
      };
      var first2 = true;
      server.activate = (idx) {
        if (idx == '2' && first2) {
          first2 = false;
          return (
            409,
            {
              'success': false,
              'code': 'SAS_SESSION_EXPIRED',
              'message':
                  'انتهت جلسة الساس — لم يُفعَّل هذا المشترك. سجّل الدخول من جديد ثمّ أكمل الباقين',
            }
          );
        }
        return (200, {'success': true});
      };
      await _openSheet(t, _subs(3));
      await _submit(t, 'تجديد 3 اشتراك', 'تجديد الآن');
      expect(server.activateCalls, ['1', '2', '2', '3']);
      expect(refreshes, 1);
      expect(find.byType(BottomSheet), findsNothing, reason: 'اكتملت ⇒ تُغلق');
      expect(find.textContaining('سجّل الدخول'), findsNothing,
          reason: 'لا طلب دخولٍ لا يلزم');
      await _drain(t);
    });

    testWidgets(
        'جلسة الساس انتهت والتجديد مرفوض (موظّف/جلسةٌ ميتة): تقف بالجلسة بلا إعادة',
        (t) async {
      final server = await _setUp(s1bSasOwner);
      server.capability = _capBody(supported: true);
      bulkSessionRefresher = () async => false;
      server.activate = (idx) => idx == '2'
          ? (
              409,
              {
                'success': false,
                'code': 'SAS_SESSION_EXPIRED',
                'message':
                    'انتهت جلسة الساس — لم يُفعَّل هذا المشترك. سجّل الدخول من جديد ثمّ أكمل الباقين',
              }
            )
          : (200, {'success': true});
      Set<String>? keep = {'unset'};
      await _openSheet(t, _subs(3), onResult: (k) => keep = k);
      await _submit(t, 'تجديد 3 اشتراك', 'تجديد الآن');
      expect(server.activateCalls, ['1', '2']);
      expect(_inReport('تمّ 1 · رُفض 1 · لم يُنفَّذ 1'), findsOneWidget);
      expect(
          _inReport(
              'توقّف التجديد: انتهت جلسة الساس — لم يُفعَّل هذا المشترك. سجّل الدخول من جديد ثمّ أكمل الباقين'),
          findsOneWidget);
      await t.tap(find.byType(SheetCloseButton));
      await settle(t, seconds: 1);
      expect(keep, {'2', '3'}, reason: 'من لم يُفعَّل يبقى محدّداً');
      await _drain(t);
    });

    testWidgets(
        'حارس التكرار: محاولةٌ سابقة غير مؤكّدة ⇒ «غير مؤكّد» تكمل بعده، ولا يبقى محدّداً',
        (t) async {
      final server = await _setUp(s1bSasOwner);
      server.capability = _capBody(supported: true);
      server.activate = (idx) => idx == '1'
          ? (
              409,
              {
                'success': false,
                'code': 'RECENT_DUPLICATE',
                'message':
                    'محاولةٌ سابقة على «u1» قبل 40 ثانية لم يتأكّد إن نُفّذت في الساس. افتح المشترك وتحقّق منه قبل أيّ تكرار',
                'last': {'at_sec_ago': 40, 'uncertain': true},
              }
            )
          : (200, {'success': true});
      Set<String>? keep = {'unset'};
      await _openSheet(t, _subs(2), onResult: (k) => keep = k);
      await _submit(t, 'تجديد 2 اشتراك', 'تجديد الآن');
      expect(server.activateCalls, ['1', '2'], reason: 'الطلب لم يلمس الساس ⇒ تكمل');
      expect(_inReport('تمّ 1 · رُفض 0 · لم يُنفَّذ 0 · غير مؤكّد 1'), findsOneWidget);
      await t.tap(find.byType(SheetCloseButton));
      await settle(t, seconds: 1);
      expect(keep, isEmpty, reason: 'غير المؤكّد يُتحقَّق منه أوّلاً — لا يُعاد');
      await _drain(t);
    });

    testWidgets('«أوقف»: بعد المشترك الحاليّ لا شيء، والباقون «لم يُنفَّذ»',
        (t) async {
      final server = await _setUp(s1bSasOwner);
      server.capability = _capBody(supported: true);
      final gate = Completer<void>();
      server.activate = (idx) async {
        if (idx == '1') await gate.future;
        return (200, {'success': true});
      };
      await _openSheet(t, _subs(3));
      await t.tap(_footer('تجديد 3 اشتراك'));
      await settle(t, seconds: 1);
      await t.tap(find.text('تجديد الآن'));
      await t.pump(const Duration(milliseconds: 300));
      expect(server.activateCalls, ['1']);
      await t.tap(find.byKey(const ValueKey('bulk-stop')));
      await t.pump();
      expect(simText('يتوقّف بعد المشترك الحاليّ…'), findsOneWidget);
      gate.complete();
      await settle(t, seconds: 2);
      expect(server.activateCalls, ['1']);
      expect(_inReport('تمّ 1 · رُفض 0 · لم يُنفَّذ 2'), findsOneWidget);
      expect(_inReport('أوقفتَ التجديد — الباقون لم يُنفَّذوا'), findsOneWidget);
      await _drain(t);
    });

    testWidgets(
        'سحب الورقة لتُغلق أثناء الدفعة (لا يمرّ بـPopScope): تقف بعد الحاليّ، والحصيلة تظهر فوق ما تحتها',
        (t) async {
      final server = await _setUp(s1bSasOwner);
      server.capability = _capBody(supported: true);
      final gate = Completer<void>();
      server.activate = (idx) async {
        if (idx == '1') await gate.future;
        return (200, {'success': true});
      };
      final nav = GlobalKey<NavigatorState>();
      Set<String>? keep = {'unset'};
      await pumpVisual(t, phone,
          navigatorKey: nav,
          home: (_) => _launcher(_subs(3), onResult: (k) => keep = k));
      await settle(t, seconds: 1);
      await t.tap(find.text('افتح'));
      await settle(t, seconds: 2);
      await t.tap(_footer('تجديد 3 اشتراك'));
      await settle(t, seconds: 1);
      await t.tap(find.text('تجديد الآن'));
      await t.pump(const Duration(milliseconds: 300));
      expect(server.activateCalls, ['1']);
      // كسحب المقبض: `Navigator.pop` المباشر (لا maybePop).
      nav.currentState!.pop();
      await settle(t, seconds: 1);
      expect(find.byType(BottomSheet), findsNothing);
      // 🚨 من يبقى محدّداً يُحسب لحظة الإغلاق: الجاري (نتيجته لم تُعرف) لا،
      // والذي لم يُرسَل نعم — لا «الكلّ» (سحبٌ يعيد null كان يُبقي المتمّ).
      expect(keep, {'2', '3'});
      gate.complete();
      await t.pump(const Duration(milliseconds: 100));
      await t.pump(const Duration(milliseconds: 100));
      expect(server.activateCalls, ['1'], reason: 'لا صفّ جديد بعد الإغلاق');
      expect(
          find.textContaining('تمّ 1 · رُفض 0 · لم يُنفَّذ 2'), findsOneWidget,
          reason: 'الحصيلة على الطبقة الجذريّة');
      await _drain(t);
    });

    testWidgets('غير مؤكّد يقف ولا يُعاد في «تجديد الباقين»', (t) async {
      final server = await _setUp(s1bSasOwner);
      server.capability = _capBody(supported: true);
      server.activate = (idx) => idx == '1'
          ? (
              409,
              {
                'success': false,
                'code': 'OUTCOME_UNKNOWN',
                'message':
                    'لم يصل ردٌّ مؤكَّد من الساس — افتح المشترك وتحقّق من تاريخ انتهائه قبل أيّ إعادة، فقد يكون فُعِّل.',
              }
            )
          : (200, {'success': true});
      await _openSheet(t, _subs(2));
      await _submit(t, 'تجديد 2 اشتراك', 'تجديد الآن');
      expect(server.activateCalls, ['1']);
      expect(_inReport('تمّ 0 · رُفض 0 · لم يُنفَّذ 1 · غير مؤكّد 1'), findsOneWidget);
      // الباقي واحدٌ فقط (الثاني) — الأوّل «ربّما تفعّل» لا يُرسَل ثانيةً.
      await _submit(t, 'تجديد الباقين (1)', 'تجديد الآن');
      expect(server.activateCalls, ['1', '2']);
      await _drain(t);
    });

    testWidgets(
        'تمّ وتعذّر ما بعده (APPLIED_WITH_ERRORS): تكمل الدفعة، ولا تُغلق على التنبيه، ولا يُعاد',
        (t) async {
      final server = await _setUp(s1bSasOwner);
      server.capability = _capBody(supported: true);
      server.activate = (idx) => idx == '1'
          ? (
              409,
              {
                'success': false,
                'code': 'APPLIED_WITH_ERRORS',
                'message':
                    'تمّ التفعيل في الساس، لكن تعذّر إكمال ما بعده — لا تُعِد التفعيل؛ حدّث بيانات المشترك وتحقّق من دينه.',
              }
            )
          : (200, {'success': true});
      await _openSheet(t, _subs(2));
      await _submit(t, 'تجديد 2 اشتراك', 'تجديد الآن');
      expect(server.activateCalls, ['1', '2'], reason: 'ليس رفضاً قاطعاً');
      expect(find.byType(BottomSheet), findsOneWidget,
          reason: 'التنبيه يبقى أمام المدير');
      expect(_inReport('تمّ 2 · رُفض 0 · لم يُنفَّذ 0'), findsOneWidget);
      expect(
          _inReport(
              '1 منهم تفعّلوا وتعذّر ما بعده — لا تُعِد تفعيلهم، وراجع دينهم'),
          findsOneWidget);
      // لا باقٍ يُرسَل — المتمّ (ولو بتنبيه) لا يُعاد.
      expect(find.text('تجديد الباقين (0)'), findsOneWidget);
      await t.tap(find.text('تجديد الباقين (0)'));
      await settle(t, seconds: 1);
      expect(find.byType(AlertDialog), findsNothing);
      expect(server.activateCalls, ['1', '2']);
      await _drain(t);
    });

    for (final d in [_phone320Dark, phone]) {
      testWidgets('التخطيط${d.tag}: سطر «خارج الدفعة» بلا فيضان', (t) async {
        final server = await _setUp(s1bSasOwner);
        server.capability = _capBody(supported: true, maxBatch: 2);
        await _openSheet(t, _subs(250), device: d);
        expect(find.byKey(const ValueKey('bulk-deferred')), findsOneWidget);
        expect(
            simText(
                'تُجدَّد في هذه الدفعة أوّل 2 من 250 المحدَّدين — الباقون (248) يبقون محدّدين للدفعة التالية'),
            findsOneWidget);
        expect(server.activationCalls, hasLength(2));
        expect(t.takeException(), isNull);
        await _drain(t);
      });

      testWidgets('التخطيط${d.tag}: الحصيلة وسطر الرصيد بلا فيضان', (t) async {
        final server = await _setUp(s1bSasOwner);
        server.capability = _capBody(supported: true);
        server.activationData = (idx) => {
              'idx': idx,
              'user_price': 1250000,
              'price_after_discount': 1250000,
              'current_balance': -3500000,
              'manager_cost': 1000000,
              'manager_balance': 1500000,
              'units': 1,
            };
        server.activate = (idx) => idx == '1'
            ? (200, {'success': true})
            : (
                403,
                {
                  'success': false,
                  'code': 'CREDIT_NOT_ALLOWED',
                  'message':
                      'هذا الحساب في الساس لا يملك صلاحيّة التفعيل من الرصيد — اطلبها من الشركة',
                }
              );
        await _openSheet(t, _subs(3), device: d);
        expect(find.byKey(const ValueKey('bulk-preflight')), findsOneWidget);
        await _submit(t, 'تجديد 3 اشتراك', 'جدّد 1 فقط');
        expect(server.activateCalls, ['1']);
        expect(find.byKey(const ValueKey('bulk-report')), findsOneWidget);
        expect(t.takeException(), isNull);
        await _drain(t);
      });
    }
  });
}
