import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/screens/my_alerts/notif_sounds_screen.dart';
import 'package:rad_mysvcs/services/notif_sound_engine.dart';
import 'package:rad_mysvcs/services/notif_sounds.dart';

/// «أصوات الإشعارات» — الشاشة بمنافذ وهميّة: الصفوف الاثنا عشر، المفتاح يحفظ، نافذة النغمة (أندرويد ١٥ خياراً، الآيفون ١٤)،
/// اختيار نغمة وحفظها، و«إشعار تجريبي على هاتفي» يحفظ الاختيار ثمّ يطلب الدفع ويقول متى يوصل.
void main() {
  late List<NotifSoundPrefs> saved;
  late List<String> tests;

  setUp(() {
    saved = [];
    tests = [];
    NotifSoundsHooks.onSaved = (p) async => saved.add(p);
    NotifSoundsHooks.loadPrefs = () async => NotifSoundPrefs.defaults;
    NotifSoundsHooks.readStatus = () async => const PhoneSoundStatus(notificationsOn: true, soundOn: true);
    NotifSoundsHooks.preview = (_, __) async {};
    NotifSoundsHooks.sendTest = (c) async {
      tests.add(c.id);
      return null;
    };
  });
  tearDown(() {
    NotifSoundsHooks.reset();
    SoundPlatform.isIos = () => false;
  });

  Future<void> pump(WidgetTester t, {bool ios = false}) async {
    SoundPlatform.isIos = () => ios;
    t.view.physicalSize = const Size(430 * 3, 2400 * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(const MaterialApp(
      home: Directionality(textDirection: TextDirection.rtl, child: NotifSoundsScreen()),
    ));
    await t.pumpAndSettle();
  }

  testWidgets('١٢ صفّاً بعناوين العائلات، والطلبات تنطق نوعها افتراضاً', (t) async {
    await pump(t);
    for (final c in kSoundCategories) {
      expect(find.byKey(ValueKey('sound-${c.id}')), findsOneWidget, reason: c.id);
    }
    for (final title in kSoundFamilyTitles.values) {
      expect(find.text(title), findsOneWidget);
    }
    expect(find.textContaining('ينطق:'), findsNWidgets(6));
    expect(find.byKey(const ValueKey('sounds-loud')), findsOneWidget, reason: 'أندرويد: الطلبات بصوت المنبّه');
  });

  testWidgets('المفتاح يطفئ صوت فئةٍ ويحفظ، والسطر يقول «بلا صوت»', (t) async {
    await pump(t);
    final row = find.byKey(const ValueKey('sound-expiry'));
    await t.ensureVisible(row);
    await t.tap(find.descendant(of: row, matching: find.byType(Switch)));
    await t.pumpAndSettle();
    expect(saved, isNotEmpty);
    expect(saved.last.isOn(kSoundCategories.firstWhere((c) => c.id == 'expiry')), isFalse);
    expect(find.descendant(of: row, matching: find.textContaining('بلا صوت')), findsOneWidget);
  });

  testWidgets('نافذة النغمة: أندرويد ١٥ خياراً بـ«من جهازك»، واختيار «جرس» يُحفظ', (t) async {
    await pump(t);
    await t.tap(find.byKey(const ValueKey('sound-balance')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('tone-device')), findsOneWidget);
    var n = 0;
    for (final tone in kTones) {
      if (find.byKey(ValueKey('tone-${tone.id}')).evaluate().isNotEmpty) n += 1;
    }
    expect(n + 1, 15);
    await t.scrollUntilVisible(find.byKey(const ValueKey('tone-bell')), 100, scrollable: find.byType(Scrollable).last);
    await t.tap(find.byKey(const ValueKey('tone-bell')));
    await t.pumpAndSettle();
    await t.tap(find.text('حفظ'));
    await t.pumpAndSettle();
    expect(saved.last.toneOf(kSoundCategories.firstWhere((c) => c.id == 'balance')), 'bell');
    expect(find.descendant(of: find.byKey(const ValueKey('sound-balance')), matching: find.text('جرس')), findsOneWidget);
  });

  testWidgets('الآيفون: بلا «من جهازك» ولا «صوت المنبّه»، والملاحظة بمكانها', (t) async {
    await pump(t, ios: true);
    expect(find.byKey(const ValueKey('sounds-loud')), findsNothing);
    expect(find.byKey(const ValueKey('sounds-ios-note')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('sound-ticket')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('tone-device')), findsNothing);
  });

  testWidgets('«إشعار تجريبي على هاتفي»: يحفظ الاختيار ثمّ يطلب الدفع، ويقول بعد كم يوصل', (t) async {
    await pump(t);
    await t.tap(find.byKey(const ValueKey('sound-store')));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.byKey(const ValueKey('tone-harp')), 100, scrollable: find.byType(Scrollable).last);
    await t.tap(find.byKey(const ValueKey('tone-harp')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('tone-test')));
    await t.pumpAndSettle();
    expect(tests, ['store']);
    expect(saved.last.toneOf(kSoundCategories.firstWhere((c) => c.id == 'store')), 'harp');
    expect(find.textContaining('يوصلك بعد ٥ ثواني'), findsOneWidget);
  });
}
