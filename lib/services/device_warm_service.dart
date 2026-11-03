import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../api/device_probe_api.dart';
import '../api/subscribers_api.dart';
import '../core/net/tcp_reachability.dart';
import '../screens/subscribers/widgets/device_chip_micro.dart';
import 'connection_readings_uploader.dart';
import 'provider_service.dart';

/// فحص أجهزة المشتركين بالخلفيّة من فتح البرنامج (٣ نوفمبر — المالك: «ليش مانخلي الدالة بالخلفية تشتغل بمجرد فتح البرنامج… حتى يكون
/// اسرع وتكون لها الاولية»).
///
/// * **بلا كلفةٍ على خادمنا:** القائمة نفسها التي تجلبها الرئيسيّة (كاش [SubscribersApi.loadAll] ٤٥ث)، والفحص لأجهزة شبكة الوكيل
///   مباشرةً — فبطاقات المشتركين تفتح بقراءاتها، و«تنبيه المشترك» التلقائيّ يقيس ولو لم تُفتح القائمة.
/// * **الأولويّة لما يفعله المستخدم:** يبدأ بعد [firstDelay] من الواجهة (لا يزاحم طلبات الرئيسيّة الأولى)، بعمّالٍ أقلّ
///   ([_workers]) من موجة القائمة، ويتوقّف فوراً حين تبدأ موجةٌ أماميّة ([DeviceProbeApi.foregroundWaves]) أو يذهب التطبيق للخلفيّة.
/// * **لا هدر:** خارج شبكة الوكيل (بيانات الهاتف) لا يردّ أيّ جهاز من عيّنةٍ صغيرة ⇒ لا موجة؛ وما فُحص خلال ٥ دقائق لا يُعاد
///   ([DeviceProbeApi.needsProbe])؛ والحسابات الكبيرة (≥٥٠٠٠) والشركات بلا أجهزة (الوطنيّ وفايبر اكس والمُضافة) خارجها.
/// * كلّ [interval] موجة، وكلّ [_tick] تُقاس أجهزة «تحت المراقبة» التي حان موعد تأكيدها ([ConnectionReadingsUploader.runRechecks]).
class DeviceWarmService with WidgetsBindingObserver {
  DeviceWarmService._();
  static final DeviceWarmService _i = DeviceWarmService._();

  static const firstDelay = Duration(seconds: 8);
  static const interval = Duration(minutes: 15);
  static const _tick = Duration(seconds: 30);
  static const _workers = 12;
  static const _sample = 5;

  Timer? _timer;
  Timer? _first;
  DateTime? _lastWave;
  bool _running = false;
  bool _waving = false;
  bool _resumed = true;

  /// الاختبار: لا مؤقّتات حقيقيّة.
  @visibleForTesting
  static bool debugDisabled = false;

  /// آخر موجةٍ بدأت (للاختبار والتشخيص).
  static DateTime? get lastWave => _i._lastWave;

  static void start() {
    // اختبارات الواجهة تبني الغلاف — لا مؤقّتات حقيقيّة فيها (والاختبار يستدعي [wave] مباشرةً)
    if (debugDisabled || _i._running || Platform.environment.containsKey('FLUTTER_TEST')) return;
    _i._running = true;
    WidgetsBinding.instance.addObserver(_i);
    _i._first = Timer(firstDelay, () => unawaited(_i._step()));
    _i._timer = Timer.periodic(_tick, (_) => unawaited(_i._step()));
  }

  static void stop() {
    if (!_i._running) return;
    _i._running = false;
    WidgetsBinding.instance.removeObserver(_i);
    _i._timer?.cancel();
    _i._first?.cancel();
    _i._timer = null;
    _i._first = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed = state == AppLifecycleState.resumed;
    if (_resumed) unawaited(_step());
  }

  bool get _yield => !_running || !_resumed || DeviceProbeApi.foregroundWaves > 0;

  static bool get _providerHasDevices => !ProviderService.isKit && !ProviderService.isFiberx;

  Future<void> _step() async {
    if (_yield || _waving) return;
    // ١) تحت المراقبة: من حان موعد تأكيده يُقاس وحده
    await ConnectionReadingsUploader.runRechecks();
    // ٢) الموجة الدوريّة
    final last = _lastWave;
    if (last != null && DateTime.now().difference(last) < interval) return;
    await wave();
  }

  /// موجةٌ واحدة (تُنادى من المؤقّت، أو من الاختبار).
  @visibleForTesting
  static Future<int> wave() => _i._wave();

  Future<int> _wave() async {
    if (_waving || !_providerHasDevices) return 0;
    _waving = true;
    _lastWave = DateTime.now();
    try {
      final list = await SubscribersApi.loadAll(); // null = حسابٌ كبير أو تعذّر ⇒ لا شيء
      if (list == null || list.isEmpty || _yield) return 0;
      final subs = list.where((s) => s.companyKey == null && s.username.isNotEmpty).toList();
      final targets = subs
          .map<ProbeTarget>((s) => (username: s.username, ip: (s.ipAddress ?? '').trim(), company: null))
          .where((t) => DeviceProbeApi.needsProbe(username: t.username, ip: t.ip, company: null))
          .toList();
      if (targets.isNotEmpty) {
        // خارج شبكة الوكيل لا يردّ شيء ⇒ لا موجة (عيّنةٌ من عناوين الراديوس، ١٫٢ث)
        final ips = targets.map((t) => t.ip).where((ip) => ip.isNotEmpty).toSet().take(_sample).toList();
        if (ips.isNotEmpty) {
          final ok = await Future.wait(ips.map((ip) => TcpReachability.isReachable(ip)));
          if (!ok.contains(true)) return 0;
        }
        if (_yield) return 0;
        await DeviceProbeApi.warmProbe(targets, concurrency: _workers, isCanceled: () => _yield);
        DeviceProbeBus.bump();
      }
      unawaited(ConnectionReadingsUploader.collect(subs));
      return targets.length;
    } catch (e) {
      if (!kReleaseMode) debugPrint('🔴 device warm: $e');
      return 0;
    } finally {
      _waving = false;
    }
  }

  /// للاختبار: يعيد الحالة.
  @visibleForTesting
  static void debugReset() {
    stop();
    _i._lastWave = null;
    _i._waving = false;
    _i._resumed = true;
  }
}
