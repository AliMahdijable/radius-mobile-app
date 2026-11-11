import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:printing/printing.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/receipt_settings_api.dart';
import 'package:rad_mysvcs/api/receipts_archive_api.dart';
import 'package:rad_mysvcs/core/platform/app_platform.dart';
import 'package:rad_mysvcs/screens/more_modules_screen.dart';
import 'package:rad_mysvcs/screens/receipts/receipts_archive_screen.dart';
import 'package:rad_mysvcs/services/print_output.dart';
import 'package:rad_mysvcs/services/print_prefs.dart';
import 'package:rad_mysvcs/services/receipt_pdf.dart';
import 'package:rad_mysvcs/services/receipt_pdf_v2.dart';
import 'package:rad_mysvcs/services/receipt_service.dart';
import 'package:rad_mysvcs/widgets/list_kit.dart';

import 'visual_perm/visual_perm_harness.dart';

/// «أرشيف الوصولات» بالتطبيق (١١ نوفمبر ٢٠٢٦ — الخادم 1e4eafd + d99b609، والويب adb0f2d).
///   • النموذج: صفّ العمليّة ووصلها، سبب منع الطباعة (ملغى / نوعٌ قديم / بلا مبلغ)، والوصل كما يُطبع و«أصدره» كما حُفظ.
///   • النداءات بشركتها صراحةً، وما يُرسل: المدّة والفلاتر، واليوزرات التي طابق اسمُها البحث (سطر العمليّة بلا اسم)، وتلميح
///     المشترك للوصل الذي يصدر لاحقاً — لا مبلغ من هنا.
///   • الشاشة: الاسم من قائمة المشتركين، «لم يُطبع» و«No. 00012»، الطباعة من الصفّ ومن نافذته، وتحديث الصفّ بمكانه.
///   • الوصل المطبوع: برقمه وتاريخه و«نسخة»، بلا أرشفةٍ ثانية؛ والبطاقة في «قوائم أخرى» بمفتاح الخادم وقفل الصلاحيّة.
class _RcServer implements HttpClientAdapter {
  _RcServer(this.inner);
  final HttpClientAdapter inner;

  bool available = true;
  bool ownOnly = false;

  /// طلب القائمة يسقط (409 بنصّ الخادم).
  bool listFails = false;

  /// كم صفّاً في الصفحة (الخادم ٤٠ — هنا أصغر لاختبار «تحميل المزيد»).
  int pageSize = 40;
  int nextNo = 126;

  /// الردّ القادم للإصدار/الإعادة: (status, body) — null ⇒ نجاح.
  (int, Map<String, dynamic>)? nextPost;

  final queries = <Map<String, dynamic>>[];
  final probes = <RequestOptions>[];
  final posts = <(String, Map<String, dynamic>)>[];

  /// كلّ طلبات الأرشيف كما وصلت — لفحص الوجهة.
  final seen = <RequestOptions>[];

  /// الطباعة المعتادة (POST /api/printed-receipts) — يجب ألّا تُنادى من الأرشيف.
  int archivedAgain = 0;
  final links = <String>[];
  bool showQr = true;

  static final _now = DateTime.now().toUtc().millisecondsSinceEpoch;
  static const _h = 3600 * 1000;

  static Map<String, dynamic> _row(String key, String type, int agoH, String user, {Map<String, dynamic> o = const {}}) => {
        'key': key,
        'activity_id': key.startsWith('a:') ? int.parse(key.substring(2)) : null,
        'receipt_id': null,
        'receipt_no': null,
        'type': type,
        'at': _now - agoH * _h,
        'printed_at': null,
        'late': false,
        'username': user,
        'idx': '7',
        'name': null,
        'phone': null,
        'amount': null,
        'pay': null,
        'partial_amount': null,
        'new_balance': null,
        'package': null,
        'by': {'employee_id': null, 'username': 'mahdi'},
        'reprints': 0,
        'voided': false,
        'printable': true,
        ...o,
      };

  /// الأحدث أوّلاً — اليوزرات من مشتركي الخادم الوهميّ (الاسم يأتي من قائمتهم لا من هنا).
  List<Map<String, dynamic>> rows = [
    _row('a:830501', 'activate', 1, 'zainab.k@najaf', o: {
      'amount': 50000, 'pay': 'partial', 'partial_amount': 20000, 'new_balance': -30000, 'package': 'Standard',
      'by': {'employee_id': 3, 'username': 'hussein'},
    }),
    _row('a:830480', 'pay_debt', 2, 'haider.s@najaf', o: {
      'amount': 15000, 'new_balance': -5000, 'receipt_id': 3101, 'receipt_no': 124, 'printed_at': _now - 2 * _h + 6000,
      'name': 'حيدر سالم', 'phone': '07701234567', 'reprints': 1,
    }),
    _row('a:830455', 'extend', 5, 'abbas.r@najaf', o: {'new_balance': 0}),
    _row('a:830431', 'pay_debt', 9, 'ahmed.k@najaf', o: {'amount': 60000, 'new_balance': 0, 'voided': true}),
    _row('a:830390', 'activate', 26, 'mustafa.office@najaf', o: {
      'amount': 75000, 'pay': 'cash', 'new_balance': 0, 'package': 'Business', 'receipt_id': 3102, 'receipt_no': 125,
      'printed_at': _now - 3 * _h, 'late': true, 'name': 'مكتب مصطفى',
    }),
    _row('r:3050', 'pay_debt', 48, 'old.user@najaf', o: {
      'amount': 10000, 'pay': 'cash', 'receipt_id': 3050, 'receipt_no': 98, 'printed_at': _now - 48 * _h, 'name': 'مشترك محذوف',
      'by': {'employee_id': 3, 'username': 'hussein'},
    }),
    _row('r:2001', 'add_debt', 480, 'ali1@najaf', o: {'receipt_id': 2001, 'receipt_no': 5, 'printed_at': _now - 480 * _h, 'printable': false}),
  ];

