import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../api/big_subscribers_api.dart';
import '../../api/debts_import_api.dart';
import '../../api/deleted_debts_api.dart';
import '../../api/subscribers_api.dart';
import '../../core/util/bidi.dart';
import '../../core/util/format.dart';
import '../../core/widgets/design_sheet.dart';
import '../../models/subscriber.dart';
import '../../services/debts_import/debts_match.dart';
import '../../services/debts_import/xlsx_lite.dart';
import '../../services/provider_service.dart';
import '../../services/subscriber_events.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../reports/v2/report_kit.dart';

/// «استيراد / تصدير الديون» بالتطبيق (٢٣ نوفمبر — المالك: «قسم استيراد وتصدير الديون اريد ينضاف مثل الويب للهاتف»): كالموقع
/// pages/DebtsImport.tsx — التصدير (المدينون، كلّ المشتركين، قالب) بملفّ Excel نفسه، والاستيراد من Excel/CSV بالاستبدال أو الإضافة،
/// والمطابقة باليوزر ثمّ الهاتف بقواعد الموقع حرفاً ([matchDebtRows])، ومعاينةٌ قبل التطبيق، والتطبيق دفعاتٍ (١٥) بتقدّمها، ونتيجةٌ
/// بأسباب ما لم يُطبَّق، و«غير موجود» ⇒ «ديون المحذوفين». لصاحب الحساب وحده (لا يُعرض للموظّف؛ الخادم يردّه OWNER_ONLY).
class DebtsImportScreen extends StatefulWidget {
  const DebtsImportScreen({super.key});

  static const title = 'استيراد / تصدير الديون';

  /// للاختبار: ملفٌّ يُختار بلا نافذة الاختيار.
  @visibleForTesting
  static Future<({String name, Uint8List bytes})?> Function()? debugPick;

  /// للاختبار: ما يُصدَّر (اسم الملفّ وبايتاته) بدل المشاركة.
  @visibleForTesting
  static Future<void> Function(String fileName, Uint8List bytes)? debugExport;

  @override
  State<DebtsImportScreen> createState() => _DebtsImportScreenState();
}

/// المشترك كما يحتاجه المطابِق — بهويّته (صفّان يصلان المشترك نفسه يُعرفان بالكائن نفسه).
class _Sub implements DebtMatchSub {
  _Sub(this.s);
  final Subscriber s;
  @override
  String get username => s.username;
  @override
  String? get phone => s.phone;
  @override
  String? get firstname => s.firstname;
  @override
  String? get lastname => s.lastname;

  /// الدين كما يكتبه الخادم في القائمة (`debt`) — كالموقع `sub.debt`.
  double get debt => s.debt ?? 0;
  bool get hasDebt => s.hasDebtFlag && (s.debt ?? 0) > 0;
  String get fullName => '${s.firstname} ${s.lastname}'.trim();
}

class _Parsed {
  _Parsed(this.row, this.m);
  final DebtFileRow row;
  final DebtMatchOut<_Sub> m;
  DebtMatchKind get kind => m.kind;
  _Sub? get sub => m.sub;
}

class _Progress {
  _Progress(this.total);
  final int total;
  int done = 0;
  List<String> current = const [];
  List<String> lastApplied = const [];
  int pending = 0;
}

class _DebtsImportScreenState extends State<DebtsImportScreen> {
  static const _chunk = 15;

  int? _bigTotal;
  List<_Sub>? _subs;
  String? _subsError;
  bool _loadingSubs = true;

  String _mode = 'set';
  String _fileName = '';
  List<_Parsed> _rows = const [];
  bool _applyReview = false;
  int _shown = 100;
  bool _reading = false;

  _Progress? _progress;
  DebtImportResult? _result;

  bool _deletedEnabled = false;
  DeletedImportResult? _deletedResult;
  List<({String name, double amount, String phone, String username})> _deletedSent = const [];
  bool _deletedBusy = false;

