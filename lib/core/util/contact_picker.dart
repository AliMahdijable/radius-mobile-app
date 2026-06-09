import 'package:flutter/foundation.dart';
import 'package:flutter_contacts/flutter_contacts.dart';

/// Wraps `flutter_contacts`'s OS-presented contact picker so the
/// add/edit subscriber sheets can pull a phone number from the
/// device's address book without re-typing. Works on both iOS
/// (Contacts framework) and Android (ContactsContract).
///
/// `openExternalPick()` shows the OS-native picker — so the
/// permission prompt comes from the system, not the app, and the
/// admin sees their familiar contact list. Returns the first phone
/// on the picked contact, or null when the admin cancels.
class ContactPicker {
  ContactPicker._();

  /// Returns the picked phone number, stripped of formatting (spaces,
  /// dashes, parens) and prefixed properly when an explicit '+' is
  /// present. The sheet's _normalizePhone handles further work, so
  /// we leave country-code conversion alone here.
  static Future<String?> pickPhone() async {
    try {
      final contact = await FlutterContacts.openExternalPick();
      if (contact == null) return null;
      if (contact.phones.isEmpty) return null;
      // Pick the first phone — most contacts have one. If admin
      // wants to choose among multiples we'd need a follow-up picker
      // but the OS picker doesn't surface them as separate options.
      var number = contact.phones.first.number.trim();
      // Strip common cosmetic characters; keep + (international) and
      // digits. Letters can appear in some VCF imports — drop them.
      number = number.replaceAll(RegExp(r'[^0-9+]'), '');
      return number.isEmpty ? null : number;
    } catch (e) {
      if (kDebugMode) debugPrint('🔴 ContactPicker: $e');
      return null;
    }
  }
}
