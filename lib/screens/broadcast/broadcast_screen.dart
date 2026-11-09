
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/big_subscribers_api.dart';
import '../../api/broadcast_api.dart';
import '../../api/send_scope_api.dart';
import '../../api/wa_contact_risk.dart';
import '../../api/subscribers_api.dart';
import '../../models/subscriber.dart';
import '../../services/permissions_service.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../../api/company_route.dart';
import '../message_logs/message_logs_screen.dart';
import 'broadcast_campaigns_screen.dart';
import '../desktop/desk_widgets.dart';
import '../../core/platform/desktop_layout.dart';
import '../../widgets/merged_section.dart';
import '../../widgets/list_kit.dart';
import '../../widgets/debt_filter_panel.dart';
import '../../core/util/amount_input.dart';
import '../../core/widgets/app_sheet.dart';
import '../../core/widgets/design_sheet.dart';

/// شاشة "التبليغات" (Broadcast) — نقل حرفي من client-v2/Notifications.tsx.
/// يسمح للمدير بإرسال رسائل واتساب جماعيّة للمشتركين حسب فلتر (كل/مدينون/
/// منتهي/قرب انتهاء) مع نطاق إرسال (عام/محدّد) + محرّر متغيّرات.
class BroadcastScreen extends StatefulWidget {
  const BroadcastScreen({super.key});

  @override
  State<BroadcastScreen> createState() => _BroadcastScreenState();
}

enum _Filter { all, debtors, expired, expiring }

/// جمهور «قرب الانتهاء» في التبليغات — **قاعدة الخادم والويب نفسها**، لا
/// [Subscriber.isNearExpiry] (ذاك يلوّن البطاقات: من الآن إلى ما دون أربعة أيّام).
///
/// الخادم يفلتر `type:'expiring'` بنفسه (إصلاح ١٨ أكتوبر — كان يعامله «عامّاً»
/// فيذهب المكتوب لكلّ المشتركين، والفارغ لا يذهب لأحد؛ والفارغ الآن قالب
/// `expiry_warning`): **لم ينتهِ بعد** (الانتهاء بعد الآن بساعة بغداد) وينتهي قبل
/// منتصف ليل **بغداد** اليوم + ثلاثة أيّام (شاملاً)، وبلا تاريخٍ مقروء الأيّامُ الباقية
/// 1..3 — مطابقٌ حرفيّاً لـ`broadcastAudience.isExpiringSoon`
/// وعدّاد `Notifications.tsx`. والنطاق «عام» لا يرسل أسماءً (الخادم يختار، فيبقى
/// نطاق الإرسال وحماية التكرار اليوميّ)، فعدّاد الشاشة وحوار التأكيد يَعُدّان
/// بالقاعدة نفسها وإلّا وعدا بعددٍ ويُرسَل لغيره. و«محدّد» يرسل الأسماء فتُرسَل كما
/// هي (لا يعيد الخادم فلترتها) — فالقائمة المعروضة للاختيار بالقاعدة نفسها أيضاً.
///
/// منتصف ليل بغداد (UTC+3 ثابتة، بلا توقيتٍ صيفيّ) لا منتصف ليل الجهاز، وتاريخ
/// الساس يُقرأ بساعته الجدرانيّة كما هو ([Subscriber.parsedExpiration]).
@visibleForTesting
bool broadcastExpiring(Subscriber s, {DateTime? now}) {
  final b = (now ?? DateTime.now()).toUtc().add(const Duration(hours: 3));
  // ساعة بغداد الجداريّة — تاريخ الساس يُقرأ بها ([Subscriber.parsedExpiration]).
  final nowWall =
      DateTime(b.year, b.month, b.day, b.hour, b.minute, b.second);
  final today = DateTime(b.year, b.month, b.day);
  final exp = s.parsedExpiration;
  if (exp != null) {
    // من انتهى صباح اليوم لا يُبلَّغ «ستنتهي بعد…» (الخادم يستثنيه أيضاً).
    return exp.isAfter(nowWall) &&
        !exp.isAfter(today.add(const Duration(days: 3)));
  }
  final d = s.remainingDays;
  return d != null && d >= 1 && d <= 3;
}

enum _Scope { all, specific }

class _BroadcastScreenState extends State<BroadcastScreen> with WidgetsBindingObserver {
  _Filter _filter = _Filter.all;
  _Scope _scope = _Scope.all;
  final Set<String> _selected = <String>{};
  final TextEditingController _msg = TextEditingController();
  final TextEditingController _search = TextEditingController();
  final FocusNode _msgFocus = FocusNode();

  List<Subscriber> _subs = const [];
  bool _loading = true;
  bool _sending = false;

  /// الحساب الكبير (≥ ٥٠٠٠): لا قائمة كاملة — المرشّحون نتائج بحث الساس، والمختارون يبقون عبر البحوث ([_bigPicked])،
  /// والإرسال للمحدّدين وحدهم (حتى [_kBigMaxTargets] — الخادم يبحث عن كلٍّ منهم). «عام» (فئةٌ كاملة) غير متاح بعد:
  /// الخادم يرفضه صراحةً (BIG_LIST)، والتذكيرات التلقائيّة تعمل لكلّ المشتركين.
  bool _big = false;
  int _bigTotal = 0;
  BigCounts? _bigCounts;
  final _bigSearch = BigSearch(size: 50);
  final Map<String, Subscriber> _bigPicked = {};
  static const int _kBigMaxTargets = 100; // = TARGET_MAX في الخادم (whatsapp/sas4Client.js)

  /// جارٍ سؤال الخادم عن خطر الأرقام — بين الضغط والحوار.
  bool _checkingRisk = false;

  /// هل يقبل المدير مراسلة الدرجة الحرجة؟ يُعاد إلى false بعد كلّ
  /// بثّ عمداً: موافقةٌ على حملةٍ ليست موافقةً دائمة.
  bool _includeHighRisk = false;
  bool _retrying = false;

  /// المدراء الفرعيون المتاحون للفلترة (من SendScopeApi.fetch).
  /// null = لم يُحمَّل بعد. فارغة = المدير ما عنده مدراء فرعيون —
  /// فلتر المدير يُخفى.
  List<String>? _subManagers;

  /// selectedSubManagers = null أو فارغة → "الكل" (بدون فلترة).
  /// خلاف ذلك = فقط مشتركو هؤلاء المدراء.
  final Set<String> _managerFilter = <String>{};

  /// صورة مرفقة (اختياريّة) — تُرسل كـcaption مع نص الرسالة. نضغطها
  /// عند الاختيار (maxWidth=1024, imageQuality=60) وإذا مازالت > الحدّ
  /// نرفضها. تُنسخ لكل مستقبل في `whatsapp_message_queue.media_data`،
  /// فحدّ 300KB مقصود.
  Uint8List? _imageBytes;
  String? _imageName;
  final ImagePicker _picker = ImagePicker();

  /// 2026-08-26 (tg parity): قناة الإرسال المفروضة على البث الجماعي.
  /// 'auto' = يحترم binding المشترك، 'whatsapp' = يجبر واتساب،
  /// 'telegram' = يفلتر المربوطين بتلغرام فقط (الباقي يُتخطى).
  String _forceChannel = 'auto';

  // ─── «تحديد المدينين» (٩ نوفمبر — المالك: «تحديد نطاقة جلب اليوزرية حسب اقدم مده دين وسقف من والى الدين … اما المده او
  // المبلغ او الاثنين») ─────────────────────────────────────────────────────────────────────────────────────────────
  // العمر = عمر **أقدم دينٍ لم يُسدَّد** (قراره بمثاله: ٣٥ ألفاً منذ ٩٠ يوماً + ٣٥ ألفاً قبل يومين ⇒ ٩٠ يوماً) — يحسبه الخادم وحده من
  // دفتر حركات الدين، فالقائمة هنا لا تُرشَّح محلّيّاً بالعمر: المعاينة (dryRun) تقول من يطابق، والإرسال يحمل بصمتها.
  /// ما يدعمه الخادم لهذا الحساب — null ⇒ لا لوحة (خادمٌ أقدم، أو بلا صلاحيّة). الكبير حين يحسبه الخادم في الخلفيّة (bigAsync).
  DebtFilterCapability? _dfCap;
  DebtFilter _df = DebtFilter.none;
  BroadcastPreview? _dfPreview;
  String? _dfPreviewError;
  bool _dfPreviewBusy = false;

  /// الحساب الكبير: «نحسب…» من الخادم (يُعاد السؤال كلّ ٤ ثوانٍ حتى تجهز) — نصّه كما قاله الخادم.
  String? _dfPending;
  int _dfSeq = 0;
  Timer? _dfDebounce;

  /// أسئلة «نحسب…» المعادة لهذا التحديد — تقف عند [_kPendingPolls] (~٣ دقائق كانتظار الإرسال) بسببها وزرّ «إعادة»، لا إلى ما لا نهاية.
  int _dfPolls = 0;

  /// معاينةٌ أُوقفت لأنّ التطبيق ذهب للخلفيّة (أو طُلبت وهو هناك) — تُعاد عند الرجوع.
  bool _dfPausedInBackground = false;
  bool _inBackground = false;

  static const _kPendingEvery = Duration(seconds: 4);
  static const _kPendingPolls = 45;

