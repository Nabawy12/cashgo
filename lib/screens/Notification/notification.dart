import 'package:cashgo/utils/colors.dart';
import 'package:flutter/material.dart';
import '../../services/db/db_helper.dart';
import '../../widgets/empty_state_card.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<Map<String, dynamic>> _lowStockItems = [];
  List<Map<String, dynamic>> _expiryItems = [];
  bool _loading = true;
  int _tabIndex = 0;
  final int expiryThresholdDays = 10;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  int _safeInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is double) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      await DBHelper.instance.ensureLowStockSeenColumn();
      await DBHelper.instance.ensureProductDatesColumns();
      await DBHelper.instance.ensureExpirySeenColumn();
      final low = await DBHelper.instance.getLowStockUnseenProducts();
      final expiry = await DBHelper.instance
          .getExpiringUnseenProducts(daysThreshold: expiryThresholdDays);
      if (!mounted) return;
      setState(() {
        _lowStockItems = low.map((p) => {
          ...p,
          'quantity': _safeInt(p['quantity']),
          'low_stock_seen': _safeInt(p['low_stock_seen']),
        }).toList();
        _expiryItems = expiry.map((p) => {
          ...p,
          'expiry_seen': _safeInt(p['expiry_seen']),
        }).toList();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _lowStockItems = [];
        _expiryItems = [];
        _loading = false;
      });
    }
  }

  Future<void> _toggleLowStockSeen(int id, bool seen) async {
    await DBHelper.instance.setProductLowStockSeen(id, true);
    setState(() => _lowStockItems.removeWhere((p) => _safeInt(p['id']) == id));
  }

  Future<void> _markAllLowStockRead() async {
    await DBHelper.instance.markAllLowStockSeen();
    if (mounted) setState(() => _lowStockItems.clear());
  }

  Future<void> _toggleExpirySeen(int id, bool seen) async {
    await DBHelper.instance.setProductExpirySeen(id, true);
    setState(() => _expiryItems.removeWhere((p) => _safeInt(p['id']) == id));
  }

  Future<void> _markAllExpiryRead() async {
    await DBHelper.instance.markAllExpirySeen(daysThreshold: expiryThresholdDays);
    if (mounted) setState(() => _expiryItems.clear());
  }

  // ── Widgets ──────────────────────────────────────────────

  Widget _tabButton(String label, IconData icon, int index, int count) {
    final selected = _tabIndex == index;
    final color = index == 0 ? Colors.orangeAccent : Colors.redAccent;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _tabIndex = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? color.withOpacity(0.12) : AppColorsDark.bgCardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? color : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: selected ? color : AppColorsDark.mainTextLight),
              const SizedBox(width: 8),
              Text(
                '$label ($count)',
                style: TextStyle(
                  color: selected ? color : AppColorsDark.mainTextLight,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stockTile(Map<String, dynamic> item) {
    final id = _safeInt(item['id']);
    final seen = _safeInt(item['low_stock_seen']) == 1;
    final qty = _safeInt(item['total_units'] ?? item['quantity']);
    final isCritical = qty == 0;
    final color = isCritical ? Colors.redAccent : Colors.orangeAccent;
    final label = isCritical ? 'نفذ المخزون' : 'مخزون منخفض';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColorsDark.bgCardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isCritical ? Icons.remove_shopping_cart_rounded : Icons.inventory_2_rounded,
              color: color,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item['name'] ?? 'بدون اسم',
                  style: TextStyle(
                    color: AppColorsDark.mainTextDark,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: color.withOpacity(0.4)),
                      ),
                      child: Text(
                        label,
                        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'المتبقي: $qty',
                      style: TextStyle(color: AppColorsDark.mainTextLight, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _toggleLowStockSeen(id, seen),
            icon: Icon(
              Icons.check_circle_rounded,
              color: seen ? Colors.green : AppColorsDark.mainTextLight,
              size: 22,
            ),
            tooltip: 'وضع كمقروء',
          ),
        ],
      ),
    );
  }

  Widget _expiryTile(Map<String, dynamic> item) {
    final id = _safeInt(item['id']);
    final seen = _safeInt(item['expiry_seen']) == 1;
    final expiryStr = (item['expiry_date'] ?? '').toString();
    final expiryDate = expiryStr.isNotEmpty ? DateTime.tryParse(expiryStr) : null;
    final daysLeft = expiryDate?.difference(DateTime.now()).inDays;

    Color color;
    String label;
    IconData icon;

    if (daysLeft == null) {
      color = Colors.grey;
      label = 'تاريخ غير معروف';
      icon = Icons.help_outline_rounded;
    } else if (daysLeft < 0) {
      color = Colors.redAccent;
      label = 'منتهي منذ ${-daysLeft} يوم';
      icon = Icons.error_rounded;
    } else if (daysLeft <= 3) {
      color = Colors.redAccent;
      label = 'ينتهي بعد $daysLeft أيام';
      icon = Icons.warning_amber_rounded;
    } else {
      color = Colors.orangeAccent;
      label = 'ينتهي بعد $daysLeft يوم';
      icon = Icons.schedule_rounded;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColorsDark.bgCardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item['name'] ?? 'بدون اسم',
                  style: TextStyle(
                    color: AppColorsDark.mainTextDark,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: color.withOpacity(0.4)),
                      ),
                      child: Text(
                        label,
                        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (expiryDate != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        expiryStr.split('T').first,
                        style: TextStyle(color: AppColorsDark.mainTextLight, fontSize: 11),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _toggleExpirySeen(id, seen),
            icon: Icon(
              Icons.check_circle_rounded,
              color: seen ? Colors.green : AppColorsDark.mainTextLight,
              size: 22,
            ),
            tooltip: 'وضع كمقروء',
          ),
        ],
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColorsDark.bgColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: Theme.of(context).iconTheme.color),
        title: Text('الإشعارات',
            style: TextStyle(color: AppColorsDark.mainTextDark, fontSize: 20)),
        actions: [
          if (_tabIndex == 0 && _lowStockItems.isNotEmpty)
            TextButton.icon(
              onPressed: _markAllLowStockRead,
              icon: Icon(Icons.done_all_rounded,
                  size: 16, color: AppColorsDark.mainColor),
              label: Text('قراءة الكل',
                  style: TextStyle(color: AppColorsDark.mainColor, fontSize: 13)),
            ),
          if (_tabIndex == 1 && _expiryItems.isNotEmpty)
            TextButton.icon(
              onPressed: _markAllExpiryRead,
              icon: Icon(Icons.done_all_rounded,
                  size: 16, color: AppColorsDark.mainColor),
              label: Text('قراءة الكل',
                  style: TextStyle(color: AppColorsDark.mainColor, fontSize: 13)),
            ),
          IconButton(
            icon: Icon(Icons.refresh, color: Theme.of(context).iconTheme.color),
            onPressed: _loadAll,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Directionality(
        textDirection: TextDirection.rtl,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Row(
                children: [
                  _tabButton('النواقص', Icons.inventory_2_rounded, 0,
                      _lowStockItems.length),
                  const SizedBox(width: 10),
                  _tabButton('قريب الانتهاء', Icons.schedule_rounded, 1,
                      _expiryItems.length),
                ],
              ),
            ),
            Expanded(
              child: _tabIndex == 0
                  ? _lowStockItems.isEmpty
                  ? const EmptyStateCard(
                icon: Icons.inventory_2_outlined,
                title: 'لا توجد نواقص',
                message: 'كل المنتجات أعلى من حد التنبيه.',
              )
                  : ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _lowStockItems.length,
                itemBuilder: (_, i) => _stockTile(_lowStockItems[i]),
              )
                  : _expiryItems.isEmpty
                  ? const EmptyStateCard(
                icon: Icons.event_available,
                title: 'لا توجد منتجات قرب الانتهاء',
                message: 'لا توجد تواريخ صلاحية تحتاج انتباهك.',
              )
                  : ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _expiryItems.length,
                itemBuilder: (_, i) => _expiryTile(_expiryItems[i]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}