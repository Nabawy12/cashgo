// lib/screens/admin/credits_screen.dart
import 'package:accordion_widget/accordion_widget.dart';
import 'package:cashgo/utils/colors.dart';
import 'package:cashgo/widgets/custom_form.dart';
import 'package:flutter/material.dart';
import '../../services/db/db_helper.dart';
import '../../models/login.dart';

class CreditsScreen extends StatefulWidget {
  static const routeName = "/credits";
  const CreditsScreen({super.key});

  @override
  State<CreditsScreen> createState() => _CreditsScreenState();
}

class _CreditsScreenState extends State<CreditsScreen> {
  bool loading = true;
  List<Map<String, dynamic>> credits = [];
  String query = "";
  final Map<int, List<Map<String, dynamic>>> saleItemsCache = {};
  final Set<int> loadingSaleItems = {};
  final Set<int> loadingSaleReturnItems = {};
  final Map<int, List<Map<String, dynamic>>> saleReturnItemsCache = {};
  final Map<int, List<Map<String, dynamic>>> saleReturnsCache = {};

  @override
  void initState() {
    super.initState();
    _loadCredits();
  }

  Future<void> _loadCredits() async {
    setState(() => loading = true);
    try {
      final rows = await DBHelper.instance.getAllSales();
      credits = rows.where((r) {
        final v = r['is_credit'];
        if (v == null) return false;
        if (v is int) return v == 1;
        if (v is bool) return v == true;
        if (v is String) {
          final s = v.trim().toLowerCase();
          return s == '1' || s == 'true' || s == 'yes';
        }
        return false;
      }).toList();

      credits.sort((a, b) {
        final da = (a['date'] ?? '').toString();
        final db = (b['date'] ?? '').toString();
        return db.compareTo(da);
      });

      saleItemsCache.clear();
      saleReturnItemsCache.clear();
      saleReturnsCache.clear();

      final ids = credits.map((c) => (c['id'] as num).toInt()).toList();
      for (final id in ids) {
        try {
          await _ensureSaleItemsLoaded(id);
          await _ensureSaleReturnDataLoaded(id);
        } catch (_) {}
      }
    } finally {
      setState(() => loading = false);
    }
  }

  Future<void> _ensureSaleItemsLoaded(int saleId) async {
    if (saleItemsCache.containsKey(saleId) || loadingSaleItems.contains(saleId)) return;
    setState(() => loadingSaleItems.add(saleId));
    try {
      final items = await DBHelper.instance.getSaleItemsBySaleId(saleId);
      saleItemsCache[saleId] = items;
    } finally {
      setState(() => loadingSaleItems.remove(saleId));
    }
  }

  Future<void> _ensureSaleReturnDataLoaded(int saleId) async {
    if (!saleReturnItemsCache.containsKey(saleId) && !loadingSaleReturnItems.contains(saleId)) {
      setState(() => loadingSaleReturnItems.add(saleId));
      try {
        final rows = await DBHelper.instance.getSaleReturnItemsForSale(saleId);
        saleReturnItemsCache[saleId] = rows;
      } finally {
        setState(() => loadingSaleReturnItems.remove(saleId));
      }
    }

    if (!saleReturnsCache.containsKey(saleId)) {
      final rows = await DBHelper.instance.getSaleReturnsBySaleId(saleId);
      saleReturnsCache[saleId] = rows;
    }
  }

  String _formatTime(String isoString) {
    try {
      final dt = DateTime.parse(isoString);
      final hh = dt.hour.toString().padLeft(2, '0');
      final mm = dt.minute.toString().padLeft(2, '0');
      final ss = dt.second.toString().padLeft(2, '0');
      return '$hh:$mm:$ss';
    } catch (_) {
      return isoString;
    }
  }

  void _applySearch(String q) {
    setState(() => query = q.trim().toLowerCase());
  }

  List<Map<String, dynamic>> get _filtered {
    if (query.isEmpty) return credits;
    return credits.where((s) {
      final name = (s['customer_name'] ?? '').toString().toLowerCase();
      final cashier = (s['cashier_username'] ?? '').toString().toLowerCase();
      final id = (s['id'] ?? '').toString();
      return name.contains(query) || cashier.contains(query) || id.contains(query);
    }).toList();
  }

