import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../core/util/error_text.dart';
import '../services/auth_storage.dart';
import '../services/provider_service.dart';
import 'api_client.dart';

/// «المشروع الوطني» داخل ساسات الوطني (١٩ نوفمبر — البصرة/الناصريّة؛ المالك: «واتاكد كلشي موجود بلصفحه انضاف» ثمّ «الموظف
/// حاليا حال العدنا»): ساس الوطني يحمل أقساماً من إضافته — التذاكر، الطلبات، عروض الاشتراك، تفاصيل الاشتراك — صفحاتٍ يرسمها الساس
/// نفسه. خادمنا يقرأ أيّها في قائمة ساس المدير وبصلاحيّاته ([SasFtthApi.sections] ⇐ `GET /api/v2/sas-ftth/sections`)، ويصدر لكلّ
/// قسمٍ نافذةً لساعتين ([SasFtthApi.frame] ⇐ `POST /api/v2/sas-ftth/frame`) تُفتح في التطبيق على غلاف الخادم ([sasFtthWrapUri] ⇐
/// `/sas-ftth/f/<id>/wrap?to=…`): صفحات الإضافة ترفض الفتح المباشر خارج إطار، والغلاف إطارٌ معزول. توكن الساس لا يصل الهاتف أبداً
/// (المعرّف في المسار — الخادم 87a6cd6، a08b7ff). ساسٌ بلا الإضافة ⇒ لا أقسام ⇒ لا بطاقة. الموظّف: «عرض المشتركين» يفتحها، والكتابة
/// داخلها بصلاحيّتها (الخادم يحكم)؛ بلا «عرض المشتركين» يرى البطاقة بمكانها مقفلة.

String? _str(Object? v) {
  final s = v?.toString().trim();
  return (s == null || s.isEmpty || s == 'null') ? null : s;
}

Map<String, dynamic> _map(Object? v) => v is Map ? Map<String, dynamic>.from(v) : const <String, dynamic>{};

void _log(String what, Object e) {
  if (kDebugMode) debugPrint('🔴 [SasFtth] $what: ${e.runtimeType}');
}

@immutable
class SasFtthSection {
  const SasFtthSection({required this.key, required this.title});

  /// tickets · requests · offers · subscription_details
  final String key;
  final String title;
}

/// أقسام الشركة وما يستطيعه الفاعل داخلها.
@immutable
class SasFtthProbe {
  const SasFtthProbe({required this.sections, this.canView = true, this.canEdit = true, this.canAdd = true});

  final List<SasFtthSection> sections;
  final bool canView;
  final bool canEdit;
  final bool canAdd;

  static const off = SasFtthProbe(sections: []);

  bool get shown => sections.isNotEmpty;

  factory SasFtthProbe.fromJson(Map<String, dynamic> j) {
    final d = _map(j['data']);
    final can = _map(d['can']);
    final list = d['sections'] is List ? d['sections'] as List : const [];
    return SasFtthProbe(
      sections: [
        for (final s in list)
          if (s is Map && _str(s['key']) != null && _str(s['title']) != null)
            SasFtthSection(key: _str(s['key'])!, title: _str(s['title'])!),
      ],
      canView: can['view'] != false,
      canEdit: can['edit'] != false,
      canAdd: can['add'] != false,
    );
  }

  /// ما يُقال للموظّف الذي يتصفّح بلا صلاحيّة الكتابة (null للمدير أو لمن يملكهما) — كالموقع.
  String? get note {
    if (!canEdit && !canAdd) {
      return 'تصفّحٌ فقط: فتح تذكرة وتعديل الجهاز يحتاجان «تعديل المشترك»، وطلب زبونٍ جديد أو اشتراكٍ يحتاج «إضافة مشترك».';
    }
    if (!canEdit) return 'فتح تذكرة وتعديل الجهاز يحتاجان صلاحيّة «تعديل المشترك».';
    if (!canAdd) return 'طلب زبونٍ جديد أو اشتراكٍ يحتاج صلاحيّة «إضافة مشترك».';
    return null;
  }
}

/// نافذة قسم: مسارٌ من جذر الخادم (`/sas-ftth/f/<id>/admin/api/index.php/api/ftth/page/<page>?…`).
typedef SasFtthFrameResult = ({String? url, String? message, String? code});

/// رابط الغلاف المطلق لمسار نافذة (صفحات الإضافة ترفض الفتح خارج إطار) — null لمسارٍ ليس من الممرّ.
Uri? sasFtthWrapUri(String frameUrl, {String base = ApiClient.baseUrl}) {
  final m = RegExp(r'^(/sas-ftth/f/[0-9a-f]{32})(/admin/api/index\.php/api/ftth/page/[A-Za-z0-9_-]{1,40}(?:\?[A-Za-z0-9_\-.=&%~+]*)?)$')
      .firstMatch(frameUrl);
  if (m == null) return null;
  final origin = Uri.parse(base);
  return origin.replace(path: '${m.group(1)}/wrap', queryParameters: {'to': m.group(2)!});
}

