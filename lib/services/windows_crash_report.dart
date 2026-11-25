import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/platform/app_platform.dart';
import 'client_diag.dart';

/// ويندوز: كراشٌ أصليّ (داخل محرّك فلاتر أو إضافةٍ أصليّة) يُغلق البرنامج قبل أن يقول شيئاً، فلا يصل الخادمَ عنه سطر
/// (المالك ٢٥ نوفمبر: «تطبيق الويندوز والمايكروسوفت … من يسوي تعديل قالب بمجرد ما يكتب اي شي يصير كراش» — وعلى ويندوز
/// حقيقيّ بالـCI لم يتكرّر: debug وprofile، تكبير ١٠٠٪ و٨٥٪، أزرار إنجليزيّة وعربيّة ويونيكود).
///
/// ويندوز نفسه يسجّله في سجلّ «Application» — الحدث 1000 «Application Error»: الوحدة ونسختها، رمز الاستثناء، الإزاحة.
/// بعد كلّ إقلاعٍ بقليل نقرأ ما استجدّ لبرنامجنا (آخر ٣ أيّام، مرّةً لكلّ حدث) ونرسله سطراً بلا هويّة
/// (ClientDiag `windows_crash`): الأسماء والأرقام وحدها — لا مسار (فيه اسم مستخدم الجهاز). ومن الإزاحة يُعرف اسم الدالّة
/// بملفّ رموز المحرّك (flutter_windows.dll.pdb لنسخة المحرّك نفسها) — بلا أن يفتح الوكيل «عارض الأحداث».
class WindowsCrashReport {
  WindowsCrashReport._();

  static const prefsKey = 'win.crash_report.last_record_v1';
  static const maxReportsPerRun = 3;
  static bool _scheduled = false;

  /// مرّةً لكلّ تشغيل، بعد [delay] — لا يمسّ الإقلاع ولا يرمي. غير ويندوز ⇒ لا شيء.
  static void schedule({Duration delay = const Duration(seconds: 20)}) {
    if (_scheduled || kIsWeb || !AppPlatform.isWindows) return;
    _scheduled = true;
    Timer(delay, () => unawaited(_run()));
  }

  static Future<void> _run() async {
    try {
      final exe = Platform.resolvedExecutable.split(RegExp(r'[\\/]')).last;
      final events = readApplicationErrors();
      final prefs = await SharedPreferences.getInstance();
      final last = prefs.getInt(prefsKey);
      final pick = pickNew(events, exe: exe, lastRecordId: last);
      for (final e in pick.toSend) {
        ClientDiag.report('windows_crash', code: e.exceptionCode, message: e.summary);
      }
      if (pick.newest != null && pick.newest != last) await prefs.setInt(prefsKey, pick.newest!);
    } catch (e) {
      if (kDebugMode) debugPrint('🟠 windows-crash-report: $e');
    }
  }

  /// ما يُرسل من [events] (الأحدث أوّلاً): أحداث برنامجنا وحده، الأحدث من [lastRecordId]، وثلاثةٌ على الأكثر.
  /// أوّل تشغيلٍ بلا [lastRecordId] يرسل آخر حدثٍ واحد فقط (لا تاريخ الجهاز كلّه)؛ و[newest] أحدث رقمٍ رآه لبرنامجنا.
  @visibleForTesting
  static ({List<WindowsCrashEvent> toSend, int? newest}) pickNew(
    List<WindowsCrashEvent> events, {
    required String exe,
    int? lastRecordId,
  }) {
    final ours = events.where((e) => e.appName.toLowerCase() == exe.toLowerCase()).toList()
      ..sort((a, b) => b.recordId.compareTo(a.recordId));
    if (ours.isEmpty) return (toSend: const <WindowsCrashEvent>[], newest: lastRecordId);
    final fresh = lastRecordId == null ? ours.take(1) : ours.where((e) => e.recordId > lastRecordId);
    return (toSend: fresh.take(maxReportsPerRun).toList(), newest: ours.first.recordId);
  }

  /// أحداث «Application Error» (1000) في آخر [maxAge] — الأحدث أوّلاً، مقروءةً XML (بيانات الحدث لا نصّه المترجَم).
  /// يرمي إن تعذّر فتح السجلّ — المستدعي يلتقطه.
  static List<WindowsCrashEvent> readApplicationErrors({Duration maxAge = const Duration(days: 3), int limit = 40}) {
    final api = _WevtApi.open();
    final query = "*[System[Provider[@Name='Application Error'] and (EventID=1000) and "
        'TimeCreated[timediff(@SystemTime) <= ${maxAge.inMilliseconds}]]]';
    final out = <WindowsCrashEvent>[];
    final path = 'Application'.toNativeUtf16();
    final q = query.toNativeUtf16();
    final handles = calloc<IntPtr>(16);
    final returned = calloc<Uint32>();
    final used = calloc<Uint32>();
    final props = calloc<Uint32>();
    var results = 0;
    try {
      results = api.query(0, path, q, _evtQueryChannelPath | _evtQueryReverseDirection);
      if (results == 0) throw StateError('EvtQuery failed');
      while (out.length < limit) {
        returned.value = 0;
        if (api.next(results, 16, handles, 1000, 0, returned) == 0) break;
        final n = returned.value;
        if (n == 0) break;
        for (var i = 0; i < n; i++) {
          final h = handles[i];
          try {
            final xml = _render(api, h, used, props);
            final e = xml == null ? null : parseEventXml(xml);
            if (e != null && out.length < limit) out.add(e);
          } finally {
            api.close(h);
          }
        }
      }
    } finally {
      if (results != 0) api.close(results);
      calloc.free(path);
      calloc.free(q);
      calloc.free(handles);
      calloc.free(returned);
      calloc.free(used);
      calloc.free(props);
    }
    return out;
  }

