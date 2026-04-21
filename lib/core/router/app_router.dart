import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/auth_provider.dart';
import '../../models/subscriber_model.dart';
import '../../screens/login_screen.dart';
import '../../screens/home_screen.dart';
import '../../screens/subscribers/subscriber_details_screen.dart';
import '../../screens/whatsapp/whatsapp_connection_screen.dart';
import '../../screens/whatsapp/whatsapp_send_scope_screen.dart';
import '../../screens/whatsapp/message_logs_screen.dart';
import '../../screens/whatsapp/broadcast_screen.dart';
import '../../screens/schedules_screen.dart';
import '../../screens/templates_screen.dart';
import '../../screens/discounts_screen.dart';
import '../../screens/debt_export_screen.dart';
import '../../screens/debt_import_screen.dart';
import '../../screens/managers_screen.dart';
import '../../screens/packages_screen.dart';
import '../../screens/print_templates_screen.dart';
import '../../screens/devices/device_defaults_screen.dart';
import '../../screens/devices/ont_device_screen.dart';
import '../../screens/devices/ubiquiti_device_screen.dart';
import '../../screens/expenses/expenses_screen.dart';

/// Root navigator for in-app overlays (e.g. [AppSnackBar]) after route changes.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authProvider);

  return GoRouter(
    navigatorKey: appNavigatorKey,
    initialLocation: '/login',
    redirect: (context, state) {
      final isAuthenticated = authState.status == AuthStatus.authenticated;
      final isLoginPage = state.matchedLocation == '/login';

      if (isAuthenticated && isLoginPage) return '/';
      if (!isAuthenticated && !isLoginPage) return '/login';
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/',
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: '/subscriber/:username',
        builder: (context, state) {
          final subscriber = state.extra as SubscriberModel?;
          if (subscriber == null) {
            return const Scaffold(
              body: Center(child: Text('مشترك غير موجود')),
            );
          }
          return SubscriberDetailsScreen(subscriber: subscriber);
        },
      ),
      GoRoute(
        path: '/whatsapp-connection',
        builder: (context, state) => const WhatsAppConnectionScreen(),
      ),
      GoRoute(
        path: '/whatsapp-send-scope',
        builder: (context, state) => const WhatsAppSendScopeScreen(),
      ),
      GoRoute(
        path: '/device-defaults',
        builder: (context, state) => const DeviceDefaultsScreen(),
      ),
      GoRoute(
        path: '/expenses',
        builder: (context, state) => const ExpensesScreen(),
      ),
      GoRoute(
        path: '/ont-device',
        builder: (context, state) {
          final args = state.extra as OntDeviceArgs;
          return OntDeviceScreen(args: args);
        },
      ),
      GoRoute(
        path: '/ubiquiti-device',
        builder: (context, state) {
          final args = state.extra as UbiquitiDeviceArgs;
          return UbiquitiDeviceScreen(args: args);
        },
      ),
      GoRoute(
        path: '/message-logs',
        builder: (context, state) => const MessageLogsScreen(),
      ),
      GoRoute(
        path: '/broadcast',
        builder: (context, state) => const BroadcastScreen(),
      ),
      GoRoute(
        path: '/schedules',
        builder: (context, state) => const SchedulesScreen(),
      ),
      GoRoute(
        path: '/templates',
        builder: (context, state) => const TemplatesScreen(),
      ),
      GoRoute(
        path: '/discounts',
        builder: (context, state) => const DiscountsScreen(),
      ),
      GoRoute(
        path: '/debt-export',
        builder: (context, state) => const DebtExportScreen(),
      ),
      GoRoute(
        path: '/debt-import',
        builder: (context, state) => const DebtImportScreen(),
      ),
      GoRoute(
        path: '/packages',
        builder: (context, state) => const PackagesScreen(),
      ),
      GoRoute(
        path: '/managers',
        builder: (context, state) => const ManagersScreen(),
      ),
      GoRoute(
        path: '/print-templates',
        builder: (context, state) => const PrintTemplatesScreen(),
      ),
    ],
  );
});
