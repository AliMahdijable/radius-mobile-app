import 'reports/reports_hub_screen.dart';

/// التوافق العكسي: main_shell.dart يستورد `ReportsScreen` كـtab.
/// نوجِّهها مباشرة لـHub الجديد بدون wrapper إضافي.
typedef ReportsScreen = ReportsHubScreen;
