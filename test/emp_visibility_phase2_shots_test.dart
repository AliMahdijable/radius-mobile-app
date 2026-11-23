import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/core/platform/desktop_layout.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/reports/v2/activity_log_v2_screen.dart';
import 'package:rad_mysvcs/screens/search/quick_search_overlay.dart';
import 'package:rad_mysvcs/screens/subscribers/sheets/edit_subscriber_sheet.dart';
import 'package:rad_mysvcs/screens/subscribers/sheets/pay_debt_sheet.dart';
import 'package:rad_mysvcs/screens/subscribers/subscribers_screen.dart';
import 'package:rad_mysvcs/screens/subscribers/widgets/filter_chips_bar.dart';
import 'package:rad_mysvcs/services/employee_visibility.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';

import 'visual_perm/visual_perm_harness.dart';

/// «ما يراه الموظّف» — المرحلة الثانية بالتطبيق (٢٣ نوفمبر): جدول الحاسبة، البحث السريع، رأس النوافذ لمشتركٍ بلا اسم، نافذة
/// التعديل، وسجلّ النشاط — بعيون المدير ثمّ بعيون موظّفٍ أطفأ عنه مديره الأصناف كلّها. والمشترك «بلا اسم» (اسمه فارغ) هو الامتحان:
/// `Subscriber.fullName` يرجع اليوزر لمن لا اسم له ⇒ كان يظهر رغم الإخفاء. الصور حين يُعطى VISUAL_OUT وحده.
const _phone = VisualDevice('390', Size(390, 844), 3);
const _phoneDark = VisualDevice('390_dark', Size(390, 844), 3, dark: true);
const _desk = VisualDevice('desk', Size(1280, 800), 2);

const _allHidden = {'debts', 'usernames', 'phones', 'counts', 'balance'};
const _empKeys = {
  'subscribers.view': true,
  'subscribers.activate': true,
  'subscribers.extend': true,
  'subscribers.edit': true,
  'subscribers.pay_debt': true,
  'subscribers.view_activity': true,
  'packages.view': true,
  'reports.activity_log': true,
};

const _nameless = 'x7@najaf';

Map<String, Object?> _namelessRow() {
  final exp = DateTime.now().add(const Duration(days: 90));
  String two(int n) => n.toString().padLeft(2, '0');
  return {
    'idx': '18',
    'username': _nameless,
    'firstname': '',
    'lastname': '',
    'phone': '07701000018',
    'profile_name': 'Economy',
    'profile_id': 7,
    'expiration': '${exp.year}-${two(exp.month)}-${two(exp.day)} 10:00:00',
    'remaining_days': 90,
    'online_status': 0,
    'enabled': 1,
    'notes': '-10000',
  };
}

List<Map<String, Object?>> _activities() {
  final at = DateTime.now().subtract(const Duration(minutes: 5));
  String two(int n) => n.toString().padLeft(2, '0');
  // كصفوف /api/activities: رقمٌ ونوعٌ لكلّ سطر (السجلّ يُسقط ما لا رقم له) — وسطر المشترك بلا اسم أوّلاً
  var id = 9000;
  Map<String, Object?> asLog(Map<String, Object?> r) => {...r, 'id': ++id, 'action_type': r['action']};
  return [
    for (final r in <Map<String, Object?>>[
    {
      'action': 'ACTIVATE',
      'action_description': 'تفعيل نقدي - المستخدم: $_nameless',
      'user_firstname': '',
      'user_lastname': '',
      'user_username': _nameless,
      'amount': 25000,
      'created_at': '${at.year}-${two(at.month)}-${two(at.day)} ${two(at.hour)}:${two(at.minute)}:00',
      'admin_username': 'admin@najaf948',
    },
    ...fixtureActivities(),
    ])
      asLog(r),
  ];
}

// كقوائم الخادم (server/employeeVisibility.js) — المستعمل هنا منها
const _phoneKeys = {'phone', 'mobile', 'phone2', 'mobile2', 'phones'};
const _debtKeys = {'debt', 'debts', 'net_debt', 'notes_balance', 'current_balance', 'balance'};
final _numericNote = RegExp(r'^[+-]?\s*[\d٠-٩][\d٠-٩,.\s]*$');

