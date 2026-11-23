import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/gdrive_backup_api.dart';
import '../../core/util/bidi.dart';
import '../../core/widgets/app_sheet.dart';
import '../../core/widgets/design_sheet.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';

/// «النسخ الاحتياطيّ إلى Google Drive» (٢٣ نوفمبر — المالك: «ميزه لكل وكيل يربط حساب كوكل درايف مالته للنسخ التلقائي للديون…»،
/// ثمّ «خليها اسهل لان الوكلاء اغلبهم صعب يعرفون هجي ربط»). نظير صفحة الموقع (/v2/backup):
///
/// • قبل الربط: زرٌّ واحد «ربط Google Drive» وثلاث خطوات (اضغط ⇒ اختر إيميلك ⇒ «Allow»). تُفتح صفحة Google داخل التطبيق (Safari/
///   Custom Tab — Google ترفض الموافقة داخل WebView)، والشاشة تسأل الخادم كلّ ثانيتين: حين يتمّ الربط تُغلق الصفحة وحدها (آيفون)
///   وتظهر «تمّ ✓»؛ وعلى أندرويد يكفي ✕ — والرجوع للتطبيق يحدّث الحال أيضاً.
/// • بعد الربط: «مربوط بـ…»، آخر نسخة، «فتح المجلّد في Drive»، «انسخ الآن»؛ ثمّ الموعد («كلّ يوم الساعة 03:00» — تغييره في نافذة)
///   وإلغاء الربط بتأكيد، وآخر النسخ. أوّل نسخةٍ يحفظها الخادم لحظة الربط بلا ضبط شيء.
/// • لمدير الصفحة وحده: الموظّف يرى القسم مقفلاً (الخادم 403 MANAGER_ONLY).
class DriveBackupScreen extends StatefulWidget {
  const DriveBackupScreen({super.key});

  /// يفتح رابطاً (صفحة Google / المجلّد / الملفّ) — بديلٌ للاختبار.
  @visibleForTesting
  static Future<bool> Function(Uri url, {bool inApp}) launcher = _defaultLaunch;

  /// يغلق صفحة Google المفتوحة داخل التطبيق (آيفون) — بديلٌ للاختبار.
  @visibleForTesting
  static Future<void> Function() closeBrowser = _defaultClose;

  /// الساعة — بديلٌ للاختبار.
  @visibleForTesting
  static int Function() now = () => DateTime.now().millisecondsSinceEpoch;

  /// فواصل السؤال — قصيرةٌ في الاختبار.
  @visibleForTesting
  static Duration linkPoll = const Duration(seconds: 2);
  @visibleForTesting
  static Duration jobPoll = const Duration(seconds: 3);

  static Future<bool> _defaultLaunch(Uri url, {bool inApp = false}) async {
    var ok = false;
    if (inApp) {
      try {
        ok = await launchUrl(url, mode: LaunchMode.inAppBrowserView);
      } catch (_) {/* الخارجيّ */}
    }
    if (!ok) {
      try {
        ok = await launchUrl(url, mode: LaunchMode.externalApplication);
      } catch (_) {/* يُقال أدناه */}
    }
    return ok;
  }

  static Future<void> _defaultClose() async {
    try {
      if (await supportsCloseForLaunchMode(LaunchMode.inAppBrowserView)) await closeInAppWebView();
    } catch (_) {/* لا يُغلق ⇒ يغلقه الوكيل */}
  }

  @override
  State<DriveBackupScreen> createState() => _DriveBackupScreenState();
}

class _DriveBackupScreenState extends State<DriveBackupScreen> with WidgetsBindingObserver {
  GdbStatus? _st;
  String? _error;
  String? _errorCode;
  bool _loading = true;
  String? _busy; // connect · run · schedule · unlink
  int? _waitingSince; // ننتظر موافقة Google منذ
  Timer? _timer;

