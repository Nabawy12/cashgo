// // ملف داخل screens أو same file
// import 'package:flutter/material.dart';
// import '../../services/db/db_helper.dart';
//
// class ReturnDialog extends StatefulWidget {
//   final Map<String, dynamic> sale;
//   const ReturnDialog({super.key, required this.sale});
//
//   @override
//   State<ReturnDialog> createState() => _ReturnDialogState();
// }
//
// class _ReturnDialogState extends State<ReturnDialog> {
//   List<Map<String, dynamic>> saleItems = [];
//   bool loading = true;
//   String returnType = 'refund'; // or 'exchange'
//   double totalRefund = 0.0;
//
//   // map productId -> controller for qty to return
//   final Map<int, TextEditingController> qtyControllers = {};
//   // for exchange: map productId -> replacement barcode and qty controllers
//   final Map<int, TextEditingController> replacementBarcode = {};
//   final Map<int, TextEditingController> replacementQty = {};
//
//   @override
//   void initState() {
//     super.initState();
//     _loadItems();
//   }
//
//   Future<void> _loadItems() async {
//     final sid = widget.sale['id'] as int;
//     saleItems = await DBHelper.instance.getSaleItemsBySaleId(sid);
//     for (final it in saleItems) {
//       final pid = (it['product_id'] as num).toInt();
//       qtyControllers[pid] = TextEditingController(text: '0');
//       replacementBarcode[pid] = TextEditingController();
//       replacementQty[pid] = TextEditingController(text: '0');
//     }
//     setState(() => loading = false);
//   }
//
//   Future<void> _submit() async {
//     // gather items to return
//     final List<Map<String, dynamic>> items = [];
//     double refundSum = 0.0;
//
//     for (final it in saleItems) {
//       final pid = (it['product_id'] as num).toInt();
//       final soldQty = (it['quantity'] as num).toInt();
//       final price = (it['price'] as num).toDouble();
//       final retQty = int.tryParse(qtyControllers[pid]?.text ?? '0') ?? 0;
//       if (retQty <= 0) continue;
//       if (retQty > soldQty) {
//         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('الكمية المرجعة لا يمكن أن تتجاوز كمية البيع (${soldQty})')));
//         return;
//       }
//
//       int? replacementPid;
//       int repQty = 0;
//       if (returnType == 'exchange') {
//         final repBarcode = replacementBarcode[pid]?.text.trim();
//         repQty = int.tryParse(replacementQty[pid]?.text ?? '0') ?? 0;
//         if ((repBarcode?.isNotEmpty ?? false) && repQty > 0) {
//           final prodMap = await DBHelper.instance.getProductByBarcode(repBarcode!);
//           if (prodMap == null) {
//             ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Replacement product with barcode $repBarcode not found')));
//             return;
//           }
//           replacementPid = (prodMap['id'] as num).toInt();
//         } else {
//           ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('حدد باركود وكمية المنتج البديل')));
//           return;
//         }
//       }
//
//       items.add({
//         'productId': pid,
//         'quantity': retQty,
//         'price': price,
//         'replacementProductId': replacementPid,
//         'replacementQuantity': repQty,
//       });
//
//       // if refund -> sum returned money (price * qty)
//       if (returnType == 'refund') refundSum += price * retQty;
//     }
//
//     if (items.isEmpty) {
//       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اختر على الأقل منتج واحد للاسترجاع')));
//       return;
//     }
//
//     // process return
//     await DBHelper.instance.processReturn(
//       saleId: widget.sale['id'] as int,
//       cashierUsername: widget.sale['cashier_username']?.toString() ?? '',
//       type: returnType,
//       items: items,
//       totalRefund: refundSum,
//       note: 'Return processed by cashier',
//     );
//
//     Navigator.pop(context, true);
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return AlertDialog(
//       title: const Text('استرجاع / استبدال'),
//       content: loading ? const CircularProgressIndicator() : SizedBox(
//         width: 600,
//         child: SingleChildScrollView(
//           child: Column(
//             children: [
//               Row(
//                 children: [
//                   Radio<String>(value: 'refund', groupValue: returnType, onChanged: (v) => setState(() => returnType = v!)),
//                   const Text('استرجاع نقدي'),
//                   const SizedBox(width: 12),
//                   Radio<String>(value: 'exchange', groupValue: returnType, onChanged: (v) => setState(() => returnType = v!)),
//                   const Text('استبدال بمنتج آخر'),
//                 ],
//               ),
//               const SizedBox(height: 8),
//               ...saleItems.map((it) {
//                 final pid = (it['product_id'] as num).toInt();
//                 final name = it['product_name'] ?? 'منتج';
//                 final soldQty = (it['quantity'] as num).toInt();
//                 return Column(
//                   crossAxisAlignment: CrossAxisAlignment.start,
//                   children: [
//                     Text('$name — مبيع: $soldQty'),
//                     Row(
//                       children: [
//                         SizedBox(
//                           width: 80,
//                           child: TextField(
//                             controller: qtyControllers[pid],
//                             keyboardType: TextInputType.number,
//                             decoration: const InputDecoration(labelText: 'كمية الراجع'),
//                           ),
//                         ),
//                         const SizedBox(width: 12),
//                         if (returnType == 'exchange')
//                           Expanded(
//                             child: Row(
//                               children: [
//                                 Expanded(
//                                   child: TextField(
//                                     controller: replacementBarcode[pid],
//                                     decoration: const InputDecoration(labelText: 'باركود المنتج البديل'),
//                                   ),
//                                 ),
//                                 const SizedBox(width: 8),
//                                 SizedBox(
//                                   width: 80,
//                                   child: TextField(
//                                     controller: replacementQty[pid],
//                                     keyboardType: TextInputType.number,
//                                     decoration: const InputDecoration(labelText: 'كمية'),
//                                   ),
//                                 ),
//                               ],
//                             ),
//                           )
//                       ],
//                     ),
//                     const Divider(),
//                   ],
//                 );
//               }).toList(),
//             ],
//           ),
//         ),
//       ),
//       actions: [
//         TextButton(onPressed: () => Navigator.pop(context,false), child: const Text('إلغاء')),
//         ElevatedButton(onPressed: _submit, child: const Text('تأكيد')),
//       ],
//     );
//   }
// }
