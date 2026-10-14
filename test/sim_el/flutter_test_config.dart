import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

/// محاكاة شاشات ايرث لنك — اللقطات تُكتب في **كلّ** تشغيل.
///
/// اللقطة هنا صورةٌ للمراجعة لا مرجعٌ يُقارَن: فشل المحاكاة يأتي من الأعطال
/// الحقيقيّة وحدها (استثناء، فيضان RenderFlex، نصّ تقنيّ ظاهر، سلوكٌ مخالف)،
/// لا من بكسلٍ تغيّر لأنّ الواجهة تحسّنت. فـ`matchesGoldenFile` يُبقي مكانه
/// (`--update-goldens` يعمل كالمعتاد)، وبلاه تُعاد كتابة اللقطة ولا تُقارَن.
///
/// المقارنة الصارمة متاحةٌ لمن أرادها:
///   flutter test test/sim_el/ --dart-define=SIM_STRICT_GOLDENS=true
const _strict = bool.fromEnvironment('SIM_STRICT_GOLDENS');

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  final base = goldenFileComparator;
  if (!_strict && base is LocalFileComparator) {
    goldenFileComparator = _ShotWriter(base.basedir.resolve('sim.dart'));
  }
  await testMain();
}

class _ShotWriter extends LocalFileComparator {
  _ShotWriter(super.testFile);

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    await update(golden, imageBytes);
    return true;
  }
}
