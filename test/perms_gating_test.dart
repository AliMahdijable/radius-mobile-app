import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/archive_info.dart';
import 'package:rad_mysvcs/core/widgets/design_sheet.dart';
import 'package:rad_mysvcs/screens/settlements/widgets/archive_bar.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';

/// حرّاس الحجب بالصلاحيّة — **على الودجت لا على نصّ المصدر**.
///
/// ⚠️ كلّ حرّاس الصلاحيّات قبل اليوم كانت تقرأ نصّ الملفّ: تُمسك حذف
/// سطرٍ ولا تُمسك منطقاً يكذب. وهذه تبني الشجرة فعلاً وتسأل: هل يرى
/// هذا الموظّفُ هذا العنصر؟
///
/// والحالات منقولةٌ من فحصٍ حيٍّ على `admin@poox` (‏2026-10-04) بثلاثة
/// موظّفين حقيقيّين: الخادم يردّ 403 `PERMISSION_DENIED` لمن لا يملك
/// `settlements.view` — فالإخفاء هنا يوافق الخادم لا يسبقه.
void main() {
  tearDown(PermissionsService.debugReset);

  /// العدّ بالنوع لا بالنصّ: الترجمة لا تُحمَّل في بيئة الاختبار،
  /// ومطابقةُ نصٍّ تجعل الحارس رهينةَ ملفّ ترجمة.
  Future<void> show(WidgetTester t, {ArchiveInfo? archive}) async {
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Directionality(
            textDirection: TextDirection.rtl,
            child: SingleChildScrollView(
              child: ArchiveBar(
                archive: archive,
                includeArchived: false,
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await t.pump();
  }

  const full = ArchiveInfo(
    hidden: true,
    included: false,
    settlements: 3,
    lastNumber: 4,
  );

  group('حبّة «تسوية الحساب» في شريط الأرشيف', () {
    testWidgets('🚨 تختفي عن موظّفٍ بلا settlements.view', (t) async {
      // `qa_none` في الفحص الحيّ: يملك `reports.expenses` فيرى الصرفيات
      // والشريط، ولا يملك `settlements.view` فيردّ الخادم 403.
      PermissionsService.debugSet(
        isEmployee: true,
        permissions: const {'reports.expenses': true},
      );
      await show(t, archive: full);
      // حبّتان: «الحاليّة» و«مع الأرشيف». والثالثة محجوبة.
      expect(find.byType(ToneChip), findsNWidgets(2));
      // والشريط نفسه ظاهرٌ — الحجب للحبّة وحدها لا للسياق الذي يشرح
      // لماذا نقصت القائمة.
      expect(find.byType(ArchiveBar), findsOneWidget);
      expect(find.byType(Text), findsWidgets);
    });

    testWidgets('وتظهر لمن يملكها', (t) async {
      // `qa_view` في الفحص الحيّ.
      PermissionsService.debugSet(
        isEmployee: true,
        permissions: const {
          'reports.expenses': true,
          'settlements.view': true,
        },
      );
      await show(t, archive: full);
      expect(find.byType(ToneChip), findsNWidgets(3));
    });

    testWidgets('والمدير يراها دائماً', (t) async {
      PermissionsService.debugSet(isEmployee: false);
      await show(t, archive: full);
      expect(find.byType(ToneChip), findsNWidgets(3));
    });
  });

  group('الشريط لا يظهر بلا تسويات', () {
    testWidgets('🚨 صفر تسوياتٍ = لا شريط إطلاقاً', (t) async {
      PermissionsService.debugSet(isEmployee: false);
      await show(
        t,
        archive: const ArchiveInfo(
            hidden: false, included: false, settlements: 0),
      );
      expect(find.byType(ToneChip), findsNothing);
    });

    testWidgets('وغيابُ الوصف كلّه كذلك', (t) async {
      PermissionsService.debugSet(isEmployee: false);
      await show(t, archive: null);
      expect(find.byType(ToneChip), findsNothing);
    });
  });

  group('منفذ الاختبار نفسه', () {
    test('🚨 قبل الضبط تُرجع has قيمة true — فاختبارٌ ينسى الضبط يمرّ كاذباً',
        () {
      PermissionsService.debugReset();
      expect(PermissionsService.has('settlements.view'), isTrue,
          reason: 'سلوكٌ مقصود في الإنتاج، ومصيدةٌ في الاختبار');
    });

    test('وبعده يُحجب غير الممنوح', () {
      PermissionsService.debugSet(
        isEmployee: true,
        permissions: const {'reports.expenses': true},
      );
      expect(PermissionsService.has('reports.expenses'), isTrue);
      expect(PermissionsService.has('settlements.view'), isFalse);
      expect(PermissionsService.has('managers.edit'), isFalse);
    });

    test('والمدير يملك كلّ شيء', () {
      PermissionsService.debugSet(isEmployee: false);
      expect(PermissionsService.has('settlements.create'), isTrue);
      expect(PermissionsService.has('أيّ مفتاحٍ كان'), isTrue);
    });
  });

  // Pro: المدير الفرعيّ يُضبَط بصلاحيّات الساس المعياريّة (لا كامل الصلاحيّات).
  // دلالةٌ مختلفةٌ عن الموظّف: مفتاحٌ خارج خريطة الساس = مسموح (ميزةٌ تطبيقيّة).
  group('المدير الفرعيّ مقيَّدٌ بصلاحيّات الساس (Pro)', () {
    test('يختفي الممنوع، يظهر المسموح، والمفتاح خارج الخريطة مسموح', () {
      PermissionsService.debugSet(
        isEmployee: false,
        managerRestricted: true,
        managerCaps: const {
          'subscribers.delete': false,
          'subscribers.show_password': true,
          'subscribers.pay_debt': true,
        },
      );
      expect(PermissionsService.has('subscribers.delete'), isFalse);
      expect(PermissionsService.has('subscribers.show_password'), isTrue);
      expect(PermissionsService.has('subscribers.pay_debt'), isTrue);
      // خارج خريطة الساس (ميزةٌ تطبيقيّة لا يحكمها الساس) → مسموح افتراضاً
      expect(PermissionsService.has('settlements.view'), isTrue);
      expect(PermissionsService.isEmployee, isFalse);
    });

    test('hasAll/hasAny للمدير المقيَّد', () {
      PermissionsService.debugSet(
        isEmployee: false,
        managerRestricted: true,
        managerCaps: const {
          'subscribers.delete': false,
          'subscribers.edit': true,
        },
      );
      expect(
          PermissionsService.hasAll(
              const ['subscribers.edit', 'subscribers.delete']),
          isFalse);
      expect(
          PermissionsService.hasAny(
              const ['subscribers.delete', 'subscribers.edit']),
          isTrue);
      expect(PermissionsService.hasAll(const ['x.one', 'x.two']), isTrue);
    });

    test('super-admin غير مقيَّدٍ ولو مرّت خريطة', () {
      PermissionsService.debugSet(isEmployee: false);
      expect(PermissionsService.has('subscribers.delete'), isTrue);
    });
  });
}
