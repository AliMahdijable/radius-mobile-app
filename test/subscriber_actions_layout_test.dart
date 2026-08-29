import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/screens/subscribers/widgets/subscriber_actions.dart';

void main() {
  testWidgets('انحدار 2026-08-29: صفّ البلاطات لا يرمي داخل ListView وما بعده يُرسم', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView(
          children: [
            SubscriberActionTiles(actions: [
              SubAction(icon: Icons.add, label: 'تمديد', onTap: () {}),
              SubAction(icon: Icons.edit, label: 'تعديل', onTap: () {}),
              SubAction(icon: Icons.block, label: 'تعطيل', onTap: () {}),
              SubAction(icon: Icons.more_horiz, label: 'المزيد', onTap: () {}),
            ]),
            const SizedBox(height: 12),
            Container(height: 80, color: Colors.red, child: const Text('كارت بعد البلاطات')),
          ],
        ),
      ),
    ));
    expect(tester.takeException(), isNull);
    expect(find.text('كارت بعد البلاطات'), findsOneWidget);
  });
}
