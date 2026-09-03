import 'package:flutter/material.dart';
import 'package:flutter_native_contact_picker/flutter_native_contact_picker.dart';
import 'app_snackbar.dart';

/// Launches the OS-native single contact picker and returns the selected
/// phone number — or `null` if the user cancels.
///
/// Uses `flutter_native_contact_picker`, which wraps Android's
/// `ACTION_PICK` and iOS's `CNContactPickerViewController`. Neither path
/// requires the app to hold the READ_CONTACTS permission: the system UI
/// shows the contact list on our behalf and returns only the chosen
/// contact's data. This keeps us out of Google Play's expanded
/// contacts-permission review.
Future<String?> pickContactPhone(BuildContext context) async {
  final picker = FlutterNativeContactPicker();

  dynamic contact;
  try {
    contact = await picker.selectContact();
  } catch (_) {
    if (context.mounted) {
      AppSnackBar.error(context, 'تعذّر فتح جهات الاتصال');
    }
    return null;
  }

  if (contact == null) return null;

  final dynamic rawPhones = contact.phoneNumbers;
  final List<String> phones = (rawPhones is List)
      ? rawPhones.map((e) => e.toString()).toList()
      : const <String>[];

  if (phones.isEmpty) {
    if (context.mounted) {
      AppSnackBar.warning(context, 'جهة الاتصال المختارة لا تحتوي على رقم');
    }
    return null;
  }

  if (phones.length == 1) return phones.first;

  if (!context.mounted) return null;

  final name = _readName(contact);
  return showDialog<String>(
    context: context,
    builder: (dCtx) => SimpleDialog(
      title: Text(name ?? 'اختر رقماً'),
      children: phones
          .map(
            (p) => SimpleDialogOption(
              onPressed: () => Navigator.pop(dCtx, p),
              child: Text(p, textDirection: TextDirection.ltr),
            ),
          )
          .toList(),
    ),
  );
}

String? _readName(dynamic contact) {
  try {
    final dynamic name = contact.fullName;
    if (name == null) return null;
    final s = name.toString().trim();
    return s.isEmpty ? null : s;
  } catch (_) {
    return null;
  }
}
