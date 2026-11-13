import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:rad_mysvcs/screens/subscribers/widgets/foldable_section.dart';
import 'package:rad_mysvcs/services/section_fold.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// طيّ أقسام صفحة المشترك — المالك ١٤ نوفمبر: «الاقسام خليهن توكل كلوز واحد منهن ع الاقل بشكل دائمي».
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SectionFold.debugReset();
  });

  Widget host(String id, {required VoidCallback onBuilt}) => MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: FoldableSection(
              id: id,
              title: 'الجهاز الثاني',
              icon: LucideIcons.router,
              builder: (fold) {
                onBuilt();
                return Column(children: [
                  FoldTitle(icon: LucideIcons.router, title: 'الجهاز الثاني', onFold: fold),
                  const Text('جسم الكرت'),
                ]);
              },
            ),
          ),
        ),
      );

  testWidgets('«الجهاز الثاني» مطويٌّ افتراضاً: شريطٌ بعنوانه، وكرته لا يُبنى (لا فحص) حتى يُفتح', (t) async {
    var built = 0;
    await t.pumpWidget(host('dev2', onBuilt: () => built++));
    await t.pump();
    expect(find.text('الجهاز الثاني'), findsOneWidget);
    expect(find.text('جسم الكرت'), findsNothing);
    expect(built, 0, reason: 'المطويّ لا يُبنى كرته');
    await t.tap(find.byKey(const ValueKey('fold-open-dev2')));
    await t.pump();
    expect(find.text('جسم الكرت'), findsOneWidget);
    expect(built, greaterThan(0));
  });

  testWidgets('النقر على العنوان يطوي، والحال تُحفظ وتعود بعد إعادة التشغيل', (t) async {
    await t.pumpWidget(host('dev1', onBuilt: () {}));
    await t.pump();
    expect(find.text('جسم الكرت'), findsOneWidget, reason: '«معلومات الجهاز» مفتوحٌ افتراضاً');
    await t.tap(find.byKey(const ValueKey('fold-close')));
    await t.pumpAndSettle();
    expect(find.text('جسم الكرت'), findsNothing);
    expect((await SharedPreferences.getInstance()).getBool('subscriber.fold.v1.dev1'), isTrue);
    // «إعادة تشغيل»: الذاكرة تُمسح والمحفوظ يبقى
    SectionFold.debugReset();
    await t.pumpWidget(const SizedBox.shrink());
    await t.pumpWidget(host('dev1', onBuilt: () {}));
    await t.pumpAndSettle();
    expect(find.text('جسم الكرت'), findsNothing, reason: 'ما طواه الوكيل يبقى مطويّاً');
    await t.tap(find.byKey(const ValueKey('fold-open-dev1')));
    await t.pumpAndSettle();
    expect((await SharedPreferences.getInstance()).getBool('subscriber.fold.v1.dev1'), isFalse);
  });

  test('الافتراض: الثاني مطويّ، وعنوان الجهاز ومعلوماته مفتوحان', () {
    expect(SectionFold.of('dev2').value, isTrue);
    expect(SectionFold.of('dev1').value, isFalse);
    expect(SectionFold.of('addr').value, isFalse);
  });
}
