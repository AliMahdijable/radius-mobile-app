import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/core/util/format.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/reports/v2/report_kit.dart';
import 'package:rad_mysvcs/screens/settlements/transfer_pots.dart';
import 'package:rad_mysvcs/screens/subscribers/sheets/activate_sheet.dart';
import 'package:rad_mysvcs/screens/subscribers/sheets/add_credit_sheet.dart';
import 'package:rad_mysvcs/screens/subscribers/sheets/pay_debt_sheet.dart';
import 'package:rad_mysvcs/services/transfer_pay.dart';
import 'package:rad_mysvcs/theme/colors.dart';
import 'package:rad_mysvcs/theme/spacing.dart';
import 'package:rad_mysvcs/theme/typography.dart';

import 'visual_perm/visual_perm_harness.dart';

/// «الحوالات» — تصاميم قبل التنفيذ (٢٣ نوفمبر — المالك: «اذا تقدر تعطيني تصاميم قبل»): الشاشات الحقيقيّة بالأداة الجديدة
/// («استلمته»: كاش افتراضيّاً · زين كاش · ماستر · أخرى باسمها) وأزرار «نقدي/دين/جزئي» صغيرة، وبطاقة «رصيد الحوالات» ونافذة
/// «سحب للصندوق»، ومثالٌ لبطاقة «النقد المستلم» بالتقرير. الصور حين يُعطى VISUAL_OUT وحده.
const _phone = VisualDevice('390', Size(390, 844), 3);
const _phoneDark = VisualDevice('390_dark', Size(390, 844), 3, dark: true);
const _narrow = VisualDevice('320', Size(320, 700), 3);

class _Server implements HttpClientAdapter {
  _Server(this.inner);
  final HttpClientAdapter inner;

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
    if (o.path.endsWith('/activation-data')) {
      return ResponseBody.fromString(jsonEncode(_activation), 200, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      });
    }
    return inner.fetch(o, requestStream, cancelFuture);
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
  final f = File('$out/${name}_${d.tag}.png');
  f.parent.createSync(recursive: true);
  f.writeAsBytesSync(png!, flush: true);
}

Future<void> _up() async {
  final server = await visualSetUp(s1bSasOwner);
  ApiClient.dio.httpClientAdapter = _Server(server);
  TransferPay.available.value = true;
  TransferPay.recentOthers.value = const ['آسيا حوالة'];
}

Future<void> _down(WidgetTester t) async {
  await t.pumpWidget(const SizedBox.shrink());
  await t.pump(const Duration(seconds: 4));
  TransferPay.available.value = false;
  TransferPay.recentOthers.value = const [];
  await visualTearDown();
}

Subscriber _hussein() => Subscriber.fromJson(Map<String, dynamic>.from(fixtureSubscribers[2]));

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

Future<void> _tapKey(WidgetTester t, String key) async {
  final f = find.byKey(ValueKey(key));
  await t.ensureVisible(f);
  await t.pump();
  await t.tap(f);
  await settle(t, seconds: 1);
}

Future<void> _showPicker(WidgetTester t) async {
  await t.ensureVisible(find.byKey(const ValueKey('paid-via-note')));
  await settle(t, seconds: 1);
}

/// مثالٌ لبطاقة «النقد المستلم» بالتقرير الماليّ بعد الميزة (للتصميم — الأرقام من الخادم لاحقاً).
Widget _financeMock() => Builder(builder: (context) {
      final cur = 'common.currency'.tr();
      Widget line(IconData i, String label, int v, {bool strong = false}) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(children: [
              Icon(i, size: 18, color: AppColors.textMid),
              const SizedBox(width: Sp.sm),
              Expanded(child: Text(label, style: strong ? AppType.bodyBold(color: AppColors.textHi) : AppType.body(color: AppColors.textBody))),
              Text('${formatIQD(v)} $cur', style: strong ? AppType.bodyBold(color: AppColors.textHi) : AppType.bodyStrong(color: AppColors.textHi)),
            ]),
          );
      return Scaffold(
        appBar: AppBar(title: const Text('التقرير المالي')),
        body: ListView(padding: const EdgeInsets.all(Sp.lg), children: [
          RpCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                const RpIconBox(icon: LucideIcons.banknote, tone: RpTone.money, size: 36),
                const SizedBox(width: Sp.md),
                Text('النقد المستلم', style: AppType.bodyBold(color: AppColors.textHi)),
              ]),
              const SizedBox(height: Sp.sm),
              line(LucideIcons.banknote, 'كاش', 1250000),
              line(LucideIcons.smartphone, 'زين كاش', 175000),
              line(LucideIcons.landmark, 'ماستر', 60000),
              line(LucideIcons.arrowLeftRight, 'آسيا حوالة', 25000),
              Divider(color: AppColors.border),
              line(LucideIcons.sigma, 'المجموع (نفسه — الربح ما يتغيّر)', 1510000, strong: true),
            ]),
          ),
          const SizedBox(height: Sp.md),
          RpCard(
            child: Row(children: [
              const RpIconBox(icon: LucideIcons.arrowLeftRight, tone: RpTone.info, size: 36),
              const SizedBox(width: Sp.md),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('رصيد الحوالات الآن', style: AppType.bodyBold(color: AppColors.textHi)),
                  Text('زين كاش 125,000 · ماستر 60,000 · آسيا حوالة 25,000 — خارج الصندوق',
                      style: AppType.micro(color: AppColors.textMid)),
                ]),
              ),
              Text('210,000 $cur', style: AppType.bodyBold(color: AppColors.brand)),
            ]),
          ),
        ]),
      );
    });