  static const _waitMax = Duration(minutes: 10);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // رجع من صفحة Google أو من درايف ⇒ الحال الآن
    if (state == AppLifecycleState.resumed && mounted) unawaited(_load(quiet: true));
  }

  Future<void> _load({bool quiet = false}) async {
    if (!quiet) setState(() => _loading = _st == null);
    final r = await GdriveBackupApi.status();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r.data != null) {
        _st = r.data;
        _error = null;
        _errorCode = null;
      } else if (_st == null) {
        _error = r.message ?? 'تعذّرت قراءة حال النسخ الآن';
        _errorCode = r.code;
      }
    });
    _afterStatus();
  }

  /// بعد كلّ قراءة: هل تمّ الربط الذي ننتظره؟ وهل نسأل ثانيةً (ربطٌ منتظر أو نسخةٌ جارية)؟
  void _afterStatus() {
    final st = _st;
    final since = _waitingSince;
    if (since != null && st != null) {
      final l = st.link;
      final done = l != null && !l.broken && (l.linkedAt ?? 0) >= since - 60000;
      if (done) {
        _waitingSince = null;
        unawaited(DriveBackupScreen.closeBrowser());
        _snack('تمّ ربط Google Drive ✓ — أوّل نسخة تُحفظ الآن');
      } else if (DriveBackupScreen.now() - since > _waitMax.inMilliseconds) {
        setState(() => _waitingSince = null);
      }
    }
    _timer?.cancel();
    final every = _waitingSince != null ? DriveBackupScreen.linkPoll : (st != null && st.working ? DriveBackupScreen.jobPoll : null);
    if (every != null) _timer = Timer(every, () => unawaited(_load(quiet: true)));
  }

  void _snack(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: error ? AppColors.errorFill : null,
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _connect() async {
    if (_busy != null) return;
    setState(() => _busy = 'connect');
    final r = await GdriveBackupApi.connect();
    if (!mounted) return;
    if (r.url == null) {
      setState(() => _busy = null);
      _snack(r.message ?? 'تعذّر بدء الربط — أعد المحاولة', error: true);
      return;
    }
    final ok = await DriveBackupScreen.launcher(Uri.parse(r.url!), inApp: true);
    if (!mounted) return;
    setState(() {
      _busy = null;
      if (ok) _waitingSince = DriveBackupScreen.now();
    });
    if (!ok) {
      _snack('تعذّر فتح صفحة Google — تأكّد من الإنترنت وأعد المحاولة', error: true);
      return;
    }
    _afterStatus();
  }

  Future<void> _write(String kind, Future<GdbResult> Function() send, {String? okText}) async {
    if (_busy != null) return;
    setState(() => _busy = kind);
    final r = await send();
    if (!mounted) return;
    setState(() {
      _busy = null;
      if (r.data != null) _st = r.data;
    });
    if (r.data != null) {
      if (okText != null) _snack(okText);
      _afterStatus();
    } else {
      _snack(r.message ?? 'تعذّر الآن — أعد المحاولة', error: true);
    }
  }

  Future<void> _open(String? url) async {
    if (url == null) return;
    final ok = await DriveBackupScreen.launcher(Uri.parse(url));
    if (!ok) _snack('تعذّر فتح الرابط', error: true);
  }

  Future<void> _editSchedule() async {
    final st = _st;
    if (st == null) return;
    final next = await showAppSheet<GdbSchedule>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: AppColors.scrim,
      builder: (_) => _ScheduleSheet(initial: st.schedule),
    );
    if (next == null || !mounted || next == st.schedule) return;
    await _write('schedule', () => GdriveBackupApi.saveSchedule(next), okText: 'تم الحفظ');
  }

  Future<void> _unlink() async {
    final yes = await showConfirmSheet(
      context,
      title: 'إلغاء ربط Google Drive؟',
      message: 'تتوقّف النسخ التلقائيّة، والملفّات الموجودة في درايفك تبقى كما هي. تستطيع الربط من جديد متى شئت.',
      confirmLabel: 'إلغاء الربط',
      cancelLabel: 'تراجع',
      icon: LucideIcons.unlink,
      tone: AppTone.danger,
    );
    if (yes != true || !mounted) return;
    await _write('unlink', GdriveBackupApi.unlink, okText: 'أُلغي الربط — الملفّات الموجودة في درايفك تبقى');
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('النسخ الاحتياطيّ')),
      body: RefreshIndicator(
        onRefresh: () => _load(quiet: true),
        child: ListView(
          key: const ValueKey('gdb-list'),
          padding: const EdgeInsets.all(Sp.lg),
          children: _body(),
        ),
      ),
    );
  }

  List<Widget> _body() {
    if (_loading) {
      return const [
        SizedBox(height: Sp.huge),
        Center(child: CircularProgressIndicator()),
      ];
    }
    final st = _st;
    if (st == null) {
      if (_errorCode == 'MANAGER_ONLY') {
        return [const _InfoCard(icon: LucideIcons.lock, text: 'لمدير الصفحة — يربط درايفه ويحدّد موعد النسخ')];
      }
      if (_errorCode == 'FEATURE_OFF') {
        return [const _InfoCard(icon: LucideIcons.info, text: 'النسخ الاحتياطيّ غير مفعّل لصفحتك بعد')];
      }
      return [
        _InfoCard(icon: LucideIcons.triangleAlert, text: _error ?? 'تعذّرت قراءة حال النسخ الآن'),
        const SizedBox(height: Sp.md),
        OutlinedButton(onPressed: () => unawaited(_load()), child: const Text('أعد المحاولة')),
      ];
    }
    if (!st.configured) {
      return [const _InfoCard(icon: LucideIcons.clock, text: 'الخدمة قيد التجهيز من جهتنا — تظهر هنا قريباً.')];
    }
    if (!st.linked) {
      return [
        _ConnectCard(busy: _busy == 'connect', waiting: _waitingSince != null, onConnect: _connect),
      ];
    }
    final now = DriveBackupScreen.now();
    return [
      _StatusCard(
        st: st,
        now: now,
        busy: _busy,
        waiting: _waitingSince != null,
        onConnect: _connect,
        onRunNow: () => _write('run', GdriveBackupApi.runNow, okText: 'بدأ حفظ نسخة الآن'),
        onOpenFolder: () => _open(st.link?.folderUrl),
      ),
      const SizedBox(height: Sp.md),
      _ScheduleCard(st: st, onEdit: _editSchedule, onUnlink: _unlink),
      if (st.runs.isNotEmpty) ...[
        const SizedBox(height: Sp.md),
        _RunsCard(runs: st.runs, now: now, onOpen: _open),
      ],
      const SizedBox(height: Sp.xl),
    ];
  }
}

