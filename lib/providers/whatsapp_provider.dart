import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../core/constants/api_constants.dart';
import '../core/network/dio_client.dart';
import '../core/services/socket_service.dart';
import '../core/services/storage_service.dart';
import '../models/whatsapp_status_model.dart';

class WhatsAppState {
  final WhatsAppStatusModel status;
  final String? qrCode;
  final String? pairCode; // كود الربط برقم الهاتف (8 خانات)
  final bool isConnecting;
  final String? error;

  const WhatsAppState({
    this.status = const WhatsAppStatusModel(),
    this.qrCode,
    this.pairCode,
    this.isConnecting = false,
    this.error,
  });

  WhatsAppState copyWith({
    WhatsAppStatusModel? status,
    String? qrCode,
    String? pairCode,
    bool? isConnecting,
    String? error,
  }) {
    return WhatsAppState(
      status: status ?? this.status,
      qrCode: qrCode ?? this.qrCode,
      pairCode: pairCode ?? this.pairCode,
      isConnecting: isConnecting ?? this.isConnecting,
      error: error,
    );
  }
}

class WhatsAppNotifier extends StateNotifier<WhatsAppState> {
  final Dio _dio;
  final SocketService _socket;
  final StorageService _storage;
  StreamSubscription? _statusSub;
  StreamSubscription? _qrSub;
  bool _pollingQr = false;
  bool _pollingPair = false;

  WhatsAppNotifier(this._dio, this._socket, this._storage)
      : super(const WhatsAppState()) {
    _listenToSocket();
  }

  void _listenToSocket() {
    _statusSub = _socket.whatsappStatus.listen((data) {
      final event = data['event'] as String?;
      if (event == 'connected') {
        state = state.copyWith(
          status: WhatsAppStatusModel(
            connected: true,
            phone: data['phone']?.toString(),
            pushname: data['pushname']?.toString(),
            platform: data['platform']?.toString(),
          ),
          isConnecting: false,
          qrCode: null,
        );
      } else if (event == 'disconnected') {
        state = state.copyWith(
          status: const WhatsAppStatusModel(connected: false),
          isConnecting: false,
        );
      } else if (event == 'error') {
        state = state.copyWith(
          error: data['message']?.toString(),
          isConnecting: false,
        );
      }
    });

    _qrSub = _socket.qrCode.listen((data) {
      state = state.copyWith(
        qrCode: data['qrCode']?.toString(),
        isConnecting: true,
      );
    });
  }

  Future<String?> _getAdminId() => _storage.getAdminId();
  Future<String?> _getUsername() => _storage.getAdminUsername();

  Future<void> fetchStatus({bool live = true}) async {
    final adminId = await _getAdminId();
    if (adminId == null) return;
    try {
      final response = await _dio.get(
        '${ApiConstants.waConnectionStatus}/$adminId?live=$live',
      );
      if (response.data['success'] == true) {
        final s = WhatsAppStatusModel.fromJson(response.data);
        state = state.copyWith(
          status: s,
          qrCode: s.connected ? null : state.qrCode,
        );
      }
    } catch (_) {}
  }

  /// تُستدعى عند فتح شاشة الاتصال: تتحقق من الحالة، وإن لم تكن متصلة قد تكون
  /// جلسة محفوظة قيد الاستعادة بالـbackend (live=true تُحفّزها). نتحقق بضع
  /// مرّات خلال ~12 ثانية بدون الاعتماد على الـsocket، فتظهر "متصل" حتى لو
  /// الـsocket مكسور. الإعادات بـlive=false (خفيفة، بلا تكرار محاولة استعادة).
  Future<void> refreshStatusOnOpen() async {
    await fetchStatus(live: true);
    for (var i = 0; i < 4; i++) {
      if (!mounted) return;
      if (state.status.connected) return;
      await Future<void>.delayed(const Duration(seconds: 3));
      if (!mounted) return;
      await fetchStatus(live: false);
    }
  }

  Future<void> startSession() async {
    final adminId = await _getAdminId();
    final username = await _getUsername();
    if (adminId == null) return;
    state = state.copyWith(isConnecting: true, error: null, qrCode: null);
    try {
      await _dio.post(ApiConstants.waStartSession, data: {
        'adminId': adminId,
        'adminUsername': username ?? '',
      });
      // احتياطي: الـQR يُرسَل عبر socket مرّة واحدة بعد ثوانٍ (توليد عملية Go).
      // لو الـsocket مو جاهز/فاتته اللحظة، نلتقط الـQR المخزَّن مؤقتاً (cache
      // 60s) عبر polling — وإلا يبقى المستخدم على "جاري الاتصال" بلا نهاية.
      unawaited(_pollForQr(adminId));
    } catch (e) {
      state = state.copyWith(isConnecting: false, error: 'فشل بدء الجلسة');
    }
  }

  Future<void> reconnect() async {
    final adminId = await _getAdminId();
    final username = await _getUsername();
    if (adminId == null) return;
    state = state.copyWith(isConnecting: true, error: null);
    try {
      await _dio.post(ApiConstants.waReconnect, data: {
        'adminId': adminId,
        'adminUsername': username ?? '',
      });
      unawaited(_pollForQr(adminId));
    } catch (e) {
      state = state.copyWith(isConnecting: false, error: 'فشل إعادة الاتصال');
    }
  }

  /// الربط بالكود (pairing code): يرسل رقم الهاتف للباكند فيرجّع كود 8 خانات
  /// يكتبه المستخدم في واتساب (الأجهزة المرتبطة ← ربط برقم الهاتف بدل المسح).
  /// عند نجاح الربط يصل حدث 'connected' عبر socket — وكـfallback نعمل polling
  /// خفيف للحالة. دائماً جلسة جديدة (مثل startSession مع QR).
  Future<void> startSessionWithCode(String phone) async {
    final adminId = await _getAdminId();
    final username = await _getUsername();
    if (adminId == null) return;
    _pollingQr = false; // أوقف أي polling QR جارٍ
    state = state.copyWith(isConnecting: true, error: null, qrCode: null, pairCode: null);
    try {
      final res = await _dio.post(ApiConstants.waStartSessionCode, data: {
        'adminId': adminId,
        'adminUsername': username ?? '',
        'phone': phone,
      });
      final data = res.data;
      if (data is Map && data['alreadyConnected'] == true) {
        state = state.copyWith(
          status: WhatsAppStatusModel(
            connected: true,
            phone: data['phone']?.toString(),
            pushname: data['pushname']?.toString(),
            platform: data['platform']?.toString(),
          ),
          isConnecting: false,
        );
        return;
      }
      final code = (data is Map) ? data['pairCode']?.toString() : null;
      if (code != null && code.isNotEmpty) {
        state = state.copyWith(pairCode: code, isConnecting: false);
        unawaited(_pollForPairConnected(adminId));
      } else {
        final msg = (data is Map ? data['message']?.toString() : null);
        state = state.copyWith(isConnecting: false, error: msg ?? 'تعذّر توليد كود الربط');
      }
    } on DioException catch (e) {
      final msg = e.response?.data?['message']?.toString();
      state = state.copyWith(isConnecting: false, error: msg ?? 'فشل بدء الربط بالكود');
    } catch (e) {
      state = state.copyWith(isConnecting: false, error: 'فشل بدء الربط بالكود');
    }
  }

  /// Polling خفيف بعد عرض كود الربط — يكتشف نجاح الاتصال لو فات حدث socket.
  /// كود الربط صالح ~3 دقائق فنفحص خلالها كل 3 ثوانٍ.
  Future<void> _pollForPairConnected(String adminId) async {
    if (_pollingPair) return;
    _pollingPair = true;
    try {
      var elapsed = 0;
      while (elapsed < 180) {
        await Future<void>.delayed(const Duration(seconds: 3));
        elapsed += 3;
        if (!_pollingPair) return; // أُلغي (disconnect/dispose)
        if (state.status.connected) return; // اتصل عبر socket
        try {
          final res = await _dio.get('${ApiConstants.waPendingPairCode}/$adminId');
          final data = res.data;
          if (data is Map && data['alreadyConnected'] == true) {
            state = state.copyWith(
              status: WhatsAppStatusModel(
                connected: true,
                phone: data['phone']?.toString(),
                pushname: data['pushname']?.toString(),
                platform: data['platform']?.toString(),
              ),
              isConnecting: false,
              pairCode: null,
            );
            return;
          }
        } catch (_) {
          // تجاهل أخطاء poll مؤقتة
        }
      }
    } finally {
      _pollingPair = false;
    }
  }

