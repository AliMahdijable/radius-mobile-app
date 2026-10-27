
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
import '../message_logs/message_logs_screen.dart';
import 'broadcast_campaigns_screen.dart';
import '../desktop/desk_widgets.dart';
import '../../core/platform/desktop_layout.dart';

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

class _BroadcastScreenState extends State<BroadcastScreen> {
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

  @override
  void initState() {
    super.initState();
    _load();
    _loadScope();
  }

  Future<void> _loadScope() async {
    final s = await SendScopeApi.fetch();
    if (!mounted) return;
    setState(() => _subManagers = s?.subManagers ?? const []);
  }

  @override
  void dispose() {
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
      (_bigAll || _targets.isNotEmpty) &&
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
    });
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
      targetUsernames: _scope == _Scope.specific
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
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const BroadcastCampaignsScreen()),
    );
  }

  void _openLogs() {
    // نفتح الشاشة الكاملة بدل الورقة السفلية — تدعم كل الأنواع + بحث +
    // فلاتر + auto-refresh للـpending، وأي رسالة بعثتها الآن رح تظهر
    // مباشرةً بحالة "انتظار" ثم تتحول لـ"أُرسلت" تلقائياً.
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const MessageLogsScreen(),
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
      body: _loading
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
            ),
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
              '«محدّد»: ابحث واختر حتى $_kBigMaxTargets مشترك في المرّة.',
              style: AppType.body(color: AppColors.textBody).copyWith(fontSize: 12.5, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterCard() {
    final counts = _counts;
    return _sectionCard(
      icon: LucideIcons.users,
      title: 'الفئة',
      child: Column(
        children: [
          GridView(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              // الحاسبة: ارتفاعٌ ثابت — النسبة تضخّم البطاقة مع عرض العمود.
              childAspectRatio: 2.6,
              mainAxisExtent: DesktopScope.of(context) ? 76 : null,
            ),
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _filterChip(_Filter.all, 'كل المشتركين', LucideIcons.users,
                  counts[_Filter.all] ?? 0, AppColors.brand),
              _filterChip(_Filter.debtors, 'المدينون', LucideIcons.wallet,
                  counts[_Filter.debtors] ?? 0, AppColors.error),
              _filterChip(_Filter.expired, 'منتهي الصلاحية', LucideIcons.clock,
                  counts[_Filter.expired] ?? 0, AppColors.error),
              _filterChip(
                  _Filter.expiring,
                  'قرب الانتهاء (3 أيام)',
                  LucideIcons.triangleAlert,
                  counts[_Filter.expiring] ?? 0,
                  AppColors.warning),
            ],
          ),
          if (_candidates.isEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.warningSoftBg,
                borderRadius: BorderRadius.circular(R.sm),
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.triangleAlert,
                      size: 12, color: AppColors.warning),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'لا يوجد مشتركون يطابقون الفئة (يحتاجون أرقام هواتف صالحة)',
                      style: AppType.muted()
                          .copyWith(fontSize: 10.5, color: AppColors.warning),
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

  Widget _filterChip(
      _Filter f, String label, IconData icon, int count, Color color) {
    final active = _filter == f;
    return Material(
      color: active ? color.withValues(alpha: 0.1) : AppColors.surface,
      borderRadius: BorderRadius.circular(R.sm),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _selectFilter(f),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(
              color: active ? color.withValues(alpha: 0.4) : AppColors.border,
              width: active ? 1.4 : 1,
            ),
            borderRadius: BorderRadius.circular(R.sm),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Icon(icon,
                      size: 14, color: active ? color : AppColors.textMid),
                  Text(
                    count < 0 ? '—' : count.toString(),
                    style:
                        AppType.title(color: active ? color : AppColors.textHi)
                            .copyWith(fontSize: 13),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: AppType.muted().copyWith(
                    fontSize: 10.5, color: active ? color : AppColors.textMid),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

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
    return _sectionCard(
      icon: LucideIcons.layers,
      title: 'نطاق الإرسال',
      child: Row(
        children: [
          Expanded(
            child: _scopeChip(
              _Scope.all,
              icon: LucideIcons.layers,
              title: 'عام',
              subtitle: _big ? 'كلّ الفئة — يُجهَّز في الخلفيّة' : 'للكل (${_candidates.length})',
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _scopeChip(
              _Scope.specific,
              icon: LucideIcons.userCheck,
              title: 'محدّد',
              subtitle: _selected.isEmpty
                  ? 'اختر يدوياً'
                  : '${_selected.length} مختار',
            ),
          ),
        ],
      ),
    );
  }

  Widget _scopeChip(_Scope s,
      {required IconData icon,
      required String title,
      required String subtitle,
      bool enabled = true}) {
    final active = _scope == s;
    return Material(
      color: active ? AppColors.brandSoftBg : AppColors.surface,
      borderRadius: BorderRadius.circular(R.sm),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? () => setState(() => _scope = s) : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            border: Border.all(
              color: active ? AppColors.brandSoftBorder : AppColors.border,
              width: active ? 1.4 : 1,
            ),
            borderRadius: BorderRadius.circular(R.sm),
          ),
          child: Row(
            children: [
              Icon(icon,
                  size: 14,
                  color: active ? AppColors.brand : AppColors.textMid),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: AppType.title(color: AppColors.textHi)
                          .copyWith(fontSize: 12.5),
                    ),
                    Text(
                      subtitle,
                      style: AppType.muted().copyWith(fontSize: 10.5),
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

  Widget _buildSelectionCard() {
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
                    _scope == _Scope.all ? 'إرسال للكل' : 'إرسال للمحدّدين',
                    style: AppType.muted().copyWith(fontSize: 10.5),
                  ),
                  Text(
                    _bigAll
                        ? '${(_counts[_filter] ?? -1) < 0 ? '—' : _counts[_filter]} مشترك'
                        : '${_targets.length} مشترك',
                    style: AppType.title(color: AppColors.brand)
                        .copyWith(fontSize: 14),
                  ),
                ],
              ),
            ),
            // الحملات: إيقاف/استئناف/حذف ما أُرسل من بثٍّ يمشي على مدى وقت
            IconButton(
              tooltip: 'حملات التبليغ',
              icon: Icon(LucideIcons.listChecks, size: 18, color: AppColors.brand),
              onPressed: _openCampaigns,
              style: IconButton.styleFrom(
                backgroundColor: AppColors.brandSoftBg,
              ),
            ),
            const SizedBox(width: 6),
            // logs
            IconButton(
              tooltip: 'حالة الإرسال',
              icon: Icon(LucideIcons.history, size: 18, color: AppColors.brand),
              onPressed: _openLogs,
              style: IconButton.styleFrom(
                backgroundColor: AppColors.brandSoftBg,
              ),
            ),
            const SizedBox(width: 6),
            // retry failed
            IconButton(
              tooltip: 'إعادة الفاشلة',
              icon: _retrying
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(LucideIcons.rotateCw,
                      size: 18, color: AppColors.warning),
              onPressed: _retrying ? null : _retryFailed,
              style: IconButton.styleFrom(
                backgroundColor: AppColors.warningSoftBg,
              ),
            ),
            const SizedBox(width: 6),
            // send
            ElevatedButton.icon(
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
                  : const Icon(LucideIcons.send, size: 14),
              label: Text(
                _checkingRisk
                    ? 'يفحص الأرقام...'
                    : (_sending ? 'جاري الإرسال...' : 'إرسال'),
                style: AppType.button(color: AppColors.onBrand)
                    .copyWith(fontSize: 13),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brand,
                foregroundColor: AppColors.onBrand,
                disabledBackgroundColor: AppColors.brandSoftBorder,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(R.sm)),
              ),
            ),
          ],
        ),
      ),
    );
  }

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