  static String? _render(_WevtApi api, int event, Pointer<Uint32> used, Pointer<Uint32> props) {
    used.value = 0;
    api.render(0, event, _evtRenderEventXml, 0, nullptr, used, props);
    final size = used.value;
    if (size == 0 || size > 1 << 20) return null;
    final buf = calloc<Uint8>(size + 2);
    try {
      if (api.render(0, event, _evtRenderEventXml, size, buf, used, props) == 0) return null;
      return buf.cast<Utf16>().toDartString();
    } finally {
      calloc.free(buf);
    }
  }

  static final _named = RegExp(r"<Data Name='([A-Za-z]+)'>([^<]*)</Data>");
  static final _plain = RegExp(r'<Data>([^<]*)</Data>');
  static const _order = [
    'AppName', 'AppVersion', 'AppTimeStamp', 'ModuleName', 'ModuleVersion', 'ModuleTimeStamp',
    'ExceptionCode', 'FaultingOffset', 'ProcessId', 'ProcessCreationTime', 'AppPath', 'ModulePath',
  ];

  /// حدث «Application Error» من XML ويندوز ⇒ [WindowsCrashEvent]؛ غير ذلك ⇒ null. البيانات بأسمائها (ويندوز 10/11)
  /// أو بترتيبها حين تأتي بلا أسماء (نسخٌ أقدم).
  @visibleForTesting
  static WindowsCrashEvent? parseEventXml(String xml) {
    final id = RegExp(r'<EventRecordID>(\d+)</EventRecordID>').firstMatch(xml);
    if (id == null) return null;
    final time = RegExp(r"<TimeCreated SystemTime='([^']+)'").firstMatch(xml)?.group(1) ?? '';
    final data = <String, String>{};
    for (final m in _named.allMatches(xml)) {
      data[m.group(1)!] = m.group(2)!.trim();
    }
    if (data.isEmpty) {
      final plain = _plain.allMatches(xml).map((m) => m.group(1)!.trim()).toList();
      for (var i = 0; i < plain.length && i < _order.length; i++) {
        data[_order[i]] = plain[i];
      }
    }
    final app = data['AppName'] ?? '';
    if (app.isEmpty) return null;
    String hex(String? v) {
      final s = (v ?? '').toLowerCase().replaceFirst('0x', '');
      final t = s.replaceFirst(RegExp(r'^0+(?=.)'), '');
      return t.isEmpty ? '' : '0x$t';
    }

    return WindowsCrashEvent(
      recordId: int.parse(id.group(1)!),
      time: time.length > 19 ? time.substring(0, 19) : time,
      appName: app,
      appVersion: data['AppVersion'] ?? '',
      moduleName: data['ModuleName'] ?? '',
      moduleVersion: data['ModuleVersion'] ?? '',
      exceptionCode: hex(data['ExceptionCode']),
      offset: hex(data['FaultingOffset']),
    );
  }

  @visibleForTesting
  static void resetForTest() => _scheduled = false;
}

/// حدث «Application Error» واحد — بلا مسارات (فيها اسم مستخدم الجهاز).
@immutable
class WindowsCrashEvent {
  const WindowsCrashEvent({
    required this.recordId,
    required this.time,
    required this.appName,
    required this.appVersion,
    required this.moduleName,
    required this.moduleVersion,
    required this.exceptionCode,
    required this.offset,
  });

  final int recordId;
  final String time;
  final String appName;
  final String appVersion;
  final String moduleName;
  final String moduleVersion;
  final String exceptionCode;
  final String offset;

  /// السطر المرسل (≤٣٠٠ حرف): الوحدة ونسختها والإزاحة ونسخة البرنامج والوقت (UTC).
  String get summary => 'module=$moduleName@$moduleVersion off=$offset app=$appVersion at=${time}Z';
}

const _evtQueryChannelPath = 0x1;
const _evtQueryReverseDirection = 0x200;
const _evtRenderEventXml = 1;

/// أربع دوالّ من wevtapi.dll (سجلّ أحداث ويندوز) — لا تُفتح إلّا على ويندوز.
class _WevtApi {
  _WevtApi._(DynamicLibrary lib)
      : query = lib.lookupFunction<IntPtr Function(IntPtr, Pointer<Utf16>, Pointer<Utf16>, Uint32),
            int Function(int, Pointer<Utf16>, Pointer<Utf16>, int)>('EvtQuery'),
        next = lib.lookupFunction<Int32 Function(IntPtr, Uint32, Pointer<IntPtr>, Uint32, Uint32, Pointer<Uint32>),
            int Function(int, int, Pointer<IntPtr>, int, int, Pointer<Uint32>)>('EvtNext'),
        render = lib.lookupFunction<
            Int32 Function(IntPtr, IntPtr, Uint32, Uint32, Pointer, Pointer<Uint32>, Pointer<Uint32>),
            int Function(int, int, int, int, Pointer, Pointer<Uint32>, Pointer<Uint32>)>('EvtRender'),
        close = lib.lookupFunction<Int32 Function(IntPtr), int Function(int)>('EvtClose');

  factory _WevtApi.open() => _WevtApi._(DynamicLibrary.open('wevtapi.dll'));

  final int Function(int, Pointer<Utf16>, Pointer<Utf16>, int) query;
  final int Function(int, int, Pointer<IntPtr>, int, int, Pointer<Uint32>) next;
  final int Function(int, int, int, int, Pointer, Pointer<Uint32>, Pointer<Uint32>) render;
  final int Function(int) close;
}
