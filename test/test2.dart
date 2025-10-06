// // PreviousSalesGroupedByCashier.dart
// import 'dart:convert';
// import 'package:flutter/material.dart';
// import 'package:http/http.dart' as http;
// import 'package:cashgo/utils/colors.dart';
// import 'package:cashgo/models/product.dart';
//
// import '../../services/Api/Admin/Products.dart';
//
// class PreviousSalesScreen extends StatefulWidget {
//   final String cashierUsername;
//   const PreviousSalesScreen({super.key, required this.cashierUsername});
//
//   @override
//   State<PreviousSalesScreen> createState() => _PreviousSalesScreenState();
// }
//
// class _PreviousSalesScreenState extends State<PreviousSalesScreen> {
//   bool loading = true;
//   List<Map<String, dynamic>> sales = [];
//   Map<int, List<Map<String, dynamic>>> saleItems = {};
//   Map<String, List<Map<String, dynamic>>> groupedSales = {};
//   DateTime selectedDate = DateTime.now();
//
//   static const String apiBase = 'https://nabawisolution.com/invoice_reciept.php';
//
//   @override
//   void initState() {
//     super.initState();
//     _loadSales(date: null);
//   }
//
//   // ------------------ Load sales and normalize ------------------
//   Future<void> _loadSales({DateTime? date}) async {
//     setState(() => loading = true);
//
//     final uri = Uri.parse('$apiBase?action=get_all_invoices');
//     debugPrint('[PreviousSales] requesting: $uri');
//
//     try {
//       final resp = await http.get(uri).timeout(const Duration(seconds: 15));
//       debugPrint('[PreviousSales] http status: ${resp.statusCode}');
//       debugPrint('[PreviousSales] response body: ${resp.body}');
//
//       if (resp.statusCode != 200) {
//         if (!mounted) return;
//         setState(() => loading = false);
//         showDialog(
//           context: context,
//           builder: (_) => AlertDialog(
//             title: Text('خطأ في الشبكة: ${resp.statusCode}'),
//             content: SingleChildScrollView(child: Text(resp.body.isNotEmpty ? resp.body : 'لا يوجد محتوى')),
//             actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text('حسناً'))],
//           ),
//         );
//         return;
//       }
//
//       final body = jsonDecode(resp.body);
//       if (body == null || body is! Map || body['success'] != true || body['data'] == null) {
//         throw Exception('استجابة غير متوقعة من السيرفر: ${resp.body}');
//       }
//
//       final List<dynamic> remote = List<dynamic>.from(body['data']);
//
//       final List<Map<String, dynamic>> all = [];
//       for (final e in remote) {
//         if (e == null) continue;
//         final Map<String, dynamic> raw = (e is Map<String, dynamic>) ? e : Map<String, dynamic>.from(e as Map);
//         if (raw['id'] == null) continue;
//         final int id = (raw['id'] as num).toInt();
//         final String invoiceId = raw['invoice_id']?.toString() ?? '';
//
//         // read meta/status fields (if present)
//         final int isCanceled = (raw['is_canceled'] is num) ? (raw['is_canceled'] as num).toInt() : ((raw['status']?.toString() ?? '').toLowerCase() == 'canceled' ? 1 : 0);
//         final String status = raw['status']?.toString() ?? '';
//         final String type = raw['type']?.toString() ?? 'sale';
//         final int? parentInvoiceId = (raw['parent_invoice_id'] is num) ? (raw['parent_invoice_id'] as num).toInt() : (raw['parent_invoice_id'] != null ? int.tryParse(raw['parent_invoice_id'].toString()) : null);
//         final dynamic metaRaw = raw['meta'] ?? raw['meta_json'];
//
//         List<Map<String, dynamic>> prodList = [];
//         final dynamic pl = raw['product_list'];
//         if (pl is List) {
//           for (final it in pl) {
//             if (it == null) continue;
//             final Map<String, dynamic> rIt = (it is Map<String, dynamic>) ? it : Map<String, dynamic>.from(it as Map);
//             prodList.add({
//               'product_id': (rIt['product_id'] is num) ? (rIt['product_id'] as num).toInt() : (int.tryParse(rIt['product_id']?.toString() ?? '') ?? 0),
//               'product_name': (rIt['product_name'] ?? rIt['name'] ?? rIt['product'] ?? '').toString(),
//               'barcode': rIt['barcode']?.toString() ?? '',
//               'price': (rIt['price'] is num) ? (rIt['price'] as num).toDouble() : (double.tryParse(rIt['price']?.toString() ?? '') ?? 0.0),
//               'qty': (rIt['qty'] is num) ? (rIt['qty'] as num).toInt() :
//               (rIt['quantity'] is num) ? (rIt['quantity'] as num).toInt() :
//               (int.tryParse(rIt['qty']?.toString() ?? '') ?? (int.tryParse(rIt['quantity']?.toString() ?? '') ?? 0)),
//             });
//           }
//         } else if (pl is Map && pl.containsKey('items')) {
//           // product_list stored as {meta:..., items: [...]}
//           final itemsRaw = pl['items'];
//           if (itemsRaw is List) {
//             for (final it in itemsRaw) {
//               if (it == null) continue;
//               final Map<String, dynamic> rIt = (it is Map<String, dynamic>) ? it : Map<String, dynamic>.from(it as Map);
//               prodList.add({
//                 'product_id': (rIt['product_id'] is num) ? (rIt['product_id'] as num).toInt() : (int.tryParse(rIt['product_id']?.toString() ?? '') ?? 0),
//                 'product_name': (rIt['product_name'] ?? rIt['name'] ?? rIt['product'] ?? '').toString(),
//                 'barcode': rIt['barcode']?.toString() ?? '',
//                 'price': (rIt['price'] is num) ? (rIt['price'] as num).toDouble() : (double.tryParse(rIt['price']?.toString() ?? '') ?? 0.0),
//                 'qty': (rIt['qty'] is num) ? (rIt['qty'] as num).toInt() :
//                 (rIt['quantity'] is num) ? (rIt['quantity'] as num).toInt() :
//                 (int.tryParse(rIt['qty']?.toString() ?? '') ?? (int.tryParse(rIt['quantity']?.toString() ?? '') ?? 0)),
//               });
//             }
//           }
//         }
//
//         final double total = (raw['total'] is num) ? (raw['total'] as num).toDouble() : (double.tryParse(raw['total']?.toString() ?? '') ?? 0.0);
//         final double paid = (raw['paid_amount'] is num) ? (raw['paid_amount'] as num).toDouble() : (double.tryParse(raw['paid_amount']?.toString() ?? '') ?? 0.0);
//         final double change = (raw['change_amount'] is num) ? (raw['change_amount'] as num).toDouble() : (double.tryParse(raw['change_amount']?.toString() ?? '') ?? (paid - total));
//
//         final String paymentType = raw['payment_type']?.toString() ?? '';
//         final String cashierUsername = raw['cashier_username']?.toString() ?? '';
//         final String dateStr = raw['date']?.toString() ?? '';
//         final String updatedAt = raw['updated_at']?.toString() ?? '';
//
//         all.add({
//           'id': id,
//           'invoice_id': invoiceId,
//           'product_list': prodList,
//           'total': total,
//           'paid_amount': paid,
//           'change_amount': change,
//           'payment_type': paymentType,
//           'cashier_username': cashierUsername,
//           'date': dateStr,
//           'updated_at': updatedAt,
//           'is_canceled': isCanceled,
//           'status': status,
//           'type': type,
//           'parent_invoice_id': parentInvoiceId,
//           'meta': metaRaw
//         });
//       }
//
//       // build saleItems map
//       saleItems.clear();
//       for (final s in all) {
//         final id = (s['id'] as num).toInt();
//         final prodList = s['product_list'];
//         if (prodList is List) {
//           final items = prodList.map<Map<String, dynamic>>((it) {
//             if (it is Map<String, dynamic>) return it;
//             return Map<String, dynamic>.from(it as Map);
//           }).toList();
//           saleItems[id] = items;
//         } else {
//           saleItems[id] = [];
//         }
//       }
//
//       // filter out canceled invoices
//       final List<Map<String, dynamic>> nonCanceled = all.where((s) {
//         final int isc = (s['is_canceled'] is num) ? (s['is_canceled'] as num).toInt() : 0;
//         final String st = (s['status']?.toString() ?? '').toLowerCase();
//         return !(isc == 1 || st == 'canceled');
//       }).toList();
//
//       final List<Map<String, dynamic>> filtered = (date == null)
//           ? nonCanceled
//           : nonCanceled.where((s) => _matchesDate(s['date'], date)).toList();
//
//       final Map<String, List<Map<String, dynamic>>> map = {};
//       for (final s in filtered) {
//         final cashierName = (s['cashier_username'] ?? s['username'] ?? s['cashier'] ?? s['user'] ?? 'Unknown').toString();
//         map.putIfAbsent(cashierName, () => []);
//         map[cashierName]!.add(s);
//       }
//
//       if (!mounted) return;
//       setState(() {
//         sales = filtered.cast<Map<String, dynamic>>();
//         groupedSales = map;
//         loading = false;
//       });
//     } catch (e, st) {
//       debugPrint('Error in _loadSales: $e\n$st');
//       if (!mounted) return;
//       setState(() => loading = false);
//       showDialog(
//         context: context,
//         builder: (_) => AlertDialog(
//           title: const Text('خطأ في تحميل الفواتير'),
//           content: SingleChildScrollView(child: Text(e.toString())),
//           actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('حسناً'))],
//         ),
//       );
//     }
//   }
//
//   bool _matchesDate(dynamic rawDate, DateTime date) {
//     if (rawDate == null) return false;
//     final s = rawDate.toString();
//     DateTime? dt;
//     try {
//       dt = DateTime.parse(s);
//     } catch (_) {
//       final m = RegExp(r'(\d{4})-(\d{2})-(\d{2})').firstMatch(s);
//       if (m != null) {
//         final y = int.tryParse(m.group(1) ?? '0') ?? 0;
//         final mo = int.tryParse(m.group(2) ?? '0') ?? 0;
//         final d = int.tryParse(m.group(3) ?? '0') ?? 0;
//         dt = DateTime(y, mo, d);
//       } else {
//         final parts = s.split(RegExp(r'[\s/\\\-]')).where((p) => p.isNotEmpty).toList();
//         if (parts.length >= 3) {
//           if (parts[0].length == 4) {
//             final y = int.tryParse(parts[0]) ?? 0;
//             final mo = int.tryParse(parts[1]) ?? 0;
//             final d = int.tryParse(parts[2]) ?? 0;
//             dt = DateTime(y, mo, d);
//           } else {
//             final d = int.tryParse(parts[0]) ?? 0;
//             final mo = int.tryParse(parts[1]) ?? 0;
//             final y = int.tryParse(parts[2]) ?? 0;
//             dt = DateTime(y, mo, d);
//           }
//         }
//       }
//     }
//     if (dt == null) return false;
//     return dt.year == date.year && dt.month == date.month && dt.day == date.day;
//   }
//
//   Future<void> _ensureItems(int saleId) async {
//     // lazy load items from server if not present or empty
//     if (saleItems.containsKey(saleId) && (saleItems[saleId]?.isNotEmpty ?? false)) return;
//     saleItems[saleId] = [];
//     try {
//       final uri = Uri.parse('$apiBase?action=get_invoice_items&id=$saleId');
//       final resp = await http.get(uri).timeout(const Duration(seconds: 10));
//       if (resp.statusCode != 200) return;
//       final decoded = jsonDecode(resp.body);
//       if (decoded is Map && decoded['success'] == true && decoded['data'] is List) {
//         final items = List<Map<String, dynamic>>.from(decoded['data'].map<Map<String, dynamic>>((e) {
//           if (e is Map<String, dynamic>) return e;
//           return Map<String, dynamic>.from(e as Map);
//         }));
//         saleItems[saleId] = items;
//       }
//     } catch (e) {
//       debugPrint('Error loading items for $saleId: $e');
//     }
//   }
//
//   // ------------------ Process Return API call ------------------
//   Future<Map<String, dynamic>> _processReturn({
//     required int originalInvoiceId,
//     required List<Map<String, dynamic>> returnItems,
//     required List<Map<String, dynamic>> exchangeItems,
//     required double refundAmount,
//     required String cashierUsername,
//     String paymentMethod = 'cash',
//     double paid = 0.0,
//     String returnNote = '',
//     bool debug = false,
//   }) async {
//     final uri = Uri.parse(apiBase);
//     final body = {
//       'action': 'process_return',
//       'original_invoice_id': originalInvoiceId,
//       'return_items': returnItems,
//       'exchange_items': exchangeItems,
//       'refund_amount': refundAmount,
//       'paid': paid,
//       'paymentMethod': paymentMethod,
//       'cashierUsername': cashierUsername,
//       'return_note': returnNote,
//       'debug': debug,
//     };
//
//     final resp = await http.post(uri, headers: {'Content-Type': 'application/json'}, body: jsonEncode(body)).timeout(const Duration(seconds: 20));
//     debugPrint('[processReturn] status=${resp.statusCode} body=${resp.body}');
//     if (resp.statusCode != 200) {
//       throw Exception('Server error ${resp.statusCode}: ${resp.body}');
//     }
//     final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
//     if (decoded['success'] != true) {
//       throw Exception(decoded['error'] ?? decoded['message'] ?? 'Unknown error');
//     }
//     return decoded;
//   }
//
//   // ------------------ UI: open sale details + process return dialog ------------------
//   void _openSaleDetails(Map<String, dynamic> sale) async {
//     final saleId = (sale['id'] as num).toInt();
//     await _ensureItems(saleId);
//
//     final cashierName = (sale['cashier_username'] ?? widget.cashierUsername).toString();
//
//     await showDialog(
//       context: context,
//       builder: (_) => AlertDialog(
//         backgroundColor: AppColorsDark.bgCardColor,
//         title: Row(
//           mainAxisAlignment: MainAxisAlignment.spaceBetween,
//           children: [
//             Text('#فاتورة رقم : $saleId', style: TextStyle(fontSize: 18, color: Colors.white)),
//             Text(cashierName, style: TextStyle(fontSize: 13, color: Colors.white70)),
//           ],
//         ),
//         content: SizedBox(
//           width: double.maxFinite,
//           child: Column(
//             mainAxisSize: MainAxisSize.min,
//             children: [
//               Text('الإجمالي: ${(sale['total'] as num?)?.toDouble() ?? 0.0}', style: TextStyle(color: Colors.white)),
//               const SizedBox(height: 8),
//               Text('المدفوع: ${(sale['paid_amount'] as num?)?.toDouble() ?? 0.0}', style: TextStyle(color: Colors.white70)),
//               const SizedBox(height: 12),
//               const Text(':العناصر', style: TextStyle(color: Colors.white)),
//               const SizedBox(height: 8),
//               Builder(builder: (_) {
//                 final items = saleItems[saleId] ?? [];
//                 if (items.isEmpty) return const Text('لا توجد عناصر معروضة', style: TextStyle(color: Colors.white70));
//                 return SizedBox(
//                   height: 260,
//                   child: ListView.builder(
//                     shrinkWrap: true,
//                     physics: const ClampingScrollPhysics(),
//                     itemCount: items.length,
//                     itemBuilder: (_, i) {
//                       final it = items[i];
//                       final name = (it['product_name'] ?? it['name'] ?? it['product'] ?? 'Product').toString();
//                       final qty = (it['qty'] as num?)?.toInt() ??
//                           (it['quantity'] as num?)?.toInt() ??
//                           (it['count'] as num?)?.toInt() ??
//                           0;
//                       final price = (it['price'] as num?)?.toDouble() ?? 0.0;
//                       return ListTile(
//                         title: Text(name, style: TextStyle(color: Colors.white)),
//                         subtitle: Text('الكمية: $qty × ${price.toStringAsFixed(2)}', style: TextStyle(color: Colors.white70)),
//                       );
//                     },
//                   ),
//                 );
//               }),
//             ],
//           ),
//         ),
//         actions: [
//           TextButton(onPressed: () => Navigator.pop(context), child: const Text('إغلاق', style: TextStyle(color: Colors.white))),
//           TextButton(
//             onPressed: () async {
//               if (Navigator.canPop(context)) Navigator.pop(context);
//               // open return dialog directly (no manual delay)
//               await _showProcessReturnDialog(saleId, cashierName);
//             },
//             child: const Text('معالجة مرتجع / بدل', style: TextStyle(color: Colors.white)),
//           ),
//         ],
//       ),
//     );
//   }
//
//   void _applyReturnExchangeLocally(int saleId, List<Map<String, dynamic>> returns, List<Map<String, dynamic>> exchanges) {
//     // تحديث saleItems (قائمة العناصر المعروضة) بتطبيق المرتجعات والاستبدالات محليًا
//     final current = List<Map<String, dynamic>>.from(saleItems[saleId] ?? []);
//
//     // تطبيق المرتجعات: نقص الكميات أو احذف العنصر إن صارت الكمية <= 0
//     for (final ret in returns) {
//       final pid = (ret['product_id'] is num) ? (ret['product_id'] as num).toInt() : int.tryParse(ret['product_id']?.toString() ?? '') ?? 0;
//       final rqty = (ret['qty'] is num) ? (ret['qty'] as num).toInt() : int.tryParse(ret['qty']?.toString() ?? '') ?? 0;
//       for (int i = current.length - 1; i >= 0; i--) {
//         final it = current[i];
//         final ipid = (it['product_id'] is num) ? (it['product_id'] as num).toInt() : int.tryParse(it['product_id']?.toString() ?? '') ?? 0;
//         if (ipid != pid) continue;
//         final existingQty = (it['qty'] is num) ? (it['qty'] as num).toInt() : int.tryParse(it['qty']?.toString() ?? '') ?? 0;
//         final newQty = existingQty - rqty;
//         if (newQty <= 0) {
//           current.removeAt(i);
//         } else {
//           current[i] = {...it, 'qty': newQty};
//         }
//         break;
//       }
//     }
//
//     // تطبيق الاستبدالات: أضف العناصر الجديدة كعناصر في الفاتورة
//     for (final ex in exchanges) {
//       final pid = (ex['product_id'] is num) ? (ex['product_id'] as num).toInt() : int.tryParse(ex['product_id']?.toString() ?? '') ?? 0;
//       final name = (ex['name'] ?? '').toString();
//       final price = (ex['price'] is num) ? (ex['price'] as num).toDouble() : double.tryParse(ex['price']?.toString() ?? '') ?? 0.0;
//       final qty = (ex['qty'] is num) ? (ex['qty'] as num).toInt() : int.tryParse(ex['qty']?.toString() ?? '') ?? 0;
//       if (pid <= 0 || qty <= 0) continue;
//       bool merged = false;
//       for (int i = 0; i < current.length; i++) {
//         final it = current[i];
//         final ipid = (it['product_id'] is num) ? (it['product_id'] as num).toInt() : int.tryParse(it['product_id']?.toString() ?? '') ?? 0;
//         if (ipid == pid) {
//           final existingQty = (it['qty'] is num) ? (it['qty'] as num).toInt() : int.tryParse(it['qty']?.toString() ?? '') ?? 0;
//           current[i] = {...it, 'qty': existingQty + qty, 'price': price};
//           merged = true;
//           break;
//         }
//       }
//       if (!merged) {
//         current.add({
//           'product_id': pid,
//           'product_name': name,
//           'qty': qty,
//           'price': price,
//           'barcode': '',
//         });
//       }
//     }
//
//     // حفظ التعديل محليًا
//     saleItems[saleId] = current;
//
//     // إذا ما بقى عناصر -> احذف الفاتورة محليًا من lists
//     if (current.isEmpty) {
//       sales.removeWhere((s) => (s['id'] as num).toInt() == saleId);
//     } else {
//       // تحديث sales: إعادة حساب المجموع المحلي التقريبي
//       for (int i = 0; i < sales.length; i++) {
//         if ((sales[i]['id'] as num).toInt() == saleId) {
//           double newTotal = 0.0;
//           for (final it in current) {
//             final p = (it['price'] is num) ? (it['price'] as num).toDouble() : double.tryParse(it['price']?.toString() ?? '') ?? 0.0;
//             final q = (it['qty'] is num) ? (it['qty'] as num).toInt() : int.tryParse(it['qty']?.toString() ?? '') ?? 0;
//             newTotal += p * q;
//           }
//           sales[i] = {...sales[i], 'product_list': current, 'total': newTotal};
//           break;
//         }
//       }
//     }
//
//     // إعادة تجميع groupedSales بسرعة
//     final Map<String, List<Map<String, dynamic>>> map = {};
//     for (final s in sales) {
//       final cashierName = (s['cashier_username'] ?? s['username'] ?? s['cashier'] ?? s['user'] ?? 'Unknown').toString();
//       map.putIfAbsent(cashierName, () => []);
//       map[cashierName]!.add(s);
//     }
//     setState(() {
//       groupedSales = map;
//     });
//   }
//
//   // ------------------ New: dialog to lookup product by barcode and return exchange item ------------------
//   Future<Map<String, dynamic>?> _showAddExchangeItemDialog(BuildContext ctx) async {
//     final TextEditingController barcodeController = TextEditingController();
//     final TextEditingController qtyController = TextEditingController(text: '1');
//     final TextEditingController priceController = TextEditingController(text: '0.0');
//
//     bool loadingProduct = false;
//     Map<String, dynamic>? foundProduct;
//     String? errorMsg;
//
//     return showDialog<Map<String, dynamic>>(
//       context: ctx,
//       barrierDismissible: false,
//       builder: (dialogCtx) {
//         return StatefulBuilder(builder: (dialogCtx, setStateDialog) {
//           Future<void> lookupByBarcode() async {
//             final code = barcodeController.text.trim();
//             if (code.isEmpty) {
//               setStateDialog(() { errorMsg = 'ادخل الباركود'; });
//               return;
//             }
//             setStateDialog(() { loadingProduct = true; errorMsg = null; foundProduct = null; });
//             try {
//               final apiResp = await ProductApi.getProductByBarcode(code);
//               if (apiResp == null) {
//                 setStateDialog(() { errorMsg = 'لم يتم العثور على المنتج بالباركود'; foundProduct = null; });
//               } else {
//                 final prod = Product.fromMap(apiResp);
//                 foundProduct = {
//                   'product_id': prod.id,
//                   'name': prod.name ?? '',
//                   'barcode': prod.barcode ?? code,
//                   'price': prod.sellingPrice?.toDouble() ?? 0.0,
//                   'available': prod.totalUnits ?? 0
//                 };
//                 priceController.text = (foundProduct!['price'] as double).toString();
//                 qtyController.text = '1';
//                 setStateDialog(() { errorMsg = null; });
//               }
//             } catch (e) {
//               setStateDialog(() { errorMsg = 'خطأ في الاتصال أو الاستجابة'; foundProduct = null; });
//             } finally {
//               setStateDialog(() { loadingProduct = false; });
//             }
//           }
//
//           return AlertDialog(
//             backgroundColor: AppColorsDark.bgCardColor,
//             title: Text('أضف عنصر استبدال بالباركود', style: TextStyle(color: Colors.white)),
//             content: ConstrainedBox(
//               constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7, maxWidth: MediaQuery.of(ctx).size.width * 0.8),
//               child: SingleChildScrollView(
//                 child: Column(
//                   crossAxisAlignment: CrossAxisAlignment.start,
//                   children: [
//                     Row(children: [
//                       Expanded(
//                         child: TextField(
//                           controller: barcodeController,
//                           keyboardType: TextInputType.text,
//                           decoration: InputDecoration(labelText: 'باركود', labelStyle: TextStyle(color: Colors.white70)),
//                           style: TextStyle(color: Colors.white),
//                           onSubmitted: (_) => lookupByBarcode(),
//                         ),
//                       ),
//                       const SizedBox(width: 8),
//                       ElevatedButton(
//                         onPressed: loadingProduct ? null : () => lookupByBarcode(),
//                         child: loadingProduct ? SizedBox(width:16, height:16, child: CircularProgressIndicator(strokeWidth:2)) : Text('بحث'),
//                       ),
//                     ]),
//                     if (errorMsg != null) ...[
//                       const SizedBox(height: 8),
//                       Text(errorMsg!, style: TextStyle(color: Colors.redAccent)),
//                     ],
//                     const SizedBox(height: 12),
//                     if (foundProduct != null) ...[
//                       Text('المنتج: ${foundProduct!['name']}', style: TextStyle(color: Colors.white)),
//                       const SizedBox(height: 6),
//                       Text('متاح: ${foundProduct!['available']}', style: TextStyle(color: Colors.white70)),
//                       const SizedBox(height: 8),
//                       Row(
//                         children: [
//                           SizedBox(
//                             width: 100,
//                             child: TextField(
//                               controller: qtyController,
//                               keyboardType: TextInputType.number,
//                               style: TextStyle(color: Colors.white),
//                               decoration: InputDecoration(labelText: 'الكمية', labelStyle: TextStyle(color: Colors.white70)),
//                             ),
//                           ),
//                           const SizedBox(width: 12),
//                           SizedBox(
//                             width: 120,
//                             child: TextField(
//                               controller: priceController,
//                               keyboardType: TextInputType.numberWithOptions(decimal: true),
//                               style: TextStyle(color: Colors.white),
//                               decoration: InputDecoration(labelText: 'السعر', labelStyle: TextStyle(color: Colors.white70)),
//                             ),
//                           ),
//                         ],
//                       ),
//                       const SizedBox(height: 8),
//                       Text('(اضبط الكمية والسعر قبل الإضافة)', style: TextStyle(color: Colors.white54)),
//                     ] else ...[
//                       Text('ابحث أولاً عن المنتج بالباركود ثم أضفه.', style: TextStyle(color: Colors.white70)),
//                     ],
//                   ],
//                 ),
//               ),
//             ),
//             actions: [
//               TextButton(
//                 onPressed: () {
//                   barcodeController.dispose();
//                   qtyController.dispose();
//                   priceController.dispose();
//                   Navigator.pop(dialogCtx, null);
//                 },
//                 child: Text('إلغاء', style: TextStyle(color: Colors.white)),
//               ),
//               TextButton(
//                 onPressed: foundProduct == null ? null : () {
//                   final available = (foundProduct!['available'] ?? 0) as int;
//                   final qty = int.tryParse(qtyController.text.trim()) ?? 0;
//                   final price = double.tryParse(priceController.text.trim()) ?? (foundProduct!['price'] as double? ?? 0.0);
//                   if (qty <= 0) {
//                     ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('ادخل كمية صحيحة')));
//                     return;
//                   }
//                   if (qty > available) {
//                     ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('الكمية أكبر من المتاح ($available)')));
//                     return;
//                   }
//                   final out = {
//                     'product_id': (foundProduct!['product_id'] ?? 0),
//                     'name': foundProduct!['name'] ?? '',
//                     'barcode': foundProduct!['barcode'] ?? '',
//                     'qty': qty,
//                     'price': price
//                   };
//                   barcodeController.dispose();
//                   qtyController.dispose();
//                   priceController.dispose();
//                   Navigator.pop(dialogCtx, out);
//                 },
//                 child: Text('أضف', style: TextStyle(color: Colors.white)),
//               ),
//             ],
//           );
//         });
//       },
//     );
//   }
//
//   Future<void> _showProcessReturnDialog(int originalSaleId, String cashierName) async {
//     final items = saleItems[originalSaleId] ?? [];
//     final List<bool> selected = List<bool>.generate(items.length, (_) => false);
//     final List<TextEditingController> qtyControllers = List.generate(items.length, (i) => TextEditingController(text: (items[i]['qty'] ?? 0).toString()));
//     final List<Map<String, dynamic>> exchangeItems = [];
//     final refundController = TextEditingController(text: '0.0');
//     final noteController = TextEditingController();
//
//     String mode = 'return'; // 'return' | 'exchange' | 'both'
//
//     bool submitting = false;
//
//     await showDialog(
//       context: context,
//       barrierDismissible: false, // important: prevent accidental dismiss
//       builder: (context) {
//         return StatefulBuilder(builder: (context, setStateDialog) {
//           return AlertDialog(
//             backgroundColor: AppColorsDark.bgCardColor,
//             title: Text('معالجة مرتجع / بدل', style: TextStyle(color: Colors.white)),
//             content: ConstrainedBox(
//               constraints: BoxConstraints(
//                 maxHeight: MediaQuery.of(context).size.height * 0.8,
//                 minWidth: MediaQuery.of(context).size.width * 0.3,
//               ),
//               child: SingleChildScrollView(
//                 child: SizedBox(
//                   width: double.maxFinite,
//                   child: Column(
//                     crossAxisAlignment: CrossAxisAlignment.start,
//                     children: [
//                       // Choice chips to select mode
//                       Wrap(
//                         spacing: 8,
//                         children: [
//                           ChoiceChip(
//                             label: Text('ارجاع', style: TextStyle(color: mode == 'return' ? Colors.white : Colors.white70)),
//                             selected: mode == 'return',
//                             onSelected: (_) => setStateDialog(() => mode = 'return'),
//                             selectedColor: Colors.blueAccent,
//                             backgroundColor: Colors.grey[800],
//                           ),
//                           ChoiceChip(
//                             label: Text('استبدال', style: TextStyle(color: mode == 'exchange' ? Colors.white : Colors.white70)),
//                             selected: mode == 'exchange',
//                             onSelected: (_) => setStateDialog(() => mode = 'exchange'),
//                             selectedColor: Colors.green,
//                             backgroundColor: Colors.grey[800],
//                           ),
//                           ChoiceChip(
//                             label: Text('ارجاع + استبدال', style: TextStyle(color: mode == 'both' ? Colors.white : Colors.white70)),
//                             selected: mode == 'both',
//                             onSelected: (_) => setStateDialog(() => mode = 'both'),
//                             selectedColor: Colors.deepOrange,
//                             backgroundColor: Colors.grey[800],
//                           ),
//                         ],
//                       ),
//
//                       const SizedBox(height: 12),
//                       const Text('اختر العناصر للإرجاع (قم بتحديث الكمية إذا لزم)', style: TextStyle(color: Colors.white70)),
//                       const SizedBox(height: 8),
//                       if (items.isEmpty) const Text('لا توجد عناصر من الفاتورة', style: TextStyle(color: Colors.white70)),
//                       if (items.isNotEmpty)
//                         SizedBox(
//                           height: 180,
//                           child: ListView.builder(
//                             shrinkWrap: true,
//                             physics: const ClampingScrollPhysics(),
//                             itemCount: items.length,
//                             itemBuilder: (_, i) {
//                               final it = items[i];
//                               final name = (it['product_name'] ?? it['name'] ?? 'Product').toString();
//                               final maxQty = (it['qty'] as num?)?.toInt() ?? (it['quantity'] as num?)?.toInt() ?? 0;
//                               final disabled = false;
//                               return Row(
//                                 children: [
//                                   Checkbox(
//                                     value: selected[i],
//                                     onChanged: disabled ? null : (v) => setStateDialog(() => selected[i] = v ?? false),
//                                   ),
//                                   Expanded(child: Text(name, style: TextStyle(color: Colors.white))),
//                                   SizedBox(
//                                     width: 80,
//                                     child: TextField(
//                                       controller: qtyControllers[i],
//                                       keyboardType: TextInputType.number,
//                                       style: TextStyle(color: Colors.white),
//                                       decoration: InputDecoration(hintText: 'Qty', hintStyle: TextStyle(color: Colors.white30)),
//                                     ),
//                                   ),
//                                   const SizedBox(width: 8),
//                                   Text('/ $maxQty', style: TextStyle(color: Colors.white70)),
//                                 ],
//                               );
//                             },
//                           ),
//                         ),
//
//                       const SizedBox(height: 12),
//                       const Divider(color: Colors.white24),
//                       const SizedBox(height: 8),
//
//                       Row(
//                         mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                         children: [
//                           Text('عناصر الاستبدال', style: TextStyle(color: Colors.white)),
//                           TextButton(
//                             onPressed: (mode == 'return') ? null : () async {
//                               // open dialog to add exchange item via barcode lookup dialog
//                               final res = await _showAddExchangeItemDialog(context);
//                               if (res != null) {
//                                 setStateDialog(() {
//                                   exchangeItems.add(res);
//                                 });
//                               }
//                             },
//                             child: Text('أضف', style: TextStyle(color: (mode == 'return') ? Colors.white24 : Colors.white)),
//                           ),
//                         ],
//                       ),
//
//                       const SizedBox(height: 8),
//                       if (mode == 'return' && exchangeItems.isNotEmpty)
//                         Text('تم تعطيل عناصر الاستبدال في وضع "ارجاع".', style: TextStyle(color: Colors.white70)),
//
//                       if (exchangeItems.isEmpty) Text('لا عناصر استبدال مضافة', style: TextStyle(color: Colors.white70)),
//                       if (exchangeItems.isNotEmpty)
//                         SizedBox(
//                           height: 120,
//                           child: ListView.builder(
//                             shrinkWrap: true,
//                             physics: const ClampingScrollPhysics(),
//                             itemCount: exchangeItems.length,
//                             itemBuilder: (_, i) {
//                               final ex = exchangeItems[i];
//                               return ListTile(
//                                 title: Text(ex['name'] ?? 'Product', style: TextStyle(color: Colors.white)),
//                                 subtitle: Text('qty: ${ex['qty']} — price: ${ex['price']}', style: TextStyle(color: Colors.white70)),
//                                 trailing: IconButton(
//                                   icon: Icon(Icons.delete, color: Colors.white70),
//                                   onPressed: () => setStateDialog(() => exchangeItems.removeAt(i)),
//                                 ),
//                               );
//                             },
//                           ),
//                         ),
//
//                       const SizedBox(height: 12),
//                       TextField(
//                         controller: refundController,
//                         keyboardType: TextInputType.numberWithOptions(decimal: true),
//                         style: TextStyle(color: Colors.white),
//                         decoration: InputDecoration(labelText: 'مبلغ الاسترداد (refund amount)', labelStyle: TextStyle(color: Colors.white70)),
//                       ),
//                       TextField(
//                         controller: noteController,
//                         style: TextStyle(color: Colors.white),
//                         decoration: InputDecoration(labelText: 'ملاحظة المرتجع', labelStyle: TextStyle(color: Colors.white70)),
//                       ),
//                     ],
//                   ),
//                 ),
//               ),
//             ),
//             actions: [
//               TextButton(onPressed: () {
//                 // dispose controllers safely and close dialog
//                 for (final c in qtyControllers) { c.dispose(); }
//                 refundController.dispose();
//                 noteController.dispose();
//                 Navigator.pop(context);
//               }, child: Text('إلغاء', style: TextStyle(color: Colors.white))),
//               TextButton(
//                 onPressed: submitting ? null : () async {
//                   setStateDialog(() => submitting = true);
//
//                   try {
//                     final List<Map<String, dynamic>> returns = [];
//                     for (int i = 0; i < items.length; i++) {
//                       if (!selected[i]) continue;
//                       final it = items[i];
//                       final pid = (it['product_id'] is num) ? (it['product_id'] as num).toInt() : int.tryParse(it['product_id']?.toString() ?? '') ?? 0;
//                       final maxQty = (it['qty'] as num?)?.toInt() ?? (it['quantity'] as num?)?.toInt() ?? 0;
//                       final qty = int.tryParse(qtyControllers[i].text.trim()) ?? 0;
//                       if (pid <= 0 || qty <= 0) continue;
//
//                       // validation: qty <= maxQty
//                       if (qty > maxQty) {
//                         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('الكمية $qty أكبر من المتاح $maxQty للعنصر ${it['product_name'] ?? it['name'] ?? ''}')));
//                         setStateDialog(() => submitting = false);
//                         return;
//                       }
//
//                       returns.add({
//                         'product_id': pid,
//                         'qty': qty,
//                         'price': (it['price'] is num) ? (it['price'] as num).toDouble() : (double.tryParse(it['price']?.toString() ?? '') ?? 0.0),
//                         'name': (it['product_name'] ?? it['name'] ?? '')
//                       });
//                     }
//
//                     final exs = exchangeItems.where((e) => (e['product_id'] ?? 0) is int && (e['qty'] ?? 0) is int && (e['qty'] ?? 0) > 0).map((e) {
//                       return {
//                         'product_id': (e['product_id'] ?? 0),
//                         'qty': (e['qty'] ?? 0),
//                         'price': (e['price'] ?? 0.0),
//                         'name': (e['name'] ?? '')
//                       };
//                     }).toList();
//
//                     // Validate according to mode
//                     if (mode == 'return' && returns.isEmpty) {
//                       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اختر عنصرًا واحدًا على الأقل للإرجاع')));
//                       setStateDialog(() => submitting = false);
//                       return;
//                     }
//                     if (mode == 'exchange' && (returns.isEmpty || exs.isEmpty)) {
//                       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('في وضع الاستبدال اختر العناصر القديمة وأضف عنصرًا واحدًا على الأقل للاستبدال')));
//                       setStateDialog(() => submitting = false);
//                       return;
//                     }
//                     if (mode == 'both' && returns.isEmpty && exs.isEmpty) {
//                       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اختر عناصر للإرجاع أو أضف عناصر للاستبدال')));
//                       setStateDialog(() => submitting = false);
//                       return;
//                     }
//
//                     final refundAmount = double.tryParse(refundController.text.trim()) ?? 0.0;
//                     final note = noteController.text.trim();
//
//                     // show progress
//                     showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));
//
//                     try {
//                       final res = await _processReturn(
//                         originalInvoiceId: originalSaleId,
//                         returnItems: returns,
//                         exchangeItems: exs,
//                         refundAmount: refundAmount,
//                         cashierUsername: cashierName,
//                         paymentMethod: 'cash',
//                         paid: 0.0,
//                         returnNote: note,
//                         debug: false,
//                       );
//
//                       // close progress & dialog
//                       if (Navigator.canPop(context)) Navigator.pop(context);
//                       if (Navigator.canPop(context)) Navigator.pop(context);
//
//                       // apply local update so the invoice UI reflects the change immediately
//                       _applyReturnExchangeLocally(originalSaleId, returns, exs);
//
//                       // reload from server to be sure (server may mark canceled or add child record)
//                       await _loadSales(date: null);
//
//                       // message: try to show child_record_id / return_invoice_id / updated_invoice_id
//                       String idShown = '';
//                       if (res.containsKey('child_record_id') && res['child_record_id'] != null) idShown = res['child_record_id'].toString();
//                       else if (res.containsKey('return_invoice_id') && res['return_invoice_id'] != null) idShown = res['return_invoice_id'].toString();
//                       else if (res.containsKey('updated_invoice_id') && res['updated_invoice_id'] != null) idShown = res['updated_invoice_id'].toString();
//
//                       ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تمت العملية بنجاح${idShown.isNotEmpty ? ' — رقم: $idShown' : ''}')));
//                     } catch (e) {
//                       if (Navigator.canPop(context)) Navigator.pop(context);
//                       showDialog(context: context, builder: (_) => AlertDialog(
//                         title: Text('خطأ أثناء معالجة المرتجع'),
//                         content: SingleChildScrollView(child: Text(e.toString())),
//                         actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text('حسناً'))],
//                       ));
//                     }
//                   } finally {
//                     // cleanup controllers in finally
//                     for (final c in qtyControllers) { c.dispose(); }
//                     refundController.dispose();
//                     noteController.dispose();
//                     setStateDialog(() => submitting = false);
//                   }
//                 },
//                 child: Text('تنفيذ العملية', style: TextStyle(color: Colors.white)),
//               ),
//             ],
//           );
//         });
//       },
//     );
//   }
//
//   Future<void> _pickDate() async {
//     final picked = await showDatePicker(context: context, initialDate: selectedDate, firstDate: DateTime(2000), lastDate: DateTime(2100));
//     if (picked != null) {
//       setState(() => selectedDate = picked);
//       await _loadSales(date: selectedDate);
//     }
//   }
//
//   String _formatDayMonth(dynamic rawDate) {
//     if (rawDate == null) return '';
//     final s = rawDate.toString();
//     try {
//       final dt = DateTime.parse(s);
//       return '${dt.day}/${dt.month}';
//     } catch (_) {
//       final m = RegExp(r'(\d{4})-(\d{2})-(\d{2})').firstMatch(s);
//       if (m != null) return '${int.parse(m.group(3)!)}/${int.parse(m.group(2)!)}';
//       return s;
//     }
//   }
//
//   String _formatSelectedDate(DateTime dt) => '${dt.day}/${dt.month}/${dt.year}';
//
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       backgroundColor: AppColorsDark.bgColor,
//       appBar: AppBar(
//         title: Text('الفواتير السابقة', style: TextStyle(color: Colors.white)),
//         backgroundColor: Colors.transparent,
//         actions: [
//           IconButton(
//             onPressed: () async => await _loadSales(date: null),
//             icon: Icon(Icons.refresh, color: Colors.white70),
//           ),
//         ],
//         iconTheme: IconThemeData(color: Colors.white70),
//       ),
//       body: loading
//           ? const Center(child: CircularProgressIndicator())
//           : Column(
//         children: [
//           Padding(
//             padding: const EdgeInsets.symmetric(vertical: 12.0),
//             child: GestureDetector(
//               onTap: _pickDate,
//               child: Column(
//                 children: [
//                   Text('التاريخ', style: TextStyle(color: Colors.white70)),
//                   const SizedBox(height: 4),
//                   Row(
//                     mainAxisAlignment: MainAxisAlignment.center,
//                     children: [
//                       Text(_formatSelectedDate(selectedDate), style: TextStyle(color: Colors.white)),
//                       const SizedBox(width: 8),
//                       Icon(Icons.calendar_today, size: 18, color: Colors.white70),
//                     ],
//                   ),
//                 ],
//               ),
//             ),
//           ),
//           Expanded(
//             child: groupedSales.isEmpty
//                 ? Center(child: Text('لا توجد فواتير', style: TextStyle(color: Colors.white70)))
//                 : ListView(
//               children: groupedSales.entries.map((entry) {
//                 final cashierName = entry.key;
//                 final list = entry.value;
//                 return Padding(
//                   padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
//                   child: Card(
//                     color: AppColorsDark.bgCardColor,
//                     child: ExpansionTile(
//                       title: Text('$cashierName (${list.length})', style: TextStyle(color: Colors.white)),
//                       children: list.map((s) {
//                         final saleId = (s['id'] as num).toInt();
//                         final total = (s['total'] as num?)?.toDouble() ?? 0.0;
//                         final paid = (s['paid_amount'] as num?)?.toDouble() ?? 0.0;
//                         final type = (s['type'] ?? 'sale').toString();
//                         final isReturn = (s['is_canceled'] ?? 0) == 1 || type == 'return';
//                         final note = (s['meta']?['last_note'] ?? s['return_note'] ?? '').toString();
//                         final dayMonth = _formatDayMonth(s['date']);
//                         return ListTile(
//                           onTap: () => _openSaleDetails(s),
//                           title: Row(
//                             children: [
//                               Expanded(child: Text('#$saleId — $dayMonth', style: TextStyle(color: Colors.white))),
//                               if (type == 'return') const Icon(Icons.cancel, color: Colors.red),
//                               if (type == 'exchange') const Icon(Icons.swap_horiz, color: Colors.green),
//                               if (type == 'both') const Icon(Icons.sync, color: Colors.orange),
//                             ],
//                           ),
//                           subtitle: Text('الإجمالي: ${total.toStringAsFixed(2)} — المدفوع: ${paid.toStringAsFixed(2)}', style: TextStyle(color: Colors.white70)),
//                           trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.white70),
//                         );
//                       }).toList(),
//                     ),
//                   ),
//                 );
//               }).toList(),
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }