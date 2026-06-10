import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../services/db/db_helper.dart';
import '../../utils/colors.dart';
import '../../widgets/empty_state_card.dart';

class ProfitReportScreen extends StatefulWidget {
  const ProfitReportScreen({super.key});

  @override
  State<ProfitReportScreen> createState() => _ProfitReportScreenState();
}

class _ProfitReportScreenState extends State<ProfitReportScreen> {
  final _money = NumberFormat.currency(locale: 'ar', symbol: 'EGP ');
  final _searchController = TextEditingController();
  DateTime _from = DateTime.now();
  DateTime _to = DateTime.now();
  bool _loading = true;
  List<Map<String, dynamic>> _rows = [];

  List<Map<String, dynamic>> get _filteredRows {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _rows;
    return _rows.where((row) {
      final name = (row['product_name'] ?? '').toString().toLowerCase();
      final barcode = (row['barcode'] ?? '').toString().toLowerCase();
      return name.contains(query) || barcode.contains(query);
    }).toList();
  }

  double get _totalProfit => _filteredRows.fold<double>(
      0, (sum, row) => sum + ((row['profit'] as num?)?.toDouble() ?? 0));

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows =
          await DBHelper.instance.getProfitReport(from: _from, to: _to);
      if (mounted) setState(() => _rows = rows);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom ? _from : _to,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _from = picked;
        if (_from.isAfter(_to)) _to = _from;
      } else {
        _to = picked;
        if (_to.isBefore(_from)) _from = _to;
      }
    });
    await _load();
  }

  Future<void> _exportPdf() async {
    final fontData = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
    final font = pw.Font.ttf(fontData);
    final doc = pw.Document();
    final dateLabel =
        '${DateFormat('yyyy-MM-dd').format(_from)} - ${DateFormat('yyyy-MM-dd').format(_to)}';

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        theme: pw.ThemeData.withFont(base: font, bold: font),
        textDirection: pw.TextDirection.rtl,
        build: (_) => [
          pw.Text('تقرير الأرباح',
              style:
                  pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          pw.Text('الفترة: $dateLabel'),
          pw.SizedBox(height: 12),
          pw.Text('إجمالي الربح: ${_totalProfit.toStringAsFixed(2)}'),
          pw.SizedBox(height: 12),
          pw.Table.fromTextArray(
            headers: const [
              'المنتج',
              'مباع',
              'مرتجع',
              'الصافي',
              'سعر البيع',
              'تكلفة الوحدة',
              'الإيراد',
              'الربح',
            ],
            data: _filteredRows.map((r) {
              final unitsInCarton =
                  ((r['units_in_carton'] as num?)?.toDouble() ?? 1);
              final purchase = ((r['purchase_price'] as num?)?.toDouble() ?? 0);
              final unitCost =
                  unitsInCarton > 0 ? purchase / unitsInCarton : purchase;
              return [
                (r['product_name'] ?? '').toString(),
                '${(r['gross_quantity_sold'] as num?)?.toInt() ?? ((r['quantity_sold'] as num?)?.toInt() ?? 0)}',
                '${(r['returned_quantity'] as num?)?.toInt() ?? 0}',
                '${(r['quantity_sold'] as num?)?.toInt() ?? 0}',
                ((r['selling_price'] as num?)?.toDouble() ?? 0)
                    .toStringAsFixed(2),
                unitCost.toStringAsFixed(2),
                ((r['revenue'] as num?)?.toDouble() ?? 0).toStringAsFixed(2),
                ((r['profit'] as num?)?.toDouble() ?? 0).toStringAsFixed(2),
              ];
            }).toList(),
          ),
        ],
      ),
    );

    final downloads = Directory('${Platform.environment['HOME']}/Downloads');
    if (!downloads.existsSync()) downloads.createSync(recursive: true);
    final file = File(
        '${downloads.path}/cashgo_profit_report_${DateTime.now().millisecondsSinceEpoch}.pdf');
    await file.writeAsBytes(await doc.save());
    _showSnack('تم حفظ التقرير في Downloads');
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Directionality(
        textDirection: TextDirection.rtl,
        child: Text(message),
      ),
    ));
  }

  Widget _dateButton(String label, DateTime date, VoidCallback onTap) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon:
          Icon(Icons.calendar_today, color: Theme.of(context).iconTheme.color),
      label: Text('$label: ${DateFormat('yyyy-MM-dd').format(date)}',
          style: TextStyle(color: AppColorsDark.mainTextDark)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColorsDark.bgColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        iconTheme: IconThemeData(color: Theme.of(context).iconTheme.color),
        title: Text('تقرير الأرباح',
            style: TextStyle(color: AppColorsDark.mainTextDark, fontSize: 24)),
        actions: [
          IconButton(
            tooltip: 'تصدير PDF',
            onPressed: _filteredRows.isEmpty ? null : _exportPdf,
            icon: Icon(Icons.picture_as_pdf,
                color: Theme.of(context).iconTheme.color),
          ),
        ],
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  _dateButton('من', _from, () => _pickDate(isFrom: true)),
                  _dateButton('إلى', _to, () => _pickDate(isFrom: false)),
                  ElevatedButton.icon(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh),
                    label: const Text('تحديث'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _searchController,
                textDirection: TextDirection.rtl,
                onChanged: (_) => setState(() {}),
                style: TextStyle(color: AppColorsDark.mainTextDark),
                decoration: InputDecoration(
                  prefixIcon: Icon(Icons.search,
                      color: Theme.of(context).iconTheme.color),
                  suffixIcon: _searchController.text.isEmpty
                      ? null
                      : IconButton(
                          onPressed: () {
                            _searchController.clear();
                            setState(() {});
                          },
                          icon: Icon(Icons.close,
                              color: Theme.of(context).iconTheme.color),
                        ),
                  hintText: 'ابحث باسم المنتج أو الباركود',
                  hintStyle: TextStyle(color: AppColorsDark.mainTextLight),
                  filled: true,
                  fillColor: AppColorsDark.bgCardColor,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                color: AppColorsDark.bgCardColor,
                child: ListTile(
                  title: Text('إجمالي الربح',
                      style: TextStyle(color: AppColorsDark.mainTextLight)),
                  trailing: Text(_money.format(_totalProfit),
                      style: TextStyle(
                          color: Colors.greenAccent,
                          fontSize: 22,
                          fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _filteredRows.isEmpty
                        ? const EmptyStateCard(
                            icon: Icons.trending_up,
                            title: 'لا توجد مبيعات',
                            message:
                                'غيّر الفترة الزمنية أو ابحث باسم/باركود آخر.',
                          )
                        : ListView.separated(
                            itemCount: _filteredRows.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (_, i) {
                              final r = _filteredRows[i];
                              final netQty =
                                  (r['quantity_sold'] as num?)?.toInt() ?? 0;
                              final grossQty =
                                  (r['gross_quantity_sold'] as num?)?.toInt() ??
                                      netQty;
                              final returnedQty =
                                  (r['returned_quantity'] as num?)?.toInt() ??
                                      0;
                              final profit =
                                  (r['profit'] as num?)?.toDouble() ?? 0;
                              final revenue =
                                  (r['revenue'] as num?)?.toDouble() ?? 0;
                              return Card(
                                color: AppColorsDark.bgCardColor,
                                child: ListTile(
                                  title: Text(
                                      (r['product_name'] ?? '').toString(),
                                      style: TextStyle(
                                          color: AppColorsDark.mainTextDark)),
                                  subtitle: Text(
                                      'مباع: $grossQty | مرتجع: $returnedQty | الصافي: $netQty | الإيراد: ${_money.format(revenue)}',
                                      style: TextStyle(
                                          color: AppColorsDark.mainTextLight)),
                                  trailing: Text(_money.format(profit),
                                      style: TextStyle(
                                          color: profit >= 0
                                              ? Colors.greenAccent
                                              : Colors.redAccent,
                                          fontWeight: FontWeight.bold)),
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
  }
}

class TopProductsChartPage extends ProfitReportScreen {
  const TopProductsChartPage({super.key});
}
