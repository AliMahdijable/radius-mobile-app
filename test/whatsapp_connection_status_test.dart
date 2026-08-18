import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/whatsapp_api.dart';

void main() {
  group('WhatsConnectionStatus', () {
    test('parses normalized message capping without duplicating a timelock',
        () {
      final status = WhatsConnectionStatus.fromJson({
        'success': true,
        'connected': true,
        'metaRestricted': true,
        'restrictionEndsAt': 1785553199,
        'messageCapping': {
          'cappingStatus': 'CAPPED',
          'totalQuota': 1000,
          'usedQuota': 1000,
          'cycleStart': 1782874800,
          'cycleEnd': 1785553199,
          'mvStatus': 'NOT_ELIGIBLE',
          'oteStatus': 'NOT_ELIGIBLE',
        },
      });

      expect(status.connected, isTrue);
      expect(status.metaRestricted, isTrue);
      expect(status.reachoutRestricted, isFalse);
      expect(status.hasSendingRestriction, isTrue);
      expect(status.messageCapping?.isCapped, isTrue);
      expect(status.messageCapping?.usedQuota, 1000);
      expect(status.messageCapping?.cycleEnd, 1785553199);
      expect(status.messageCapping?.mvStatus, 'NOT_ELIGIBLE');
    });

    test('parses nested WAHA pairing, timelock, and capping warning fields',
        () {
      final status = WhatsConnectionStatus.fromJson({
        'connected': false,
        'session': {
          'status': 'PASSKEY_REQUIRED',
          'me': {
            'reachoutTimelock': {
              'enforcementType': 'RESTRICT_ALL_COMPANIONS',
              'isActive': true,
              'timeEnforcementEnds': 1784477333,
            },
            'messageCapping': {
              'cappingStatus': 'FIRST_WARNING',
              'totalQuota': '1000',
              'usedQuota': '640',
              'cycle_end_timestamp': 1785553199000,
            },
          },
        },
      });

      expect(status.needsPairing, isTrue);
      expect(status.sessionStatus, 'PASSKEY_REQUIRED');
      expect(status.reachoutRestricted, isTrue);
      expect(status.restrictionEndsAt, 1784477333);
      expect(status.restrictionEnforcementType, 'RESTRICT_ALL_COMPANIONS');
      expect(status.messageCapping?.isWarning, isTrue);
      expect(status.messageCapping?.totalQuota, 1000);
      expect(status.messageCapping?.usedQuota, 640);
      expect(status.messageCapping?.cycleEnd, 1785553199);
    });

    test('keeps future capping warning statuses visible', () {
      final status = WhatsConnectionStatus.fromJson({
        'connected': true,
        'messageCapping': {'cappingStatus': 'FUTURE_WARNING'},
      });

      expect(status.messageCapping?.isWarning, isTrue);
      expect(status.messageCapping?.isCapped, isFalse);
      expect(status.hasSendingRestriction, isFalse);
    });
  });
}
