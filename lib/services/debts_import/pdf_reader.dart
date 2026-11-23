import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'debts_match.dart';

/// صفٌّ قرأه قارئ الموقع من الـPDF (`DebtPdfRow` في client-v2 lib/debts-pdf.ts).
class PdfDebtRow {
  const PdfDebtRow({
    required this.username,
    required this.name,
    required this.debt,
    required this.negative,
    required this.phone,
    required this.raw,
    this.seq,
  });

  final String username;
  final String name;

  /// null = خليّةٌ بلا أرقام (لا تُعدّ صفراً).
  final double? debt;

  /// الدين مكتوبٌ سالباً — المعنى يختلف بين الأنظمة ⇒ «غير صالح» يُعرض ولا يُطبَّق.
  final bool negative;
  final String phone;
  final String raw;
  final int? seq;

  static PdfDebtRow fromJson(Map<String, dynamic> j) => PdfDebtRow(
        username: '${j['username'] ?? ''}',
        name: '${j['name'] ?? ''}',
        debt: (j['debt'] as num?)?.toDouble(),
        negative: j['negative'] == true,
        phone: '${j['phone'] ?? ''}',
        raw: '${j['raw'] ?? ''}',
        seq: (j['seq'] as num?)?.toInt(),
      );
}

/// ناتج قراءة الـPDF (`DebtPdfResult`).
class PdfDebtsResult {
  const PdfDebtsResult({required this.rows, this.pages = 0, this.missingSeq = const [], this.duplicateSeq = const []});

  final List<PdfDebtRow> rows;
  final int pages;
  final List<int> missingSeq;
  final List<int> duplicateSeq;

  /// الترقيم (#) فيه نقصٌ أو تكرار ⇒ يُقارَن عدد الصفوف بالملفّ قبل التطبيق (كالموقع).
  bool get seqBroken => missingSeq.isNotEmpty || duplicateSeq.isNotEmpty;

  static PdfDebtsResult fromJson(Map<String, dynamic> j) {
    List<int> ints(Object? v) => [
          for (final x in (v as List?) ?? const [])
            if (x is num) x.toInt()
        ];
    return PdfDebtsResult(
      rows: [
        for (final r in (j['rows'] as List?) ?? const [])
          if (r is Map) PdfDebtRow.fromJson(Map<String, dynamic>.from(r))
      ],
      pages: (j['pages'] as num?)?.toInt() ?? 0,
      missingSeq: ints(j['missingSeq']),
      duplicateSeq: ints(j['duplicateSeq']),
    );
  }

  /// صفوف الاستيراد كما يبنيها الموقع من الـPDF (pages/DebtsImport.tsx): دينٌ لا يُقرأ أو مكتوبٌ سالباً ⇒ NaN («مبلغٌ غير صالح»).
  List<DebtFileRow> get fileRows => [
        for (final r in rows)
          DebtFileRow(
            username: r.username,
            amount: r.debt == null || r.negative ? double.nan : r.debt!,
            raw: r.raw,
            phone: r.phone,
            name: r.name,
          ),
      ];
}

class PdfReadError implements Exception {
  const PdfReadError(this.message);
  final String message;
  @override
  String toString() => message;

  /// خطأ قارئ الموقع (رسالة pdf.js بالإنجليزيّة غالباً) ⇒ عربيّةٌ تقول ما العمل.
  static PdfReadError fromReader(Object? error) {
    final e = '${error ?? ''}'.trim();
    final l = e.toLowerCase();
    if (l.contains('password')) {
      return const PdfReadError('الملفّ محميّ بكلمة سرّ — احفظه بلا كلمة سرّ أو صدّره Excel');
    }
    if (l.contains('invalid pdf') || l.contains('missing pdf')) {
      return const PdfReadError('الملفّ ليس PDF سليماً — جرّب ملفّ Excel');
    }
    return PdfReadError('تعذّرت قراءة الـPDF${e.isEmpty ? '' : ': $e'} — جرّب ملفّ Excel');
  }
}

/// «قراءة الـPDF بالتطبيق» (٢٣ نوفمبر — المالك: «اي سوي قراءة الـPDF بالتطبيق هم»): بقارئ الموقع نفسه حرفاً (pdf.js بمواضع الكلمات،
/// client-v2 lib/debts-pdf.ts — الذي ثبتت دقّته على ملفّ المالك ٥٢٧/٥٢٧) في WebView مخفيّ يفتح صفحة `pdf-reader.html` (بلا واجهةٍ ولا
/// حساب): الملفّ يُمرَّر قطعاً base64 وتُقرأ نتيجته من قناة JavaScript — **لا يُرفع لأيّ خادم** (القراءة على الجهاز). الهاتف وحده
/// (webview_flutter: أندرويد وiOS)؛ الحاسبة تُحال للموقع. الصفحة بنسخة pdf.js «legacy» + بديل تكرار التيّار لـWebKit (الموقع 86d00b2):
/// مفحوصةٌ بـWebView حقيقيّ — محاكي iOS 26.5، أندرويد WebView 149، وأندرويد قديم WebView 95.
class PdfDebtsReader {
  PdfDebtsReader({Uri? page}) : _page = page;

