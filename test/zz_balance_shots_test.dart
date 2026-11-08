import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/account_api.dart';
import 'package:rad_mysvcs/api/dashboard_api.dart';
import 'package:rad_mysvcs/screens/dashboard/widgets/stats_grid.dart';
import 'package:rad_mysvcs/services/merged_mode.dart';
import 'package:rad_mysvcs/theme/colors.dart';

import 'visual_perm/visual_perm_harness.dart';

// لقطة بطاقة الرصيد في «كل الشركات» (مؤقّت للمراجعة — لا يُحفظ في المستودع).
void main() {
  setUpAll(visualSetUpAll);
  for (final dark in [false, true]) {
    testWidgets('balance tiles dark=$dark', (t) async {
      final inner = await visualSetUp(s1bSasOwner);
      AccountApi.tokenSource = ({bool force = false}) async => 'acct';
      MergedMode.reset();
      MergedMode.fetchRaw = () async => {
            'routing': true,
            'writes': true,
            'companies': [
              {'key': 'c0000000000a1', 'code': 'supernet', 'username': 'mahdi', 'name': 'سوبرنت (SuperNet) · mahdi', 'status': 'ok', 'admin_id': '2', 'color_index': 0},
              {'key': 'c0000000000a2', 'code': 'supernet', 'username': 'admin@b', 'name': 'سوبرنت (SuperNet) · admin@karbala', 'status': 'ok', 'admin_id': '3', 'color_index': 1},
              {'key': 'c0000000000a3', 'code': 'supernet', 'username': 'x', 'name': 'سوبرنت (SuperNet) · net.zaid', 'status': 'ok', 'admin_id': '4', 'color_index': 2},
              {'key': 'c0000000000a4', 'code': 'ftth', 'provider': 'kit', 'username': '07701112233', 'name': 'المشروع الوطني · 07701112233', 'status': 'ok', 'admin_id': 'watani:5', 'color_index': 3},
              {'key': 'c0000000000a5', 'code': 'earthlink', 'provider': 'earthlink', 'username': 'el1', 'name': 'ايرث لنك (Earthlink)', 'status': 'ok', 'admin_id': 'earthlink:6', 'color_index': 4},
              {'key': 'c0000000000a6', 'code': 'ftth', 'provider': 'kit', 'username': 'memo_r', 'name': 'المشروع الوطني · memo_r', 'status': 'ok', 'admin_id': 'watani:7', 'color_index': 5},
            ],
          };
      await t.runAsync(() => MergedMode.enter());
      const d = VisualDevice('', Size(390, 700), 3);
      AppColors.setDarkMode(dark);
      await pumpVisual(t, VisualDevice(dark ? '_dark' : '', const Size(390, 700), 3, dark: dark),
          home: (_) => Scaffold(
                body: Padding(
                  padding: const EdgeInsets.all(16),
                  child: StatsGrid(
                    wallet: const WalletResult(balance: 0, points: 0),
                    debtors: null,
                    walletLines: const [
                      (key: 'c0000000000a1', balance: 4378141, reason: null),
                      (key: 'c0000000000a2', balance: 219750, reason: null),
                      (key: 'c0000000000a3', balance: 14064750, reason: null),
                      (key: 'c0000000000a4', balance: 5731502, reason: null),
                      (key: 'c0000000000a5', balance: -4000, reason: null),
                      (key: 'c0000000000a6', balance: null, reason: 'تعذّرت قراءة الرصيد'),
                    ],
                  ),
                ),
              ));
      await settle(t, seconds: 1);
      await shoot(t, s1bSasOwner, 'balance_tiles', VisualDevice(dark ? '_dark' : '', const Size(390, 700), 3, dark: dark), inner);
      AppColors.setDarkMode(false);
      MergedMode.reset();
      await visualTearDown();
      expect(d.size.width, 390);
    });
  }
}
