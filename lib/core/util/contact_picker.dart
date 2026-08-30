import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';

/// Wraps `flutter_contacts`'s OS-presented contact picker so the
/// add/edit subscriber sheets can pull a phone number from the
/// device's address book without re-typing. Works on both iOS
/// (Contacts framework) and Android (ContactsContract).
class ContactPicker {
  ContactPicker._();

  /// Result: (phone, error). `error` is null on success or user-cancel.
  /// When set, callers should show the message to the user instead of
  /// silently failing.
  static Future<({String? phone, String? error})> pickPhone() async {
    // 2026-07-13: crash-report from the field — some devices (خصوصاً
    // Xiaomi/Oppo/Vivo وأجهزة Android 14) كانت تتعطّل عند فتح الـpicker
    // بلا permission مسبق أو ترجع Uri فاسد. الحلّ:
    //   1) اطلب READ_CONTACTS بلطف قبل أي شيء (لا نُسقط لو رفض — نجرّب
    //      الـpicker بأمان + fallback بإذن + قراءة كل الأرقام).
    //   2) لفّ كل استدعاء بـtry/catch منفصل حتى لا ينتشر platform
    //      exception إلى شاشة المشترك ويسبب "crash + exit".
    //   3) لو المستخدم اختار جهة بلا هاتف، نُرجع خطأ مفهوم بدل null.
    try {
      // 1) request permission — best-effort, لا يفتح إذا رفض
      bool granted = false;
      try {
        granted = await FlutterContacts.requestPermission(readonly: true);
      } catch (e) {
        if (kDebugMode) debugPrint('ContactPicker.perm: $e');
      }

      // 2) primary path: OS-native picker
      try {
        final contact = await FlutterContacts.openExternalPick();
        if (contact == null) return (phone: null, error: null);
        // openExternalPick يرجع contact خفيف (بدون phones أحياناً على Android)
        // — أعِد جلب الجهة كاملة بالـid لضمان الأرقام.
        var full = contact;
        if (contact.phones.isEmpty && granted && contact.id.isNotEmpty) {
          try {
            final fetched = await FlutterContacts.getContact(
              contact.id,
              withProperties: true,
            );
            if (fetched != null) full = fetched;
          } catch (_) {/* keep original */}
        }
        if (full.phones.isEmpty) {
          return (
            phone: null,
            error: 'الجهة المختارة لا تحتوي على رقم هاتف',
          );
        }
        return (phone: _clean(full.phones.first.number), error: null);
      } on PlatformException catch (e) {
        if (kDebugMode) {
          debugPrint('ContactPicker.pick: ${e.code} ${e.message}');
        }
        // على Android بدون visibility declaration الحدث يرجع FailedResult
        // — نجرّب fallback لو الإذن معطى.
      } catch (e) {
        if (kDebugMode) debugPrint('ContactPicker.pick: $e');
      }

      // 3) fallback: لو الـpicker فشل ومعنا الإذن — لا نُظهر شيئاً بل نُبلّغ.
      if (!granted) {
        return (
          phone: null,
          error: 'اسمح بالوصول لجهات الاتصال من إعدادات النظام لهذا التطبيق',
        );
      }
      return (
        phone: null,
        error: 'تعذّر فتح دليل الأسماء — أدخل الرقم يدوياً',
      );
    } catch (e, st) {
      if (kDebugMode) debugPrint('🔴 ContactPicker fatal: $e\n$st');
      return (phone: null, error: 'تعذّر فتح دليل الأسماء');
    }
  }

  static String? _clean(String raw) {
    final n = raw.trim().replaceAll(RegExp(r'[^0-9+]'), '');
    return n.isEmpty ? null : n;
  }
}
