import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/dashboard/dashboard_screen.dart';
import 'package:rad_mysvcs/screens/subscribers/sheets/activate_sheet.dart';
import 'package:rad_mysvcs/screens/subscribers/sheets/pay_debt_sheet.dart';
import 'package:rad_mysvcs/screens/subscribers/subscriber_detail_screen.dart';
import 'package:rad_mysvcs/screens/subscribers/subscribers_screen.dart';
import 'package:rad_mysvcs/screens/subscribers/widgets/filter_chips_bar.dart';
import 'package:rad_mysvcs/services/employee_visibility.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';

import 'visual_perm/visual_perm_harness.dart';

/// «ما يراه الموظّف» (٢٣ نوفمبر — المالك: «ونطين الصور»): الشاشات نفسها مرّتين — بعيون المدير، وبعيون موظّفٍ أطفأ عنه مديره
/// الديون واليوزر والهاتف والأعداد والرصيد. ردود الخادم للموظّف تمرّ بإخفاءٍ كإخفاء الخادم (server/employeeVisibility.js):
/// الهاتف والدين ورصيد الصفحة null. تُكتب الصور حين يُعطى VISUAL_OUT وحده.
const _devices = [
  VisualDevice('390', Size(390, 844), 3),
  VisualDevice('390_dark', Size(390, 844), 3, dark: true),
];

const _allHidden = {'debts', 'usernames', 'phones', 'counts', 'balance'};
const _empKeys = {
  'subscribers.view': true,
  'subscribers.activate': true,
  'subscribers.extend': true,
  'subscribers.pay_debt': true,
  'subscribers.send_whatsapp': true,
  'subscribers.generate_link': true,
  'subscribers.view_activity': true,
  'subscribers.private_note': true,
  'packages.view': true,
  'whatsapp.send': true,
  'notifications.view': true,
  'reports.daily_activations': true,
};

// كقوائم الخادم (server/employeeVisibility.js) — المستعمل هنا منها
const _phoneKeys = {'phone', 'mobile', 'phone2', 'mobile2', 'phones', 'raw_phone', 'wa_phone', 'wa_phone2', 'whatsapp2', 'telegram'};
const _debtKeys = {
  'debt', 'debts', 'debt_amount', 'net_debt', 'notes_balance', 'current_balance', 'hasdebt', 'has_debt', 'balance', 'new_balance',
  'previous_balance', 'remaining_debt', 'debtors', 'wa', 'wa_preview',
};
const _walletKeys = {'manager_balance', 'reward_points'};
final _numericNote = RegExp(r'^[+-]?\s*[\d٠-٩][\d٠-٩,.\s]*$');

Object? _mask(Object? v, {required bool phones, required bool debts, required bool wallet, required bool dashboard}) {
  if (v is List) return [for (final e in v) _mask(e, phones: phones, debts: debts, wallet: wallet, dashboard: dashboard)];
  if (v is! Map) return v;
  final out = <String, Object?>{};
  for (final e in v.entries) {
    final k = e.key.toString();
    final lk = k.toLowerCase();
    final val = e.value;
    if (phones && _phoneKeys.contains(lk) && val != null && val != '') {
      out[k] = null;
    } else if (debts && !dashboard && _debtKeys.contains(lk) && val != null) {
      out[k] = null;
    } else if (debts && (lk == 'notes' || lk == 'comments') && val is String && _numericNote.hasMatch(val.trim())) {
      out[k] = null;
    } else if (wallet && (_walletKeys.contains(lk) || (dashboard && (lk == 'balance' || lk == 'points')))) {
      out[k] = null;
    } else {
      out[k] = _mask(val, phones: phones, debts: debts, wallet: wallet, dashboard: dashboard);
    }
  }
  return out;
}

/// الخادم الوهميّ للّقطات + نافذة التفعيل، وإخفاء الخادم للموظّف المقيَّد.
class _MaskingServer implements HttpClientAdapter {
  _MaskingServer(this.inner, {required this.restricted});
  final HttpClientAdapter inner;
  final bool restricted;

  static const _activation = {
    'success': true,
    'data': {
      'idx': '3',
      'username': 'hussein77@najaf',
      'firstname': 'حسين',
      'lastname': 'عبد الأمير',
      'user_price': 35000,
      'price_after_discount': 35000,
      'base_price': 35000,
      'profile_name': 'Plus',
      'profile_id': 7,
      'profile_duration': '30',
      'current_balance': -35000,
      'manager_balance': 1505000,
      'reward_points': 2,
      'manager_cost': 21000,
      'phone': '07701000003',
      'activation_methods': {'credit': true, 'card': false},
      'cards': {'enabled': false},
    },
  };

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final p = o.path;
    final ResponseBody raw = p.endsWith('/activation-data')
        ? ResponseBody.fromString(jsonEncode(_activation), 200, headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          })
        : await inner.fetch(o, requestStream, cancelFuture);
    if (!restricted) return raw;
    final subs = p.startsWith('/api/v2/subscribers') || p.startsWith('/api/subscribers') || p.startsWith('/api/v2/online-users');
    final dash = p.startsWith('/api/v2/admin-widgets');
    final walletPath = dash || p.endsWith('/activation-data');
    if (!subs && !walletPath) return raw;
    final bytes = await raw.stream.fold<List<int>>(<int>[], (a, b) => a..addAll(b));
    Object? body;
    try {
      body = jsonDecode(utf8.decode(bytes));
    } catch (_) {
      return ResponseBody.fromBytes(bytes, raw.statusCode, headers: raw.headers);
    }
    var masked = _mask(body, phones: subs, debts: subs, wallet: walletPath, dashboard: dash);
    if (dash && masked is Map) masked = {...masked, 'balanceHidden': true};
    return ResponseBody.fromString(jsonEncode(masked), raw.statusCode, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
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
  final f = File('$out/empvis_${name}_${d.tag}.png');
  f.parent.createSync(recursive: true);
  f.writeAsBytesSync(png!, flush: true);
}

