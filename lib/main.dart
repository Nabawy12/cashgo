// lib/main.dart
import 'package:cashgo/services/Api/Admin/Products.dart';
import 'package:cashgo/services/app_settings_controller.dart';
import 'package:cashgo/services/cashier/close_shieft.dart';
import 'package:cashgo/utils/colors.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/adapters.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'screens/shared/login_screen.dart';
import 'screens/admin/dashboard_screen.dart';
import 'screens/cashier/cashier_screen.dart';
import 'screens/admin/receipts.dart';
import 'screens/admin/stock_screen.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Hive.initFlutter();
  await Hive.openBox('products');
  await Hive.openBox('sales');
  await Hive.openBox('users');
  await Hive.openBox('financial_accounts');
  await Hive.openBox('close_shifts');
  await Hive.openBox('meta');
  await Hive.openBox('ops');

  await ProductApi.initBoxes();

  final box = Hive.box('products');
  for (final k in box.keys) {
    print('product key=$k value=${box.get(k)}');
  }

  await SyncManager.init();
  final api = ApiServiceClose_shieft();
  await api.migrateOldCloseShiftOps();
  SyncManager.start();

  await initializeDateFormatting('ar');
  await AppSettingsController.loadThemeMode();

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppSettingsController.themeMode,
      builder: (context, themeMode, _) => MaterialApp(
        title: 'CashGo',
        debugShowCheckedModeBanner: false,
        navigatorKey: appNavigatorKey,
        themeMode: themeMode,
        home: LoginScreen(), // ✅ كل الأجهزة تفتح Login مباشرة
        routes: {
          '/admin': (context) {
            final username =
                ModalRoute.of(context)?.settings.arguments?.toString() ??
                    'admin';
            return AdminDashboardScreen(username: username);
          },
          CashierScreen.routName: (context) {
            final args = ModalRoute.of(context)?.settings.arguments;
            String username = 'cashier';
            if (args is Map && args['username'] != null) {
              username = args['username'].toString();
            } else if (args is String && args.isNotEmpty) {
              username = args;
            }
            return CashierScreen(cashierUsername: username);
          },
          receiptsScreen.routeName: (context) => const receiptsScreen(),
          CreditsScreen.routeName: (context) => const CreditsScreen(),
        },
        theme: _buildTheme(Brightness.light),
        darkTheme: _buildTheme(Brightness.dark),
      ),
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    final isLight = brightness == Brightness.light;
    final background =
    isLight ? AppColorsLight.bgColor : const Color(0xff1A1C28);
    final surface =
    isLight ? AppColorsLight.bgCardColor : const Color(0xff262935);
    final onSurface = isLight ? Colors.black : Colors.white;
    final iconColor = isLight ? Colors.black : const Color(0xff808B97);
    final mutedText = isLight ? Colors.grey.shade800 : const Color(0xff808B97);

    return ThemeData(
      brightness: brightness,
      colorScheme: ColorScheme.fromSeed(
        brightness: brightness,
        seedColor: AppColorsLight.mainColor,
        primary: AppColorsLight.mainColor,
        surface: surface,
        onSurface: onSurface,
        onPrimary: Colors.white,
        onSecondary: onSurface,
        onTertiary: onSurface,
      ),
      useMaterial3: true,
      scaffoldBackgroundColor: background,
      canvasColor: background,
      cardColor: surface,
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surface,
        contentTextStyle: TextStyle(
          color: onSurface,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
        actionTextColor: AppColorsLight.mainColor,
        disabledActionTextColor: mutedText,
        elevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: AppColorsLight.mainColor, width: 1.5),
        ),
      ),
      textTheme: TextTheme(
        bodyLarge: TextStyle(color: onSurface),
        bodyMedium: TextStyle(color: onSurface),
        titleLarge: TextStyle(color: onSurface),
        titleMedium: TextStyle(color: onSurface),
      ),
      iconTheme: IconThemeData(color: iconColor),
      primaryIconTheme: IconThemeData(color: iconColor),
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: onSurface,
        iconTheme: IconThemeData(color: iconColor),
        actionsIconTheme: IconThemeData(color: iconColor),
        surfaceTintColor: Colors.transparent,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: iconColor,
        textColor: onSurface,
        titleTextStyle: TextStyle(color: onSurface),
        subtitleTextStyle: TextStyle(color: mutedText),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: onSurface,
        unselectedLabelColor: mutedText,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(foregroundColor: Colors.white),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: Colors.white),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(foregroundColor: Colors.white),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        titleTextStyle: TextStyle(
          color: isLight ? Colors.black : Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
        contentTextStyle: TextStyle(
          color: isLight ? Colors.black : Colors.white,
          fontSize: 16,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        labelStyle: TextStyle(color: mutedText),
        hintStyle: TextStyle(color: mutedText),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: AppColorsDark.strokColor),
        ),
        focusedBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: AppColorsLight.mainColor),
        ),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: surface,
        headerBackgroundColor: surface,
        headerForegroundColor: onSurface,
        dayForegroundColor: WidgetStateProperty.all(onSurface),
        todayForegroundColor: WidgetStateProperty.all(onSurface),
        todayBackgroundColor: WidgetStateProperty.all(AppColorsLight.mainColor),
        rangePickerBackgroundColor:
        AppColorsLight.mainColor.withValues(alpha: 0.5),
        weekdayStyle: TextStyle(color: mutedText),
        yearStyle: TextStyle(color: mutedText),
        headerHeadlineStyle: TextStyle(color: mutedText),
        headerHelpStyle: TextStyle(color: mutedText),
      ),
    );
  }
}