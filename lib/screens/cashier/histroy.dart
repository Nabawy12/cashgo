import 'package:flutter/material.dart';
import 'package:cashgo/utils/colors.dart';
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
  Map<int, List<Map<String, dynamic>>> saleReturnItems = {};
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

  // ─── status logic ────────────────────────────────────────────────────────────

  /// 'none' | 'partial_return' | 'fully_returned' | 'exchange' | 'exchange_with_return'
  String _getSaleStatus(int saleId) {
    final returnItems = saleReturnItems[saleId] ?? [];
    if (returnItems.isEmpty) return 'none';

    final hasReturn =
        returnItems.any((i) => (i['is_replacement'] as num?)?.toInt() == 0);
    final hasReplacement =
        returnItems.any((i) => (i['is_replacement'] as num?)?.toInt() == 1);

    if (hasReplacement && hasReturn) return 'exchange_with_return';
    if (hasReplacement) return 'exchange';

    if (hasReturn) {
      // check if ALL items fully returned
      final items = saleItems[saleId] ?? [];
      final allReturned = items.isNotEmpty &&
          items.every((item) {
            final qty = (item['quantity'] as num?)?.toInt() ?? 0;
            final returned = (item['returned_quantity'] as num?)?.toInt() ?? 0;
            return qty > 0 && returned >= qty;
          });
      return allReturned ? 'fully_returned' : 'partial_return';
    }

    return 'none';
  }

  // ── per-status UI values ─────────────────────────────────────────────────────

  Color? _tileBgColor(String status) {
    switch (status) {
      case 'fully_returned':
        return Colors.red.withOpacity(0.07);
      case 'partial_return':
        return Colors.orange.withOpacity(0.06);
      case 'exchange':
        return Colors.green.withOpacity(0.06);
      case 'exchange_with_return':
        return Colors.orange.withOpacity(0.06);
      default:
        return null;
    }
  }

  Widget _statusIcon(String status) {
    switch (status) {
      case 'fully_returned':
        return const Icon(Icons.cancel, color: Colors.red, size: 23);
      case 'partial_return':
        return const Icon(Icons.assignment_return,
            color: Colors.orange, size: 23);
      case 'exchange':
        return const Icon(Icons.swap_horiz, color: Colors.green, size: 23);
      case 'exchange_with_return':
        return const Icon(Icons.sync, color: Colors.orange, size: 23);
      default:
        return const SizedBox.shrink();
    }
  }

  Color _statusLabelColor(String status) {
    switch (status) {
      case 'fully_returned':
        return Colors.red[300]!;
      case 'partial_return':
        return Colors.orange[300]!;
      case 'exchange':
        return Colors.green[300]!;
      case 'exchange_with_return':
        return Colors.orange[300]!;
      default:
        return _cardLabelColor;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'fully_returned':
        return 'تم الاسترجاع الكامل';
      case 'partial_return':
        return 'استرجاع جزئي';
      case 'exchange':
        return 'تم الاستبدال';
      case 'exchange_with_return':
        return 'استبدال مع استرجاع';
      default:
        return '';
    }
  }

  // ─── helpers ─────────────────────────────────────────────────────────────────

  String _formatTime12h(dynamic rawDate) {
    if (rawDate == null) return '';
    try {
      final dt = DateTime.parse(rawDate.toString());
      int hour = dt.hour;
      final minute = dt.minute.toString().padLeft(2, '0');
      final period = hour >= 12 ? 'م' : 'ص';
      hour = hour % 12;
      if (hour == 0) hour = 12;
      return '$hour:$minute $period';
    } catch (_) {
      return '';
    }
  }

  // ─── load ────────────────────────────────────────────────────────────────────

  Future<void> _loadSales({DateTime? date}) async {
    setState(() => loading = true);
    try {
      final all = await DBHelper.instance.getAllSales();
      saleItems.clear();
      saleReturnItems.clear();
      final filtered = <Map<String, dynamic>>[];

      for (final raw in all) {
        final saleId = (raw['id'] as num).toInt();
        final items = await DBHelper.instance.getSaleItemsBySaleId(saleId);
        final returnItems =
            await DBHelper.instance.getSaleReturnItemsForSale(saleId);

        saleItems[saleId] = items
            .map((it) => {
                  ...it,
                  'qty': it['quantity'],
                  'product_name': it['product_name'] ?? it['name'] ?? '',
                  'barcode': it['product_barcode'] ?? '',
                })
            .toList();

        saleReturnItems[saleId] =
            returnItems.map((it) => Map<String, dynamic>.from(it)).toList();

        final sale = {
          'id': saleId,
          'invoice_id': saleId.toString(),
          'product_list': saleItems[saleId],
          'total': raw['total'] ?? 0.0,
          'paid_amount': raw['paid_amount'] ?? 0.0,
          'change_amount': raw['change_amount'] ?? 0.0,
          'payment_type': raw['payment_method'] ?? 'cash',
          'cashier_username': raw['cashier_username'] ?? '',
          'customer_name': raw['customer_name'] ?? '',
          'customer_phone': raw['customer_phone'] ?? '',
          'is_credit': raw['is_credit'] ?? 0,
          'date': raw['date'] ?? '',
          'updated_at': raw['date'] ?? '',
          'is_canceled': 0,
          'status': '',
          'type': raw['is_return'] == 1 && raw['return_of_sale_id'] != null
              ? 'return'
              : 'sale',
          'parent_invoice_id': raw['return_of_sale_id'],
          'return_note': raw['return_note'] ?? '',
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

  bool _matchesDate(dynamic rawDate, DateTime date) {
    if (rawDate == null) return false;
    final s = rawDate.toString();
    DateTime? dt;
    try {
      dt = DateTime.parse(s);
    } catch (_) {
      final m = RegExp(r'(\d{4})-(\d{2})-(\d{2})').firstMatch(s);
      if (m != null) {
        dt = DateTime(
          int.tryParse(m.group(1) ?? '0') ?? 0,
          int.tryParse(m.group(2) ?? '0') ?? 0,
          int.tryParse(m.group(3) ?? '0') ?? 0,
        );
      } else {
        final parts =
            s.split(RegExp(r'[\s/\\\-]')).where((p) => p.isNotEmpty).toList();
        if (parts.length >= 3) {
          if (parts[0].length == 4) {
            dt = DateTime(int.tryParse(parts[0]) ?? 0,
                int.tryParse(parts[1]) ?? 0, int.tryParse(parts[2]) ?? 0);
          } else {
            dt = DateTime(int.tryParse(parts[2]) ?? 0,
                int.tryParse(parts[1]) ?? 0, int.tryParse(parts[0]) ?? 0);
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

  // ─── dialogs ─────────────────────────────────────────────────────────────────

  void _openSaleDetails(Map<String, dynamic> sale) async {
    final saleId = (sale['id'] as num).toInt();
    await _ensureItems(saleId);

    final actorCashier = widget.cashierUsername.toString();
    final returnItems = saleReturnItems[saleId] ?? [];
    final returned = returnItems
        .where((i) => (i['is_replacement'] as num?)?.toInt() == 0)
        .toList();
    final replacements = returnItems
        .where((i) => (i['is_replacement'] as num?)?.toInt() == 1)
        .toList();

    // map: product_id → total returned qty
    final Map<int, int> returnedQtyMap = {};
    for (final r in returned) {
      final pid = (r['product_id'] as num?)?.toInt() ?? 0;
      returnedQtyMap[pid] =
          (returnedQtyMap[pid] ?? 0) + ((r['qty'] as num?)?.toInt() ?? 0);
    }

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColorsDark.bgCardColor,
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('#فاتورة رقم : $saleId',
                style: TextStyle(fontSize: 21, color: _cardTextColor)),
            Text(actorCashier,
                style: TextStyle(fontSize: 16, color: _cardLabelColor)),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // totals
                Text('الإجمالي: ${(sale['total'] as num?)?.toDouble() ?? 0.0}',
                    style: TextStyle(color: _cardTextColor, fontSize: 17)),
                const SizedBox(height: 4),
                Text(
                    'المدفوع: ${(sale['paid_amount'] as num?)?.toDouble() ?? 0.0}',
                    style: TextStyle(color: _cardLabelColor, fontSize: 16)),

                // customer
                Builder(builder: (_) {
                  final customerName =
                      (sale['customer_name'] ?? '').toString().trim();
                  final customerPhone =
                      (sale['customer_phone'] ?? '').toString().trim();
                  final label = customerName.isNotEmpty
                      ? customerName
                      : customerPhone.isNotEmpty
                          ? customerPhone
                          : null;
                  if (label == null) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(children: [
                      Icon(Icons.person_outline,
                          size: 17, color: AppColorsDark.mainColor),
                      const SizedBox(width: 4),
                      Text('العميل: $label',
                          style: TextStyle(
                              color: AppColorsDark.mainColor, fontSize: 16)),
                    ]),
                  );
                }),

                const SizedBox(height: 12),

                // sale items
                Text(':العناصر',
                    style: TextStyle(color: _cardTextColor, fontSize: 17)),
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
                  return ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
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
                          0;
                      final price = (it['price'] as num?)?.toDouble() ?? 0.0;
                      final pid = (it['product_id'] as num?)?.toInt() ?? 0;
                      final retQty = returnedQtyMap[pid] ??
                          (it['returned_quantity'] as num?)?.toInt() ??
                          0;
                      final fullyRet = retQty >= qty && qty > 0;
                      final partialRet = retQty > 0 && !fullyRet;

                      return ListTile(
                        dense: true,
                        title: Text(name,
                            style: TextStyle(
                              color:
                                  fullyRet ? Colors.red[300] : _cardTextColor,
                              decoration:
                                  fullyRet ? TextDecoration.lineThrough : null,
                              fontSize: 16,
                            )),
                        subtitle: Text(
                          'الكمية: $qty × ${price.toStringAsFixed(2)}'
                          '${fullyRet ? " — تم الاسترجاع" : partialRet ? " — مرتجع: $retQty" : ""}',
                          style:
                              TextStyle(color: _cardLabelColor, fontSize: 14),
                        ),
                        trailing: fullyRet
                            ? const Icon(Icons.cancel,
                                color: Colors.red, size: 19)
                            : partialRet
                                ? Icon(Icons.remove_circle_outline,
                                    color: Colors.orange[300], size: 19)
                                : null,
                      );
                    },
                  );
                }),

                // return + exchange sections
                if (returned.isNotEmpty || replacements.isNotEmpty) ...[
                  const Divider(height: 24),
                  if (returned.isNotEmpty) ...[
                    Row(children: [
                      const Icon(Icons.assignment_return,
                          color: Colors.orange, size: 19),
                      const SizedBox(width: 6),
                      Text('المرتجعات:',
                          style: TextStyle(
                              color: Colors.orange[300],
                              fontWeight: FontWeight.bold,
                              fontSize: 16)),
                    ]),
                    const SizedBox(height: 4),
                    ...returned.map((r) => ListTile(
                          dense: true,
                          leading: const Icon(Icons.cancel,
                              color: Colors.red, size: 21),
                          title: Text((r['product_name'] ?? '').toString(),
                              style: TextStyle(
                                  color: _cardTextColor, fontSize: 16)),
                          subtitle: Text('كمية مرتجعة: ${r['qty']}',
                              style: TextStyle(
                                  color: _cardLabelColor, fontSize: 14)),
                        )),
                  ],
                  if (replacements.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: Colors.green.withOpacity(0.3), width: 1),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            const Icon(Icons.swap_horiz,
                                color: Colors.green, size: 19),
                            const SizedBox(width: 6),
                            Text('منتجات الاستبدال:',
                                style: TextStyle(
                                    color: Colors.green[300],
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16)),
                          ]),
                          const SizedBox(height: 4),
                          ...replacements.map((r) => Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 3),
                                child: Row(children: [
                                  const Icon(Icons.arrow_left,
                                      color: Colors.green, size: 18),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      '${r['product_name'] ?? ''} — كمية: ${r['qty']}',
                                      style: TextStyle(
                                          color: _cardTextColor, fontSize: 15),
                                    ),
                                  ),
                                ]),
                              )),
                        ],
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('إغلاق',
                  style: TextStyle(
                      fontSize: 16,
                      color: Theme.of(context).brightness == Brightness.light
                          ? Colors.black
                          : Colors.white))),
          TextButton(
            onPressed: () async {
              if (Navigator.canPop(context)) Navigator.pop(context);
              await _showProcessReturnDialog(saleId, actorCashier);
            },
            child: Text('معالجة مرتجع / بدل',
                style: TextStyle(
                    fontSize: 16,
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

  // ─── date picker ─────────────────────────────────────────────────────────────

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

  // ─── build ───────────────────────────────────────────────────────────────────

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
              style: TextStyle(color: AppColorsDark.mainTextDark, fontSize: 19),
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
                      style: TextStyle(color: _cardTextColor, fontSize: 23),
                    ),
                  ),
                  content: Column(
                    children: list.map((s) {
                      final saleId = (s['id'] as num).toInt();
                      final total = (s['total'] as num?)?.toDouble() ?? 0.0;
                      final paid =
                          (s['paid_amount'] as num?)?.toDouble() ?? 0.0;
                      final dayMonth = _formatDayMonth(s['date']);
                      final timeStr = _formatTime12h(s['date']);

                      final status = _getSaleStatus(saleId);
                      final isDisabled = status == 'fully_returned';

                      final customerName =
                          (s['customer_name'] ?? '').toString().trim();
                      final customerPhone =
                          (s['customer_phone'] ?? '').toString().trim();
                      final customerLabel = customerName.isNotEmpty
                          ? customerName
                          : customerPhone.isNotEmpty
                              ? customerPhone
                              : null;

                      final statusLabel = _statusLabel(status);
                      final statusColor = _statusLabelColor(status);

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
                            tileColor: _tileBgColor(status),
                            onTap:
                                isDisabled ? null : () => _openSaleDetails(s),
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '#$saleId — $dayMonth',
                                    style: TextStyle(
                                      fontSize: 19,
                                      color: isDisabled
                                          ? Colors.red[300]
                                          : _cardTextColor,
                                      decoration: isDisabled
                                          ? TextDecoration.lineThrough
                                          : null,
                                    ),
                                  ),
                                ),
                                _statusIcon(status),
                              ],
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'الإجمالي: ${total.toStringAsFixed(2)} — المدفوع: ${paid.toStringAsFixed(2)}',
                                  style: TextStyle(
                                      color: _cardLabelColor, fontSize: 16),
                                ),
                                if (customerLabel != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Row(children: [
                                      Icon(Icons.person_outline,
                                          size: 15,
                                          color: AppColorsDark.mainColor),
                                      const SizedBox(width: 3),
                                      Text(customerLabel,
                                          style: TextStyle(
                                              color: AppColorsDark.mainColor,
                                              fontSize: 14)),
                                    ]),
                                  ),
                                if (timeStr.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Row(children: [
                                      Icon(Icons.access_time,
                                          size: 15, color: _cardLabelColor),
                                      const SizedBox(width: 3),
                                      Text(timeStr,
                                          style: TextStyle(
                                              color: _cardLabelColor,
                                              fontSize: 14)),
                                    ]),
                                  ),
                                if (statusLabel.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(statusLabel,
                                        style: TextStyle(
                                            color: statusColor,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500)),
                                  ),
                              ],
                            ),
                            // عادي → arrow | مرتجع كامل → لا شيء | باقي الحالات → icon الحالة
                            trailing: isDisabled
                                ? null
                                : status == 'none'
                                    ? Icon(Icons.arrow_forward_ios,
                                        size: 19,
                                        color:
                                            Theme.of(context).iconTheme.color)
                                    : null,
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
            style: TextStyle(color: AppColorsDark.mainTextDark, fontSize: 23)),
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
                            style: TextStyle(
                                color: AppColorsDark.mainTextLight,
                                fontSize: 16)),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(_formatSelectedDate(selectedDate),
                                style: TextStyle(
                                    color: AppColorsDark.mainTextDark,
                                    fontSize: 19)),
                            const SizedBox(width: 8),
                            Icon(Icons.calendar_today,
                                size: 21,
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