  static ResponseBody _json(int status, Object body) => ResponseBody.fromString(jsonEncode(body), status, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      });

  Map<String, dynamic> _receiptOf(Map<String, dynamic> r, {required bool copy}) => {
        'id': r['receipt_id'],
        'receipt_no': r['receipt_no'],
        'type': r['type'],
        'kind': switch (r['type']) { 'activate' => 'activation', 'extend' => 'extension', 'pay_debt' => 'payment', _ => null },
        'issued_at': r['late'] == true ? r['at'] : r['printed_at'],
        'printed_at': r['printed_at'],
        'late': r['late'],
        'copy': copy,
        'reprints': r['reprints'],
        'activity_id': r['activity_id'],
        'subscriber': {'username': r['username'], 'name': r['name'], 'phone': r['phone'], 'idx': r['idx']},
        'package': {'name': r['package'], 'price': r['type'] == 'pay_debt' ? null : r['amount']},
        'expiration': r['expiration'],
        'remaining_days': null,
        'pay': r['pay'],
        'amount': r['amount'],
        'partial_amount': r['partial_amount'],
        'new_balance': r['new_balance'],
        'issuer': {'name': 'مكتب النجف', 'employee_username': null, 'manager_username': 'mahdi'},
      };

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final get = o.method.toUpperCase() == 'GET';
    final p = o.path;
    if (p.startsWith('/api/printed-receipts/')) seen.add(o);

    if (get && p == '/api/printed-receipts/archive') {
      final q = Map<String, dynamic>.from(o.queryParameters);
      if (q['probe'] == '1') {
        probes.add(o);
        return _json(200, {'success': true, 'available': available, 'can_view': true});
      }
      queries.add(q);
      if (listFails) return _json(409, {'success': false, 'code': 'RECEIPTS_UNAVAILABLE', 'message': 'تعذّر تحميل الوصولات الآن — أعد المحاولة'});
      if (!available) return _json(200, {'success': true, 'available': false, 'data': const [], 'next': null});
      final text = (q['q'] ?? '').toString().toLowerCase();
      final users = (q['users'] ?? '').toString().split(',').where((u) => u.isNotEmpty).toSet();
      var list = rows.where((r) {
        if (q['state'] == 'printed' && r['receipt_id'] == null) return false;
        if (q['state'] == 'unprinted' && r['receipt_id'] != null) return false;
        if (q['type'] != null && r['type'] != q['type']) return false;
        if (q['from'] != 'all' && (r['at'] as int) < int.parse(q['from'].toString())) return false;
        if (text.isEmpty && users.isEmpty) return true;
        final no = int.tryParse(text.replaceAll(RegExp(r'[^0-9]'), ''));
        return (text.isNotEmpty && r['username'].toString().toLowerCase().contains(text)) ||
            (text.isNotEmpty && (r['name'] ?? '').toString().contains(text)) ||
            users.contains(r['username']) ||
            (no != null && r['receipt_no'] == no);
      }).toList();
      final start = q['cursor'] == null ? 0 : int.parse(q['cursor'].toString().substring(1));
      final end = (start + pageSize).clamp(0, list.length);
      final more = end < list.length;
      list = list.sublist(start.clamp(0, list.length), end);
      return _json(200, {'success': true, 'available': true, 'data': list, 'next': more ? 'c$end' : null, 'own_only': ownOnly});
    }

    if (!get && (p == '/api/printed-receipts/issue' || p == '/api/printed-receipts/reprint')) {
      final body = Map<String, dynamic>.from(o.data as Map);
      posts.add((p.split('/').last, body));
      final forced = nextPost;
      if (forced != null) {
        nextPost = null;
        return _json(forced.$1, forced.$2);
      }
      final issue = p.endsWith('/issue');
      final i = rows.indexWhere((r) => issue ? r['activity_id'] == body['activity_id'] : r['receipt_id'] == body['id']);
      if (i < 0) return _json(404, {'success': false, 'code': issue ? 'OPERATION_NOT_FOUND' : 'RECEIPT_NOT_FOUND', 'message': 'غير موجود'});
      final r = Map<String, dynamic>.from(rows[i]);
      final fresh = issue && r['receipt_id'] == null;
      if (fresh) {
        final hint = body['subscriber'] is Map ? Map<String, dynamic>.from(body['subscriber'] as Map) : const <String, dynamic>{};
        r.addAll({
          'receipt_id': 3200 + nextNo,
          'receipt_no': nextNo++,
          'printed_at': _now,
          'late': true,
          'name': hint['name'] ?? r['name'],
          'phone': hint['phone'] ?? r['phone'],
          'expiration': hint['expiration'],
        });
      } else {
        r['reprints'] = (r['reprints'] as int) + 1;
      }
      rows = [...rows]..[i] = r;
      return _json(200, {'success': true, 'existing': !fresh, 'receipt': _receiptOf(r, copy: !fresh)});
    }

    // الطباعة المعتادة تؤرشف هنا — الأرشيف لا يناديها
    if (!get && p == '/api/printed-receipts') {
      archivedAgain++;
      return _json(200, {'success': true, 'receipt_no': 999});
    }
    if (get && p == '/api/v2/receipt-settings') {
      return _json(200, {
        'success': true,
        'data': {'shop_name': 'مكتب النجف', 'show_qr': showQr ? 1 : 0, 'auto_print': 0, 'issuer_name': 'اسم من يطبع الآن'},
      });
    }
    final lm = RegExp(r'^/api/v2/subscribers/(\d+)/generate-link$').firstMatch(p);
    if (!get && lm != null) {
      links.add(lm.group(1)!);
      return _json(200, {
        'success': true,
        'data': {'linkUrl': 'https://pro.mysvcs.net/user-info/t1'},
      });
    }
    return inner.fetch(o, requestStream, cancelFuture);
  }

  @override
  void close({bool force = false}) => inner.close(force: force);
}

