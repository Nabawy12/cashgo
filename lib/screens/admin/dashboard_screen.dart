// lib/screens/admin/admin_dashboard_screen.dart
// Admin dashboard — عرض الفاتورة الأصلية + عمليات المرتجع مفصّلة (كل عملية: مرجوعات ✖ وبدائل ✓)
// ويعرض تحت كل عملية المرتجع العناصر المضافة كبديل مباشرة (indent) — لجعل العلاقة واضحة.

import 'package:flutter/material.dart';
import '../../services/db/db_helper.dart';
import '../../utils/colors.dart';
import '../Notification/notification.dart';
import 'product_management_screen.dart';
import 'profit_screen.dart';
import 'change_password_screen.dart';

class AdminDashboardScreen extends StatefulWidget {
  final String username;
  const AdminDashboardScreen({super.key, required this.username});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  int _unseenCount = 0;
  bool loading = true;
  List<Map<String, dynamic>> sales = [];
  Map<String, List<Map<String, dynamic>>> groupedByDate = {};

  // caches
  final Map<int, List<Map<String, dynamic>>> saleItemsCache = {};
  final Set<int> loadingSaleItems = {};

  final Map<int, List<Map<String, dynamic>>> saleReturnItemsCache = {}; // joined rows (includes return_id)
  final Set<int> loadingSaleReturnItems = {};

  final Map<int, List<Map<String, dynamic>>> saleReturnsCache = {}; // sale_returns rows (contain paid_delta, date, note)
  final Set<int> loadingSaleReturns = {};

  @override
  void initState() {
    super.initState();
    _loadUnseen();
    _loadSales();
  }

  Future<void> _loadSales() async {
    setState(() => loading = true);
    try {
      final rows = await DBHelper.instance.getAllSales();
      sales = rows;
      saleItemsCache.clear();
      saleReturnItemsCache.clear();
      saleReturnsCache.clear();
      _groupSalesByDate();
    } finally {
      setState(() => loading = false);
    }
  }