BoxDecoration _cardDeco() => BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(R.card),
      border: Border.all(color: AppColors.border),
    );

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      decoration: _cardDeco(),
      padding: const EdgeInsets.all(Sp.lg),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 20, color: AppColors.textMid),
        const SizedBox(width: Sp.md),
        Expanded(child: Text(text, style: AppType.body(color: AppColors.textBody))),
      ]),
    );
  }
}

class _ConnectCard extends StatelessWidget {
  const _ConnectCard({required this.busy, required this.waiting, required this.onConnect});
  final bool busy;
  final bool waiting;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      key: const ValueKey('gdb-connect-card'),
      decoration: _cardDeco(),
      padding: const EdgeInsets.all(Sp.lg),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: AppColors.brandSoftBg, borderRadius: BorderRadius.circular(R.md)),
            child: Icon(LucideIcons.hardDriveUpload, color: AppColors.brand, size: 22),
          ),
          const SizedBox(width: Sp.md),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('نسخة من ديونك ومشتركيك في Google Drive', style: AppType.subtitle(color: AppColors.textHi)),
              const SizedBox(height: Sp.xs),
              Text('ملفّ إكسل يُحفظ تلقائيّاً كلّ يوم في درايفك — تفتحه من أيّ مكانٍ وأيّ وقت، حتى لو صار شي.',
                  style: AppType.muted(color: AppColors.textMid)),
            ]),
          ),
        ]),
        const SizedBox(height: Sp.lg),
        for (var i = 0; i < gdbSteps.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: Sp.sm),
            child: Row(children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: AppColors.brand, shape: BoxShape.circle),
                child: Text('${i + 1}', style: AppType.label(color: AppColors.onBrand)),
              ),
              const SizedBox(width: Sp.md),
              Expanded(
                child: Text(gdbSteps[i],
                    maxLines: 3, overflow: TextOverflow.ellipsis, style: AppType.body(color: AppColors.textBody)),
              ),
            ]),
          ),
        const SizedBox(height: Sp.md),
        if (waiting)
          const _WaitingLine()
        else
          SizedBox(
            height: H.button,
            child: FilledButton.icon(
              key: const ValueKey('gdb-connect'),
              onPressed: busy ? null : onConnect,
              icon: busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(LucideIcons.hardDriveUpload, size: 18),
              label: const Text('ربط Google Drive'),
            ),
          ),
        const SizedBox(height: Sp.md),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(LucideIcons.shieldCheck, size: 14, color: AppColors.textLow),
          const SizedBox(width: Sp.xs),
          Expanded(
            child: Text('نكتب ملفّات النسخ وحدها في درايفك، ولا نرى أيّ ملفٍّ آخر فيه.',
                style: AppType.muted(color: AppColors.textLow)),
          ),
        ]),
      ]),
    );
  }
}

