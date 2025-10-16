import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:cashgo/utils/colors.dart';
import 'package:cashgo/models/product.dart';
import 'package:accordion_widget/accordion_widget.dart';
import 'package:shimmer/shimmer.dart';

import '../../services/Api/Admin/Products.dart';

// full-screen return dialog
import '../../widgets/Cashier/returndailog.dart';

class PreviousSalesScreen extends StatefulWidget {
  final String cashierUsername;
  const PreviousSalesScreen({super.key, required this.cashierUsername});

  @override
  State<PreviousSalesScreen> createState() => _PreviousSalesScreenState();
}

class _PreviousSalesScreenState extends State<PreviousSalesScreen> {
  bool loading = true;
  List<Map<String, dynamic>> sales = [];
  Map<int, List<Map<String, dynamic>>> saleItems = {};
  Map<String, List<Map<String, dynamic>>> groupedSales = {};
  DateTime selectedDate = DateTime.now();

  static const String apiBase = 'https://nabawisolution.com/invoice_reciept.php';

  @override
  void initState() {
    super.initState();
    _loadSales(date: selectedDate);
  }


  // ------------------ Load sales and normalize ------------------
  Future<void> _loadSales({DateTime? date}) async {
    setState(() => loading = true);

    final uri = Uri.parse('$apiBase?action=get_all_invoices');
    debugPrint('[PreviousSales] requesting: $uri');

    try {
      final resp = await http.get(uri).timeout(const Duration(seconds: 15));
      debugPrint('[PreviousSales] http status: ${resp.statusCode}');
      debugPrint('[PreviousSales] response body: ${resp.body}');

      if (resp.statusCode != 200) {
        if (!mounted) return;
        setState(() => loading = false);
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: Text('خطأ في الشبكة: ${resp.statusCode}'),
            content: SingleChildScrollView(child: Text(resp.body.isNotEmpty ? resp.body : 'لا يوجد محتوى')),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text('حسناً'))],
          ),
        );
        return;
      }

      final body = jsonDecode(resp.body);
      if (body == null || body is! Map || body['success'] != true || body['data'] == null) {
        throw Exception('استجابة غير متوقعة من السيرفر: ${resp.body}');
      }

      final List<dynamic> remote = List<dynamic>.from(body['data']);

      final List<Map<String, dynamic>> all = [];
      for (final e in remote) {
        if (e == null) continue;
        final Map<String, dynamic> raw = (e is Map<String, dynamic>) ? e : Map<String, dynamic>.from(e as Map);
        if (raw['id'] == null) continue;
        final int id = (raw['id'] as num).toInt();
        final String invoiceId = raw['invoice_id']?.toString() ?? '';

        // read meta/status fields (if present)
        final int isCanceled = (raw['is_canceled'] is num) ? (raw['is_canceled'] as num).toInt() : ((raw['status']?.toString() ?? '').toLowerCase() == 'canceled' ? 1 : 0);
        final String status = raw['status']?.toString() ?? '';
        final String type = raw['type']?.toString() ?? 'sale';
        final int? parentInvoiceId = (raw['parent_invoice_id'] is num) ? (raw['parent_invoice_id'] as num).toInt() : (raw['parent_invoice_id'] != null ? int.tryParse(raw['parent_invoice_id'].toString()) : null);
        final dynamic metaRaw = raw['meta'] ?? raw['meta_json'];

        // ====== SKIP CHILD/DERIVED INVOICES: do not include records that have a parent_invoice_id ======
        // This prevents showing both the original and the child (exchange/return) invoice.
        if (parentInvoiceId != null) {
          continue;
        }

        List<Map<String, dynamic>> prodList = [];
        final dynamic pl = raw['product_list'];
        if (pl is List) {
          for (final it in pl) {
            if (it == null) continue;
            final Map<String, dynamic> rIt = (it is Map<String, dynamic>) ? it : Map<String, dynamic>.from(it as Map);
            prodList.add({
              'product_id': (rIt['product_id'] is num) ? (rIt['product_id'] as num).toInt() : (int.tryParse(rIt['product_id']?.toString() ?? '') ?? 0),
              'product_name': (rIt['product_name'] ?? rIt['name'] ?? rIt['product'] ?? '').toString(),
              'barcode': rIt['barcode']?.toString() ?? '',
              'price': (rIt['price'] is num) ? (rIt['price'] as num).toDouble() : (double.tryParse(rIt['price']?.toString() ?? '') ?? 0.0),
              'qty': (rIt['qty'] is num) ? (rIt['qty'] as num).toInt() :
              (rIt['quantity'] is num) ? (rIt['quantity'] as num).toInt() :
              (int.tryParse(rIt['qty']?.toString() ?? '') ?? (int.tryParse(rIt['quantity']?.toString() ?? '') ?? 0)),
            });
          }
        } else if (pl is Map && pl.containsKey('items')) {
          // product_list stored as {meta:..., items: [...]}
          final itemsRaw = pl['items'];
          if (itemsRaw is List) {
            for (final it in itemsRaw) {
              if (it == null) continue;
              final Map<String, dynamic> rIt = (it is Map<String, dynamic>) ? it : Map<String, dynamic>.from(it as Map);
              prodList.add({
                'product_id': (rIt['product_id'] is num) ? (rIt['product_id'] as num).toInt() : (int.tryParse(rIt['product_id']?.toString() ?? '') ?? 0),
                'product_name': (rIt['product_name'] ?? rIt['name'] ?? rIt['product'] ?? '').toString(),
                'barcode': rIt['barcode']?.toString() ?? '',
                'price': (rIt['price'] is num) ? (rIt['price'] as num).toDouble() : (double.tryParse(rIt['price']?.toString() ?? '') ?? 0.0),
                'qty': (rIt['qty'] is num) ? (rIt['qty'] as num).toInt() :
                (rIt['quantity'] is num) ? (rIt['quantity'] as num).toInt() :
                (int.tryParse(rIt['qty']?.toString() ?? '') ?? (int.tryParse(rIt['quantity']?.toString() ?? '') ?? 0)),
              });
            }
          }
        }

        final double total = (raw['total'] is num) ? (raw['total'] as num).toDouble() : (double.tryParse(raw['total']?.toString() ?? '') ?? 0.0);
        final double paid = (raw['paid_amount'] is num) ? (raw['paid_amount'] as num).toDouble() : (double.tryParse(raw['paid_amount']?.toString() ?? '') ?? 0.0);
        final double change = (raw['change_amount'] is num) ? (raw['change_amount'] as num).toDouble() : (double.tryParse(raw['change_amount']?.toString() ?? '') ?? (paid - total));

        final String paymentType = raw['payment_type']?.toString() ?? '';
        final String cashierUsername = raw['cashier_username']?.toString() ?? '';
        final String dateStr = raw['date']?.toString() ?? '';
        final String updatedAt = raw['updated_at']?.toString() ?? '';

        all.add({
          'id': id,
          'invoice_id': invoiceId,
          'product_list': prodList,
          'total': total,
          'paid_amount': paid,
          'change_amount': change,
          'payment_type': paymentType,
          'cashier_username': cashierUsername,
          'date': dateStr,
          'updated_at': updatedAt,
          'is_canceled': isCanceled,
          'status': status,
          'type': type,
          'parent_invoice_id': parentInvoiceId,
          'meta': metaRaw
        });
      }

      // build saleItems map
      saleItems.clear();
      for (final s in all) {
        final id = (s['id'] as num).toInt();
        final prodList = s['product_list'];
        if (prodList is List) {
          final items = prodList.map<Map<String, dynamic>>((it) {
            if (it is Map<String, dynamic>) return it;
            return Map<String, dynamic>.from(it as Map);
          }).toList();
          saleItems[id] = items;
        } else {
          saleItems[id] = [];
        }
      }

      // filter out canceled invoices
      final List<Map<String, dynamic>> nonCanceled = all.where((s) {
        final int isc = (s['is_canceled'] is num) ? (s['is_canceled'] as num).toInt() : 0;
        final String st = (s['status']?.toString() ?? '').toLowerCase();
        return !(isc == 1 || st == 'canceled');
      }).toList();

      final List<Map<String, dynamic>> filtered = (date == null)
          ? nonCanceled
          : nonCanceled.where((s) => _matchesDate(s['date'], date)).toList();

      final Map<String, List<Map<String, dynamic>>> map = {};
      for (final s in filtered) {
        final cashierName = (s['cashier_username'] ?? s['username'] ?? s['cashier'] ?? s['user'] ?? 'Unknown').toString();
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
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('حسناً'))],
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
        final parts = s.split(RegExp(r'[\s/\\\-]')).where((p) => p.isNotEmpty).toList();
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

  Future<void> _ensureItems(int saleId) async {
    // lazy load items from server if not present or empty
    if (saleItems.containsKey(saleId) && (saleItems[saleId]?.isNotEmpty ?? false)) return;
    saleItems[saleId] = [];
    try {
      final uri = Uri.parse('$apiBase?action=get_invoice_items&id=$saleId');
      final resp = await http.get(uri).timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return;
      final decoded = jsonDecode(resp.body);
      if (decoded is Map && decoded['success'] == true && decoded['data'] is List) {
        final items = List<Map<String, dynamic>>.from(decoded['data'].map<Map<String, dynamic>>((e) {
          if (e is Map<String, dynamic>) return e;
          return Map<String, dynamic>.from(e as Map);
        }));
        saleItems[saleId] = items;
      }
    } catch (e) {
      debugPrint('Error loading items for $saleId: $e');
    }
  }

  void _openSaleDetails(Map<String, dynamic> sale) async {
    final saleId = (sale['id'] as num).toInt();
    await _ensureItems(saleId);

// القديم:
// final cashierName = (sale['cashier_username'] ?? widget.cashierUsername).toString();

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
            Text('#فاتورة رقم : $saleId', style: TextStyle(fontSize: 18, color: Colors.white)),
            Text(actorCashier, style: TextStyle(fontSize: 13, color: Colors.white70)),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('الإجمالي: ${(sale['total'] as num?)?.toDouble() ?? 0.0}', style: TextStyle(color: Colors.white)),
              const SizedBox(height: 8),
              Text('المدفوع: ${(sale['paid_amount'] as num?)?.toDouble() ?? 0.0}', style: TextStyle(color: Colors.white70)),
              const SizedBox(height: 12),
              const Text(':العناصر', style: TextStyle(color: Colors.white)),
              const SizedBox(height: 8),
              Builder(builder: (_) {
                final items = saleItems[saleId] ?? [];
                if (items.isEmpty) return const Text('لا توجد عناصر معروضة', style: TextStyle(color: Colors.white70));
                return SizedBox(
                  height: 260,
                  child: ListView.builder(
                    shrinkWrap: true,
                    physics: const ClampingScrollPhysics(),
                    itemCount: items.length,
                    itemBuilder: (_, i) {
                      final it = items[i];
                      final name = (it['product_name'] ?? it['name'] ?? it['product'] ?? 'Product').toString();
                      final qty = (it['qty'] as num?)?.toInt() ??
                          (it['quantity'] as num?)?.toInt() ??
                          (it['count'] as num?)?.toInt() ??
                          0;
                      final price = (it['price'] as num?)?.toDouble() ?? 0.0;
                      return ListTile(
                        title: Text(name, style: TextStyle(color: Colors.white)),
                        subtitle: Text('الكمية: $qty × ${price.toStringAsFixed(2)}', style: TextStyle(color: Colors.white70)),
                      );
                    },
                  ),
                );
              }),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إغلاق', style: TextStyle(color: Colors.white))),
          TextButton(
            onPressed: () async {
              if (Navigator.canPop(context)) Navigator.pop(context);
              // open return dialog as full-screen ProcessReturnDialog (uses ProductApi inside dialog)
              await _showProcessReturnDialog(saleId, actorCashier);
            },
            child: const Text('معالجة مرتجع / بدل', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _showProcessReturnDialog(int originalSaleId, String cashierName) async {
    // ensure items loaded
    await _ensureItems(originalSaleId);
    final items = saleItems[originalSaleId] ?? [];

    // open full-screen dialog/screen using ProcessReturnDialog (which now uses ProductApi and API calls)
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: AppColorsDark.bgColor,
          appBar: AppBar(
            title: Text('معالجة مرتجع / بدل', style: TextStyle(color: Colors.white)),
            backgroundColor: Colors.transparent,
            elevation: 0,
            iconTheme: IconThemeData(color: Colors.white70),
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
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تحديث الفواتير')));
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
    final picked = await showDatePicker(context: context, initialDate: selectedDate, firstDate: DateTime(2000), lastDate: DateTime(2100));
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
      if (m != null) return '${int.parse(m.group(3)!)}/${int.parse(m.group(2)!)}';
      return s;
    }
  }

  String _formatSelectedDate(DateTime dt) => '${dt.day}/${dt.month}/${dt.year}';

  Widget _buildShimmer() {
    // A shimmer skeleton roughly matching the layout of the actual UI
    return Directionality(
      textDirection: TextDirection.rtl,
      child: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              child: Shimmer.fromColors(
                baseColor: Colors.grey.shade800,
                highlightColor: Colors.grey.shade600,
                child: Column(
                  children: [
                    Container(height: 16, width: 120, color: Colors.grey.shade800),
                    const SizedBox(height: 8),
                    Container(height: 20, width: 180, color: Colors.grey.shade800),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            // show a few placeholder cashier cards
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              child: Column(
                children: List.generate(4, (index) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6.0),
                    child: Card(
                      color: AppColorsDark.bgCardColor,
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Shimmer.fromColors(
                          baseColor: AppColorsDark.bgColor,
                          highlightColor: AppColorsDark.mainColor.withOpacity(0.1),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(height: 22, width: 200, color: Colors.grey.shade800),
                              const SizedBox(height: 12),
                              Column(
                                children: List.generate(3, (i) {
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                                    child: Row(
                                      children: [
                                        Expanded(child: Container(height: 14, color: Colors.grey.shade800)),
                                        const SizedBox(width: 12),
                                        Container(height: 12, width: 60, color: Colors.grey.shade800),
                                      ],
                                    ),
                                  );
                                }),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColorsDark.bgColor,
      appBar: AppBar(
        title: Text('الفواتير السابقة', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            onPressed: () async => await _loadSales(date: selectedDate),
            icon: Icon(Icons.refresh, color: Colors.white70),
          ),
        ],
        iconTheme: IconThemeData(color: Colors.white70),
      ),
      body: loading
          ? _buildShimmer()
          : Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12.0),
            child: GestureDetector(
              onTap: _pickDate,
              child: Column(
                children: [
                  Text('التاريخ', style: TextStyle(color: Colors.white70)),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_formatSelectedDate(selectedDate), style: TextStyle(color: Colors.white)),
                      const SizedBox(width: 8),
                      Icon(Icons.calendar_today, size: 18, color: Colors.white70),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: groupedSales.isEmpty
                ? Center(child: Text('لا توجد فواتير', style: TextStyle(color: Colors.white70)))
                : ListView(
              children: groupedSales.entries.map((entry) {
                final cashierName = entry.key;
                final list = entry.value;

                // Use the accordion_widget package for each cashier group
                return Directionality(
                  textDirection: TextDirection.rtl,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
                    child: Card(
                      color: AppColorsDark.bgCardColor,
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: AccordionWidget(
                          showIcon: false,
                          decoration: BoxDecoration(
                              color: Colors.transparent
                          ),
                          header: AbsorbPointer(
                              absorbing: true,
                              child: Text('$cashierName (${list.length})',style: TextStyle(color: Colors.white,fontSize: 20),)),
                          // content: build list of invoices for this cashier
                          content: Column(
                            children: list.map((s) {
                              final saleId = (s['id'] as num).toInt();
                              final total = (s['total'] as num?)?.toDouble() ?? 0.0;
                              final paid = (s['paid_amount'] as num?)?.toDouble() ?? 0.0;
                              final type = (s['type'] ?? 'sale').toString();
                              final dayMonth = _formatDayMonth(s['date']);

                              return Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Theme(
                                  data: Theme.of(context).copyWith(hoverColor: AppColorsDark.mainColor.withOpacity(0.1)),
                                  child: ListTile(
                                    selectedColor: AppColorsDark.mainColor.withOpacity(0.1),
                                    splashColor: AppColorsDark.mainColor.withOpacity(0.1),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12), // <-- هنا تحدد الـ radius
                                    ),
                                    onTap: () => _openSaleDetails(s),
                                    title: Row(
                                      children: [
                                        Expanded(child: Text('#$saleId — $dayMonth', style: TextStyle(color: Colors.white))),
                                        if (type == 'return') const Icon(Icons.cancel, color: Colors.red),
                                        if (type == 'exchange') const Icon(Icons.swap_horiz, color: Colors.green),
                                        if (type == 'both') const Icon(Icons.sync, color: Colors.orange),
                                      ],
                                    ),
                                    subtitle: Text('الإجمالي: ${total.toStringAsFixed(2)} — المدفوع: ${paid.toStringAsFixed(2)}', style: TextStyle(color: Colors.white70)),
                                    trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.white70),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
