import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/screens/portal_settings/widgets/link_image_preview.dart';

/// معاينة رابط الصورة في «بوابة المشترك» — تقول الحقيقة ولا تُغرق الشبكة.
///
/// 🐛 تدقيق البوّابة ٢٠٢٦-١٠-١٧ (§2.6): 17 من 27 شعاراً صفحاتٌ أو روابط
/// ميّتة، والمعاينة كانت تعرض للرابط المكسور أيقونة الحقل الفارغ نفسها.
void main() {
  late List<String> loads;
  late ui.Image pixel;
  final pending = <String, Completer<ImageInfo>>{};
  final original = LinkImagePreview.imageFor;

  setUpAll(() async {
    pixel = await createTestImage(width: 4, height: 4);
  });

  setUp(() {
    loads = [];
    pending.clear();
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    LinkImagePreview.imageFor = (url) => _FakeImage(url, loads, pending, pixel);
  });

  tearDown(() => LinkImagePreview.imageFor = original);

  final url = ValueNotifier<String>('');
  // إعادة بناءٍ بالرابط نفسه — ككتابةٍ في حقل الاسم بجانب المعاينة.
  final rebuild = ValueNotifier<int>(0);

  Future<void> show(WidgetTester t, String start) async {
    url.value = start;
    await t.pumpWidget(Directionality(
      textDirection: TextDirection.rtl,
      child: ListenableBuilder(
        listenable: Listenable.merge([url, rebuild]),
        builder: (_, __) => LinkImagePreview(
          url: url.value,
          size: 40,
          builder: (context, image, state) => Column(
            children: [Text(state.name), if (image != null) image],
          ),
        ),
      ),
    ));
    await t.pump(); // ردّ الصورة (خطأ صفحة الويب يصل في مهمّةٍ دقيقة)
  }

  /// كتابةٌ ثمّ توقّف: إطارٌ يُطبّق التغيير (يبدأ المؤقّت)، ثمّ المهلة، ثمّ
  /// إطارا الطلب وردّه.
  Future<void> type(WidgetTester t, String s) async {
    url.value = s;
    await t.pump();
    await t.pump(LinkImagePreview.settle);
    await t.pump();
    await t.pump();
  }

  testWidgets('الحقل الفارغ: لا معاينة ولا طلب', (t) async {
    await show(t, '');
    expect(find.text('none'), findsOneWidget);
    expect(loads, isEmpty);
  });

  testWidgets('🚨 ما ليس رابط ويب: «ليس صورة» فوراً بلا طلب', (t) async {
    for (final s in ['logo.png', '@mynet', 'ftp://x.com/a.png', 'https://']) {
      await show(t, s);
      expect(find.text('broken'), findsOneWidget, reason: s);
    }
    expect(loads, isEmpty);
  });

  testWidgets('🚨 صفحة ويب لا صورة (ibb.co): «ليس صورة» لا أيقونةٌ صامتة',
      (t) async {
    await show(t, 'https://ibb.co/page1');
    expect(find.text('broken'), findsOneWidget);
    expect(find.byType(RawImage), findsNothing);
    expect(loads, ['https://ibb.co/page1']);
  });

  testWidgets('صورةٌ حقيقيّة تُعرض', (t) async {
    await show(t, 'https://i.ibb.co/x/logo.png');
    expect(find.text('ok'), findsOneWidget);
    expect(find.byType(RawImage), findsOneWidget);
  });

  testWidgets('ما لم يصل بعد «يُحمَّل» — لا يُحكم عليه قبل ردّه', (t) async {
    await show(t, 'https://cdn.example/slow.png');
    expect(find.text('loading'), findsOneWidget);
    expect(find.text('broken'), findsNothing);
    pending['https://cdn.example/slow.png']!
        .complete(ImageInfo(image: pixel.clone()));
    await t.pump(); // الردّ (مهمّة دقيقة) ثمّ إطارٌ يرسمه
    await t.pump();
    expect(find.text('ok'), findsOneWidget);
  });

  testWidgets('🚨 الكتابة: طلبٌ واحد بعد التوقّف لا طلبٌ لكلّ حرف', (t) async {
    await show(t, '');
    for (final s in [
      'h',
      'ht',
      'https://',
      'https://i.co/a',
      'https://i.co/a.png'
    ]) {
      url.value = s;
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(loads, isEmpty, reason: 'لم يتوقّف بعد');
    expect(find.text('broken'), findsNothing, reason: 'لا وميض «ليس صورة»');
    await t.pump(LinkImagePreview.settle);
    await t.pump();
    expect(loads, ['https://i.co/a.png']);
    expect(find.text('ok'), findsOneWidget);
  });

  testWidgets('إعادة بناءٍ بالرابط نفسه لا تؤجّل المعاينة من جديد', (t) async {
    await show(t, '');
    url.value = 'https://i.co/a.png';
    await t.pump(); // يبدأ المؤقّت
    await t.pump(const Duration(milliseconds: 300));
    rebuild.value++; // حرفٌ في حقل الاسم
    await t.pump();
    await t.pump(const Duration(milliseconds: 200)); // 500 > 450 من البداية
    await t.pump();
    expect(loads, ['https://i.co/a.png'],
        reason: 'لو أعاد البناءُ ضبطَ المؤقّت لانتظر حتى 750');
  });

  testWidgets('رابطٌ جديد لا يرث حكم سابقه', (t) async {
    await show(t, 'https://ibb.co/page1');
    expect(find.text('broken'), findsOneWidget);
    await type(t, 'https://i.ibb.co/x/logo.png');
    expect(find.text('ok'), findsOneWidget);
    await type(t, 'https://ibb.co/page2');
    expect(find.text('broken'), findsOneWidget);
  });

  testWidgets('المسح فوريّ', (t) async {
    await show(t, 'https://i.ibb.co/x/logo.png');
    expect(find.text('ok'), findsOneWidget);
    url.value = '';
    await t.pump();
    expect(find.text('none'), findsOneWidget);
  });
}

/// صورةٌ بلا شبكة. «page» في الرابط = صفحة ويب لا يفكّها المحرّك صورةً،
/// و«slow» = لم يصل الردّ بعد (يُكمَل من [pending])، وغيرهما صورة.
class _FakeImage extends ImageProvider<_FakeImage> {
  _FakeImage(this.url, this.loads, this.pending, this.pixel);
  final String url;
  final List<String> loads;
  final Map<String, Completer<ImageInfo>> pending;
  final ui.Image pixel;

  @override
  Future<_FakeImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<_FakeImage>(this);

  @override
  ImageStreamCompleter loadImage(_FakeImage key, ImageDecoderCallback decode) {
    loads.add(url);
    final Future<ImageInfo> info;
    if (url.contains('page')) {
      info = Future<ImageInfo>.error(const FormatException('not an image'));
    } else if (url.contains('slow')) {
      info = (pending[url] = Completer<ImageInfo>()).future;
    } else {
      info = SynchronousFuture(ImageInfo(image: pixel.clone()));
    }
    return OneFrameImageStreamCompleter(info);
  }

  @override
  bool operator ==(Object other) => other is _FakeImage && other.url == url;

  @override
  int get hashCode => url.hashCode;
}
