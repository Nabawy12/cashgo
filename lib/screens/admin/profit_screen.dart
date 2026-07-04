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
  bool _markedOnly = false;
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
      final rows = await DBHelper.instance.getProfitReport(
        from: _from,
        to: _to,
        markedOnly: _markedOnly,
      );
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
          pw.Text(
              _markedOnly
                  ? 'تقرير أرباح المنتجات التي تم تعليمها'
                  : 'تقرير الأرباح',
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



  Widget _summaryHeader() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColorsDark.bgCardColor, AppColorsDark.bgCardColor.withOpacity(0.6)],
        ),
        border: Border(right: BorderSide(color: Colors.greenAccent, width: 3)),
        boxShadow: [
          BoxShadow(color: Colors.greenAccent.withOpacity(0.15), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(Icons.trending_up_rounded, color: Colors.greenAccent, size: 20),
              const SizedBox(width: 8),
              Text('إجمالي الربح',
                  style: TextStyle(color: AppColorsDark.mainTextLight, fontSize: 14)),
            ],
          ),
          Text(
            _money.format(_totalProfit),
            style: const TextStyle(color: Colors.greenAccent, fontSize: 24, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }


  Widget _filterBar() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickDate(isFrom: true),
                  icon: Icon(Icons.calendar_today, size: 16, color: Theme.of(context).iconTheme.color),
                  label: Text('من: ${DateFormat('yyyy-MM-dd').format(_from)}',
                      style: TextStyle(color: AppColorsDark.mainTextDark)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickDate(isFrom: false),
                  icon: Icon(Icons.calendar_today, size: 16, color: Theme.of(context).iconTheme.color),
                  label: Text('إلى: ${DateFormat('yyyy-MM-dd').format(_to)}',
                      style: TextStyle(color: AppColorsDark.mainTextDark)),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'تحديث',
                onPressed: _load,
                icon: Icon(Icons.refresh, color: Theme.of(context).iconTheme.color),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilterChip(
                  selected: _markedOnly,
                  onSelected: (v) async {
                    setState(() => _markedOnly = v);
                    await _load();
                  },
                  label: const Text('المنتجات التي تم تعليمها فقط'),
                  avatar: Icon(
                    _markedOnly ? Icons.check_circle : Icons.circle_outlined,
                    size: 18,
                    color: _markedOnly ? AppColorsDark.mainColor : null,
                  ),
                  selectedColor: AppColorsDark.mainColor.withOpacity(0.2),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }



  Widget _profitTile(Map<String, dynamic> r) {
    final netQty = (r['quantity_sold'] as num?)?.toInt() ?? 0;
    final grossQty = (r['gross_quantity_sold'] as num?)?.toInt() ?? netQty;
    final returnedQty = (r['returned_quantity'] as num?)?.toInt() ?? 0;
    final profit = (r['profit'] as num?)?.toDouble() ?? 0;
    final revenue = (r['revenue'] as num?)?.toDouble() ?? 0;
    final profitColor = profit >= 0 ? Colors.greenAccent : Colors.redAccent;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColorsDark.bgCardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: profitColor.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text((r['product_name'] ?? '').toString(),
                    style: TextStyle(color: AppColorsDark.mainTextDark, fontWeight: FontWeight.w600)),
              ),
              Text(_money.format(profit),
                  style: TextStyle(color: profitColor, fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _statChip('مباع', '$grossQty', AppColorsDark.mainTextLight),
              const SizedBox(width: 8),
              _statChip('مرتجع', '$returnedQty', Colors.orangeAccent),
              const SizedBox(width: 8),
              _statChip('الصافي', '$netQty', AppColorsDark.mainTextDark),
              const SizedBox(width: 8),
              _statChip('الإيراد', _money.format(revenue), Colors.blueAccent),
            ],
          ),
        ],
      ),
    );
  }



  Widget _statChip(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Text(label, style: TextStyle(color: color, fontSize: 10)),
            Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: AppColorsDark.mainTextDark, fontSize: 11, fontWeight: FontWeight.w600)),
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
              _filterBar(),
              const SizedBox(height: 12),
              TextField(
                controller: _searchController,
                textDirection: TextDirection.rtl,
                onChanged: (_) => setState(() {}),
                style: TextStyle(color: AppColorsDark.mainTextDark),
                decoration: InputDecoration(
                  prefixIcon: Icon(Icons.search, color: Theme.of(context).iconTheme.color),
                  suffixIcon: _searchController.text.isEmpty
                      ? null
                      : IconButton(
                    onPressed: () {
                      _searchController.clear();
                      setState(() {});
                    },
                    icon: Icon(Icons.close, color: Theme.of(context).iconTheme.color),
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
              const SizedBox(height: 25),
              _summaryHeader(),
              const SizedBox(height: 25),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _filteredRows.isEmpty
                    ? const EmptyStateCard(
                  icon: Icons.trending_up,
                  title: 'لا توجد مبيعات',
                  message: 'غيّر الفترة الزمنية أو ابحث باسم/باركود آخر.',
                )
                    : ListView.builder(
                  itemCount: _filteredRows.length,
                  itemBuilder: (_, i) => _profitTile(_filteredRows[i]),
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
