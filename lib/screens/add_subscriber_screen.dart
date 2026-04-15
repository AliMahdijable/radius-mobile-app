import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../widgets/add_subscriber_sheet.dart';
import '../providers/subscribers_provider.dart';
import '../core/theme/app_theme.dart';

class AddSubscriberScreen extends ConsumerWidget {
  const AddSubscriberScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: AddSubscriberSheet(),
        ),
      ),
    );
  }
}