Future<void> _up({required bool restricted}) async {
  final server = await visualSetUp(s1bSasOwner);
  ApiClient.dio.httpClientAdapter = _MaskingServer(server, restricted: restricted);
  if (restricted) {
    PermissionsService.debugSet(isEmployee: true, permissions: _empKeys, hidden: _allHidden);
  }
}

Future<void> _down(WidgetTester t) async {
  await t.pumpWidget(const SizedBox.shrink());
  await t.pump(const Duration(seconds: 4));
  await visualTearDown();
}

Subscriber _hussein({required bool restricted}) {
  final row = Map<String, dynamic>.from(fixtureSubscribers[2]);
  if (restricted) {
    row['phone'] = null;
    row['notes'] = null;
  }
  return Subscriber.fromJson(row);
}

void main() {
  setUpAll(visualSetUpAll);

  for (final restricted in [false, true]) {
    final who = restricted ? 'b_employee' : 'a_owner';
    for (final d in _devices) {
      if (!restricted && d.tag.contains('dark')) continue; // المدير مرجعٌ بالفاتح وحده
      testWidgets('الرئيسيّة — $who ${d.tag}', (t) async {
        await _up(restricted: restricted);
        await pumpVisual(t, d, home: (_) => const DashboardScreen());
        await settle(t, seconds: 4);
        if (restricted) {
          expect(Sees.debts || Sees.counts || Sees.balance, isFalse);
          expect(find.text('1,505,000'), findsNothing);
        }
        await _shot(t, '1_home_$who', d);
        expect(t.takeException(), isNull);
        await _down(t);
      });

      testWidgets('المشتركون — $who ${d.tag}', (t) async {
        await _up(restricted: restricted);
        final cmd = ValueNotifier<SubscriberFilter?>(SubscriberFilter.all);
        await pumpVisual(t, d, home: (_) => SubscribersScreen(filterCmd: cmd));
        await settle(t, seconds: 4);
        if (restricted) {
          expect(find.text('hussein77@najaf'), findsNothing, reason: 'اليوزر مخفيّ');
          expect(find.textContaining('35,000'), findsNothing, reason: 'الدين مخفيّ');
        }
        await _shot(t, '2_subscribers_$who', d);
        expect(t.takeException(), isNull);
        await _down(t);
      });

      testWidgets('كرت المشترك — $who ${d.tag}', (t) async {
        await _up(restricted: restricted);
        await pumpVisual(t, d, home: (_) => SubscriberDetailScreen(sub: _hussein(restricted: restricted)));
        await settle(t, seconds: 4);
        if (restricted) {
          expect(find.text('hussein77@najaf'), findsNothing);
          expect(find.text(kHiddenWord), findsWidgets);
          expect(find.text('تسديد'), findsWidgets, reason: 'التسديد يبقى');
        }
        await _shot(t, '3_subscriber_$who', d);
        expect(t.takeException(), isNull);
        await _down(t);
      });

      testWidgets('نافذة التجديد — $who ${d.tag}', (t) async {
        await _up(restricted: restricted);
        final sub = _hussein(restricted: restricted);
        await pumpVisual(
          t,
          d,
          home: (c) => Scaffold(body: Center(child: TextButton(onPressed: () => showActivateSheet(c, sub), child: const Text('افتح')))),
        );
        await settle(t, seconds: 1);
        await t.tap(find.text('افتح'));
        await settle(t, seconds: 3);
        if (restricted) {
          expect(find.textContaining('1,505,000'), findsNothing, reason: 'رصيد المدير مخفيّ');
          expect(find.text(kHiddenWord), findsOneWidget);
        }
        await _shot(t, '4_renew_$who', d);
        expect(t.takeException(), isNull);
        await _down(t);
      });

      testWidgets('نافذة التسديد — $who ${d.tag}', (t) async {
        await _up(restricted: restricted);
        final sub = _hussein(restricted: restricted);
        await pumpVisual(
          t,
          d,
          home: (c) => Scaffold(body: Center(child: TextButton(onPressed: () => showPayDebtSheet(c, sub), child: const Text('افتح')))),
        );
        await settle(t, seconds: 1);
        await t.tap(find.text('افتح'));
        await settle(t, seconds: 3);
        if (restricted) {
          expect(find.text('كامل الدين'), findsNothing);
          expect(find.text(kHiddenWord), findsOneWidget);
          expect(find.text('لا يوجد دين على هذا المشترك'), findsNothing, reason: 'يبقى يسدّد');
        }
        await _shot(t, '5_pay_$who', d);
        expect(t.takeException(), isNull);
        await _down(t);
      });
    }
  }
}
