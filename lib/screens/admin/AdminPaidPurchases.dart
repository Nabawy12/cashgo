// admin_paid_purchases_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../services/db/db_helper.dart';
import '../../utils/colors.dart';
import '../../widgets/Loading/Admin/invoice_cash.dart';
import '../../widgets/empty_state_card.dart';

class AdminPaidPurchasesScreen extends StatefulWidget {
  const AdminPaidPurchasesScreen({Key? key}) : super(key: key);

  @override
  State<AdminPaidPurchasesScreen> createState() =>
      _AdminPaidPurchasesScreenState();
}

class _AdminPaidPurchasesScreenState extends State<AdminPaidPurchasesScreen> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = false;
  String? _error;
  final ScrollController _scrollController = ScrollController();

  // totals by payment type
  double _cashTotal = 0.0;
  int _cashCount = 0;
  double _walletTotal = 0.0;
  int _walletCount = 0;
  double _cardTotal = 0.0;
  int _cardCount = 0;

  // ===== فلتر التاريخ =====
  DateTime selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _load(date: selectedDate);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load({DateTime? date}) async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final rows = await _fetchReceiptsFromServer(date: date);

      // نعرض السندات التي اكتمل دفعها، حتى لو اتدفعت على أكثر من مرحلة.
      List<Map<String, dynamic>> filtered = rows.where((r) {
        // exclude any record that still has due/credit > 0
        final due = _getDueAmount(r) ?? 0.0;
        if (due > 0.0) return false;
        if (_getPaidAmount(r) <= 0.0) return false;

        if (date == null) return true;
        return _matchesReceiptOrPaymentDate(r, date);
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

  Future<List<Map<String, dynamic>>> _fetchReceiptsFromServer(
      {DateTime? date}) async {
    return DBHelper.instance.getPaidPurchaseReceipts();
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
      final parts =
          raw.split(RegExp(r'[\s/\\\-]')).where((p) => p.isNotEmpty).toList();
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

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool _matchesReceiptOrPaymentDate(Map<String, dynamic> r, DateTime date) {
    final rawReceiptDate =
        (r['created_at'] ?? r['receipt_date'] ?? r['date'] ?? '').toString();
    final receiptDate = _parseDateOnly(rawReceiptDate);
    if (receiptDate != null && _sameDay(receiptDate, date)) return true;

    for (final payment in _paymentHistory(r)) {
      final paymentDate =
          _parseDateOnly((payment['created_at'] ?? '').toString());
      if (paymentDate != null && _sameDay(paymentDate, date)) return true;
    }
    return false;
  }

  void _computeTotals(List<Map<String, dynamic>> rows) {
    double cash = 0.0, wallet = 0.0, card = 0.0;
    int cashC = 0, walletC = 0, cardC = 0;

    for (final r in rows) {
      final paidByMethod = _paidByMethod(r);
      if ((paidByMethod['cash'] ?? 0.0) > 0) {
        cash += paidByMethod['cash']!;
        cashC++;
      }
      if ((paidByMethod['wallet'] ?? 0.0) > 0) {
        wallet += paidByMethod['wallet']!;
        walletC++;
      }
      if ((paidByMethod['card'] ?? 0.0) > 0) {
        card += paidByMethod['card']!;
        cardC++;
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
    final candidates = [
      'amount',
      'total_paid',
      'totalPaid',
      'paid',
      'paid_amount',
      'paidAmount'
    ];
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

  List<Map<String, dynamic>> _paymentHistory(Map<String, dynamic> r) {
    final raw = r['payment_history'] ?? r['payments'];
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((payment) => Map<String, dynamic>.from(payment))
          .toList();
    }
    return const [];
  }

  Map<String, double> _paidByMethod(Map<String, dynamic> r) {
    final out = {'cash': 0.0, 'wallet': 0.0, 'card': 0.0};
    final history = _paymentHistory(r);
    if (history.isNotEmpty) {
      for (final payment in history) {
        final method = _normalizePaymentType(payment);
        final amount = _getPaidAmount(payment);
        if (method == 'wallet') {
          out['wallet'] = out['wallet']! + amount;
        } else if (method == 'card') {
          out['card'] = out['card']! + amount;
        } else {
          out['cash'] = out['cash']! + amount;
        }
      }
      return out;
    }

    final paidCash = (r['paid_cash'] as num?)?.toDouble() ?? 0.0;
    final paidWallet = (r['paid_wallet'] as num?)?.toDouble() ?? 0.0;
    if (paidCash > 0 || paidWallet > 0) {
      out['cash'] = paidCash;
      out['wallet'] = paidWallet;
      return out;
    }

    final method = _effectivePaymentType(r);
    final paid = _getPaidAmount(r);
    if (method == 'wallet') {
      out['wallet'] = paid;
    } else if (method == 'card') {
      out['card'] = paid;
    } else {
      out['cash'] = paid;
    }
    return out;
  }

  String _paymentMethodLabel(String method) {
    final normalized = _normalizePaymentType({'payment_type': method});
    if (normalized == 'wallet') return 'محفظة';
    if (normalized == 'card') return 'بطاقة';
    return 'نقدي';
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
    final raw = (r['payment_type'] ??
            r['payment_method'] ??
            r['method'] ??
            r['paymentType'] ??
            '')
        .toString()
        .trim()
        .toLowerCase();
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
    final keys = [
      'last_payment_method',
      'lastPaymentMethod',
      'last_payment_type',
      'lastPaymentType',
      'last_method',
      'recent_payment_method',
      'recentPaymentMethod'
    ];
    for (final k in keys) {
      final v = r[k];
      if (v == null) continue;
      final s = v.toString().trim();
      if (s.isNotEmpty) return s;
    }

    // لو فيه حقل payments أو payment_history كمصفوفة، حاول نأخذ آخر عنصر
    final paymentsCandidates = [
      'payments',
      'payment_history',
      'payments_history',
      'paymentsList',
      'paymentHistory'
    ];
    for (final k in paymentsCandidates) {
      final v = r[k];
      if (v == null) continue;
      if (v is List && v.isNotEmpty) {
        final last = v.last;
        if (last is Map) {
          final maybe = (last['method'] ??
              last['payment_type'] ??
              last['type'] ??
              last['paymentMethod'] ??
              last['method_name']);
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
        return Theme.of(context).cardColor;
      case 'wallet':
        return Theme.of(context).cardColor;
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
            ? 'دفع بالمحفظة'
            : paymentType == 'card'
                ? 'بطاقة'
                : paymentType == 'mixed'
                    ? 'مدفوع على مراحل'
                    : paymentType;
    return Chip(
      label: Text(label,
          style: TextStyle(
              color: AppColorsDark.mainTextDark,
              fontSize: 15,
              fontWeight: FontWeight.bold)),
      backgroundColor: _paymentColor(paymentType),
      visualDensity: VisualDensity.compact,
      shape: RoundedRectangleBorder(
          side: BorderSide(
              color: label == 'دفع بالمحفظة' ? Colors.blueAccent : Colors.green,
              width: 1.5),
          borderRadius: BorderRadius.circular(15)),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  String _displayPaymentType(Map<String, dynamic> r) {
    final paidByMethod = _paidByMethod(r);
    final methodsCount = [
      paidByMethod['cash'] ?? 0.0,
      paidByMethod['wallet'] ?? 0.0,
      paidByMethod['card'] ?? 0.0,
    ].where((amount) => amount > 0).length;
    if (methodsCount > 1) return 'mixed';
    return _effectivePaymentType(r);
  }

  Widget _buildSummaryBoards() {
    Widget board(String title, int count, double total, Color bg) {
      return SizedBox(
        width: 220,
        child: Card(
          color: bg.withOpacity(0.1),
          shape: RoundedRectangleBorder(
              side: BorderSide(color: bg),
              borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(vertical: 16.0, horizontal: 12.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    style: TextStyle(
                        color: AppColorsDark.mainTextLight, fontSize: 14)),
                const SizedBox(height: 8),
                Text('$count سند',
                    style: TextStyle(
                        color: AppColorsDark.mainTextDark,
                        fontWeight: FontWeight.bold,
                        fontSize: 16)),
                const SizedBox(height: 8),
                Text(total.toStringAsFixed(2),
                    style: TextStyle(
                        color: AppColorsDark.mainTextDark,
                        fontSize: 18,
                        fontWeight: FontWeight.w800)),
              ],
            ),
          ),
        ),
      );
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 10,
        runSpacing: 10,
        children: [
          board('نقدي', _cashCount, _cashTotal, Colors.green),
          board('دفع بالمحفظة', _walletCount, _walletTotal, Colors.blueAccent),
        ],
      ),
    );
  }

  Widget _buildPaymentHistory(Map<String, dynamic> r) {
    final history = _paymentHistory(r);
    if (history.isEmpty) {
      final paidByMethod = _paidByMethod(r);
      final parts = <String>[];
      if ((paidByMethod['cash'] ?? 0.0) > 0) {
        parts.add('نقدي: ${paidByMethod['cash']!.toStringAsFixed(2)}');
      }
      if ((paidByMethod['wallet'] ?? 0.0) > 0) {
        parts.add('محفظة: ${paidByMethod['wallet']!.toStringAsFixed(2)}');
      }
      if ((paidByMethod['card'] ?? 0.0) > 0) {
        parts.add('بطاقة: ${paidByMethod['card']!.toStringAsFixed(2)}');
      }
      return _buildInfoRow(
        'تفاصيل الدفع:',
        parts.isEmpty ? 'غير محدد' : parts.join(' | '),
        valueColor: Colors.blueAccent,
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('تفاصيل الدفع:',
              style: TextStyle(color: Colors.grey[400], fontSize: 14)),
          const SizedBox(height: 6),
          ...history.asMap().entries.map((entry) {
            final index = entry.key + 1;
            final payment = entry.value;
            final method = _paymentMethodLabel(
                (payment['payment_method'] ?? '').toString());
            final amount = _getPaidAmount(payment);
            final created = (payment['created_at'] ?? '').toString();
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                'الدفعة $index: $method - ${amount.toStringAsFixed(2)}${created.isEmpty ? '' : ' (${_fmtDate(created)})'}',
                style:
                    TextStyle(color: AppColorsDark.mainTextDark, fontSize: 14),
              ),
            );
          }),
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
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0.0,
        scrolledUnderElevation: 0.0,
        iconTheme: IconThemeData(color: Theme.of(context).iconTheme.color),
        title: Text(
          'المشتريات المدفوعة',
          style: TextStyle(color: AppColorsDark.mainTextDark),
        ),
        actions: [
          IconButton(
            tooltip: "إعادة تحميل (فلتر التاريخ الحالي)",
            onPressed: () => _load(date: selectedDate),
            icon: Icon(Icons.refresh, color: Theme.of(context).iconTheme.color),
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
                    padding: const EdgeInsets.symmetric(
                        vertical: 12.0, horizontal: 16.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        GestureDetector(
                          onTap: _pickDate,
                          child: Column(
                            children: [
                              Text('التاريخ',
                                  style: TextStyle(
                                      color: AppColorsDark.mainTextLight,
                                      fontSize: 13)),
                              const SizedBox(height: 4),
                              Text(_formatSelectedDate(selectedDate),
                                  style: TextStyle(
                                      color: AppColorsDark.mainTextDark,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold)),
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
                      child: Text('حدث خطأ: $_error',
                          style: TextStyle(color: Colors.redAccent)),
                    ),
                  Expanded(
                    child: Scrollbar(
                      controller: _scrollController,
                      thumbVisibility: true,
                      child: _rows.isEmpty
                          ? const EmptyStateCard(
                              icon: Icons.assignment_turned_in,
                              title: 'لا توجد سندات',
                              message: 'لا توجد سندات مدفوعة في هذا التاريخ.',
                            )
                          : ListView.builder(
                              controller: _scrollController,
                              itemCount: _rows.length,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 30, vertical: 20),
                              itemBuilder: (_, i) {
                                final r = _rows[i];
                                final title =
                                    r['product_name'] ?? r['barcode'] ?? '—';
                                final paid = _getPaidAmount(r);
                                final created =
                                    (r['created_at'] ?? r['receipt_date'] ?? '')
                                        .toString();
                                final paymentType = _displayPaymentType(r);

                                return Card(
                                  color: Theme.of(context).cardColor,
                                  margin:
                                      const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                  child: Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          crossAxisAlignment:
                                              WrapCrossAlignment.center,
                                          children: [
                                            ConstrainedBox(
                                              constraints: const BoxConstraints(
                                                  minWidth: 160, maxWidth: 520),
                                              child: Text('$title',
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                      color: AppColorsDark
                                                          .mainTextDark,
                                                      fontSize: 18,
                                                      fontWeight:
                                                          FontWeight.bold)),
                                            ),
                                            _buildPaymentChip(paymentType),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        _buildInfoRow(
                                            "استلم:", _getCashierName(r)),
                                        _buildInfoRow("الكمية:",
                                            "${r['cartons'] ?? 0} كرتونه + ${r['units'] ?? 0} وحدات"),
                                        _buildInfoRow(
                                            "المدفوع:", paid.toStringAsFixed(1),
                                            valueColor: Colors.green),
                                        _buildPaymentHistory(r),
                                        _buildInfoRow(
                                            "التاريخ:", _fmtDate(created)),
                                        if ((_getDueAmount(r) ?? 0.0) > 0)
                                          _buildInfoRow(
                                              "المتبقي (Due):",
                                              (_getDueAmount(r) ?? 0.0)
                                                  .toStringAsFixed(2),
                                              valueColor:
                                                  Colors.orangeAccent[200]),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20.0, vertical: 12.0),
                    child: _buildSummaryBoards(),
                  ),
                ],
              ),
            ),
    );
  }

  double? _getDueAmount(Map<String, dynamic> r) {
    // support many possible keys, including credit_amount which we want to check
    final candidates = [
      'credit_amount',
      'creditAmount',
      'due_amount',
      'due',
      'remaining',
      'dueAmount'
    ];
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
            TextSpan(
                text: "$label ",
                style: TextStyle(color: Colors.grey[400], fontSize: 14)),
            TextSpan(
                text: value,
                style: TextStyle(
                    color: valueColor ?? AppColorsDark.mainTextDark,
                    fontSize: 14)),
          ],
        ),
      ),
    );
  }
}
