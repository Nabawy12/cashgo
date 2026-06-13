// lib/screens/receipts_screen.dart
import 'package:accordion_widget/Accordion_Widget.dart';
import 'package:cashgo/utils/colors.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../services/db/db_helper.dart';
import '../../widgets/Loading/Admin/invoice_cash.dart';
import '../../widgets/empty_state_card.dart';

class receiptsScreen extends StatefulWidget {
  final String initialFilter;
  static const routeName = '/receipts';
  const receiptsScreen({Key? key, this.initialFilter = 'all'})
      : super(key: key);

  @override
  State<receiptsScreen> createState() => _receiptsScreenState();
}

class _receiptsScreenState extends State<receiptsScreen> {
  bool loading = true;
  List<Map<String, dynamic>> sales = [];
  Map<String, List<Map<String, dynamic>>> groupedByDate = {};
  final Map<int, List<Map<String, dynamic>>> saleItemsCache = {};
  final Set<int> loadingSaleReturnItems = {};
  final Set<int> loadingSaleItems = {};
  final Set<int> loadingSaleReturns = {};
  Map<String, dynamic>? _currentUser;
  final Map<int, List<Map<String, dynamic>>> saleReturnItemsCache = {};
  final Map<int, List<Map<String, dynamic>>> saleReturnsCache = {};
  String _activeFilter = 'all';
  DateTime selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _activeFilter = widget.initialFilter;
    _loadSales(date: selectedDate);
    // current user not available from local DB here; keep null (or implement API call if you have one)
  }

  /// Try to parse full DateTime string, fallback to date-only parse, fallback to epoch.
  DateTime _parseDateTimeString(String raw) {
    if (raw.isEmpty) return DateTime.fromMillisecondsSinceEpoch(0);
    try {
      // try full ISO or any DateTime.parse compatible string
      return DateTime.parse(raw);
    } catch (_) {
      // fallback to date-only parser you already have
      final dt = _parseDateOnly(raw);
      if (dt != null) return dt;
      // last resort: return epoch so unknown dates sort to the end
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
  }

  // ------------------ Fetch all invoices from API and normalize ------------------
  Future<void> _loadSales({DateTime? date}) async {
    if (mounted) setState(() => loading = true);

    try {
      final rows = await DBHelper.instance.getAllSales();
      sales = rows.where((s) {
        if (_isCreditValue(s['is_credit'])) return false;
        if (date == null) return true;
        final dt = _parseDateOnly((s['date'] ?? '').toString());
        return dt != null &&
            dt.year == date.year &&
            dt.month == date.month &&
            dt.day == date.day;
      }).map((s) {
        return {
          'id': s['id'],
          'invoice_id': s['id'].toString(),
          'product_list': null,
          'total': s['total'] ?? 0.0,
          'paid_amount': s['paid_amount'] ?? 0.0,
          'change_amount': s['change_amount'] ?? 0.0,
          'payment_type': s['payment_method'] ?? 'cash',
          'cashier_username': s['cashier_username'] ?? '',
          'date': s['date'] ?? '',
          'updated_at': s['date'] ?? '',
          'is_canceled': 0,
          'status': '',
          'type': s['is_return'] == 1 ? 'return' : 'sale',
          'parent_invoice_id': s['return_of_sale_id'],
          'meta': {},
          'is_credit_flag': s['is_credit'],
          'discount_type': s['discount_type'] ?? 'fixed',
          'discount_value': s['discount_value'] ?? 0.0,
          'customer_name': s['customer_name'] ?? '',
          'customer_phone': s['customer_phone'] ?? '',
          'loyalty_discount': s['loyalty_discount'] ?? 0.0,
        };
      }).toList();

      sales.sort((a, b) {
        final String aDateRaw = (a['date'] ?? '').toString();
        final String bDateRaw = (b['date'] ?? '').toString();
        final DateTime aDt = _parseDateTimeString(aDateRaw);
        final DateTime bDt = _parseDateTimeString(bDateRaw);
        // descending: most recent first
        return bDt.compareTo(aDt);
      });

      // clear caches
      saleItemsCache.clear();
      saleReturnItemsCache.clear();
      saleReturnsCache.clear();

      // Pre-fetch items for each top-level sale (chunked)
      final saleIds = sales.map((s) => (s['id'] as num).toInt()).toList();
      const int chunkSize = 12;
      for (int i = 0; i < saleIds.length; i += chunkSize) {
        final end =
            (i + chunkSize < saleIds.length) ? i + chunkSize : saleIds.length;
        final chunk = saleIds.sublist(i, end);

        await Future.wait(chunk.map((saleId) async {
          try {
            final items = await _fetchInvoiceItems(saleId);
            saleItemsCache[saleId] = items;
          } catch (e) {
            debugPrint('Error fetching items for sale $saleId: $e');
            saleItemsCache[saleId] = [];
          }
        }));

        if (mounted) setState(() {});
      }

      // group by date and done
      _groupSalesByDate();

      if (mounted) setState(() => loading = false);
    } catch (e, st) {
      debugPrint('Error in _loadSales: $e\n$st');
      if (mounted) setState(() => loading = false);
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> _fetchInvoiceItems(int saleId) async {
    final rows = await DBHelper.instance.getSaleItemsBySaleId(saleId);
    return rows
        .map((r) => {
              'product_id': r['product_id'],
              'id': r['id'],
              'product_name': r['product_name'] ?? '',
              'barcode': r['product_barcode'] ?? '',
              'price': r['price'] ?? 0.0,
              'quantity': r['quantity'] ?? 0,
              'returned': r['returned'] ?? 0,
              'returned_quantity': r['returned_quantity'] ?? 0,
            })
        .toList();
  }

  DateTime? _parseDateOnly(String raw) {
    if (raw.isEmpty) return null;
    try {
      final dt = DateTime.parse(raw);
      return DateTime(dt.year, dt.month, dt.day);
    } catch (_) {
      final m = RegExp(r'(\d{4})-(\d{2})-(\d{2})').firstMatch(raw);
      if (m != null) {
        final y = int.tryParse(m.group(1) ?? '') ?? 0;
        final mo = int.tryParse(m.group(2) ?? '') ?? 0;
        final d = int.tryParse(m.group(3) ?? '') ?? 0;
        if (y > 0 && mo > 0 && d > 0) return DateTime(y, mo, d);
      }
      final parts =
          raw.split(RegExp(r'[\s/\\\-]')).where((p) => p.isNotEmpty).toList();
      if (parts.length >= 3) {
        if (parts[0].length == 4) {
          final y = int.tryParse(parts[0]) ?? 0;
          final mo = int.tryParse(parts[1]) ?? 0;
          final d = int.tryParse(parts[2]) ?? 0;
          if (y > 0 && mo > 0 && d > 0) return DateTime(y, mo, d);
        } else {
          final d = int.tryParse(parts[0]) ?? 0;
          final mo = int.tryParse(parts[1]) ?? 0;
          final y = int.tryParse(parts[2]) ?? 0;
          if (y > 0 && mo > 0 && d > 0) return DateTime(y, mo, d);
        }
      }
    }
    return null;
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

  String _formatTime(String isoString) {
    try {
      final dt = DateTime.parse(isoString);
      int hour = dt.hour;
      final mm = dt.minute.toString().padLeft(2, '0');
      final ss = dt.second.toString().padLeft(2, '0');

      final suffix = hour >= 12 ? "م" : "ص";
      hour = hour % 12;
      if (hour == 0) hour = 12;

      return '$hour:$mm:$ss $suffix';
    } catch (_) {
      return isoString;
    }
  }

  bool _isCreditValue(dynamic v) {
    if (v == null) return false;
    if (v is int) return v == 1;
    if (v is bool) return v == true;
    if (v is String) {
      final s = v.trim().toLowerCase();
      return s == '1' || s == 'true' || s == 'yes';
    }
    return false;
  }

  bool _matchesPaymentFilter(Map<String, dynamic> s) {
    if (_activeFilter == 'all') return true;
    final pmRaw =
        (s['payment_type'] ?? s['paymentMethod'] ?? s['return_note'] ?? '')
            .toString()
            .toLowerCase();
    final isCard = pmRaw.contains('wallet') ||
        pmRaw.contains('كارت') ||
        pmRaw.contains('كرديت') ||
        pmRaw.contains('credit') ||
        pmRaw.contains('كريدت');
    final isCash = pmRaw.contains('cash') || pmRaw.contains('نقد');
    if (_activeFilter == 'card') return isCard;
    if (_activeFilter == 'cash') return isCash;
    return true;
  }

  Map<String, double> _computeReturnSums(int saleId) {
    final rows = saleReturnItemsCache[saleId] ?? [];
    double refunded = 0.0;
    double addedCost = 0.0;
    for (final r in rows) {
      final qty = (r['qty'] as num?)?.toInt() ?? 0;
      final price = (r['price'] as num?)?.toDouble() ?? 0.0;
      final isReplacement = (r['is_replacement'] as num?)?.toInt() ?? 0;
      if (isReplacement == 0)
        refunded += qty * price;
      else
        addedCost += qty * price;
    }
    return {
      'refunded': refunded,
      'added': addedCost,
      'net': addedCost - refunded
    };
  }

  double _sumPaidDeltaForSale(int saleId) {
    final rows = saleReturnsCache[saleId] ?? [];
    double sum = 0.0;
    for (final r in rows) {
      sum += (r['paid_delta'] as num?)?.toDouble() ?? 0.0;
    }
    return sum;
  }

  Map<int, List<Map<String, dynamic>>> _groupReturnItemsByReturnId(int saleId) {
    final rows = saleReturnItemsCache[saleId] ?? [];
    final Map<int, List<Map<String, dynamic>>> m = {};
    for (final r in rows) {
      final rid = (r['return_id'] as num).toInt();
      m.putIfAbsent(rid, () => []).add(r);
    }
    return m;
  }

  Widget buildLabelValue(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          value,
          textAlign: TextAlign.right,
          style: TextStyle(
            color: AppColorsDark.mainTextLight,
            fontSize: 15,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(width: 6),
        Text(
          ' : $label',
          style: TextStyle(
            color: AppColorsDark.mainTextDark,
            fontSize: 13,
          ),
        ),
      ],
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        selectedDate = picked;
      });
      await _loadSales(date: selectedDate);
    }
  }

  String _formatSelectedDate(DateTime dt) => '${dt.day}/${dt.month}';

  // ----------------------
  // Helper: extract discount info (original_total, type, value, computed amount, effective total)
  // ----------------------
  Map<String, dynamic> _extractDiscountInfo(
    Map<String, dynamic> s, {
    double currentItemsTotal = 0.0,
  }) {
    final meta = s['meta'];
    double originalTotal = currentItemsTotal;
    if (s.containsKey('original_total') && s['original_total'] != null) {
      final ot = s['original_total'];
      originalTotal = (ot is num)
          ? ot.toDouble()
          : (double.tryParse(ot.toString()) ?? currentItemsTotal);
    } else if (meta is Map && meta['original_total'] != null) {
      final ot = meta['original_total'];
      originalTotal = (ot is num)
          ? ot.toDouble()
          : (double.tryParse(ot.toString()) ?? currentItemsTotal);
    } else {
      originalTotal = currentItemsTotal;
    }

    String discountTypeRaw = '';
    double discountValueRaw = 0.0;
    dynamic disc = s['discount'] ?? (meta is Map ? meta['discount'] : null);
    if (disc is Map) {
      if (disc.containsKey('type'))
        discountTypeRaw = (disc['type'] ?? '').toString();
      if (disc.containsKey('value')) {
        final v = disc['value'];
        discountValueRaw =
            (v is num) ? v.toDouble() : (double.tryParse(v.toString()) ?? 0.0);
      }
    } else {
      final t = s['discount_type'] ??
          s['discountType'] ??
          (meta is Map ? meta['discount_type'] ?? meta['discountType'] : null);
      final v = s['discount_value'] ??
          s['discountValue'] ??
          (meta is Map
              ? meta['discount_value'] ?? meta['discountValue']
              : null);
      if (t != null) discountTypeRaw = t.toString();
      if (v != null)
        discountValueRaw =
            (v is num) ? v.toDouble() : (double.tryParse(v.toString()) ?? 0.0);
    }

    final lcType = discountTypeRaw.toString().toLowerCase();
    final isPercent = lcType.contains('percent') ||
        lcType.contains('%') ||
        lcType.contains('perc');
    final discountType = isPercent ? 'percent' : 'fixed';
    double discountAmount = 0.0;

    if (isPercent) {
      discountAmount = originalTotal * (discountValueRaw / 100.0);
    } else {
      discountAmount = discountValueRaw;
    }

    if (discountAmount.isNaN || discountAmount.isInfinite) discountAmount = 0.0;
    if (discountAmount < 0) discountAmount = 0.0;
    if (discountAmount > originalTotal) discountAmount = originalTotal;

    final effectiveTotal =
        (originalTotal - discountAmount).clamp(0.0, double.infinity);

    return {
      'original_total': originalTotal,
      'discount_type': discountType,
      'discount_value': discountValueRaw,
      'discount_amount': discountAmount,
      'effective_total': effectiveTotal,
    };
  }

  // ----------------------
  // Class-level effective total for header (uses cached items when available)
  // ----------------------
  double _effectiveTotalForSaleHeader(Map<String, dynamic> s) {
    final saleId = (s['id'] is num)
        ? (s['id'] as num).toInt()
        : (int.tryParse(s['id']?.toString() ?? '') ?? 0);
    double currentItemsTotal = 0.0;
    if (saleId != 0 && saleItemsCache.containsKey(saleId)) {
      final items = saleItemsCache[saleId]!;
      currentItemsTotal = items.fold<double>(0.0, (p, it) {
        final qty = (it['quantity'] as num?)?.toDouble() ?? 0.0;
        final price = (it['price'] as num?)?.toDouble() ?? 0.0;
        return p + qty * price;
      });
    } else {
      currentItemsTotal = (s['total'] as num?)?.toDouble() ?? 0.0;
    }

    final info = _extractDiscountInfo(s, currentItemsTotal: currentItemsTotal);
    return (info['effective_total'] as double?) ?? currentItemsTotal;
  }

  @override
  Widget build(BuildContext context) {
    final dateKeys = groupedByDate.keys.toList()
      ..sort((a, b) => b.compareTo(a));
    return Scaffold(
      backgroundColor: AppColorsDark.bgColor,
      appBar: AppBar(
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: Theme.of(context).iconTheme.color),
        backgroundColor: Colors.transparent,
        elevation: 0.0,
        centerTitle: true,
        title: Text(
          'الفواتير المدفوعه',
          style: TextStyle(
            color: AppColorsDark.mainTextDark,
            fontSize: 20,
          ),
        ),
        actions: [
          IconButton(
            onPressed: () async {
              setState(() {
                selectedDate = DateTime.now();
              });
              await _loadSales(date: selectedDate);
            },
            icon: Icon(Icons.refresh, color: Theme.of(context).iconTheme.color),
            tooltip: 'تحديث لليوم',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Padding(
              padding:
                  const EdgeInsets.symmetric(vertical: 12.0, horizontal: 16.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  GestureDetector(
                    onTap: _pickDate,
                    child: Column(
                      children: [
                        Text(
                          'التاريخ',
                          style: TextStyle(
                            color: AppColorsDark.mainTextLight,
                            fontSize: 15,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _formatSelectedDate(selectedDate),
                              style: TextStyle(
                                  color: AppColorsDark.mainTextDark,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(width: 8),
                            Icon(Icons.calendar_today,
                                size: 18,
                                color: Theme.of(context).iconTheme.color),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Directionality(
              textDirection: TextDirection.rtl,
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 8,
                children: [
                  // chips...
                  Theme(
                    data: Theme.of(context).copyWith(
                      chipTheme: Theme.of(context).chipTheme.copyWith(
                            checkmarkColor: AppColorsDark.mainColor,
                          ),
                    ),
                    child: ChoiceChip(
                      disabledColor: AppColorsDark.bgColor,
                      backgroundColor: AppColorsDark.bgColor,
                      selectedColor: AppColorsDark.bgColor,
                      labelStyle: TextStyle(
                        color: _activeFilter == 'card'
                            ? AppColorsDark.mainTextDark
                            : AppColorsDark.mainTextLight,
                        fontWeight: FontWeight.w600,
                      ),
                      side: BorderSide(
                        color: AppColorsDark.mainColor,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                      label: const Text('دفع بالمحفظة'),
                      iconTheme: IconThemeData(
                        color: Theme.of(context).iconTheme.color,
                      ),
                      selected: _activeFilter == 'card',
                      onSelected: (_) {
                        setState(() {
                          _activeFilter = 'card';
                        });
                      },
                    ),
                  ),
                  Theme(
                    data: Theme.of(context).copyWith(
                      chipTheme: Theme.of(context).chipTheme.copyWith(
                            checkmarkColor: AppColorsDark.mainColor,
                          ),
                    ),
                    child: ChoiceChip(
                      disabledColor: AppColorsDark.bgColor,
                      backgroundColor: AppColorsDark.bgColor,
                      selectedColor: AppColorsDark.bgColor,
                      labelStyle: TextStyle(
                        color: _activeFilter == 'cash'
                            ? AppColorsDark.mainTextDark
                            : AppColorsDark.mainTextLight,
                        fontWeight: FontWeight.w600,
                      ),
                      side: BorderSide(
                        color: AppColorsDark.mainColor,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                      label: const Text('نقدي'),
                      iconTheme: IconThemeData(
                        color: Theme.of(context).iconTheme.color,
                      ),
                      selected: _activeFilter == 'cash',
                      onSelected: (_) {
                        setState(() {
                          _activeFilter = 'cash';
                        });
                      },
                    ),
                  ),
                  Theme(
                    data: Theme.of(context).copyWith(
                      chipTheme: Theme.of(context).chipTheme.copyWith(
                            checkmarkColor: AppColorsDark.mainColor,
                          ),
                    ),
                    child: ChoiceChip(
                      disabledColor: AppColorsDark.bgColor,
                      backgroundColor: AppColorsDark.bgColor,
                      selectedColor: AppColorsDark.bgColor,
                      labelStyle: TextStyle(
                        color: _activeFilter == 'all'
                            ? AppColorsDark.mainTextDark
                            : AppColorsDark.mainTextLight,
                        fontWeight: FontWeight.w600,
                      ),
                      side: BorderSide(color: AppColorsDark.mainColor),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                      label: const Text('الكل'),
                      iconTheme: IconThemeData(
                          color: Theme.of(context).iconTheme.color),
                      selected: _activeFilter == 'all',
                      onSelected: (_) {
                        setState(() {
                          _activeFilter = 'all';
                        });
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: loading
                  ? ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount:
                          6, // عدد عناصر shimmer المراد عرضها أثناء التحميل
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        return LoadingShimmer(
                          height: 80,
                          borderRadius: BorderRadius.circular(10),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                        );
                      },
                    )
                  : groupedByDate.isEmpty
                      ? const EmptyStateCard(
                          icon: Icons.receipt_long,
                          title: 'لا توجد فواتير',
                          message: 'لا توجد فواتير مسجلة حتى الآن.',
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: dateKeys.length,
                          itemBuilder: (context, idx) {
                            final date = dateKeys[idx];
                            final daySales = groupedByDate[date]!
                                .where((s) =>
                                    !_isCreditValue(s['is_credit']) &&
                                    _matchesPaymentFilter(s))
                                .toList();

                            if (daySales.isEmpty) {
                              return const SizedBox.shrink();
                            }

                            final dayTotal = daySales.fold<double>(0.0, (p, s) {
                              return p +
                                  ((s['total'] as num?)?.toDouble() ?? 0.0);
                            });
                            final Map<String, List<Map<String, dynamic>>>
                                cashierGroups = {};
                            for (final s in daySales) {
                              final cashierFromSale =
                                  (s['cashier_username'] ?? '').toString();
                              final cashier = cashierFromSale.isNotEmpty
                                  ? cashierFromSale
                                  : (_currentUser != null
                                      ? (_currentUser!['username'] ??
                                          'غير معروف')
                                      : 'غير معروف');
                              cashierGroups
                                  .putIfAbsent(cashier, () => [])
                                  .add(s);
                            }
                            return Card(
                                color: AppColorsDark.bgColor,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 10.0),
                                  child: AccordionWidget(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 10),
                                    isInitiallyExpanded: false,
                                    showIcon: false,
                                    decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(15),
                                        color: AppColorsDark.bgColor,
                                        border: Border.all(
                                            color: AppColorsDark.mainColor)),
                                    header: AbsorbPointer(
                                      absorbing: true,
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 20.0, vertical: 20.0),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Align(
                                                alignment: Alignment.centerLeft,
                                                child: Text(
                                                  date,
                                                  style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: AppColorsDark
                                                          .mainTextDark),
                                                ),
                                              ),
                                            ),
                                            Expanded(
                                              child: Center(
                                                child: Text(
                                                  'فاتورات: ${daySales.length}',
                                                  style: TextStyle(
                                                      color: AppColorsDark
                                                          .mainTextDark,
                                                      fontSize: 17),
                                                ),
                                              ),
                                            ),
                                            Expanded(
                                              child: Align(
                                                alignment:
                                                    Alignment.centerRight,
                                                child: Text(
                                                  'إجمالي اليوم: ${dayTotal.toStringAsFixed(2)}',
                                                  style: TextStyle(
                                                      fontSize: 17,
                                                      color: AppColorsDark
                                                          .mainTextDark),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    content: Column(
                                      children:
                                          cashierGroups.entries.map((entry) {
                                        final cashierName = entry.key;
                                        final cashierSales = entry.value;
                                        final cashierTotal = cashierSales
                                            .fold<double>(0.0, (p, s) {
                                          return p +
                                              ((s['total'] as num?)
                                                      ?.toDouble() ??
                                                  0.0);
                                        });
                                        return Padding(
                                          padding: const EdgeInsets.all(20.0),
                                          child: AccordionWidget(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 10, vertical: 10),
                                            isInitiallyExpanded: false,
                                            showIcon: false,
                                            decoration: BoxDecoration(
                                                borderRadius:
                                                    BorderRadius.circular(15),
                                                color:
                                                    Theme.of(context).cardColor,
                                                border: Border.all(
                                                    color: AppColorsDark
                                                        .mainColor)),
                                            header: AbsorbPointer(
                                              absorbing: true,
                                              child: Padding(
                                                padding:
                                                    EdgeInsetsGeometry.all(8),
                                                child: Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment
                                                          .spaceBetween,
                                                  children: [
                                                    Expanded(
                                                        child: Align(
                                                            alignment: Alignment
                                                                .centerLeft,
                                                            child: Text(
                                                                cashierName,
                                                                style: TextStyle(
                                                                    color: Colors
                                                                        .black,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .bold,
                                                                    fontSize:
                                                                        17)))),
                                                    Expanded(
                                                        child: Center(
                                                            child: Text(
                                                                'فاتورات: ${cashierSales.length}',
                                                                style: TextStyle(
                                                                    color: Colors
                                                                        .black)))),
                                                    Expanded(
                                                        child: Align(
                                                            alignment: Alignment
                                                                .centerRight,
                                                            child: Text(
                                                                'إجمالي: ${cashierTotal.toStringAsFixed(2)}',
                                                                style: TextStyle(
                                                                    color: Colors
                                                                        .black)))),
                                                  ],
                                                ),
                                              ),
                                            ),
                                            content: Column(
                                              children: [
                                                ...cashierSales.map((s) {
                                                  final saleId =
                                                      (s['id'] as num).toInt();
                                                  final salePaidFromAPI =
                                                      (s['paid_amount'] as num?)
                                                              ?.toDouble() ??
                                                          0.0;
                                                  final cashierFromSale =
                                                      (s['cashier_username'] ??
                                                              '')
                                                          .toString();
                                                  final cashier = cashierFromSale
                                                          .isNotEmpty
                                                      ? cashierFromSale
                                                      : (_currentUser != null
                                                          ? (_currentUser![
                                                                  'username'] ??
                                                              'غير معروف')
                                                          : 'غير معروف');
                                                  final dateRaw =
                                                      (s['date'] ?? '')
                                                          .toString();
                                                  final time =
                                                      _formatTime(dateRaw);
                                                  final bool isCredit =
                                                      _isCreditValue(
                                                          s['is_credit']);
                                                  final pmRaw = (s[
                                                              'payment_type'] ??
                                                          s['paymentMethod'] ??
                                                          s['return_note'] ??
                                                          '')
                                                      .toString()
                                                      .toLowerCase();
                                                  String paymentLabel;
                                                  if (isCredit) {
                                                    paymentLabel = 'آجل';
                                                  } else if (pmRaw
                                                          .contains('wallet') ||
                                                      pmRaw.contains('كارت') ||
                                                      pmRaw.contains('كرديت') ||
                                                      pmRaw.contains('kard') ||
                                                      pmRaw.contains('كريدت')) {
                                                    paymentLabel = 'كرديت';
                                                  } else if (pmRaw
                                                          .contains('cash') ||
                                                      pmRaw.contains('نقد')) {
                                                    paymentLabel = 'مدفوعة';
                                                  } else {
                                                    paymentLabel = 'مدفوعة';
                                                  }

                                                  return Card(
                                                    color: AppColorsDark
                                                        .bgCardColor,
                                                    child: AccordionWidget(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                          horizontal: 25,
                                                          vertical: 25),
                                                      decoration: BoxDecoration(
                                                        color: AppColorsDark
                                                            .bgCardColor,
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(15),
                                                      ),
                                                      header: AbsorbPointer(
                                                        absorbing: true,
                                                        child: Padding(
                                                          padding:
                                                              const EdgeInsets
                                                                  .symmetric(
                                                                  horizontal:
                                                                      20.0,
                                                                  vertical:
                                                                      20.0),
                                                          child: Row(
                                                            mainAxisAlignment:
                                                                MainAxisAlignment
                                                                    .spaceBetween,
                                                            children: [
                                                              Expanded(
                                                                child: Align(
                                                                    alignment:
                                                                        Alignment
                                                                            .centerLeft,
                                                                    child: Text(
                                                                      'الوقت: $time',
                                                                      style: TextStyle(
                                                                          fontWeight: FontWeight
                                                                              .bold,
                                                                          fontSize:
                                                                              15,
                                                                          color:
                                                                              AppColorsDark.mainTextDark),
                                                                    )),
                                                              ),
                                                              Expanded(
                                                                child: Align(
                                                                  alignment:
                                                                      Alignment
                                                                          .center,
                                                                  child: Text(
                                                                    'فاتورة #$saleId',
                                                                    style: TextStyle(
                                                                        fontWeight:
                                                                            FontWeight
                                                                                .bold,
                                                                        fontSize:
                                                                            15,
                                                                        color: AppColorsDark
                                                                            .mainTextDark),
                                                                  ),
                                                                ),
                                                              ),
                                                              Expanded(
                                                                child: Align(
                                                                  alignment:
                                                                      Alignment
                                                                          .centerRight,
                                                                  child: Text(
                                                                    'المجموع: ${_effectiveTotalForSaleHeader(s).toStringAsFixed(2)}',
                                                                    style: TextStyle(
                                                                        fontWeight:
                                                                            FontWeight
                                                                                .bold,
                                                                        fontSize:
                                                                            15,
                                                                        color: AppColorsDark
                                                                            .mainTextDark),
                                                                  ),
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                      ),
                                                      showIcon: true,
                                                      content: Padding(
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                                horizontal: 25,
                                                                vertical: 25),
                                                        child: Builder(
                                                            builder: (context) {
                                                          final items =
                                                              saleItemsCache[
                                                                      saleId] ??
                                                                  [];
                                                          final returnsMeta =
                                                              saleReturnsCache[
                                                                      saleId] ??
                                                                  [];
                                                          final sums =
                                                              _computeReturnSums(
                                                                  saleId);
                                                          final paidDeltaSum =
                                                              _sumPaidDeltaForSale(
                                                                  saleId);
                                                          final refundedVal =
                                                              sums['refunded'] ??
                                                                  0.0;
                                                          final addedVal =
                                                              sums['added'] ??
                                                                  0.0;
                                                          final currentItemsTotal =
                                                              items
                                                                  .fold<double>(
                                                                      0.0,
                                                                      (p, it) {
                                                            final qty = (it['quantity']
                                                                        as num?)
                                                                    ?.toInt() ??
                                                                0;
                                                            final price = (it[
                                                                            'price']
                                                                        as num?)
                                                                    ?.toDouble() ??
                                                                0.0;
                                                            return p +
                                                                (qty * price);
                                                          });

                                                          // <-- replaced discount logic: use helper to extract discount info -->
                                                          final info =
                                                              _extractDiscountInfo(
                                                                  s,
                                                                  currentItemsTotal:
                                                                      currentItemsTotal);
                                                          final double
                                                              originalTotalFromMeta =
                                                              (info['original_total']
                                                                      as double?) ??
                                                                  currentItemsTotal;
                                                          final String
                                                              discountTypeUsed =
                                                              (info['discount_type']
                                                                      as String?) ??
                                                                  'fixed';
                                                          final double
                                                              discountValueUsed =
                                                              (info['discount_value']
                                                                      as double?) ??
                                                                  0.0;
                                                          final double
                                                              discountAmount =
                                                              (info['discount_amount']
                                                                      as double?) ??
                                                                  0.0;
                                                          final double
                                                              effectiveTotalAfterDiscount =
                                                              (info['effective_total']
                                                                      as double?) ??
                                                                  currentItemsTotal;
                                                          final customerName =
                                                              (s['customer_name'] ??
                                                                      '')
                                                                  .toString();
                                                          final customerPhone =
                                                              (s['customer_phone'] ??
                                                                      '')
                                                                  .toString();
                                                          final loyaltyDiscount =
                                                              (s['loyalty_discount']
                                                                          as num?)
                                                                      ?.toDouble() ??
                                                                  0.0;
                                                          final finalTotalAfterLoyalty =
                                                              (effectiveTotalAfterDiscount -
                                                                      loyaltyDiscount)
                                                                  .clamp(
                                                                      0.0,
                                                                      double
                                                                          .infinity);

                                                          String discountLabel =
                                                              '';
                                                          if (discountAmount >
                                                              0) {
                                                            if (discountTypeUsed ==
                                                                'percent') {
                                                              discountLabel =
                                                                  ' • خصم ${discountValueUsed.toStringAsFixed(2)}% (${discountAmount.toStringAsFixed(2)})';
                                                            } else {
                                                              discountLabel =
                                                                  ' • خصم بالجنيه (${discountAmount.toStringAsFixed(2)})';
                                                            }
                                                          }

                                                          final double
                                                              originalTotalBefore =
                                                              (currentItemsTotal +
                                                                  refundedVal -
                                                                  addedVal);

                                                          // المبلغ الذي كان مسجلاً على الفاتورة قبل أي إجراءات
                                                          final double
                                                              originalPaidBefore =
                                                              (salePaidFromAPI)
                                                                  .clamp(
                                                                      0.0,
                                                                      double
                                                                          .infinity);

                                                          // المبلغ الإضافي الذي سجله سجل المرتجع/الاستبدال (قد يكون موجبًا أو سالبًا)
                                                          final double
                                                              extraPaid =
                                                              paidDeltaSum;

                                                          // إجمالي ما دفعه العميل فعليًا بعد العملية
                                                          final double
                                                              totalPaidByCustomer =
                                                              (originalPaidBefore +
                                                                      extraPaid)
                                                                  .clamp(
                                                                      0.0,
                                                                      double
                                                                          .infinity);

                                                          // حساب التغيير الذي أعطي للعميل أثناء الفاتورة الأصلية (إن وُجد)
                                                          final double
                                                              originalChangeGiven =
                                                              (originalPaidBefore >
                                                                      originalTotalBefore)
                                                                  ? (originalPaidBefore -
                                                                      originalTotalBefore)
                                                                  : 0.0;

                                                          // مبالغ معروضة (نستثني التغيير المعاد للعميل من المبالغ الفعلية المعروضة)
                                                          final double
                                                              displayOriginalPaid =
                                                              (originalPaidBefore -
                                                                      originalChangeGiven)
                                                                  .clamp(
                                                                      0.0,
                                                                      double
                                                                          .infinity);
                                                          final double
                                                              displayEffectivePaid =
                                                              (totalPaidByCustomer -
                                                                      originalChangeGiven)
                                                                  .clamp(
                                                                      0.0,
                                                                      double
                                                                          .infinity);

                                                          // الفروقات النهائية
                                                          final double
                                                              paidDifference =
                                                              displayEffectivePaid -
                                                                  displayOriginalPaid;
                                                          final double
                                                              absPaidDifference =
                                                              paidDifference
                                                                  .abs();

                                                          final double
                                                              effectiveTotal =
                                                              effectiveTotalAfterDiscount;
                                                          final double
                                                              effectiveRemaining =
                                                              (displayEffectivePaid <
                                                                      effectiveTotal)
                                                                  ? (effectiveTotal -
                                                                      displayEffectivePaid)
                                                                  : 0.0;
                                                          final double
                                                              originalRemaining =
                                                              (displayOriginalPaid <
                                                                      originalTotalBefore)
                                                                  ? (originalTotalBefore -
                                                                      displayOriginalPaid)
                                                                  : 0.0;

                                                          if (items.isEmpty &&
                                                              _groupReturnItemsByReturnId(
                                                                      saleId)
                                                                  .isEmpty) {
                                                            return const Padding(
                                                              padding:
                                                                  EdgeInsets
                                                                      .all(8.0),
                                                              child:
                                                                  EmptyStateCard(
                                                                icon: Icons
                                                                    .inventory_2_outlined,
                                                                title:
                                                                    'لا توجد عناصر',
                                                                message:
                                                                    'لا توجد عناصر مسجلة لهذه الفاتورة.',
                                                                margin:
                                                                    EdgeInsets
                                                                        .zero,
                                                              ),
                                                            );
                                                          }

                                                          Color badgeColor;
                                                          IconData badgeIcon;
                                                          String badgeText;
                                                          if (paymentLabel ==
                                                              'كرديت') {
                                                            badgeColor = Colors
                                                                .blueAccent;
                                                            badgeIcon = Icons
                                                                .credit_card;
                                                            badgeText =
                                                                'مدفوع إلكترونياً (بطاقة/بوابة)';
                                                          } else if (paymentLabel ==
                                                              'مدفوعة') {
                                                            badgeColor =
                                                                Colors.green;
                                                            badgeIcon = Icons
                                                                .attach_money;
                                                            badgeText =
                                                                'مدفوعة نقداً';
                                                          } else {
                                                            badgeColor =
                                                                Colors.orange;
                                                            badgeIcon =
                                                                Icons.schedule;
                                                            badgeText =
                                                                'آجل (فاتورة مستحقة)';
                                                          }
                                                          final badgeFullText =
                                                              '$badgeText$discountLabel';

                                                          final returnsById =
                                                              _groupReturnItemsByReturnId(
                                                                  saleId);

                                                          return Column(
                                                            crossAxisAlignment:
                                                                CrossAxisAlignment
                                                                    .end,
                                                            children: [
                                                              const Text(
                                                                  ' : عناصر الفاتورة الأصلية',
                                                                  style: TextStyle(
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .bold,
                                                                      color: Colors
                                                                          .white)),
                                                              const SizedBox(
                                                                  height: 15),
                                                              ListView
                                                                  .separated(
                                                                shrinkWrap:
                                                                    true,
                                                                physics:
                                                                    const NeverScrollableScrollPhysics(),
                                                                itemCount: items
                                                                    .length,
                                                                separatorBuilder:
                                                                    (_, __) =>
                                                                        Divider(
                                                                  color: AppColorsDark
                                                                      .mainColor,
                                                                ),
                                                                itemBuilder:
                                                                    (context,
                                                                        i) {
                                                                  final it =
                                                                      items[i];
                                                                  final name = (it[
                                                                              'product_name'] ??
                                                                          'منتج')
                                                                      .toString();
                                                                  final qty =
                                                                      (it['quantity'] as num?)
                                                                              ?.toInt() ??
                                                                          0;
                                                                  final price =
                                                                      (it['price'] as num?)
                                                                              ?.toDouble() ??
                                                                          0.0;
                                                                  final subtotal =
                                                                      qty *
                                                                          price;
                                                                  final barcode =
                                                                      (it['barcode'] ??
                                                                              '-')
                                                                          .toString();
                                                                  final returnedQty = (it['returned_quantity']
                                                                              as num?)
                                                                          ?.toInt() ??
                                                                      (((it['returned'] as num?)?.toInt() ?? 0) ==
                                                                              1
                                                                          ? qty
                                                                          : 0);
                                                                  final isPartiallyReturned =
                                                                      returnedQty >
                                                                          0;
                                                                  final isFullyReturned =
                                                                      qty > 0 &&
                                                                          returnedQty >=
                                                                              qty;
                                                                  final returnedSubtotal =
                                                                      returnedQty *
                                                                          price;
                                                                  final itemValueStyle =
                                                                      TextStyle(
                                                                    color: isPartiallyReturned
                                                                        ? Colors
                                                                            .redAccent
                                                                        : AppColorsDark
                                                                            .mainTextLight,
                                                                    fontSize:
                                                                        15,
                                                                    decoration: isFullyReturned
                                                                        ? TextDecoration
                                                                            .lineThrough
                                                                        : TextDecoration
                                                                            .none,
                                                                  );
                                                                  return Container(
                                                                    padding: const EdgeInsets
                                                                        .symmetric(
                                                                        vertical:
                                                                            10,
                                                                        horizontal:
                                                                            8),
                                                                    decoration:
                                                                        BoxDecoration(
                                                                      color: Colors
                                                                          .transparent,
                                                                      borderRadius:
                                                                          BorderRadius.circular(
                                                                              6),
                                                                    ),
                                                                    child:
                                                                        Column(
                                                                      crossAxisAlignment:
                                                                          CrossAxisAlignment
                                                                              .stretch,
                                                                      children: [
                                                                        Row(
                                                                          mainAxisAlignment:
                                                                              MainAxisAlignment.end,
                                                                          crossAxisAlignment:
                                                                              CrossAxisAlignment.center,
                                                                          children: [
                                                                            Expanded(
                                                                              child: RichText(
                                                                                textAlign: TextAlign.right,
                                                                                text: TextSpan(
                                                                                  children: [
                                                                                    TextSpan(
                                                                                      text: name,
                                                                                      style: itemValueStyle,
                                                                                    ),
                                                                                    TextSpan(
                                                                                      text: ' : الاسم',
                                                                                      style: TextStyle(color: AppColorsDark.mainTextDark, fontSize: 13),
                                                                                    ),
                                                                                  ],
                                                                                ),
                                                                                overflow: TextOverflow.ellipsis,
                                                                              ),
                                                                            ),
                                                                          ],
                                                                        ),
                                                                        const SizedBox(
                                                                            height:
                                                                                12),
                                                                        if (isPartiallyReturned) ...[
                                                                          Align(
                                                                            alignment:
                                                                                Alignment.centerRight,
                                                                            child:
                                                                                Container(
                                                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                                              decoration: BoxDecoration(
                                                                                color: Colors.redAccent.withOpacity(0.12),
                                                                                border: Border.all(color: Colors.redAccent),
                                                                                borderRadius: BorderRadius.circular(999),
                                                                              ),
                                                                              child: Text(
                                                                                isFullyReturned ? 'تم الاسترجاع' : 'تم استرجاع $returnedQty من $qty',
                                                                                style: TextStyle(
                                                                                  color: Colors.redAccent,
                                                                                  fontWeight: FontWeight.bold,
                                                                                ),
                                                                              ),
                                                                            ),
                                                                          ),
                                                                          const SizedBox(
                                                                              height: 12),
                                                                        ],
                                                                        buildLabelValue(
                                                                            'باركود',
                                                                            barcode),
                                                                        const SizedBox(
                                                                            height:
                                                                                12),
                                                                        RichText(
                                                                          textAlign:
                                                                              TextAlign.right,
                                                                          text:
                                                                              TextSpan(
                                                                            children: [
                                                                              TextSpan(
                                                                                text: "$qty × ${price.toStringAsFixed(2)}",
                                                                                style: itemValueStyle,
                                                                              ),
                                                                              TextSpan(
                                                                                text: ' : الكميه',
                                                                                style: TextStyle(color: AppColorsDark.mainTextDark, fontSize: 13),
                                                                              ),
                                                                            ],
                                                                          ),
                                                                          overflow:
                                                                              TextOverflow.ellipsis,
                                                                        ),
                                                                        const SizedBox(
                                                                            height:
                                                                                12),
                                                                        RichText(
                                                                          textAlign:
                                                                              TextAlign.right,
                                                                          text:
                                                                              TextSpan(
                                                                            children: [
                                                                              TextSpan(
                                                                                text: subtotal.toStringAsFixed(2),
                                                                                style: itemValueStyle,
                                                                              ),
                                                                              TextSpan(
                                                                                text: ' : الإجمالي',
                                                                                style: TextStyle(color: AppColorsDark.mainTextDark, fontSize: 13),
                                                                              ),
                                                                            ],
                                                                          ),
                                                                          overflow:
                                                                              TextOverflow.ellipsis,
                                                                        ),
                                                                        if (isPartiallyReturned) ...[
                                                                          const SizedBox(
                                                                              height: 12),
                                                                          Text(
                                                                            'مسترجع: $name - ${returnedSubtotal.toStringAsFixed(2)}',
                                                                            textAlign:
                                                                                TextAlign.right,
                                                                            style:
                                                                                const TextStyle(
                                                                              color: Colors.redAccent,
                                                                              fontWeight: FontWeight.bold,
                                                                            ),
                                                                          ),
                                                                        ],
                                                                      ],
                                                                    ),
                                                                  );
                                                                },
                                                              ),
                                                              const SizedBox(
                                                                  height: 12),
                                                              if (customerPhone
                                                                      .isNotEmpty ||
                                                                  customerName
                                                                      .isNotEmpty) ...[
                                                                Divider(
                                                                    color: AppColorsDark
                                                                        .mainColor),
                                                                buildLabelValue(
                                                                    'رقم العميل',
                                                                    customerPhone
                                                                            .isEmpty
                                                                        ? '-'
                                                                        : customerPhone),
                                                                if (customerName
                                                                        .isNotEmpty &&
                                                                    customerName !=
                                                                        customerPhone) ...[
                                                                  const SizedBox(
                                                                      height:
                                                                          10),
                                                                  buildLabelValue(
                                                                      'اسم العميل',
                                                                      customerName),
                                                                ],
                                                                const SizedBox(
                                                                    height: 10),
                                                              ],
                                                              if (discountAmount >
                                                                  0) ...[
                                                                Divider(
                                                                    color: AppColorsDark
                                                                        .mainColor),
                                                                buildLabelValue(
                                                                    'الإجمالي قبل الخصم',
                                                                    originalTotalFromMeta
                                                                        .toStringAsFixed(
                                                                            2)),
                                                                const SizedBox(
                                                                    height: 10),
                                                                buildLabelValue(
                                                                  discountTypeUsed ==
                                                                          'percent'
                                                                      ? 'الخصم (${discountValueUsed.toStringAsFixed(2)}%)'
                                                                      : 'الخصم مبلغ ثابت',
                                                                  discountAmount
                                                                      .toStringAsFixed(
                                                                          2),
                                                                ),
                                                                const SizedBox(
                                                                    height: 10),
                                                                buildLabelValue(
                                                                    'الإجمالي بعد الخصم',
                                                                    effectiveTotalAfterDiscount
                                                                        .toStringAsFixed(
                                                                            2)),
                                                                const SizedBox(
                                                                    height: 12),
                                                              ],
                                                              if (loyaltyDiscount >
                                                                  0) ...[
                                                                Divider(
                                                                    color: Colors
                                                                        .orangeAccent),
                                                                buildLabelValue(
                                                                  'خصم رصيد العميل المستخدم',
                                                                  loyaltyDiscount
                                                                      .toStringAsFixed(
                                                                          2),
                                                                ),
                                                                const SizedBox(
                                                                    height: 10),
                                                                buildLabelValue(
                                                                  'الإجمالي بعد خصم العميل',
                                                                  finalTotalAfterLoyalty
                                                                      .toStringAsFixed(
                                                                          2),
                                                                ),
                                                                const SizedBox(
                                                                    height: 12),
                                                              ],
                                                              if (returnsById
                                                                  .isNotEmpty)
                                                                Divider(
                                                                    color: AppColorsDark
                                                                        .mainColor),
                                                              ...returnsById
                                                                  .entries
                                                                  .map((entry) {
                                                                final rid =
                                                                    entry.key;
                                                                final rows =
                                                                    entry.value;
                                                                final meta = (saleReturnsCache[
                                                                            saleId] ??
                                                                        [])
                                                                    .firstWhere(
                                                                        (rm) =>
                                                                            (rm['id']
                                                                                as int?) ==
                                                                            rid,
                                                                        orElse: () =>
                                                                            {});
                                                                final rDate =
                                                                    (meta['date'] ??
                                                                            '')
                                                                        as String;
                                                                final returnedRows = rows
                                                                    .where((r) =>
                                                                        (r['is_replacement']
                                                                                as num?)
                                                                            ?.toInt() ==
                                                                        0)
                                                                    .toList();
                                                                final replacementRows = rows
                                                                    .where((r) =>
                                                                        (r['is_replacement']
                                                                                as num?)
                                                                            ?.toInt() ==
                                                                        1)
                                                                    .toList();

                                                                return Card(
                                                                    margin: const EdgeInsets
                                                                        .symmetric(
                                                                        vertical:
                                                                            6),
                                                                    color: AppColorsDark
                                                                        .bgColor,
                                                                    child: Padding(
                                                                        padding: const EdgeInsets.all(8.0),
                                                                        child: Directionality(
                                                                          textDirection:
                                                                              TextDirection.rtl,
                                                                          child:
                                                                              Column(
                                                                            crossAxisAlignment:
                                                                                CrossAxisAlignment.start,
                                                                            children: [
                                                                              Row(
                                                                                children: [
                                                                                  Icon(
                                                                                    Icons.repeat,
                                                                                    size: 18,
                                                                                    color: Theme.of(context).iconTheme.color,
                                                                                  ),
                                                                                  const SizedBox(width: 8),
                                                                                  Column(
                                                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                                                    children: [
                                                                                      RichText(
                                                                                        text: TextSpan(
                                                                                          children: [
                                                                                            TextSpan(
                                                                                              text: 'اليوم: ',
                                                                                              style: TextStyle(color: AppColorsDark.mainTextDark, fontWeight: FontWeight.bold),
                                                                                            ),
                                                                                            TextSpan(
                                                                                              text: rDate.split('T').first,
                                                                                              style: TextStyle(color: AppColorsDark.mainTextLight),
                                                                                            ),
                                                                                          ],
                                                                                        ),
                                                                                      ),
                                                                                      const SizedBox(height: 10),
                                                                                      RichText(
                                                                                        text: TextSpan(
                                                                                          children: [
                                                                                            TextSpan(
                                                                                              text: 'الوقت: ',
                                                                                              style: TextStyle(color: AppColorsDark.mainTextDark, fontWeight: FontWeight.bold),
                                                                                            ),
                                                                                            TextSpan(
                                                                                              text: DateFormat('hh:mm a').format(DateTime.parse(rDate)),
                                                                                              style: TextStyle(color: AppColorsDark.mainTextLight),
                                                                                            ),
                                                                                          ],
                                                                                        ),
                                                                                      ),
                                                                                    ],
                                                                                  ),
                                                                                ],
                                                                              ),
                                                                              const SizedBox(height: 20),
                                                                              if (returnedRows.isNotEmpty)
                                                                                Text(
                                                                                  'العناصر المرجوعة:',
                                                                                  style: TextStyle(fontWeight: FontWeight.bold, color: AppColorsDark.mainTextDark, fontSize: 17),
                                                                                ),
                                                                              ...returnedRows.map((r) {
                                                                                final name = (r['product_name'] ?? 'منتج') as String;
                                                                                final qty = (r['qty'] as num?)?.toInt() ?? 0;
                                                                                final price = (r['price'] as num?)?.toDouble() ?? 0.0;
                                                                                final total = qty * price;
                                                                                return Padding(
                                                                                  padding: const EdgeInsets.symmetric(vertical: 6.0),
                                                                                  child: Column(
                                                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                                                    children: [
                                                                                      RichText(
                                                                                        text: TextSpan(children: [
                                                                                          TextSpan(text: 'الاسم: ', style: TextStyle(color: AppColorsDark.mainTextDark, fontWeight: FontWeight.bold)),
                                                                                          TextSpan(text: name, style: TextStyle(color: AppColorsDark.mainTextLight)),
                                                                                        ]),
                                                                                      ),
                                                                                      const SizedBox(height: 10),
                                                                                      RichText(
                                                                                        text: TextSpan(children: [
                                                                                          TextSpan(text: 'الكمية: ', style: TextStyle(color: AppColorsDark.mainTextDark, fontWeight: FontWeight.bold)),
                                                                                          TextSpan(text: '$qty', style: TextStyle(color: AppColorsDark.mainTextLight)),
                                                                                        ]),
                                                                                      ),
                                                                                      const SizedBox(height: 10),
                                                                                      RichText(
                                                                                        text: TextSpan(children: [
                                                                                          TextSpan(text: 'السعر: ', style: TextStyle(color: AppColorsDark.mainTextDark, fontWeight: FontWeight.bold)),
                                                                                          TextSpan(text: price.toStringAsFixed(2), style: TextStyle(color: AppColorsDark.mainTextLight)),
                                                                                        ]),
                                                                                      ),
                                                                                      const SizedBox(height: 10),
                                                                                      RichText(
                                                                                        text: TextSpan(children: [
                                                                                          TextSpan(text: 'الإجمالي: ', style: TextStyle(color: AppColorsDark.mainTextDark, fontWeight: FontWeight.bold)),
                                                                                          TextSpan(text: total.toStringAsFixed(2), style: TextStyle(color: AppColorsDark.mainTextLight)),
                                                                                        ]),
                                                                                      ),
                                                                                      const SizedBox(height: 10),
                                                                                    ],
                                                                                  ),
                                                                                );
                                                                              }).toList(),
                                                                              if (replacementRows.isNotEmpty)
                                                                                Padding(
                                                                                  padding: EdgeInsets.only(top: 8.0),
                                                                                  child: Text(
                                                                                    'البدائل (مقابل المرجوع):',
                                                                                    style: TextStyle(fontWeight: FontWeight.bold, color: AppColorsDark.mainTextDark, fontSize: 17),
                                                                                  ),
                                                                                ),
                                                                              ...replacementRows.map((r) {
                                                                                final name = (r['product_name'] ?? 'منتج') as String;
                                                                                final qty = (r['qty'] as num?)?.toInt() ?? 0;
                                                                                final price = (r['price'] as num?)?.toDouble() ?? 0.0;
                                                                                final total = qty * price;
                                                                                return Padding(
                                                                                  padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 12.0),
                                                                                  child: Column(
                                                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                                                    children: [
                                                                                      RichText(
                                                                                        text: TextSpan(children: [
                                                                                          TextSpan(text: 'الاسم: ', style: TextStyle(color: AppColorsDark.mainTextDark, fontWeight: FontWeight.bold)),
                                                                                          TextSpan(text: name, style: TextStyle(color: AppColorsDark.mainTextLight)),
                                                                                        ]),
                                                                                      ),
                                                                                      const SizedBox(height: 10),
                                                                                      RichText(
                                                                                        text: TextSpan(children: [
                                                                                          TextSpan(text: 'الكمية: ', style: TextStyle(color: AppColorsDark.mainTextDark, fontWeight: FontWeight.bold)),
                                                                                          TextSpan(text: '$qty', style: TextStyle(color: AppColorsDark.mainTextLight)),
                                                                                        ]),
                                                                                      ),
                                                                                      const SizedBox(height: 10),
                                                                                      RichText(
                                                                                        text: TextSpan(children: [
                                                                                          TextSpan(text: 'السعر: ', style: TextStyle(color: AppColorsDark.mainTextDark, fontWeight: FontWeight.bold)),
                                                                                          TextSpan(text: price.toStringAsFixed(2), style: TextStyle(color: AppColorsDark.mainTextLight)),
                                                                                        ]),
                                                                                      ),
                                                                                      const SizedBox(height: 10),
                                                                                      RichText(
                                                                                        text: TextSpan(children: [
                                                                                          TextSpan(text: 'الإجمالي: ', style: TextStyle(color: AppColorsDark.mainTextDark, fontWeight: FontWeight.bold)),
                                                                                          TextSpan(text: total.toStringAsFixed(2), style: TextStyle(color: AppColorsDark.mainTextLight)),
                                                                                        ]),
                                                                                      ),
                                                                                      const SizedBox(height: 10),
                                                                                    ],
                                                                                  ),
                                                                                );
                                                                              }).toList(),
                                                                            ],
                                                                          ),
                                                                        )));
                                                              }).toList(),
                                                              Divider(
                                                                  color: AppColorsDark
                                                                      .mainColor),
                                                              const SizedBox(
                                                                  height: 10),
                                                              Column(
                                                                crossAxisAlignment:
                                                                    CrossAxisAlignment
                                                                        .stretch,
                                                                children: [
                                                                  Text(
                                                                    'ملخص مالي مبسّط',
                                                                    textAlign:
                                                                        TextAlign
                                                                            .right,
                                                                    style: TextStyle(
                                                                        fontWeight:
                                                                            FontWeight
                                                                                .bold,
                                                                        fontSize:
                                                                            17,
                                                                        color: AppColorsDark
                                                                            .mainTextDark),
                                                                  ),
                                                                  const SizedBox(
                                                                      height:
                                                                          12),
                                                                  Row(
                                                                    textDirection:
                                                                        TextDirection
                                                                            .rtl,
                                                                    children: [
                                                                      Expanded(
                                                                        child:
                                                                            Column(
                                                                          crossAxisAlignment:
                                                                              CrossAxisAlignment.end,
                                                                          children: [
                                                                            Text(':قبل الإجراء',
                                                                                style: TextStyle(fontWeight: FontWeight.bold, color: AppColorsDark.mainTextDark)),
                                                                            const SizedBox(height: 10),
                                                                            Text(
                                                                              'إجمالي الفاتورة: ${originalTotalBefore.toStringAsFixed(2)}',
                                                                              textAlign: TextAlign.right,
                                                                              style: TextStyle(color: AppColorsDark.mainTextDark),
                                                                            ),
                                                                            const SizedBox(height: 10),
                                                                            Text('المشتري دفع: ${originalPaidBefore.toStringAsFixed(2)}',
                                                                                textAlign: TextAlign.right,
                                                                                style: TextStyle(fontWeight: FontWeight.bold, color: AppColorsDark.mainTextDark)),
                                                                            const SizedBox(height: 10),
                                                                            if (originalChangeGiven >
                                                                                0)
                                                                              Text(
                                                                                'الكاشير رجع للعميل: ${originalChangeGiven.toStringAsFixed(2)}',
                                                                                textAlign: TextAlign.right,
                                                                                style: TextStyle(color: AppColorsDark.mainTextLight, fontStyle: FontStyle.italic),
                                                                              ),
                                                                            const SizedBox(height: 10),
                                                                          ],
                                                                        ),
                                                                      ),
                                                                      const SizedBox(
                                                                          width:
                                                                              16),
                                                                      Expanded(
                                                                        child:
                                                                            Column(
                                                                          crossAxisAlignment:
                                                                              CrossAxisAlignment.end,
                                                                          children: [
                                                                            Text(':بعد الإجراء',
                                                                                style: TextStyle(fontWeight: FontWeight.bold, color: AppColorsDark.mainTextDark)),
                                                                            const SizedBox(height: 10),
                                                                            Text('إجمالي الفاتورة الآن: ${effectiveTotal.toStringAsFixed(2)}',
                                                                                textAlign: TextAlign.right,
                                                                                style: TextStyle(color: AppColorsDark.mainTextDark)),
                                                                            const SizedBox(height: 10),
                                                                            Builder(builder:
                                                                                (_) {
                                                                              if (paidDifference > 0) {
                                                                                return Text('المشتري دفع فرق: ${paidDifference.toStringAsFixed(2)}', textAlign: TextAlign.right, style: TextStyle(color: Colors.green, fontSize: 16));
                                                                              } else if (paidDifference < 0) {
                                                                                return Text('المشتري استلم فرق: ${absPaidDifference.toStringAsFixed(2)}', textAlign: TextAlign.right, style: TextStyle(color: Colors.red, fontSize: 16));
                                                                              } else {
                                                                                return Text('لم يحدث فرق في المبلغ المدفوع', textAlign: TextAlign.right, style: TextStyle(fontSize: 16, color: AppColorsDark.mainTextLight));
                                                                              }
                                                                            }),
                                                                            if (originalRemaining.abs() >
                                                                                0.001)
                                                                              Text('متبقي على العميل الآن: ${effectiveRemaining.toStringAsFixed(2)}', textAlign: TextAlign.right, style: TextStyle(color: (displayEffectivePaid < effectiveTotal) ? Colors.red : Colors.green)),
                                                                          ],
                                                                        ),
                                                                      ),
                                                                    ],
                                                                  ),
                                                                  const SizedBox(
                                                                      height:
                                                                          12),
                                                                  Divider(
                                                                      color: AppColorsDark
                                                                          .mainColor),
                                                                  const SizedBox(
                                                                      height:
                                                                          8),
                                                                  Column(
                                                                    crossAxisAlignment:
                                                                        CrossAxisAlignment
                                                                            .end,
                                                                    children: [
                                                                      Text(
                                                                          '${cashier.isNotEmpty ? cashier : 'غير معروف'} : المسؤول عن العملية',
                                                                          textAlign: TextAlign
                                                                              .right,
                                                                          style: TextStyle(
                                                                              fontWeight: FontWeight.bold,
                                                                              color: AppColorsDark.mainTextDark)),
                                                                      const SizedBox(
                                                                          height:
                                                                              15),
                                                                      Builder(
                                                                          builder:
                                                                              (_) {
                                                                        if (paidDeltaSum >
                                                                            0) {
                                                                          return Text(
                                                                              'أثناء الاستبدال/المرتجع، دفع المشتري مبلغًا إضافيًّا قدره ${paidDeltaSum.toStringAsFixed(2)} (الكاشير استلم هذا المبلغ).',
                                                                              textAlign: TextAlign.right,
                                                                              style: TextStyle(fontStyle: FontStyle.italic, color: AppColorsDark.mainTextLight, fontWeight: FontWeight.w300));
                                                                        } else if (paidDeltaSum <
                                                                            0) {
                                                                          return Text(
                                                                              'أثناء الاستبدال/المرتجع، أعاد/دفع الكاشير للمشتري مبلغًا قدره ${(-paidDeltaSum).toStringAsFixed(2)}.',
                                                                              textAlign: TextAlign.right,
                                                                              style: TextStyle(fontStyle: FontStyle.italic, color: AppColorsDark.mainTextLight, fontWeight: FontWeight.w300));
                                                                        } else {
                                                                          return Text(
                                                                              'خلال العملية لم يحدث أي دفع/استلام نقدي إضافي',
                                                                              textAlign: TextAlign.right,
                                                                              style: TextStyle(fontStyle: FontStyle.italic, color: AppColorsDark.mainTextLight, fontSize: 10, fontWeight: FontWeight.w300));
                                                                        }
                                                                      }),
                                                                    ],
                                                                  ),
                                                                ],
                                                              ),
                                                              const SizedBox(
                                                                  height: 12),
                                                              Align(
                                                                alignment: Alignment
                                                                    .centerRight,
                                                                child:
                                                                    Container(
                                                                  padding: const EdgeInsets
                                                                      .symmetric(
                                                                      vertical:
                                                                          8,
                                                                      horizontal:
                                                                          12),
                                                                  decoration:
                                                                      BoxDecoration(
                                                                    border: Border.all(
                                                                        color:
                                                                            badgeColor,
                                                                        width:
                                                                            1.6),
                                                                    color: badgeColor
                                                                        .withOpacity(
                                                                            0.08),
                                                                    borderRadius:
                                                                        BorderRadius
                                                                            .circular(8),
                                                                  ),
                                                                  child: Row(
                                                                    mainAxisSize:
                                                                        MainAxisSize
                                                                            .min,
                                                                    children: [
                                                                      Icon(
                                                                          badgeIcon,
                                                                          size:
                                                                              18,
                                                                          color:
                                                                              badgeColor),
                                                                      const SizedBox(
                                                                          width:
                                                                              8),
                                                                      Text(
                                                                        badgeFullText,
                                                                        style: TextStyle(
                                                                            color:
                                                                                badgeColor,
                                                                            fontWeight:
                                                                                FontWeight.bold),
                                                                      ),
                                                                    ],
                                                                  ),
                                                                ),
                                                              ),
                                                            ],
                                                          );
                                                        }),
                                                      ),
                                                    ),
                                                  );
                                                }).toList()
                                              ],
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                  ),
                                ));
                          },
                        ),
            )
          ],
        ),
      ),
    );
  }
}
