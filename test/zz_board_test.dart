import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// لوحة «قبل/بعد» للمالك (مؤقّت — لا يُحفظ في المستودع): صورٌ متجاورة بعناوين عربيّة.
// BOARD_SPEC=<json file>: {"out": "...png", "title": "...", "items": [{"path": "...png", "caption": "...", "tone": "before|after"}]}
Future<void> _font() async {
  final loader = FontLoader('Plex');
  for (final w in [400, 600, 700]) {
    final f = File('assets/fonts/IBMPlexSansArabic-$w.ttf');
    loader.addFont(Future.value(ByteData.view(f.readAsBytesSync().buffer)));
  }
  await loader.load();
}

void main() {
  testWidgets('board', (t) async {
    final specPath = Platform.environment['BOARD_SPEC'] ?? '';
    if (specPath.isEmpty) return;
    final spec = jsonDecode(File(specPath).readAsStringSync()) as Map<String, dynamic>;
    final items = (spec['items'] as List).cast<Map<String, dynamic>>();
    await t.runAsync(_font);
    const colW = 390.0;
    const imgH = 844.0;
    const gap = 28.0;
    final width = items.length * colW + (items.length + 1) * gap;
    const height = imgH + 250.0;
    t.view.physicalSize = Size(width, height) * 2;
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    final images = <ui.Image>[];
    await t.runAsync(() async {
      for (final it in items) {
        final codec = await ui.instantiateImageCodec(File(it['path'] as String).readAsBytesSync());
        images.add((await codec.getNextFrame()).image);
      }
    });
    const key = ValueKey('board');
    await t.pumpWidget(Directionality(
      textDirection: TextDirection.rtl,
      child: RepaintBoundary(
        key: key,
        child: Container(
          color: const Color(0xFFE9ECE8),
          padding: const EdgeInsets.all(gap),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(spec['title'] as String,
                  style: const TextStyle(fontFamily: 'Plex', fontSize: 30, fontWeight: FontWeight.w700, color: Color(0xFF12201A))),
              const SizedBox(height: 18),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < items.length; i++) ...[
                    if (i > 0) const SizedBox(width: gap),
                    SizedBox(
                      width: colW,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: items[i]['tone'] == 'before' ? const Color(0xFFF6E3E1) : const Color(0xFFDDEFE4),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(items[i]['caption'] as String,
                              style: TextStyle(
                                  fontFamily: 'Plex',
                                  fontSize: 19,
                                  fontWeight: FontWeight.w600,
                                  color: items[i]['tone'] == 'before' ? const Color(0xFF9B2C22) : const Color(0xFF14532D))),
                        ),
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(22),
                          child: SizedBox(
                            width: colW,
                            height: imgH,
                            child: RawImage(image: images[i], fit: (Platform.environment['BOARD_FIT'] == 'contain') ? BoxFit.contain : BoxFit.cover, alignment: Alignment.topCenter),
                          ),
                        ),
                      ]),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    ));
    await t.pump();
    final boundary = t.renderObject<RenderRepaintBoundary>(find.byKey(key));
    final png = await t.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    });
    File(spec['out'] as String)
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(png!);
  });
}
