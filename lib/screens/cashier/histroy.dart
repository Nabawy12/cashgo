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
          'type': (raw['is_return'] == 1) ? 'return' : 'sale',
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

  void _openSaleDetails(Map<String, dynamic> sale) async {
    final saleId = (sale['id'] as num).toInt();
    await _ensureItems(saleId);

    // الجديد: استخدم دائماً اسم الكاشير الحالي (actor) من الـ widget
    final actorCashier = widget.cashierUsername.toString();

    // إذا رغبت تعرض صاحب الفاتورة في العنوان يمكنك حفظه أيضاً:
    final originalCashier = (sale['cashier_username'] ?? '').toString();

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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
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
                  height: 260,
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
                      final price = (it['price'] as num?)?.toDouble() ?? 0.0;
                      return ListTile(
                        title:
                            Text(name, style: TextStyle(color: _cardTextColor)),
                        subtitle: Text(
                            'الكمية: $qty × ${price.toStringAsFixed(2)}',
                            style: TextStyle(color: _cardLabelColor)),
                      );
                    },
                  ),
                );
              }),
            ],
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
          TextButton(
            onPressed: () async {
              if (Navigator.canPop(context)) Navigator.pop(context);
              // open return dialog as full-screen ProcessReturnDialog (uses ProductApi inside dialog)
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
    // ensure items loaded
    await _ensureItems(originalSaleId);
    final items = saleItems[originalSaleId] ?? [];

    // open full-screen dialog/screen using ProcessReturnDialog (which now uses ProductApi and API calls)
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
                // simply refresh local sales/items when dialog signals done
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
                      final type = (s['type'] ?? 'sale').toString();
                      final dayMonth = _formatDayMonth(s['date']);

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
                                if (type == 'return')
                                  const Icon(Icons.cancel, color: Colors.red),
                                if (type == 'exchange')
                                  const Icon(Icons.swap_horiz,
                                      color: Colors.green),
                                if (type == 'both')
                                  const Icon(Icons.sync, color: Colors.orange),
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
