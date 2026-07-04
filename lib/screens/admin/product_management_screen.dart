// lib/screens/product_management_screen.dart
import 'dart:async';

import 'package:cashgo_supermarket/utils/colors.dart';
import 'package:cashgo_supermarket/widgets/custom_button.dart';
import 'package:flutter/material.dart';
import 'package:skeletonizer/skeletonizer.dart';
import '../../services/Api/Admin/Products.dart';
import '../../widgets/custom_form.dart';
import '../../widgets/empty_state_card.dart';

class ProductManagementScreen extends StatefulWidget {
  const ProductManagementScreen({super.key});

  @override
  State<ProductManagementScreen> createState() =>
      _ProductManagementScreenState();
}

class _ProductManagementScreenState extends State<ProductManagementScreen> {
  List<Map<String, dynamic>> products = [];
  bool loading = true;
  String searchQuery = '';
  final barcodeFocusNode = FocusNode();
  final barcodeController = TextEditingController();

  // Pagination state
  int currentPage = 1;
  int totalPages = 1; // will be updated from meta if available
  bool loadingMore = false;
  bool allLoaded = false;

  // Auto-load timer: loads next page every second, no scroll needed

  final ScrollController verticalScrollController = ScrollController();

  Color _dialogTextColor(BuildContext ctx) =>
      Theme.of(ctx).brightness == Brightness.light
          ? Colors.black87
          : Colors.white;

  @override
  void initState() {
    super.initState();
    refreshProducts();

    // listener to load more when scrolled to bottom
    verticalScrollController.addListener(() {
      if (!verticalScrollController.hasClients) return;
      final pos = verticalScrollController.position;
      if (pos.maxScrollExtent <= 0) return;
      if (pos.pixels >= pos.maxScrollExtent - 40) {
        if (!loadingMore && !allLoaded && currentPage < totalPages) {
          loadMoreProducts();
        }
      }
    });

  }

  Future<void> _preloadRemainingPages() async {
    while (!allLoaded && mounted) {
      await loadMoreProducts();
      await Future.delayed(const Duration(milliseconds: 30));
    }
  }

  Future<void> refreshProducts() async {
    setState(() {
      loading = true;
      currentPage = 1;
      totalPages = 1;
      allLoaded = false;
    });

    try {
      // Try to use paged endpoint (returns meta + rows)
      final page = await ProductApi.getProductsPage();
      List<Map<String, dynamic>> rows = [];
      int tp = 1;
      if (page != null && page['rows'] is List) {
        rows = List<Map<String, dynamic>>.from(page['rows'] as List);
        final meta = page['meta'] as Map<String, dynamic>? ?? {};
        if (meta.containsKey('total_pages')) {
          tp = (meta['total_pages'] is int)
              ? meta['total_pages'] as int
              : int.tryParse(meta['total_pages']?.toString() ?? '1') ?? 1;
        } else if (meta.containsKey('total') && meta.containsKey('per_page')) {
          final total = int.tryParse(meta['total']?.toString() ?? '0') ?? 0;
          final perPage =
              int.tryParse(meta['per_page']?.toString() ?? '10') ?? 10;
          tp = perPage > 0 ? ((total + perPage - 1) ~/ perPage) : 1;
        }
      } else {
        // fallback: call getAllProducts with count=1 (if you implemented that earlier)
        final fallbackRows = await ProductApi.getAllProducts(count: 1);
        rows = fallbackRows;
        // best-effort: if returned less than per-page (10) assume only one page
        tp = (rows.length < 10)
            ? 1
            : 999999; // unknown total -> allow more loads
      }

      setState(() {
        products = rows;
        currentPage = 1;
        totalPages = tp;
        loading = false;
        allLoaded =
            rows.isEmpty || (currentPage >= totalPages && totalPages > 0);
      });

      if (verticalScrollController.hasClients) {
        verticalScrollController.jumpTo(0);
      }

      _preloadRemainingPages();


      // scroll to top
      if (verticalScrollController.hasClients) {
        verticalScrollController.jumpTo(0);
      }
    } catch (e) {
      setState(() {
        loading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Directionality(
          textDirection: TextDirection.rtl,
          child: Text('فشل تحميل المنتجات: $e'),
        ),
      ));
    }
  }

