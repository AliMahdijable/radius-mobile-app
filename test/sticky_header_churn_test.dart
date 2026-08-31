import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/subscribers/widgets/subscriber_card_v3.dart';
import 'package:rad_mysvcs/theme/colors.dart';

/// الرأس المثبَّت لا يكسر الشجرة تحت التمرير السريع.
///
/// 🐛 بلاغ 2026-08-31: فيضٌ لا ينقطع في قسم «غير مفعّل» —
///   Failed assertion: '!semantics.parentDataDirty': is not true.
///   Null check operator used on a null value
/// مئات المرّات في الثانية.
///
/// السبب أُثبت بالعزل: `AnimatedSwitcher` في `_ChipsBarDelegate` يُبقي
/// الطفل الخارج حيّاً 180ms. وعتبة الانضغاط 56/40 بكسل، فتمريرة سريعة
/// تعبرها ذهاباً وإياباً داخل تلك النافذة فيعود **نفس** المفتاح بينما
/// القديم ما زال خارجاً → «Duplicate keys found» → شجرة عناصر مكسورة →
/// فيضُ محرّك الدلالات عليها بلا توقّف.
///
/// نفس هذا الاختبار بالمبدّل يرصد 4 أخطاء وبلاه صفراً — وهو ما يجعله
/// حكماً لا توثيقاً.
class _Delegate extends SliverPersistentHeaderDelegate {
  _Delegate({required this.child, required this.compactChild, required this.compact});
  final Widget child;
  final Widget compactChild;
  final bool compact;
  static const double _height = 44;
  @override
  double get minExtent => _height;
  @override
  double get maxExtent => _height;
  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) => SizedBox(
        height: _height,
        child: compact ? compactChild : child,
      );
  @override
  bool shouldRebuild(_Delegate old) =>
      old.child != child || old.compactChild != compactChild || old.compact != compact;
}

class _Host extends StatefulWidget {
  const _Host();
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  final _scroll = ScrollController();
  bool _compact = false;
  int _tick = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      final want = _scroll.offset > 40;
      if (want != _compact) setState(() => _compact = want);
    });
  }

  Subscriber _sub(int i) => Subscriber(
        idx: 'u$i',
        username: 'user$i',
        firstname: 'اسم',
        lastname: 'المشترك',
        phone: '07712345678',
        expiration: '2026-09-20 12:00:00',
        remainingDays: 20,
        notes: '-25000',
        hasDebtFlag: true,
        debt: 25000,
        isEnabled: false, // ← القسم المعطَّل
        isOnlineFlag: false,
      );

  @override
  Widget build(BuildContext context) {
    final subs = [for (var i = 0; i < 20; i++) _sub(i)];
    return Scaffold(
      body: CustomScrollView(
        controller: _scroll,
        slivers: [
          SliverToBoxAdapter(child: SizedBox(height: 160, child: Text('رأس $_tick'))),
          SliverPersistentHeader(
            pinned: true,
            delegate: _Delegate(
              compact: _compact,
              compactChild: const ColoredBox(color: Colors.white, child: Text('بحث')),
              child: ColoredBox(
                color: Colors.white,
                child: Row(children: [for (var i = 0; i < 6; i++) Text('شريحة$i ')]),
              ),
            ),
          ),
          SliverList.separated(
            itemCount: subs.length,
            itemBuilder: (_, i) => SubscriberCardV3(
              key: ValueKey(subs[i].idx),
              sub: subs[i],
              selected: false,
              onTap: () {},
              onLongPress: () {},
            ),
            separatorBuilder: (_, __) => const SizedBox(height: 8),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => setState(() => _tick++),
        child: const Icon(Icons.refresh),
      ),
    );
  }
}

void main() {
  _sourceGuard();
  testWidgets('رأس مثبَّت + AnimatedSwitcher فوق كروت معطَّلة، مع الدلالات', (t) async {
    final caught = <String>[];
    final prev = FlutterError.onError;
    FlutterError.onError = (d) {
      caught.add('${d.library} | ${d.exceptionAsString()} | ctx=${d.context} | ${d.exception.runtimeType}');
    };
    final handle = t.ensureSemantics();
    AppColors.setDarkMode(false);
    await t.pumpWidget(const MaterialApp(home: _Host()));
    await t.pumpAndSettle();

    // مرِّر لتفعيل الوضع المضغوط أثناء تحوّل AnimatedSwitcher
    await t.drag(find.byType(CustomScrollView), const Offset(0, -200));
    await t.pump(); // إطار واحد — التحوّل جارٍ ولم يكتمل

    // setState وسط التحوّل — هذا ما يفعله الاستطلاع كلّ 5 ثوانٍ
    await t.tap(find.byType(FloatingActionButton));
    await t.pump(const Duration(milliseconds: 60));

    await t.pumpAndSettle();

    // ذهاباً وإياباً
    for (var i = 0; i < 3; i++) {
      await t.drag(find.byType(CustomScrollView), const Offset(0, 300));
      await t.pump(const Duration(milliseconds: 40));
      await t.tap(find.byType(FloatingActionButton));
      await t.pump(const Duration(milliseconds: 40));
      await t.drag(find.byType(CustomScrollView), const Offset(0, -300));
      await t.pump(const Duration(milliseconds: 40));
    }
    await t.pumpAndSettle();
    FlutterError.onError = prev;
    // ignore: avoid_print
    for (final c in caught.toSet()) {
      print('‼️ $c');
    }
    // ignore: avoid_print
    print('عدد الأخطاء: ${caught.length} · فريدة: ${caught.toSet().length}');
    handle.dispose();
  });
}

// ─────────────────────────────────────────────────────────────
// حارس مصدريّ: لا يعود المبدّل إلى الرأس المثبَّت.
//
// الاختبار أعلاه يحرس الشكل الآمن في محاكٍ؛ وهذا يحرس الملفّ الحقيقيّ —
// فمحاكٍ سليم لا ينفع إن عاد الأصل إلى النمط المكسور.

void _sourceGuard() {
  test('_ChipsBarDelegate لا يستعمل AnimatedSwitcher', () {
    final src =
        File('lib/screens/subscribers/subscribers_screen.dart').readAsStringSync();
    final i = src.indexOf('class _ChipsBarDelegate');
    expect(i, greaterThan(0), reason: 'لم يُعثر على الصنف — رُبّما أُعيدت تسميته');
    final j = src.indexOf('\nclass ', i + 1);
    final raw = j > 0 ? src.substring(i, j) : src.substring(i);
    // ⚠️ جرِّد التعليقات: تعليق الصنف نفسه يشرح لماذا أُزيل المبدّل
    // ويذكر اسمه، فبلا التجريد يُسقط الحارسُ الإصلاحَ الذي يحرسه.
    final body = raw
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');
    expect(body.contains('AnimatedSwitcher'), isFalse,
        reason: 'AnimatedSwitcher بمفاتيح ثابتة داخل رأس مثبَّت يُنتج '
            '«Duplicate keys found» عند التمرير السريع — راجع تعليق الصنف');
    expect(body.contains('AnimatedCrossFade'), isFalse,
        reason: 'AnimatedCrossFade تُبقي الطفلين مركَّبَين، فيصير _searchCtrl '
            'مربوطاً بحقلَي نصّ معاً');
  });
}
