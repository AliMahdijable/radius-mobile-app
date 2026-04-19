import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'app_snackbar.dart';

/// Opens a bottom sheet that lists the user's phone contacts (with numbers),
/// lets them search by name, and returns the selected phone number.
///
/// Returns `null` if the user cancels, denies permission, or no contacts exist.
Future<String?> pickContactPhone(BuildContext context) async {
  final granted = await FlutterContacts.requestPermission(readonly: true);
  if (!granted) {
    if (context.mounted) {
      AppSnackBar.warning(
        context,
        'تحتاج السماح بقراءة جهات الاتصال من إعدادات الهاتف',
      );
    }
    return null;
  }

  List<Contact> contacts;
  try {
    contacts = await FlutterContacts.getContacts(
      withProperties: true,
      withPhoto: false,
    );
  } catch (_) {
    if (context.mounted) {
      AppSnackBar.error(context, 'تعذّر قراءة جهات الاتصال');
    }
    return null;
  }

  final withPhones = contacts
      .where((c) => c.phones.isNotEmpty)
      .toList(growable: false);

  if (withPhones.isEmpty) {
    if (context.mounted) {
      AppSnackBar.warning(context, 'لا توجد جهات اتصال بأرقام على هذا الهاتف');
    }
    return null;
  }

  withPhones.sort((a, b) =>
      a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));

  if (!context.mounted) return null;

  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _ContactsSheet(contacts: withPhones),
  );
}

class _ContactsSheet extends StatefulWidget {
  final List<Contact> contacts;
  const _ContactsSheet({required this.contacts});

  @override
  State<_ContactsSheet> createState() => _ContactsSheetState();
}

class _ContactsSheetState extends State<_ContactsSheet> {
  late List<Contact> _filtered;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _filtered = widget.contacts;
  }

  void _onSearch(String value) {
    final q = value.trim().toLowerCase();
    setState(() {
      _query = q;
      if (q.isEmpty) {
        _filtered = widget.contacts;
      } else {
        _filtered = widget.contacts.where((c) {
          if (c.displayName.toLowerCase().contains(q)) return true;
          for (final ph in c.phones) {
            final digits = ph.number.replaceAll(RegExp(r'[^0-9+]'), '');
            if (digits.contains(q) || ph.number.contains(q)) return true;
          }
          return false;
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenH = MediaQuery.of(context).size.height;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SizedBox(
        height: screenH * 0.85,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade400,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
              child: Row(
                children: [
                  Icon(Icons.contacts_rounded,
                      color: theme.colorScheme.primary),
                  const SizedBox(width: 10),
                  Text(
                    'اختر من جهات الاتصال',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const Spacer(),
                  Text(
                    '${_filtered.length}',
                    style: TextStyle(
                      color: theme.colorScheme.onSurface.withOpacity(0.6),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 6, 18, 10),
              child: TextField(
                autofocus: true,
                onChanged: _onSearch,
                decoration: InputDecoration(
                  hintText: 'ابحث بالاسم أو الرقم…',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close_rounded, size: 18),
                          onPressed: () => _onSearch(''),
                        ),
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _filtered.isEmpty
                  ? Center(
                      child: Text(
                        'لا توجد نتائج',
                        style: TextStyle(
                          color:
                              theme.colorScheme.onSurface.withOpacity(0.5),
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _filtered.length,
                      itemBuilder: (ctx, i) {
                        final c = _filtered[i];
                        final hasMultiple = c.phones.length > 1;
                        return ListTile(
                          dense: hasMultiple ? false : true,
                          leading: CircleAvatar(
                            backgroundColor: theme.colorScheme.primary
                                .withOpacity(0.15),
                            child: Text(
                              c.displayName.isNotEmpty
                                  ? c.displayName[0].toUpperCase()
                                  : '?',
                              style: TextStyle(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          title: Text(
                            c.displayName.isEmpty ? '(بدون اسم)' : c.displayName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            c.phones
                                .map((p) => p.number)
                                .take(3)
                                .join(' • '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurface
                                  .withOpacity(0.65),
                            ),
                          ),
                          onTap: () async {
                            if (c.phones.length == 1) {
                              Navigator.of(ctx).pop(c.phones.first.number);
                              return;
                            }
                            final picked = await showDialog<String>(
                              context: ctx,
                              builder: (dCtx) => SimpleDialog(
                                title: Text(c.displayName),
                                children: c.phones
                                    .map((p) => SimpleDialogOption(
                                          onPressed: () =>
                                              Navigator.pop(dCtx, p.number),
                                          child: Text(
                                            p.number,
                                            textDirection:
                                                TextDirection.ltr,
                                          ),
                                        ))
                                    .toList(),
                              ),
                            );
                            if (picked != null && ctx.mounted) {
                              Navigator.of(ctx).pop(picked);
                            }
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
