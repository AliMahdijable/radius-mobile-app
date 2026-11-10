// «الأمر الصوتي ٢» (١٠ نوفمبر): الأمر بالإنكليزيّة يُكتب اسمه لاتينيّاً ("activate Ali Hussein") والمشترك مسجَّلٌ بالعربيّة —
// المطابقة كلمةً كلمة بالهيكل الصوتيّ، واليوزر اللاتينيّ بكلماته. لا شبكة هنا.
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/models/network_device.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/services/voice/voice_resolver.dart';

Subscriber _s(String idx, String user, String first, String last) =>
    Subscriber.fromJson({'idx': idx, 'username': user, 'firstname': first, 'lastname': last});

NetworkDevice _d(int id, String name, String type) => NetworkDevice(
      id: id,
      adminId: '2',
      name: name,
      type: type,
      brand: 'mikrotik',
      ip: '10.0.0.$id',
      port: 8728,
      protocol: 'api',
      hasCredentials: true,
      lastStatus: 'online',
      createdAt: DateTime(2026, 11, 1),
    );

void main() {
  final subs = [
    _s('1', '07701', 'علي', 'حسين'),
    _s('2', '07702', 'علي', 'حسن'),
    _s('3', '07703', 'محمد', 'كاظم جبار'),
    _s('4', '07704', 'زينب', 'علي'),
    _s('5', '07705', 'ابو حيدر', 'الحلي'),
    _s('6', '07706', 'فاطمة', 'عبدالله'),
    _s('7', '07707', 'ليلى', 'نور'),
    _s('8', '07708', 'علا', 'هادي'),
    _s('9', 'mustafa.karim', '', ''),
  ];
  List<String> top(String q) => VoiceResolver.rank(subs, q).map((m) => m.item.username).toList();
  VoiceMatches<Subscriber> match(String q) => VoiceMatches(VoiceResolver.rank(subs, q));

  test('الاسم اللاتينيّ يطابق المسجَّل بالعربيّة كلمةً كلمة — ويُجزم بالواضح', () {
    expect(top('mohammed kadhim').first, '07703');
    expect(match('mohammed kadhim').sure, isTrue);
    expect(top('zainab ali').first, '07704');
    expect(top('abu haider').first, '07705');
    expect(top('abu haider alhilli').first, '07705', reason: 'أداة التعريف ملصوقةً باللاتينيّة');
    expect(top('abu haider al hilli').first, '07705', reason: 'وقائمةً بنفسها');
    expect(top('fatima abdullah').first, '07706', reason: 'التاء المربوطة = a، و«الله» = llah');
    expect(top('fatimah').first, '07706');
  });

  test('«hussein» يقدّم «حسين» على «حسن» (الياء الممدودة) ولا يُجزم بينهما', () {
    final m = match('ali hussein');
    expect(m.items.first.item.username, '07701');
    expect(m.items.map((x) => x.item.username), contains('07702'));
    expect(m.sure, isFalse, reason: 'حسن/حسين هيكلٌ واحد — يختار الوكيل');
    expect(top('ali hassan').take(2).toSet(), {'07701', '07702'});
  });

  test('الهيكل القصير لا يطابق كلّ شيء: «ali» ⇔ «علي» لا «ليلى» ولا «علا»', () {
    final ali = top('ali');
    expect(ali, containsAll(['07701', '07702', '07704']));
    expect(ali, isNot(contains('07707')), reason: '«ليلى» تبدأ بساكن');
    expect(ali, isNot(contains('07708')), reason: '«علا» تنتهي بألف');
    expect(top('ola hadi').first, '07708');
    expect(top('layla noor').first, '07707');
  });

  test('التقريبيّ (حرفٌ ساكن مختلف) مرشّحٌ لا جزم: «kazem» ⇔ «كاظم»', () {
    final m = match('muhammad kazem');
    expect(m.items.first.item.username, '07703');
    expect(m.sure, isFalse);
    expect(VoiceResolver.phoneticMatch('kadhim', 'كاظم'), 2);
    expect(VoiceResolver.phoneticMatch('kazem', 'كاظم'), 1);
    expect(VoiceResolver.phoneticMatch('salim', 'كاظم'), 0);
    expect(VoiceResolver.phoneticMatch('علي', 'حسين'), 0, reason: 'لغةٌ واحدة ليست من شأنه');
  });

  test('اليوزر اللاتينيّ بكلماته («mustafa karim» ⇔ mustafa.karim)، والعربيّ يطابقه بالهيكل كما كان', () {
    expect(top('mustafa karim').first, 'mustafa.karim');
    expect(match('mustafa karim').sure, isTrue);
    expect(top('mustafa').first, 'mustafa.karim');
    expect(top('مصطفى كريم').first, 'mustafa.karim');
  });

  test('الأجهزة: الاتّجاه الإنكليزيّ يطابق الاسم العربيّ، واسم المكان بالهيكل', () {
    final devs = [_d(1, 'سكتر الشمال', 'sector'), _d(2, 'راوتر الكرادة', 'router'), _d(3, 'سكتر الجنوب', 'sector')];
    expect(VoiceResolver.rankDevices(devs, 'north', kind: 'sector').first.item.id, 1);
    expect(VoiceResolver.rankDevices(devs, 'south').first.item.id, 3);
    expect(VoiceResolver.rankDevices(devs, 'karrada').first.item.id, 2);
    expect(VoiceResolver.rankDevices(devs, 'west'), isEmpty);
  });
}
