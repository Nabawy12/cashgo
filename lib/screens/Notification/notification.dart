// screens/notifications/notifications_screen.dart
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
  int _tabIndex = 0; // 0 -> low stock, 1 -> expiry
  final int expiryThresholdDays = 10; // عدد الأيام للتحذير (قابل للتغيير)

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  int _safeInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is double) return v.toInt();
    final s = v.toString();
    return int.tryParse(s) ?? 0;
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      // ensure columns exist (مفيد لو نسخة قديمة)
      await DBHelper.instance.ensureLowStockSeenColumn();
      await DBHelper.instance.ensureProductDatesColumns();
      await DBHelper.instance.ensureExpirySeenColumn();

      final low = await DBHelper.instance.getLowStockUnseenProducts();
      final expiry = await DBHelper.instance
          .getExpiringUnseenProducts(daysThreshold: expiryThresholdDays);

      final normalizedLow = low.map((p) {
        return {
          ...p,
          'quantity': _safeInt(p['quantity']),
          'low_stock_seen': _safeInt(p['low_stock_seen']),
        };
      }).toList();

      final normalizedExpiry = expiry.map((p) {
        return {
          ...p,
          'expiry_seen': _safeInt(p['expiry_seen']),
        };
      }).toList();

      if (!mounted) return;
      setState(() {
        _lowStockItems = normalizedLow;
        _expiryItems = normalizedExpiry;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _lowStockItems = [];
        _expiryItems = [];
        _loading = false;
      });
    }
  }

  // ---- Low stock actions ----
  Future<void> _toggleLowStockSeen(int productId, bool currentSeen) async {
    try {
      await DBHelper.instance.setProductLowStockSeen(productId, true);
      final idx =
          _lowStockItems.indexWhere((p) => _safeInt(p['id']) == productId);
      if (idx != -1) {
        setState(() => _lowStockItems.removeAt(idx));
      } else {
        await _loadAll();
      }
    } catch (e) {
      await _loadAll();
    }
  }

  Future<void> _markAllLowStockRead() async {
    try {
      await DBHelper.instance.markAllLowStockSeen();
      if (!mounted) return;
      setState(() => _lowStockItems.clear());
    } catch (e) {
      await _loadAll();
    }
  }

  // ---- Expiry actions ----
  Future<void> _toggleExpirySeen(int productId, bool currentSeen) async {
    try {
      await DBHelper.instance.setProductExpirySeen(productId, true);
      final idx =
          _expiryItems.indexWhere((p) => _safeInt(p['id']) == productId);
      if (idx != -1) {
        setState(() => _expiryItems.removeAt(idx));
      } else {
        await _loadAll();
      }
    } catch (e) {
      await _loadAll();
    }
  }

  Future<void> _markAllExpiryRead() async {
    try {
      await DBHelper.instance
          .markAllExpirySeen(daysThreshold: expiryThresholdDays);
      if (!mounted) return;
      setState(() => _expiryItems.clear());
    } catch (e) {
      await _loadAll();
    }
  }

  bool _hasLowUnseen() => _lowStockItems.any(
      (p) => _safeInt(p['quantity']) < 5 && _safeInt(p['low_stock_seen']) == 0);
  bool _hasExpiryUnseen() => _expiryItems.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColorsDark.bgColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0.0,
        iconTheme: IconThemeData(
          color: Theme.of(context).iconTheme.color,
          size: 26,
        ),
        title: Text(
          'الإشعارات',
          style: TextStyle(fontSize: 20, color: AppColorsDark.mainTextDark),
        ),
        actions: [
          if (_tabIndex == 0 && _hasLowUnseen())
            IconButton(
              icon: const Icon(Icons.mark_email_read),
              tooltip: 'وضع كل الإشعارات مقروءة (النواقص)',
              onPressed: () async {
                await _markAllLowStockRead();
              },
            ),
          if (_tabIndex == 1 && _hasExpiryUnseen())
            IconButton(
              icon: const Icon(Icons.mark_email_read),
              tooltip: 'وضع كل الإشعارات مقروءة (قريب للانتهاء)',
              onPressed: () async {
                await _markAllExpiryRead();
              },
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAll,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Tabs
                Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: InkWell(
                            onTap: () => setState(() => _tabIndex = 0),
                            child: Container(
                              alignment: Alignment.center,
                              height: 40,
                              decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: _tabIndex == 1
                                        ? AppColorsDark.bgCardColor
                                        : AppColorsDark.mainColor,
                                    width: 2,
                                  )),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 20, vertical: 1),
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.inventory_2_outlined,
                                        size: 23,
                                        color:
                                            Theme.of(context).iconTheme.color,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'النواقص (${_lowStockItems.length})',
                                        style: TextStyle(
                                            color: AppColorsDark.mainTextDark,
                                            fontSize: 18),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            )),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: InkWell(
                            onTap: () => setState(() => _tabIndex = 1),
                            child: Container(
                              alignment: Alignment.center,
                              height: 40,
                              decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: _tabIndex == 0
                                        ? AppColorsDark.bgCardColor
                                        : AppColorsDark.mainColor,
                                    width: 2,
                                  )),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 20, vertical: 1),
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.access_time_outlined,
                                        size: 23,
                                        color:
                                            Theme.of(context).iconTheme.color,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'قريب للانتهاء (${_expiryItems.length})',
                                        style: TextStyle(
                                            color: AppColorsDark.mainTextDark,
                                            fontSize: 18),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            )),
                      ),
                    ],
                  ),
                ),

                // Content
                Expanded(
                  child: _tabIndex == 0
                      ? _buildLowStockList()
                      : _buildExpiryList(),
                ),
              ],
            ),
    );
  }

  Widget _buildLowStockList() {
    if (_lowStockItems.isEmpty) {
      return const EmptyStateCard(
        icon: Icons.inventory_2_outlined,
        title: 'لا توجد نواقص',
        message: 'كل المنتجات حالياً أعلى من حد التنبيه.',
      );
    }
    return ListView.separated(
      itemCount: _lowStockItems.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final item = _lowStockItems[index];
        final quantity = _safeInt(item['quantity']);
        if (quantity >= 5) return const SizedBox.shrink();
        final seen = _safeInt(item['low_stock_seen']) == 1;
        return Container(
          margin: EdgeInsets.symmetric(vertical: 15, horizontal: 12),
          padding: EdgeInsets.all(5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: AppColorsDark.mainColor.withOpacity(0.6),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                spreadRadius: 2,
                blurRadius: 8,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: ListTile(
            leading: Icon(Icons.inventory,
                color: quantity == 0
                    ? Colors.red
                    : Theme.of(context).iconTheme.color),
            title: Text(
              item['name'] ?? 'بدون اسم',
              style: TextStyle(
                fontSize: 15,
                color: AppColorsDark.mainTextLight,
              ),
            ),
            subtitle: Text(
              'الكمية المتبقية: $quantity',
              style: TextStyle(
                  fontSize: 17,
                  color: AppColorsDark.mainTextDark,
                  fontWeight: FontWeight.w500),
            ),
            trailing: IconButton(
              icon: Icon(Icons.mark_email_read,
                  color:
                      seen ? Colors.green : Theme.of(context).iconTheme.color),
              onPressed: () => _toggleLowStockSeen(_safeInt(item['id']), seen),
            ),
            tileColor: seen ? Colors.black12 : null,
          ),
        );
      },
    );
  }

  Widget _buildExpiryList() {
    if (_expiryItems.isEmpty) {
      return const EmptyStateCard(
        icon: Icons.event_available,
        title: 'لا توجد منتجات قرب الانتهاء',
        message: 'لا توجد تواريخ صلاحية تحتاج انتباهك الآن.',
      );
    }
    return ListView.separated(
      itemCount: _expiryItems.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final item = _expiryItems[index];
        final expiryStr = (item['expiry_date'] ?? '').toString();
        final expiryDate =
            expiryStr.isNotEmpty ? DateTime.tryParse(expiryStr) : null;
        final daysLeft = expiryDate != null
            ? expiryDate.difference(DateTime.now()).inDays
            : null;
        final seen = _safeInt(item['expiry_seen']) == 1;

        String subtitle;
        if (expiryDate == null) {
          subtitle = 'تاريخ انتهاء غير معروف';
        } else if (daysLeft! < 0) {
          subtitle = 'منتهي منذ ${-daysLeft} يوم';
        } else {
          subtitle = 'ينتهي بعد $daysLeft يوم';
        }

        return Container(
          margin: EdgeInsets.symmetric(vertical: 15, horizontal: 12),
          padding: EdgeInsets.all(5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: AppColorsDark.mainColor.withOpacity(0.6),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                spreadRadius: 2,
                blurRadius: 8,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: ListTile(
            leading: Icon(Icons.timer,
                color: (daysLeft != null && daysLeft <= 0)
                    ? Colors.red
                    : Colors.grey.withOpacity(0.5)),
            title: Text(
              item['name'] ?? 'بدون اسم',
              style:
                  TextStyle(fontSize: 15, color: AppColorsDark.mainTextLight),
            ),
            subtitle: Text(
              '$expiryStr — $subtitle',
              style: TextStyle(
                  fontSize: 17,
                  color: AppColorsDark.mainTextDark,
                  fontWeight: FontWeight.w500),
            ),
            trailing: IconButton(
              icon: Icon(Icons.mark_email_read,
                  color:
                      seen ? Colors.green : Theme.of(context).iconTheme.color),
              onPressed: () => _toggleExpirySeen(_safeInt(item['id']), seen),
            ),
            tileColor:
                seen ? AppColorsDark.mainColor.withValues(alpha: 0.08) : null,
          ),
        );
      },
    );
  }
}
