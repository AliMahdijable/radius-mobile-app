import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/account_api.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/company_route.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/national/national_wallet_topup_sheet.dart';
import 'package:rad_mysvcs/screens/subscribers/sheets/activate_sheet.dart';
import 'package:rad_mysvcs/services/merged_mode.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:rad_mysvcs/services/provider_service.dart';

import 'sim_el/sim_harness.dart';

/// عضو فريق الوطنيّ في «كل الشركات» (١٥ نوفمبر) — الشكل على الشاشة الضيّقة بخطٍّ مكبَّر: شيت التفعيل بسطر «حدّ محفظتك»
/// ثمّ نافذة «تعبئة محفظة المشترك» باسم شركة الصفّ في رأسها. لا نصّ يخرج ولا رقم يُقصّ بعرض ٣٢٠ و٤٨٠ × خطّ ١٫٢، و٣٩٠ داكناً.
/// بياناتٌ تجريبيّة وحدها. اللقطات: VISUAL_OUT (أو build/natwallet_shots المُتجاهَل بgit) — لا تُكتب في المجلّد المتتبَّع.
const _sid = '555';
const _base = '/api/v2/ftth/subscriptions/$_sid/wallet';
const _kOpen = 'c0000000000a1';
const _kB = 'c0000000000b2';

class _Dev {
  const _Dev(this.tag, this.width, {this.dark = false, this.scale = 1.0});
  final String tag;
  final double width;
  final bool dark;
  final double scale;
}

const _devices = [
  _Dev('320_x1.2', 320, scale: 1.2),
  _Dev('480_x1.2', 480, scale: 1.2),
  _Dev('320_dark_x1.2', 320, dark: true, scale: 1.2),
  _Dev('390_dark', 390, dark: true),
];

Map<String, Object?> _companies() => {
      'routing': true,
      'writes': true,
      'companies': [
        {'key': _kOpen, 'code': 'watani', 'username': 'main-a', 'name': 'المشروع الوطني · المكتب الرئيسيّ', 'provider': 'kit', 'status': 'ok',
          'admin_id': 'watani:15742', 'ns': 'watani|main-a', 'currency': 'IQD', 'color_index': 0},
        {'key': _kB, 'code': 'watani', 'username': 'member-b', 'name': 'المشروع الوطني · فريق الصيانة والتحصيل', 'provider': 'kit', 'status': 'ok',
          'admin_id': 'watani:1380', 'ns': 'watani|member-b', 'currency': 'IQD', 'color_index': 1},
      ],
    };

class _Echo implements HttpClientAdapter {
  _Echo(this.inner);
  final SimServer inner;

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? rs, Future<void>? cf) async {
    final r = await inner.fetch(o, rs, cf);
    final key = o.headers['x-company-key'] as String?;
    if (key == null) return r;
    return ResponseBody(r.stream, r.statusCode, headers: {
      ...r.headers,
      'x-company-key': [key],
      if (o.method.toUpperCase() == 'GET' && o.uri.path == '/api/v2/subscribers/$_sid') 'x-company-ref': ['r_AAAAAAAAAAAAAAAAAAAAAA'],
    });
  }

  @override
  void close({bool force = false}) {}
}

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 120));
  }
  await t.pumpAndSettle();
}

/// النصّ بلا محارف العزل الاتّجاهيّ (بأرقامها — لا محارف خفيّة في الملفّ).
String _plain(String s) => String.fromCharCodes(
    s.runes.where((r) => !((r >= 0x2066 && r <= 0x2069) || r == 0x200E || r == 0x200F || (r >= 0x202A && r <= 0x202E))));

/// النصوص المقصوصة الآن (تجاوزت أسطرها) — لا يُقبل منها سطرٌ من سطورنا ولا رقم.
List<String> _cut() => [
      for (final e in find.byType(RichText).evaluate())
        if (e.renderObject case final RenderParagraph p when p.didExceedMaxLines) _plain(p.text.toPlainText()),
    ];

