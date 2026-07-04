import 'package:cashgo_supermarket/screens/admin/product_management_screen.dart'
    show ProductManagementScreen;
import 'package:cashgo_supermarket/screens/admin/profit_screen.dart';
import 'package:cashgo_supermarket/screens/admin/receipts.dart';
import 'package:cashgo_supermarket/screens/admin/stock_screen.dart';
import 'package:flutter/material.dart';
import '../../services/db/db_helper.dart';
import '../../utils/colors.dart';
import '../../widgets/Admin/DashBoard/dash_widget.dart';
import '../Notification/notification.dart';
import 'AdminCreditPurchases.dart';
import 'AdminPaidPurchases.dart';
import 'FinancialAccounts.dart';
import 'Settings.dart';
import 'shop_profit_screen.dart';

class AdminDashboardScreen extends StatefulWidget {
  final String username;
  const AdminDashboardScreen({super.key, required this.username});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  int _unseenCount = 0;

  Future<void> _loadUnseen() async {
    try {
      final count = await DBHelper.instance.getLowStockUnseenCount();
      final count2 =
          await DBHelper.instance.getExpiringUnseenCount(daysThreshold: 10);
      setState(() => _unseenCount = count + count2);
    } catch (e) {
      await DBHelper.instance.ensureLowStockSeenColumn();
      await DBHelper.instance.ensureExpirySeenColumn();
      final count = await DBHelper.instance.getLowStockUnseenCount();
      final count2 =
          await DBHelper.instance.getExpiringUnseenCount(daysThreshold: 10);
      setState(() => _unseenCount = count + count2);
    }
  }

  @override
  void initState() {
    super.initState();
    _loadUnseen();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColorsDark.bgColor,
      extendBodyBehindAppBar: false,
      appBar: AppBar(
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: Theme.of(context).iconTheme.color),
        backgroundColor: Colors.transparent,
        elevation: 0.0,
        title: Text(
          'اداره التطبيق',
          style: TextStyle(color: AppColorsDark.mainTextDark,fontSize: 25),
        ),
        centerTitle: true,
        actions: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Tooltip(
                message: 'الاشعارات',
                waitDuration: const Duration(milliseconds: 1),
                child: IconButton(
                  icon: Icon(Icons.notifications_outlined,
                      color: Theme.of(context).iconTheme.color, size: 26),
                  onPressed: () async {
                    await Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const NotificationsScreen()));
                    await _loadUnseen();
                  },
                ),
              ),
              if (_unseenCount > 0)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                        color: Colors.red, shape: BoxShape.circle),
                    child: Text('$_unseenCount',
                        style: TextStyle(
                            color: AppColorsDark.mainTextDark, fontSize: 12)),
                  ),
                ),
            ],
          ),
          Tooltip(
            message: 'اداره المستخدمين',
            waitDuration: const Duration(milliseconds: 1),
            child: IconButton(
              mouseCursor: SystemMouseCursors.click,
              icon: Icon(Icons.settings_outlined,
                  color: Theme.of(context).iconTheme.color, size: 22),
              onPressed: () {
                Navigator.push(
                    context, MaterialPageRoute(builder: (_) => SettingsPage()));
              },
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 25,
            crossAxisSpacing: 25,
            childAspectRatio: 2.5,
            children: [
              DashboardWidget(
                title: 'اداره المنتجات',
                image: 'assets/icons/products.svg',
                color: Colors.blueAccent,
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const ProductManagementScreen())),
              ),
              DashboardWidget(
                title: 'الفواتير المدفوعه',
                image: 'assets/icons/paid_receipt.svg',
                color: Colors.greenAccent,
                onTap: () => Navigator.pushNamed(context, receiptsScreen.routeName),
              ),
              DashboardWidget(
                title: 'الفواتير الآجله',
                image: 'assets/icons/rejected_receipt.svg',
                color: Colors.orangeAccent,
                onTap: () => Navigator.pushNamed(context, CreditsScreen.routeName),
              ),
              DashboardWidget(
                title: 'المشتريات المدفوعه',
                image: 'assets/icons/paid_purchases.svg',
                color: Colors.purpleAccent,
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const AdminPaidPurchasesScreen())),
              ),
              DashboardWidget(
                title: 'المشتريات الاجله',
                image: 'assets/icons/rejected_purchases.svg',
                color: Colors.amberAccent,
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const AdminLaterPurchasesScreen())),
              ),
              DashboardWidget(
                title: 'الحسبات الماليه',
                image: 'assets/icons/financial.svg',
                color: Colors.tealAccent,
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => AdminCashDrawerPage())),
              ),
              DashboardWidget(
                title: 'تقرير الأرباح',
                image: 'assets/icons/financial.svg',
                color: Colors.cyanAccent,
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const ProfitReportScreen())),
              ),
              DashboardWidget(
                title: 'تقرير المخزون',
                image: 'assets/icons/products.svg',
                color: Colors.indigoAccent,
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const CreditsScreen())),
              ),
              DashboardWidget(
                title: 'أرباح المحل',
                image: 'assets/icons/financial.svg',
                color: Colors.pinkAccent,
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const ShopProfitScreen())),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