/// بانتظار موافقة Google: تُغلق الصفحة وحدها حين يتمّ الربط (آيفون)، أو ✕ ثمّ هنا.
class _WaitingLine extends StatelessWidget {
  const _WaitingLine();

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      key: const ValueKey('gdb-waiting'),
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(color: AppColors.brandSoftBg, borderRadius: BorderRadius.circular(R.md)),
      child: Row(children: [
        const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
        const SizedBox(width: Sp.md),
        Expanded(
          child: Text('بانتظار موافقتك في صفحة Google… بعد «Allow» ارجع هنا (✕ أعلى الصفحة).',
              style: AppType.body(color: AppColors.brandOnSoft)),
        ),
      ]),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.st,
    required this.now,
    required this.busy,
    required this.waiting,
    required this.onConnect,
    required this.onRunNow,
    required this.onOpenFolder,
  });
  final GdbStatus st;
  final int now;
  final String? busy;
  final bool waiting;
  final VoidCallback onConnect;
  final VoidCallback onRunNow;
  final VoidCallback onOpenFolder;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final link = st.link!;
    final last = st.lastOk;
    return Container(
      key: const ValueKey('gdb-status'),
      decoration: _cardDeco(),
      padding: const EdgeInsets.all(Sp.lg),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (link.broken) ...[
          Container(
            padding: const EdgeInsets.all(Sp.md),
            decoration: BoxDecoration(color: AppColors.dangerSoftBg, borderRadius: BorderRadius.circular(R.md)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(LucideIcons.triangleAlert, size: 18, color: AppColors.error),
              const SizedBox(width: Sp.sm),
              Expanded(
                child: Text(link.brokenMessage ?? 'انقطع ربط Google Drive', style: AppType.body(color: AppColors.dangerOnSoft)),
              ),
            ]),
          ),
          const SizedBox(height: Sp.md),
          if (waiting)
            const _WaitingLine()
          else
            SizedBox(
              height: H.button,
              child: FilledButton(
                key: const ValueKey('gdb-reconnect'),
                onPressed: busy == null ? onConnect : null,
                child: const Text('أعد الربط'),
              ),
            ),
        ] else
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(LucideIcons.circleCheck, size: 18, color: AppColors.success),
            const SizedBox(width: Sp.sm),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('مربوط بحساب Google', style: AppType.bodyStrong(color: AppColors.success)),
                // الإيميل بسطره (لا يُقطع بين «بـ» وآخره) وبعزلٍ اتّجاهيّ — لا ينقلب بين العربيّ
                if (link.email != null) Text(iso(link.email!), style: AppType.bodyStrong(color: AppColors.textHi)),
              ]),
            ),
          ]),
        const SizedBox(height: Sp.md),
        if (st.working)
          Row(key: const ValueKey('gdb-job'), children: [
            const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: Sp.sm),
            Expanded(
              child: Text(st.jobState == 'running' ? 'جارٍ حفظ نسخة الآن…' : 'نسخةٌ بالدور — تبدأ بعد قليل…',
                  style: AppType.body(color: AppColors.textBody)),
            ),
          ])
        else if (last != null)
          Text.rich(
            key: const ValueKey('gdb-last'),
            TextSpan(children: [
              TextSpan(text: 'آخر نسخة: ', style: AppType.body(color: AppColors.textMid)),
              TextSpan(text: gdbRunWhen(last.finishedAt ?? last.startedAt, now: now), style: AppType.bodyStrong(color: AppColors.textHi)),
              if (gdbRunCounts(last).isNotEmpty) TextSpan(text: ' · ${gdbRunCounts(last)}', style: AppType.body(color: AppColors.textMid)),
            ]),
          )
        else
          Text('لم تُحفظ نسخة بعد.', style: AppType.body(color: AppColors.textMid)),
        const SizedBox(height: Sp.lg),
        Wrap(spacing: Sp.sm, runSpacing: Sp.sm, children: [
          if (link.folderUrl != null)
            OutlinedButton.icon(
              key: const ValueKey('gdb-folder'),
              onPressed: onOpenFolder,
              icon: const Icon(LucideIcons.folderOpen, size: 18),
              label: const Text('فتح المجلّد في Drive'),
            ),
          if (!link.broken)
            OutlinedButton(
              key: const ValueKey('gdb-run'),
              onPressed: busy == null && !st.working ? onRunNow : null,
              child: busy == 'run'
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('انسخ الآن'),
            ),
        ]),
      ]),
    );
  }
}