Object? _mask(Object? v) {
  if (v is List) return [for (final e in v) _mask(e)];
  if (v is! Map) return v;
  final out = <String, Object?>{};
  for (final e in v.entries) {
    final lk = e.key.toString().toLowerCase();
    final val = e.value;
    if (_phoneKeys.contains(lk) && val != null && val != '') {
      out[e.key.toString()] = null;
    } else if (_debtKeys.contains(lk) && val != null) {
      out[e.key.toString()] = null;
    } else if ((lk == 'notes' || lk == 'comments') && val is String && _numericNote.hasMatch(val.trim())) {
      out[e.key.toString()] = null;
    } else {
      out[e.key.toString()] = _mask(val);
    }
  }
  return out;
}

ResponseBody _json(Object body) => ResponseBody.fromString(jsonEncode(body), 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });

/// الخادم الوهميّ + مشتركٌ بلا اسم + سجلّ النشاط، وإخفاء الخادم للموظّف المقيَّد (الهاتف والدين null — اليوزر يصل: العمليّات تحتاجه).
class _Server implements HttpClientAdapter {
  _Server(this.inner, {required this.restricted});
  final HttpClientAdapter inner;
  final bool restricted;

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final p = o.path;
    final get = o.method.toUpperCase() == 'GET';
    Object? body;
    if (get && p == '/api/activities') {
      final rows = _activities();
      body = {'success': true, 'data': rows, 'pagination': {'total': rows.length}};
    } else if (get && p == '/api/v2/subscribers') {
      body = {
        'success': true,
        'data': [...fixtureSubscribers, _namelessRow()],
      };
    }
    if (body == null) return inner.fetch(o, requestStream, cancelFuture);
    return _json(restricted && p.startsWith('/api/v2/subscribers') ? _mask(body)! : body);
  }

  @override
  void close({bool force = false}) {}
}

Future<void> _shot(WidgetTester t, String name, VisualDevice d) async {
  final out = Platform.environment['VISUAL_OUT'];
  if (out == null || out.isEmpty) return;
  final boundary = t.renderObject<RenderRepaintBoundary>(find.byKey(visualRootKey));
  final png = await t.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: d.dpr);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  });
  final f = File('$out/empvis2_${name}_${d.tag}.png');
  f.parent.createSync(recursive: true);
  f.writeAsBytesSync(png!, flush: true);
}

Future<void> _up({required bool restricted}) async {
  final server = await visualSetUp(s1bSasOwner);
  ApiClient.dio.httpClientAdapter = _Server(server, restricted: restricted);
  if (restricted) {
    PermissionsService.debugSet(isEmployee: true, permissions: _empKeys, hidden: _allHidden);
  }
}

Future<void> _down(WidgetTester t) async {
  await t.pumpWidget(const SizedBox.shrink());
  await t.pump(const Duration(seconds: 4));
  await visualTearDown();
}

Subscriber _namelessSub({required bool restricted}) {
  final row = _namelessRow();
  if (restricted) {
    row['phone'] = null;
    row['notes'] = null;
  }
  return Subscriber.fromJson(row);
}

Finder _anyText(String s) => find.textContaining(s, findRichText: true);

Future<void> _openFrom(WidgetTester t, VisualDevice d, Future<void> Function(BuildContext c) open) async {
  await pumpVisual(
    t,
    d,
    home: (c) => Scaffold(body: Center(child: TextButton(onPressed: () => open(c), child: const Text('افتح')))),
  );
  await settle(t, seconds: 1);
  await t.tap(find.text('افتح'));
  await settle(t, seconds: 3);
}