Future<void> _shot(WidgetTester t, String name, _Dev d) async {
  final boundary = t.renderObject<RenderRepaintBoundary>(find.byKey(simRootKey));
  final png = await t.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 3);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  });
  final dir = Platform.environment['VISUAL_OUT'] ?? 'build/natwallet_shots';
  final f = File('$dir/${name}_${d.tag}.png');
  f.parent.createSync(recursive: true);
  f.writeAsBytesSync(png!, flush: true);
  final ex = t.takeException();
  expect(ex, isNull, reason: 'استثناء (نصٌّ خرج؟) في $name ${d.tag}:\n$ex');
  final cut = _cut();
  for (final s in cut) {
    stdout.writeln('NW-TRUNC|$name ${d.tag}|$s');
  }
  // رأس شيت التفعيل «الاسم · «الشركة»» سطرٌ واحد في كلّ نوافذ الوضع (قائمٌ قبل هذا العمل) — يُسجَّل أعلاه ولا يُحاسَب هنا.
  expect(cut.where((s) => RegExp(r'[0-9٠-٩]').hasMatch(s) || s.contains('حدّ محفظتك') || s.contains('محفظتك في بوّابة') || s.startsWith('في «')), isEmpty,
      reason: 'رقمٌ أو سطرٌ من سطورنا مقصوص في $name ${d.tag}');
}