class _ScheduleCard extends StatelessWidget {
  const _ScheduleCard({required this.st, required this.onEdit, required this.onUnlink});
  final GdbStatus st;
  final VoidCallback onEdit;
  final VoidCallback onUnlink;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      decoration: _cardDeco(),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          key: const ValueKey('gdb-schedule'),
          onTap: onEdit,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Sp.lg, vertical: Sp.md),
            child: Row(children: [
              Icon(LucideIcons.calendarClock, size: 20, color: AppColors.brand),
              const SizedBox(width: Sp.md),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('الموعد', style: AppType.label(color: AppColors.textHi)),
                  const SizedBox(height: 2),
                  Text(
                    st.schedule.enabled ? st.scheduleText : 'موقوف — لا نسخ تلقائيّة',
                    style: AppType.muted(color: st.schedule.enabled ? AppColors.textMid : AppColors.warning),
                  ),
                ]),
              ),
              Text('تغيير', style: AppType.link(color: AppColors.brand)),
            ]),
          ),
        ),
        Divider(height: 1, color: AppColors.divider),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Sp.lg, vertical: Sp.md),
          child: Text(
            'نحتفظ بآخر ${st.keep} نسخة في درايفك، والأقدم تروح لسلّة المحذوفات فيه. الملفّ فيه ورقتان: «الديون» و«المشتركون».',
            style: AppType.muted(color: AppColors.textLow),
          ),
        ),
        Divider(height: 1, color: AppColors.divider),
        InkWell(
          key: const ValueKey('gdb-unlink'),
          onTap: onUnlink,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Sp.lg, vertical: Sp.md),
            child: Row(children: [
              Icon(LucideIcons.unlink, size: 18, color: AppColors.error),
              const SizedBox(width: Sp.md),
              Expanded(child: Text('إلغاء ربط Google Drive', style: AppType.label(color: AppColors.error))),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _RunsCard extends StatelessWidget {
  const _RunsCard({required this.runs, required this.now, required this.onOpen});
  final List<GdbRun> runs;
  final int now;
  final void Function(String? url) onOpen;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      key: const ValueKey('gdb-runs'),
      decoration: _cardDeco(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.sm),
          child: Text('آخر النسخ', style: AppType.subtitle(color: AppColors.textHi)),
        ),
        for (final r in runs) ...[
          Divider(height: 1, color: AppColors.divider),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Sp.lg, vertical: Sp.md),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text.rich(TextSpan(children: [
                    TextSpan(text: gdbRunWhen(r.startedAt, now: now), style: AppType.label(color: AppColors.textHi)),
                    TextSpan(text: ' · ${gdbTriggerLabel(r.trigger)}', style: AppType.muted(color: AppColors.textLow)),
                  ])),
                  const SizedBox(height: 2),
                  Text(
                    r.ok
                        ? (gdbRunCounts(r).isEmpty ? 'حُفظت' : gdbRunCounts(r))
                        : r.failed
                            ? (r.errorMessage ?? 'لم تُحفظ')
                            : 'جارية…',
                    style: AppType.muted(color: r.failed ? AppColors.error : AppColors.textMid),
                  ),
                ]),
              ),
              if (r.ok && r.fileUrl != null)
                TextButton(onPressed: () => onOpen(r.fileUrl), child: const Text('فتح')),
            ]),
          ),
        ],
      ]),
    );
  }
}