  /// «كل الشركات» (٨ نوفمبر): شركةٌ غير المفتوحة — للعرض وحده (حملاتها وحالة رسائلها)؛ لا قائمة مشتركين تُقرأ هنا (كانت
  /// تُقرأ قائمة المفتوحة فتُعرض أعدادها وأسماؤها تحت شركةٍ أخرى) ولا إرسال — من صفحتها.
  bool get _viewOnly => CompanyRoute.sectionKeyFor('/api/whatsapp/broadcast') != null;

  @override
  void initState() {
    super.initState();
    if (_viewOnly) {
      _loading = false;
      return;
    }
    WidgetsBinding.instance.addObserver(this);
    _load();
    _loadScope();
    _loadDebtCap();
  }

  /// التطبيق في الخلفيّة (أو أُخفيت نافذته): معاينة التحديد لا تُسأل هناك — تقف، وتُعاد عند الرجوع إن بقي التحديد قائماً.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.hidden || AppLifecycleState.paused || AppLifecycleState.detached:
        _inBackground = true;
        if (_dfPreviewBusy && !_dfPausedInBackground) {
          _dfDebounce?.cancel();
          _dfSeq++; // ردٌّ يصل بعد الآن لا يُطبَّق ولا يعيد السؤال
          _dfPausedInBackground = true;
        }
      case AppLifecycleState.resumed:
        _inBackground = false;
        if (_dfPausedInBackground) _schedulePreview();
      case AppLifecycleState.inactive:
        break;
    }
  }

  Future<void> _loadDebtCap() async {
    final c = await BroadcastApi.debtFilterCapability();
    if (!mounted) return;
    setState(() => _dfCap = c);
  }

  Future<void> _loadScope() async {
    final s = await SendScopeApi.fetch();
    if (!mounted) return;
    setState(() => _subManagers = s?.subManagers ?? const []);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _dfDebounce?.cancel();
    _bigSearch.dispose();
    _msg.dispose();
    _search.dispose();
    _msgFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final big = await BigSubscribersApi.probe();
    if (!mounted) return;
    if (big > 0) {
      final c = await BigSubscribersApi.summary();
      if (!mounted) return;
      setState(() {
        _big = true;
        _bigTotal = big;
        _bigCounts = c;
        _scope = _Scope.specific;
        _loading = false;
      });
      _bigSearch.search(_search.text, onRows: _setBigRows, now: true);
      return;
    }
    final subs = await SubscribersApi.loadAll();
    if (!mounted) return;
    setState(() {
      _subs = subs ?? const [];
      _loading = false;
    });
  }

  void _setBigRows(List<Subscriber> rows) {
    if (mounted) setState(() => _subs = rows);
  }

  // ─── فلاتر ─────────────────────────────────────

  List<Subscriber> get _withPhone => _subs
      .where(
          (s) => (s.phone?.length ?? 0) >= 10 || (s.mobile?.length ?? 0) >= 10)
      .toList();

  /// المشتركون بعد فلتر الفئة (all/debtors/expired/expiring).
  List<Subscriber> get _byCategory {
    switch (_filter) {
      case _Filter.all:
        return _withPhone;
      case _Filter.debtors:
        return _withPhone.where((s) {
          if (s.hasDebtFlag) return true;
          if ((s.debt ?? 0) > 0) return true;
          final n = double.tryParse((s.notes ?? '0').replaceAll(',', ''));
          return n != null && n < 0;
        }).toList();
      case _Filter.expired:
        return _withPhone.where((s) => s.isExpired).toList();
      case _Filter.expiring:
        final now = DateTime.now();
        return _withPhone.where((s) => broadcastExpiring(s, now: now)).toList();
    }
  }

  /// المرشّحون النهائيون = فلتر الفئة + (اختياراً) فلتر مدير الأب.
  /// لو _managerFilter فارغة = بدون قيود مدير.
  List<Subscriber> get _candidates {
    if (_managerFilter.isEmpty) return _byCategory;
    final allowedLower = _managerFilter.map((m) => m.toLowerCase()).toSet();
    return _byCategory.where((s) {
      final p = (s.parentUsername ?? '').toLowerCase();
      return allowedLower.contains(p);
    }).toList();
  }

  List<Subscriber> get _visibleCandidates {
    if (_big) return _candidates; // الساس بحث
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return _candidates;
    return _candidates.where((s) {
      return s.username.toLowerCase().contains(q) ||
          s.firstname.toLowerCase().contains(q) ||
          s.lastname.toLowerCase().contains(q) ||
          (s.phone ?? '').contains(q) ||
          (s.mobile ?? '').contains(q);
    }).toList();
  }

  List<Subscriber> get _targets => _big
      ? (_scope == _Scope.specific ? _bigPicked.values.toList() : const [])
      : _scope == _Scope.all
          ? _candidates
          : _candidates.where((s) => _selected.contains(s.username)).toList();

  /// اللوحة متاحة: خادمٌ يدعمها، والحساب الكبير حين يحسب الخادم معاينته في الخلفيّة (٩ نوفمبر ٢ — المالك «نعم» للكبيرة).
  bool get _dfAvailable => _dfCap != null && (!_big || _dfCap!.bigAsync);

  /// التحديد مفعّلٌ الآن (فئة المدينين، خادمٌ يدعمه لهذا الحساب، وحدٌّ واحدٌ على الأقلّ).
  bool get _debtFilterOn => _filter == _Filter.debtors && _dfAvailable && _df.active;

  /// فلتر المدير الفرعيّ لا يعرفه الخادم: معه تُرسَل أسماء الفئة بعد الفلتر صراحةً (كان «عام» يرسل للفئة كلّها مهما اختير المدير).
  List<String>? get _managerScopedUsernames =>
      _managerFilter.isEmpty || _big ? null : _candidates.map((s) => s.username).toList();

  /// المختارون من قائمة المعاينة (بالتحديد) — الظاهرون فيها وحدهم.
  List<String> get _pickedFromPreview {
    final rows = {for (final r in _dfPreview?.rows ?? const <BroadcastPreviewRow>[]) r.username};
    return _selected.where(rows.contains).toList();
  }

  void _setDebtFilter(DebtFilter f) {
    setState(() {
      _df = f;
      _selected.clear();
      _dfPreview = null;
      _dfPreviewError = null;
      _dfPending = null;
    });
    _schedulePreview();
  }

  void _schedulePreview() {
    _dfDebounce?.cancel();
    final seq = ++_dfSeq;
    _dfPolls = 0;
    _dfPausedInBackground = false;
    if (!_debtFilterOn || _df.problem() != null) {
      setState(() => _dfPreviewBusy = false);
      return;
    }
    // «إعادة» بعد خطأٍ أو مهلة: «يحسب…» يظهر مكان السبب لا تحته
    setState(() {
      _dfPreviewBusy = true;
      _dfPreviewError = null;
    });
    // طُلبت والتطبيق في الخلفيّة (إرسالٌ انتهى هناك مثلاً): تُسأل عند الرجوع لا هناك
    if (_inBackground) {
      _dfPausedInBackground = true;
      return;
    }
    _dfDebounce = Timer(const Duration(milliseconds: 600), () => _runPreview(seq));
  }

  /// اللوحة اختفت (فئةٌ غير «المدينون»): لا سؤال بعدها ولا ردٌّ متأخّرٌ يُطبَّق — والعودة إليها تعيد المعاينة ([_selectFilter]).
  void _stopPreview() {
    _dfDebounce?.cancel();
    _dfSeq++;
    _dfPolls = 0;
    _dfPausedInBackground = false;
    _dfPreviewBusy = false;
    _dfPending = null;
  }

  Future<void> _runPreview(int seq) async {
    final r = await BroadcastApi.preview(
      intent: MessageIntent.debtors,
      debtFilter: _df,
      targetUsernames: _managerScopedUsernames,
    );
    if (!mounted || seq != _dfSeq) return;
    // الحساب الكبير: الخادم يحسب في الخلفيّة — السؤال نفسه بعد ٤ ثوانٍ (يُجاب من ذاكرته بلا ساس) ما لم يتغيّر التحديد، وما دامت
    // اللوحة ظاهرةً والتطبيق أمامه — حتى [_kPendingPolls] سؤالاً، ثمّ السبب و«إعادة»
    if (r.preview?.pending == true) {
      if (_dfPolls >= _kPendingPolls) {
        setState(() {
          _dfPreviewBusy = false;
          _dfPending = null;
          _dfPreviewError = 'ما زالت المعاينة تُحسب — أعد المحاولة بعد قليل';
        });
        return;
      }
      _dfPolls++;
      setState(() {
        _dfPreviewBusy = true;
        _dfPending = r.preview!.pendingMessage ?? 'حسابك كبير: نحسب من يطابق في الخلفيّة — تظهر النتيجة خلال دقيقة تقريباً';
        _dfPreviewError = null;
      });
      _dfDebounce?.cancel();
      _dfDebounce = Timer(_kPendingEvery, () {
        if (mounted && seq == _dfSeq && _debtFilterOn) _runPreview(seq);
      });
      return;
    }
    setState(() {
      _dfPreviewBusy = false;
      _dfPending = null;
      _dfPreview = r.preview;
      _dfPreviewError = r.preview == null ? (r.message ?? 'تعذّرت المعاينة') : null;
    });
  }

  Map<_Filter, int> get _counts {
    // الكبير: أعداد الفئات من الساس (كلّ المشتركين، لا من لهم رقم) — والدين -1 «—» حين لا يُعرف
    if (_big) {
      final c = _bigCounts;
      return {
        _Filter.all: c?.all ?? _bigTotal,
        _Filter.debtors: c?.debtors ?? -1,
        _Filter.expired: c?.expired ?? -1,
        _Filter.expiring: c?.nearExpiry ?? -1,
      };
    }
    int debtors = 0;
    int expired = 0;
    int expiring = 0;
    final now = DateTime.now();
    for (final s in _withPhone) {
      final hasDebt = s.hasDebtFlag ||
          (s.debt ?? 0) > 0 ||
          (double.tryParse((s.notes ?? '0').replaceAll(',', '')) ?? 0) < 0;
      if (hasDebt) debtors++;
      if (s.isExpired) expired++;
      if (broadcastExpiring(s, now: now)) expiring++;
    }
    return {
      _Filter.all: _withPhone.length,
      _Filter.debtors: debtors,
      _Filter.expired: expired,
      _Filter.expiring: expiring,
    };
  }

  MessageIntent get _intent {
    switch (_filter) {
      case _Filter.all:
        return MessageIntent.general;
      case _Filter.debtors:
        return MessageIntent.debtors;
      case _Filter.expired:
        return MessageIntent.expired;
      case _Filter.expiring:
        return MessageIntent.expiring;
    }
  }

  bool get _messageOptional => _intent.messageOptional;

  /// الحساب الكبير «عام»: الفئة كلّها يجمعها الخادم في الخلفيّة — لا قائمة هنا يُحسب منها.
  bool get _bigAll => _big && _scope == _Scope.all;

  bool get _canSend =>
      !_sending &&
      // الفحص لحظةٌ واحدة، لكنّ نقرةً ثانيةً فيها تفتح حوارين.
      !_checkingRisk &&
      (_debtFilterOn
          ? _df.problem() == null &&
              (_scope == _Scope.specific ? _pickedFromPreview.isNotEmpty : (_dfPreview?.count ?? 0) > 0)
          : (_bigAll || _targets.isNotEmpty)) &&
      // مع وجود صورة، الرسالة النصّية اختياريّة (تصبح caption).
      (_messageOptional ||
          _msg.text.trim().isNotEmpty ||
          _imageBytes != null) &&
      Perms.has('whatsapp.broadcast');

  // ─── actions ─────────────────────────────────────

  void _selectFilter(_Filter f) {
    setState(() {
      _filter = f;
      _selected.clear();
      _bigPicked.clear();
      if (f != _Filter.debtors) _stopPreview();
    });
    if (f == _Filter.debtors && _df.active) _schedulePreview();
  }

  void _toggleSelect(String username) {
    if (_big && !_selected.contains(username) && _selected.length >= _kBigMaxTargets) {
      _snack('حتى $_kBigMaxTargets مشتركاً في المرّة للحسابات الكبيرة', isError: true);
      return;
    }
    setState(() {
      if (_selected.contains(username)) {
        _selected.remove(username);
        _bigPicked.remove(username);
      } else {
        _selected.add(username);
        if (_big) {
          for (final s in _subs) {
            if (s.username == username) _bigPicked[username] = s;
          }
        }
      }
    });
  }

  void _toggleSelectAllVisible() {
    setState(() {
      final visible = _visibleCandidates;
      final allSelected = visible.every((s) => _selected.contains(s.username));
      if (allSelected) {
        for (final s in visible) {
          _selected.remove(s.username);
          _bigPicked.remove(s.username);
        }
      } else {
        for (final s in visible) {
          if (_big && _selected.length >= _kBigMaxTargets) break;
          _selected.add(s.username);
          if (_big) _bigPicked[s.username] = s;
        }
      }
    });
  }

  void _insertVariable(String token) {
    HapticFeedback.selectionClick();
    final sel = _msg.selection;
    final txt = _msg.text;
    final start = sel.start < 0 ? txt.length : sel.start;
    final end = sel.end < 0 ? txt.length : sel.end;
    final needsSpace = start > 0 && !txt.substring(0, start).endsWith(' ');
    final withSpace = needsSpace ? ' $token' : token;
    final finalText = txt.substring(0, start) + withSpace + txt.substring(end);
    _msg.value = TextEditingValue(
      text: finalText,
      selection: TextSelection.collapsed(offset: start + withSpace.length),
    );
    _msgFocus.requestFocus();
  }

  Future<void> _send() async {
    if (_debtFilterOn) return _sendFiltered();
    if (_bigAll) return _sendBigAll();
    final targets = _targets;
    if (targets.isEmpty) return;

    // ── حارس الحظر — يُسأل **قبل** الحوار ─────────────────────────
    //
    // الحارس المفرد يقف أمام رسالةٍ واحدة والمدير يقرأ ويقرّر. أمّا
    // هنا فمئتا رسالة بنقرة، ولا أحد يقرأ مئتَي تحذير — فالملخّص
    // جملةٌ واحدة أو لا شيء.
    //
    // ⚠️ ولا يوقف: الفشل يُرجع `none` فيمضي الإرسال بحواره المعتاد.
    // حارسٌ يمنع البثّ عند أوّل انقطاع شبكة يُطفَأ في يومه الأوّل.
    setState(() => _checkingRisk = true);
    final risk = await WaBulkRiskApi.fetch(
      [for (final t in targets) t.displayPhone].where((p) => p.isNotEmpty).toList(),
    );
    if (!mounted) return;
    setState(() => _checkingRisk = false);

    final confirm = await _confirmSend(targets.length, risk);
    if (confirm != true) return;
    setState(() => _sending = true);
    final r = await BroadcastApi.broadcast(
      intent: _intent,
      message: _msg.text.trim(),
      // «عام» مع فلتر مديرٍ فرعيّ: أسماء الفئة بعد الفلتر صراحةً — الخادم لا يعرف الفلتر، وبلاها يرسل للفئة كلّها (وحوار التأكيد قال غيرها)
      targetUsernames: _scope == _Scope.specific || _managerFilter.isNotEmpty
          ? targets.map((t) => t.username).toList()
          : null,
      imageBytes: _imageBytes,
      imageMime: 'image/jpeg',
      imageFilename: _imageName ?? 'broadcast.jpg',
      forceChannel: _forceChannel == 'auto' ? null : _forceChannel,
      includeHighRisk: _includeHighRisk,
    );
    if (!mounted) return;
    setState(() => _sending = false);
    if (r.ok) {
      // ⚠️ الاستبعاد يُذكر دائماً: عمليّةٌ صامتة تُنقص ٦٪ من حملة
      // تذكيرٍ بالديون تُكتشَف بعد أسبوع «ليش ما وصلته رسالة؟».
      final ex = r.excludedHighRisk ?? 0;
      _snack(
        ex > 0
            ? 'أُدرجت ${r.queued ?? 0} رسالة — واستُبعد $ex لخطر الحظر'
            : 'تم إرسال ${r.queued ?? targets.length} رسالة إلى الطابور',
        isError: false,
      );
      setState(() {
        _msg.clear();
        _selected.clear();
        _imageBytes = null;
        _imageName = null;
      });
    } else {
      _snack(r.message ?? 'فشل الإرسال', isError: true);
    }
  }

  /// الإرسال بالتحديد: معاينةٌ للطلب نفسه (الكلّ أو المختارون) ⇒ ورقة تأكيدٍ بالعدد والقائمة ⇒ الإرسال ببصمتها. تغيّرت القائمة بين
  /// الاثنين ⇒ الخادم يرفض (409) فتُعاد المعاينة — لا يُرسَل لغير ما رآه المدير.
  Future<void> _sendFiltered() async {
    final specific = _scope == _Scope.specific;
    final picked = specific ? _pickedFromPreview : null;
    if (specific && (picked == null || picked.isEmpty)) return;
    // الكبير «الكلّ»: الخادم يجمع المدينين كلّهم — فلتر المدير لا يصله، فلا يُرسَل لأوسع ممّا اختاره المدير (كـ«عام» الكبير)
    final bigAll = _big && !specific;
    if (bigAll && _managerFilter.isNotEmpty) {
      _snack('فلتر المدير لا يُطبَّق على «الكلّ» في الحساب الكبير — ألغِه أو استعمل «أختار بنفسي»', isError: true);
      return;
    }
    setState(() => _checkingRisk = true);
    var pv = await BroadcastApi.preview(
      intent: MessageIntent.debtors,
      debtFilter: _df,
      targetUsernames: specific ? picked : _managerScopedUsernames,
    );
    // الكبير: معاينةٌ قديمة تُحسب من جديد في الخلفيّة — ننتظرها (حتى ٣ دقائق) قبل ورقة التأكيد
    for (var i = 0; i < _kPendingPolls && mounted && pv.preview?.pending == true; i++) {
      await Future<void>.delayed(_kPendingEvery);
      if (!mounted) return;
      pv = await BroadcastApi.preview(intent: MessageIntent.debtors, debtFilter: _df, targetUsernames: specific ? picked : _managerScopedUsernames);
    }
    if (!mounted) return;
    setState(() => _checkingRisk = false);
    if (pv.preview?.pending == true) {
      _snack('ما زالت المعاينة تُحسب — أعد المحاولة بعد قليل. لم يُرسَل شيء', isError: true);
      return;
    }
    final preview = pv.preview;
    if (preview == null) {
      _snack(pv.message ?? 'تعذّرت المعاينة — لم يُرسَل شيء', isError: true);
      return;
    }
    if (preview.count == 0 && preview.excludedHighRisk == 0) {
      _snack('لا أحد يطابق التحديد الآن', isError: true);
      return;
    }
    final include = await showAppSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: AppColors.scrim,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _FilteredConfirmSheet(
        preview: preview,
        summary: _df.describe(),
        channel: _forceChannel,
        includeHighRisk: _includeHighRisk,
        bigBackground: bigAll,
      ),
    );
    if (include == null || !mounted) return;
    setState(() => _sending = true);
    final r = await BroadcastApi.broadcast(
      intent: MessageIntent.debtors,
      message: _msg.text.trim(),
      targetUsernames: specific ? picked : _managerScopedUsernames,
      debtFilter: _df,
      audienceKey: preview.audienceKey,
      audienceCount: preview.audience,
      imageBytes: _imageBytes,
      imageMime: 'image/jpeg',
      imageFilename: _imageName ?? 'broadcast.jpg',
      forceChannel: _forceChannel == 'auto' ? null : _forceChannel,
      includeHighRisk: include,
    );
    if (!mounted) return;
    setState(() => _sending = false);
    if (r.ok) {
      final ex = r.excludedHighRisk ?? 0;
      _snack(
        r.message ??
            (ex > 0
                ? 'أُدرجت ${r.queued ?? 0} رسالة — واستُبعد $ex لخطر الحظر'
                : 'تم إرسال ${r.queued ?? preview.count} رسالة إلى الطابور'),
        isError: false,
      );
      setState(() {
        _msg.clear();
        _selected.clear();
        _imageBytes = null;
        _imageName = null;
      });
      _schedulePreview();
    } else {
      _snack(r.message ?? 'فشل الإرسال', isError: true);
      if (r.code == 'BROADCAST_AUDIENCE_CHANGED' || r.code == 'DEBT_FILTER_PREVIEW_EXPIRED') _schedulePreview();
    }
  }

  /// الحساب الكبير «عام»: تأكيدٌ بعدد الفئة من الساس، ثمّ يردّ الخادم فوراً «بدأ التجهيز» ويصل إشعارٌ بالنتيجة.
  Future<void> _sendBigAll() async {
    // الخادم يجمع الفئة كلّها — فلتر المدير لا يصله، فلا يُرسَل لأوسع ممّا اختاره المدير
    if (_managerFilter.isNotEmpty) {
      _snack('فلتر المدير لا يُطبَّق على «عام» في الحساب الكبير — ألغِه أو استعمل «محدّد»', isError: true);
      return;
    }
    final n = _counts[_filter] ?? -1;
    final ok = await _confirmDialog(
      'إرسال لفئةٍ كاملة',
      '${n < 0 ? 'إرسال لكلّ مشتركي الفئة' : 'إرسال لنحو $n مشترك في الفئة'} (من له رقم هاتف)؟ '
      'يجهّزها الخادم خلال دقائق ويصلك إشعارٌ بالنتيجة.',
      confirmLabel: 'إرسال',
      confirmColor: AppColors.brand,
    );
    if (ok != true || !mounted) return;
    setState(() => _sending = true);
    final r = await BroadcastApi.broadcast(
      intent: _intent,
      message: _msg.text.trim(),
      targetUsernames: null,
      imageBytes: _imageBytes,
      imageMime: 'image/jpeg',
      imageFilename: _imageName ?? 'broadcast.jpg',
      forceChannel: _forceChannel == 'auto' ? null : _forceChannel,
      includeHighRisk: false,
    );
    if (!mounted) return;
    setState(() => _sending = false);
    if (r.ok) {
      _snack(r.message ?? 'بدأ تجهيز التبليغ — يصلك إشعارٌ بالنتيجة', isError: false);
      setState(() {
        _msg.clear();
        _imageBytes = null;
        _imageName = null;
      });
    } else {
      _snack(r.message ?? 'فشل الإرسال', isError: true);
    }
  }

  Future<void> _pickImage() async {
    try {
      // imageQuality: 60 + maxWidth: 1024 يضغطها لصورة ~50-200KB في
      // الغالب. الحدّ النهائي محسوم في BroadcastApi.maxImageBytes.
      final XFile? file = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 60,
        maxWidth: 1024,
        maxHeight: 1024,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      if (bytes.length > BroadcastApi.maxImageBytes) {
        _snack(
          'الصورة أكبر من ${(BroadcastApi.maxImageBytes / 1024).round()}KB '
          '(الحجم الحالي ~${(bytes.length / 1024).round()}KB). اختر صورة أصغر.',
          isError: true,
        );
        return;
      }
      setState(() {
        _imageBytes = bytes;
        _imageName = file.name;
      });
    } catch (e) {
      if (!mounted) return;
      _snack('تعذّر اختيار الصورة: $e', isError: true);
    }
  }

  void _removeImage() {
    setState(() {
      _imageBytes = null;
      _imageName = null;
    });
  }

  Future<void> _retryFailed() async {
    final confirm = await _confirmDialog(
      'إعادة الفاشلة',
      'إعادة محاولة الرسائل الفاشلة من آخر 24 ساعة؟',
      confirmLabel: 'إعادة',
      confirmColor: AppColors.warning,
    );
    if (confirm != true) return;
    setState(() => _retrying = true);
    final r = await BroadcastApi.retryFailed();
    if (!mounted) return;
    setState(() => _retrying = false);
    _snack(
      r.ok
          ? (r.message ?? 'تمّت إعادة المحاولة')
          : (r.message ?? 'فشلت إعادة المحاولة'),
      isError: !r.ok,
    );
  }

  void _openCampaigns() {
    final ro = _viewOnly;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => BroadcastCampaignsScreen(readOnly: ro)),
    );
  }

  /// للعرض وحده: حملات الشركة وحالة رسائلها — كلاهما يُقرأ موجَّهاً لها.
  Widget _viewOnlyBody() {
    Widget tile(IconData icon, String title, String subtitle, VoidCallback onTap, Key key) => Padding(
          padding: const EdgeInsets.only(bottom: Sp.sm),
          child: Material(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(R.md),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: key,
              onTap: onTap,
              child: Container(
                padding: const EdgeInsets.all(Sp.md),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(R.md),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(children: [
                  Icon(icon, size: 20, color: AppColors.brand),
                  const SizedBox(width: Sp.md),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(title, style: AppType.bodyBold(color: AppColors.textHi)),
                      const SizedBox(height: 2),
                      Text(subtitle, style: AppType.micro(color: AppColors.textMid)),
                    ]),
                  ),
                  Icon(LucideIcons.chevronLeft, size: 18, color: AppColors.textMid),
                ]),
              ),
            ),
          ),
        );
    return ListView(
      padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.lg, Sp.lg, Sp.huge),
      children: [
        tile(LucideIcons.listChecks, 'حملات التبليغ', 'كلّ بثٍّ أُرسل بأعداده وحاله', _openCampaigns,
            const ValueKey('broadcast-view-campaigns')),
        tile(LucideIcons.history, 'حالة الرسائل', 'ما أُرسل وما فشل وما ينتظر', _openLogs,
            const ValueKey('broadcast-view-logs')),
      ],
    );
  }

  void _openLogs() {
    // نفتح الشاشة الكاملة بدل الورقة السفلية — تدعم كل الأنواع + بحث +
    // فلاتر + auto-refresh للـpending، وأي رسالة بعثتها الآن رح تظهر
    // مباشرةً بحالة "انتظار" ثم تتحول لـ"أُرسلت" تلقائياً.
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MessageLogsScreen.mergedPage(),
      ),
    );
  }

  /// حوار التأكيد مع ملخّص الخطر.
  ///
  /// ── لماذا رقمان لا واحد ──────────────────────────────────────────
  /// «لم يراسلوك» و«تجاهلوا ستّاً» ليسا درجتين من شيءٍ واحد، بل
  /// شيئان مختلفان في القرار:
  ///
  /// الأوّل نصف الجمهور تقريباً (قِيس: ٥٢٪) — واستبعادُه يُلغي البثّ
  /// لا يحرسه. يُذكَر ليعرف المدير طبيعة جمهوره، ولا يُطرح أحد.
  ///
  /// الثاني ٦٪ وسطيّاً على ستّة مدراء حقيقيّين — وهو من راسلتَه ستّاً
  /// فلم يردّ مرّة، أو ثبت أنّ رقمه لا يستقبل. هؤلاء يُطرحون
  /// افتراضيّاً، ويستطيع المدير إعادتهم بمفتاحٍ في هذا الحوار.
  ///
  /// ⚠️ ودمجُ الرقمين في تحذيرٍ واحد يُفقد كليهما معناه: «١٠٤ من ٢٠٠
  /// في خطر» رقمٌ يُتجاهَل في اليوم الثاني، بينما «١٢ سيُستبعَدون»
  /// رقمٌ يُقرأ ويُقرَّر فيه.
  Future<bool?> _confirmSend(int count, WaBulkRisk risk) async {
    if (!risk.hasWarning) {
      return _confirmDialog(
        'إرسال الرسالة',
        'إرسال إلى $count مشترك؟',
        confirmLabel: 'إرسال',
        confirmColor: AppColors.brand,
      );
    }
    var include = _includeHighRisk;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final willSend = include ? count : count - risk.highRisk;
          return AlertDialog(
            backgroundColor: AppColors.surface,
            title: Text('إرسال إلى $count مشترك',
                style: AppType.title(color: AppColors.textHi)
                    .copyWith(fontSize: 16)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (risk.noInbound > 0)
                  Text(
                    '${risk.noInbound} من ${risk.total} لم تسبق لهم مراسلتك.',
                    style: AppType.subtitle(color: AppColors.textMid),
                  ),
                if (risk.highRisk > 0) ...[
                  const SizedBox(height: Sp.sm),
                  Container(
                    padding: const EdgeInsets.all(Sp.sm),
                    decoration: BoxDecoration(
                      color: AppColors.dangerSoftBg,
                      borderRadius: BorderRadius.circular(R.sm),
                      border: Border.all(color: AppColors.dangerSoftBorder),
                    ),
                    child: Text(
                      'منهم ${risk.highRisk} تجاهلوا ٦ رسائل فأكثر بلا ردّ — '
                      'وهؤلاء أكثر من يُبلّغ عنك فيُحظر رقمك.',
                      style: AppType.subtitle(color: AppColors.error),
                    ),
                  ),
                  const SizedBox(height: Sp.xs),
                  // ⚠️ المفتاح لا زرّ: القرار قابلٌ للتراجع قبل الإرسال،
                  // والمدير يرى أثره في السطر الذي تحته فوراً.
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    value: include,
                    activeThumbColor: AppColors.error,
                    onChanged: (v) => setLocal(() => include = v),
                    title: Text('أرسل لهم أيضاً',
                        style: AppType.subtitle(color: AppColors.textHi)),
                  ),
                ],
                const SizedBox(height: Sp.xs),
                Text('سيصل الآن: $willSend',
                    style: AppType.bodyStrong(color: AppColors.brand)),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('إلغاء'),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text('إرسال',
                    style: TextStyle(color: AppColors.brand)),
              ),
            ],
          );
        },
      ),
    );
    if (ok == true) _includeHighRisk = include;
    return ok;
  }

  Future<bool?> _confirmDialog(
    String title,
    String message, {
    required String confirmLabel,
    required Color confirmColor,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(title,
            style:
                AppType.title(color: AppColors.textHi).copyWith(fontSize: 16)),
        content:
            Text(message, style: AppType.subtitle(color: AppColors.textMid)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(confirmLabel, style: TextStyle(color: confirmColor)),
          ),
        ],
      ),
    );
  }

  void _snack(String msg, {required bool isError}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? AppColors.error : AppColors.brand,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ─── UI ────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: deskPageBar(
        context,
        mobile: AppBar(
          backgroundColor: AppColors.surface,
          elevation: 0,
          centerTitle: true,
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.bell, size: 16, color: AppColors.brand),
              const SizedBox(width: 6),
              Text(
                'التبليغات',
                style:
                    AppType.title(color: AppColors.textHi).copyWith(fontSize: 16),
              ),
            ],
          ),
          iconTheme: IconThemeData(color: AppColors.textHi),
        ),
      ),
      body: MergedSectionBody(child: _viewOnly
          ? _viewOnlyBody()
          : _loading
          ? const Center(child: CircularProgressIndicator())
          : DesktopScope.of(context)
              ? _desktopBody()
              : Column(
              children: [
                Expanded(
                  child: RefreshIndicator(
                    color: AppColors.brand,
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(
                          Sp.lg, Sp.md, Sp.lg, Sp.huge),
                      children: [
                        _toolsRow(),
                        const SizedBox(height: Sp.md),
                        if (_big) ...[
                          _bigNotice(),
                          const SizedBox(height: Sp.md),
                        ],
                        _buildFilterCard(),
                        // فلتر مدير فرعي — يظهر فقط لو المدير الرئيسي
                        // عنده مدراء تحته (matches SendScopePanel visibility).
                        if ((_subManagers ?? const []).isNotEmpty) ...[
                          const SizedBox(height: Sp.md),
                          _buildManagerFilterCard(),
                        ],
                        const SizedBox(height: Sp.md),
                        _buildScopeCard(),
                        if (_scope == _Scope.specific &&
                            (_candidates.isNotEmpty || _big)) ...[
                          const SizedBox(height: Sp.md),
                          _buildSelectionCard(),
                        ],
                        const SizedBox(height: Sp.md),
                        _buildChannelCard(),
                        const SizedBox(height: Sp.md),
                        _buildMessageCard(),
                      ],
                    ),
                  ),
                ),
                _buildActionBar(),
              ],
            )),
    );
  }

  /// الحاسبة: عمودان — الجمهور (الفئة، المدير، النطاق، الاختيار) يميناً، والقناة والرسالة يساراً،
  /// وشريط الإرسال تحتهما — بدل عمودٍ واحدٍ ممدود تتضخّم فيه بطاقات الفئة.
  Widget _desktopBody() {
    Widget col(List<Widget> children) => ListView(
          padding: const EdgeInsets.only(bottom: Sp.lg),
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(height: Sp.md),
              children[i],
            ],
          ],
        );
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.xs, Sp.lg, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 5,
                  child: col([
                    if (_big) _bigNotice(),
                    _buildFilterCard(),
                    if ((_subManagers ?? const []).isNotEmpty) _buildManagerFilterCard(),
                    _buildScopeCard(),
                    if (_scope == _Scope.specific && (_candidates.isNotEmpty || _big))
                      _buildSelectionCard(),
                  ]),
                ),
                const SizedBox(width: Sp.lg),
                Expanded(
                  flex: 6,
                  child: col([_buildChannelCard(), _buildMessageCard()]),
                ),
              ],
            ),
          ),
        ),
        _buildActionBar(),
      ],
    );
  }

  Widget _buildChannelCard() {
    final options = [
      (
        value: 'auto',
        label: 'تلقائي',
        icon: LucideIcons.split,
        color: AppColors.brand,
        hint: 'يحترم ربط المشترك (تلغرام لو مربوط، وإلا واتساب)',
      ),
      (
        value: 'whatsapp',
        label: 'واتساب فقط',
        icon: LucideIcons.messageCircle,
        color: AppColors.channelWhatsApp,
        hint: 'يجبر الواتساب حتى للمربوطين بتلغرام',
      ),
      (
        value: 'telegram',
        label: 'تلغرام فقط',
        icon: LucideIcons.send,
        color: AppColors.channelTelegram,
        hint: 'يجبر تلغرام — يتخطّى غير المربوطين',
      ),
    ];
    return _sectionCard(
      icon: LucideIcons.split,
      title: 'قناة الإرسال',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (int i = 0; i < options.length; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                Expanded(
                  child: _channelChoice(
                    label: options[i].label,
                    icon: options[i].icon,
                    color: options[i].color,
                    selected: _forceChannel == options[i].value,
                    onTap: () =>
                        setState(() => _forceChannel = options[i].value),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Text(
            options.firstWhere((o) => o.value == _forceChannel).hint,
            style: AppType.muted().copyWith(fontSize: 10.5, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _channelChoice({
    required String label,
    required IconData icon,
    required Color color,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(R.sm),
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color:
              selected ? color.withValues(alpha: 0.14) : AppColors.surfaceInput,
          borderRadius: BorderRadius.circular(R.sm),
          border: Border.all(
            color: selected ? color : AppColors.border,
            width: selected ? 1 : 0.5,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: selected ? color : AppColors.textMid),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                style: AppType.labelBold(color: selected ? color : AppColors.textMid),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Sections ─────────────────────────────

  /// الحساب الكبير: ما يختلف هنا ولماذا — بلا «تعذّر» ولا قائمةٍ فارغة صامتة.
  Widget _bigNotice() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.warningSoftBg,
        borderRadius: BorderRadius.circular(R.sm),
        border: Border.all(color: AppColors.warningSoftBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.info, size: 14, color: AppColors.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'حسابك كبير ($_bigTotal مشترك): «عام» يرسل للفئة كلّها — يجهّزها الخادم في الخلفيّة ويصلك إشعارٌ بالنتيجة. '
              '«محدّد»: ابحث واختر حتى $_kBigMaxTargets مشترك في المرّة.'
              '${_dfAvailable ? ' و«المدينون» بالتحديد: من يطابق يُحسب في الخلفيّة، والإرسال لمن تراهم ولا يزالون يطابقون.' : ''}',
              style: AppType.body(color: AppColors.textBody).copyWith(fontSize: 12.5, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  /// أدوات ما بعد الإرسال (الهاتف): ثلاث بطاقاتٍ بأسمائها أعلى الشاشة — كانت أيقوناتٍ بلا كلمات في شريط الإرسال.
  Widget _toolsRow() {
    Widget tile(IconData icon, String label, ListTone tone, VoidCallback? onTap, {bool busy = false, Key? key}) => Expanded(
          child: Material(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(R.lg),
            child: InkWell(
              key: key,
              onTap: onTap,
              borderRadius: BorderRadius.circular(R.lg),
              child: Container(
                constraints: const BoxConstraints(minHeight: 64),
                padding: const EdgeInsets.symmetric(horizontal: Sp.xs, vertical: Sp.sm),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(R.lg),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    busy
                        ? const SizedBox(width: 30, height: 30, child: Padding(padding: EdgeInsets.all(6), child: CircularProgressIndicator(strokeWidth: 2)))
                        : ListIconBox(icon: icon, tone: tone, size: 30),
                    const SizedBox(height: Sp.xs),
                    Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.labelBold(color: AppColors.textBody)),
                  ],
                ),
              ),
            ),
          ),
        );
    return Row(children: [
      tile(LucideIcons.history, 'حالة الإرسال', ListTone.info, _openLogs, key: const ValueKey('broadcast-tool-logs')),
      const SizedBox(width: Sp.sm),
      tile(LucideIcons.listChecks, 'الحملات', ListTone.brand, _openCampaigns, key: const ValueKey('broadcast-tool-campaigns')),
      const SizedBox(width: Sp.sm),
      tile(LucideIcons.rotateCw, 'إعادة الفاشلة', ListTone.warning, _retrying ? null : _retryFailed,
          busy: _retrying, key: const ValueKey('broadcast-tool-retry')),
    ]);
  }

  Widget _buildFilterCard() {
    final counts = _counts;
    return _sectionCard(
      icon: LucideIcons.users,
      title: 'لمن ترسل؟',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GridView(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              // ارتفاعٌ ثابت (لا نسبة): البطاقة لا تتضخّم مع عرض العمود في الحاسبة.
              mainAxisExtent: 64,
            ),
            shrinkWrap: true,
            // بلا حشوة MediaQuery (يرثها GridView داخل القائمة فيُلحق فراغاً تحت البطاقات)
            padding: EdgeInsets.zero,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _filterChip(_Filter.all, 'كل المشتركين', LucideIcons.users, counts[_Filter.all] ?? 0, ListTone.brand),
              _filterChip(_Filter.debtors, 'المدينون', LucideIcons.wallet, counts[_Filter.debtors] ?? 0, ListTone.warning),
              _filterChip(_Filter.expired, 'منتهي الصلاحية', LucideIcons.clock, counts[_Filter.expired] ?? 0, ListTone.danger),
              _filterChip(_Filter.expiring, 'قرب الانتهاء (3 أيام)', LucideIcons.triangleAlert, counts[_Filter.expiring] ?? 0,
                  ListTone.info),
            ],
          ),
          if (_filter == _Filter.debtors && _big && _dfCap != null && !_dfCap!.bigAsync) ...[
            const SizedBox(height: Sp.sm),
            _note(LucideIcons.funnel, 'تحديد المدينين بعمر الدين ومبلغه غير متاحٍ للحسابات الكبيرة — أرسل للمدينين كلّهم أو اختر بالبحث.'),
          ],
          if (_filter == _Filter.debtors && _dfAvailable) ...[
            const SizedBox(height: Sp.md),
            _debtFilterPanel(),
          ],
          if (_candidates.isEmpty && !_debtFilterOn) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.warningSoftBg,
                borderRadius: BorderRadius.circular(R.sm),
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.triangleAlert, size: 12, color: AppColors.warning),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'لا يوجد مشتركون يطابقون الفئة (يحتاجون أرقام هواتف صالحة)',
                      maxLines: 2,
                      style: AppType.muted().copyWith(fontSize: 10.5, color: AppColors.warning),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _note(IconData icon, String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(color: AppColors.surfaceSunken, borderRadius: BorderRadius.circular(R.sm)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 14, color: AppColors.textMid),
            const SizedBox(width: 6),
            Expanded(child: Text(text, maxLines: 3, style: AppType.micro(color: AppColors.textMid).copyWith(height: 1.5))),
          ],
        ),
      );

  Widget _filterChip(_Filter f, String label, IconData icon, int count, ListTone tone) {
    final active = _filter == f;
    return Material(
      color: active ? tone.soft : AppColors.surface,
      borderRadius: BorderRadius.circular(R.md),
      child: InkWell(
        onTap: () => _selectFilter(f),
        borderRadius: BorderRadius.circular(R.md),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            border: Border.all(color: active ? tone.softBorder : AppColors.border, width: active ? BW.selected : BW.normal),
            borderRadius: BorderRadius.circular(R.md),
          ),
          child: Row(
            children: [
              ListIconBox(icon: icon, tone: tone, size: 32),
              const SizedBox(width: Sp.sm),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      count < 0 ? '—' : count.toString(),
                      maxLines: 1,
                      style: AppType.statValue(color: active ? tone.fg : AppColors.textHi).copyWith(fontSize: 16),
                    ),
                    Text(
                      label,
                      style: AppType.micro(color: active ? tone.fg : AppColors.textMid),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// لوحة «تحديد المدينين»: عمر أقدم دينٍ لم يُسدَّد و/أو مبلغ الدين — اختياريّان، والنتيجة من الخادم تحتهما.
  Widget _debtFilterPanel() => DebtFilterPanel(
        cap: _dfCap!,
        value: _df,
        onChanged: _setDebtFilter,
        busy: _dfPreviewBusy,
        pendingText: _dfPending,
        error: _dfPreviewError,
        preview: _dfPreview,
        onRetry: _schedulePreview,
      );

  /// كارت فلتر المدير الفرعي — يظهر فقط لمن عنده مدراء فرعيون.
  /// التحديد فارغ = بدون قيد (كل المدراء).
  Widget _buildManagerFilterCard() {
    final mgrs = _subManagers ?? const <String>[];
    final allSelected = _managerFilter.isEmpty;
    return _sectionCard(
      icon: LucideIcons.userCog,
      title: allSelected
          ? 'الفلترة حسب المدير (الكل)'
          : 'الفلترة حسب المدير (${_managerFilter.length}/${mgrs.length})',
      trailing: allSelected
          ? null
          : TextButton.icon(
              onPressed: () {
                setState(() {
                  _managerFilter.clear();
                  _selected.clear();
                });
              },
              icon: Icon(LucideIcons.x, size: 12, color: AppColors.textMid),
              label: Text(
                'مسح',
                style: AppType.button(color: AppColors.textMid)
                    .copyWith(fontSize: 11),
              ),
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 30),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'اختر مدراء لإرسال الرسائل لمشتركيهم فقط',
            style: AppType.muted().copyWith(fontSize: 10.5),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final u in mgrs)
                _managerFilterChip(
                  username: u,
                  checked: _managerFilter.contains(u),
                  onToggle: (nowChecked) {
                    setState(() {
                      if (nowChecked) {
                        _managerFilter.add(u);
                      } else {
                        _managerFilter.remove(u);
                      }
                      _selected.clear(); // تنظيف الاختيار المحدَّد اليدوي
                    });
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _managerFilterChip({
    required String username,
    required bool checked,
    required ValueChanged<bool> onToggle,
  }) {
    return Material(
      color: checked ? AppColors.brandSoftBg : AppColors.surfaceInput,
      borderRadius: BorderRadius.circular(R.sm),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => onToggle(!checked),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            border: Border.all(
              color: checked ? AppColors.brandSoftBorder : AppColors.border,
              width: checked ? 1.4 : 1,
            ),
            borderRadius: BorderRadius.circular(R.sm),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                checked ? LucideIcons.squareCheck : LucideIcons.square,
                size: 12,
                color: checked ? AppColors.brand : AppColors.textLow,
              ),
              const SizedBox(width: 4),
              Text(
                username,
                style: AppType.button(
                  color: checked ? AppColors.brand : AppColors.textMid,
                ).copyWith(fontSize: 10.5),
                textDirection: TextDirection.ltr,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScopeCard() {
    final allLabel = _debtFilterOn
        ? (_dfPreview == null ? 'الكلّ' : 'الكلّ (${_dfPreview!.audience})')
        : _big
            ? 'الفئة كلّها'
            : 'الكلّ (${_candidates.length})';
    return _sectionCard(
      icon: LucideIcons.layers,
      title: 'نطاق الإرسال',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetSegmented(
            labels: [allLabel, _selected.isEmpty ? 'أختار بنفسي' : 'أختار بنفسي (${_selected.length})'],
            icons: const [LucideIcons.layers, LucideIcons.userCheck],
            selectedIndex: _scope == _Scope.all ? 0 : 1,
            onSelect: (i) => setState(() => _scope = i == 0 ? _Scope.all : _Scope.specific),
          ),
          if (_big && _scope == _Scope.all) ...[
            const SizedBox(height: 6),
            Text(
              _debtFilterOn
                  ? 'يُجهَّز في الخلفيّة على أحدث الديون — لمن تراهم ولا يزالون يطابقون'
                  : 'الفئة كلّها — يجهّزها الخادم في الخلفيّة',
              style: AppType.micro(color: AppColors.textMid),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSelectionCard() {
    if (_debtFilterOn) return _buildFilteredSelectionCard();
    final visible = _visibleCandidates;
    final allSelected = visible.isNotEmpty &&
        visible.every((s) => _selected.contains(s.username));
    return _sectionCard(
      icon: LucideIcons.userCheck,
      title: _big
          ? 'اختيار المشتركين (${_selected.length} مختار)'
          : 'اختيار المشتركين (${_selected.length}/${_candidates.length})',
      trailing: TextButton.icon(
        onPressed: _toggleSelectAllVisible,
        icon: Icon(
          allSelected ? LucideIcons.square : LucideIcons.squareCheck,
          size: 14,
          color: AppColors.brand,
        ),
        label: Text(
          allSelected ? 'إلغاء الكل' : 'تحديد الكل',
          style: AppType.button(color: AppColors.brand).copyWith(fontSize: 11),
        ),
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 30),
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ),
      ),
      child: Column(
        children: [
          // Search
          TextField(
            controller: _search,
            onChanged: (q) {
              setState(() {});
              if (_big) _bigSearch.search(q, onRows: _setBigRows);
            },
            decoration: InputDecoration(
              hintText: 'ابحث بالاسم أو الهاتف…',
              hintStyle: AppType.muted().copyWith(fontSize: 12.5),
              prefixIcon:
                  Icon(LucideIcons.search, size: 14, color: AppColors.textMid),
              filled: true,
              fillColor: AppColors.surfaceInput,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(R.sm),
                borderSide: BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(R.sm),
                borderSide: BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(R.sm),
                borderSide: BorderSide(color: AppColors.brand),
              ),
            ),
            style:
                AppType.input(color: AppColors.textHi).copyWith(fontSize: 13),
          ),
          const SizedBox(height: 8),
          if (visible.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'لا نتائج',
                style: AppType.muted().copyWith(fontSize: 12.5),
                textAlign: TextAlign.center,
              ),
            )
          else
            Container(
              constraints: const BoxConstraints(maxHeight: 320),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(R.sm),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(R.sm),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: visible.length,
                  separatorBuilder: (_, __) =>
                      Divider(height: 1, color: AppColors.border),
                  itemBuilder: (_, i) => _candidateTile(visible[i]),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// الاختيار بالتحديد: من قائمة المعاينة نفسها (الخادم حسب عمر أقدم دينٍ لم يُسدَّد) — الاسم والدين والعمر أو «دين قديم».
  Widget _buildFilteredSelectionCard() {
    final q = _search.text.trim().toLowerCase();
    final rows = (_dfPreview?.rows ?? const <BroadcastPreviewRow>[])
        .where((r) => q.isEmpty || r.username.toLowerCase().contains(q) || (r.name ?? '').toLowerCase().contains(q))
        .toList();
    final allSelected = rows.isNotEmpty && rows.every((r) => _selected.contains(r.username));
    return _sectionCard(
      icon: LucideIcons.userCheck,
      title: 'اختيار المدينين (${_pickedFromPreview.length}/${_dfPreview?.audience ?? 0})',
      trailing: TextButton(
        onPressed: rows.isEmpty
            ? null
            : () => setState(() {
                  if (allSelected) {
                    for (final r in rows) {
                      _selected.remove(r.username);
                    }
                  } else {
                    for (final r in rows) {
                      // الحساب الكبير: حتى $_kBigMaxTargets في المرّة (بحثٌ لكلٍّ منهم في الخادم)
                      if (_big && _selected.length >= _kBigMaxTargets) break;
                      _selected.add(r.username);
                    }
                  }
                }),
        child: Text(allSelected ? 'إلغاء الكل' : 'تحديد الكل', style: AppType.button(color: AppColors.brand).copyWith(fontSize: 11)),
      ),
      child: Column(
        children: [
          ListSearchField(controller: _search, hint: 'ابحث بالاسم أو اليوزر', onChanged: (_) => setState(() {})),
          const SizedBox(height: 8),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(_dfPreviewBusy ? 'يحسب من يطابق…' : 'لا أحد يطابق', style: AppType.muted().copyWith(fontSize: 12.5)),
            )
          else
            Container(
              constraints: const BoxConstraints(maxHeight: 360),
              decoration: BoxDecoration(border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(R.md)),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(R.md),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => Divider(height: 1, color: AppColors.border),
                  itemBuilder: (_, i) {
                    final r = rows[i];
                    return ListSubscriberRow(
                      key: ValueKey('df-row-${r.username}'),
                      title: r.name ?? r.username,
                      subtitle: r.name == null ? '' : r.username,
                      subtitleLtr: true,
                      selectable: true,
                      selected: _selected.contains(r.username),
                      onTap: () => _toggleSelect(r.username),
                      trailing: _previewDebtCell(r),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _candidateTile(Subscriber s) {
    final isSel = _selected.contains(s.username);
    return InkWell(
      onTap: () => _toggleSelect(s.username),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        color: isSel ? AppColors.brandSoftBg : null,
        child: Row(
          children: [
            Icon(
              isSel ? LucideIcons.squareCheck : LucideIcons.square,
              size: 16,
              color: isSel ? AppColors.brand : AppColors.textLow,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    s.fullName,
                    style: AppType.title(color: AppColors.textHi)
                        .copyWith(fontSize: 12.5),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 1),
                  Row(
                    children: [
                      Text(
                        s.username,
                        style: AppType.muted().copyWith(fontSize: 10.5),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        width: 3,
                        height: 3,
                        decoration: BoxDecoration(
                          color: AppColors.textLow,
                          borderRadius: BorderRadius.circular(R.pill),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        s.phone ?? s.mobile ?? '',
                        style: AppType.muted().copyWith(fontSize: 10.5),
                        textDirection: TextDirection.ltr,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageCard() {
    return _sectionCard(
      icon: LucideIcons.messageSquare,
      title: 'الرسالة',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Variables strip
          Text('اضغط متغيّراً لإدراجه:',
              style: AppType.muted().copyWith(fontSize: 10.5)),
          const SizedBox(height: 6),
          SizedBox(
            height: 34,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: BroadcastVariables.all.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (_, i) {
                final v = BroadcastVariables.all[i];
                return Material(
                  color: AppColors.brandSoftBg,
                  borderRadius: BorderRadius.circular(R.pill),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => _insertVariable(v.token),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(LucideIcons.plus,
                              size: 11, color: AppColors.brand),
                          const SizedBox(width: 3),
                          Text(
                            v.label,
                            style: AppType.button(color: AppColors.brand)
                                .copyWith(fontSize: 10.5),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          // Textarea
          TextField(
            controller: _msg,
            focusNode: _msgFocus,
            maxLines: 6,
            minLines: 4,
            maxLength: 2000,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: _messageOptional
                  ? 'اختياري — يستخدم القالب التلقائي لو فاضي'
                  : 'اكتب الرسالة هنا…',
              hintStyle: AppType.muted().copyWith(fontSize: 12.5),
              filled: true,
              fillColor: AppColors.surfaceInput,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(R.sm),
                borderSide: BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(R.sm),
                borderSide: BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(R.sm),
                borderSide: BorderSide(color: AppColors.brand),
              ),
              counterText: '',
              contentPadding: const EdgeInsets.all(12),
            ),
            style: AppType.input(color: AppColors.textHi)
                .copyWith(fontSize: 13, height: 1.55),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  _messageOptional
                      ? 'لو فاضي، يُستخدم قالب افتراضي'
                      : 'المتغيرات تُستبدل تلقائياً لكل مشترك',
                  style: AppType.muted().copyWith(fontSize: 10.5),
                ),
              ),
              Text(
                '${_msg.text.length} / 2000',
                style: AppType.muted().copyWith(
                  fontSize: 10.5,
                  fontFamily: AppType.family,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buildImageAttachment(),
        ],
      ),
    );
  }

  Widget _buildImageAttachment() {
    if (_imageBytes == null) {
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: OutlinedButton.icon(
          onPressed: _sending ? null : _pickImage,
          icon: Icon(LucideIcons.image, size: 16, color: AppColors.brand),
          label: Text(
            'إرفاق صورة (اختياري)',
            style:
                AppType.button(color: AppColors.brand).copyWith(fontSize: 12.5),
          ),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: AppColors.brandSoftBorder),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(R.sm)),
          ),
        ),
      );
    }
    final sizeKb = (_imageBytes!.length / 1024).round();
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.surfaceInput,
        borderRadius: BorderRadius.circular(R.sm),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(R.sm),
            child: Image.memory(
              _imageBytes!,
              width: 56,
              height: 56,
              // 2026-08-28 (Google 2027): cacheWidth/Height يفكّ الصورة
              // بأبعاد thumbnail (56×2×DPR ≈ 112) بدل الأصل 1024×1024
              // → ~4MB في imageCache تصبح ~50KB.
              cacheWidth: 112,
              cacheHeight: 112,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _imageName ?? 'صورة مرفقة',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.subtitle(color: AppColors.textHi)
                      .copyWith(fontSize: 12.5),
                ),
                const SizedBox(height: 2),
                Text(
                  '$sizeKb KB',
                  style: AppType.muted().copyWith(fontSize: 10.5),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'حذف الصورة',
            icon: Icon(LucideIcons.x, size: 18, color: AppColors.textMid),
            onPressed: _sending ? null : _removeImage,
          ),
        ],
      ),
    );
  }

  Widget _buildActionBar() {
    final desk = DesktopScope.of(context);
    final count = _bigAll
        ? '${(_counts[_filter] ?? -1) < 0 ? '—' : _counts[_filter]} مشترك'
        : _debtFilterOn
            ? (_scope == _Scope.all
                ? (_dfPreviewBusy || _dfPreview == null ? '… مشترك' : '${_dfPreview!.count} مشترك')
                : '${_pickedFromPreview.length} مشترك')
            : '${_targets.length} مشترك';
    return Container(
      padding: const EdgeInsets.fromLTRB(Sp.lg, 10, Sp.lg, 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border, width: 1)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            // count
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _debtFilterOn ? 'المدينون — بالتحديد' : (_scope == _Scope.all ? 'إرسال للكل' : 'إرسال للمحدّدين'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.muted().copyWith(fontSize: 10.5),
                  ),
                  Text(
                    count,
                    maxLines: 1,
                    style: AppType.title(color: AppColors.brand).copyWith(fontSize: 14),
                  ),
                ],
              ),
            ),
            // الحاسبة: الأدوات بجانب الإرسال كما كانت (الهاتف: بطاقاتٌ بأسمائها أعلى الشاشة)
            if (desk) ...[
              IconButton(
                tooltip: 'حملات التبليغ',
                icon: Icon(LucideIcons.listChecks, size: 18, color: AppColors.brand),
                onPressed: _openCampaigns,
                style: IconButton.styleFrom(backgroundColor: AppColors.brandSoftBg),
              ),
              const SizedBox(width: 6),
              IconButton(
                tooltip: 'حالة الإرسال',
                icon: Icon(LucideIcons.history, size: 18, color: AppColors.brand),
                onPressed: _openLogs,
                style: IconButton.styleFrom(backgroundColor: AppColors.brandSoftBg),
              ),
              const SizedBox(width: 6),
              IconButton(
                tooltip: 'إعادة الفاشلة',
                icon: _retrying
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(LucideIcons.rotateCw, size: 18, color: AppColors.warning),
                onPressed: _retrying ? null : _retryFailed,
                style: IconButton.styleFrom(backgroundColor: AppColors.warningSoftBg),
              ),
              const SizedBox(width: 6),
            ],
            // send
            ElevatedButton.icon(
              key: const ValueKey('broadcast-send'),
              onPressed: _canSend ? _send : null,
              icon: (_sending || _checkingRisk)
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(AppColors.onBrand),
                      ),
                    )
                  : const Icon(LucideIcons.send, size: 16),
              label: Text(
                _checkingRisk
                    ? 'يفحص الأرقام...'
                    : (_sending ? 'جاري الإرسال...' : 'إرسال'),
                style: AppType.button(color: AppColors.onBrand)
                    .copyWith(fontSize: 14),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brand,
                foregroundColor: AppColors.onBrand,
                disabledBackgroundColor: AppColors.brandSoftBorder,
                minimumSize: const Size(0, 46),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.md)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// الدين وعمر أقدم دينٍ لم يُسدَّد («دين قديم» = أقدم من سجلّاتنا).
  Widget _previewDebtCell(BroadcastPreviewRow r) => ListAmountCell(
        amount: AmountShorthand.format(r.debt.round()).isEmpty ? '0' : AmountShorthand.format(r.debt.round()),
        amountColor: AppColors.warningOnSoft,
        badge: r.legacy ? 'دين قديم' : (r.days == null ? null : (r.days == 0 ? 'اليوم' : arDaysCount(r.days!))),
        badgeTone: r.legacy ? ListTone.info : ((r.days ?? 0) > 30 ? ListTone.danger : ListTone.warning),
      );

  Widget _sectionCard({
    required IconData icon,
    required String title,
    Widget? trailing,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(R.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 13, color: AppColors.brand),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: AppType.title(color: AppColors.textHi)
                      .copyWith(fontSize: 12.5),
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

/// ورقة تأكيد الإرسال بالتحديد — من معاينة الطلب نفسه: كم سيصلهم، ومن هم (الاسم والدين والعمر أو «دين قديم»)، وما استُبعد ولماذا.
/// تُرجع includeHighRisk (true/false) عند التأكيد، وnull عند الرجوع.
class _FilteredConfirmSheet extends StatefulWidget {
  const _FilteredConfirmSheet({
    required this.preview,
    required this.summary,
    required this.channel,
    required this.includeHighRisk,
    this.bigBackground = false,
  });
  final BroadcastPreview preview;
  final String summary;
  final String channel;
  final bool includeHighRisk;

  /// الحساب الكبير «الكلّ»: يُجهَّز في الخلفيّة على أحدث الديون، لمن رآهم المدير ولا يزالون يطابقون.
  final bool bigBackground;

  @override
  State<_FilteredConfirmSheet> createState() => _FilteredConfirmSheetState();
}

class _FilteredConfirmSheetState extends State<_FilteredConfirmSheet> {
  late bool _include = widget.includeHighRisk;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final pv = widget.preview;
    final willSend = pv.count + (_include ? pv.excludedHighRisk : 0);
    final notes = <String>[
      if (pv.legacy > 0) '${pv.legacy} عليهم «دين قديم» (أقدم من سجلّاتنا) — مشمولون بأيّ عمر',
      if (pv.unknownAge > 0)
        pv.ageUnsupported ? 'عمر الدين غير معروف لهذه الشركة — ${pv.unknownAge} لم يُشملوا' : '${pv.unknownAge} بلا عمر دينٍ معروف — لم يُشملوا',
      if (pv.deduped > 0) '${pv.deduped} يتشاركون رقماً — رسالةٌ واحدة لكلّ رقم',
      if (pv.missing > 0) '${pv.missing} من المختارين لم يعودوا في القائمة',
      if (pv.partial) 'تعذّر جلب كلّ المشتركين — من لم يُجلب لا يصله',
      if (widget.channel == 'telegram') 'تلغرام وحده: يصل لمن ربط حسابه من هؤلاء',
      if (widget.bigBackground)
        'حسابٌ كبير: يُجهَّز الإرسال في الخلفيّة على أحدث الديون، ويصل لمن تراهم هنا ولا يزالون يطابقون — ويصلك إشعارٌ بالعدد',
    ];
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.send,
        title: 'تأكيد الإرسال',
        subtitle: 'المدينون — بالتحديد',
        onClose: () => Navigator.of(context).pop(),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // الجملة كاملةً هنا (سطر الرأس واحدٌ يقطعها)
          Text(widget.summary, style: AppType.body(color: AppColors.textBody)),
          const SizedBox(height: Sp.sm),
          Container(
            padding: const EdgeInsets.all(Sp.md),
            decoration: BoxDecoration(
              color: AppColors.brandSoftBg,
              borderRadius: BorderRadius.circular(R.md),
              border: Border.all(color: AppColors.brandSoftBorder),
            ),
            child: Row(children: [
              const ListIconBox(icon: LucideIcons.send, tone: ListTone.brand, size: 40),
              const SizedBox(width: Sp.md),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('$willSend', style: AppType.statValue(color: AppColors.brand).copyWith(fontSize: 24)),
                  Text('سيصلهم التبليغ', maxLines: 1, style: AppType.micro(color: AppColors.textMid)),
                ]),
              ),
            ]),
          ),
          if (pv.excludedHighRisk > 0) ...[
            const SizedBox(height: Sp.sm),
            Container(
              padding: const EdgeInsets.all(Sp.sm),
              decoration: BoxDecoration(
                color: AppColors.dangerSoftBg,
                borderRadius: BorderRadius.circular(R.sm),
                border: Border.all(color: AppColors.dangerSoftBorder),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('منهم ${pv.excludedHighRisk} تجاهلوا رسائل كثيرة بلا ردّ — يُستبعدون افتراضيّاً حمايةً لرقمك.',
                    style: AppType.subtitle(color: AppColors.error)),
                // Material شفّافةٌ خاصّة: الصندوق الملوّن فوقها كان يخفي تموّج اللمس (تحذير ListTile في وضع التطوير)
                Material(
                  type: MaterialType.transparency,
                  child: SwitchListTile(
                    key: const ValueKey('df-include-risk'),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    value: _include,
                    activeThumbColor: AppColors.error,
                    onChanged: (v) => setState(() => _include = v),
                    title: Text('أرسل لهم أيضاً', style: AppType.subtitle(color: AppColors.textHi)),
                  ),
                ),
              ]),
            ),
          ],
          if (notes.isNotEmpty) ...[
            const SizedBox(height: Sp.sm),
            for (final n in notes)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Padding(padding: const EdgeInsets.only(top: 6), child: Icon(LucideIcons.dot, size: 12, color: AppColors.textMid)),
                  const SizedBox(width: 4),
                  Expanded(child: Text(n, maxLines: 3, style: AppType.micro(color: AppColors.textMid).copyWith(height: 1.5))),
                ]),
              ),
          ],
          const SizedBox(height: Sp.sm),
          Container(
            decoration: BoxDecoration(border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(R.md)),
            child: Column(children: [
              for (var i = 0; i < pv.rows.length; i++) ...[
                if (i > 0) Divider(height: 1, color: AppColors.border),
                ListSubscriberRow(
                  title: pv.rows[i].name ?? pv.rows[i].username,
                  subtitle: pv.rows[i].name == null ? '' : pv.rows[i].username,
                  subtitleLtr: true,
                  selectable: false,
                  selected: false,
                  trailing: ListAmountCell(
                    amount: AmountShorthand.format(pv.rows[i].debt.round()).isEmpty ? '0' : AmountShorthand.format(pv.rows[i].debt.round()),
                    amountColor: AppColors.warningOnSoft,
                    badge: pv.rows[i].legacy
                        ? 'دين قديم'
                        : (pv.rows[i].days == null ? null : (pv.rows[i].days == 0 ? 'اليوم' : arDaysCount(pv.rows[i].days!))),
                    badgeTone: pv.rows[i].legacy ? ListTone.info : ((pv.rows[i].days ?? 0) > 30 ? ListTone.danger : ListTone.warning),
                  ),
                ),
              ],
            ]),
          ),
          if (pv.truncated) ...[
            const SizedBox(height: Sp.xs),
            Text('تُعرض أوّل ${pv.rows.length} — والإرسال للجميع (${pv.audience})',
                textAlign: TextAlign.center, style: AppType.micro(color: AppColors.textMid)),
          ],
        ],
      ),
      footer: SheetFooterBar(
        label: 'إرسال إلى $willSend',
        icon: LucideIcons.send,
        enabled: willSend > 0,
        onPressed: () => Navigator.of(context).pop(_include),
      ),
    );
  }
}