  Future<void> loadMoreProducts() async {
    if (loading || loadingMore || allLoaded) return;
    setState(() {
      loadingMore = true;
    });

    final nextPage = currentPage + 1;
    try {
      // try paged endpoint first
      final page = await ProductApi.getProductsPage(count: nextPage);
      List<Map<String, dynamic>> rows = [];
      int tp = totalPages;
      if (page != null && page['rows'] is List) {
        rows = List<Map<String, dynamic>>.from(page['rows'] as List);
        final meta = page['meta'] as Map<String, dynamic>? ?? {};
        if (meta.containsKey('total_pages')) {
          tp = (meta['total_pages'] is int)
              ? meta['total_pages'] as int
              : int.tryParse(
              meta['total_pages']?.toString() ?? tp.toString()) ??
              tp;
        } else if (meta.containsKey('total') && meta.containsKey('per_page')) {
          final total = int.tryParse(meta['total']?.toString() ?? '0') ?? 0;
          final perPage =
              int.tryParse(meta['per_page']?.toString() ?? '10') ?? 10;
          tp = perPage > 0 ? ((total + perPage - 1) ~/ perPage) : tp;
        }
      } else {
        // fallback to getAllProducts(count)
        final fallbackRows = await ProductApi.getAllProducts(count: nextPage);
        rows = fallbackRows;
        // if returned empty, mark allLoaded
        if (fallbackRows.isEmpty) {
          rows = [];
          tp = currentPage; // no more pages
        } else {
          // unknown total -> leave tp large
          tp = 999999;
        }
      }

      // append unique rows (avoid duplicates by id)
      final existingIds = products.map((e) => e['id']).toSet();
      final newRows =
      rows.where((r) => !existingIds.contains(r['id'])).toList();

      setState(() {
        if (newRows.isNotEmpty) {
          products.addAll(newRows);
          currentPage = nextPage;
        } else {
          // if no new rows returned, assume no more pages
          allLoaded = true;
        }
        totalPages = tp;
        if (currentPage >= totalPages) allLoaded = true;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Directionality(
          textDirection: TextDirection.rtl,
          child: Text('فشل تحميل المزيد من المنتجات: $e'),
        ),
      ));
    } finally {
      setState(() {
        loadingMore = false;
      });
    }
  }

  double computeProductProfit(Map<String, dynamic> p) {
    final unitsInCarton = (p['units_in_carton'] ?? 0) as num;
    final totalUnits = (p['total_units'] ??
        ((p['quantity'] as num? ?? 0) * (p['units_in_carton'] as num? ?? 0) +
            (p['units_remainder'] ?? 0))) as num;
    final purchasePrice = (p['purchase_price'] as num? ?? 0).toDouble();
    final sellingPrice = (p['selling_price'] as num? ?? 0).toDouble();

    if (unitsInCarton == 0) {
      final profitPerUnit = sellingPrice - (purchasePrice);
      return profitPerUnit * totalUnits;
    }

    final purchasePerUnit = purchasePrice / unitsInCarton;
    return (sellingPrice - purchasePerUnit) * totalUnits;
  }

  double computeTotalProfit() {
    return products.fold(0.0, (prev, p) => prev + computeProductProfit(p));
  }

  List<Map<String, dynamic>> get filteredProducts {
    if (searchQuery.trim().isEmpty) return products;
    final q = searchQuery.toLowerCase();
    return products.where((p) {
      final name = (p['name'] as String? ?? '').toLowerCase();
      final barcode = ((p['barcode'] ?? '') as String).toLowerCase();
      return name.contains(q) || barcode.contains(q);
    }).toList();
  }

