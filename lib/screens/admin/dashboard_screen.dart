

import 'package:cashgo/screens/admin/product_management_screen.dart' show ProductManagementScreen;
import 'package:cashgo/screens/admin/profit_screen.dart';
import 'package:cashgo/screens/admin/receipts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';

import '../../services/db/db_helper.dart';
import '../../utils/colors.dart';
import '../../widgets/Admin/DashBoard/dash_widget.dart';
import '../Notification/notification.dart';
import 'change_password_screen.dart';

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
      final count2 = await DBHelper.instance.getExpiringUnseenCount(daysThreshold: 10);
      setState(() => _unseenCount = count + count2);
    } catch (e) {
      await DBHelper.instance.ensureLowStockSeenColumn();
      await DBHelper.instance.ensureExpirySeenColumn();
      final count = await DBHelper.instance.getLowStockUnseenCount();
      final count2 = await DBHelper.instance.getExpiringUnseenCount(daysThreshold: 10);
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
      appBar: AppBar(
        iconTheme: const IconThemeData(color: Colors.white),
        backgroundColor: Colors.transparent,
        elevation: 0.0,
        title: const Text(
            'اداره التطبيق',
            style: TextStyle(
                color: Colors.white
            ),
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
                  icon: const Icon(Icons.notifications_outlined, color: Colors.white70, size: 26),
                  onPressed: () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsScreen()));
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
                    decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                    child: Text('$_unseenCount', style: const TextStyle(color: Colors.white, fontSize: 12)),
                  ),
                ),
            ],
          ),
          Tooltip(
            message: 'تغيير كلمة المرور',
            waitDuration: const Duration(milliseconds: 1),
            child: IconButton(
              mouseCursor: SystemMouseCursors.click,
              icon: const Icon(Icons.lock_outline_rounded, color: Colors.white70, size: 22),
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => ChangePasswordScreen(username: widget.username)));
              },
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(width: 20),
                DashboardWidget(
                title: 'اداره المنتجات',
                image: 'assets/icons/products.svg',
                onTap: ()=> Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ProductManagementScreen()),
                ),
                ),
                const SizedBox(width: 20),
                DashboardWidget(
                  title: 'نسبه الارباح',
                  image: 'assets/icons/profit.svg',
                  onTap: ()=> Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ProfitScreen()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(width: 20),
                DashboardWidget(
                  title: 'الفواتير المدفوعه',
                  image: 'assets/icons/paid_receipt.svg',
                  onTap: ()=> Navigator.pushNamed(
                    context,
                    receiptsScreen.routeName,
                  ),
                ),
                const SizedBox(width: 20),
                DashboardWidget(
                  title: 'الفواتير الاجله',
                  image: 'assets/icons/rejected_receipt.svg',
                  onTap: ()=> Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ProfitScreen()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(width: 20),
                DashboardWidget(
                  title: 'المشتريات المدفوعه',
                  image: 'assets/icons/paid_purchases.svg',
                  onTap: ()=> Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ProductManagementScreen()),
                  ),
                ),
                const SizedBox(width: 20),
                DashboardWidget(
                  title: 'المشتريات الاجله',
                  image: 'assets/icons/rejected_purchases.svg',
                  onTap: ()=> Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ProfitScreen()),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
