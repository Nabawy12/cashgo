// admin_paid_purchases_screen.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:http/http.dart' as http;

import '../../utils/colors.dart';
import '../../widgets/Loading/Admin/invoice_cash.dart';

class AdminPaidPurchasesScreen extends StatefulWidget {
  const AdminPaidPurchasesScreen({Key? key}) : super(key: key);

  @override
  State<AdminPaidPurchasesScreen> createState() => _AdminPaidPurchasesScreenState();
}

class _AdminPaidPurchasesScreenState extends State<AdminPaidPurchasesScreen> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = false;
  String? _error;

  // totals by payment type
  double _cashTotal = 0.0;
  int _cashCount = 0;
  double _walletTotal = 0.0;
  int _walletCount = 0;
  double _cardTotal = 0.0;
  int _cardCount = 0;

  // ===== فلتر التاريخ =====
  DateTime selectedDate = DateTime.now();

  static const String _endpoint = 'https://nabawisolution.com/receive_from_supplier.php';

  @override
  void initState() {
    super.initState();
    _load(date: selectedDate);
  }

  Future<void> _load({DateTime? date}) async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final rows = await _fetchReceiptsFromServer(date: date);

      // الآن نفلتر لعرض سجلات الدفع الفعلي فقط:
      // فقط payment_type == 'cash' أو 'wallet'، ولا نعرض أي سجل به مبلغ آجل/credit (>0).
      List<Map<String, dynamic>> filtered = rows.where((r) {
        final pt = _effectivePaymentType(r);
        // show only cash or wallet (and card if you want)
        if (!(pt == 'cash' || pt == 'wallet')) return false;

        // exclude any record that still has due/credit > 0
        final due = _getDueAmount(r) ?? 0.0;
        if (due > 0.0) return false;

        if (date == null) return true;
        final raw = (r['created_at'] ?? r['receipt_date'] ?? r['date'] ?? '').toString();
        final dt = _parseDateOnly(raw);
        if (dt == null) return false;
        return dt.year == date.year && dt.month == date.month && dt.day == date.day;
      }).toList();

      _computeTotals(filtered);

      setState(() {
        _rows = filtered;
        _loading = false;
      });
    } catch (e, st) {
      debugPrint('Error loading paid purchase receipts: $e\n$st');
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<List<Map<String, dynamic>>> _fetchReceiptsFromServer({DateTime? date}) async {
    final qp = <String, String>{'action': 'get_goods_receipts'};
    if (date != null) {
      qp['date'] = DateFormat('yyyy-MM-dd').format(date);
    }

    final uri = Uri.parse(_endpoint).replace(queryParameters: qp);
    final resp = await http.get(uri).timeout(const Duration(seconds: 15));

    if (resp.statusCode != 200) {
      throw Exception('Server returned ${resp.statusCode}');
    }

    final body = resp.body.trim();
    if (body.isEmpty) return [];

    final jsonBody = jsonDecode(body);
    // API (as provided) returns: { success: true, data: [...] }
    List<dynamic> data = [];
    if (jsonBody is Map && jsonBody.containsKey('data')) {
      data = jsonBody['data'] as List<dynamic>;
    } else if (jsonBody is List) {
      data = jsonBody;
    } else {
      throw Exception('Unexpected response format from server');
    }

    // normalize into List<Map<String,dynamic>>
    return data.map<Map<String, dynamic>>((e) {
      if (e is Map<String, dynamic>) return e;
      return Map<String, dynamic>.from(e as Map);
    }).toList();
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
      // API field name: total_paid (or maybe totalPaid). allow fallback to 'paid_amount'
      final paid = _getPaidAmount(r);
      final pt = _effectivePaymentType(r);
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

  double _getPaidAmount(Map<String, dynamic> r) {
    final candidates = ['total_paid', 'totalPaid', 'paid', 'paid_amount', 'paidAmount'];
    for (final k in candidates) {
      final v = r[k];
      if (v == null) continue;
      if (v is num) return v.toDouble();
      final s = v.toString().replaceAll(',', '').trim();
      final d = double.tryParse(s);
      if (d != null) return d;
    }
    return 0.0;
  }

  /// يرجع اسم الكاشير من row بفحص عدة مفاتيح محتملة ثم إرجاع fallback '—' إذا كان فارغًا
  String _getCashierName(Map<String, dynamic> r) {
    final candidates = [
      'cashier_name',
      'cashierName',
      'received_by',
      'receivedBy',
      'received_by_name',
      'created_by',
      'user',
      'username'
    ];

    for (final k in candidates) {
      final v = r[k];
      if (v == null) continue;
      final s = v.toString().trim();
      if (s.isNotEmpty) return s;
    }

    return '—';
  }

  String _fmtDate(String s) {
    if (s.isEmpty) return s;
    try {
      final d = DateTime.parse(s);
      return DateFormat('yyyy-MM-dd HH:mm').format(d);
    } catch (_) {
      return s;
    }
  }

  String _normalizePaymentType(Map<String, dynamic> r) {
    final raw = (r['payment_type'] ?? r['paymentType'] ?? '').toString().trim().toLowerCase();
    if (raw.isEmpty) return 'cash';
    if (raw == 'wallet' || raw == 'card' || raw == 'cash') return raw;
    if (raw.contains('card')) return 'card';
    if (raw.contains('wallet') || raw.contains('محفظ')) return 'wallet';
    if (raw.contains('cash') || raw.contains('نقد')) return 'cash';
    return 'cash';
  }

  /// استخراج آخر وسيلة دفع ممكنة من الـ row (يحاول عدة مفاتيح محتملة)
  String? _extractLastPaymentMethod(Map<String, dynamic> r) {
    // مفاتيح محتملة نصية مباشرة
    final keys = ['last_payment_method', 'lastPaymentMethod', 'last_payment_type', 'lastPaymentType', 'last_method', 'recent_payment_method', 'recentPaymentMethod'];
    for (final k in keys) {
      final v = r[k];
      if (v == null) continue;
      final s = v.toString().trim();
      if (s.isNotEmpty) return s;
    }

    // لو فيه حقل payments أو payment_history كمصفوفة، حاول نأخذ آخر عنصر
    final paymentsCandidates = ['payments', 'payment_history', 'payments_history', 'paymentsList', 'paymentHistory'];
    for (final k in paymentsCandidates) {
      final v = r[k];
      if (v == null) continue;
      if (v is List && v.isNotEmpty) {
        final last = v.last;
        if (last is Map) {
          final maybe = (last['method'] ?? last['payment_type'] ?? last['type'] ?? last['paymentMethod'] ?? last['method_name']);
          if (maybe != null) {
            final s = maybe.toString().trim();
            if (s.isNotEmpty) return s;
          }
        } else {
          final s = last.toString().trim();
          if (s.isNotEmpty) return s;
        }
      }
    }

    return null;
  }

  /// إرجاع paymentType "النهائي" الذي نعرضه/نحسب به:
  /// - لو لم يعد هناك credit (due == 0) نحاول استخدام آخر وسيلة دفع فعليّة إذا وجدت
  /// - وإلا نعيد _normalizePaymentType(r)
  String _effectivePaymentType(Map<String, dynamic> r) {
    final due = _getDueAmount(r) ?? 0.0;
    if (due <= 0.0001) {
      // حاول استخراج آخر وسيلة دفع
      final last = _extractLastPaymentMethod(r);
      if (last != null && last.isNotEmpty) {
        final l = last.toLowerCase();
        if (l.contains('wallet') || l.contains('محفظ')) return 'wallet';
        if (l.contains('card')) return 'card';
        if (l.contains('cash') || l.contains('نقد')) return 'cash';
        // قد يكون قيمة مسماة أخرى (مثلاً 'cashout'...) — حاول تطبيعها باستخدام normalize
        final fakeMap = {'payment_type': last};
        final norm = _normalizePaymentType(fakeMap);
        if (norm.isNotEmpty) return norm;
      }

      // لو لم نجد آخر وسيلة دفع خدي fallback:
      final normExisting = _normalizePaymentType(r);
      if (normExisting == 'credit') {
        // إذا السجل بلا دين لكن ما زال type 'credit'، فمن الأجدر اعتباره نقدي كـ fallback
        return 'cash';
      }
      return normExisting;
    } else {
      return _normalizePaymentType(r);
    }
  }

  Color? _paymentColor(String paymentType) {
    switch (paymentType) {
      case 'cash':
        return AppColorsDark.bgColor;
      case 'wallet':
        return AppColorsDark.bgColor;
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
        : paymentType == 'card'
        ? 'بطاقة'
        : paymentType;
    return Chip(
      label: Text(label, style: const TextStyle(color: Colors.white, fontSize: 15,fontWeight: FontWeight.bold)),
      backgroundColor: _paymentColor(paymentType),
      visualDensity: VisualDensity.compact,
      shape: RoundedRectangleBorder(
          side: BorderSide(
              color:
              label == 'محفظة إلكترونية' ?
              Colors.blueAccent : Colors.green,
              width: 1.5
          ),
          borderRadius: BorderRadius.circular(15)
      ),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  Widget _buildSummaryBoards() {
    Widget board(String title, int count, double total, Color bg) {
      return Expanded(
        child: Card(
          color: bg.withOpacity(0.1),
          shape: RoundedRectangleBorder(side: BorderSide(color: bg), borderRadius: BorderRadius.circular(12)),
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
          ? ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: 6, // عدد عناصر shimmer المراد عرضها أثناء التحميل
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          return LoadingShimmer(
            height: 80,
            borderRadius: BorderRadius.circular(10),
            padding: const EdgeInsets.symmetric(horizontal: 12),
          );
        },
      )
          : Directionality(
        textDirection: TextDirection.rtl,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // التاريخ
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
                        Text('التاريخ', style: TextStyle(color: Colors.white70, fontSize: 13)),
                        const SizedBox(height: 4),
                        Text(_formatSelectedDate(selectedDate), style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // error
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text('حدث خطأ: $_error', style: const TextStyle(color: Colors.redAccent)),
              ),
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
                    final paid = _getPaidAmount(r);
                    final created = (r['created_at'] ?? r['receipt_date'] ?? '').toString();
                    final paymentType = _effectivePaymentType(r);

                    return Card(
                      color: AppColorsDark.bgCardColor,
                      margin: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text('$title', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                                ),
                                const SizedBox(width: 8),
                                _buildPaymentChip(paymentType),
                              ],
                            ),
                            const SizedBox(height: 8),
                            _buildInfoRow("استلم:", _getCashierName(r)),
                            _buildInfoRow("الكمية:", "${r['cartons'] ?? 0} كرتينات + ${r['units'] ?? 0} وحدات"),
                            _buildInfoRow("المدفوع:", paid.toStringAsFixed(1), valueColor: Colors.green),
                            _buildInfoRow("التاريخ:", _fmtDate(created)),
                            if ((_getDueAmount(r) ?? 0.0) > 0)
                              _buildInfoRow("المتبقي (Due):", (_getDueAmount(r) ?? 0.0).toStringAsFixed(2), valueColor: Colors.orangeAccent[200]),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
              child: _buildSummaryBoards(),
            ),
          ],
        ),
      ),
    );
  }

  double? _getDueAmount(Map<String, dynamic> r) {
    // support many possible keys, including credit_amount which we want to check
    final candidates = ['credit_amount', 'creditAmount', 'due_amount', 'due', 'remaining', 'dueAmount'];
    for (final k in candidates) {
      final v = r[k];
      if (v == null) continue;
      if (v is num) return v.toDouble();
      final s = v.toString().replaceAll(',', '').trim();
      final d = double.tryParse(s);
      if (d != null) return d;
    }
    return null;
  }

  Widget _buildInfoRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4.0),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: "$label ", style: TextStyle(color: Colors.grey[400], fontSize: 14)),
            TextSpan(text: value, style: TextStyle(color: valueColor ?? Colors.white, fontSize: 14)),
          ],
        ),
      ),
    );
  }
}
