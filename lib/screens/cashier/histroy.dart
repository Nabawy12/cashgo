import 'package:flutter/material.dart';
import 'package:cashgo_supermarket/utils/colors.dart';
import 'package:accordion_widget/accordion_widget.dart';
import '../../services/db/db_helper.dart';
import '../../widgets/Cashier/returndailog.dart';
import '../../widgets/empty_state_card.dart';

class PreviousSalesScreen extends StatefulWidget {
  final String cashierUsername;
  final bool canViewCreditInvoices;
  const PreviousSalesScreen({
    super.key,
    required this.cashierUsername,
    this.canViewCreditInvoices = false,
  });

  @override
  State<PreviousSalesScreen> createState() => _PreviousSalesScreenState();
}

class _PreviousSalesScreenState extends State<PreviousSalesScreen> {
  bool loading = true;
  List<Map<String, dynamic>> sales = [];
  Map<int, List<Map<String, dynamic>>> saleItems = {};
  // NEW: كل صفوف sale_return_items الخاصة بكل فاتورة (مرتجع + بدائل)
  Map<int, List<Map<String, dynamic>>> saleReturnItems = {};
  // NEW: حالة محسوبة لكل فاتورة: isFullyReturned / isPartiallyReturned / hasExchange
  Map<int, Map<String, bool>> saleReturnStatus = {};
  Map<String, List<Map<String, dynamic>>> groupedSales = {};
  DateTime selectedDate = DateTime.now();

  Color get _cardTextColor => Theme.of(context).brightness == Brightness.light
      ? Colors.black87
      : Colors.white;

  Color get _cardLabelColor => Theme.of(context).brightness == Brightness.light
      ? Colors.grey[700]!
      : AppColorsDark.mainTextLight;

  @override
  void initState() {
    super.initState();
    _loadSales(date: selectedDate);
  }

