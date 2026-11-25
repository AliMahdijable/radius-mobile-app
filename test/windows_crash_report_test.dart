import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/services/windows_crash_report.dart';

/// كراش ويندوز الأصليّ (٢٥ نوفمبر — «من يسوي تعديل قالب بمجرد ما يكتب اي شي يصير كراش»): نقرأ حدث «Application Error»
/// الذي يسجّله ويندوز ونرسل الوحدة والرمز والإزاحة وحدها — لا مسار (فيه اسم مستخدم الجهاز)، ومرّةً لكلّ حدث.
void main() {
  const named = '''
<Event xmlns='http://schemas.microsoft.com/win/2004/08/events/event'><System><Provider Name='Application Error'/>
<EventID Qualifiers='0'>1000</EventID><TimeCreated SystemTime='2026-11-25T09:46:20.1234567Z'/><EventRecordID>48213</EventRecordID>
<Channel>Application</Channel><Computer>DESKTOP-AGENT</Computer></System><EventData>
<Data Name='AppName'>MyServicesPro.exe</Data><Data Name='AppVersion'>3.0.195.0</Data><Data Name='AppTimeStamp'>6a1b2c3d</Data>
<Data Name='ModuleName'>flutter_windows.dll</Data><Data Name='ModuleVersion'>0.0.0.0</Data><Data Name='ModuleTimeStamp'>6a000000</Data>
<Data Name='ExceptionCode'>c0000409</Data><Data Name='FaultingOffset'>00000000004d5e6f</Data><Data Name='ProcessId'>0x1a2b</Data>
<Data Name='ProcessCreationTime'>0x1dc5e</Data><Data Name='AppPath'>C:\\Users\\Haider\\AppData\\Local\\MyServicesPro\\MyServicesPro.exe</Data>
<Data Name='ModulePath'>C:\\Users\\Haider\\AppData\\Local\\MyServicesPro\\flutter_windows.dll</Data></EventData></Event>''';

  test('XML بأسماء البيانات ⇒ الوحدة والرمز والإزاحة والنسخة والوقت — بلا مسار ولا اسم مستخدم', () {
    final e = WindowsCrashReport.parseEventXml(named)!;
    expect(e.recordId, 48213);
    expect(e.appName, 'MyServicesPro.exe');
    expect(e.moduleName, 'flutter_windows.dll');
    expect(e.exceptionCode, '0xc0000409');
    expect(e.offset, '0x4d5e6f');
    expect(e.summary, 'module=flutter_windows.dll@0.0.0.0 off=0x4d5e6f app=3.0.195.0 at=2026-11-25T09:46:20Z');
    expect(e.summary.contains('Haider'), isFalse);
    expect(e.summary.contains(r'C:\'), isFalse);
    expect(e.summary.length <= 300, isTrue);
  });

  test('XML بلا أسماء (ويندوز أقدم) ⇒ بالترتيب؛ وحدثٌ بلا رقمٍ أو بلا برنامج ⇒ null', () {
    const plain = '''<Event><System><TimeCreated SystemTime='2026-11-24T10:00:00.0Z'/><EventRecordID>7</EventRecordID></System>
<EventData><Data>MyServicesPro.exe</Data><Data>3.0.194.0</Data><Data>x</Data><Data>ucrtbase.dll</Data><Data>10.0.1</Data>
<Data>y</Data><Data>c0000005</Data><Data>0000000000001234</Data></EventData></Event>''';
    final e = WindowsCrashReport.parseEventXml(plain)!;
    expect(e.moduleName, 'ucrtbase.dll');
    expect(e.exceptionCode, '0xc0000005');
    expect(e.offset, '0x1234');
    expect(WindowsCrashReport.parseEventXml('<Event><EventData></EventData></Event>'), isNull);
    expect(WindowsCrashReport.parseEventXml("<Event><EventRecordID>9</EventRecordID></Event>"), isNull);
  });

  WindowsCrashEvent ev(int id, [String app = 'MyServicesPro.exe']) => WindowsCrashEvent(
        recordId: id,
        time: '2026-11-25T09:00:00',
        appName: app,
        appVersion: '3.0.195.0',
        moduleName: 'flutter_windows.dll',
        moduleVersion: '0.0.0.0',
        exceptionCode: '0xc0000409',
        offset: '0x10',
      );

  test('مرّةً لكلّ حدث: أوّل تشغيلٍ يرسل الأحدث وحده؛ بعده الأحدث من آخر ما أُرسل؛ ثلاثةٌ على الأكثر؛ برنامجنا وحده', () {
    final events = [ev(5), ev(9), ev(7, 'chrome.exe'), ev(3), ev(12), ev(11), ev(10)];
    final first = WindowsCrashReport.pickNew(events, exe: 'myservicespro.EXE');
    expect(first.toSend.map((e) => e.recordId), [12]);
    expect(first.newest, 12);
    final next = WindowsCrashReport.pickNew(events, exe: 'MyServicesPro.exe', lastRecordId: 5);
    expect(next.toSend.map((e) => e.recordId), [12, 11, 10], reason: 'ثلاثةٌ على الأكثر، الأحدث أوّلاً');
    final none = WindowsCrashReport.pickNew(events, exe: 'MyServicesPro.exe', lastRecordId: 12);
    expect(none.toSend, isEmpty);
    expect(none.newest, 12);
    final other = WindowsCrashReport.pickNew([ev(4, 'chrome.exe')], exe: 'MyServicesPro.exe', lastRecordId: 2);
    expect(other.toSend, isEmpty);
    expect(other.newest, 2);
  });

  test('غير ويندوز ⇒ لا جدولة ولا قراءة (الماك والاختبار)', () {
    WindowsCrashReport.resetForTest();
    WindowsCrashReport.schedule(delay: Duration.zero);
    // على غير ويندوز لا شيء يُجدول — لا استثناء ولا مؤقّت معلّق
    WindowsCrashReport.resetForTest();
  });
}
