import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/core/net/android_ping.dart';

/// ping أندرويد يطبع خطأ «الجهاز غير قابل للوصول» من الراوتر ردّاً من الجهاز (٤ نوفمبر — المالك: «التطبيق يكذب بالقراءات»).
/// المخرجات أدناه حقيقيّة: أندرويد 12 (iputils-s20121221) على شبكة المالك — 10.70.241.10 مفصولٌ من السويج، و.11 حيّ.
const _dead3 = r'''PING 10.70.241.10 (10.70.241.10) 56(84) bytes of data.
64 bytes from 10.70.241.10: icmp_seq=0 ttl=255 time=0.000 ms
wrong data byte #16 should be 0x10 but was 0xa
#16	a 46 f1 a e0 17 22 18 26 22 98 69 0 0 0 0 b0 c2 ff ff df 48 0 0 2 4 5 a0 1 3 3 6 
#48	1 1 8 a a0 c3 cb f 
64 bytes from 10.70.241.10: icmp_seq=0 ttl=255 time=0.000 ms (DUP!)
wrong data byte #16 should be 0x10 but was 0xa
#16	a 46 f1 a e0 17 22 18 26 22 98 69 0 0 0 0 b0 c2 ff ff df 48 0 0 2 4 5 a0 1 3 3 6 
#48	1 1 8 a a0 c3 cb f 
Warning: time of day goes back (-1110222118443565625us), taking countermeasures.
Warning: time of day goes back (-1110222118443565303us), taking countermeasures.
Warning: time of day goes back (-1110222118443565266us), taking countermeasures.

--- 10.70.241.10 ping statistics ---
3 packets transmitted, 1 received, +1 duplicates, 66% packet loss, time 2021ms
rtt min/avg/max/mdev = 0.000/0.000/0.000/0.000 ms, pipe 3
''';
const _live3 = r'''PING 10.70.241.11 (10.70.241.11) 56(84) bytes of data.
64 bytes from 10.70.241.11: icmp_seq=1 ttl=255 time=4.06 ms
64 bytes from 10.70.241.11: icmp_seq=2 ttl=255 time=4.52 ms
64 bytes from 10.70.241.11: icmp_seq=3 ttl=255 time=4.70 ms

--- 10.70.241.11 ping statistics ---
3 packets transmitted, 3 received, 0% packet loss, time 2003ms
rtt min/avg/max/mdev = 4.069/4.432/4.700/0.271 ms
''';
const _noroute1 = r'''PING 10.99.99.99 (10.99.99.99) 56(84) bytes of data.
64 bytes from 10.99.99.99: icmp_seq=0 ttl=255 time=0.000 ms
wrong data byte #16 should be 0x10 but was 0xa
#16	a 46 f1 a e0 17 22 18 26 22 98 69 0 0 0 0 b0 2 ff ff d0 66 0 0 2 4 5 a0 1 3 3 6 
#48	1 1 8 a a0 c3 da b1 

--- 10.99.99.99 ping statistics ---
1 packets transmitted, 1 received, 0% packet loss, time 0ms
rtt min/avg/max/mdev = 0.000/0.000/0.000/0.000 ms, pipe 2
Warning: time of day goes back (-1110222118439645821us), taking countermeasures.
Warning: time of day goes back (-1110222118439645513us), taking countermeasures.
''';
const _dead250 = r'''PING 10.70.241.250 (10.70.241.250) 56(84) bytes of data.
64 bytes from 10.70.241.250: icmp_seq=1 ttl=255 time=9.09 ms
64 bytes from 10.70.241.250: icmp_seq=2 ttl=255 time=6.75 ms

--- 10.70.241.250 ping statistics ---
2 packets transmitted, 2 received, 0% packet loss, time 1002ms
rtt min/avg/max/mdev = 6.751/7.925/9.099/1.174 ms
''';

void main() {
  test('مفصولٌ خلف راوتر: «ردٌّ» بزمن 0.000 يليه «wrong data byte» ومكرّر — ليس ردّاً', () {
    expect(AndroidPing.validTimes(_dead3, '10.70.241.10', maxMs: 2000), isEmpty);
    expect(AndroidPing.validTimes(_noroute1, '10.99.99.99', maxMs: 2000), isEmpty, reason: 'عنوانٌ لا وجود له «يردّ» بلا الإصلاح');
  });

  test('حيّ: كلّ ردٍّ بزمنه (مدوَّراً)', () {
    expect(AndroidPing.validTimes(_live3, '10.70.241.11', maxMs: 2000), [4, 5, 5]);
    expect(AndroidPing.validTimes(_dead250, '10.70.241.250', maxMs: 2000), [9, 7]);
  });

  test('ردٌّ من عنوانٍ آخر، أو بزمنٍ أطول من المهلة، أو مكرّر، أو بالاسم (اسم (عنوان)) — قواعدٌ لكلّ لهجة', () {
    const other = '64 bytes from 10.70.241.1: icmp_seq=1 ttl=64 time=1.20 ms';
    expect(AndroidPing.validTimes(other, '10.70.241.10', maxMs: 2000), isEmpty);
    const huge = '64 bytes from 10.70.241.10: icmp_seq=1 ttl=64 time=987654.321 ms';
    expect(AndroidPing.validTimes(huge, '10.70.241.10', maxMs: 2000), isEmpty, reason: 'طابعٌ زمنيّ من بايتاتٍ خاطئة');
    const dup = '64 bytes from 10.70.241.10: icmp_seq=1 ttl=64 time=3.10 ms (DUP!)';
    expect(AndroidPing.validTimes(dup, '10.70.241.10', maxMs: 2000), isEmpty);
    const named = '64 bytes from router.lan (10.70.241.10): icmp_seq=1 ttl=64 time=2.40 ms';
    expect(AndroidPing.validTimes(named, '10.70.241.10', maxMs: 2000), [2]);
    const sub = '64 bytes from 10.70.241.10: icmp_seq=1 ttl=64 time=0.043 ms';
    expect(AndroidPing.validTimes(sub, '10.70.241.10', maxMs: 2000), [0], reason: 'ردٌّ حقيقيّ دون الملّي ثانية يبقى ردّاً');
    expect(AndroidPing.validTimes('', '10.70.241.10', maxMs: 2000), isEmpty);
  });

  test('ping: المخرَج المحقون ⇒ الأزمنة الصحيحة؛ رمي الأمر ⇒ لا ردّ', () async {
    final keep = AndroidPing.runner;
    try {
      AndroidPing.runner = (ip, count, timeout) async => _dead3;
      expect(await AndroidPing.ping('10.70.241.10', count: 3), isEmpty);
      AndroidPing.runner = (ip, count, timeout) async => _live3;
      expect(await AndroidPing.ping('10.70.241.11', count: 3), [4, 5, 5]);
      AndroidPing.runner = (ip, count, timeout) async => throw Exception('no ping binary');
      expect(await AndroidPing.ping('10.70.241.11'), isEmpty);
    } finally {
      AndroidPing.runner = keep;
    }
  });
}