void main() {
  setUpAll(simSetUpAll);

  tearDown(() {
    MergedMode.reset();
    CompanyRefs.reset();
    PermissionsService.debugReset();
    ProviderService.debugSet(null);
  });

  for (final d in _devices) {
    testWidgets('عضو الفريق: شيت التفعيل «حدّ محفظتك» ثمّ نافذة التعبئة باسم الشركة ${d.tag}', (t) async {
      debugDisableShadows = false;
      try {
        if (d.scale != 1.0) {
          t.platformDispatcher.textScaleFactorTestValue = d.scale;
          addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
        }
        final server = await simSetUp(secure: {'auth.admin_id': 'watani:15742', 'auth.admin_username': 'main-a'});
        ApiClient.dio.httpClientAdapter = _Echo(server);
        PermissionsService.debugSet(isEmployee: false);
        ProviderService.debugSet('watani', label: 'المشروع الوطني');
        AccountApi.tokenSource = ({bool force = false}) async => 'acct';
        MergedMode.reset();
        CompanyRefs.reset();
        MergedMode.fetchRaw = () async => Map<String, dynamic>.from(_companies());
        expect(await t.runAsync(() => MergedMode.enter()), isTrue);

        server.reply('GET', '/api/v2/subscribers/$_sid/activation-data', 200, {
          'success': true,
          'data': {
            'idx': _sid, 'username': 'FKR0194_F3_P7', 'profile_name': 'Basic', 'profile_id': 11, 'user_price': 40000,
            'price_after_discount': 40000, 'base_price': 40000, 'current_balance': 0,
            'manager_balance': 1999.97, 'manager_balance_is_limit': true,
            'provider': 'watani', 'provider_label': 'المشروع الوطني',
            'packages': [{'id': 11, 'name': 'Basic', 'price': 40000, 'cost': null, 'days': null}],
            'package_change_allowed': false, 'package_change_timing': ['now'], 'card_payment': true,
            'customer_wallet': {'balance': 0, 'price': 35000, 'enough': false, 'topup': true},
          },
        });
        server.reply('GET', '$_base/topup', 200, {
          'success': true,
          'data': {
            'transfer': {'ok': true, 'reason': null},
            'card': {'ok': true, 'reason': null},
            'partner_balance': 1250000,
            'customer_balance': 0,
            'target': {'name': 'مشترك وطني', 'phone': '•••0000'},
            'limits': {'min': 1000, 'max': 1000000, 'step': 250},
            'recent': null,
          },
        });
        final sub = Subscriber.fromJson({'idx': _sid, 'username': 'FKR0194_F3_P7', 'firstname': 'مشترك', 'lastname': 'وطني', 'profile_id': 11, 'profile_name': 'Basic'})
            .withCompany(_kB);
        await pumpSim(t, SimVariant(d.width, dark: d.dark), home: (_) => simLauncher((c) => showActivateSheet(c, sub)));
        await simOpen(t);
        await t.pump(const Duration(milliseconds: 400));
        await _settle(t);
        expect(find.text('حدّ محفظتك'), findsOneWidget);
        await _shot(t, '01_activate', d);

        final tile = find.text('محفظة المشترك');
        await t.ensureVisible(tile.first);
        await _settle(t);
        await _shot(t, '02_activate_pay', d);
        await t.tap(tile.first);
        await _settle(t);
        await _shot(t, '03_wallet_short', d);
        await t.tap(find.text('شحن المحفظة'));
        await _settle(t);
        expect(find.text('تعبئة محفظة المشترك'), findsOneWidget);
        // اسم شركة الصفّ هو سطر الرأس — كاملاً (يلتفّ ولا يُقصّ)، لا ملحقاً بوصفٍ طويل يدفعه خارج السطر
        final head = find.text('في «المشروع الوطني · فريق الصيانة والتحصيل»');
        expect(head, findsOneWidget, reason: 'اسم شركة الصفّ في رأس النافذة');
        expect(t.renderObject<RenderParagraph>(find.descendant(of: head, matching: find.byType(RichText))).didExceedMaxLines, isFalse,
            reason: 'اسم الشركة مقصوص في رأس النافذة ${d.tag}');
        expect(find.textContaining('من محفظتك في بوّابة الوطني'), findsNothing, reason: 'الوصف الطويل لا يزاحم اسم الشركة في الوضع');
        await _shot(t, '04_topup', d);

        final f = find.byType(TextField).at(0);
        await t.ensureVisible(f);
        await t.enterText(f, '25000');
        await _settle(t);
        await _shot(t, '05_topup_typed', d);
        await simDrain(t);
      } finally {
        debugDisableShadows = true;
      }
    });

    testWidgets('خارج الوضع: رأس نافذة التعبئة بوصفه القائم كاملاً (يلتفّ على الشاشة الضيّقة ولا يُقصّ) ${d.tag}', (t) async {
      debugDisableShadows = false;
      try {
        if (d.scale != 1.0) {
          t.platformDispatcher.textScaleFactorTestValue = d.scale;
          addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
        }
        final server = await simSetUp(secure: {'auth.admin_id': 'watani:15742', 'auth.admin_username': 'main-a'});
        ApiClient.dio.httpClientAdapter = server;
        PermissionsService.debugSet(isEmployee: false);
        ProviderService.debugSet('watani', label: 'المشروع الوطني');
        MergedMode.reset();
        CompanyRefs.reset();
        server.reply('GET', '$_base/topup', 200, {
          'success': true,
          'data': {
            'transfer': {'ok': true, 'reason': null},
            'card': {'ok': true, 'reason': null},
            'partner_balance': 12500000,
            'customer_balance': 1250000,
            'target': {'name': 'مشترك وطني', 'phone': '•••0000'},
            'limits': {'min': 1000, 'max': 1000000, 'step': 250},
            'recent': null,
          },
        });
        await pumpSim(t, SimVariant(d.width, dark: d.dark),
            home: (_) => simLauncher((c) => showNationalWalletTopupSheet(c, sid: _sid, companyKey: null)));
        await simOpen(t);
        await _settle(t);
        final head = find.text('من محفظتك في بوّابة الوطني أو بكارت الشركة');
        expect(head, findsOneWidget, reason: 'خارج الوضع: الوصف كما كان حرفاً وبلا اسم شركة');
        expect(t.renderObject<RenderParagraph>(find.descendant(of: head, matching: find.byType(RichText))).didExceedMaxLines, isFalse,
            reason: 'وصف الرأس مقصوص ${d.tag}');
        await _shot(t, '06_topup_normal', d);
        await simDrain(t);
      } finally {
        debugDisableShadows = true;
      }
    });
  }
}
