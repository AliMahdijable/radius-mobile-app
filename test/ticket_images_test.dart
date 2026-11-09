import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:rad_mysvcs/api/tickets_api.dart';
import 'package:rad_mysvcs/screens/tickets/ticket_image.dart';
import 'package:rad_mysvcs/screens/tickets/ticket_thread_screen.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:rad_mysvcs/services/provider_service.dart';

import 'sim_el/sim_harness.dart';

/// صور «التذاكر» بتطبيق المدير (٩ نوفمبر — «ولا تنسى ضغط الصورة»): الضغط (أطول ضلع ١٦٠٠، ≤ ٤٠٠ ك.ب، JPEG، بلا EXIF/GPS، الاتّجاه
/// مطبَّق، الشفّاف على أبيض، لا تكبير)، والإرفاق والإزالة والإرسال، والعرض (المصغّرة، ملء الشاشة، المحذوفة، الفاشلة وإعادتها)، ورفض
/// الخادم.
const _v = SimVariant(390, dark: false);

/// ردٌّ ببايتات صورة (كاختبار طلبات التجديد).
class _BytesReply extends SimReply {
  const _BytesReply(this.bytes) : super(200);
  final Uint8List bytes;

  @override
  ResponseBody toBody() => ResponseBody(Stream.value(bytes), 200, headers: {
        Headers.contentTypeHeader: ['image/jpeg'],
      });
}

String _iso(Duration ago) => DateTime.now().toUtc().subtract(ago).toIso8601String();

Map<String, dynamic> _ticket(int id, String status) => {
      'id': id,
      'status': status,
      'category': 'device',
      'subject': null,
      'subscriber': {'idx': '$id', 'username': 'ali.abbas', 'name': 'علي عباس'},
      'provider': 'sas4',
      'unread': false,
      'seen_by_subscriber': true,
      'message_count': 1,
      'last_author': 'subscriber',
      'last_preview': 'صورة',
      'last_activity_at': _iso(const Duration(minutes: 7)),
      'created_at': _iso(const Duration(minutes: 30)),
      'updated_at': _iso(const Duration(minutes: 7)),
      'closed_at': null,
      'status_by': null,
      'status_at': null,
      'via': 'app',
      'can_reply': true,
      'can_reopen': false,
      'actions': ['in_progress', 'resolved', 'closed'],
      'image_count': 1,
    };

Map<String, dynamic> _msg(int id, String side, String body, {Map<String, dynamic>? image}) => {
      'id': id,
      'side': side,
      'author': side == 'subscriber' ? null : 'boss',
      'kind': 'text',
      'event': null,
      'body': body,
      'image': image,
      'created_at': _iso(Duration(minutes: 30 - id)),
    };

Map<String, dynamic> _img({bool available = true, int w = 40, int h = 30}) =>
    {'available': available, 'mime': 'image/jpeg', 'width': w, 'height': h, 'bytes': 900};

/// JPEG حقيقيّ بـEXIF (APP1) من الحزمة نفسها: اتّجاه [orientation] ووصفٌ فيه «GPS-SECRET» ومرجع GPS — لا يبقى منه شيءٌ بعد الضغط.
Uint8List _jpegWithExif(img.Image im, {int orientation = 1}) {
  final x = img.Image.from(im);
  x.exif.imageIfd.orientation = orientation;
  x.exif.imageIfd['ImageDescription'] = 'GPS-SECRET-33.31,44.36';
  x.exif.gpsIfd[1] = img.IfdValueAscii('N');
  return img.encodeJpg(x, quality: 90);
}

/// مقاطع JPEG قبل المسح: هل فيها APP1 (EXIF/XMP)؟
bool _hasApp1(Uint8List b) {
  var i = 2;
  while (i + 4 < b.length && b[i] == 0xff) {
    final m = b[i + 1];
    if (m == 0xda) return false;
    if (m == 0xe1) return true;
    i += 2 + ((b[i + 2] << 8) | b[i + 3]);
  }
  return false;
}

img.Image _photo(int w, int h, {int noise = 0, int seed = 7}) {
  final r = math.Random(seed);
  final im = img.Image(width: w, height: h);
  for (final p in im) {
    final n = noise == 0 ? 0 : r.nextInt(noise);
    p
      ..r = (p.x * 255 ~/ w + n).clamp(0, 255)
      ..g = (p.y * 255 ~/ h + n).clamp(0, 255)
      ..b = (128 + n).clamp(0, 255);
  }
  return im;
}