/// نافذة الموعد: كلّ يوم / كلّ أسبوع / كلّ شهر + اليوم + الساعة (بغداد) + تشغيل النسخ التلقائيّ.
class _ScheduleSheet extends StatefulWidget {
  const _ScheduleSheet({required this.initial});
  final GdbSchedule initial;

  @override
  State<_ScheduleSheet> createState() => _ScheduleSheetState();
}

class _ScheduleSheetState extends State<_ScheduleSheet> {
  late GdbSchedule _s = widget.initial.copyWith(weekday: widget.initial.weekday ?? 6, monthday: widget.initial.monthday ?? 1);

  Future<void> _pickTime() async {
    final p = _s.time.split(':');
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: int.tryParse(p[0]) ?? 3, minute: int.tryParse(p.length > 1 ? p[1] : '0') ?? 0),
    );
    if (picked == null || !mounted) return;
    setState(() => _s = _s.copyWith(time: '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}'));
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final freq = _s.frequency;
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.calendarClock,
        title: 'موعد النسخ',
        subtitle: 'بتوقيت بغداد',
        onClose: () => Navigator.of(context).pop(),
      ),
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SegmentedButton<String>(
          key: const ValueKey('gdb-freq'),
          segments: const [
            ButtonSegment(value: 'daily', label: Text('كل يوم')),
            ButtonSegment(value: 'weekly', label: Text('كل أسبوع')),
            ButtonSegment(value: 'monthly', label: Text('كل شهر')),
          ],
          selected: {freq},
          showSelectedIcon: false,
          onSelectionChanged: (v) => setState(() => _s = _s.copyWith(frequency: v.first)),
        ),
        const SizedBox(height: Sp.lg),
        if (freq == 'weekly')
          _SheetRow(
            label: 'اليوم',
            child: DropdownButton<int>(
              key: const ValueKey('gdb-weekday'),
              value: _s.weekday,
              underline: const SizedBox.shrink(),
              items: [for (final (n, name) in gdbWeekdays) DropdownMenuItem(value: n, child: Text(name))],
              onChanged: (v) => setState(() => _s = _s.copyWith(weekday: v)),
            ),
          ),
        if (freq == 'monthly')
          _SheetRow(
            label: 'يوم الشهر',
            child: DropdownButton<int>(
              key: const ValueKey('gdb-monthday'),
              value: _s.monthday,
              underline: const SizedBox.shrink(),
              items: [
                for (var d = 1; d <= 28; d++) DropdownMenuItem(value: d, child: Text('يوم $d')),
                const DropdownMenuItem(value: 0, child: Text('آخر يوم بالشهر')),
              ],
              onChanged: (v) => setState(() => _s = _s.copyWith(monthday: v)),
            ),
          ),
        _SheetRow(
          label: 'الساعة',
          child: TextButton(
            key: const ValueKey('gdb-time'),
            onPressed: _pickTime,
            // الساعة رقمٌ لاتينيّ بين عربيّ — معزولة (LRI … PDI)
            child: Text(iso(_s.time), style: AppType.label(color: AppColors.brand)),
          ),
        ),
        _SheetRow(
          label: 'النسخ التلقائيّ',
          child: Switch(
            key: const ValueKey('gdb-enabled'),
            value: _s.enabled,
            onChanged: (v) => setState(() => _s = _s.copyWith(enabled: v)),
          ),
        ),
        const SizedBox(height: Sp.sm),
        Text('نقترح ساعةً بالليل (مثل 03:00) حتى ما تزاحم الشغل.', style: AppType.muted(color: AppColors.textLow)),
      ]),
      footer: SizedBox(
        height: H.button,
        width: double.infinity,
        child: FilledButton(
          key: const ValueKey('gdb-schedule-save'),
          onPressed: () => Navigator.of(context).pop(_s),
          child: const Text('حفظ'),
        ),
      ),
    );
  }
}

class _SheetRow extends StatelessWidget {
  const _SheetRow({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Padding(
      padding: const EdgeInsets.only(bottom: Sp.sm),
      child: Row(children: [
        Expanded(child: Text(label, style: AppType.body(color: AppColors.textMid))),
        child,
      ]),
    );
  }
}
