// lib/screens/receipts_screen.dart
import 'package:accordion_widget/Accordion_Widget.dart';
import 'package:cashgo/utils/colors.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart'hide TextDirection ;
import '../../services/db/db_helper.dart';

class receiptsScreen extends StatefulWidget {
  final String initialFilter;
  static const routeName = '/receipts';
  const receiptsScreen({Key? key, this.initialFilter = 'all'}) : super(key: key);

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

  // ====== جديد: فلتر التاريخ ======
  DateTime selectedDate = DateTime.now();

  Future<void> _loadSales({DateTime? date}) async {
    if (mounted) setState(() => loading = true);
    try {
      final rows = await DBHelper.instance.getAllSales();

      // إذا مررنا تاريخ - فلتر لذات اليوم
      if (date != null) {
        sales = rows.where((s) {
          final raw = (s['date'] ?? '').toString();
          final dt = _parseDateOnly(raw);
          if (dt == null) return false;
          return dt.year == date.year && dt.month == date.month && dt.day == date.day;
        }).toList();
      } else {
        sales = rows;
      }

      saleItemsCache.clear();
      saleReturnItemsCache.clear();
      saleReturnsCache.clear();
      _groupSalesByDate();
      final saleIds = sales.map((s) => (s['id'] as num).toInt()).toList();
      const int chunkSize = 10;

      for (int i = 0; i < saleIds.length; i += chunkSize) {
        final end = (i + chunkSize < saleIds.length) ? i + chunkSize : saleIds.length;
        final chunk = saleIds.sublist(i, end);

        await Future.wait(chunk.map((saleId) async {
          try {
            final itemsFuture = DBHelper.instance.getSaleItemsBySaleId(saleId);
            final returnItemsFuture = DBHelper.instance.getSaleReturnItemsForSale(saleId);
            final returnsFuture = DBHelper.instance.getSaleReturnsBySaleId(saleId);

            final results = await Future.wait([itemsFuture, returnItemsFuture, returnsFuture]);

            saleItemsCache[saleId] = (results[0] as List).cast<Map<String, dynamic>>();
            saleReturnItemsCache[saleId] = (results[1] as List).cast<Map<String, dynamic>>();
            saleReturnsCache[saleId] = (results[2] as List).cast<Map<String, dynamic>>();
          } catch (e) {
            debugPrint('prefetch error for sale $saleId: $e');
          }
        }));
        if (mounted) setState(() {});
      }
    } catch (e) {
      debugPrint('Error loading sales: $e');
      rethrow;
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  // مساعد لتحليل تاريخ بصيغ متعددة إلى DateTime (يُستخدم للفلترة)
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
      final parts = raw.split(RegExp(r'[\s/\\\-]')).where((p) => p.isNotEmpty).toList();
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
    final pmRaw = (s['payment_method'] ?? s['paymentMethod'] ?? s['return_note'] ?? '').toString().toLowerCase();
    final isCard = pmRaw.contains('wallet') || pmRaw.contains('كارت') || pmRaw.contains('كرديت') || pmRaw.contains('credit') || pmRaw.contains('كريدت');
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
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 15,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(width: 6),
        Text(
          ' : $label',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
          ),
        ),
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    _activeFilter = widget.initialFilter;
    // نحمّل الفواتير مُفلترة لليوم الحالي بالافتراضي
    _loadSales(date: selectedDate);
    _loadCurrentUser();
  }

  Future<void> _loadCurrentUser() async {
    _currentUser = await DBHelper.instance.getCurrentUser();
    if (mounted) setState(() {});
  }

  // ====== جديد: اختيار التاريخ ======
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

