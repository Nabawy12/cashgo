// lib/main.dart
import 'package:cashgo/utils/colors.dart';
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
      home: LoginScreen(),
      routes: {
        '/admin': (context) => const AdminDashboardScreen(username: 'admin'),
        CashierScreen.routName: (context) => const CashierScreen(),
        receiptsScreen.routeName: (context) => const receiptsScreen(),
        CreditsScreen.routeName: (context) => const CreditsScreen(),
      },

      theme: ThemeData(
        // بقية ثيم التطبيق...
        colorScheme: ColorScheme.fromSeed(seedColor: AppColorsDark.mainColor),
        useMaterial3: true,

        // هنا نعرف ثيم للـ SnackBar على مستوى التطبيق
        snackBarTheme: SnackBarThemeData(
          backgroundColor: AppColorsDark.bgColor,
          contentTextStyle: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
          actionTextColor: Colors.white,
          disabledActionTextColor: Colors.grey,
          elevation: 6,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: AppColorsDark.mainColor,
              width: 1.5
            )
          ),
          width: 1400,
          insetPadding: const EdgeInsets.symmetric(horizontal: 500, vertical: 25), // مسافة من الحواف
        ),
      ),
    );

  }
}
