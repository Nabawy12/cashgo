// import 'package:cashgo/services/db/db_helper.dart';
// import 'package:flutter/material.dart';
// import 'screens/shared/login_screen.dart';
// import 'screens/cashier/cashier_screen.dart';
// import 'screens/admin/dashboard_screen.dart';
//
// void main() async {
//   WidgetsFlutterBinding.ensureInitialized();
//   WidgetsFlutterBinding.ensureInitialized();
//   await DBHelper.instance.database; // يفتح/ينشئ DB
//   await DBHelper.instance.ensureLowStockSeenColumn(); //
//   await DBHelper.instance.ensureProductDatesColumns();
//   await DBHelper.instance.ensureExpirySeenColumn();
//
//   runApp(
//     MyApp(),
//   );
// }
//
// class MyApp extends StatelessWidget {
//   const MyApp({super.key});
//
//   @override
//   Widget build(BuildContext context) {
//     return MaterialApp(
//       title: 'POS Desktop',
//       debugShowCheckedModeBanner: false,
//       theme: ThemeData(primarySwatch: Colors.blue),
//       routes: {
//         '/': (context) => const LoginScreen(),
//         '/admin': (context) => const AdminDashboardScreen(username: 'admin'),
//         '/cashier': (context) => const CashierScreen(),
//       },
//     );
//   }
// }
