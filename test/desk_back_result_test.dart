import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:rad_mysvcs/core/platform/desktop_layout.dart';
import 'package:rad_mysvcs/screens/desktop/desk_widgets.dart';

/// المالك ٢٧ أكتوبر (الحاسبة): «احوله snmp يكلي تم الحفظ، اخرج وارجع للجهاز يرجعه api!» — الخادم حفظ، لكنّ رجوع
/// الحاسبة كان maybePop بلا نتيجة فلا تتحدّث القائمة. زرّ رجوع الحاسبة صار زرّ الصفحة نفسه إن كان لها واحد.
void main() {
  testWidgets('🚨 رجوع الحاسبة يحمل نتيجة الصفحة (زرّها) لا رجوعاً فارغاً', (t) async {
    Object? result = 'لم يرجع';
    // الغلاف فوق الـNavigator (كما في التطبيق) — الصفحات المدفوعة ليست أبناء home.
    await t.pumpWidget(MaterialApp(
      builder: (context, child) => Directionality(textDirection: TextDirection.rtl, child: DesktopScope(child: child!)),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Builder(
          builder: (_) => Builder(
            builder: (ctx) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await Navigator.of(ctx).push<bool>(MaterialPageRoute(
                    builder: (c) => Scaffold(
                      appBar: deskPageBar(
                        c,
                        mobile: AppBar(
                          title: const Text('جهاز'),
                          leading: IconButton(icon: const Icon(LucideIcons.arrowRight), onPressed: () => Navigator.pop(c, true)),
                        ),
                      ),
                      body: const SizedBox(),
                    ),
                  ));
                },
                child: const Text('افتح'),
              ),
            ),
          ),
        ),
      ),
    ));
    await t.tap(find.text('افتح'));
    await t.pumpAndSettle();
    expect(find.text('جهاز'), findsOneWidget, reason: 'رأس الحاسبة');
    expect(find.byType(AppBar), findsNothing, reason: 'رأس الحاسبة لا شريط الهاتف');
    await t.tap(find.byIcon(LucideIcons.arrowRight).first);
    await t.pumpAndSettle();
    expect(result, isTrue);
  });
}
