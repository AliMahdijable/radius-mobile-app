import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/services/provider_service.dart';

/// «الزون» بدل «المدير» (المالك ٣١ أكتوبر: «بالويب والتطبيقات الوطني بدل المدير الحقل يصير الزون»): الوطنيّ القديم (ftth)
/// والجديد على providerKit (watani) وحدهما — تسميةٌ لا سلوك.
void main() {
  tearDown(() => ProviderService.debugSet(null));

  test('parentIsZone: الوطنيّ القديم والجديد وحدهما', () {
    for (final (p, want) in [('watani', true), ('ftth', true), ('nabd', false), ('accessgate', false), ('earthlink', false), ('fiberx', false), (null, false)]) {
      ProviderService.debugSet(p);
      expect(ProviderService.parentIsZone, want, reason: '$p');
    }
  });
}