  Future<void> toggleProfitMarked(
      Map<String, dynamic> product, bool value) async {
    final id = (product['id'] as num?)?.toInt() ??
        int.tryParse(product['id']?.toString() ?? '') ??
        0;
    if (id <= 0) return;

    setState(() {
      product['profit_marked'] = value ? 1 : 0;
      final index = products.indexWhere((p) => p['id'] == product['id']);
      if (index >= 0) products[index]['profit_marked'] = value ? 1 : 0;
    });

    try {
      await ProductApi.setProductProfitMarked(id, value);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        product['profit_marked'] = value ? 0 : 1;
        final index = products.indexWhere((p) => p['id'] == product['id']);
        if (index >= 0) products[index]['profit_marked'] = value ? 0 : 1;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Directionality(
          textDirection: TextDirection.rtl,
          child: Text('فشل حفظ علامة تقرير الأرباح: $e'),
        ),
      ));
    }
  }

  Future<void> onScanBarcodeSubmitted(String code) async {
    if (code.trim().isEmpty) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final p = await ProductApi.getProductByBarcode(code.trim());
      Navigator.pop(context);
      if (p != null) {
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(
              'تم العثور على المنتج',
              style: TextStyle(color: _dialogTextColor(ctx)),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('الاسم: ${p['name']}',
                    style: TextStyle(color: _dialogTextColor(ctx))),
                Text('الباركود: ${p['barcode'] ?? '-'}',
                    style: TextStyle(color: _dialogTextColor(ctx))),
                Text('السعر: ${p['selling_price']}',
                    style: TextStyle(color: _dialogTextColor(ctx))),
                Text('الكرتون: ${p['quantity']}',
                    style: TextStyle(color: _dialogTextColor(ctx))),
                Text('الوحدات في الكرتونة: ${p['units_in_carton']}',
                    style: TextStyle(color: _dialogTextColor(ctx))),
                Text('الوحدات المتبقية: ${p['units_remainder'] ?? 0}',
                    style: TextStyle(color: _dialogTextColor(ctx))),
                Text(
                  'إجمالي الوحدات: ${p['total_units'] ?? ((p['quantity'] as num? ?? 0) * (p['units_in_carton'] as num? ?? 0) + (p['units_remainder'] ?? 0))}',
                  style: TextStyle(color: _dialogTextColor(ctx)),
                ),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('إغلاق',
                      style: TextStyle(color: _dialogTextColor(ctx)))),
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  openAddEditDialog(existing: p);
                },
                child: Text('تعديل',
                    style: TextStyle(color: _dialogTextColor(ctx))),
              ),
            ],
          ),
        );
      } else {
        final add = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(
              'المنتج غير موجود',
              style: TextStyle(color: _dialogTextColor(ctx)),
            ),
            content: Text(
              'لم يتم العثور على منتج بالباركود "$code". هل تريد إضافة منتج جديد بهذا الكود؟',
              style: TextStyle(color: _dialogTextColor(ctx)),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text('لا',
                      style: TextStyle(color: _dialogTextColor(ctx)))),
              TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text('نعم',
                      style: TextStyle(color: _dialogTextColor(ctx)))),
            ],
          ),
        );
        if (add == true) {
          openAddEditDialog(prefillBarcode: code.trim());
        }
      }
    } catch (e) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Directionality(
          textDirection: TextDirection.rtl,
          child: Text('حدث خطأ أثناء البحث عن الباركود: $e'),
        ),
      ));
    } finally {
      barcodeController.clear();
      barcodeFocusNode.requestFocus();
      await refreshProducts();
    }
  }

  Future<void> openAddEditDialog(
      {Map<String, dynamic>? existing, String? prefillBarcode}) async {
    final didChange = await showDialog<bool>(
      context: context,
      builder: (_) => AddEditProductDialog(
          existing: existing, prefillBarcode: prefillBarcode),
    );
    if (didChange == true) {
      await refreshProducts();
    }
  }

  void openScannerFallbackInfo() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'مسح الباركود بالكاميرا',
          style: TextStyle(color: _dialogTextColor(ctx)),
        ),
        content: Text(
          'استخدم قارئ باركود USB لإدخال الكود مباشرة، أو أضف شاشة مسح بالكاميرا إذا احتجت ذلك لاحقاً.',
          style: TextStyle(color: _dialogTextColor(ctx)),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('حسناً',
                  style: TextStyle(color: _dialogTextColor(ctx)))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0.0,
        centerTitle: true,
        iconTheme: IconThemeData(
          color: Theme.of(context).iconTheme.color,
        ),
        title: Text(
          'اداره المنتجات',
          style: TextStyle(color: AppColorsDark.mainTextDark),
        ),
        actions: [
          IconButton(
            tooltip: 'بحث بالباركود',
            onPressed: () {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text(
                    'بحث بالباركود',
                    style: TextStyle(color: _dialogTextColor(ctx)),
                  ),
                  content: TextField(
                    controller: barcodeController,
                    focusNode: barcodeFocusNode,
                    decoration: const InputDecoration(
                        hintText: 'اكتب الباركود ثم اضغط بحث'),
                    onSubmitted: (v) {
                      Navigator.pop(context);
                      onScanBarcodeSubmitted(v);
                    },
                  ),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text('إلغاء',
                            style: TextStyle(color: _dialogTextColor(ctx)))),
                    TextButton(
                        onPressed: () {
                          final v = barcodeController.text.trim();
                          Navigator.pop(ctx);
                          onScanBarcodeSubmitted(v);
                        },
                        child: Text('بحث',
                            style: TextStyle(color: _dialogTextColor(ctx)))),
                  ],
                ),
              );
            },
            icon:
            Icon(Icons.qr_code_2, color: Theme.of(context).iconTheme.color),
          ),
          IconButton(
            tooltip: 'تحديث',
            onPressed: refreshProducts,
            icon: Icon(Icons.refresh,
                color: Theme.of(context).iconTheme.color, size: 25),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => openAddEditDialog(),
        icon: Icon(Icons.add, color: Theme.of(context).iconTheme.color),
        backgroundColor: AppColorsDark.mainColor,
        label: Text(
          'اضافه منتج',
          style: TextStyle(fontSize: 17, color: AppColorsDark.mainTextDark),
        ),
      ),
      body: Skeletonizer(
        enabled: loading,
        enableSwitchAnimation: true,
        effect: ShimmerEffect(
          baseColor: AppColorsDark.mainColor,
          highlightColor: Colors.grey.shade600,
          duration: const Duration(seconds: 2),
        ),
        containersColor: Theme.of(context).cardColor,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: constraints.maxWidth),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      Wrap(
                        spacing: 16,
                        runSpacing: 12,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          SizedBox(
                            width: (constraints.maxWidth - 180).clamp(
                              260.0,
                              constraints.maxWidth,
                            ),
                            child: CustomFormField(
                              hint: "بحث بواسطه الاسم او الرمز التعريفي",
                              onChanged: (v) => setState(() {
                                searchQuery = v;
                                // reset pagination when searching
                                currentPage = 1;
                                allLoaded = false;
                                // scroll to top
                                if (verticalScrollController.hasClients) {
                                  verticalScrollController.jumpTo(0);
                                }
                              }),
                              centerHint: true,
                            ),
                          ),
                          SizedBox(
                            width: 140,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Text(
                                  'صافي الربح',
                                  style: TextStyle(
                                    fontSize: 15,
                                    color: AppColorsDark.mainTextDark,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                Text(
                                  '${computeTotalProfit().toStringAsFixed(2)}',
                                  style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: AppColorsDark.mainTextDark),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: filteredProducts.isEmpty
                            ? const EmptyStateCard(
                          icon: Icons.inventory_2_outlined,
                          title: 'لا توجد منتجات',
                          message:
                          'أضف منتجاً جديداً أو غيّر كلمات البحث لعرض النتائج.',
                        )
                            : LayoutBuilder(
                          builder: (context, constraints) {
                            final visibleProducts =
                            filteredProducts.where((p) {
                              final name =
                              (p['name']?.toString() ?? '').trim();
                              final barcode =
                              (p['barcode']?.toString() ?? '').trim();
                              // show if either name أو barcode موجود أو id موجود وصالح
                              final hasValidId = p['id'] != null &&
                                  p['id'].toString().isNotEmpty;
                              return name.isNotEmpty ||
                                  barcode.isNotEmpty ||
                                  hasValidId;
                            }).toList();

                            return SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                    minWidth: constraints.maxWidth),
                                child: SingleChildScrollView(
                                  // attach the vertical controller so we can detect reaching bottom
                                  scrollDirection: Axis.vertical,
                                  controller: verticalScrollController,
                                  child: Column(
                                    children: [
                                      Container(
                                        width: constraints
                                            .maxWidth, // <-- يجبر الحاوية تأخذ كامل العرض المتاح
                                        decoration: BoxDecoration(
                                          border: Border.all(
                                              color: AppColorsDark
                                                  .strokColor,
                                              width: 1),
                                          borderRadius:
                                          BorderRadius.circular(8),
                                        ),
                                        child: DataTable(
                                          columnSpacing: 18,
                                          headingRowColor:
                                          MaterialStateProperty.all(
                                              Theme.of(context)
                                                  .cardColor),
                                          dataRowColor:
                                          MaterialStateProperty.all(
                                              Theme.of(context)
                                                  .cardColor),
                                          columns: [
                                            DataColumn(
                                                label: Text('الرقم',
                                                    style: TextStyle(
                                                        color: AppColorsDark
                                                            .mainTextDark))),
                                            DataColumn(
                                                label: Text(
                                                    'تقرير الأرباح',
                                                    style: TextStyle(
                                                        color: AppColorsDark
                                                            .mainTextDark))),
                                            DataColumn(
                                                label: Text('الباركود',
                                                    style: TextStyle(
                                                        color: AppColorsDark
                                                            .mainTextDark))),
                                            DataColumn(
                                                label: Text('الاسم',
                                                    style: TextStyle(
                                                        color: AppColorsDark
                                                            .mainTextDark))),
                                            DataColumn(
                                                label: Text('الشراء',
                                                    style: TextStyle(
                                                        color: AppColorsDark
                                                            .mainTextDark))),
                                            DataColumn(
                                                label: Text('البيع',
                                                    style: TextStyle(
                                                        color: AppColorsDark
                                                            .mainTextDark))),
                                            DataColumn(
                                                label: Text('كرتون',
                                                    style: TextStyle(
                                                        color: AppColorsDark
                                                            .mainTextDark))),
                                            DataColumn(
                                                label: Text('الوحدات',
                                                    style: TextStyle(
                                                        color: AppColorsDark
                                                            .mainTextDark))),
                                            DataColumn(
                                                label: Text('الصلاحية',
                                                    style: TextStyle(
                                                        color: AppColorsDark
                                                            .mainTextDark))),
                                            DataColumn(
                                                label: Text('الربح',
                                                    style: TextStyle(
                                                        color: AppColorsDark
                                                            .mainTextDark))),
                                            DataColumn(
                                                label: Text('الإجراءات',
                                                    style: TextStyle(
                                                        color: AppColorsDark
                                                            .mainTextDark))),
                                          ],
                                          rows: visibleProducts.map((p) {
                                            final profit =
                                            computeProductProfit(p);
                                            final totalUnits = ((p[
                                            'total_units'] ??
                                                ((p['quantity'] as num? ??
                                                    0) *
                                                    (p['units_in_carton']
                                                    as num? ??
                                                        0) +
                                                    (p['units_remainder'] ??
                                                        0))) as num)
                                                .toInt();
                                            final cartons =
                                            (p['quantity'] as num? ??
                                                0)
                                                .toInt();
                                            final unitsInCarton =
                                            (p['units_in_carton']
                                            as num? ??
                                                0)
                                                .toInt();
                                            final remainder =
                                            (p['units_remainder'] ??
                                                0) as int;
                                            final lowStock =
                                                totalUnits <= 5;
                                            final isProfitMarked = ((p[
                                            'profit_marked']
                                            as num?)
                                                ?.toInt() ??
                                                int.tryParse(
                                                    p['profit_marked']
                                                        ?.toString() ??
                                                        '') ??
                                                0) ==
                                                1;
                                            String stockText;
                                            if (unitsInCarton > 0) {
                                              stockText =
                                              '$cartons كرتونة + $remainder قطعة = $totalUnits قطعة';
                                            } else {
                                              stockText =
                                              '$totalUnits قطعة';
                                            }

                                            return DataRow(
                                              cells: [
                                                DataCell(Text(
                                                    p['id']?.toString() ??
                                                        '-',
                                                    style: TextStyle(
                                                        color: AppColorsDark
                                                            .mainTextDark))),
                                                DataCell(
                                                  Checkbox(
                                                    value: isProfitMarked,
                                                    onChanged: (value) =>
                                                        toggleProfitMarked(
                                                          p,
                                                          value ?? false,
                                                        ),
                                                  ),
                                                ),
                                                DataCell(Text(
                                                    p['barcode']
                                                        ?.toString() ??
                                                        '-',
                                                    style: TextStyle(
                                                        color: AppColorsDark
                                                            .mainTextDark))),
                                                DataCell(Text(
                                                    p['name']
                                                        ?.toString() ??
                                                        '-',
                                                    style: TextStyle(
                                                        color: AppColorsDark
                                                            .mainTextDark))),
                                                DataCell(Text(
                                                    (p['purchase_price'] !=
                                                        null)
                                                        ? p['purchase_price']
                                                        .toString()
                                                        : '0',
                                                    style: TextStyle(
                                                        color: AppColorsDark
                                                            .mainTextDark))),
                                                DataCell(Text(
                                                    (p['selling_price']
                                                    as num? ??
                                                        0)
                                                        .toString(),
                                                    style: TextStyle(
                                                        color: AppColorsDark
                                                            .mainTextDark))),
                                                DataCell(
                                                  Text(
                                                    "$cartons",
                                                    style: TextStyle(
                                                      color: lowStock
                                                          ? Colors.red
                                                          : AppColorsDark
                                                          .mainTextDark,
                                                    ),
                                                  ),
                                                ),
                                                DataCell(
                                                  Text(
                                                    "$totalUnits",
                                                    style: TextStyle(
                                                      color: lowStock
                                                          ? Colors.red
                                                          : AppColorsDark
                                                          .mainTextDark,
                                                    ),
                                                  ),
                                                ),
                                                DataCell(
                                                  Container(
                                                    alignment:
                                                    Alignment.center,
                                                    width: 50,
                                                    child: Text(
                                                          () {
                                                        if (p['expiry_date'] ==
                                                            null ||
                                                            p['expiry_date']
                                                                .toString()
                                                                .isEmpty)
                                                          return '-';
                                                        final expiry = DateTime
                                                            .tryParse(p[
                                                        'expiry_date']);
                                                        if (expiry ==
                                                            null)
                                                          return '-';
                                                        final daysLeft = expiry
                                                            .difference(
                                                            DateTime
                                                                .now())
                                                            .inDays;
                                                        return '$daysLeft';
                                                      }(),
                                                      style: TextStyle(
                                                        color: AppColorsDark
                                                            .mainTextDark,
                                                      ),
                                                      textAlign: TextAlign
                                                          .center,
                                                    ),
                                                  ),
                                                ),
                                                DataCell(Text(
                                                    profit
                                                        .toStringAsFixed(
                                                        2),
                                                    style: TextStyle(
                                                        color: AppColorsDark
                                                            .mainTextDark))),
                                                DataCell(Row(
                                                  children: [
                                                    IconButton(
                                                      tooltip: 'تعديل',
                                                      icon: Icon(
                                                          Icons.edit,
                                                          color: AppColorsDark
                                                              .mainTextDark),
                                                      onPressed: () =>
                                                          openAddEditDialog(
                                                              existing:
                                                              p),
                                                    ),
                                                    const Spacer(),
                                                    IconButton(
                                                      tooltip: 'حذف',
                                                      icon: const Icon(
                                                          Icons.delete,
                                                          color:
                                                          Colors.red),
                                                      onPressed:
                                                          () async {
                                                        final ok =
                                                        await showDialog<
                                                            bool>(
                                                          context:
                                                          context,
                                                          builder: (ctx) =>
                                                              AlertDialog(
                                                                title: Text(
                                                                  'حذف المنتج',
                                                                  style: TextStyle(
                                                                      color: _dialogTextColor(
                                                                          ctx)),
                                                                ),
                                                                content: Text(
                                                                  'هل تريد حذف "${p['name']}"؟',
                                                                  style: TextStyle(
                                                                      color: _dialogTextColor(
                                                                          ctx)),
                                                                ),
                                                                actions: [
                                                                  TextButton(
                                                                    onPressed: () =>
                                                                        Navigator.pop(
                                                                            ctx,
                                                                            false),
                                                                    child:
                                                                    Text(
                                                                      'إلغاء',
                                                                      style: TextStyle(
                                                                          color:
                                                                          _dialogTextColor(ctx)),
                                                                    ),
                                                                  ),
                                                                  TextButton(
                                                                    onPressed: () =>
                                                                        Navigator.pop(
                                                                            ctx,
                                                                            true),
                                                                    child:
                                                                    Text(
                                                                      'حذف',
                                                                      style: TextStyle(
                                                                          color:
                                                                          _dialogTextColor(ctx)),
                                                                    ),
                                                                  ),
                                                                ],
                                                              ),
                                                        );
                                                        if (ok == true) {
                                                          try {
                                                            final deleted =
                                                            await ProductApi
                                                                .deleteProduct(
                                                                p['id']);
                                                            if (!context
                                                                .mounted) {
                                                              return;
                                                            }
                                                            if (deleted) {
                                                              ScaffoldMessenger.of(
                                                                  context)
                                                                  .showSnackBar(
                                                                  const SnackBar(
                                                                    content:
                                                                    Directionality(
                                                                      textDirection:
                                                                      TextDirection.rtl,
                                                                      child: Text(
                                                                          'تم الحذف بنجاح'),
                                                                    ),
                                                                  ));
                                                              await refreshProducts();
                                                            } else {
                                                              ScaffoldMessenger.of(
                                                                  context)
                                                                  .showSnackBar(
                                                                  const SnackBar(
                                                                    content:
                                                                    Directionality(
                                                                      textDirection:
                                                                      TextDirection.rtl,
                                                                      child: Text(
                                                                          'فشل الحذف'),
                                                                    ),
                                                                  ));
                                                            }
                                                          } catch (e) {
                                                            if (!context
                                                                .mounted) {
                                                              return;
                                                            }
                                                            await showDialog<
                                                                void>(
                                                              context:
                                                              context,
                                                              builder:
                                                                  (dialogContext) =>
                                                                  AlertDialog(
                                                                    title:
                                                                    Text(
                                                                      'تعذر الحذف',
                                                                      style: TextStyle(
                                                                          color:
                                                                          _dialogTextColor(dialogContext)),
                                                                    ),
                                                                    content:
                                                                    Text(
                                                                      'لا يمكن حذف هذا المنتج لأن له سجل مبيعات أو مشتريات.\nيمكنك تعديل الكمية بدلاً من الحذف.',
                                                                      style: TextStyle(
                                                                          color:
                                                                          _dialogTextColor(dialogContext)),
                                                                    ),
                                                                    actions: [
                                                                      TextButton(
                                                                        onPressed: () =>
                                                                            Navigator.pop(dialogContext),
                                                                        child:
                                                                        Text(
                                                                          'حسناً',
                                                                          style:
                                                                          TextStyle(color: _dialogTextColor(dialogContext)),
                                                                        ),
                                                                      ),
                                                                    ],
                                                                  ),
                                                            );
                                                          }
                                                        }
                                                      },
                                                    ),
                                                  ],
                                                )),
                                              ],
                                            );
                                          }).toList(),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      if (loadingMore)
                                        const Padding(
                                          padding: EdgeInsets.symmetric(
                                              vertical: 8.0),
                                          child: Center(
                                              child:
                                              CircularProgressIndicator()),
                                        ),
                                      if (allLoaded)
                                        Padding(
                                          padding:
                                          const EdgeInsets.symmetric(
                                              vertical: 8.0),
                                          child: Center(
                                              child: Text(
                                                  'لا يوجد منتجات اخرا',
                                                  style: TextStyle(
                                                      color: AppColorsDark
                                                          .mainTextLight))),
                                        ),
                                    ],
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
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    barcodeController.dispose();
    barcodeFocusNode.dispose();
    verticalScrollController.dispose();
    super.dispose();
  }
}

// AddEditProductDialog remains unchanged (copied from your original file)
class AddEditProductDialog extends StatefulWidget {
  final Map<String, dynamic>? existing;
  final String? prefillBarcode;
  const AddEditProductDialog({super.key, this.existing, this.prefillBarcode});

  @override
  State<AddEditProductDialog> createState() => _AddEditProductDialogState();
}

class _AddEditProductDialogState extends State<AddEditProductDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController barcodeController;
  final nameController = TextEditingController();
  final purchaseController = TextEditingController();
  final sellingController = TextEditingController();
  final unitsInCartonController = TextEditingController();
  final qtyController = TextEditingController(); // عدد الكراتين
  final unitsRemainderController =
  TextEditingController(); // محجوز داخلياً (لن يدخل المستخدمه يدوياً)
  final productionDateController = TextEditingController();
  final expiryDateController = TextEditingController();
  final externalUnitsController = TextEditingController();

  final barcodeFocusNode = FocusNode();
  final nameProductFocusNode = FocusNode();
  final paidPriceFocusNode = FocusNode();
  final salePriceFocusNode = FocusNode();
  final unisInCartonFocusNode = FocusNode();
  final quantityFocusNode = FocusNode();
  final externalUnitsFocusNode = FocusNode(); // focus للحقول الجديدة
  final unitsRemainderFocusNode = FocusNode();
  final productionDateFocusNode = FocusNode();
  final expiryDateFocusNode = FocusNode();

  bool isEdit = false;

  Color _dialogTextColor(BuildContext ctx) =>
      Theme.of(ctx).brightness == Brightness.light
          ? Colors.black87
          : Colors.white;

  @override
  void initState() {
    super.initState();
    isEdit = widget.existing != null;
    barcodeController = TextEditingController(
        text: widget.existing != null
            ? widget.existing!['barcode']?.toString() ?? ''
            : (widget.prefillBarcode ?? ''));
    nameController.text =
    widget.existing != null ? widget.existing!['name'] ?? '' : '';
    purchaseController.text = widget.existing != null
        ? (widget.existing!['purchase_price']?.toString() ?? '')
        : '';
    sellingController.text = widget.existing != null
        ? (widget.existing!['selling_price']?.toString() ?? '')
        : '';
    unitsInCartonController.text = widget.existing != null
        ? (widget.existing!['units_in_carton']?.toString() ?? '')
        : '';
    qtyController.text = widget.existing != null
        ? (widget.existing!['quantity']?.toString() ?? '')
        : '';
    externalUnitsController.text = widget.existing != null
        ? (widget.existing!['units_remainder']?.toString() ?? '0')
        : '0';
    unitsRemainderController.text = widget.existing != null
        ? (widget.existing!['units_remainder']?.toString() ?? '0')
        : '0';
    productionDateController.text = widget.existing?['production_date'] ?? '';
    expiryDateController.text = widget.existing?['expiry_date'] ?? '';
  }

  Future<void> save() async {
    if (!_formKey.currentState!.validate()) return;

    final unitsInCarton =
        int.tryParse(unitsInCartonController.text.trim()) ?? 0;
    final cartons = int.tryParse(qtyController.text.trim()) ?? 0;
    final external = int.tryParse(externalUnitsController.text.trim()) ?? 0;

    int finalCartons = cartons;
    int remainder = 0;
    if (unitsInCarton > 0) {
      finalCartons += external ~/ unitsInCarton;
      remainder = external % unitsInCarton;
    } else {
      remainder = external;
    }

    final prod = {
      'id': isEdit ? widget.existing!['id'] : null,
      'barcode': barcodeController.text.trim(),
      'name': nameController.text.trim(),
      'purchase_price': double.tryParse(purchaseController.text.trim()) ?? 0.0,
      'selling_price': double.tryParse(sellingController.text.trim()) ?? 0.0,
      'units_in_carton': unitsInCarton,
      'quantity': finalCartons,
      'units_remainder': remainder,
      'production_date': productionDateController.text.trim(),
      'expiry_date': expiryDateController.text.trim(),
      'profit_marked': isEdit ? (widget.existing!['profit_marked'] ?? 0) : 0,
    };

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    final success = await ProductApi.saveProduct(prod);

    Navigator.pop(context); // close loading

    if (!success) {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(
            'فشل الحفظ',
            style: TextStyle(color: _dialogTextColor(ctx)),
          ),
          content: Text(
            'فشل حفظ المنتج. راجع بيانات المنتج ثم حاول مرة أخرى.',
            style: TextStyle(color: _dialogTextColor(ctx)),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('حسناً',
                    style: TextStyle(color: _dialogTextColor(ctx)))),
          ],
        ),
      );
      return;
    }

    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final focusNode = FocusNode();

    return AlertDialog(
      backgroundColor: Theme.of(context).cardColor,
      title: Center(
        child: Text(
          isEdit ? 'تعديل المنتج' : 'اضافه منتج جديد',
          style: TextStyle(color: _dialogTextColor(context)),
        ),
      ),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 560,
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                CustomFormField(
                  controller: barcodeController,
                  hint: 'الرمز التعريفي الخاص بالمنتج',
                  autoFocus: true,
                  focusNode: barcodeFocusNode,
                  onFieldSubmitted: (_) {
                    FocusScope.of(context).requestFocus(nameProductFocusNode);
                  },
                  validator: (v) =>
                  (v?.trim().isEmpty ?? true) ? 'ادخل الباركود' : null,
                ),
                const SizedBox(height: 10),
                CustomFormField(
                  controller: nameController,
                  focusNode: nameProductFocusNode,
                  hint: 'اسم المنتج',
                  onFieldSubmitted: (_) {
                    FocusScope.of(context).requestFocus(paidPriceFocusNode);
                  },
                  validator: (v) =>
                  (v?.trim().isEmpty ?? true) ? 'ادخل اسم المنتج' : null,
                ),
                const SizedBox(height: 10),
                CustomFormField(
                  controller: purchaseController,
                  focusNode: paidPriceFocusNode,
                  hint: 'سعر شراء الجمله',
                  validator: (v) =>
                  (v?.trim().isEmpty ?? true) ? 'ادخل الاسم' : null,
                  keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
                  onFieldSubmitted: (_) {
                    FocusScope.of(context).requestFocus(salePriceFocusNode);
                  },
                ),
                const SizedBox(height: 10),
                CustomFormField(
                  controller: sellingController,
                  focusNode: salePriceFocusNode,
                  hint: 'سعر بيع القطعه',
                  keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
                  onFieldSubmitted: (_) {
                    FocusScope.of(context).requestFocus(unisInCartonFocusNode);
                  },
                ),
                const SizedBox(height: 10),
                CustomFormField(
                  controller: unitsInCartonController,
                  focusNode: unisInCartonFocusNode,
                  hint: 'كام قطعه في الكرتونه',
                  keyboardType: TextInputType.number,
                  onFieldSubmitted: (_) {
                    FocusScope.of(context).requestFocus(quantityFocusNode);
                  },
                ),
                const SizedBox(height: 10),
                CustomFormField(
                  controller: qtyController,
                  focusNode: quantityFocusNode,
                  hint: 'كام كرتونه عندك',
                  keyboardType: TextInputType.number,
                  onFieldSubmitted: (_) {
                    FocusScope.of(context).requestFocus(externalUnitsFocusNode);
                  },
                ),
                const SizedBox(height: 10),
                CustomFormField(
                  controller: externalUnitsController,
                  focusNode: externalUnitsFocusNode,
                  hint: 'وحدات خارج الكراتين (مثلاً 10)',
                  keyboardType: TextInputType.number,
                  onFieldSubmitted: (_) {
                    FocusScope.of(context)
                        .requestFocus(productionDateFocusNode);
                  },
                ),
                const SizedBox(height: 10),
                CustomFormField(
                  controller: productionDateController,
                  focusNode: productionDateFocusNode,
                  hint: 'تاريخ الإنتاج',
                  readOnly: true,
                  onTap: () async {
                    DateTime? picked = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now(),
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) {
                      productionDateController.text =
                          picked.toIso8601String().split('T').first;
                    }
                  },
                  onFieldSubmitted: (_) {
                    FocusScope.of(context).requestFocus(expiryDateFocusNode);
                  },
                ),
                const SizedBox(height: 10),
                CustomFormField(
                  controller: expiryDateController,
                  focusNode: expiryDateFocusNode,
                  hint: 'تاريخ الانتهاء',
                  readOnly: true,
                  onTap: () async {
                    DateTime? picked = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now(),
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) {
                      expiryDateController.text =
                          picked.toIso8601String().split('T').first;
                    }
                  },
                  onFieldSubmitted: (_) => save(),
                ),
                const SizedBox(height: 12),
                Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: SizedBox(
                        width: double.infinity,
                        height: 30,
                        child: Center(
                          child: Text(
                            'إلغاء',
                            style: TextStyle(
                                color: Theme.of(context).brightness ==
                                    Brightness.light
                                    ? Colors.black
                                    : Colors.white),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 15),
                    CustomButton(
                      onPressed: save,
                      text: isEdit ? 'حفظ' : 'اضافه',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