  double _effectiveTotalForSaleHeader(Map<String, dynamic> s) {
    final saleId = (s['id'] as num?)?.toInt();
    double currentItemsTotal = 0.0;
    if (saleId != null && saleItemsCache.containsKey(saleId)) {
      final items = saleItemsCache[saleId]!;
      currentItemsTotal = items.fold<double>(0.0, (p, it) {
        final qty = (it['quantity'] as num?)?.toDouble() ?? 0.0;
        final price = (it['price'] as num?)?.toDouble() ?? 0.0;
        return p + qty * price;
      });
    } else {
      currentItemsTotal = (s['total'] as num?)?.toDouble() ?? 0.0;
    }

    final discountTypeRaw = (s['discount_type'] ?? 'fixed').toString();
    final discountValueRaw = (s['discount_value'] as num?)?.toDouble() ?? 0.0;
    final discountType = (discountTypeRaw == 'percent') ? 'percent' : 'fixed';
    double discountValue = discountValueRaw.isFinite ? discountValueRaw : 0.0;

    double discountAmount = 0.0;
    if (discountType == 'percent') {
      discountAmount = currentItemsTotal * (discountValue / 100.0);
    } else {
      discountAmount = discountValue;
    }
    if (discountAmount < 0) discountAmount = 0.0;
    if (discountAmount > currentItemsTotal) discountAmount = currentItemsTotal;

    return (currentItemsTotal - discountAmount).clamp(0.0, double.infinity);
  }

  String _discountLabelForSale(Map<String, dynamic> s) {
    final saleId = (s['id'] as num?)?.toInt();
    double currentItemsTotal = 0.0;
    if (saleId != null && saleItemsCache.containsKey(saleId)) {
      final items = saleItemsCache[saleId]!;
      currentItemsTotal = items.fold<double>(0.0, (p, it) {
        final qty = (it['quantity'] as num?)?.toDouble() ?? 0.0;
        final price = (it['price'] as num?)?.toDouble() ?? 0.0;
        return p + qty * price;
      });
    } else {
      currentItemsTotal = (s['total'] as num?)?.toDouble() ?? 0.0;
    }

    final discountTypeRaw = (s['discount_type'] ?? 'fixed').toString();
    final discountValueRaw = (s['discount_value'] as num?)?.toDouble() ?? 0.0;
    final discountType = (discountTypeRaw == 'percent') ? 'percent' : 'fixed';
    double discountValue = discountValueRaw.isFinite ? discountValueRaw : 0.0;

    double discountAmount = 0.0;
    if (discountType == 'percent') {
      discountAmount = currentItemsTotal * (discountValue / 100.0);
    } else {
      discountAmount = discountValue;
    }
    if (discountAmount <= 0) return '';

    if (discountType == 'percent') {
      return 'خصم ${discountValue.toStringAsFixed(0)}% (${discountAmount.toStringAsFixed(2)})';
    } else {
      return 'خصم ثابت ${discountAmount.toStringAsFixed(2)}';
    }
  }

  Future<void> _markAsPaid(int saleId, Map<String, dynamic> saleRow, String method) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColorsDark.bgCardColor,
        title: Center(child: Text('تأكيد الدفع', style: TextStyle(color: Colors.white))),
        content: Directionality(
          textDirection: TextDirection.rtl,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Text(
              method == 'cash' ? 'سيتم تسجيل الفاتورة كمُسدّدة نقدًا.' : 'سيتم تسجيل الفاتورة كمُسدّدة بكارت/كريدت.',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ),
        actions: [
          TextButton(
              style: TextButton.styleFrom(backgroundColor: AppColorsDark.bgCardColor),
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء', style: TextStyle(color: Colors.white))),
          TextButton(
              style: TextButton.styleFrom(backgroundColor: AppColorsDark.bgCardColor),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('تأكيد', style: TextStyle(color: Colors.white))),
        ],
      ),
    );
    if (confirmed != true) return;

    final double currentTotal = _effectiveTotalForSaleHeader(saleRow);
    final double prevPaid = (saleRow['paid_amount'] as num?)?.toDouble() ?? 0.0;
    final double paymentDelta = (currentTotal - prevPaid);

    final db = await DBHelper.instance.database;
    await db.update(
      'sales',
      {
        'is_credit': 0,
        'paid_amount': currentTotal,
        'change_amount': 0,
        'payment_method': method,
      },
      where: 'id = ?',
      whereArgs: [saleId],
    );

    if (paymentDelta > 0) {
      try {
        await db.insert('drawer_movements', {
          'amount': paymentDelta,
          'method': method,
          'ref_sale_id': saleId,
          'date': DateTime.now().toIso8601String(),
          'note': 'سداد فاتورة آجل #$saleId'
        });
      } catch (e) {
        debugPrint('Cannot insert drawer_movements: $e');
      }
    }