void main() {
  setUpAll(visualSetUpAll);

  for (final restricted in [false, true]) {
    final who = restricted ? 'b_employee' : 'a_owner';

    testWidgets('جدول الحاسبة — $who', (t) async {
      await _up(restricted: restricted);
      final cmd = ValueNotifier<SubscriberFilter?>(SubscriberFilter.all);
      await pumpVisual(t, _desk, home: (_) => DesktopScope(child: SubscribersScreen(filterCmd: cmd)));
      await settle(t, seconds: 4);
      await _shot(t, '1_desk_$who', _desk);
      if (restricted) {
        expect(_anyText('@najaf'), findsNothing, reason: 'لا يوزر بالجدول');
        expect(find.text(kNoNameWord), findsWidgets, reason: 'المشترك بلا اسم ⇒ «بلا اسم» لا يوزره');
        expect(_anyText('0770'), findsNothing, reason: 'لا عمود هاتف');
        expect(_anyText('مشترك، و'), findsNothing, reason: 'لا «N مشترك، وM متّصل الآن» بالرأس');
      } else {
        expect(find.text(_nameless), findsWidgets);
      }
      expect(t.takeException(), isNull);
      await _down(t);
    });

    for (final d in [_phone, if (restricted) _phoneDark]) {
      testWidgets('البحث السريع — $who ${d.tag}', (t) async {
        await _up(restricted: restricted);
        await _openFrom(t, d, (c) => showQuickSearch(c));
        await t.enterText(find.byType(TextField).first, 'najaf');
        await settle(t, seconds: 3);
        await _shot(t, '2_search_$who', d);
        if (restricted) {
          expect(_anyText('@najaf'), findsNothing, reason: 'البحث باليوزر يشتغل والنتيجة بلا يوزر');
          expect(_anyText(' من 18 نتيجة'), findsNothing, reason: 'لا مجموع — أعداد المشتركين مخفيّة');
        } else {
          expect(_anyText('(hussein77@najaf)'), findsWidgets);
        }
        // المشترك بلا اسم يُوجد بيوزره — ويُعرض «بلا اسم» للموظّف
        await t.enterText(find.byType(TextField).first, 'x7');
        await settle(t, seconds: 3);
        await _shot(t, '2b_search_nameless_$who', d);
        expect(find.text(restricted ? kNoNameWord : _nameless), findsOneWidget);
        if (restricted) expect(_anyText(_nameless), findsNothing);
        expect(t.takeException(), isNull);
        await _down(t);
      });

      testWidgets('نافذة التسديد لمشتركٍ بلا اسم — $who ${d.tag}', (t) async {
        await _up(restricted: restricted);
        final sub = _namelessSub(restricted: restricted);
        await _openFrom(t, d, (c) => showPayDebtSheet(c, sub));
        if (restricted) {
          expect(_anyText(_nameless), findsNothing);
          expect(find.text(kNoNameWord), findsOneWidget);
        } else {
          expect(find.text(_nameless), findsOneWidget);
        }
        await _shot(t, '3_pay_nameless_$who', d);
        expect(t.takeException(), isNull);
        await _down(t);
      });

      testWidgets('نافذة التعديل — $who ${d.tag}', (t) async {
        await _up(restricted: restricted);
        final row = Map<String, Object?>.from(fixtureSubscribers[2]);
        if (restricted) {
          row['phone'] = null;
          row['notes'] = null;
        }
        final sub = Subscriber.fromJson(row);
        await _openFrom(t, d, (c) => showEditSubscriberSheet(c, sub));
        if (restricted) {
          expect(find.text('اسم المستخدم'), findsNothing, reason: 'لا حقل يوزر');
          expect(find.text('رقم الهاتف'), findsNothing, reason: 'لا حقل هاتف');
          expect(_anyText('hussein77@najaf'), findsNothing);
        } else {
          expect(find.text('اسم المستخدم'), findsOneWidget);
          expect(find.text('رقم الهاتف'), findsOneWidget);
        }
        await _shot(t, '4_edit_$who', d);
        expect(t.takeException(), isNull);
        await _down(t);
      });

      testWidgets('سجلّ النشاط — $who ${d.tag}', (t) async {
        await _up(restricted: restricted);
        await pumpVisual(t, d, home: (_) => const ActivityLogV2Screen());
        await settle(t, seconds: 4);
        await _shot(t, '5_activity_$who', d);
        if (restricted) {
          // يوزرات المشتركين وحدها (منفّذ العمليّة admin@… مديرٌ لا مشترك — يبقى)
          for (final u in [_nameless, 'ali1@najaf', 'zainab.k@najaf', 'haider.s@najaf']) {
            expect(_anyText(u), findsNothing, reason: 'لا يوزر مشترك بعنوان السطر ولا بوصفه: $u');
          }
          expect(_anyText('حسن الموسوي'), findsWidgets, reason: 'الاسم يبقى');
          expect(find.text(kNoNameWord), findsOneWidget, reason: 'المشترك بلا اسم');
        } else {
          expect(_anyText(_nameless), findsWidgets);
        }
        expect(t.takeException(), isNull);
        await _down(t);
      });
    }
  }
}
