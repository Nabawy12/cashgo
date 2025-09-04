import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../services/db/db_helper.dart';
import '../../utils/colors.dart';

class AdminPaidPurchasesScreen extends StatefulWidget {
  const AdminPaidPurchasesScreen({Key? key}) : super(key: key);

  @override
  State<AdminPaidPurchasesScreen> createState() => _AdminPaidPurchasesScreenState();
}

class _AdminPaidPurchasesScreenState extends State<AdminPaidPurchasesScreen> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = false;

  // totals by payment type
  double _cashTotal = 0.0;
  int _cashCount = 0;
  double _walletTotal = 0.0;
  int _walletCount = 0;
  double _cardTotal = 0.0;
  int _cardCount = 0;

  // ===== جديد: فلتر التاريخ =====
  DateTime selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    // نحمّل افتراضياً سجلات يوم اليوم
    _load(date: selectedDate);
  }

  /// _load now يدعم تمرير تاريخ (فلترة لليوم المحدد).
  Future<void> _load({DateTime? date}) async {
    setState(() => _loading = true);
    try {
      final rows = await DBHelper.instance.getPaidPurchaseReceipts();

      // إذا تم تمرير تاريخ -> فلتر لذات اليوم
      List<Map<String, dynamic>> filtered = rows;
      if (date != null) {
        filtered = rows.where((r) {
          final raw = (r['created_at'] ?? r['date'] ?? '').toString();
          final dt = _parseDateOnly(raw);
          if (dt == null) return false;
          return dt.year == date.year && dt.month == date.month && dt.day == date.day;
        }).toList();
      }

      _computeTotals(filtered);
      setState(() {
        _rows = filtered;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      debugPrint('Error loading paid purchase receipts: $e');
      rethrow;
    }
  }

  /// مساعد لتحليل التاريخ بصيغ متعددة إلى DateTime (يُستخدم للفلترة)
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

  void _computeTotals(List<Map<String, dynamic>> rows) {
    double cash = 0.0, wallet = 0.0, card = 0.0;
    int cashC = 0, walletC = 0, cardC = 0;

    for (final r in rows) {
      final paid = (r['paid_amount'] as num?)?.toDouble() ?? 0.0;
      final pt = _normalizePaymentType(r);
      switch (pt) {
        case 'wallet':
          wallet += paid;
          walletC++;
          break;
        case 'card':
          card += paid;
          cardC++;
          break;
        case 'cash':
        default:
          cash += paid;
          cashC++;
          break;
      }
    }

    _cashTotal = cash;
    _cashCount = cashC;
    _walletTotal = wallet;
    _walletCount = walletC;
    _cardTotal = card;
    _cardCount = cardC;
  }

  String _fmtDate(String s) {
    try {
      final d = DateTime.parse(s);
      return DateFormat('yyyy-MM-dd HH:mm').format(d);
    } catch (_) {
      return s;
    }
  }

  String _normalizePaymentType(Map<String, dynamic> r) {
    final pt = (r['payment_type'] ?? r['paymentType'] ?? '').toString().trim().toLowerCase();
    if (pt.isEmpty) return 'cash';
    if (pt == 'wallet' || pt == 'card' || pt == 'cash') return pt;
    if (pt.contains('card')) return 'card';
    if (pt.contains('wallet') || pt.contains('محفظ')) return 'wallet';
    return 'cash';
  }

  Color? _paymentColor(String paymentType) {
    switch (paymentType) {
      case 'cash':
        return Colors.greenAccent[400];
      case 'wallet':
        return Colors.cyan[300];
      case 'card':
        return Colors.orangeAccent[200];
      default:
        return Colors.grey[400];
    }
  }

  Widget _buildPaymentChip(String paymentType) {
    final label = paymentType == 'cash'
        ? 'نقدي'
        : paymentType == 'wallet'
        ? 'محفظة إلكترونية'
        : paymentType;
    return Chip(
      label: Text(label, style: const TextStyle(color: Colors.black87, fontSize: 12)),
      backgroundColor: _paymentColor(paymentType),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  Widget _buildSummaryBoards() {
    Widget board(String title, int count, double total, Color bg) {
      return Expanded(
        child: Card(
          color: bg.withOpacity(0.1),
          shape: RoundedRectangleBorder(
              side:BorderSide(color:bg),borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 12.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: const TextStyle(color: Colors.white70, fontSize: 14)),
                const SizedBox(height: 8),
                Text('$count سند', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 8),
                Text(total.toStringAsFixed(2), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
        ),
      );
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Row(
        children: [
          board('نقدي', _cashCount, _cashTotal, Colors.green),
          const SizedBox(width: 10),
          board('محفظة إلكترونية', _walletCount, _walletTotal, Colors.blueAccent),
          const SizedBox(width: 10),
        ],
      ),
    );
  }

  // ===== جديد: فتح DatePicker =====
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
      await _load(date: selectedDate);
    }
  }

  // عرض التاريخ day/month/year مثل 22/8/2025
  String _formatSelectedDate(DateTime dt) => '${dt.day}/${dt.month}/${dt.year}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColorsDark.bgColor,
      appBar: AppBar(
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0.0,
        scrolledUnderElevation: 0.0,
        iconTheme: const IconThemeData(color: Colors.white70),
        title: const Text(
          'المشتريات المدفوعة',
          style: TextStyle(color: Colors.white),
        ),
        actions: [
          IconButton(
            tooltip: "إعادة تحميل (فلتر التاريخ الحالي)",
            onPressed: () => _load(date: selectedDate),
            icon: const Icon(Icons.refresh, color: Colors.white70),
          )
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Directionality(
        textDirection: TextDirection.rtl,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // === عرض التاريخ تحت الاب بار (منتصف) ===
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
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                        const SizedBox(height: 4),
                        // عرض التاريخ فقط بدون أيقونة
                        Text(
                          _formatSelectedDate(selectedDate),
                          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // القائمة
            Expanded(
              child: Scrollbar(
                thumbVisibility: true,
                child: _rows.isEmpty
                    ? Center(child: Text('لا توجد سندات لعرضها', style: TextStyle(color: Colors.white70)))
                    : ListView.builder(
                  itemCount: _rows.length,
                  primary: true,
                  padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 20),
                  itemBuilder: (_, i) {
                    final r = _rows[i];
                    final title = r['product_name'] ?? r['barcode'] ?? '—';
                    final paid = (r['paid_amount'] as num?)?.toDouble() ?? 0.0;
                    final created = r['created_at'] ?? '';
                    final paymentType = _normalizePaymentType(r);
                    final paidColor = _paymentColor(paymentType) ?? Colors.white;

                    return Card(
                      color: AppColorsDark.bgCardColor,
                      margin: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '$title',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                _buildPaymentChip(paymentType),
                              ],
                            ),
                            const SizedBox(height: 8),
                            _buildInfoRow("استلم:", "${r['received_by'] ?? ''}"),
                            _buildInfoRow("كمية:", "${r['cartons'] ?? 0} كرتينات + ${r['units'] ?? 0} وحدات"),
                            _buildInfoRow("المدفوع:", paid.toStringAsFixed(2), valueColor: paidColor),
                            _buildInfoRow("التاريخ:", _fmtDate(created)),
                            if ((r['due_amount'] as num?)?.toDouble() != null && (r['due_amount'] as num?)!.toDouble() > 0)
                              _buildInfoRow(
                                "المتبقي (Due):",
                                ((r['due_amount'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(2),
                                valueColor: Colors.orangeAccent[200],
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

            // هنا: البوردات التفريعية حسب طريقة الدفع (اللوحة الأخيرة تحت الـ cards)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
              child: _buildSummaryBoards(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4.0),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: "$label ",
              style: TextStyle(color: Colors.grey[400], fontSize: 14),
            ),
            TextSpan(
              text: value,
              style: TextStyle(
                color: valueColor ?? Colors.white,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