const _pots = [
  TransferPot(key: 'zaincash', label: 'زين كاش', balance: 125000, received: 175000, withdrawn: 50000),
  TransferPot(key: 'master', label: 'ماستر', balance: 60000, received: 60000),
  TransferPot(key: 'other:آسيا حوالة', label: 'آسيا حوالة', balance: 25000, received: 25000),
];

Widget _settlementMock(void Function(TransferPot) onWithdraw) => Builder(builder: (context) {
      final cur = 'common.currency'.tr();
      return Scaffold(
        appBar: AppBar(title: const Text('تسوية الحساب')),
        body: ListView(padding: const EdgeInsets.all(Sp.lg), children: [
          RpCard(
            child: Row(children: [
              const RpIconBox(icon: LucideIcons.wallet, tone: RpTone.money, size: 36),
              const SizedBox(width: Sp.md),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('الصندوق الآن (كاش)', style: AppType.bodyBold(color: AppColors.textHi)),
                  Text('كاش 1,250,000 + سحب من زين كاش 50,000 — الحوالات لا تدخله حتى تسحبها',
                      style: AppType.micro(color: AppColors.textMid)),
                ]),
              ),
              Text('1,300,000 $cur', style: AppType.bodyBold(color: AppColors.textHi)),
            ]),
          ),
          const SizedBox(height: Sp.md),
          TransferPotsCard(pots: _pots, onWithdraw: onWithdraw),
        ]),
      );
    });

void main() {
  setUpAll(visualSetUpAll);

  for (final d in [_phone, _phoneDark, _narrow]) {
    testWidgets('التفعيل: نقدي ⇒ «استلمته» كاش افتراضيّاً ثمّ زين كاش — ${d.tag}', (t) async {
      await _up();
      final sub = _hussein();
      await _openFrom(t, d, (c) => showActivateSheet(c, sub));
      await t.tap(find.text('نقدي'));
      await settle(t, seconds: 1);
      await _showPicker(t);
      expect(find.text('يدخل الصندوق.'), findsOneWidget, reason: 'الافتراضيّ كاش');
      await _shot(t, '01_تفعيل_نقدي_كاش', d);
      await _tapKey(t, 'paid-via-zaincash');
      await _showPicker(t);
      expect(find.textContaining('رصيد «زين كاش»'), findsOneWidget);
      await _shot(t, '02_تفعيل_نقدي_زين_كاش', d);
      expect(t.takeException(), isNull);
      await _down(t);
    });
  }

  testWidgets('التفعيل: جزئي + ماستر، ثمّ «أخرى» باسمها', (t) async {
    await _up();
    final sub = _hussein();
    await _openFrom(t, _phone, (c) => showActivateSheet(c, sub));
    await t.tap(find.text('جزئي'));
    await settle(t, seconds: 1);
    await _tapKey(t, 'paid-via-master');
    await _showPicker(t);
    await _shot(t, '03_تفعيل_جزئي_ماستر', _phone);
    await _tapKey(t, 'paid-via-other');
    await t.enterText(find.byKey(const ValueKey('paid-via-other-name')), 'آسيا حوالة');
    await settle(t, seconds: 1);
    await _showPicker(t);
    expect(find.textContaining('رصيد «آسيا حوالة»'), findsOneWidget);
    await _shot(t, '04_تفعيل_طريقة_أخرى', _phone);
    expect(t.takeException(), isNull);
    await _down(t);
  });

  for (final d in [_phone, _phoneDark]) {
    testWidgets('تسديد دين بزين كاش — ${d.tag}', (t) async {
      await _up();
      final sub = _hussein();
      await _openFrom(t, d, (c) => showPayDebtSheet(c, sub));
      await _tapKey(t, 'paid-via-zaincash');
      await _showPicker(t);
      await _shot(t, '05_تسديد_زين_كاش', d);
      expect(t.takeException(), isNull);
      await _down(t);
    });

    testWidgets('إضافة رصيد: استلمت المبلغ بماستر — ${d.tag}', (t) async {
      await _up();
      final sub = _hussein();
      await _openFrom(t, d, (c) => showAddCreditSheet(c, sub));
      await t.tap(find.text('استلمت المبلغ'));
      await settle(t, seconds: 1);
      await _tapKey(t, 'paid-via-master');
      await _showPicker(t);
      expect(find.textContaining('على رصيد «ماستر»'), findsWidgets);
      await _shot(t, '06_اضافة_رصيد_ماستر', d);
      expect(t.takeException(), isNull);
      await _down(t);
    });

    testWidgets('رصيد الحوالات ثمّ سحب للصندوق — ${d.tag}', (t) async {
      await _up();
      late BuildContext ctx;
      await pumpVisual(t, d, home: (c) {
        ctx = c;
        return _settlementMock((p) => showTransferWithdrawSheet(ctx, p));
      });
      await settle(t, seconds: 2);
      await _shot(t, '07_رصيد_الحوالات', d);
      await t.tap(find.byKey(const ValueKey('transfer-withdraw-zaincash')));
      await settle(t, seconds: 2);
      await t.tap(find.text('كامل الرصيد'));
      await settle(t, seconds: 1);
      await _shot(t, '08_سحب_للصندوق', d);
      expect(t.takeException(), isNull);
      await _down(t);
    });

    testWidgets('التقرير المالي: النقد المستلم مقسوماً — ${d.tag}', (t) async {
      await _up();
      await pumpVisual(t, d, home: (_) => _financeMock());
      await settle(t, seconds: 2);
      await _shot(t, '09_التقرير_المالي', d);
      expect(t.takeException(), isNull);
      await _down(t);
    });
  }
}