  void _groupSalesByDate() {
    groupedByDate = {};
    for (final s in sales) {
      final dateRaw = (s['date'] ?? '').toString();
      String dateOnly;
      try {
        dateOnly = DateTime.parse(dateRaw).toIso8601String().split('T').first;
      } catch (_) {
        dateOnly = dateRaw.split(' ').first.split('T').first;
      }
      groupedByDate.putIfAbsent(dateOnly, () => []).add(s);
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

  /// Load both sale_return_items (joined) and sale_returns
  Future<void> _ensureSaleReturnDataLoaded(int saleId) async {
    if (!saleReturnItemsCache.containsKey(saleId) && !loadingSaleReturnItems.contains(saleId)) {
      setState(() => loadingSaleReturnItems.add(saleId));
      try {
        final rows = await DBHelper.instance.getSaleReturnItemsForSale(saleId);
        // each row contains: sri.*, sr.date, sr.paid_delta, sr.return_note, product fields
        saleReturnItemsCache[saleId] = rows;
      } finally {
        setState(() => loadingSaleReturnItems.remove(saleId));
      }
    }

    if (!saleReturnsCache.containsKey(saleId) && !loadingSaleReturns.contains(saleId)) {
      setState(() => loadingSaleReturns.add(saleId));
      try {
        final rows = await DBHelper.instance.getSaleReturnsBySaleId(saleId);
        saleReturnsCache[saleId] = rows;
      } finally {
        setState(() => loadingSaleReturns.remove(saleId));
      }
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

  // helpers: build maps & sums
  Map<int, int> _returnedQtyMapForSale(int saleId) {
    final rows = saleReturnItemsCache[saleId] ?? [];
    final Map<int, int> m = {};
    for (final r in rows) {
      final pid = (r['product_id'] as num).toInt();
      final qty = (r['qty'] as num?)?.toInt() ?? 0;
      final isReplacement = (r['is_replacement'] as num?)?.toInt() ?? 0;
      if (isReplacement == 0) {
        m[pid] = (m[pid] ?? 0) + qty;
      }
    }
    return m;
  }

  Map<int, int> _replacementQtyMapForSale(int saleId) {
    final rows = saleReturnItemsCache[saleId] ?? [];
    final Map<int, int> m = {};
    for (final r in rows) {
      final pid = (r['product_id'] as num).toInt();
      final qty = (r['qty'] as num?)?.toInt() ?? 0;
      final isReplacement = (r['is_replacement'] as num?)?.toInt() ?? 0;
      if (isReplacement == 1) {
        m[pid] = (m[pid] ?? 0) + qty;
      }
    }
    return m;
  }

  Map<String, double> _computeReturnSums(int saleId) {
    final rows = saleReturnItemsCache[saleId] ?? [];
    double refunded = 0.0;
    double addedCost = 0.0;
    for (final r in rows) {
      final qty = (r['qty'] as num?)?.toInt() ?? 0;
      final price = (r['price'] as num?)?.toDouble() ?? 0.0;
      final isReplacement = (r['is_replacement'] as num?)?.toInt() ?? 0;
      if (isReplacement == 0) refunded += qty * price;
      else addedCost += qty * price;
    }
    return {'refunded': refunded, 'added': addedCost, 'net': addedCost - refunded};
  }

  double _sumPaidDeltaForSale(int saleId) {
    final rows = saleReturnsCache[saleId] ?? [];
    double sum = 0.0;
    for (final r in rows) {
      sum += (r['paid_delta'] as num?)?.toDouble() ?? 0.0;
    }
    return sum;
  }

  // Group sale_return_items by return_id so we can show replacements under the specific return action
  Map<int, List<Map<String, dynamic>>> _groupReturnItemsByReturnId(int saleId) {
    final rows = saleReturnItemsCache[saleId] ?? [];
    final Map<int, List<Map<String, dynamic>>> m = {};
    for (final r in rows) {
      final rid = (r['return_id'] as num).toInt();
      m.putIfAbsent(rid, () => []).add(r);
    }
    return m;
  }

  @override
  Widget build(BuildContext context) {
    final dateKeys = groupedByDate.keys.toList()..sort((a,b) => b.compareTo(a)); // latest first

    return Scaffold(
      backgroundColor: AppColorsDark.bgColor,
      appBar: AppBar(
        iconTheme: const IconThemeData(color: Colors.white),
        backgroundColor: Colors.transparent,
        elevation: 0.0,
        title: const Text('اداره التطبيق', style: TextStyle(color: Colors.white)),
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
            // top actions
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProductManagementScreen())),
                    child: Container(
                      alignment: Alignment.center,
                      height: 40,
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColorsDark.mainColor, width: 2)),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 1),
                        child: Text('اداره المنتجات', style: TextStyle(color: Colors.white, fontSize: 18)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: InkWell(
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfitScreen())),
                    child: Container(
                      alignment: Alignment.center,
                      height: 40,
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColorsDark.mainColor, width: 2)),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 1),
                        child: Text('نسبه الارباح', style: TextStyle(color: Colors.white, fontSize: 18)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            // sales list
            Expanded(
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : groupedByDate.isEmpty
                  ? const Center(child: Text('لا توجد فواتير حتى الآن', style: TextStyle(fontSize: 20, color: Colors.white)))
                  : ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: dateKeys.length,
                itemBuilder: (context, idx) {
                  final date = dateKeys[idx];
                  final daySales = groupedByDate[date]!;
                  final dayTotal = daySales.fold<double>(0.0, (p, s) => p + ((s['total'] as num?)?.toDouble() ?? 0.0));
                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    child: ExpansionTile(
                      initiallyExpanded: true,
                      title: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(date, style: const TextStyle(fontWeight: FontWeight.bold)),
                          Text('فاتورات: ${daySales.length}'),
                          Text('إجمالي اليوم: ${dayTotal.toStringAsFixed(2)}'),
                        ],
                      ),
                      children: daySales.map((s) {
                        final saleId = (s['id'] as num).toInt();
                        final originalTotal = (s['total'] as num?)?.toDouble() ?? 0.0; // original, unchanged
                        final originalPaid = (s['paid_amount'] as num?)?.toDouble() ?? 0.0;
                        final cashier = (s['cashier_username'] ?? '').toString();
                        final dateRaw = (s['date'] ?? '').toString();
                        final time = _formatTime(dateRaw);

                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
                          child: Card(
                            color: Colors.white,
                            child: ExpansionTile(
                              onExpansionChanged: (open) {
                                if (open) {
                                  _ensureSaleItemsLoaded(saleId);
                                  _ensureSaleReturnDataLoaded(saleId);
                                }
                              },
                              title: Row(
                                children: [
                                  Expanded(child: Text('فاتورة #$saleId', style: const TextStyle(fontWeight: FontWeight.bold))),
                                  const SizedBox(width: 8),
                                  Text('الوقت: $time'),
                                  const SizedBox(width: 8),
                                  Text('المجموع: ${originalTotal.toStringAsFixed(2)}'),
                                ],
                              ),
                              subtitle: Row(
                                children: [
                                  Text('كاشير: ${cashier.isEmpty ? "-" : cashier}'),
                                  const SizedBox(width: 12),
                                  Text((s['is_credit'] ?? 0) == 1 ? 'آجل' : 'مدفوعة'),
                                  const SizedBox(width: 12),
                                  if ((s['is_return'] ?? 0) == 1) const Text('مرتجع', style: TextStyle(color: Colors.red)),
                                ],
                              ),
                              childrenPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              children: [
                                Builder(builder: (context) {
                                  final items = saleItemsCache[saleId] ?? [];
                                  final returnRows = saleReturnItemsCache[saleId] ?? [];
                                  final returnsMeta = saleReturnsCache[saleId] ?? [];

                                  final returnedMap = _returnedQtyMapForSale(saleId);
                                  final replacementMap = _replacementQtyMapForSale(saleId);
                                  final sums = _computeReturnSums(saleId);
                                  final paidDeltaSum = _sumPaidDeltaForSale(saleId);

                                  final refundedVal = sums['refunded'] ?? 0.0;
                                  final addedVal = sums['added'] ?? 0.0;
                                  final netVal = sums['net'] ?? 0.0;

                                  final effectiveTotal = originalTotal + addedVal - refundedVal;
                                  final effectivePaid = originalPaid + paidDeltaSum;
                                  final effectiveChange = (effectivePaid >= effectiveTotal) ? (effectivePaid - effectiveTotal) : 0.0;
                                  final effectiveRemaining = (effectivePaid < effectiveTotal) ? (effectiveTotal - effectivePaid) : 0.0;

                                  if (loadingSaleItems.contains(saleId) || loadingSaleReturnItems.contains(saleId) || loadingSaleReturns.contains(saleId)) {
                                    return const Padding(
                                      padding: EdgeInsets.all(8.0),
                                      child: Center(child: CircularProgressIndicator()),
                                    );
                                  }

                                  if (items.isEmpty) {
                                    return const Padding(
                                      padding: EdgeInsets.all(8.0),
                                      child: Text('لا توجد عناصر مسجلة لهذه الفاتورة'),
                                    );
                                  }

                                  // group return_items by return_id to display mapping: returned items -> replacements per return
                                  final returnsById = _groupReturnItemsByReturnId(saleId);

                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('عناصر الفاتورة الأصلية:', style: TextStyle(fontWeight: FontWeight.bold)),
                                      const SizedBox(height: 8),
                                      ListView.separated(
                                        shrinkWrap: true,
                                        physics: const NeverScrollableScrollPhysics(),
                                        itemCount: items.length,
                                        separatorBuilder: (_, __) => const Divider(),
                                        itemBuilder: (context, i) {
                                          final it = items[i];
                                          final pid = (it['product_id'] as num).toInt();
                                          final name = (it['product_name'] ?? 'منتج') as String;
                                          final qty = (it['quantity'] as num?)?.toInt() ?? 0;
                                          final price = (it['price'] as num?)?.toDouble() ?? 0.0;
                                          final subtotal = qty * price;
                                          final barcode = (it['product_barcode'] ?? '-') as String;

                                          final returnedQty = returnedMap[pid] ?? 0;
                                          final replacementQty = replacementMap[pid] ?? 0;

                                          return ListTile(
                                            contentPadding: EdgeInsets.zero,
                                            title: Row(
                                              children: [
                                                Expanded(child: Text(name)),
                                                if (returnedQty > 0)
                                                  Padding(
                                                    padding: const EdgeInsets.only(left: 8.0),
                                                    child: Row(
                                                      children: [
                                                        const Icon(Icons.close, color: Colors.red, size: 18),
                                                        const SizedBox(width: 4),
                                                        Text('رجع: $returnedQty', style: const TextStyle(color: Colors.red)),
                                                      ],
                                                    ),
                                                  ),
                                                if (replacementQty > 0)
                                                  Padding(
                                                    padding: const EdgeInsets.only(left: 8.0),
                                                    child: Row(
                                                      children: [
                                                        const Icon(Icons.check_circle, color: Colors.green, size: 18),
                                                        const SizedBox(width: 4),
                                                        Text('بدل: $replacementQty', style: const TextStyle(color: Colors.green)),
                                                      ],
                                                    ),
                                                  ),
                                              ],
                                            ),
                                            subtitle: Text('باركود: $barcode'),
                                            trailing: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              crossAxisAlignment: CrossAxisAlignment.end,
                                              children: [
                                                Text('$qty × ${price.toStringAsFixed(2)}'),
                                                Text(subtotal.toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.bold)),
                                              ],
                                            ),
                                          );
                                        },
                                      ),

                                      // show returns grouped by return action (so replacements that belong to the same return appear under that return)
                                      if (returnsById.isNotEmpty) const Divider(),
                                      ...returnsById.entries.map((entry) {
                                        final rid = entry.key;
                                        final rows = entry.value;
                                        final meta = returnsMeta.firstWhere((rm) => (rm['id'] as num).toInt() == rid, orElse: () => {});
                                        final rDate = (meta['date'] ?? '') as String;
                                        final paidDelta = (meta['paid_delta'] as num?)?.toDouble() ?? 0.0;
                                        final note = (meta['note'] ?? '') as String;

                                        final returnedRows = rows.where((r) => (r['is_replacement'] as num?)?.toInt() == 0).toList();
                                        final replacementRows = rows.where((r) => (r['is_replacement'] as num?)?.toInt() == 1).toList();

                                        return Card(
                                          margin: const EdgeInsets.symmetric(vertical: 6),
                                          color: const Color(0xFFF7F7F7),
                                          child: Padding(
                                            padding: const EdgeInsets.all(8.0),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    const Icon(Icons.repeat, size: 18),
                                                    const SizedBox(width: 8),
                                                    Text('مرتجع/استبدال — ${rDate.split('T').first} ${rDate.contains('T') ? rDate.split('T').last.split('.').first : ''}'),
                                                    const Spacer(),
                                                    if (paidDelta > 0) Text('+${paidDelta.toStringAsFixed(2)}', style: const TextStyle(color: Colors.green)),
                                                    if (paidDelta < 0) Text('${paidDelta.toStringAsFixed(2)}', style: const TextStyle(color: Colors.red)),
                                                  ],
                                                ),
                                                if (note.isNotEmpty) Padding(
                                                  padding: const EdgeInsets.only(top: 4.0),
                                                  child: Text('ملاحظة: $note', style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
                                                ),
                                                const SizedBox(height: 8),
                                                // returned items
                                                if (returnedRows.isNotEmpty) const Text('العناصر المرجوعة:', style: TextStyle(fontWeight: FontWeight.bold)),
                                                ...returnedRows.map((r) {
                                                  final name = (r['product_name'] ?? 'منتج') as String;
                                                  final barcode = (r['product_barcode'] ?? '-') as String;
                                                  final qty = (r['qty'] as num?)?.toInt() ?? 0;
                                                  final price = (r['price'] as num?)?.toDouble() ?? 0.0;
                                                  return Padding(
                                                    padding: const EdgeInsets.symmetric(vertical: 4.0),
                                                    child: Row(
                                                      children: [
                                                        const Icon(Icons.close, color: Colors.red, size: 16),
                                                        const SizedBox(width: 8),
                                                        Expanded(child: Text('$name — رجع: $qty × ${price.toStringAsFixed(2)}')),
                                                        Text((qty * price).toStringAsFixed(2)),
                                                      ],
                                                    ),
                                                  );
                                                }).toList(),

                                                // replacements of this same return (shown under the returned items)
                                                if (replacementRows.isNotEmpty) const Padding(
                                                  padding: EdgeInsets.only(top: 8.0),
                                                  child: Text('البدائل (مقابل المرجوع):', style: TextStyle(fontWeight: FontWeight.bold)),
                                                ),
                                                ...replacementRows.map((r) {
                                                  final name = (r['product_name'] ?? 'منتج') as String;
                                                  final barcode = (r['product_barcode'] ?? '-') as String;
                                                  final qty = (r['qty'] as num?)?.toInt() ?? 0;
                                                  final price = (r['price'] as num?)?.toDouble() ?? 0.0;
                                                  return Padding(
                                                    padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 12.0),
                                                    child: Row(
                                                      children: [
                                                        const Icon(Icons.check_circle, color: Colors.green, size: 16),
                                                        const SizedBox(width: 8),
                                                        Expanded(child: Text('$name — بدل: $qty × ${price.toStringAsFixed(2)}')),
                                                        Text((qty * price).toStringAsFixed(2)),
                                                      ],
                                                    ),
                                                  );
                                                }).toList(),
                                              ],
                                            ),
                                          ),
                                        );
                                      }).toList(),

                                      const Divider(),
                                      // financial summary
                                      const SizedBox(height: 8),
                                      const Text('تفاصيل مالية:', style: TextStyle(fontWeight: FontWeight.bold)),
                                      const SizedBox(height: 6),
                                      Text('الإجمالي الأصلي للفاتورة: ${originalTotal.toStringAsFixed(2)}'),
                                      Text('المدفوع الأصلي: ${originalPaid.toStringAsFixed(2)}'),
                                      const SizedBox(height: 6),
                                      Text('قيمة المرتجع (لِلعميل): ${refundedVal.toStringAsFixed(2)}'),
                                      Text('قيمة البدائل: ${addedVal.toStringAsFixed(2)}'),
                                      Text('صافي (بدل - مرتجع): ${netVal.toStringAsFixed(2)}'),
                                      const SizedBox(height: 6),
                                      Text('مجموع التغير النقدي (paid_delta): ${paidDeltaSum.toStringAsFixed(2)}'),
                                      const SizedBox(height: 6),
                                      Text('الحالة الفعلية بعد المرتجع — إجمالي: ${effectiveTotal.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                                      Text('المدفوع حالياً (بعد التغيرات): ${effectivePaid.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                                      if (effectivePaid >= effectiveTotal)
                                        Text('فكة/الباقي: ${effectiveChange.toStringAsFixed(2)}', style: const TextStyle(color: Colors.green))
                                      else
                                        Text('متبقي على العميل: ${effectiveRemaining.toStringAsFixed(2)}', style: const TextStyle(color: Colors.red)),
                                      const SizedBox(height: 8),

                                      Builder(builder: (_) {
                                        String explanation;
                                        if (netVal > 0) {
                                          explanation = 'البدائل أغلى من المرتجع — العميل يدفع ${netVal.toStringAsFixed(2)} إضافيّاً (قبل احتساب paid_delta).';
                                        } else if (netVal < 0) {
                                          explanation = 'قيمة المرتجع أكبر من البدائل — يجب رد ${(-netVal).toStringAsFixed(2)} للعميل (قبل احتساب paid_delta).';
                                        } else {
                                          explanation = 'قيمة المرتجع تساوي قيمة البدائل — لا يوجد فرق صافي (قبل احتساب paid_delta).';
                                        }

                                        String paidDeltaExplain;
                                        if (paidDeltaSum > 0) {
                                          paidDeltaExplain = 'أثناء العملية، دفع العميل إضافيًّا بمقدار ${paidDeltaSum.toStringAsFixed(2)}.';
                                        } else if (paidDeltaSum < 0) {
                                          paidDeltaExplain = 'أثناء العملية، أعاد الكاشير للعميل مبلغًا مقداره ${(-paidDeltaSum).toStringAsFixed(2)}.';
                                        } else {
                                          paidDeltaExplain = 'لم يحدث أي تحويل نقدي أثناء الإجراء (paid_delta = 0).';
                                        }

                                        return Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(explanation, style: const TextStyle(fontStyle: FontStyle.italic)),
                                            Text(paidDeltaExplain, style: const TextStyle(fontStyle: FontStyle.italic)),
                                            const SizedBox(height: 6),
                                            const Text('ملاحظة: الفاتورة الأصلية لم تُعدّل؛ ما تراه هنا هو أثر عمليات المرتجع المسجلة.'),
                                          ],
                                        );
                                      }),
                                    ],
                                  );
                                }),

