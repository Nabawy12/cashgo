// lib/main.dart
import 'dart:io' show Platform;
import 'package:cashgo/screens/admin/receipts.dart';
import 'package:cashgo/screens/admin/stock_screen.dart';
import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite/sqflite.dart';

import 'package:cashgo/services/db/db_helper.dart';
import 'screens/shared/login_screen.dart';
import 'screens/cashier/cashier_screen.dart';
import 'screens/admin/dashboard_screen.dart';
import 'package:intl/date_symbol_data_local.dart'; // << مهم
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ar');


  // If running on desktop (Windows / Linux / macOS) initialize sqflite FFI
  // BEFORE opening the database. This makes `openDatabase` use the
  // `databaseFactoryFfi` implementation which works on desktop.
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;


  // Open/create DB and run any migration helpers that expect DB to exist
  await DBHelper.instance.database;
  await DBHelper.instance.ensureLowStockSeenColumn();
  await DBHelper.instance.ensureProductDatesColumns();
  await DBHelper.instance.ensureExpirySeenColumn();

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
      routes: {
        '/': (context) => const LoginScreen(),
        '/admin': (context) => const AdminDashboardScreen(username: 'admin'),
        CashierScreen.routName: (context) => const CashierScreen(),
        receiptsScreen.routeName: (context) => const receiptsScreen(),
        CreditsScreen.routeName: (context) => const CreditsScreen(),
      },
    );
  }
}
