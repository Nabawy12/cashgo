// lib/main.dart
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'screens/shared/login_screen.dart';
import 'screens/admin/dashboard_screen.dart';
import 'screens/cashier/cashier_screen.dart';
import 'screens/admin/receipts.dart';
import 'screens/admin/stock_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ar');
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CashGo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.blue),
      home: LoginScreen(),
      routes: {
        '/admin': (context) => const AdminDashboardScreen(username: 'admin'),
        CashierScreen.routName: (context) => const CashierScreen(),
        receiptsScreen.routeName: (context) => const receiptsScreen(),
        CreditsScreen.routeName: (context) => const CreditsScreen(),
      },
    );
  }
}