  static const readerUrl = 'https://pro.mysvcs.net/v2/pdf-reader.html';
  static const _chunk = 200000;

  static bool get supported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  final Uri? _page;
  WebViewController? _c;

  /// الصفحة بيوم اليوم في الرابط: الصفحة مخزّنةٌ أسبوعاً عند المتصفّح (/v2 immutable)، فإصلاحٌ فيها يصل بعد يومٍ على الأكثر.
  Uri get page {
    final p = _page;
    if (p != null) return p;
    final n = DateTime.now();
    return Uri.parse('$readerUrl?d=${n.year}-${n.month}-${n.day}');
  }

  /// الـWebView بحجم ١×١ — يوضع في الشجرة أثناء القراءة وحدها (بعض المنصّات لا تشغّل صفحةً غير معروضة).
  Widget view() {
    final c = _c;
    if (c == null) return const SizedBox.shrink();
    return SizedBox(width: 1, height: 1, child: WebViewWidget(controller: c));
  }

  bool get active => _c != null;

  /// يقرأ [bytes]. [onChange] يُنادى حين يُضاف الـWebView للشجرة أو يُزال (الشاشة تعيد بناءها).
  Future<PdfDebtsResult> read(
    Uint8List bytes, {
    VoidCallback? onChange,
    Duration loadTimeout = const Duration(seconds: 45),
    Duration readTimeout = const Duration(seconds: 120),
    Duration notReadyGrace = const Duration(seconds: 5),
  }) async {
    final ready = Completer<void>();
    final done = Completer<Map<String, dynamic>>();
    void markReady() {
      if (!ready.isCompleted) ready.complete();
    }

    final c = WebViewController();
    try {
      await c.setJavaScriptMode(JavaScriptMode.unrestricted);
      await c.addJavaScriptChannel('PdfReader', onMessageReceived: (m) {
        Object? j;
        try {
          j = jsonDecode(m.message);
        } catch (_) {
          return;
        }
        if (j is! Map) return;
        if (j['ready'] == true) {
          markReady();
        } else if (j.containsKey('ok') && !done.isCompleted) {
          done.complete(Map<String, dynamic>.from(j));
        }
      });
      Future<bool> pageReady() async {
        try {
          final r = await c.runJavaScriptReturningResult('window.__pdfReady === true');
          return '$r' == 'true' || r == true;
        } catch (_) {
          return false;
        }
      }

      await c.setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) async {
          if (ready.isCompleted) return;
          // الجاهزيّة من الصفحة نفسها أيضاً (إن سبقت رسالتها القناة)
          if (await pageReady()) return markReady();
          // انتهى تحميل الصفحة ولم يعمل القارئ (محرّكٌ أقدم من أن يشغّله، أو صفحةٌ غير القارئ): مهلةٌ قصيرة ثمّ رسالةٌ واضحة — لا ٤٥ ثانية
          // ثمّ «الاتّصال بطيء» يعيدها الوكيل بلا فائدة
          await Future<void>.delayed(notReadyGrace);
          if (ready.isCompleted) return;
          if (await pageReady()) return markReady();
          if (!ready.isCompleted) {
            ready.completeError(
                const PdfReadError('قارئ الـPDF لا يعمل على هذا الجهاز — حدّث نظام الهاتف، أو ارفع الملفّ Excel، أو الـPDF من الموقع'));
          }
        },
        onWebResourceError: (e) {
          if (e.isForMainFrame != false && !ready.isCompleted) {
            ready.completeError(const PdfReadError('تعذّر فتح قارئ الـPDF — تحقّق من الاتّصال وأعد'));
          }
        },
      ));
      _c = c;
      onChange?.call();
      await c.loadRequest(page);
      try {
        await ready.future.timeout(loadTimeout);
      } on TimeoutException {
        throw const PdfReadError('تعذّر فتح قارئ الـPDF — الاتّصال بطيء، أعد بعد قليل');
      }
      final b64 = base64Encode(bytes);
      for (var i = 0; i < b64.length; i += _chunk) {
        final part = b64.substring(i, i + _chunk > b64.length ? b64.length : i + _chunk);
        await c.runJavaScript("window.__pdfAppend('$part')");
      }
      await c.runJavaScript('window.__pdfRun()');
      final Map<String, dynamic> msg;
      try {
        msg = await done.future.timeout(readTimeout);
      } on TimeoutException {
        throw const PdfReadError('قراءة الـPDF أخذت وقتاً طويلاً — جرّب ملفّ Excel');
      }
      if (msg['ok'] != true || msg['result'] is! Map) {
        throw PdfReadError.fromReader(msg['error']);
      }
      return PdfDebtsResult.fromJson(Map<String, dynamic>.from(msg['result'] as Map));
    } finally {
      _c = null;
      onChange?.call();
      unawaited(c.loadRequest(Uri.parse('about:blank')).catchError((_) {}));
    }
  }
}
