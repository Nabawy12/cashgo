// lib/main.dart
import 'package:cashgo/services/Api/Admin/Products.dart';
import 'package:cashgo/services/cashier/close_shieft.dart';
import 'package:cashgo/utils/colors.dart';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/adapters.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'screens/shared/login_screen.dart';
import 'screens/admin/dashboard_screen.dart';
import 'screens/cashier/cashier_screen.dart';
import 'screens/admin/receipts.dart';
import 'screens/admin/stock_screen.dart';

Future<void> main() async {
  /// استدعي هذي الوظيفة مرة واحدة (مثلاً من main أثناء التطوير) لتصحيح ops القديمة.

  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  // open boxes used by the code
  await Hive.openBox('products');
  await Hive.openBox('sales');
  await Hive.openBox('users');
  await Hive.openBox('financial_accounts');
  await Hive.openBox('close_shifts');
  await Hive.openBox('meta');

  await Hive.openBox('ops');
  // init product api boxes
  await ProductApi.initBoxes();
  await ProductApi.initBoxes();
  final box = await Hive.openBox('products');
  for (final k in box.keys) {
    print('product key=$k value=${box.get(k)}');
  }

  // start sync manager
  await SyncManager.init();
  await Hive.openBox('ops');
  final api = ApiServiceClose_shieft();
  await api.migrateOldCloseShiftOps(); // لو ضفتها في نفس الملف
  await SyncManager.init();
  SyncManager.start();
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
        colorScheme: ColorScheme.fromSeed(
            primary:AppColorsDark.mainColor ,
            seedColor: AppColorsDark.mainColor,
            onSurface: Colors.white70,
            surface: Colors.white70
        ),
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

        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: Colors.white), // ← يؤثر على النص داخل TextField
          bodyMedium: TextStyle(color: Colors.white), // ← مهم جدًا
        ),
        iconTheme: const IconThemeData(
          color: Colors.white70,
        ),

        dialogBackgroundColor: AppColorsDark.bgCardColor, // خلفية الديالوج
        datePickerTheme: DatePickerThemeData(
          backgroundColor: AppColorsDark.bgCardColor, // خلفية داخلية للديالوج
          headerBackgroundColor: AppColorsDark.bgCardColor, // خلفية الهيدر
          headerForegroundColor: Colors.white,            // لون "October 2025" والنّص في الهيدر
          dayForegroundColor: MaterialStateProperty.all(Colors.white),
          todayForegroundColor: MaterialStateProperty.all(Colors.white),
          todayBackgroundColor: MaterialStateProperty.all(AppColorsDark.mainColor),
          rangePickerBackgroundColor: AppColorsDark.mainColor.withOpacity(0.5),
          weekdayStyle: const TextStyle(color: Colors.white70), // لون أيام الأسبوع S M T W ...
          yearStyle: const TextStyle(color: Colors.white70),
          headerHeadlineStyle: const TextStyle(color: Colors.white70),
          headerHelpStyle: const TextStyle(color: Colors.white70),

          inputDecorationTheme:  InputDecorationTheme(
            labelStyle: TextStyle(color: Colors.white70), // لون نص "Enter Date"
            hintStyle: TextStyle(color: Colors.white),

            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: AppColorsDark.mainColor), // حدود عادية
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: AppColorsDark.mainColor), // حدود لما يكون الفوكس
            ),
          ),

        ),
      ),
    );

  }
}