  bool get _busy => _progress != null;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    // الحساب الكبير (≥ ٥٠٠٠): المطابقة تحتاج القائمة الكاملة دفعةً — لا تُطلب (كالموقع)
    final big = await BigSubscribersApi.probe();
    if (!mounted) return;
    if (big > 0) {
      setState(() {
        _bigTotal = big;
        _loadingSubs = false;
      });
      return;
    }
    final subs = await SubscribersApi.loadAll();
    if (!mounted) return;
    setState(() {
      _loadingSubs = false;
      _subs = subs == null ? null : [for (final s in subs) _Sub(s)];
      _subsError = subs == null ? (SubscribersApi.lastListError ?? 'تعذّر جلب قائمة المشتركين') : null;
    });
    final dd = await DeletedDebtsApi.list();
    if (mounted) setState(() => _deletedEnabled = dd.page?.enabled == true);
  }

  void _say(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? AppColors.error : null,
      behavior: SnackBarBehavior.floating,
    ));
  }

  // ═══════════════ التصدير ═══════════════

  List<Object?> _sheetRow(_Sub s, Object? amount) => [
        s.s.username,
        amount,
        s.fullName,
        s.s.phone ?? '',
        s.s.profileName ?? '',
        s.s.expiration ?? '',
      ];

  /// الحالة نصّاً للملفّ (كالموقع statusText): معطَّل، منتهٍ (أيّامه سالبة أو انتهاؤه مضى)، وإلّا فعّال.
  static String _status(Subscriber s) {
    if (!s.isEnabled) return 'معطّل';
    final d = s.remainingDays;
    if (d != null) return d < 0 ? 'منتهٍ' : 'فعّال';
    final t = DateTime.tryParse((s.expiration ?? '').replaceFirst(' ', 'T'));
    if (t != null) return t.isBefore(DateTime.now()) ? 'منتهٍ' : 'فعّال';
    return '';
  }

  String get _today {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  Future<void> _share(String fileName, Uint8List bytes) async {
    final sink = DebtsImportScreen.debugExport;
    if (sink != null) return sink(fileName, bytes);
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/$fileName');
    await f.writeAsBytes(bytes, flush: true);
    await Share.shareXFiles(
      [XFile(f.path, mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', name: fileName)],
      subject: fileName,
    );
  }

  static const _sheetHeaders = ['username', 'amount', 'الاسم', 'رقم الهاتف', 'الباقة', 'تاريخ النفاذ'];

  List<_Sub> get _debtors => [
        for (final s in _subs ?? const <_Sub>[])
          if (s.hasDebt) s
      ];

  Future<void> _exportDebtors() async {
    final d = _debtors;
    if (d.isEmpty) return _say('لا توجد ديون للتصدير');
    try {
      await _share(
          'debts-$_today.xlsx', writeXlsx(sheetName: 'Debts', headers: _sheetHeaders, rows: [for (final s in d) _sheetRow(s, s.debt)]));
    } catch (_) {
      _say('فشل تصدير ملف الديون', error: true);
    }
  }

  Future<void> _exportAll() async {
    final all = _subs ?? const <_Sub>[];
    if (all.isEmpty) return _say('لا مشتركين للتصدير');
    try {
      // «أرقام تواصل إضافيّة» عمودان بعد «المدير» حين تكون مفتوحةً للحساب (كالموقع)
      final contacts = await DebtsImportApi.contactsAll();
      final rows = [
        for (final s in all)
          [
            ..._sheetRow(s, s.hasDebt ? s.debt : 0),
            _status(s.s),
            s.s.parentUsername ?? '',
            if (contacts != null) ...[contacts[s.s.username]?.wa2 ?? '', contacts[s.s.username]?.tg ?? ''],
          ],
      ];
      await _share(
        'subscribers-$_today.xlsx',
        writeXlsx(
            sheetName: 'Subscribers',
            headers: [
              ..._sheetHeaders,
              'الحالة',
              'المدير',
              if (contacts != null) ...['واتساب ثانٍ', 'تلغرام'],
            ],
            rows: rows),
      );
    } catch (_) {
      _say('فشل تصدير المشتركين', error: true);
    }
  }

  Future<void> _exportTemplate() async {
    try {
      await _share(
          'debts-import-template.xlsx',
          writeXlsx(
              sheetName: 'Debts', headers: _sheetHeaders, rows: [for (final s in (_subs ?? const <_Sub>[]).take(3)) _sheetRow(s, '')]));
    } catch (_) {
      _say('فشل تنزيل القالب', error: true);
    }
  }

  // ═══════════════ الاستيراد ═══════════════

  Future<({String name, Uint8List bytes})?> _pickFile() async {
    final hook = DebtsImportScreen.debugPick;
    if (hook != null) return hook();
    final desktop = !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
    final f = await openFile(acceptedTypeGroups: [
      if (desktop) const XTypeGroup(label: 'Excel / CSV', extensions: ['xlsx', 'csv', 'txt']),
    ]);
    if (f == null) return null;
    if (await f.length() > 20 * 1024 * 1024) {
      _say('الملفّ أكبر من المعقول (أكثر من ٢٠ ميغا)', error: true);
      return null;
    }
    return (name: f.name, bytes: await f.readAsBytes());
  }

  Future<void> _pick() async {
    // المطابقة بقائمةٍ لم تصل = «غير موجود» للكلّ — يُرفع الملفّ بعد وصولها
    final subs = _subs;
    if (subs == null) {
      return _say(
          _subsError != null ? 'تعذّر جلب قائمة المشتركين — حدّث الصفحة ثمّ اختر الملفّ' : 'انتظر تحميل قائمة المشتركين ثمّ اختر الملفّ',
          error: true);
    }
    final f = await _pickFile();
    if (f == null || !mounted) return;
    setState(() {
      _reading = true;
      _result = null;
      _deletedResult = null;
    });
    try {
      final bytes = f.bytes;
      final lower = f.name.toLowerCase();
      final isPdf =
          lower.endsWith('.pdf') || (bytes.length > 4 && bytes[0] == 0x25 && bytes[1] == 0x50 && bytes[2] == 0x44 && bytes[3] == 0x46);
      if (isPdf) {
        setState(() => _reading = false);
        return _say('تقرير PDF يُقرأ من الموقع الآن — ارفعه هناك، أو احفظه Excel وارفعه هنا', error: true);
      }
      final kind = sheetKindOf(bytes);
      List<List<String>> table;
      switch (kind) {
        case SheetKind.xlsx:
          table = readXlsxRows(bytes);
        case SheetKind.xls:
        case SheetKind.ods:
          setState(() => _reading = false);
          return _say('هذه صيغة Excel قديمة (${kind == SheetKind.xls ? 'xls' : 'ods'}) — احفظ الملفّ xlsx أو CSV ثمّ ارفعه', error: true);
        case SheetKind.other:
          var text = utf8.decode(bytes, allowMalformed: true);
          if (text.startsWith('\uFEFF')) text = text.substring(1); // TextDecoder يحذف BOM كالموقع
          table = parseCsv(text);
      }
      if (table.isEmpty) {
        setState(() => _reading = false);
        return _say('الملف فارغ', error: true);
      }
      final extracted = debtRowsOfTable(table);
      final matches = matchDebtRows([for (final r in extracted) r.input], subs);
      final parsed = [for (var i = 0; i < extracted.length; i++) _Parsed(extracted[i], matches[i])];
      if (!mounted) return;
      setState(() {
        _reading = false;
        _fileName = f.name;
        _rows = parsed;
        _applyReview = false;
        _shown = 100;
      });
      final c = _counts;
      _say('${c[DebtMatchKind.username]! + c[DebtMatchKind.phone]!} مطابق'
          '${c[DebtMatchKind.phone]! > 0 ? ' (منها ${c[DebtMatchKind.phone]} بالهاتف)' : ''}، '
          '${c[DebtMatchKind.review]! + c[DebtMatchKind.ambiguous]!} للمراجعة، ${c[DebtMatchKind.notFound]} غير موجود، ${c[DebtMatchKind.invalid]} غير صالح');
    } on XlsxReadError catch (e) {
      if (mounted) setState(() => _reading = false);
      _say(e.message, error: true);
    } catch (_) {
      if (mounted) setState(() => _reading = false);
      _say('فشل قراءة الملف', error: true);
    }
  }

  Map<DebtMatchKind, int> get _counts {
    final c = {for (final k in DebtMatchKind.values) k: 0};
    for (final r in _rows) {
      c[r.kind] = c[r.kind]! + 1;
    }
    return c;
  }

  /// صفٌّ يُطبَّق: مطابقٌ باليوزر أو بالهاتف، و«الاسم مختلف» باختيارٍ صريح وحده.
  bool _willApply(_Parsed r) =>
      r.kind == DebtMatchKind.username || r.kind == DebtMatchKind.phone || (_applyReview && r.kind == DebtMatchKind.review);

  int get _applyCount {
    final c = _counts;
    return c[DebtMatchKind.username]! + c[DebtMatchKind.phone]! + (_applyReview ? c[DebtMatchKind.review]! : 0);
  }

  Future<void> _apply() async {
    final rows = [
      for (final r in _rows)
        if (_willApply(r))
          // بالهاتف ⇒ يوزر المشترك المطابَق (الخادم يطبّق باليوزر)
          (username: r.kind == DebtMatchKind.username ? r.row.username : (r.sub?.username ?? ''), amount: r.row.amount),
    ]..removeWhere((r) => r.username.isEmpty);
    if (rows.isEmpty) return _say('لا توجد صفوف صالحة للاستيراد', error: true);
    final ok = await showConfirmSheet(
      context,
      title: 'تأكيد ${formatIQD(rows.length)} عملية ${_mode == 'add' ? 'إضافة دين' : 'استبدال دين'}؟',
      message: _mode == 'add'
          ? 'يُضاف مبلغ كلّ صفٍّ فوق دين مشتركه الحالي.'
          : 'يُمسح دين كلّ مشتركٍ في الملفّ ويُكتب مبلغ الملفّ مكانه. المشتركون غير الموجودين في الملفّ لا يتأثّرون.',
      confirmLabel: 'تطبيق ${formatIQD(rows.length)}',
      icon: LucideIcons.wallet,
      tone: _mode == 'add' ? AppTone.brand : AppTone.danger,
    );
    if (ok != true || !mounted) return;
    final result = DebtImportResult(total: rows.length);
    final p = _Progress(rows.length)..pending = rows.length;
    setState(() {
      _progress = p;
      _result = null;
    });
    String? stoppedMessage;
    var sent = 0;
    for (var i = 0; i < rows.length; i += _chunk) {
      final chunk = rows.sublist(i, i + _chunk > rows.length ? rows.length : i + _chunk);
      final names = [for (final r in chunk) r.username];
      setState(() {
        p.current = names;
        p.pending = rows.length - i - chunk.length;
      });
      final res = await DebtsImportApi.bulkImport(chunk, _mode);
      if (!mounted) return;
      if (res.data != null) {
        result.add(res.data!);
        sent += chunk.length;
        setState(() {
          p.done = sent;
          p.current = const [];
          final applied = [
            for (final d in (res.data!['details'] as List?) ?? const [])
              if (d is Map) '${d['username']}'
          ];
          p.lastApplied = applied.length > 5 ? applied.sublist(applied.length - 5) : applied;
        });
        if (result.stopped != null) {
          stoppedMessage = result.stopped;
          break;
        }
        continue;
      }
      if (res.unknown) {
        // انقطع الردّ: نتيجة الدفعة غير مؤكَّدة — لا تُعاد، والباقي لا يُرسل
        result.unknown.addAll(names);
        stoppedMessage = 'انقطع الاتّصال أثناء دفعة — نتيجة صفوفها غير مؤكَّدة';
      } else {
        stoppedMessage = res.message ?? 'لم يُطبَّق';
      }
      break;
    }
    final notSent = rows.length - sent - result.unknown.length;
    setState(() {
      _progress = null;
      _result = result
        ..stopped = stoppedMessage ?? result.stopped
        ..total = rows.length;
      _notSent = notSent < 0 ? 0 : notSent;
    });
    if (result.applied > 0) SubscriberEvents.notifyChange();
    _say(stoppedMessage == null ? 'تم تطبيق ${formatIQD(result.applied)} دين' : 'توقّف الاستيراد — ${formatIQD(result.applied)} طُبِّق',
        error: stoppedMessage != null);
  }

  int _notSent = 0;

  // ═══════════════ ديون المحذوفين ═══════════════

  List<_Parsed> get _missing => [
        for (final r in _rows)
          if (r.kind == DebtMatchKind.notFound && r.row.amount > 0 && (r.row.name.isNotEmpty || r.row.username.isNotEmpty)) r,
      ];

  Future<void> _addDeleted({List<({String name, double amount, String phone, String username})>? again}) async {
    final send = again ??
        [
          for (final r in _missing)
            (name: r.row.name.isNotEmpty ? r.row.name : r.row.username, amount: r.row.amount, phone: r.row.phone, username: r.row.username),
        ];
    if (send.isEmpty) return;
    final total = send.fold<double>(0, (a, r) => a + r.amount);
    final ok = await showConfirmSheet(
      context,
      title: again == null
          ? 'إضافة ${formatIQD(send.length)} ديناً لديون المحذوفين؟'
          : 'إضافة الـ${formatIQD(send.length)} المكرّرة مرّةً ثانية؟',
      message: again == null
          ? 'بمجموع ${formatIQD(total)} د.ع — تبقى ديونهم لك وتسدّدها من «ديون المحذوفين».'
          : 'ديونٌ أخرى بنفس الاسم والمبلغ أُضيفت قبل أقلّ من ٣٠ دقيقة.',
      confirmLabel: 'أضفها',
      icon: LucideIcons.userX,
      tone: AppTone.danger,
    );
    if (ok != true || !mounted) return;
    setState(() {
      _deletedBusy = true;
      _deletedSent = send;
    });
    final r = await DebtsImportApi.importDeleted(send, confirmRepeat: again != null);
    if (!mounted) return;
    setState(() {
      _deletedBusy = false;
      if (r.result != null) _deletedResult = r.result;
    });
    final res = r.result;
    if (res == null) return _say(r.message ?? 'تعذّرت الإضافة', error: true);
    if (res.added > 0) {
      _say('أُضيف ${formatIQD(res.added)} لديون المحذوفين — ${formatIQD(res.debtAdded)} د.ع');
    } else {
      _say('لم يُضف شيء — راجع التفاصيل', error: true);
    }
  }

  // ═══════════════ الرسم ═══════════════

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return PopScope(
      // أثناء التطبيق لا يُغلق القسم (الدفعات تكمل وتُعرض نتيجتها)
      canPop: !_busy,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _busy) _say('انتظر حتى تكتمل الدفعات');
      },
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(
          backgroundColor: AppColors.surface,
          elevation: 0,
          scrolledUnderElevation: 0,
          title: Text(DebtsImportScreen.title, style: AppType.title(color: AppColors.textHi).copyWith(fontSize: 16)),
          iconTheme: IconThemeData(color: AppColors.textHi),
        ),
        body: SafeArea(
          child: ListView(
            key: const ValueKey('dimp-list'),
            padding: EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, MediaQuery.paddingOf(context).bottom + Sp.huge),
            children: _parts(),
          ),
        ),
      ),
    );
  }

  List<Widget> _parts() {
    final out = <Widget>[];
    void add(Widget w) {
      if (out.isNotEmpty) out.add(const SizedBox(height: Sp.md));
      out.add(w);
    }

    final big = _bigTotal;
    if (big != null) {
      add(_note(
        LucideIcons.triangleAlert,
        'حسابك كبير (${formatIQD(big)} مشترك): الاستيراد والتصدير بالجملة غير متاحين بعد له — يحتاجان مطابقة كلّ المشتركين دفعةً واحدة، '
        'ومطابقةٌ ناقصة على الديون لا تُجرَّب. المدينون وإجمالي ديونهم في صفحة المشتركين (تبويب «مديون»).',
        AppTone.warning,
      ));
      return out;
    }
    if (ProviderService.isEarthlink || ProviderService.isFiberx) {
      add(Text(
        'الديون تُحفظ في دفتر MyServices — ${ProviderService.isEarthlink ? 'ايرث لنك' : 'فايبر اكس'} لا تحفظ ديوناً.',
        style: AppType.micro(color: AppColors.textMid),
      ));
    }
    add(_exportCard());
    add(_importCard());
    // التقدّم والنتيجة فوق المعاينة (على الهاتف كانت النتيجة تحت مئات الصفوف فلا تُرى)
    if (_progress != null) add(_progressCard(_progress!));
    if (_result != null) add(_resultCard(_result!));
    if (_rows.isNotEmpty) add(_previewCard());
    return out;
  }

  Widget _note(IconData icon, String text, AppTone tone) => Container(
        padding: const EdgeInsets.all(Sp.md),
        decoration: BoxDecoration(
          color: tone.softBg,
          borderRadius: BorderRadius.circular(R.md),
          border: Border.all(color: tone.fill.withValues(alpha: 0.35)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(padding: const EdgeInsets.only(top: 2), child: Icon(icon, size: 15, color: tone.onSoft)),
            const SizedBox(width: Sp.sm),
            Expanded(child: Text(text, style: AppType.micro(color: tone.onSoft).copyWith(height: 1.5))),
          ],
        ),
      );

  Widget _actionButton({required Key key, required IconData icon, required String label, VoidCallback? onTap}) {
    return OutlinedButton.icon(
      key: key,
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.textHi,
        side: BorderSide(color: AppColors.border),
        minimumSize: const Size.fromHeight(42),
        alignment: AlignmentDirectional.centerStart,
        padding: const EdgeInsets.symmetric(horizontal: Sp.md),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.md)),
      ),
      icon: Icon(icon, size: 16, color: onTap == null ? AppColors.textLow : AppColors.brand),
      label: Text(label, style: AppType.bodyBold(color: onTap == null ? AppColors.textLow : AppColors.textHi)),
    );
  }

  Widget _exportCard() {
    final subs = _subs;
    final debtors = _debtors.length;
    return RpCard(
      key: const ValueKey('dimp-export'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const RpTitle(icon: LucideIcons.download, title: 'تصدير', tone: RpTone.brand),
          const SizedBox(height: Sp.md),
          if (_loadingSubs)
            const Padding(padding: EdgeInsets.symmetric(vertical: Sp.md), child: Center(child: CircularProgressIndicator()))
          else if (subs == null)
            Text(_subsError ?? 'تعذّر جلب قائمة المشتركين', style: AppType.micro(color: AppColors.error))
          else ...[
            _actionButton(
              key: const ValueKey('dimp-export-debtors'),
              icon: LucideIcons.download,
              label: 'المدينون الحاليون (${formatIQD(debtors)})',
              onTap: debtors == 0 ? null : _exportDebtors,
            ),
            const SizedBox(height: Sp.sm),
            _actionButton(
              key: const ValueKey('dimp-export-all'),
              icon: LucideIcons.users,
              label: 'كلّ المشتركين (${formatIQD(subs.length)})',
              onTap: subs.isEmpty ? null : _exportAll,
            ),
            const SizedBox(height: Sp.sm),
            _actionButton(
              key: const ValueKey('dimp-export-template'),
              icon: LucideIcons.fileSpreadsheet,
              label: 'قالب فارغ',
              onTap: _exportTemplate,
            ),
          ],
          const SizedBox(height: Sp.sm),
          Text(
            'ملفّ التصدير والقالب بالشكل نفسه (Excel)، فيُرفع ملفّ التصدير كما هو. الأعمدة المطلوبة: username (أو رقم الهاتف) وamount.',
            style: AppType.micro(color: AppColors.textMid),
          ),
        ],
      ),
    );
  }

  Widget _modeCard(String mode, String title, String sub) {
    final on = _mode == mode;
    return Expanded(
      child: Material(
        color: on ? AppColors.brandSoftBg : AppColors.surface,
        borderRadius: BorderRadius.circular(R.md),
        child: InkWell(
          key: ValueKey('dimp-mode-$mode'),
          onTap: _busy ? null : () => setState(() => _mode = mode),
          borderRadius: BorderRadius.circular(R.md),
          child: Container(
            padding: const EdgeInsets.all(Sp.sm + 2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(R.md),
              border: Border.all(color: on ? AppColors.brand.withValues(alpha: 0.5) : AppColors.border, width: on ? 1.5 : 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppType.bodyBold(color: on ? AppColors.brand : AppColors.textHi)),
                const SizedBox(height: 2),
                Text(sub, style: AppType.micro(color: AppColors.textMid)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _importCard() {
    final c = _counts;
    final missing = _missing;
    return RpCard(
      key: const ValueKey('dimp-import'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const RpTitle(icon: LucideIcons.upload, title: 'استيراد', tone: RpTone.brand),
          const SizedBox(height: Sp.md),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _modeCard('set', 'استبدال (=) — الافتراضي', 'يمسح الدين القديم ويضع القيمة الجديدة'),
                const SizedBox(width: Sp.sm),
                _modeCard('add', 'إضافة (+)', 'المبلغ يُضاف لدين المشترك الحالي'),
              ],
            ),
          ),
          const SizedBox(height: Sp.sm),
          _mode == 'set'
              ? _note(
                  LucideIcons.triangleAlert,
                  'وضع الاستبدال: الدين الحالي لكلّ مشتركٍ في الملفّ سيُمسح ويُستبدَل بالقيمة الجديدة. المشتركون غير الموجودين في الملفّ لن يتأثّروا.',
                  AppTone.danger)
              : _note(LucideIcons.info, 'وضع الإضافة: المبلغ في الملفّ سيُضاف فوق الدين الموجود حالياً (تراكم).', AppTone.brand),
          const SizedBox(height: Sp.md),
          FilledButton.icon(
            key: const ValueKey('dimp-pick'),
            onPressed: _busy || _reading || _loadingSubs ? null : _pick,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.brand,
              foregroundColor: AppColors.onBrand,
              minimumSize: const Size.fromHeight(44),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.md)),
            ),
            icon: _reading
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(LucideIcons.upload, size: 16),
            label: Text(
              _fileName.isEmpty ? 'اختر ملف Excel أو CSV' : 'الملفّ: ${iso(_fileName)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.bodyBold(color: AppColors.onBrand),
            ),
          ),
          const SizedBox(height: Sp.sm),
          Text(
            'Excel (xlsx) أو CSV — صفٌّ بلا اسم مستخدم يُطابَق برقم الهاتف (رقمٌ لمشتركٍ واحد فقط، وما لا يُحسم لا يُطبَّق). راجع المعاينة قبل التطبيق.',
            style: AppType.micro(color: AppColors.textMid),
          ),
          if (_rows.isNotEmpty) ...[
            const SizedBox(height: Sp.md),
            Wrap(
              key: const ValueKey('dimp-stats'),
              spacing: Sp.x6,
              runSpacing: Sp.x6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ToneChip(
                  label: 'مطابق ${c[DebtMatchKind.username]! + c[DebtMatchKind.phone]!}'
                      '${c[DebtMatchKind.phone]! > 0 ? ' (بالهاتف ${c[DebtMatchKind.phone]})' : ''}',
                  icon: LucideIcons.circleCheck,
                  tone: AppTone.success,
                  dense: true,
                ),
                if (c[DebtMatchKind.review]! + c[DebtMatchKind.ambiguous]! > 0)
                  ToneChip(
                    label: 'للمراجعة ${c[DebtMatchKind.review]! + c[DebtMatchKind.ambiguous]!}',
                    icon: LucideIcons.triangleAlert,
                    tone: AppTone.warning,
                    dense: true,
                  ),
                ToneChip(label: 'غير موجود ${c[DebtMatchKind.notFound]}', icon: LucideIcons.userX, tone: AppTone.warning, dense: true),
                ToneChip(label: 'غير صالح ${c[DebtMatchKind.invalid]}', icon: LucideIcons.circleX, tone: AppTone.danger, dense: true),
                InkWell(
                  key: const ValueKey('dimp-clear'),
                  onTap: _busy
                      ? null
                      : () => setState(() {
                            _rows = const [];
                            _fileName = '';
                            _result = null;
                            _deletedResult = null;
                          }),
                  borderRadius: BorderRadius.circular(R.sm),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Sp.xs, vertical: 2),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(LucideIcons.trash2, size: 13, color: AppColors.textMid),
                      const SizedBox(width: 3),
                      Text('مسح', style: AppType.micro(color: AppColors.textMid)),
                    ]),
                  ),
                ),
              ],
            ),
          ],
          // «غير موجود» ⇒ «ديون المشتركين المحذوفين» (حين تُفتح للحساب) — كالموقع DeletedDebtsOffer
          if (_deletedEnabled && (missing.isNotEmpty || _deletedResult != null)) ...[
            const SizedBox(height: Sp.md),
            _deletedOffer(missing),
          ],
          if (c[DebtMatchKind.review]! > 0) ...[
            const SizedBox(height: Sp.md),
            Container(
              padding: const EdgeInsets.fromLTRB(Sp.md, Sp.sm, Sp.sm, Sp.sm),
              decoration: BoxDecoration(
                color: AppColors.warningSoftBg,
                borderRadius: BorderRadius.circular(R.md),
                border: Border.all(color: AppTone.warning.fill.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('تطبيق «الاسم مختلف» أيضاً (${c[DebtMatchKind.review]})',
                            style: AppType.bodyBold(color: AppTone.warning.onSoft)),
                        Text(
                          'الرقم لمشتركٍ واحد لكنّ اسمه لا يشبه اسم الملف (رقمٌ انتقل لشخصٍ آخر؟) — راجعها في المعاينة؛ لا تُطبَّق إلّا بتفعيل هذا.',
                          style: AppType.micro(color: AppColors.textMid),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    key: const ValueKey('dimp-review'),
                    value: _applyReview,
                    activeThumbColor: AppColors.brand,
                    onChanged: _busy ? null : (v) => setState(() => _applyReview = v),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _deletedOffer(List<_Parsed> missing) {
    final total = missing.fold<double>(0, (a, r) => a + r.row.amount);
    final res = _deletedResult;
    return Container(
      key: const ValueKey('dimp-deleted'),
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.dangerSoftBg,
        borderRadius: BorderRadius.circular(R.md),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${formatIQD(missing.length)} غير موجود بالساس — بمجموع ${rpMoney(total)}',
                        style: AppType.bodyBold(color: AppColors.error)),
                    Text(
                      'مشتركون حذفتهم الشركة؟ أضفهم لـ«ديون المشتركين المحذوفين» بالاسم والهاتف والمبلغ — تبقى ديونهم لك وتسدّدها من هناك.',
                      style: AppType.micro(color: AppColors.textMid),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Sp.sm),
              OutlinedButton(
                key: const ValueKey('dimp-deleted-add'),
                onPressed: missing.isEmpty || _deletedBusy || _busy ? null : () => _addDeleted(),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.error,
                  side: BorderSide(color: AppColors.error.withValues(alpha: 0.5)),
                  minimumSize: const Size(0, 34),
                  padding: const EdgeInsets.symmetric(horizontal: Sp.sm + 2),
                ),
                child: _deletedBusy
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text('أضفها (${formatIQD(missing.length)})', style: AppType.labelBold(color: AppColors.error)),
              ),
            ],
          ),
          if (res != null) ...[
            const SizedBox(height: Sp.sm),
            Text(
              [
                'أُضيف ${formatIQD(res.added)}',
                if (res.exists > 0) 'موجودون بالساس (لم يُضافوا) ${res.exists}',
                if (res.repeatRows.isNotEmpty) 'أُضيفوا قبل أقلّ من ٣٠ دقيقة ${res.repeatRows.length}',
                if (res.duplicate > 0) 'مكرّر بالملفّ ${res.duplicate}',
                if (res.invalid > 0) 'غير صالح ${res.invalid}',
                if (res.failed > 0) 'لم يُطبَّق ${res.failed}',
              ].join(' · '),
              style: AppType.micro(color: AppColors.textMid),
            ),
            if (res.repeatRows.isNotEmpty)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  key: const ValueKey('dimp-deleted-again'),
                  onPressed: _deletedBusy
                      ? null
                      : () {
                          // «أضف المكرّرة» يعيد صفوفها وحدها (رقم الصفّ من ردّ الخادم)، لا الملفّ كلّه
                          final again = [
                            for (final n in res.repeatRows)
                              if (n >= 1 && n <= _deletedSent.length) _deletedSent[n - 1],
                          ];
                          if (again.isNotEmpty) _addDeleted(again: again);
                        },
                  child: Text('أضف المكرّرة أيضاً', style: AppType.labelBold(color: AppColors.error)),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _progressCard(_Progress p) {
    final pct = p.total == 0 ? 0.0 : p.done / p.total;
    return RpCard(
      key: const ValueKey('dimp-progress'),
      tint: AppColors.brand,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: Sp.sm),
              Expanded(child: Text('جارٍ تطبيق الديون…', maxLines: 2, style: AppType.bodyBold(color: AppColors.textHi))),
              Text('${formatIQD(p.done)} / ${formatIQD(p.total)}', style: AppType.bodyStrong(color: AppColors.brand)),
            ],
          ),
          const SizedBox(height: Sp.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(R.pill),
            child: LinearProgressIndicator(value: pct, minHeight: 8, backgroundColor: AppColors.surfaceSunken, color: AppColors.brand),
          ),
          if (p.current.isNotEmpty) ...[
            const SizedBox(height: Sp.sm),
            Text('قيد المعالجة الآن (${p.current.length}): ${p.current.map(iso).join('، ')}',
                maxLines: 3, overflow: TextOverflow.ellipsis, style: AppType.micro(color: AppColors.brand)),
          ],
          if (p.lastApplied.isNotEmpty)
            Text('آخر من طُبِّق: ${p.lastApplied.map(iso).join('، ')}',
                maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.micro(color: AppColors.success)),
          if (p.pending > 0) Text('في الانتظار: ${formatIQD(p.pending)} صفّ', style: AppType.micro(color: AppColors.textMid)),
        ],
      ),
    );
  }

  Widget _previewCard() {
    final rows = _rows;
    final shown = rows.take(_shown).toList();
    final n = _applyCount;
    return RpCard(
      key: const ValueKey('dimp-preview'),
      padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.lg, Sp.lg, Sp.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RpTitle(
            icon: LucideIcons.listOrdered,
            title: 'معاينة الصفوف',
            tone: RpTone.neutral,
            trailing: Text('${formatIQD(rows.length)} صفّ', style: AppType.pillBold(color: AppColors.textMid)),
          ),
          const SizedBox(height: Sp.md),
          FilledButton.icon(
            key: const ValueKey('dimp-apply'),
            onPressed: n == 0 || _busy ? null : _apply,
            style: FilledButton.styleFrom(
              backgroundColor: _mode == 'set' ? AppColors.errorFill : AppColors.brand,
              foregroundColor: AppColors.onBrand,
              minimumSize: const Size.fromHeight(44),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.md)),
            ),
            icon: const Icon(LucideIcons.wallet, size: 16),
            label: Text('تطبيق (${formatIQD(n)}) — ${_mode == 'set' ? 'استبدال' : 'إضافة'}',
                style: AppType.bodyBold(color: AppColors.onBrand)),
          ),
          const SizedBox(height: Sp.x6),
          for (var i = 0; i < shown.length; i++) ...[
            if (i > 0) Divider(height: 1, thickness: 1, color: AppColors.divider),
            _previewRow(shown[i], i),
          ],
          if (rows.length > shown.length)
            Center(
              child: TextButton(
                key: const ValueKey('dimp-more'),
                onPressed: () => setState(() => _shown += 100),
                child: Text('عرض المزيد (${formatIQD(rows.length - shown.length)})', style: AppType.bodyBold(color: AppColors.brand)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _previewRow(_Parsed r, int i) {
    final sub = r.sub;
    final applied = _willApply(r);
    final byPhone = r.kind == DebtMatchKind.phone || r.kind == DebtMatchKind.review;
    final current = sub?.debt ?? 0;
    final next = applied ? (_mode == 'add' ? current + r.row.amount : r.row.amount) : null;
    final user = r.kind == DebtMatchKind.username ? r.row.username : (sub?.username ?? r.row.username);
    final (icon, tone) = applied
        ? (LucideIcons.circleCheck, RpTone.money)
        : r.kind == DebtMatchKind.invalid
            ? (LucideIcons.circleX, RpTone.loss)
            : (LucideIcons.triangleAlert, RpTone.debt);
    final name = sub?.fullName ?? '';
    final amountOk = r.row.amount.isFinite && r.row.amount > 0;
    return Padding(
      key: ValueKey('dimp-row-$i'),
      padding: const EdgeInsets.symmetric(vertical: Sp.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RpIconBox(icon: icon, tone: tone, size: 32),
          const SizedBox(width: Sp.sm + 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: Sp.x6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(user.isEmpty ? '—' : user, textDirection: TextDirection.ltr, style: AppType.bodyBold(color: AppColors.textHi)),
                    if (byPhone && sub != null) const ToneChip(label: 'بالهاتف', tone: AppTone.brand, dense: true),
                  ],
                ),
                if (name.isNotEmpty || r.kind == DebtMatchKind.notFound)
                  Text(name.isNotEmpty ? name : 'غير موجود', style: AppType.micro(color: AppColors.textMid)),
                if (r.row.name.isNotEmpty && r.kind != DebtMatchKind.username)
                  Text('في الملف: ${r.row.name}', style: AppType.micro(color: AppColors.textLow)),
                if (r.m.note != null)
                  Text(r.m.note!, style: AppType.micro(color: r.kind == DebtMatchKind.invalid ? AppColors.error : AppColors.warning)),
              ],
            ),
          ),
          const SizedBox(width: Sp.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(amountOk ? formatIQD(r.row.amount) : '—',
                  textDirection: TextDirection.ltr, style: AppType.bodyStrong(color: AppColors.textHi)),
              if (sub != null) Text('الحالي ${formatIQD(current)}', style: AppType.micro(color: AppColors.textLow)),
              if (next != null) Text('بعده ${formatIQD(next)}', style: AppType.microBold(color: AppColors.error)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _resultCard(DebtImportResult r) {
    Widget stat(String label, int v, Color color, String id) => Expanded(
          child: Container(
            key: ValueKey('dimp-res-$id'),
            padding: const EdgeInsets.all(Sp.sm),
            decoration: BoxDecoration(
              color: AppColors.surfaceSunken,
              borderRadius: BorderRadius.circular(R.sm),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppType.micro(color: AppColors.textMid)),
                RpFitText(formatIQD(v), style: AppType.statValue(color: color)),
              ],
            ),
          ),
        );
    return RpCard(
      key: const ValueKey('dimp-result'),
      tint: r.stopped != null ? AppColors.error : AppColors.brand,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const RpTitle(icon: LucideIcons.info, title: 'نتيجة الاستيراد', tone: RpTone.brand),
          const SizedBox(height: Sp.md),
          IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              stat('الإجمالي', r.total, AppColors.textHi, 'total'),
              const SizedBox(width: Sp.x6),
              stat('مُطبَّق', r.applied, AppColors.success, 'applied'),
            ]),
          ),
          const SizedBox(height: Sp.x6),
          IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              stat('غير موجود', r.notFound.length, AppColors.warning, 'notfound'),
              const SizedBox(width: Sp.x6),
              stat('لم يُطبَّق', r.failed.length, AppColors.error, 'failed'),
            ]),
          ),
          if (r.stopped != null) ...[
            const SizedBox(height: Sp.md),
            _note(LucideIcons.octagonAlert, 'توقّف: ${r.stopped}', AppTone.danger),
          ],
          if (r.unknown.isNotEmpty) ...[
            const SizedBox(height: Sp.sm),
            _note(
              LucideIcons.circleHelp,
              'غير مؤكَّد (${formatIQD(r.unknown.length)}): ${r.unknown.map(iso).join('، ')} — قد يكون بعضها طُبِّق. راجع ديونهم قبل أن تعيد رفعها '
              '(ما طُبِّق خلال ٣٠ دقيقة لا يُطبَّق ثانيةً).',
              AppTone.warning,
            ),
          ],
          if (_notSent > 0) ...[
            const SizedBox(height: Sp.sm),
            Text('لم يُرسل ${formatIQD(_notSent)} صفّاً بعد التوقّف — أعد رفع الملفّ لها.', style: AppType.micro(color: AppColors.error)),
          ],
          if (r.notFound.isNotEmpty)
            _expand('مشتركون غير موجودين (${formatIQD(r.notFound.length)})',
                [Text(r.notFound.map(iso).join('، '), style: AppType.micro(color: AppColors.textMid))]),
          if (r.failed.isNotEmpty)
            _expand('صفوفٌ لم تُطبَّق (${formatIQD(r.failed.length)})', [
              for (final f in r.failed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text('${iso(f.username)} — ${f.error}', style: AppType.micro(color: AppColors.textMid)),
                ),
            ]),
        ],
      ),
    );
  }

  Widget _expand(String title, List<Widget> children) => Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        // طبقة Material خاصّة: داخل بطاقةٍ ملوّنة يختفي حبر اللمس (وتنبيه Flutter عن ListTile)
        child: Material(
          type: MaterialType.transparency,
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: Sp.sm),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            title: Text(title, style: AppType.bodyBold(color: AppColors.textHi)),
            children: children,
          ),
        ),
      );
}
