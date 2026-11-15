import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/ubnt_api.dart';

/// بلاغ المالك (١٥ نوفمبر، جهازا MASTER_ZAA2/SLAVE_ZAA2 = Ubiquiti GigaBeam LR، ٦٠ گيگا):
/// «للنك نوعه ٦ گيگا جاي ياخذ قراءات الـ٥». حين يكون الراديو الاحتياطيّ ٥ گيگا شغّالاً يملأ
/// wlanFrequency/wlanSignal (4980 MHz · -89 dBm) فيطمس تردّد الـ60 (من قسم radio) وإشارته (من المحطّة).
/// الطرف الآخر (الاحتياطيّ خامل) يقرأ الـ60 صحيحاً (62640) — فالقاعدة: جهاز ٦٠ يعرض راديو الـ60 دائماً.
void main() {
  // محطّة الطرف الآخر على الـ60 (prs_sta كما يعطيها airFiber 60): الإشارة rssi_data، SNR، السعة.
  List<Map<String, dynamic>> sta60({int rssi = -53}) => [
        {
          'mac': '00:11:22:33:44:55',
          'linked_60': true,
          'prs_sta': {
            'rssi_data': rssi,
            'snr': 18,
            'dl_capacity': 780000, // Kbps ⇒ 780 Mbps
            'ul_capacity': 866000,
            'distance': 481,
            'uptime': 5550000,
          },
        },
      ];

  group('أجهزة ٦٠ گيگا — راديو الـ60 لا الاحتياطيّ ٥', () {
    test('الماستر: الاحتياطيّ ٥ شغّال (4980/-89) ⇒ يُعرض الـ60 (62640) وإشارة المحطّة (-53)', () {
      // خريطة mca-dump مسطّحة كما يبنيها المحلّل: wlanFrequency=4980 (الاحتياطيّ ٥)،
      // radioFrequency=62640 (الـ60، محفوظٌ منفصلاً بعد الإصلاح).
      final m = {
        'platform': 'GigaBeam LR',
        'wlanEssid': '@ZAA2',
        'wlanMode': 'sta',
        'wlanSignal': '-89', // الراديو الاحتياطيّ ٥
        'wlanFrequency': '4980', // الاحتياطيّ ٥
        'radioFrequency': '62640', // الـ60 (لا يُطمس)
        'wlanNoiseFloor': '-89',
        'wlanChanWidth': '80',
        'station1_snr': '22',
      };
      final s = UbntStats.fromMcaStatus(m, wstalistStations: sta60());
      final w = s.wireless!;
      expect(w.frequency, 62640, reason: 'التردّد = راديو الـ60 لا الاحتياطيّ 4980');
      expect(w.signal, -53, reason: 'الإشارة = المحطّة على الـ60 لا -89');
      expect(s.isAirFiber60, isTrue);
      // الاحتياطيّ ٥ لا يضيع — ينزل للتفاصيل
      final backup = s.extras.where((e) => e.k.contains('الاحتياطيّ'));
      expect(backup, hasLength(1));
      expect(backup.first.v, contains('4980'));
      // لا سطر تشخيصٍ ما دام التردّد وُجد
      expect(s.extras.where((e) => e.k.contains('تشخيص')), isEmpty);
    });

    test('السلف: الاحتياطيّ ٥ خامل ⇒ الـ60 مقروءٌ أصلاً (62640) — بلا تبديل ولا «احتياطيّ»', () {
      final m = {
        'platform': 'GigaBeam LR',
        'wlanEssid': '@ZAA2',
        'wlanMode': 'ap',
        'wlanFrequency': '62640', // الـ60 مباشرةً (الاحتياطيّ خامل)
        'wlanNoiseFloor': '-88',
        'wlanChanWidth': '80',
      };
      final s = UbntStats.fromMcaStatus(m, wstalistStations: sta60(rssi: -53));
      expect(s.wireless!.frequency, 62640);
      expect(s.extras.where((e) => e.k.contains('الاحتياطيّ')), isEmpty,
          reason: 'لا تبديل حين التردّد ليس من نطاق الـ5');
    });

    test('جهاز airMAX ٥ گيگا عاديّ لا يتأثّر', () {
      final m = {
        'platform': 'NanoBeam M5',
        'wlanEssid': 'sector-1',
        'wlanMode': 'ap',
        'wlanSignal': '-60',
        'wlanFrequency': '5745',
        'wlanNoiseFloor': '-95',
        'wlanChanWidth': '40',
      };
      final s = UbntStats.fromMcaStatus(m, wstalistStations: [
        {'mac': 'AA:BB:CC:DD:EE:01', 'signal': -62, 'ccq': 95},
      ]);
      expect(s.wireless!.frequency, 5745, reason: 'لا تبديل — ليس ٦٠');
      expect(s.wireless!.signal, -60);
      expect(s.isAirFiber60, isFalse);
      expect(s.extras.where((e) => e.k.contains('الاحتياطيّ')), isEmpty);
    });

    test('جهاز ٦٠ بلا تردّد ٦٠ مكشوف ⇒ «—» لا 4980، وسطر تشخيصٍ مؤقّت', () {
      final m = {
        'platform': 'GigaBeam LR',
        'wlanEssid': '@ZAA2',
        'wlanMode': 'sta',
        'wlanSignal': '-89',
        'wlanFrequency': '4980', // الاحتياطيّ ٥ فقط — لا مصدر ٦٠
      };
      final s = UbntStats.fromMcaStatus(m, wstalistStations: sta60());
      expect(s.wireless!.frequency, 0, reason: '«—» لا 4980 الاحتياطيّ');
      expect(s.wireless!.signal, -53, reason: 'الإشارة من المحطّة تبقى صحيحة');
      expect(s.extras.where((e) => e.k.contains('تشخيص')), hasLength(1));
    });
  });
}