  // ------------------ Load sales and normalize ------------------
  Future<void> _loadSales({DateTime? date}) async {
    setState(() => loading = true);
    try {
      final all = await DBHelper.instance.getAllSales();
      saleItems.clear();
      saleReturnItems.clear();
      saleReturnStatus.clear();
      final filtered = <Map<String, dynamic>>[];
      for (final raw in all) {
        final saleId = (raw['id'] as num).toInt();
        final items = await DBHelper.instance.getSaleItemsBySaleId(saleId);
        saleItems[saleId] = items
            .map((it) => {
          ...it,
          'qty': it['quantity'],
          'product_name': it['product_name'] ?? it['name'] ?? '',
          'barcode': it['product_barcode'] ?? '',
        })
            .toList();

        // NEW: نجيب سجل المرتجع/الاستبدال لهذه الفاتورة ونحسب حالتها
        final returnItems =
        await DBHelper.instance.getSaleReturnItemsForSale(saleId);
        saleReturnItems[saleId] = returnItems;
        saleReturnStatus[saleId] =
            _computeReturnStatus(saleItems[saleId]!, returnItems);

        final status = saleReturnStatus[saleId]!;
        final sale = {
          'id': saleId,
          'invoice_id': saleId.toString(),
          'product_list': saleItems[saleId],
          'total': raw['total'] ?? 0.0,
          'paid_amount': raw['paid_amount'] ?? 0.0,
          'change_amount': raw['change_amount'] ?? 0.0,
          'payment_type': raw['payment_method'] ?? 'cash',
          'cashier_username': raw['cashier_username'] ?? '',
          'is_credit': raw['is_credit'] ?? 0,
          'date': raw['date'] ?? '',
          'updated_at': raw['date'] ?? '',
          'is_canceled': 0,
          'status': '',
          // NEW: النوع بقى محسوب من حالة الأصناف الفعلية مش من is_return القديم
          'type': status['hasExchange'] == true
              ? 'exchange'
              : (status['isFullyReturned'] == true
              ? 'return'
              : (status['isPartiallyReturned'] == true
              ? 'partial_return'
              : 'sale')),
          'parent_invoice_id': raw['return_of_sale_id'],
          'meta': {},
        };
        final isCredit = _isCreditValue(sale['is_credit']) ||
            sale['payment_type'].toString().toLowerCase() == 'credit';
        if (!widget.canViewCreditInvoices && isCredit) continue;
        if (date == null || _matchesDate(sale['date'], date))
          filtered.add(sale);
      }
      final Map<String, List<Map<String, dynamic>>> map = {};
      for (final s in filtered) {
        final cashierName = (s['cashier_username'] ??
            s['username'] ??
            s['cashier'] ??
            s['user'] ??
            'Unknown')
            .toString();
        map.putIfAbsent(cashierName, () => []);
        map[cashierName]!.add(s);
      }

      if (!mounted) return;
      setState(() {
        sales = filtered.cast<Map<String, dynamic>>();
        groupedSales = map;
        loading = false;
      });
    } catch (e, st) {
      debugPrint('Error in _loadSales: $e\n$st');
      if (!mounted) return;
      setState(() => loading = false);
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('خطأ في تحميل الفواتير'),
          content: SingleChildScrollView(child: Text(e.toString())),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('حسناً'))
          ],
        ),
      );
    }
  }

  // NEW: يحسب حالة الفاتورة من الأصناف الفعلية (بدون أي عمود جديد في الداتابيز)
  Map<String, bool> _computeReturnStatus(
      List<Map<String, dynamic>> items,
      List<Map<String, dynamic>> returnItems,
      ) {
    if (items.isEmpty) {
      return {
        'isFullyReturned': false,
        'isPartiallyReturned': false,
        'hasExchange': false,
      };
    }
    bool allFullyReturned = true;
    bool anyReturned = false;
    for (final it in items) {
      final qty = (it['quantity'] as num?)?.toInt() ??
          (it['qty'] as num?)?.toInt() ??
          0;
      final returnedQty = (it['returned_quantity'] as num?)?.toInt() ?? 0;
      if (returnedQty > 0) anyReturned = true;
      if (returnedQty < qty) allFullyReturned = false;
    }
    final hasExchange = returnItems
        .any((r) => ((r['is_replacement'] as num?)?.toInt() ?? 0) == 1);
    return {
      'isFullyReturned': allFullyReturned && anyReturned,
      'isPartiallyReturned': anyReturned && !allFullyReturned,
      'hasExchange': hasExchange,
    };
  }

  // NEW: يجمع صفوف sale_return_items حسب return_id عشان نعرض كل عملية استرجاع/استبدال لوحدها
  Map<int, List<Map<String, dynamic>>> _groupByReturnId(
      List<Map<String, dynamic>> rows) {
    final map = <int, List<Map<String, dynamic>>>{};
    for (final r in rows) {
      final rid = (r['return_id'] as num?)?.toInt() ?? 0;
      map.putIfAbsent(rid, () => []).add(r);
    }
    return map;
  }

  bool _matchesDate(dynamic rawDate, DateTime date) {
    if (rawDate == null) return false;
    final s = rawDate.toString();
    DateTime? dt;
    try {
      dt = DateTime.parse(s);
    } catch (_) {
      final m = RegExp(r'(\d{4})-(\d{2})-(\d{2})').firstMatch(s);
      if (m != null) {
        final y = int.tryParse(m.group(1) ?? '0') ?? 0;
        final mo = int.tryParse(m.group(2) ?? '0') ?? 0;
        final d = int.tryParse(m.group(3) ?? '0') ?? 0;
        dt = DateTime(y, mo, d);
      } else {
        final parts =
        s.split(RegExp(r'[\s/\\\-]')).where((p) => p.isNotEmpty).toList();
        if (parts.length >= 3) {
          if (parts[0].length == 4) {
            final y = int.tryParse(parts[0]) ?? 0;
            final mo = int.tryParse(parts[1]) ?? 0;
            final d = int.tryParse(parts[2]) ?? 0;
            dt = DateTime(y, mo, d);
          } else {
            final d = int.tryParse(parts[0]) ?? 0;
            final mo = int.tryParse(parts[1]) ?? 0;
            final y = int.tryParse(parts[2]) ?? 0;
            dt = DateTime(y, mo, d);
          }
        }
      }
    }
    if (dt == null) return false;
    return dt.year == date.year && dt.month == date.month && dt.day == date.day;
  }

  bool _isCreditValue(dynamic v) {
    if (v == null) return false;
    if (v is bool) return v;
    if (v is num) return v != 0;
    final s = v.toString().trim().toLowerCase();
    return s == '1' || s == 'true' || s == 'yes' || s == 'credit';
  }

  Future<void> _ensureItems(int saleId) async {
    if (saleItems.containsKey(saleId) &&
        (saleItems[saleId]?.isNotEmpty ?? false)) return;
    try {
      saleItems[saleId] = await DBHelper.instance.getSaleItemsBySaleId(saleId);
    } catch (e) {
      debugPrint('Error loading items for $saleId: $e');
      saleItems[saleId] = [];
    }
  }

  // NEW: يتأكد إن سجل المرتجع/الاستبدال والحالة محسوبين لهذه الفاتورة
  Future<void> _ensureReturnData(int saleId) async {
    if (saleReturnItems.containsKey(saleId) &&
        saleReturnStatus.containsKey(saleId)) return;
    try {
      final rows = await DBHelper.instance.getSaleReturnItemsForSale(saleId);
      saleReturnItems[saleId] = rows;
      saleReturnStatus[saleId] =
          _computeReturnStatus(saleItems[saleId] ?? [], rows);
    } catch (e) {
      debugPrint('Error loading return items for $saleId: $e');
      saleReturnItems[saleId] = [];
      saleReturnStatus[saleId] = {
        'isFullyReturned': false,
        'isPartiallyReturned': false,
        'hasExchange': false,
      };
    }
  }

  // NEW: شارة صغيرة توضح حالة الفاتورة
  Widget _statusBadge(Map<String, bool> status) {
    // NEW: الاسترجاع الكامل بقى له الأولوية حتى لو فيه تاريخ استبدال قبل كده
    if (status['isFullyReturned'] == true) {
      return _buildBadge('تم الاسترجاع بالكامل', Colors.redAccent, Icons.cancel);
    }
    if (status['hasExchange'] == true) {
      return _buildBadge('تم الاستبدال', Colors.blueAccent, Icons.swap_horiz);
    }
    if (status['isPartiallyReturned'] == true) {
      return _buildBadge('مرتجع جزئي', Colors.orangeAccent, Icons.undo);
    }
    return const SizedBox.shrink();
  }

  Widget _buildBadge(String label, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  color: color, fontSize: 11, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }


  // NEW: بلوك منفصل لكل صنف في سجل المرتجع/الاستبدال — كل معلومة في سطرها
  Widget _returnItemBlock(Map<String, dynamic> row) {
    final isReplacement =
        ((row['is_replacement'] as num?)?.toInt() ?? 0) == 1;
    final name = (row['product_name'] ?? '').toString();
    final qty = (row['qty'] as num?)?.toInt() ?? 0;
    final color = isReplacement ? Colors.greenAccent : Colors.redAccent;
    final label = isReplacement ? 'بديل' : 'مرتجع';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              isReplacement ? Icons.add_circle_outline : Icons.remove_circle_outline,
              size: 14,
              color: color,
            ),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    color: color, fontSize: 12, fontWeight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: 4),
        Text(name,
            style: TextStyle(
                color: _cardTextColor,
                fontSize: 14,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text('الكمية: $qty',
            style: TextStyle(color: _cardLabelColor, fontSize: 12)),
      ],
    );
  }

  void _openSaleDetails(Map<String, dynamic> sale) async {
    final saleId = (sale['id'] as num).toInt();
    await _ensureItems(saleId);
    await _ensureReturnData(saleId); // NEW

    final actorCashier = widget.cashierUsername.toString();
    final originalCashier = (sale['cashier_username'] ?? '').toString();

    final status = saleReturnStatus[saleId] ??
        {
          'isFullyReturned': false,
          'isPartiallyReturned': false,
          'hasExchange': false,
        };
    final isFullyReturned = status['isFullyReturned'] == true;
    final returnRows = saleReturnItems[saleId] ?? [];
    final groupedReturns = _groupByReturnId(returnRows);

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColorsDark.bgCardColor,
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('#فاتورة رقم : $saleId',
                style: TextStyle(fontSize: 18, color: _cardTextColor)),
            Text(actorCashier,
                style: TextStyle(fontSize: 13, color: _cardLabelColor)),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // NEW: شارة حالة الفاتورة أعلى التفاصيل
                if (status['isFullyReturned'] == true ||
                    status['isPartiallyReturned'] == true ||
                    status['hasExchange'] == true) ...[
                  Align(
                    alignment: Alignment.centerRight,
                    child: _statusBadge(status),
                  ),
                  const SizedBox(height: 10),
                ],
                Text('الإجمالي: ${(sale['total'] as num?)?.toDouble() ?? 0.0}',
                    style: TextStyle(color: _cardTextColor)),
                const SizedBox(height: 8),
                Text(
                    'المدفوع: ${(sale['paid_amount'] as num?)?.toDouble() ?? 0.0}',
                    style: TextStyle(color: _cardLabelColor)),
                const SizedBox(height: 12),
                Text(':العناصر', style: TextStyle(color: _cardTextColor)),
                const SizedBox(height: 8),
                Builder(builder: (_) {
                  final items = saleItems[saleId] ?? [];
                  if (items.isEmpty)
                    return const EmptyStateCard(
                      icon: Icons.inventory_2_outlined,
                      title: 'لا توجد عناصر',
                      message: 'لا توجد عناصر معروضة لهذه الفاتورة.',
                      margin: EdgeInsets.zero,
                    );
                  return SizedBox(
                    height: 220,
                    child: ListView.builder(
                      shrinkWrap: true,
                      physics: const ClampingScrollPhysics(),
                      itemCount: items.length,
                      itemBuilder: (_, i) {
                        final it = items[i];
                        final name = (it['product_name'] ??
                            it['name'] ??
                            it['product'] ??
                            'Product')
                            .toString();
                        final qty = (it['qty'] as num?)?.toInt() ??
                            (it['quantity'] as num?)?.toInt() ??
                            (it['count'] as num?)?.toInt() ??
                            0;
                        final returnedQty =
                            (it['returned_quantity'] as num?)?.toInt() ?? 0;
                        final price = (it['price'] as num?)?.toDouble() ?? 0.0;
                        final itemFullyReturned =
                            qty > 0 && returnedQty >= qty;
                        final itemPartiallyReturned =
                            returnedQty > 0 && returnedQty < qty;

                        return ListTile(
                          title: Text(
                            name,
                            style: TextStyle(
                              color: itemFullyReturned
                                  ? _cardLabelColor
                                  : _cardTextColor,
                              decoration: itemFullyReturned
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                          subtitle: Text(
                            itemPartiallyReturned
                                ? 'الكمية: $qty × ${price.toStringAsFixed(2)} — متبقي بعد المرتجع: ${qty - returnedQty}'
                                : 'الكمية: $qty × ${price.toStringAsFixed(2)}',
                            style: TextStyle(color: _cardLabelColor),
                          ),
                          trailing: itemFullyReturned
                              ? const Icon(Icons.cancel,
                              color: Colors.redAccent, size: 18)
                              : (itemPartiallyReturned
                              ? const Icon(Icons.undo,
                              color: Colors.orangeAccent, size: 18)
                              : null),
                        );
                      },
                    ),
                  );
                }),
                // NEW: سجل المرتجع/الاستبدال — كل عملية على حدة
// NEW: سجل المرتجع/الاستبدال — كل عملية على حدة
                if (groupedReturns.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(':سجل المرتجع / الاستبدال',
                      style: TextStyle(color: _cardTextColor)),
                  const SizedBox(height: 8),
                  ...groupedReturns.entries.map((entry) {
                    final rows = entry.value;
                    final date = (rows.first['return_date'] ?? '').toString();

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.03),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (date.isNotEmpty) ...[
                            Text(_formatDayMonth(date),
                                style: TextStyle(fontSize: 11, color: _cardLabelColor)),
                            const SizedBox(height: 6),
                          ],
                          for (int i = 0; i < rows.length; i++) ...[
                            _returnItemBlock(rows[i]),
                            if (i != rows.length - 1) ...[
                              const SizedBox(height: 8),
                              Divider(color: Colors.white12, height: 1),
                              const SizedBox(height: 8),
                            ],
                          ],
                        ],
                      ),
                    );
                  }),
                ],              ],

            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('إغلاق',
                  style: TextStyle(
                      color: Theme.of(context).brightness == Brightness.light
                          ? Colors.black
                          : Colors.white))),
          // NEW: لو الفاتورة اتسترجعت بالكامل، ما نعرضش زرار المعالجة خالص
          if (!isFullyReturned)
            TextButton(
              onPressed: () async {
                if (Navigator.canPop(context)) Navigator.pop(context);
                await _showProcessReturnDialog(saleId, actorCashier);
              },
              child: Text('معالجة مرتجع / بدل',
                  style: TextStyle(
                      color: Theme.of(context).brightness == Brightness.light
                          ? Colors.black
                          : Colors.white)),
            ),
        ],
      ),
    );
  }

  Future<void> _showProcessReturnDialog(
      int originalSaleId, String cashierName) async {
    await _ensureItems(originalSaleId);
    final items = (saleItems[originalSaleId] ?? []).where((item) {
      final qty = (item['quantity'] as num?)?.toInt() ??
          (item['qty'] as num?)?.toInt() ??
          0;
      final returnedQty = (item['returned_quantity'] as num?)?.toInt() ?? 0;
      return qty - returnedQty > 0;
    }).map((item) {
      final qty = (item['quantity'] as num?)?.toInt() ??
          (item['qty'] as num?)?.toInt() ??
          0;
      final returnedQty = (item['returned_quantity'] as num?)?.toInt() ?? 0;
      return {
        ...item,
        'original_quantity': qty,
        'quantity': qty - returnedQty,
        'qty': qty - returnedQty,
      };
    }).toList();

    if (items.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Directionality(
            textDirection: TextDirection.rtl,
            child: Text('كل عناصر هذه الفاتورة تم استرجاعها بالفعل'),
          ),
        ),
      );
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: AppColorsDark.bgColor,
          appBar: AppBar(
            title: Text('معالجة مرتجع / بدل',
                style: TextStyle(color: AppColorsDark.mainTextDark)),
            backgroundColor: Colors.transparent,
            elevation: 0,
            iconTheme: IconThemeData(color: Theme.of(context).iconTheme.color),
          ),
          body: SafeArea(
            child: ProcessReturnDialog(
              originalSaleId: originalSaleId,
              items: items,
              cashierUsername: cashierName,
              onDone: () async {
                await _loadSales(date: selectedDate);
                await _ensureItems(originalSaleId);
                await _ensureReturnData(originalSaleId); // NEW
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Directionality(
                        textDirection: TextDirection.rtl,
                        child: Text('تم تحديث الفواتير'),
                      ),
                    ),
                  );
                }
              },
            ),
          ),
        ),
        fullscreenDialog: true,
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
        context: context,
        initialDate: selectedDate,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100));
    if (picked != null) {
      setState(() => selectedDate = picked);
      await _loadSales(date: selectedDate);
    }
  }

  String _formatDayMonth(dynamic rawDate) {
    if (rawDate == null) return '';
    final s = rawDate.toString();
    try {
      final dt = DateTime.parse(s);
      return '${dt.day}/${dt.month}';
    } catch (_) {
      final m = RegExp(r'(\d{4})-(\d{2})-(\d{2})').firstMatch(s);
      if (m != null)
        return '${int.parse(m.group(3)!)}/${int.parse(m.group(2)!)}';
      return s;
    }
  }

  String _formatSelectedDate(DateTime dt) => '${dt.day}/${dt.month}/${dt.year}';

  Widget _buildLoadingState() {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppColorsDark.mainColor),
            const SizedBox(height: 16),
            Text(
              'جاري تحميل الفواتير من قاعدة البيانات المحلية...',
              style: TextStyle(color: AppColorsDark.mainTextDark, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSalesList() {
    if (groupedSales.isEmpty) {
      return const Center(
        child: EmptyStateCard(
          icon: Icons.receipt_long,
          title: 'لا توجد فواتير',
          message: 'لا توجد فواتير مسجلة في هذا التاريخ.',
        ),
      );
    }

    return ListView(
      children: groupedSales.entries.map((entry) {
        final cashierName = entry.key;
        final list = entry.value;

        return Directionality(
          textDirection: TextDirection.rtl,
          child: Padding(
            padding:
            const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
            child: Card(
              color: AppColorsDark.bgCardColor,
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: AccordionWidget(
                  showIcon: false,
                  decoration: const BoxDecoration(color: Colors.transparent),
                  header: AbsorbPointer(
                    absorbing: true,
                    child: Text(
                      '$cashierName (${list.length})',
                      style: TextStyle(color: _cardTextColor, fontSize: 20),
                    ),
                  ),
                  content: Column(
                    children: list.map((s) {
                      final saleId = (s['id'] as num).toInt();
                      final total = (s['total'] as num?)?.toDouble() ?? 0.0;
                      final paid =
                          (s['paid_amount'] as num?)?.toDouble() ?? 0.0;
                      final dayMonth = _formatDayMonth(s['date']);
                      // NEW: حالة الفاتورة المحسوبة فعليًا من الأصناف
                      final status = saleReturnStatus[saleId] ??
                          {
                            'isFullyReturned': false,
                            'isPartiallyReturned': false,
                            'hasExchange': false,
                          };

                      return Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Theme(
                          data: Theme.of(context).copyWith(
                              hoverColor:
                              AppColorsDark.mainColor.withOpacity(0.1)),
                          child: ListTile(
                            selectedColor:
                            AppColorsDark.mainColor.withOpacity(0.1),
                            splashColor:
                            AppColorsDark.mainColor.withOpacity(0.1),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            onTap: () => _openSaleDetails(s),
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '#$saleId — $dayMonth',
                                    style: TextStyle(color: _cardTextColor),
                                  ),
                                ),
                                _statusBadge(status), // NEW
                              ],
                            ),
                            subtitle: Text(
                              'الإجمالي: ${total.toStringAsFixed(2)} — المدفوع: ${paid.toStringAsFixed(2)}',
                              style: TextStyle(color: _cardLabelColor),
                            ),
                            trailing: Icon(
                              Icons.arrow_forward_ios,
                              size: 16,
                              color: Theme.of(context).iconTheme.color,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  padding:
                  const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColorsDark.bgColor,
      appBar: AppBar(
        title: Text('الفواتير السابقة',
            style: TextStyle(color: AppColorsDark.mainTextDark)),
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            onPressed: () async => await _loadSales(date: selectedDate),
            icon: Icon(Icons.refresh, color: Theme.of(context).iconTheme.color),
          ),
        ],
        iconTheme: IconThemeData(color: Theme.of(context).iconTheme.color),
      ),
      body: loading
          ? _buildLoadingState()
          : Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12.0),
            child: GestureDetector(
              onTap: _pickDate,
              child: Column(
                children: [
                  Text('التاريخ',
                      style:
                      TextStyle(color: AppColorsDark.mainTextLight)),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_formatSelectedDate(selectedDate),
                          style: TextStyle(
                              color: AppColorsDark.mainTextDark)),
                      const SizedBox(width: 8),
                      Icon(Icons.calendar_today,
                          size: 18,
                          color: Theme.of(context).iconTheme.color),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Expanded(child: _buildSalesList()),
        ],
      ),
    );
  }
}