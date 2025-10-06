import 'package:cashgo/screens/admin/product_management_screen.dart' show ProductManagementScreen;
import 'package:cashgo/screens/admin/profit_screen.dart';
import 'package:cashgo/screens/admin/receipts.dart';
import 'package:cashgo/screens/admin/stock_screen.dart';
import 'package:cashgo/screens/admin/waletScreen.dart';
import 'package:flutter/material.dart';
import '../../services/db/db_helper.dart';
import '../../utils/colors.dart';
import '../../widgets/Admin/DashBoard/dash_widget.dart';
import '../Notification/notification.dart';
import 'AdminCreditPurchases.dart';
import 'AdminPaidPurchases.dart';
import 'FinancialAccounts.dart';
import 'Settings.dart';

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
        extendBodyBehindAppBar: false,
        appBar: AppBar(
          scrolledUnderElevation: 0,
          iconTheme: const IconThemeData(color: Colors.white),
          backgroundColor: Colors.transparent,
          elevation: 0.0,
          title: const Text(
            'اداره التطبيق',
            style: TextStyle(color: Colors.white),
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
              message: 'اداره المستخدمين',
              waitDuration: const Duration(milliseconds: 1),
              child: IconButton(
                mouseCursor: SystemMouseCursors.click,
                icon: const Icon(Icons.settings_outlined, color: Colors.white70, size: 22),
                onPressed: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => SettingsPage()));
                },
              ),
            ),

            // ------------------ أيقونة مسح البيانات (ما عدا المنتجات) ------------------
            Tooltip(
              message: 'مسح كل البيانات (ما عدا المنتجات)',
              waitDuration: const Duration(milliseconds: 1),
              child: IconButton(
                icon: const Icon(Icons.delete_forever, color: Colors.white70, size: 22),
                onPressed: () async {
                  // 1) حوار التأكيد مع خيار الاحتفاظ بالمستخدمين
                  final choice = await showDialog<int>(
                    context: context,
                    builder: (c) => AlertDialog(
                      title: const Text('تأكيد عملية المسح'),
                      content: const Text('هل أنت متأكد؟ سيتم حذف كل البيانات ما عدا جدول "المنتجات".'),
                      actions: [
                        TextButton(onPressed: () => Navigator.of(c).pop(0), child: const Text('إلغاء')),
                        TextButton(onPressed: () => Navigator.of(c).pop(1), child: const Text('مسح واحتفاظ بالمستخدمين')),
                        ElevatedButton(onPressed: () => Navigator.of(c).pop(2), child: const Text('مسح الكل')),
                      ],
                    ),
                  );

                  if (choice == null || choice == 0) return; // الغى المستخدم

                  final keepUsers = (choice == 1);

                  // 2) مؤشر تقدم غير قابل للإغلاق أثناء التنفيذ
                  showDialog(
                    context: context,
                    barrierDismissible: false,
                    builder: (c) => Dialog(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            SizedBox(width: 16),
                            Text('جاري المسح...'),
                          ],
                        ),
                      ),
                    ),
                  );

                  try {
                    // نفّذ المسح عبر singleton (تأكد إن الدالة داخل DBHelper وليست static)
                    await DBHelper.instance.wipeAllExceptProducts(keepUsers: keepUsers);

                    // اغلاق مؤشر التقدم
                    Navigator.of(context).pop();

                    // رسالة نجاح
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(keepUsers ? 'تم مسح البيانات مع الاحتفاظ بالمستخدمين.' : 'تم مسح كل البيانات بنجاح.')),
                    );

                    // لو محتاج تعيد تحميل أي بيانات بالواجهة:
                    if (mounted) setState(() {
                      // حدث الحالة لو عندك حاجة تتغير قدام المستخدم
                      // مثال: _loadData();
                    });
                  } catch (e, st) {
                    // اغلاق مؤشر التقدم
                    Navigator.of(context).pop();
                    debugPrint('wipeAllExceptProducts error: $e\n$st');

                    // اظهار خطأ
                    showDialog(
                      context: context,
                      builder: (c) => AlertDialog(
                        title: const Text('حدث خطأ'),
                        content: Text('فشل المسح: $e'),
                        actions: [TextButton(onPressed: () => Navigator.of(c).pop(), child: const Text('حسناً'))],
                      ),
                    );
                  }
                },
              ),
            ),
          ],
        ),        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 16,horizontal: 20),
            child: Column(
              mainAxisSize: MainAxisSize.max,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
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
                        MaterialPageRoute(builder: (_) => const TopProductsChartPage()),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    DashboardWidget(
                      title: 'الفواتير المدفوعه',
                      image: 'assets/icons/paid_receipt.svg',
                      onTap: ()=> Navigator.pushNamed(
                        context,
                        receiptsScreen.routeName,
                      ),
                    ),
                    SizedBox(width: 20,),
                    DashboardWidget(
                      title: 'الفواتير الآجله',
                      image: 'assets/icons/rejected_receipt.svg',
                      onTap: ()=> Navigator.pushNamed(
                        context,
                        CreditsScreen.routeName,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    DashboardWidget(
                      title: 'المشتريات المدفوعه',
                      image: 'assets/icons/paid_purchases.svg',
                      onTap: ()=> Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const AdminPaidPurchasesScreen()),
                      ),
                    ),
                    const SizedBox(width: 20),
                    DashboardWidget(
                      title: 'المشتريات الاجله',
                      image: 'assets/icons/rejected_purchases.svg',
                      onTap: ()=> Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const AdminLaterPurchasesScreen()),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    DashboardWidget(
                      title: 'الحسبات الماليه',
                      image: 'assets/icons/financial.svg',
                      onTap: ()=> Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => AdminCashDrawerPage()),
                      ),
                    ),
                    const SizedBox(width: 20,),
                    DashboardWidget(
                      title: 'سجل السحب و الايداع',
                      image: 'assets/icons/deposit.svg',
                      onTap: ()=> Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => CardWalletActivityScreen()),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        )
    );
  }
}