                                // actions
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    IconButton(
                                      tooltip: 'طباعة (placeholder)',
                                      onPressed: () {
                                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('طباعة (غير مفعلة)')));
                                      },
                                      icon: const Icon(Icons.print),
                                    ),
                                    const SizedBox(width: 8),
                                    IconButton(
                                      tooltip: 'حذف الفاتورة (تحذير)',
                                      onPressed: () async {
                                        final ok = await showDialog<bool>(
                                          context: context,
                                          builder: (_) => AlertDialog(
                                            title: const Text('حذف الفاتورة'),
                                            content: Text('هل تريد حذف الفاتورة #$saleId ؟ هذا لن يستعيد المخزون تلقائياً.'),
                                            actions: [
                                              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
                                              TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('حذف')),
                                            ],
                                          ),
                                        );
                                        if (ok == true) {
                                          final db = await DBHelper.instance.database;
                                          await db.delete('sale_return_items', where: 'return_id IN (SELECT id FROM sale_returns WHERE sale_id = ?)', whereArgs: [saleId]);
                                          await db.delete('sale_returns', where: 'sale_id = ?', whereArgs: [saleId]);
                                          await db.delete('sale_items', where: 'sale_id = ?', whereArgs: [saleId]);
                                          await db.delete('sales', where: 'id = ?', whereArgs: [saleId]);
                                          await _loadSales();
                                        }
                                      },
                                      icon: const Icon(Icons.delete, color: Colors.red),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
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