class _FakeBackend implements PrintBackend {
  final calls = <String>[];
  PrintDoc? last;

  @override
  Future<bool> layout(PrintDoc doc) async {
    calls.add('layout');
    last = doc;
    return true;
  }

  @override
  Future<bool> direct(Printer printer, PrintDoc doc) async {
    calls.add('direct');
    last = doc;
    return true;
  }

  @override
  Future<List<Printer>> printers() async => const [];
}

const _elEmployeeView = Scenario(
  id: 'S2_el_emp_view',
  title: 'موظّف ايرث لنك — عرض المشتركين وحده',
  actor: Actor.elEmployee,
  provider: 'earthlink',
  keys: {'subscribers.view': true},
);

const _elEmployeeNone = Scenario(
  id: 'S3_el_emp_reports',
  title: 'موظّف ايرث لنك — بلا عرض المشتركين',
  actor: Actor.elEmployee,
  provider: 'earthlink',
  keys: {'reports.expenses': true},
);

/// أضيق هاتفٍ ندعمه — لا فيض ولا كرت يكبر.
const _narrow = VisualDevice('_320', Size(320, 1100), 2);

void main() {
  setUpAll(visualSetUpAll);

  group('النموذج', () {
    test('صفّ العمليّة: الأوقات بالميلّي ثانية، والوصل إن طُبع، وما بلا مفتاحٍ أو نوعٍ يُسقط', () {
      final it = ArchiveItem.fromJson({
        'key': 'a:830480', 'activity_id': 830480, 'receipt_id': '3101', 'receipt_no': 0, 'type': 'pay_debt', 'at': 1762000000000,
        'printed_at': 1762000006000, 'late': false, 'username': 'ali@net', 'idx': 1520, 'name': 'علي', 'amount': '15000', 'pay': null,
        'new_balance': -25000, 'by': {'employee_id': 3, 'username': 'hussein'}, 'reprints': 2, 'voided': false, 'printable': true,
      })!;
      expect((it.key, it.activityId, it.receiptId, it.receiptNo, it.type), ('a:830480', 830480, 3101, 0, ArchiveOp.payDebt));
      expect(it.at, DateTime.fromMillisecondsSinceEpoch(1762000000000, isUtc: true));
      expect(it.printed, isTrue, reason: 'الرقم صفر رقمٌ صحيح (أوّل وصلٍ للصفحة)');
      expect((it.amount, it.newBalance, it.byUsername, it.reprints, it.idx), (15000, -25000, 'hussein', 2, '1520'));
      expect(it.blockedReason, isNull);

      final un = ArchiveItem.fromJson({'key': 'a:1', 'type': 'activate', 'at': 1762000000000, 'pay': 'partial', 'partial_amount': 20000})!;
      expect((un.printed, un.pay, un.partialAmount, un.printable), (false, ReceiptPay.partial, 20000, true));
      for (final bad in [
        null,
        'x',
        {'type': 'activate', 'at': 1},
        {'key': 'a:1', 'type': 'zzz', 'at': 1762000000000},
        {'key': 'a:1', 'type': 'activate'},
        {'key': 'a:1', 'type': 'activate', 'at': 0},
      ]) {
        expect(ArchiveItem.fromJson(bad), isNull, reason: '$bad');
      }
    });

    test('سبب منع الطباعة: ملغى، نوعٌ قديم، بلا مبلغ', () {
      ArchiveItem of(Map<String, dynamic> o) => ArchiveItem.fromJson({'key': 'a:1', 'type': 'pay_debt', 'at': 1762000000000, ...o})!;
      expect(of({'voided': true}).blockedReason, 'أُلغي هذا التسديد — لا وصل له');
      expect(of({'printable': false}).blockedReason, 'لا مبلغ مسجَّلاً لهذه العمليّة');
      expect(of({'type': 'add_debt', 'printable': false}).blockedReason, 'نوعٌ قديم من الوصولات لا يُعاد طبعه');
      expect(of({}).blockedReason, isNull);
    });

    test('الوصل كما يُطبع: «أصدره» الاسم المختار ثمّ يوزر الموظّف ثمّ المدير؛ والصفّ بعد الطباعة', () {
      Map<String, dynamic> j(Map<String, dynamic> issuer, [Map<String, dynamic> o = const {}]) => {
            'id': 3200, 'receipt_no': 126, 'type': 'activate', 'kind': 'activation', 'issued_at': 1761900000000, 'printed_at': 1762000000000,
            'late': true, 'copy': false, 'reprints': 0, 'activity_id': 9,
            'subscriber': {'username': 'ali@net', 'name': 'علي حسن', 'phone': '0770', 'idx': '1520'},
            'package': {'name': 'باقة 35', 'price': 35000}, 'expiration': '2026-12-10 18:30:00', 'remaining_days': null,
            'pay': 'partial', 'amount': 35000, 'partial_amount': 10000, 'new_balance': -25000, 'issuer': issuer, ...o,
          };
      final r = ArchivedReceipt.fromJson(j({'name': 'مكتب النور', 'employee_username': 'cashier', 'manager_username': 'admin@x'}))!;
      expect((r.id, r.receiptNo, r.kind, r.late, r.copy), (3200, 126, ReceiptKind.activation, true, false));
      expect(r.issuedAt, DateTime.fromMillisecondsSinceEpoch(1761900000000, isUtc: true));
      expect((r.username, r.name, r.phone, r.idx, r.packageName, r.packagePrice), ('ali@net', 'علي حسن', '0770', '1520', 'باقة 35', 35000));
      expect((r.pay, r.amount, r.partialAmount, r.newBalance, r.expiration), (ReceiptPay.partial, 35000, 10000, -25000, '2026-12-10 18:30:00'));
      expect(r.issuer, 'مكتب النور');
      expect(ArchivedReceipt.fromJson(j({'name': null, 'employee_username': 'cashier', 'manager_username': 'admin@x'}))!.issuer, 'cashier');
      expect(ArchivedReceipt.fromJson(j({'manager_username': 'admin@x'}))!.issuer, 'admin@x');
      expect(ArchivedReceipt.fromJson(j({}, {'kind': null, 'type': 'add_debt'}))!.kind, isNull);
      expect(ArchivedReceipt.fromJson(j({}, {'subscriber': {'name': 'بلا يوزر'}})), isNull);
      expect(ArchivedReceipt.fromJson('x'), isNull);

      final row = ArchiveItem.fromJson({'key': 'a:9', 'activity_id': 9, 'type': 'activate', 'at': 1761900000000, 'username': 'ali@net', 'amount': 35000})!;
      final after = row.afterPrint(r);
      expect((after.key, after.receiptId, after.receiptNo, after.late, after.name, after.amount), ('a:9', 3200, 126, true, 'علي حسن', 35000));
      expect(after.printed, isTrue);
    });

    test('البحث المحلّيّ بالاسم: أرقامٌ لاتينيّة وألف/ياء/تاء موحّدة، والهاتف، واليوزر للخادم', () {
      expect(foldArchiveSearch('  أَحْمَد  إبراهيم ٠٧٧ '), 'احمد ابراهيم 077');
      expect(foldArchiveSearch('فاطمة'), foldArchiveSearch('فاطمه'));
      expect(foldArchiveSearch('مصطفى'), foldArchiveSearch('مصطفي'));
      final known = [
        (username: 'ahmed.k@najaf', name: 'أحمد كامل', phone: '07701234567'),
        (username: 'ali1@najaf', name: 'علي حسن', phone: '07809999999'),
        (username: '', name: 'أحمد بلا يوزر', phone: ''),
      ];
      expect(archiveUsersMatching(known, 'احمد'), ['ahmed.k@najaf']);
      expect(archiveUsersMatching(known, '0780999'), ['ali1@najaf']);
      expect(archiveUsersMatching(known, 'ali1'), isEmpty, reason: 'اليوزر يطابقه الخادم نفسه');
      expect(archiveUsersMatching(known, 'ع'), isEmpty, reason: 'حرفٌ واحد لا يُرسل قائمة');
      final many = [for (var i = 0; i < 100; i++) (username: 'u$i', name: 'محمد $i', phone: '')];
      expect(archiveUsersMatching(many, 'محمد'), hasLength(ReceiptsArchiveApi.usersMax));
    });

    test('الوصل: «نسخة» تلحق الرقم في كلّ التصاميم، والتاريخ ما يُعطى لا «الآن»', () {
      ReceiptDoc doc({bool copy = false, int? no = 12}) => ReceiptDoc(
            kind: ReceiptKind.payment,
            issuedAt: DateTime.utc(2026, 11, 9, 19, 29),
            shopName: 'مكتب',
            subscriberName: 'علي',
            username: 'ali@net',
            receiptNo: no,
            copy: copy,
          );
      expect(doc().receiptId, 'No. 00012');
      expect(doc(copy: true).receiptId, 'No. 00012 (نسخة)');
      expect(doc(copy: true).receiptIdPlain, 'No. 00012');
      expect(doc(copy: true).issuedText, '2026-11-09 22:29', reason: 'بتوقيت بغداد');
      final input = receiptInputOf(doc(copy: true), hasLogo: false);
      expect((input.receiptId, input.receiptNoText, input.issuedText), ('No. 00012 (نسخة)', '00012 (نسخة)', '2026-11-09 22:29'));
      expect(receiptInputOf(doc(), hasLogo: false).receiptNoText, '00012');
      expect(doc(copy: true, no: null).receiptId, endsWith(' (نسخة)'));
    });

    test('الوصل بتصميمه الافتراضيّ يُبنى نسخةً وأصلاً', () async {
      for (final copy in [false, true]) {
        final pdf = await ReceiptPdf.build(
            ReceiptDoc(
              kind: ReceiptKind.activation,
              issuedAt: DateTime.utc(2026, 11, 9, 19, 29),
              shopName: 'مكتب النجف',
              subscriberName: 'علي حسن',
              username: 'ali@net',
              receiptNo: 124,
              copy: copy,
              pay: ReceiptPay.cash,
              amount: 35000,
            ),
            a4: false);
        expect(String.fromCharCodes(pdf.bytes.take(4)), '%PDF');
      }
    });
  });

  group('النداءات', () {
    late _RcServer server;
    setUp(() async {
      server = _RcServer(await visualSetUp(s1bSasOwner));
      ApiClient.dio.httpClientAdapter = server;
    });
    tearDown(visualTearDown);

    test('القائمة: المدّة والفلاتر واليوزرات (حتى ٦٠) — للشركة المفتوحة صراحةً أو بمفتاحها', () async {
      final now = DateTime.fromMillisecondsSinceEpoch(1762000000000, isUtc: true);
      final r = await ReceiptsArchiveApi.page(companyKey: null, now: now);
      expect(r.error, isNull);
      expect(r.page!.items.map((i) => i.key).toList(), ['a:830501', 'a:830480', 'a:830455', 'a:830431', 'a:830390', 'r:3050', 'r:2001']);
      expect((r.page!.available, r.page!.next, r.page!.ownOnly), (true, null, false));
      expect(server.queries.single, {'limit': 40, 'from': '${1762000000000 - 30 * 86400000}'});
      expect(server.seen.single.extra['companyOpen'], isTrue, reason: 'المفتوحة صراحةً');

      await ReceiptsArchiveApi.page(
        companyKey: 'c0123456789ab',
        query: '  علي ',
        users: [for (var i = 0; i < 80; i++) 'u$i'],
        type: ArchiveOp.payDebt,
        state: ArchiveState.unprinted,
        spanDays: null,
        cursor: 'c40',
      );
      final q = server.queries.last;
      expect((q['q'], q['type'], q['state'], q['from'], q['cursor'], q['limit']), ('علي', 'pay_debt', 'unprinted', 'all', 'c40', 40));
      expect(q['users'].toString().split(','), hasLength(60));
      expect(server.seen.last.extra['companyKey'], 'c0123456789ab');

      await ReceiptsArchiveApi.page(companyKey: null, state: ArchiveState.all, spanDays: 7, now: now);
      expect(server.queries.last.containsKey('state'), isFalse);
      expect(server.queries.last['from'], '${1762000000000 - 7 * 86400000}');
    });

    test('القائمة: ما لا يُفهم من الصفوف يُسقط، والخطأ بنصّ الخادم، ومطفأةٌ للحساب', () async {
      server.rows = [...server.rows.take(2), {'key': 'a:1'}, {'type': 'activate'}];
      final ok = await ReceiptsArchiveApi.page(companyKey: null, spanDays: null);
      expect(ok.page!.items, hasLength(2));
      expect(ok.page!.available, isTrue);
      server.listFails = true;
      final bad = await ReceiptsArchiveApi.page(companyKey: null);
      expect((bad.page, bad.error), (null, 'تعذّر تحميل الوصولات الآن — أعد المحاولة'));
      server
        ..listFails = false
        ..available = false;
      final off = await ReceiptsArchiveApi.page(companyKey: null);
      expect(off.page!.available, isFalse);
      expect(off.page!.items, isEmpty);
    });

    test('الإصدار والإعادة: رقم العمليّة/الوصل وتلميح المشترك وحده — لا مبلغ', () async {
      final a = await ReceiptsArchiveApi.issue(
        companyKey: null,
        activityId: 830501,
        hint: const ArchiveHint(name: 'زينب كاظم', phone: '', expiration: '2026-11-20 14:30:00', packageName: null),
      );
      expect((a.existing, a.receipt!.receiptNo, a.receipt!.copy, a.receipt!.late, a.message), (false, 126, false, true, null));
      expect(server.posts.single.$1, 'issue');
      expect(server.posts.single.$2, {'activity_id': 830501, 'subscriber': {'name': 'زينب كاظم', 'expiration': '2026-11-20 14:30:00'}});
      expect(server.seen.last.extra['companyOpen'], isTrue);

      final again = await ReceiptsArchiveApi.issue(companyKey: null, activityId: 830501);
      expect((again.existing, again.receipt!.receiptNo, again.receipt!.copy, again.receipt!.reprints), (true, 126, true, 1));
      expect(server.posts.last.$2, {'activity_id': 830501}, reason: 'بلا تلميح: لا حقل subscriber');

      final rp = await ReceiptsArchiveApi.reprint(companyKey: null, receiptId: 3101);
      expect((rp.existing, rp.receipt!.receiptNo, rp.receipt!.copy, rp.receipt!.reprints), (true, 124, true, 2));
      expect(server.posts.last.$1, 'reprint');
      expect(server.posts.last.$2, {'id': 3101});
      expect(server.seen.last.extra['companyOpen'], isTrue, reason: 'كتابةٌ بشركتها صراحةً — لا وجهة ضمنيّة');

      server.nextPost = (409, {'success': false, 'code': 'RECEIPT_VOIDED', 'message': 'هذا التسديد أُلغي — لا وصل له'});
      final v = await ReceiptsArchiveApi.issue(companyKey: null, activityId: 830431);
      expect((v.receipt, v.message, v.code), (null, 'هذا التسديد أُلغي — لا وصل له', 'RECEIPT_VOIDED'));
      server.nextPost = (200, {'success': true, 'existing': false, 'receipt': {'id': 1}});
      final broken = await ReceiptsArchiveApi.reprint(companyKey: null, receiptId: 3101);
      expect((broken.receipt, broken.message), (null, 'تعذّرت إعادة الطباعة الآن — أعد المحاولة'), reason: 'وصلٌ لا يُفهم ليس نجاحاً');
    });

    test('مفتاح القسم: مفتوح / مطفأ / خادمٌ أقدم / تعذّر — والبطاقة لا تظهر بلا تأكيد', () async {
      expect(await ReceiptsArchiveApi.probe(), isTrue);
      expect(server.probes.single.extra['companyOpen'], isTrue);
      server.available = false;
      expect(await ReceiptsArchiveApi.probe(), isFalse);

      ReceiptsArchiveState.reset();
      expect(ReceiptsArchiveState.visible, isFalse, reason: 'قبل الجواب: لا بطاقة');
      server.available = true;
      await ReceiptsArchiveState.ensureFresh(force: true);
      expect(ReceiptsArchiveState.visible, isTrue);
      final n = server.probes.length;
      await ReceiptsArchiveState.ensureFresh();
      expect(server.probes, hasLength(n), reason: 'حالٌ حديثة لا تُسأل ثانية');
      ReceiptsArchiveState.reset();
      expect(ReceiptsArchiveState.visible, isFalse, reason: 'تبديل الجلسة يمسحها');
    });

    test('مفتاح القسم: خادمٌ أقدم (400 من /:id) أو مزوّدٌ لا يمرّره ⇒ مطفأ؛ وسقوطٌ ⇒ لا حكم', () async {
      ApiClient.dio.httpClientAdapter = _Canned(400, {'success': false, 'message': 'id غير صالح'});
      expect(await ReceiptsArchiveApi.probe(), isFalse);
      ApiClient.dio.httpClientAdapter = _Canned(200, {'success': true, 'data': null});
      expect(await ReceiptsArchiveApi.probe(), isFalse, reason: 'الردّ الآمن بلا available');
      ApiClient.dio.httpClientAdapter = _Canned(403, {'success': false, 'code': 'PERMISSION_DENIED'});
      expect(await ReceiptsArchiveApi.probe(), isFalse);
      ApiClient.dio.httpClientAdapter = _Canned(503, {'success': false});
      expect(await ReceiptsArchiveApi.probe(), isNull);
    });
  });

  group('الوصل من الأرشيف', () {
    late _RcServer server;
    late _FakeBackend fake;
    setUp(() async {
      server = _RcServer(await visualSetUp(s1bSasOwner));
      ApiClient.dio.httpClientAdapter = server;
      ReceiptSettingsApi.clearCache();
      fake = _FakeBackend();
      PrintOutput.backend = fake;
      AppPlatform.debugIsDesktop = true;
      PrintPrefs.printer.value = null;
    });
    tearDown(() async {
      AppPlatform.debugIsDesktop = null;
      ReceiptSettingsApi.clearCache();
      await visualTearDown();
    });

    ArchivedReceipt receipt({String? idx = '7', ReceiptKind? kind = ReceiptKind.payment, bool copy = true}) => ArchivedReceipt(
          id: 3101,
          receiptNo: 124,
          kind: kind,
          issuedAt: DateTime.utc(2026, 11, 9, 19, 29),
          printedAt: DateTime.utc(2026, 11, 9, 19, 29),
          copy: copy,
          username: 'haider.s@najaf',
          name: 'حيدر سالم',
          idx: idx,
          amount: 15000,
          newBalance: -5000,
          issuer: 'مكتب النجف',
        );

    testWidgets('يُطبع بلا أرشفةٍ ثانية، برمز QR للساس حين يطبعه التصميم', (t) async {
      late PrintResult r;
      await t.runAsync(() async => r = await ReceiptService.printArchived(receipt()));
      expect(r.ok, isTrue);
      expect(fake.calls, ['layout']);
      expect(server.archivedAgain, 0, reason: 'صفّه قائم — لا رقم ثانٍ');
      expect(server.links, ['7']);
    });

    testWidgets('بلا رقم مشترك أو التصميم بلا رمز ⇒ لا رابط يُطلب؛ والنوع القديم لا يُطبع', (t) async {
      late PrintResult a;
      await t.runAsync(() async => a = await ReceiptService.printArchived(receipt(idx: null)));
      expect(a.ok, isTrue);
      expect(server.links, isEmpty);
      server.showQr = false;
      ReceiptSettingsApi.clearCache();
      await t.runAsync(() async => a = await ReceiptService.printArchived(receipt()));
      expect(a.ok, isTrue);
      expect(server.links, isEmpty);
      late PrintResult old;
      await t.runAsync(() async => old = await ReceiptService.printArchived(receipt(kind: null)));
      expect((old.ok, old.error), (false, 'هذا النوع من الوصولات لا يُطبع'));
      expect(fake.calls, hasLength(2));
      expect(server.archivedAgain, 0);
    });
  });

  group('الشاشة', () {
    tearDown(visualTearDown);

    Future<_RcServer> open(WidgetTester t, Scenario s, {VisualDevice d = phone, void Function(_RcServer)? prep}) async {
      final server = _RcServer(await visualSetUp(s));
      prep?.call(server);
      ApiClient.dio.httpClientAdapter = server;
      await pumpVisual(t, d, home: (_) => const ReceiptsArchiveScreen());
      await settle(t, seconds: 2);
      return server;
    }

    testWidgets('المالك: كلّ عمليّةٍ ووصلها — الاسم من قائمة المشتركين، «لم يُطبع» و«No.»، والملغى بلا طباعة', (t) async {
      final server = await open(t, s1bSasOwner);
      expect(server.queries.single['limit'], 40);
      expect(find.byType(ArchiveRowTile), findsNWidgets(7));
      // الاسم من قائمة المشتركين لغير المطبوع، ومن الوصل للمطبوع
      expect(find.text('زينب كاظم'), findsOneWidget);
      expect(find.text('حيدر سالم'), findsOneWidget);
      expect(find.text('عبّاس رضا'), findsOneWidget);
      expect(find.text('لم يُطبع'), findsNWidgets(3));
      expect(find.text('No. 00124'), findsOneWidget);
      expect(find.text('أُعيد 1'), findsOneWidget);
      expect(find.text('ملغى'), findsOneWidget);
      expect(find.textContaining('50,000'), findsOneWidget);
      final voided = t.widget<IconButton>(find.descendant(of: find.byType(ArchiveRowTile).at(3), matching: find.byType(IconButton)));
      expect(voided.onPressed, isNull, reason: 'تسديدٌ ملغى لا يُطبع');
      await shoot(t, s1bSasOwner, 'receipts_archive', phone, server.inner as VisualServer);

      // نافذة غير المطبوع
      await t.tap(find.text('زينب كاظم'));
      await settle(t, seconds: 1);
      expect(find.text('تفعيل — لم يُطبع وصله'), findsOneWidget);
      expect(find.text('طباعة الوصل'), findsOneWidget);
      expect(find.textContaining('20,000'), findsOneWidget, reason: 'المدفوع نقداً');
      await shoot(t, s1bSasOwner, 'receipts_archive_sheet_unprinted', phone, server.inner as VisualServer);
      await t.tap(find.text('إغلاق'));
      await settle(t, seconds: 1);

      // نافذة الملغى: للعرض فقط
      await t.tap(find.text('أحمد كامل'));
      await settle(t, seconds: 1);
      expect(find.text('أُلغي هذا التسديد — لا وصل له'), findsOneWidget);
      expect(find.text('للعرض فقط.'), findsOneWidget);
      await shoot(t, s1bSasOwner, 'receipts_archive_sheet_voided', phone, server.inner as VisualServer);
      await t.tap(find.text('طباعة الوصل'));
      await settle(t, seconds: 1);
      expect(server.posts, isEmpty, reason: 'الزرّ معطَّل');
    });

    testWidgets('الوضع الداكن والشاشة الضيّقة: لا فيض، والمبلغ قبل اسم الباقة', (t) async {
      final server = await open(t, s1bSasOwner, d: phoneDark);
      await shoot(t, s1bSasOwner, 'receipts_archive', phoneDark, server.inner as VisualServer);
      await t.tap(find.text('حيدر سالم'));
      await settle(t, seconds: 1);
      expect(find.text('وصل تسديد دين'), findsOneWidget);
      expect(find.text('إعادة طباعة'), findsOneWidget);
      await shoot(t, s1bSasOwner, 'receipts_archive_sheet_printed', phoneDark, server.inner as VisualServer);
    });

    testWidgets('٣٢٠: الصفوف لا تفيض', (t) async {
      final server = await open(t, s1bSasOwner, d: _narrow, prep: (s) {
        s.rows = [
          ...s.rows,
          _RcServer._row('a:830210', 'activate', 70, 'noor.h@najaf', o: {'amount': 25000, 'pay': 'credit', 'package': 'اقتصاديّة 25 ميغا — عرض الشتاء الطويل الاسم جدّاً'}),
        ];
      });
      expect(t.takeException(), isNull);
      await shoot(t, s1bSasOwner, 'receipts_archive', _narrow, server.inner as VisualServer);
    });

    testWidgets('البحث بالاسم يرسل يوزرات من طابقه؛ والفلاتر تُعيد الجلب', (t) async {
      final server = await open(t, s1bSasOwner);
      await t.enterText(find.byType(TextField), 'زينب');
      await settle(t, seconds: 2);
      final q = server.queries.last;
      expect(q['q'], 'زينب');
      expect(q['users'], 'zainab.k@najaf', reason: 'سطر العمليّة بلا اسم — اليوزر من قائمة المشتركين');
      expect(find.byType(ArchiveRowTile), findsOneWidget);
      expect(find.text('زينب كاظم'), findsOneWidget);

      // رقم الوصل
      await t.enterText(find.byType(TextField), '124');
      await settle(t, seconds: 2);
      expect(server.queries.last['q'], '124');
      expect(find.text('حيدر سالم'), findsOneWidget);
      expect(find.byType(ArchiveRowTile), findsOneWidget);

      // لا نتيجة
      await t.enterText(find.byType(TextField), 'zzzz');
      await settle(t, seconds: 2);
      expect(find.text('لا نتيجة'), findsOneWidget);
      await t.enterText(find.byType(TextField), '');
      await settle(t, seconds: 2);

      await t.tap(find.widgetWithText(ListFilterChip, 'لم تُطبع'));
      await settle(t, seconds: 1);
      expect(server.queries.last['state'], 'unprinted');
      expect(find.byType(ArchiveRowTile), findsNWidgets(3));
      await t.tap(find.widgetWithText(ListFilterChip, 'المطبوعة'));
      await settle(t, seconds: 1);
      expect(server.queries.last['state'], 'printed');
      expect(find.text('لم يُطبع'), findsNothing);

      // النوع والمدّة
      await t.tap(find.byKey(const ValueKey('archive-type')));
      await settle(t, seconds: 1);
      await t.tap(find.text('تسديد دين').last);
      await settle(t, seconds: 1);
      expect(server.queries.last['type'], 'pay_debt');
      await t.tap(find.byKey(const ValueKey('archive-span')));
      await settle(t, seconds: 1);
      await t.tap(find.text('كلّ المدّة').last);
      await settle(t, seconds: 1);
      expect(server.queries.last['from'], 'all');
    });

    testWidgets('«تحميل المزيد» يلحق الصفحة التالية بموضعها بلا تكرار', (t) async {
      final server = await open(t, s1bSasOwner, prep: (s) => s.pageSize = 3);
      expect(find.byType(ArchiveRowTile), findsNWidgets(3));
      await t.scrollUntilVisible(find.text('تحميل المزيد'), 200, scrollable: find.byType(Scrollable).first);
      await t.tap(find.text('تحميل المزيد'));
      await settle(t, seconds: 1);
      expect(server.queries.last['cursor'], 'c3');
      expect(find.byType(ArchiveRowTile), findsNWidgets(6));
      await t.scrollUntilVisible(find.text('تحميل المزيد'), 200, scrollable: find.byType(Scrollable).first);
      await t.tap(find.text('تحميل المزيد'));
      await settle(t, seconds: 1);
      expect(find.byType(ArchiveRowTile, skipOffstage: false), findsNWidgets(7));
      expect(find.text('تحميل المزيد'), findsNothing);
    });

    testWidgets('طباعة ما لم يُطبع: يصدر برقمه بتلميح المشترك، يُحدَّث الصفّ بمكانه، ولا أرشفة ثانية — ثمّ إعادته نسخةً', (t) async {
      final fake = _FakeBackend();
      PrintOutput.backend = fake;
      AppPlatform.debugIsDesktop = true;
      PrintPrefs.printer.value = null;
      ReceiptSettingsApi.clearCache();
      addTearDown(() {
        AppPlatform.debugIsDesktop = null;
        ReceiptSettingsApi.clearCache();
      });
      final server = await open(t, s1bSasOwner);

      Future<void> waitPrint(int n) async {
        // الطلبات الوهميّة تمضي بالوقت المزيّف، وقراءة الخطّ وبناء الـPDF بالحقيقيّ — نناوب بينهما.
        for (var i = 0; i < 60 && fake.calls.length < n; i++) {
          await t.pump(const Duration(milliseconds: 100));
          await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        }
        await settle(t, seconds: 1);
      }

      // من زرّ الصفّ الأوّل (زينب — لم يُطبع)
      await t.tap(find.descendant(of: find.byType(ArchiveRowTile).first, matching: find.byType(IconButton)));
      await waitPrint(1);
      expect(server.posts.single.$1, 'issue');
      final body = server.posts.single.$2;
      expect(body['activity_id'], 830501);
      expect((body['subscriber'] as Map)['name'], 'زينب كاظم');
      expect((body['subscriber'] as Map).containsKey('expiration'), isTrue);
      expect(body.containsKey('amount'), isFalse, reason: 'المبلغ من سطر العمليّة في الخادم');
      expect(fake.calls, ['layout']);
      expect(server.archivedAgain, 0);
      expect(find.text('No. 00126'), findsOneWidget, reason: 'الصفّ صار له وصل بمكانه');
      expect(find.text('لم يُطبع'), findsNWidgets(2));
      expect(server.queries, hasLength(1), reason: 'بلا إعادة جلب القائمة');

      // الصفّ نفسه ثانيةً ⇒ إعادة (نسخة) لا رقمٌ جديد
      await t.tap(find.descendant(of: find.byType(ArchiveRowTile).first, matching: find.byType(IconButton)));
      await waitPrint(2);
      expect(server.posts.last.$1, 'reprint');
      expect(fake.calls, ['layout', 'layout']);
      expect(find.text('No. 00126'), findsOneWidget);
      expect(find.text('أُعيد 1'), findsNWidgets(2));

      // من النافذة: وصلٌ مؤرشف
      await t.tap(find.text('حيدر سالم'));
      await settle(t, seconds: 1);
      await t.tap(find.text('إعادة طباعة'));
      await waitPrint(3);
      expect(server.posts.last.$1, 'reprint');
      expect(server.posts.last.$2, {'id': 3101});
      expect(find.text('أُعيد 2'), findsOneWidget);
      expect(server.archivedAgain, 0);

      // رفض الخادم يُعرض بنصّه ولا يُطبع شيء
      server.nextPost = (409, {'success': false, 'code': 'RECEIPT_VOIDED', 'message': 'هذا التسديد أُلغي — لا وصل له'});
      await t.tap(find.descendant(of: find.byType(ArchiveRowTile).at(2), matching: find.byType(IconButton)));
      await settle(t, seconds: 2);
      expect(find.text('هذا التسديد أُلغي — لا وصل له'), findsOneWidget);
      expect(fake.calls, hasLength(3));
      // إشعارات النتيجة بمؤقّتاتها — تُترك تنتهي
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 8));
    });

    testWidgets('الموظّف الذي يرى عمليّاته وحدها: سطرٌ يقول ذلك', (t) async {
      final server = await open(t, _elEmployeeView, prep: (s) => s.ownOnly = true);
      expect(find.text('تظهر لك عمليّاتك وما طبعته أنت.'), findsOneWidget);
      await shoot(t, _elEmployeeView, 'receipts_archive_own', phone, server.inner as VisualServer);
    });

    testWidgets('حسابٌ لم يُفتح له المفتاح: «غير مفعّل» بلا صفوف', (t) async {
      final off = await open(t, s1bSasOwner, prep: (s) => s.available = false);
      expect(find.text('«أرشيف الوصولات» غير مفعّل لهذا الحساب بعد'), findsOneWidget);
      expect(find.byType(ArchiveRowTile), findsNothing);
      expect(off.posts, isEmpty);
    });

    testWidgets('سقوط القائمة يُعرض بنصّ الخادم', (t) async {
      await open(t, s1bSasOwner, prep: (s) => s.listFails = true);
      expect(find.text('تعذّر تحميل الوصولات الآن — أعد المحاولة'), findsOneWidget);
    });
  });

  group('«قوائم أخرى»', () {
    tearDown(() async {
      ReceiptsArchiveState.reset();
      await visualTearDown();
    });

    testWidgets('البطاقة بمفتاح الخادم: غائبةٌ حتى يُفتح، ثمّ تفتح القسم', (t) async {
      final server = _RcServer(await visualSetUp(s1bSasOwner))..available = false;
      ApiClient.dio.httpClientAdapter = server;
      ReceiptsArchiveState.reset();
      await pumpVisual(t, phone, home: (_) => const MoreModulesScreen());
      await settle(t, seconds: 2);
      expect(server.probes, isNotEmpty, reason: 'الاستماع يطلب الحال');
      expect(find.text(ReceiptsArchiveScreen.title, skipOffstage: false), findsNothing);

      ReceiptsArchiveState.debugSet(true);
      await settle(t, seconds: 1);
      await t.scrollUntilVisible(find.text(ReceiptsArchiveScreen.title), 200, scrollable: find.byType(Scrollable).first);
      expect(find.text(ReceiptsArchiveScreen.title), findsOneWidget);
      await t.tap(find.text(ReceiptsArchiveScreen.title));
      await settle(t, seconds: 2);
      expect(find.byType(ReceiptsArchiveScreen), findsOneWidget);

    });

    testWidgets('موظّفٌ بلا «عرض المشتركين»: البطاقة بمكانها مقفلة — النقر لا يفتحها ولا يطلب قائمتها', (t) async {
      final server = _RcServer(await visualSetUp(_elEmployeeNone));
      ApiClient.dio.httpClientAdapter = server;
      ReceiptsArchiveState.debugSet(true);
      await pumpVisual(t, phone, home: (_) => const MoreModulesScreen());
      await settle(t, seconds: 2);
      await t.scrollUntilVisible(find.text(ReceiptsArchiveScreen.title), 200, scrollable: find.byType(Scrollable).first);
      await t.tap(find.text(ReceiptsArchiveScreen.title));
      await settle(t, seconds: 1);
      expect(find.byType(ReceiptsArchiveScreen), findsNothing);
      expect(server.queries, isEmpty);
      // إشعار «لا صلاحيّة» بمؤقّته — يُترك ينتهي
      await t.pump(const Duration(seconds: 8));
    });
  });
}

/// ردٌّ واحد لكلّ طلب — لحالات مفتاح القسم.
class _Canned implements HttpClientAdapter {
  _Canned(this.status, this.body);
  final int status;
  final Map<String, dynamic> body;

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async =>
      ResponseBody.fromString(jsonEncode(body), status, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      });

  @override
  void close({bool force = false}) {}
}