  @override
  Widget build(BuildContext context) {
    final dateKeys = groupedByDate.keys.toList()..sort((a, b) => b.compareTo(a));

    return Scaffold(
      backgroundColor: AppColorsDark.bgColor,
      appBar: AppBar(
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        backgroundColor: Colors.transparent,
        elevation: 0.0,
        centerTitle: true,
        title: const Text(
          'الفواتير المدفوعه',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
          ),
        ),
        actions: [
          IconButton(
            onPressed: () async {
              // إعادة التعيين لليوم الحالي وإعادة التحميل
              setState(() {
                selectedDate = DateTime.now();
              });
              await _loadSales(date: selectedDate);
            },
            icon: Icon(Icons.refresh, color: Colors.white70),
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
            // === عرض التاريخ والفلتر تحت الاب بار (بالمنتصف) ===
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 16.0),
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
                          style: TextStyle(color: Colors.white70, fontSize: 15,),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _formatSelectedDate(selectedDate),
                              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(width: 8),
                            Icon(Icons.calendar_today, size: 18, color: Colors.white70),
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
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
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
                        color: _activeFilter == 'card' ? Colors.white : Colors.white70,
                        fontWeight: FontWeight.w600,
                      ),
                      side: BorderSide(
                        color: AppColorsDark.mainColor,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                      label: const Text('محفظة إلكترونية'),
                      iconTheme: const IconThemeData(
                        color: Colors.white,
                      ),
                      selected: _activeFilter == 'card',
                      onSelected: (_) {
                        setState(() {
                          _activeFilter = 'card';
                        });
                      },
                    ),
                  ),
                  SizedBox(width: 20),
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
                        color: _activeFilter == 'cash' ? Colors.white : Colors.white70,
                        fontWeight: FontWeight.w600,
                      ),
                      side: BorderSide(
                        color: AppColorsDark.mainColor,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                      label: const Text('نقدي'),
                      iconTheme: const IconThemeData(
                        color: Colors.white,
                      ),
                      selected: _activeFilter == 'cash',
                      onSelected: (_) {
                        setState(() {
                          _activeFilter = 'cash';
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 20),
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
                        color: _activeFilter == 'cash' ? Colors.white : Colors.white70,
                        fontWeight: FontWeight.w600,
                      ),
                      side: BorderSide(color: AppColorsDark.mainColor),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                      label: const Text('الكل'),
                      iconTheme: IconThemeData(color: Colors.white),
                      selected: _activeFilter == 'all',
                      onSelected: (_) {
                        setState(() {
                          _activeFilter = 'all';
                        });
                        // لو بتحب أن زر "الكل" يُلغي فلتر التاريخ بدلاً من الاحتفاظ به، فكّر في استدعاء:
                        // _loadSales(date: null);
                      },
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),

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
                  final daySales = groupedByDate[date]!
                      .where((s) => !_isCreditValue(s['is_credit']) && _matchesPaymentFilter(s))
                      .toList();

                  if (daySales.isEmpty) {
                    return const SizedBox.shrink();
                  }

                  final dayTotal = daySales.fold<double>(0.0, (p, s) {
                    return p + ((s['total'] as num?)?.toDouble() ?? 0.0);
                  });

                  // ===== تجميع حسب اسم الكاشير داخل اليوم =====
                  final Map<String, List<Map<String, dynamic>>> cashierGroups = {};
                  for (final s in daySales) {
                    final cashierFromSale = (s['cashier_username'] ?? '').toString();
                    final cashier = cashierFromSale.isNotEmpty
                        ? cashierFromSale
                        : (_currentUser != null ? (_currentUser!['username'] ?? 'غير معروف') : 'غير معروف');
                    cashierGroups.putIfAbsent(cashier, () => []).add(s);
                  }

                  return Card(
                    color: AppColorsDark.bgColor,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10.0),
                      child: AccordionWidget(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        isInitiallyExpanded: false,
                        showIcon: false,
                        decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(15),
                            color: AppColorsDark.bgColor,
                            border: Border.all(color: AppColorsDark.mainColor)),
                        header: AbsorbPointer(
                          absorbing: true,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 20.0),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      date,
                                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Center(
                                    child: Text(
                                      'فاتورات: ${daySales.length}',
                                      style: const TextStyle(color: Colors.white, fontSize: 17),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Align(
                                    alignment: Alignment.centerRight,
                                    child: Text(
                                      'إجمالي اليوم: ${dayTotal.toStringAsFixed(2)}',
                                      style: const TextStyle(fontSize: 17, color: Colors.white),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        // ===== هنا نعرض كل كاشير مع فواتيره داخل اليوم =====
                        content: Column(
                          children: cashierGroups.entries.map((entry) {
                            final cashierName = entry.key;
                            final cashierSales = entry.value;
                            final cashierTotal = cashierSales.fold<double>(0.0, (p, s) {
                              return p + ((s['total'] as num?)?.toDouble() ?? 0.0);
                            });

                            return Padding(
                              padding: const EdgeInsets.all(20.0),
                              child: AccordionWidget(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                isInitiallyExpanded: false,
                                showIcon: false,
                                decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(15),
                                    color: AppColorsDark.bgColor,
                                    border: Border.all(color: AppColorsDark.mainColor)),
                                  header:AbsorbPointer(
                                    absorbing: true,
                                    child: Padding(
                                      padding: EdgeInsetsGeometry.all(8),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(child: Align(alignment: Alignment.centerLeft, child: Text(cashierName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold,fontSize: 17)))),
                                          Expanded(child: Center(child: Text('فاتورات: ${cashierSales.length}', style: const TextStyle(color: Colors.white70)))),
                                          Expanded(child: Align(alignment: Alignment.centerRight, child: Text('إجمالي: ${cashierTotal.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white)))),
                                        ],
                                      ),
                                    ),
                                  ),

                                  content: Column(
                                    children: [
                                      // الآن نعرض كل فاتورة للكاشير
                                      ...cashierSales.map((s) {
                                        final saleId = (s['id'] as num).toInt();
                                        final saleTotalFromDB = (s['total'] as num?)?.toDouble() ?? 0.0;
                                        final salePaidFromDB = (s['paid_amount'] as num?)?.toDouble() ?? 0.0;
                                        final cashierFromSale = (s['cashier_username'] ?? '').toString();
                                        final cashier = cashierFromSale.isNotEmpty
                                            ? cashierFromSale
                                            : (_currentUser != null ? (_currentUser!['username'] ?? 'غير معروف') : 'غير معروف');
                                        final dateRaw = (s['date'] ?? '').toString();
                                        final time = _formatTime(dateRaw);
                                        final bool isCredit = _isCreditValue(s['is_credit']);
                                        final pmRaw = (s['payment_method'] ?? s['paymentMethod'] ?? s['return_note'] ?? '').toString().toLowerCase();

                                        String paymentLabel;
                                        if (isCredit) {
                                          paymentLabel = 'آجل';
                                        } else if (pmRaw.contains('wallet') ||
                                            pmRaw.contains('كارت') ||
                                            pmRaw.contains('كرديت') ||
                                            pmRaw.contains('wallet') ||
                                            pmRaw.contains('كريدت')) {
                                          paymentLabel = 'كرديت';
                                        } else if (pmRaw.contains('cash') || pmRaw.contains('نقد')) {
                                          paymentLabel = 'مدفوعة';
                                        } else {
                                          paymentLabel = 'مدفوعة';
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

                                        return Card(
                                          color: AppColorsDark.bgCardColor,
                                          child: AccordionWidget(
                                            padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 25),
                                            decoration: BoxDecoration(
                                              color: AppColorsDark.bgCardColor,
                                              borderRadius: BorderRadius.circular(15),
                                            ),
                                            header: AbsorbPointer(
                                              absorbing: true,
                                              child: Padding(
                                                padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 20.0),
                                                child: Row(
                                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                  children: [
                                                    Expanded(
                                                      child: Align(
                                                          alignment: Alignment.centerLeft,
                                                          child: Text(
                                                            'الوقت: $time',
                                                            style: const TextStyle(
                                                                fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white),
                                                          )),
                                                    ),
                                                    Expanded(
                                                      child: Align(
                                                        alignment: Alignment.center,
                                                        child: Text(
                                                          'فاتورة #$saleId',
                                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white),
                                                        ),
                                                      ),
                                                    ),
                                                    Expanded(
                                                      child: Align(
                                                        alignment: Alignment.centerRight,
                                                        child: Text(
                                                          'المجموع: ${_effectiveTotalForSaleHeader(s).toStringAsFixed(2)}',
                                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white),
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                            showIcon: true,
                                            content: Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 25),
                                              child: Builder(builder: (context) {
                                                final items = saleItemsCache[saleId] ?? [];
                                                final returnsMeta = saleReturnsCache[saleId] ?? [];
                                                final sums = _computeReturnSums(saleId);
                                                final paidDeltaSum = _sumPaidDeltaForSale(saleId);
                                                final refundedVal = sums['refunded'] ?? 0.0;
                                                final addedVal = sums['added'] ?? 0.0;
                                                final currentItemsTotal = items.fold<double>(0.0, (p, it) {
                                                  final qty = (it['quantity'] as num?)?.toInt() ?? 0;
                                                  final price = (it['price'] as num?)?.toDouble() ?? 0.0;
                                                  return p + (qty * price);
                                                });

                                                final discountTypeRaw = (s['discount_type'] ?? 'fixed').toString();
                                                final discountValueRaw = (s['discount_value'] as num?)?.toDouble() ?? 0.0;

                                                final discountType = (discountTypeRaw == 'percent') ? 'percent' : 'fixed';
                                                double discountValue = discountValueRaw;
                                                if (discountValue.isNaN || discountValue.isInfinite) discountValue = 0.0;

                                                double discountAmount = 0.0;
                                                if (discountType == 'percent') {
                                                  discountAmount = currentItemsTotal * (discountValue / 100.0);
                                                } else {
                                                  discountAmount = discountValue;
                                                }
                                                if (discountAmount < 0) discountAmount = 0.0;
                                                if (discountAmount > currentItemsTotal) discountAmount = currentItemsTotal;

                                                final double effectiveTotalAfterDiscount = (currentItemsTotal - discountAmount).clamp(0.0, double.infinity);

                                                String discountLabel = '';
                                                if (discountAmount > 0) {
                                                  if (discountType == 'percent') {
                                                    discountLabel = ' • خصم ${discountValue.toStringAsFixed(2)}% (${discountAmount.toStringAsFixed(2)})';
                                                  } else {
                                                    discountLabel = ' • خصم ثابت (${discountAmount.toStringAsFixed(2)})';
                                                  }
                                                }

                                                final String paymentLabelWithDiscount = '$paymentLabel$discountLabel';

                                                final originalTotalBefore = (currentItemsTotal + refundedVal - addedVal);
                                                double originalPaidBefore;
                                                if (s.containsKey('original_paid')) {
                                                  originalPaidBefore = (s['original_paid'] as num?)?.toDouble() ?? (salePaidFromDB - paidDeltaSum);
                                                } else if (s.containsKey('paid_before')) {
                                                  originalPaidBefore = (s['paid_before'] as num?)?.toDouble() ?? (salePaidFromDB - paidDeltaSum);
                                                } else {
                                                  originalPaidBefore = salePaidFromDB - paidDeltaSum;
                                                }
                                                if (originalPaidBefore < 0) originalPaidBefore = 0.0;

                                                final double originalChangeGiven = (originalPaidBefore > originalTotalBefore) ? (originalPaidBefore - originalTotalBefore) : 0.0;

                                                final double displayOriginalPaid = (originalPaidBefore - originalChangeGiven).clamp(0.0, double.infinity);

                                                final double currentPaid = salePaidFromDB;

                                                final double displayEffectivePaid = (currentPaid - originalChangeGiven).clamp(0.0, double.infinity);

                                                final double paidDifference = displayEffectivePaid - displayOriginalPaid;
                                                final double absPaidDifference = paidDifference.abs();

                                                final double effectiveTotal = effectiveTotalAfterDiscount;
                                                final double effectiveRemaining = (displayEffectivePaid < effectiveTotal) ? (effectiveTotal - displayEffectivePaid) : 0.0;

                                                final double originalRemaining = (displayOriginalPaid < originalTotalBefore) ? (originalTotalBefore - displayOriginalPaid) : 0.0;
                                                if (loadingSaleItems.contains(saleId) || loadingSaleReturnItems.contains(saleId) || loadingSaleReturns.contains(saleId)) {
                                                  return const Padding(
                                                    padding: EdgeInsets.all(8.0),
                                                    child: Center(child: CircularProgressIndicator()),
                                                  );
                                                }
                                                final returnsById = _groupReturnItemsByReturnId(saleId);


                                                if (items.isEmpty && returnsById.isEmpty) {
                                                  return const Padding(
                                                    padding: EdgeInsets.all(8.0),
                                                    child: Text(
                                                      'لا توجد عناصر مسجلة لهذه الفاتورة',
                                                      style: TextStyle(color: Colors.white, fontSize: 20),
                                                    ),
                                                  );
                                                }




                                                Color badgeColor;
                                                IconData badgeIcon;
                                                String badgeText;
                                                if (paymentLabel == 'كرديت') {
                                                  badgeColor = Colors.blueAccent;
                                                  badgeIcon = Icons.credit_card;
                                                  badgeText = 'مدفوع إلكترونياً (بطاقة/بوابة)';
                                                } else if (paymentLabel == 'مدفوعة') {
                                                  badgeColor = Colors.green;
                                                  badgeIcon = Icons.attach_money;
                                                  badgeText = 'مدفوعة نقداً';
                                                } else {
                                                  badgeColor = Colors.orange;
                                                  badgeIcon = Icons.schedule;
                                                  badgeText = 'آجل (فاتورة مستحقة)';
                                                }

                                                final badgeFullText = '$badgeText$discountLabel';

                                                return Column(
                                                  crossAxisAlignment: CrossAxisAlignment.end,
                                                  children: [
                                                    const Text(' : عناصر الفاتورة الأصلية', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                                                    const SizedBox(height: 15),
                                                    ListView.separated(
                                                      shrinkWrap: true,
                                                      physics: const NeverScrollableScrollPhysics(),
                                                      itemCount: items.length,
                                                      separatorBuilder: (_, __) => Divider(
                                                        color: AppColorsDark.mainColor,
                                                      ),
                                                      itemBuilder: (context, i) {
                                                        final it = items[i];
                                                        final name = (it['product_name'] ?? 'منتج') as String;
                                                        final qty = (it['quantity'] as num?)?.toInt() ?? 0;
                                                        final price = (it['price'] as num?)?.toDouble() ?? 0.0;
                                                        final subtotal = qty * price;
                                                        final barcode = (it['product_barcode'] ?? '-') as String;
                                                        return Container(
                                                          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                                                          decoration: BoxDecoration(
                                                            color: Colors.transparent,
                                                            borderRadius: BorderRadius.circular(6),
                                                          ),
                                                          child: Column(
                                                            crossAxisAlignment: CrossAxisAlignment.stretch,
                                                            children: [
                                                              Row(
                                                                mainAxisAlignment: MainAxisAlignment.end,
                                                                crossAxisAlignment: CrossAxisAlignment.center,
                                                                children: [
                                                                  Expanded(
                                                                    child: RichText(
                                                                      textAlign: TextAlign.right,
                                                                      text: TextSpan(
                                                                        children: [
                                                                          TextSpan(
                                                                            text: name,
                                                                            style: const TextStyle(
                                                                              color: Colors.white70,
                                                                              fontSize: 15,
                                                                            ),
                                                                          ),
                                                                          const TextSpan(
                                                                            text: ' : الاسم',
                                                                            style: TextStyle(color: Colors.white, fontSize: 13),
                                                                          ),
                                                                        ],
                                                                      ),
                                                                      overflow: TextOverflow.ellipsis,
                                                                    ),
                                                                  ),
                                                                ],
                                                              ),
                                                              const SizedBox(height: 12),
                                                              buildLabelValue('باركود', barcode),
                                                              const SizedBox(height: 12),
                                                              RichText(
                                                                textAlign: TextAlign.right,
                                                                text: TextSpan(
                                                                  children: [
                                                                    TextSpan(
                                                                      text: "$qty × ${price.toStringAsFixed(2)}",
                                                                      style: const TextStyle(color: Colors.white70, fontSize: 15),
                                                                    ),
                                                                    const TextSpan(
                                                                      text: ' : الكميه',
                                                                      style: TextStyle(color: Colors.white, fontSize: 13),
                                                                    ),
                                                                  ],
                                                                ),
                                                                overflow: TextOverflow.ellipsis,
                                                              ),
                                                              const SizedBox(height: 12),
                                                              RichText(
                                                                textAlign: TextAlign.right,
                                                                text: TextSpan(
                                                                  children: [
                                                                    TextSpan(
                                                                      text: subtotal.toStringAsFixed(2),
                                                                      style: const TextStyle(color: Colors.white70, fontSize: 15),
                                                                    ),
                                                                    const TextSpan(
                                                                      text: ' : الإجمالي',
                                                                      style: TextStyle(color: Colors.white, fontSize: 13),
                                                                    ),
                                                                  ],
                                                                ),
                                                                overflow: TextOverflow.ellipsis,
                                                              ),
                                                            ],
                                                          ),
                                                        );
                                                      },
                                                    ),
                                                    const SizedBox(height: 12),
                                                    if (returnsById.isNotEmpty)
                                                      Divider(
                                                        color: AppColorsDark.mainColor,
                                                      ),
                                                    ...returnsById.entries.map((entry) {
                                                      final rid = entry.key;
                                                      final rows = entry.value;
                                                      final meta = returnsMeta.firstWhere((rm) => (rm['id'] as num).toInt() == rid, orElse: () => {});
                                                      final rDate = (meta['date'] ?? '') as String;
                                                      final returnedRows = rows.where((r) => (r['is_replacement'] as num?)?.toInt() == 0).toList();
                                                      final replacementRows = rows.where((r) => (r['is_replacement'] as num?)?.toInt() == 1).toList();

                                                      return Card(
                                                          margin: const EdgeInsets.symmetric(vertical: 6),
                                                          color: AppColorsDark.bgColor,
                                                          child: Padding(
                                                              padding: const EdgeInsets.all(8.0),
                                                              child: Directionality(
                                                                textDirection: TextDirection.rtl,
                                                                child: Column(
                                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                                  children: [
                                                                    Row(
                                                                      children: [
                                                                        const Icon(
                                                                          Icons.repeat,
                                                                          size: 18,
                                                                          color: Colors.white70,
                                                                        ),
                                                                        const SizedBox(width: 8),
                                                                        Column(
                                                                          crossAxisAlignment: CrossAxisAlignment.start,
                                                                          children: [
                                                                            RichText(
                                                                              text: TextSpan(
                                                                                children: [
                                                                                  const TextSpan(
                                                                                    text: 'اليوم: ',
                                                                                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                                                                  ),
                                                                                  TextSpan(
                                                                                    text: rDate.split('T').first,
                                                                                    style: const TextStyle(color: Colors.white70),
                                                                                  ),
                                                                                ],
                                                                              ),
                                                                            ),
                                                                            const SizedBox(height: 10),
                                                                            RichText(
                                                                              text: TextSpan(
                                                                                children: [
                                                                                  const TextSpan(
                                                                                    text: 'الوقت: ',
                                                                                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                                                                  ),
                                                                                  TextSpan(
                                                                                    text: DateFormat('hh:mm a').format(DateTime.parse(rDate)),
                                                                                    style: const TextStyle(color: Colors.white70),
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
                                                                      const Text(
                                                                        'العناصر المرجوعة:',
                                                                        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 17),
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
                                                                                const TextSpan(text: 'الاسم: ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                                                                TextSpan(text: name, style: const TextStyle(color: Colors.white70)),
                                                                              ]),
                                                                            ),
                                                                            const SizedBox(height: 10),
                                                                            RichText(
                                                                              text: TextSpan(children: [
                                                                                const TextSpan(text: 'الكمية: ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                                                                TextSpan(text: '$qty', style: const TextStyle(color: Colors.white70)),
                                                                              ]),
                                                                            ),
                                                                            const SizedBox(height: 10),
                                                                            RichText(
                                                                              text: TextSpan(children: [
                                                                                const TextSpan(text: 'السعر: ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                                                                TextSpan(text: price.toStringAsFixed(2), style: const TextStyle(color: Colors.white70)),
                                                                              ]),
                                                                            ),
                                                                            const SizedBox(height: 10),
                                                                            RichText(
                                                                              text: TextSpan(children: [
                                                                                const TextSpan(text: 'الإجمالي: ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                                                                TextSpan(text: total.toStringAsFixed(2), style: const TextStyle(color: Colors.white70)),
                                                                              ]),
                                                                            ),
                                                                            const SizedBox(height: 10),
                                                                          ],
                                                                        ),
                                                                      );
                                                                    }).toList(),
                                                                    if (replacementRows.isNotEmpty)
                                                                      const Padding(
                                                                        padding: EdgeInsets.only(top: 8.0),
                                                                        child: Text(
                                                                          'البدائل (مقابل المرجوع):',
                                                                          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 17),
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
                                                                                const TextSpan(text: 'الاسم: ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                                                                TextSpan(text: name, style: const TextStyle(color: Colors.white70)),
                                                                              ]),
                                                                            ),
                                                                            const SizedBox(height: 10),
                                                                            RichText(
                                                                              text: TextSpan(children: [
                                                                                const TextSpan(text: 'الكمية: ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                                                                TextSpan(text: '$qty', style: const TextStyle(color: Colors.white70)),
                                                                              ]),
                                                                            ),
                                                                            const SizedBox(height: 10),
                                                                            RichText(
                                                                              text: TextSpan(children: [
                                                                                const TextSpan(text: 'السعر: ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                                                                TextSpan(text: price.toStringAsFixed(2), style: const TextStyle(color: Colors.white70)),
                                                                              ]),
                                                                            ),
                                                                            const SizedBox(height: 10),
                                                                            RichText(
                                                                              text: TextSpan(children: [
                                                                                const TextSpan(text: 'الإجمالي: ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                                                                TextSpan(text: total.toStringAsFixed(2), style: const TextStyle(color: Colors.white70)),
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
                                                    const Divider(color: AppColorsDark.mainColor),
                                                    const SizedBox(height: 10),
                                                    Column(
                                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                                      children: [
                                                        const Text(
                                                          'ملخص مالي مبسّط',
                                                          textAlign: TextAlign.right,
                                                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Colors.white),
                                                        ),
                                                        const SizedBox(height: 12),
                                                        Row(
                                                          textDirection: TextDirection.rtl,
                                                          children: [
                                                            Expanded(
                                                              child: Column(
                                                                crossAxisAlignment: CrossAxisAlignment.end,
                                                                children: [
                                                                  const Text(':قبل الإجراء', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                                                                  const SizedBox(height: 10),
                                                                  Text(
                                                                    'إجمالي الفاتورة: ${originalTotalBefore.toStringAsFixed(2)}',
                                                                    textAlign: TextAlign.right,
                                                                    style: const TextStyle(color: Colors.white),
                                                                  ),
                                                                  const SizedBox(height: 10),
                                                                  Text('المشتري دفع: ${originalPaidBefore.toStringAsFixed(2)}',
                                                                      textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                                                                  const SizedBox(height: 10),
                                                                  if (originalChangeGiven > 0)
                                                                    Text(
                                                                      'الكاشير رجع للعميل: ${originalChangeGiven.toStringAsFixed(2)}',
                                                                      textAlign: TextAlign.right,
                                                                      style: const TextStyle(color: Colors.white70, fontStyle: FontStyle.italic),
                                                                    ),
                                                                  const SizedBox(height: 10),
                                                                ],
                                                              ),
                                                            ),
                                                            const SizedBox(width: 16),
                                                            Expanded(
                                                              child: Column(
                                                                crossAxisAlignment: CrossAxisAlignment.end,
                                                                children: [
                                                                  const Text(':بعد الإجراء', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                                                                  const SizedBox(height: 10),
                                                                  Text('إجمالي الفاتورة الآن: ${effectiveTotal.toStringAsFixed(2)}',
                                                                      textAlign: TextAlign.right, style: const TextStyle(color: Colors.white)),
                                                                  const SizedBox(height: 10),
                                                                  Builder(builder: (_) {
                                                                    if (paidDifference > 0) {
                                                                      return Text('المشتري دفع فرق: ${paidDifference.toStringAsFixed(2)}',
                                                                          textAlign: TextAlign.right, style: TextStyle(color: Colors.green, fontSize: 16));
                                                                    } else if (paidDifference < 0) {
                                                                      return Text('المشتري استلم فرق: ${absPaidDifference.toStringAsFixed(2)}',
                                                                          textAlign: TextAlign.right, style: TextStyle(color: Colors.red, fontSize: 16));
                                                                    } else {
                                                                      return const Text('لم يحدث فرق في المبلغ المدفوع',
                                                                          textAlign: TextAlign.right, style: TextStyle(fontSize: 16, color: Colors.white70));
                                                                    }
                                                                  }),
                                                                  if (originalRemaining.abs() > 0.001)
                                                                    Text('متبقي على العميل الآن: ${effectiveRemaining.toStringAsFixed(2)}',
                                                                        textAlign: TextAlign.right,
                                                                        style: TextStyle(color: (displayEffectivePaid < effectiveTotal) ? Colors.red : Colors.green)),
                                                                ],
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                        const SizedBox(height: 12),
                                                        const Divider(color: AppColorsDark.mainColor),
                                                        const SizedBox(height: 8),
                                                        Column(
                                                          crossAxisAlignment: CrossAxisAlignment.end,
                                                          children: [
                                                            Text(
                                                                '${cashier.isNotEmpty ? cashier : 'غير معروف'} : المسؤول عن العملية',
                                                                textAlign: TextAlign.right,
                                                                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                                                            const SizedBox(height: 15),
                                                            Builder(builder: (_) {
                                                              if (paidDeltaSum > 0) {
                                                                return Text(
                                                                    'أثناء الاستبدال/المرتجع، دفع المشتري مبلغًا إضافيًّا قدره ${paidDeltaSum.toStringAsFixed(2)} (الكاشير استلم هذا المبلغ).',
                                                                    textAlign: TextAlign.right,
                                                                    style: TextStyle(fontStyle: FontStyle.italic, color: Colors.white70, fontWeight: FontWeight.w300));
                                                              } else if (paidDeltaSum < 0) {
                                                                return Text('أثناء الاستبدال/المرتجع، أعاد/دفع الكاشير للمشتري مبلغًا قدره ${(-paidDeltaSum).toStringAsFixed(2)}.',
                                                                    textAlign: TextAlign.right,
                                                                    style: const TextStyle(fontStyle: FontStyle.italic, color: Colors.white70, fontWeight: FontWeight.w300));
                                                              } else {
                                                                return const Text('خلال العملية لم يحدث أي دفع/استلام نقدي إضافي',
                                                                    textAlign: TextAlign.right,
                                                                    style: TextStyle(fontStyle: FontStyle.italic, color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w300));
                                                              }
                                                            }),
                                                          ],
                                                        ),
                                                      ],
                                                    ),
                                                    const SizedBox(height: 12),
                                                    Align(
                                                      alignment: Alignment.centerRight,
                                                      child: Container(
                                                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                                                        decoration: BoxDecoration(
                                                          border: Border.all(color: badgeColor, width: 1.6),
                                                          color: badgeColor.withOpacity(0.08),
                                                          borderRadius: BorderRadius.circular(8),
                                                        ),
                                                        child: Row(
                                                          mainAxisSize: MainAxisSize.min,
                                                          children: [
                                                            Icon(badgeIcon, size: 18, color: badgeColor),
                                                            const SizedBox(width: 8),
                                                            Text(
                                                              badgeFullText,
                                                              style: TextStyle(color: badgeColor, fontWeight: FontWeight.bold),
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
                                  )
                              ),
                            );
                          }).toList(),
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