  /// Polling احتياطي للـQR بعد بدء/إعادة الجلسة. الـsocket هو الأساس (فوري)؛
  /// هذا يلتقط الحالات اللي تفوت فيها رسالة الـsocket. يتوقف فور ظهور QR (من
  /// socket أو poll) أو الاتصال، ويضع رسالة واضحة عند انتهاء المهلة بدل تعليق
  /// لا نهائي على "جاري الاتصال".
  Future<void> _pollForQr(String adminId) async {
    if (_pollingQr) return;
    _pollingQr = true;
    try {
      // نبقى نُحدّث الـQR كل 3 ثوانٍ لمدة ~90 ثانية (مثل الويب) — whatsmeow
      // يولّد QR جديد كل ~20 ثانية، والـcache يتحدّث، فحتى لو الـsocket مكسور
      // يبقى الـQR المعروض حديثاً قابلاً للمسح. نتوقف عند الاتصال أو المهلة.
      var elapsed = 0;
      while (elapsed < 90) {
        await Future<void>.delayed(const Duration(seconds: 3));
        elapsed += 3;
        if (!_pollingQr) return; // أُلغي (disconnect/dispose)
        if (state.status.connected) return; // اتصل عبر socket
        try {
          final res = await _dio.get('${ApiConstants.waPendingQr}/$adminId');
          final data = res.data;
          if (data is Map) {
            if (data['alreadyConnected'] == true) {
              state = state.copyWith(
                status: WhatsAppStatusModel(
                  connected: true,
                  phone: data['phone']?.toString(),
                  pushname: data['pushname']?.toString(),
                  platform: data['platform']?.toString(),
                ),
                isConnecting: false,
                qrCode: null,
              );
              return;
            }
            final qr = data['qrCode']?.toString();
            if (qr != null && qr.isNotEmpty && qr != state.qrCode) {
              // حدّث الـQR كل مرة يتغيّر (refresh) — لا نتوقف، نكمل المتابعة.
              state = state.copyWith(qrCode: qr, isConnecting: false);
            }
          }
        } catch (_) {
          // تجاهل أخطاء poll مؤقتة وأعد المحاولة
        }
      }
      // انتهت المهلة (~90s) بلا اتصال — أخرج المستخدم من حالة الانتظار.
      if (!state.status.connected) {
        state = state.copyWith(
          isConnecting: false,
          error: state.qrCode == null
              ? 'تعذّر توليد رمز QR. حاول مرة أخرى.'
              : 'انتهت مهلة الانتظار. حاول مجدداً.',
        );
      }
    } finally {
      _pollingQr = false;
    }
  }

  Future<void> disconnect() async {
    final adminId = await _getAdminId();
    if (adminId == null) return;
    _pollingQr = false; // أوقف أي polling جارٍ للـQR
    _pollingPair = false; // وأي polling لكود الربط
    try {
      await _dio.post(ApiConstants.waDisconnect, data: {
        'adminId': adminId,
      });
      state = state.copyWith(
        status: const WhatsAppStatusModel(connected: false),
        qrCode: null,
      );
    } catch (e) {
      state = state.copyWith(error: 'فشل قطع الاتصال');
    }
  }

  Future<({bool success, String? error})> sendMessage(
      String to, String message) async {
    final adminId = await _getAdminId();
    if (adminId == null) {
      return (success: false, error: 'لم يتم العثور على معرف المدير');
    }
    try {
      final response = await _dio.post(ApiConstants.waSendMessage, data: {
        'adminId': adminId,
        'to': to,
        'message': message,
      });
      if (response.data['success'] == true) {
        return (success: true, error: null);
      }
      final msg = response.data['message']?.toString() ??
          response.data['error']?.toString();
      return (success: false, error: msg ?? 'فشل إرسال الرسالة');
    } on DioException catch (e) {
      final serverMsg = e.response?.data?['message']?.toString();
      final serverErr = e.response?.data?['error']?.toString();
      final detail = [serverMsg, serverErr].where((s) => s != null && s.isNotEmpty).join(' - ');
      return (success: false, error: detail.isNotEmpty ? detail : 'خطأ في الاتصال بالخادم');
    } catch (_) {
      return (success: false, error: 'خطأ غير متوقع');
    }
  }

  Future<({bool success, String? error})> sendMedia({
    required String to,
    required String base64Data,
    required String mimetype,
    String filename = 'file',
    String caption = '',
  }) async {
    final adminId = await _getAdminId();
    if (adminId == null) {
      return (success: false, error: 'لم يتم العثور على معرف المدير');
    }
    try {
      final response = await _dio.post(ApiConstants.waSendMedia, data: {
        'adminId': adminId,
        'to': to,
        'data': base64Data,
        'mimetype': mimetype,
        'filename': filename,
        'caption': caption,
      });
      if (response.data['success'] == true) {
        return (success: true, error: null);
      }
      final msg = response.data['message']?.toString() ??
          response.data['error']?.toString();
      return (success: false, error: msg ?? 'فشل إرسال الملف');
    } on DioException catch (e) {
      final msg = e.response?.data?['message']?.toString() ??
          e.response?.data?['error']?.toString();
      return (success: false, error: msg ?? 'خطأ في الاتصال بالخادم');
    } catch (_) {
      return (success: false, error: 'خطأ غير متوقع');
    }
  }

  @override
  void dispose() {
    _pollingQr = false;
    _pollingPair = false;
    _statusSub?.cancel();
    _qrSub?.cancel();
    super.dispose();
  }
}

final whatsappProvider =
    StateNotifierProvider<WhatsAppNotifier, WhatsAppState>((ref) {
  return WhatsAppNotifier(
    ref.read(backendDioProvider),
    ref.read(socketServiceProvider),
    ref.read(storageServiceProvider),
  );
});