    setState(() {
      credits.removeWhere((r) => (r['id'] as num).toInt() == saleId);
      saleItemsCache.remove(saleId);
      saleReturnItemsCache.remove(saleId);
      saleReturnsCache.remove(saleId);
    });

    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تحويل الفاتورة إلى مدفوعة.')));
  }

  Future<void> _deleteCredit(int saleId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColorsDark.bgCardColor,
        title:Center(child: Text('حذف الفاتورة',style: TextStyle(color: Colors.white),)),
        content: Text(
          'هل تريد حذف الفاتورة #$saleId؟ حذف الفاتورة الآجلة لن يعيد المخزون تلقائيًا',
          style: TextStyle(
              color: Colors.white
          ),
        ),
        actions: [
          TextButton(
              style: TextButton.styleFrom(
                backgroundColor: AppColorsDark.bgCardColor,
              ),
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء',style: TextStyle(color: Colors.white),)
          ),
          TextButton(
              style: TextButton.styleFrom(
                backgroundColor: AppColorsDark.bgCardColor,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('حذف',style: TextStyle(color: Colors.white),)),
        ],
      ),
    );
    if (ok != true) return;
    final db = await DBHelper.instance.database;
    await db.delete('sale_return_items', where: 'return_id IN (SELECT id FROM sale_returns WHERE sale_id = ?)', whereArgs: [saleId]);
    await db.delete('sale_returns', where: 'sale_id = ?', whereArgs: [saleId]);
    await db.delete('sale_items', where: 'sale_id = ?', whereArgs: [saleId]);
    await db.delete('sales', where: 'id = ?', whereArgs: [saleId]);
    setState(() => credits.removeWhere((r) => (r['id'] as num).toInt() == saleId));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('حُذفت الفاتورة الآجلة.')));
  }

  @override
  Widget build(BuildContext context) {
    final list = _filtered;

    // Group credits by cashier username
    final Map<String, List<Map<String, dynamic>>> byCashier = {};
    for (final s in list) {
      final cashier = (s['cashier_username'] ?? Session.currentUsername ?? '-').toString();
      byCashier.putIfAbsent(cashier, () => []).add(s);
    }
    final cashiers = byCashier.keys.toList();

    return Scaffold(
      backgroundColor: AppColorsDark.bgColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0.0,
        scrolledUnderElevation: 0.0,
        iconTheme: IconThemeData(
            color: Colors.white70
        ),
        title: const Text(
          'الفواتير الآجلة',
          style: TextStyle(
              color: Colors.white,
              fontSize: 25
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'تحديث',
            onPressed: _loadCredits,
            icon: const Icon(Icons.refresh,color: Colors.white70,size: 22,),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            CustomFormField(
              hint: 'بحث باسم العميل / رقم الفاتورة',
              onChanged: _applySearch,
              centerHint: true,
            ),
            const SizedBox(height: 14),
            Expanded(
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : list.isEmpty
                  ? const Center(child: Text('لا توجد فواتير آجلة', style: TextStyle(fontSize: 18,color: Colors.white)))
                  : ListView.separated(
                itemCount: cashiers.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, idx) {
                  final cashier = cashiers[idx];
                  final salesForCashier = byCashier[cashier] ?? [];

                  return Card(
                    color: AppColorsDark.bgCardColor,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: AppColorsDark.mainColor.withOpacity(0.12))),
                    child: Directionality(
                      textDirection: TextDirection.rtl,
                      child: AccordionWidget(
                        decoration: BoxDecoration(
                            color: AppColorsDark.bgColor
                        ),
                        showIcon: true,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        header: AbsorbPointer(
                          absorbing: true,

                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 6),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 22,
                                  backgroundColor: AppColorsDark.mainColor.withOpacity(0.12),
                                  child: Text('${salesForCashier.length}', style: TextStyle(color: AppColorsDark.mainColor, fontWeight: FontWeight.bold)),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(cashier, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
                                      const SizedBox(height: 6),
                                      Text('الفواتير الخاصة بهذا الكاشير', style: TextStyle(color: Colors.white70, fontSize: 12)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        content: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // For each sale of this cashier, render the existing sale Card+Accordion as before
                              ...salesForCashier.map((s) {
                                final saleId = (s['id'] as num).toInt();
                                final customer = (s['customer_name'] ?? '-').toString();
                                final effectiveTotal = _effectiveTotalForSaleHeader(s);
                                final paid = (s['paid_amount'] as num?)?.toDouble() ?? 0.0;
                                final dateRaw = (s['date'] ?? '').toString();
                                final time = _formatTime(dateRaw);
                                final cashierName = (s['cashier_username'] ?? Session.currentUsername ?? '-').toString();
                                final discountLabel = _discountLabelForSale(s);

                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 6.0),
                                  child: Card(
                                    color: AppColorsDark.bgCardColor,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: AppColorsDark.mainColor.withOpacity(0.12))),
                                    child: Directionality(
                                      textDirection: TextDirection.rtl,
                                      child: AccordionWidget(
                                        decoration: BoxDecoration(
                                            color: AppColorsDark.bgColor
                                        ),

                                        showIcon: false,
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                        header: Padding(
                                          padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 6),
                                          child: AbsorbPointer(
                                            absorbing: true,
                                            child: Row(
                                              children: [
                                                CircleAvatar(
                                                  radius: 22,
                                                  backgroundColor: AppColorsDark.mainColor.withOpacity(0.12),
                                                  child: Text('#$saleId', style: TextStyle(color: AppColorsDark.mainColor, fontWeight: FontWeight.bold)),
                                                ),
                                                const SizedBox(width: 12),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Text(customer, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
                                                      const SizedBox(height: 6),
                                                      Row(
                                                        children: [
                                                          Icon(Icons.person, size: 14, color: Colors.white24),
                                                          const SizedBox(width: 6),
                                                          Text(cashierName, style: TextStyle(color: Colors.white70, fontSize: 12)),
                                                          const SizedBox(width: 12),
                                                          Icon(Icons.access_time, size: 14, color: Colors.white24),
                                                          const SizedBox(width: 6),
                                                          Text(time, style: TextStyle(color: Colors.white70, fontSize: 12)),
                                                        ],
                                                      )
                                                    ],
                                                  ),
                                                ),

                                                Column(
                                                  crossAxisAlignment: CrossAxisAlignment.end,
                                                  children: [
                                                    Text(effectiveTotal.toStringAsFixed(2), style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                                                    const SizedBox(height: 6),
                                                    if (discountLabel.isNotEmpty)
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                        decoration: BoxDecoration(
                                                          color: AppColorsDark.mainColor.withOpacity(0.08),
                                                          borderRadius: BorderRadius.circular(20),
                                                          border: Border.all(color: AppColorsDark.mainColor.withOpacity(0.2)),
                                                        ),
                                                        child: Text(discountLabel, style: TextStyle(color: AppColorsDark.mainColor, fontSize: 12)),
                                                      )
                                                  ],
                                                )
                                              ],
                                            ),
                                          ),
                                        ),
                                        content: Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Builder(builder: (_) {
                                                final items = saleItemsCache[saleId] ?? [];
                                                if (loadingSaleItems.contains(saleId)) {
                                                  return const Padding(
                                                    padding: EdgeInsets.all(8.0),
                                                    child: Center(child: CircularProgressIndicator()),
                                                  );
                                                }
                                                if (items.isEmpty) {
                                                  return const Padding(
                                                    padding: EdgeInsets.all(8.0),
                                                    child: Text('لا توجد عناصر مسجلة لهذه الفاتورة', style: TextStyle(color: Colors.white)),
                                                  );
                                                }

                                                final itemsTotal = items.fold<double>(0.0, (p, it) {
                                                  final qty = (it['quantity'] as num?)?.toDouble() ?? 0.0;
                                                  final price = (it['price'] as num?)?.toDouble() ?? 0.0;
                                                  return p + qty * price;
                                                });

                                                final discountTypeRaw = (s['discount_type'] ?? 'fixed').toString();
                                                final discountValueRaw = (s['discount_value'] as num?)?.toDouble() ?? 0.0;
                                                final discountType = (discountTypeRaw == 'percent') ? 'percent' : 'fixed';
                                                double discountValue = discountValueRaw.isFinite ? discountValueRaw : 0.0;
                                                double discountAmount = 0.0;
                                                if (discountType == 'percent') {
                                                  discountAmount = itemsTotal * (discountValue / 100.0);
                                                } else {
                                                  discountAmount = discountValue;
                                                }
                                                if (discountAmount < 0) discountAmount = 0.0;
                                                if (discountAmount > itemsTotal) discountAmount = itemsTotal;

                                                final effectiveTotalLocal = (itemsTotal - discountAmount).clamp(0.0, double.infinity);

                                                return Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    // items list: compact rows
                                                    ...items.map((it) {
                                                      final name = (it['product_name'] ?? 'منتج') as String;
                                                      final qty = (it['quantity'] as num?)?.toInt() ?? 0;
                                                      final price = (it['price'] as num?)?.toDouble() ?? 0.0;
                                                      return Padding(
                                                        padding: const EdgeInsets.symmetric(vertical: 6.0),
                                                        child: Row(
                                                          children: [
                                                            Expanded(
                                                              child: Text(name, style: const TextStyle(color: Colors.white70, fontSize: 14), overflow: TextOverflow.ellipsis),
                                                            ),
                                                            const SizedBox(width: 8),
                                                            Text('$qty x', style: const TextStyle(color: Colors.white54, fontSize: 13)),
                                                            const SizedBox(width: 8),
                                                            Text(price.toStringAsFixed(2), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                                                          ],
                                                        ),
                                                      );
                                                    }).toList(),

                                                    const Divider(color: Colors.white12),

                                                    // summary row: neat two-column layout
                                                    Padding(
                                                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                                                      child: Row(
                                                        children: [
                                                          Expanded(
                                                            child: Column(
                                                              crossAxisAlignment: CrossAxisAlignment.start,
                                                              children: [
                                                                Text('مجموع العناصر', style: TextStyle(color: Colors.white70, fontSize: 12)),
                                                                const SizedBox(height: 6),
                                                                Text(itemsTotal.toStringAsFixed(2), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                                              ],
                                                            ),
                                                          ),
                                                          Expanded(
                                                            child: Column(
                                                              crossAxisAlignment: CrossAxisAlignment.end,
                                                              children: [
                                                                Text('بعد الخصم', style: TextStyle(color: Colors.white70, fontSize: 12)),
                                                                const SizedBox(height: 6),
                                                                Text(effectiveTotalLocal.toStringAsFixed(2), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                                              ],
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),

                                                    const SizedBox(height: 10),

                                                    // actions row
                                                    Row(
                                                      mainAxisAlignment: MainAxisAlignment.end,
                                                      children: [
                                                        TextButton.icon(
                                                          style: TextButton.styleFrom(
                                                            backgroundColor: AppColorsDark.bgCardColor,
                                                          ),
                                                          onPressed: () async {
                                                            final choice = await showDialog<String>(
                                                              context: context,
                                                              builder: (ctx) => AlertDialog(
                                                                backgroundColor: AppColorsDark.bgCardColor,
                                                                title:Center(child: Text('بماذا تم الدفع؟',style: TextStyle(color: Colors.white,fontSize: 22),)),
                                                                actions: [
                                                                  TextButton(
                                                                      style: TextButton.styleFrom(
                                                                        backgroundColor: AppColorsDark.bgCardColor,
                                                                      ),
                                                                      onPressed: () => Navigator.pop(ctx, null),
                                                                      child: const Text('إلغاء',style: TextStyle(color: Colors.white),)),
                                                                  TextButton(
                                                                      style: TextButton.styleFrom(
                                                                        backgroundColor: AppColorsDark.bgCardColor,
                                                                      ),
                                                                      onPressed: () => Navigator.pop(ctx, 'card'),
                                                                      child: const Text('كارت',style: TextStyle(color: Colors.white),)),
                                                                  TextButton(
                                                                      style: TextButton.styleFrom(
                                                                        backgroundColor: AppColorsDark.bgCardColor,
                                                                      ),
                                                                      onPressed: () => Navigator.pop(ctx, 'cash'),
                                                                      child: const Text('نقدي',style: TextStyle(color: Colors.white),)),
                                                                ],
                                                              ),
                                                            );
                                                            if (choice == null) return;
                                                            await _markAsPaid(saleId, s, choice);
                                                          },
                                                          icon: const Icon(Icons.check_circle, color: Colors.green),
                                                          label: const Text('تم الدفع',style: TextStyle(color: Colors.green),),
                                                        ),
                                                        const SizedBox(width: 8),
                                                        TextButton.icon(
                                                          style: TextButton.styleFrom(
                                                            backgroundColor: AppColorsDark.bgCardColor,
                                                          ),
                                                          onPressed: () => _deleteCredit(saleId),
                                                          icon:Icon(Icons.delete,color: Colors.red.withOpacity(0.7)),
                                                          label: Text('حذف',style: TextStyle(color: Colors.red.withOpacity(0.7)),),
                                                        ),
                                                      ],
                                                    ),

                                                  ],
                                                );
                                              }),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