class SasFtthApi {
  SasFtthApi._();

  static const _base = '/api/v2/sas-ftth';

  /// الأقسام — null حين تعذّر السؤال (شبكة/خادم)، و[SasFtthProbe.off] حين يرفض الخادم بكلامه (ساسٌ بلا الإضافة يأتي أقساماً فارغة).
  static Future<SasFtthProbe?> sections() async {
    String? token;
    try {
      token = await AuthStorage.readToken();
    } catch (_) {
      token = null;
    }
    if (token == null || token.isEmpty) return null;
    try {
      final r = await ApiClient.dio.get<Object?>('$_base/sections');
      return SasFtthProbe.fromJson(_map(r.data));
    } catch (e) {
      _log('sections', e);
      if (e is DioException && e.response?.data is Map) return SasFtthProbe.off;
      return null;
    }
  }

  /// نافذةٌ جديدة لقسم — رسالة الخادم بالعربيّة حين يرفض (انتهت جلسة الساس، القسم غير متاح…).
  static Future<SasFtthFrameResult> frame(String section) async {
    try {
      final r = await ApiClient.dio.post<Object?>('$_base/frame', data: {'section': section});
      final d = _map(_map(r.data)['data']);
      final url = _str(d['url']);
      if (url == null || !url.startsWith('/sas-ftth/f/')) {
        return (url: null, message: 'تعذّر فتح القسم — حاول مرّةً أخرى', code: 'BAD_FRAME');
      }
      return (url: url, message: null, code: null);
    } catch (e) {
      _log('frame', e);
      final body = e is DioException && e.response?.data is Map ? _map(e.response!.data) : const <String, dynamic>{};
      final msg = _str(body['message']);
      return (
        url: null,
        message: msg != null && RegExp(r'[\u0600-\u06FF]').hasMatch(msg)
            ? msg
            : humanError(e, fallback: 'تعذّر فتح القسم — تحقّق من الاتّصال وحاول مرّةً أخرى'),
        code: _str(body['code']),
      );
    }
  }
}

/// حال الأقسام للقائمة («قوائم أخرى» والحاسبة) — سؤالٌ كسول بالاستماع، يُخبَّأ ١٠ دقائق، ولا سؤال لغير ساس فور.
class SasFtthState {
  SasFtthState._();

  static final ValueNotifier<SasFtthProbe?> gate = _SasFtthGate();

  static int _epoch = 0;
  static DateTime? _fetchedAt;
  static DateTime? _failedAt;
  static Future<void>? _inflight;

  static const ttl = Duration(minutes: 10);
  static const _cooldown = Duration(seconds: 30);

  /// ساس فور وحده قد يحمل الإضافة (لا ايرث لنك ولا الوطنيّ القديم ولا فايبر اكس ولا الشركات المُضافة).
  static bool get _eligible =>
      ProviderService.isLoaded && !ProviderService.isEarthlink && !ProviderService.isFtth && !ProviderService.isFiberx && !ProviderService.isKit;

  static bool get visible => _eligible && (gate.value?.shown ?? false);

  static Future<void> ensureFresh({bool force = false}) {
    if (!_eligible) return Future<void>.value();
    final running = _inflight;
    if (running != null) return running;
    if (!force) {
      final now = DateTime.now();
      final at = _fetchedAt;
      if (at != null && now.difference(at) < ttl) return Future<void>.value();
      final failed = _failedAt;
      if (failed != null && now.difference(failed) < _cooldown) return Future<void>.value();
    }
    final epoch = _epoch;
    late final Future<void> run;
    run = SasFtthApi.sections().then((p) {
      if (epoch != _epoch) return;
      if (p == null) {
        _failedAt = DateTime.now();
        return;
      }
      _fetchedAt = DateTime.now();
      _failedAt = null;
      gate.value = p;
    }).whenComplete(() {
      if (identical(_inflight, run)) _inflight = null;
    });
    _inflight = run;
    return run;
  }

  /// تبديل الجلسة: لا يرى المدير التالي أقسام سابقه.
  static void reset() {
    _epoch++;
    _fetchedAt = null;
    _failedAt = null;
    _inflight = null;
    gate.value = null;
  }

  @visibleForTesting
  static void debugSet(SasFtthProbe? p) {
    _epoch++;
    _inflight = null;
    _failedAt = null;
    _fetchedAt = p == null ? null : DateTime.now();
    gate.value = p;
  }
}

class _SasFtthGate extends ValueNotifier<SasFtthProbe?> {
  _SasFtthGate() : super(null);

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    scheduleMicrotask(SasFtthState.ensureFresh);
  }
}
