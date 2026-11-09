import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/services/auth_storage.dart';
import 'package:rad_mysvcs/services/merged_mode.dart';
import 'package:rad_mysvcs/services/voice/voice_resolver.dart';

import 'emp_merged/emp_merged_fixture.dart';
import 'visual_perm/visual_perm_harness.dart';

/// «افحص سكتر …» بـ«كل الصفحات» للموظّف (مراجعة 3.0.18+179): جهاز صفحته الحاليّة يُعلَّم «المفتوحة» — بمعرّف صفحته من ردّ
/// صفحاته (MergedMode.openAdminId) لا بمعرّف جلسته المحفوظ بصيغةٍ أخرى — فيُفحص من شبكته كالمعتاد (لا «عبر VPN غير مفعّل لك»)،
/// وجهاز صفحةٍ أخرى يبقى لـVPN شركته. موظّف emp_merged: صفحته ألف (2251) وجلسته supernet:12.
void main() {
  setUpAll(visualSetUpAll);

  testWidgets('جهاز صفحته الحاليّة open=true، وجهاز صفحةٍ أخرى open=false', (t) async {
    await empUp();
    VoiceResolver.mergedOn = () => true;
    addTearDown(() => VoiceResolver.mergedOn = () => MergedMode.active.value);
    await t.runAsync(() => MergedMode.load(fresh: true));
    expect(await t.runAsync(AuthStorage.readAdminId), 'supernet:12', reason: 'جلسته بصيغةٍ غير معرّف صفحته');

    final mine = (await t.runAsync(() => VoiceResolver.devices('سكتر ألف', kind: 'sector')))!;
    expect(mine.error, isNull);
    expect(mine.items.first.item.id, 501);
    final co = VoiceResolver.companyOfDevice(501);
    expect(co?.company.key, kA);
    expect(co?.open, isTrue, reason: 'صفحته الحاليّة ⇒ فحصٌ من شبكته بطريقه المعتاد');

    final other = (await t.runAsync(() => VoiceResolver.devices('برج جيم')))!;
    expect(other.items.first.item.id, 702);
    expect(VoiceResolver.companyOfDevice(702)?.company.key, kC);
    expect(VoiceResolver.companyOfDevice(702)?.open, isFalse, reason: 'صفحةٌ أخرى ⇒ عبر VPN شركتها');
    await empDown();
  });
}