void main() {
  group('الضغط', () {
    test('صورة هاتفٍ كبيرة بـEXIF واتّجاهٍ ٩٠°: أطول ضلع ١٦٠٠ بالاتّجاه الصحيح، JPEG ≤ ٤٠٠ ك.ب، وبلا EXIF ولا نصّ GPS', () {
      final raw = _jpegWithExif(_photo(3200, 2400, noise: 24), orientation: 6);
      final rawText = String.fromCharCodes(raw);
      expect([rawText.contains('Exif'), rawText.contains('GPS-SECRET'), _hasApp1(raw)], [true, true, true], reason: 'الأصل يحمل EXIF');
      final rawDims = img.decodeJpg(raw)!;
      expect([rawDims.width, rawDims.height], [2400, 3200], reason: 'المفكِّك يطبّق اتّجاه EXIF (٩٠°)');
      final out = prepareTicketJpeg(raw);
      expect(out.sublist(0, 3), [0xff, 0xd8, 0xff], reason: 'JPEG');
      expect(out.length, lessThanOrEqualTo(ticketImageTargetBytes));
      final d = img.decodeJpg(out)!;
      expect([d.width, d.height], [1200, 1600], reason: 'مدوَّرة ثمّ مصغَّرة: أطول ضلع ١٦٠٠');
      expect(_hasApp1(out), false, reason: 'بلا EXIF');
      expect(String.fromCharCodes(out).contains('GPS-SECRET'), false);
      expect(d.exif.isEmpty, true);
    });

    test('الحدّ يُحترم بالجودة ثمّ بالتصغير: ضجيجٌ بهدفٍ صغير ⇒ ≤ الهدف وأبعادٌ أصغر', () {
      final raw = Uint8List.fromList(img.encodePng(_photo(900, 700, noise: 255)));
      final out = prepareTicketJpeg(raw, target: 60 * 1024);
      expect(out.length, lessThanOrEqualTo(60 * 1024));
      final d = img.decodeJpg(out)!;
      expect(d.width < 900 && (d.width / d.height - 900 / 700).abs() < 0.02, true, reason: 'صُغِّرت بنسبتها: ${d.width}×${d.height}');
    });

    test('الصغيرة لا تُكبَّر لكنّها تُعاد ترميزاً بلا EXIF؛ الطويلة ⇒ ٢٠٠×١٦٠٠؛ والشفّاف على أبيض', () {
      final small = prepareTicketJpeg(_jpegWithExif(_photo(320, 240)));
      final s = img.decodeJpg(small)!;
      expect([s.width, s.height], [320, 240]);
      expect(_hasApp1(small), false);
      final tall = img.decodeJpg(prepareTicketJpeg(Uint8List.fromList(img.encodeJpg(_photo(500, 4000)))))!;
      expect([tall.width, tall.height], [200, 1600]);
      final clear = img.Image(width: 60, height: 40, numChannels: 4); // شفّافٌ كلّه
      final w = img.decodeJpg(prepareTicketJpeg(Uint8List.fromList(img.encodePng(clear))))!;
      final px = w.getPixel(30, 20);
      expect([px.r >= 245, px.g >= 245, px.b >= 245], [true, true, true], reason: 'أبيض لا أسود');
    });

    test('ما لا يُقرأ ⇒ TicketImageError(decode) بنصٍّ عربيّ', () {
      expect(() => prepareTicketJpeg(Uint8List.fromList(List.filled(64, 7))),
          throwsA(isA<TicketImageError>().having((e) => e.reason, 'reason', 'decode')));
      expect(const TicketImageError('too-big').message, 'الصورة كبيرة جداً — اختر صورةً أخرى');
    });
  });

  group('الواجهة', () {
    late SimServer server;
    final jpeg = Uint8List.fromList(img.encodeJpg(_photo(40, 30), quality: 70));
    final picks = <bool>[];
    setUpAll(simSetUpAll);
    setUp(() async {
      TicketThreadScreen.pollEvery = null;
      TicketsState.reset();
      TicketsApi.debugClearImages();
      ProviderService.debugSet(null);
      PermissionsService.debugSet(isEmployee: false);
      picks.clear();
      TicketThreadScreen.pickImage = ({required bool camera}) async {
        picks.add(camera);
        return jpeg;
      };
      TicketThreadScreen.imageLoader = null;
      server = await simSetUp(secure: {'auth.admin_id': 'speed:7', 'auth.admin_username': 'boss'});
      server.reply('GET', '/api/v2/portal/tickets/summary', 200, {'success': true, 'available': true, 'can_view': true, 'can_reply': true});
    });
    tearDown(() {
      TicketThreadScreen.pickImage = pickTicketImage;
      TicketThreadScreen.imageLoader = null;
      TicketsState.reset();
      PermissionsService.debugReset();
    });

    testWidgets(
        'الإرفاق: المعرض ⇒ معاينةٌ بزرّ إزالة؛ الإزالة تُسقطها؛ ثمّ إرسال الصورة وحدها ⇒ data:image/jpeg ونصٌّ فارغ، والفقاعة بمصغّرتها',
        (t) async {
      server.reply('GET', '/api/v2/portal/tickets/9', 200, {
        'success': true,
        'ticket': _ticket(9, 'open'),
        'messages': [_msg(1, 'subscriber', 'الراوتر يطفي')]
      });
      server.on('POST', '/api/v2/portal/tickets/9/reply',
          (req) => SimReply(200, {'success': true, 'ticket': _ticket(9, 'answered'), 'message': _msg(21, 'manager', '', image: _img())}));
      server.on('GET', '/api/v2/portal/tickets/9/messages/21/image', (_) => _BytesReply(jpeg));
      await pumpSim(t, _v, home: (_) => const TicketThreadScreen(ticketId: 9));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('ticket-attach-preview')), findsNothing);
      await t.tap(find.byKey(const ValueKey('ticket-attach')));
      await t.pumpAndSettle();
      expect(find.text('الكاميرا'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('ticket-image-gallery')));
      await t.pumpAndSettle();
      expect(picks, [false], reason: 'المعرض');
      expect(find.byKey(const ValueKey('ticket-attach-preview')), findsOneWidget);
      expect(find.textContaining('صورة · 1 ك.ب'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('ticket-attach-remove')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('ticket-attach-preview')), findsNothing, reason: 'أُزيلت قبل الإرسال');
      await t.tap(find.byKey(const ValueKey('ticket-send')));
      await t.pumpAndSettle();
      expect(server.calls('POST', '/api/v2/portal/tickets/9/reply'), isEmpty, reason: 'لا نصّ ولا صورة');
      await t.tap(find.byKey(const ValueKey('ticket-attach')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('ticket-image-camera')));
      await t.pumpAndSettle();
      expect(picks, [false, true]);
      await t.tap(find.byKey(const ValueKey('ticket-send')));
      await t.pumpAndSettle();
      final body = server.bodies('POST', '/api/v2/portal/tickets/9/reply').single;
      expect(body['body'], '');
      expect((body['image'] as String).startsWith('data:image/jpeg;base64,'), true);
      expect(body.keys.toSet(), {'body', 'image'});
      expect(find.byKey(const ValueKey('ticket-attach-preview')), findsNothing, reason: 'أُرسلت');
      expect(find.byKey(const ValueKey('ticket-img-21')), findsOneWidget, reason: 'الفقاعة بصورتها');
      expect(server.calls('GET', '/api/v2/portal/tickets/9/messages/21/image'), hasLength(1));
      expect(t.takeException(), isNull);
      await simDrain(t);
    });

    testWidgets('العرض: المصغّرة تُجلب بمسارها وتُكبَّر بالنقر؛ المحذوفة «حُذفت» بلا طلب؛ الفاشلة «اضغط للإعادة» ثمّ تظهر', (t) async {
      var fail = true;
      server.reply('GET', '/api/v2/portal/tickets/9', 200, {
        'success': true,
        'ticket': _ticket(9, 'open'),
        'messages': [
          _msg(1, 'subscriber', 'هذي الصورة', image: _img()),
          _msg(2, 'subscriber', 'قديمة', image: _img(available: false)),
          _msg(3, 'manager', '', image: _img()),
        ],
      });
      server.on('GET', '/api/v2/portal/tickets/9/messages/1/image', (_) => _BytesReply(jpeg));
      server.on('GET', '/api/v2/portal/tickets/9/messages/3/image', (_) {
        if (fail) {
          fail = false;
          return const SimReply(500, {'success': false});
        }
        return _BytesReply(jpeg);
      });
      await pumpSim(t, _v, home: (_) => const TicketThreadScreen(ticketId: 9));
      await t.pumpAndSettle();
      expect(find.text('هذي الصورة'), findsOneWidget, reason: 'النصّ تحت الصورة');
      expect(find.text('حُذفت الصورة — التذاكر وصورها تُحذف بعد ٣ أشهر من فتحها'), findsOneWidget);
      expect(server.calls('GET', '/api/v2/portal/tickets/9/messages/2/image'), isEmpty, reason: 'المحذوفة لا تُطلب');
      expect(find.text('تعذّر تحميل الصورة — اضغط للإعادة'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('ticket-img-3')));
      await t.pumpAndSettle();
      expect(find.text('تعذّر تحميل الصورة — اضغط للإعادة'), findsNothing);
      expect(server.calls('GET', '/api/v2/portal/tickets/9/messages/3/image'), hasLength(2));
      await t.tap(find.byKey(const ValueKey('ticket-img-1')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('ticket-image-viewer')), findsOneWidget);
      expect(find.byType(InteractiveViewer), findsOneWidget);
      // الذاكرة: إعادة فتح المحادثة لا تطلب الصورة ثانيةً
      await t.tap(find.byKey(const ValueKey('ticket-viewer-close')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('ticket-image-viewer')), findsNothing);
      expect(server.calls('GET', '/api/v2/portal/tickets/9/messages/1/image'), hasLength(1));
      expect(t.takeException(), isNull);
      await simDrain(t);
    });

    testWidgets('صورةٌ لا تُضغط ⇒ نصّ السبب بلا معاينة؛ ورفض الخادم (حدّ الصور) ⇒ رسالته والصورة باقيةٌ للتعديل', (t) async {
      server.reply('GET', '/api/v2/portal/tickets/9', 200, {
        'success': true,
        'ticket': _ticket(9, 'open'),
        'messages': [_msg(1, 'subscriber', 'مرحبا')]
      });
      server.reply('POST', '/api/v2/portal/tickets/9/reply', 409,
          {'success': false, 'code': 'TICKET_IMAGES_FULL', 'message': 'وصلت التذكرة حدّ الصور (20)'});
      TicketThreadScreen.pickImage = ({required bool camera}) async => throw const TicketImageError('too-big');
      await pumpSim(t, _v, home: (_) => const TicketThreadScreen(ticketId: 9));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('ticket-attach')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('ticket-image-gallery')));
      await t.pumpAndSettle();
      expect(find.text('الصورة كبيرة جداً — اختر صورةً أخرى'), findsOneWidget);
      expect(find.byKey(const ValueKey('ticket-attach-preview')), findsNothing);
      expect(t.widget<IconButton>(find.byKey(const ValueKey('ticket-attach'))).onPressed, isNotNull, reason: 'الزرّ يعود متاحاً');
      t.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger)).removeCurrentSnackBar();
      await t.pumpAndSettle();
      TicketThreadScreen.pickImage = ({required bool camera}) async => jpeg;
      await t.tap(find.byKey(const ValueKey('ticket-attach')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('ticket-image-gallery')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const ValueKey('ticket-composer')), 'شوف الصورة');
      await t.tap(find.byKey(const ValueKey('ticket-send')));
      await t.pumpAndSettle();
      expect(find.text('وصلت التذكرة حدّ الصور (20)'), findsOneWidget);
      expect(find.text('شوف الصورة'), findsOneWidget, reason: 'النصّ باقٍ أيضاً');
      expect(find.byKey(const ValueKey('ticket-attach-preview')), findsOneWidget, reason: 'لم تُرسل ⇒ باقية');
      expect(server.bodies('POST', '/api/v2/portal/tickets/9/reply').single['body'], 'شوف الصورة');
      await simDrain(t);
    });

    test('النموذج: صورة الرسالة ونسبتها، وimage_count للتذكرة', () {
      final m = TicketMessage.fromJson(_msg(5, 'subscriber', '', image: _img(w: 1200, h: 1600)))!;
      expect([m.image!.available, m.image!.width, m.image!.height, m.hasText], [true, 1200, 1600, false]);
      expect(m.image!.aspect, closeTo(0.75, 0.001));
      expect(TicketMessage.fromJson(_msg(6, 'manager', 'نصّ'))!.image, isNull);
      expect(TicketImage.fromJson({'available': false})!.aspect, closeTo(4 / 3, 0.001), reason: 'بلا أبعاد ⇒ ٤:٣');
      expect(Ticket.fromJson(_ticket(9, 'open'))!.imageCount, 1);
    });
  });
}
