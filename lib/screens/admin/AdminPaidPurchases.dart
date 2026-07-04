// admin_paid_purchases_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../services/db/db_helper.dart';
import '../../utils/colors.dart';
import '../../widgets/Loading/Admin/invoice_cash.dart';
import '../../widgets/empty_state_card.dart';

/// لوحة الألوان المستخدمة في تصميم شاشة المشتريات المدفوعة الجديدة
class _Palette {
  static const Color background = Color(0xFF0A0E1A);
  static const Color card = Color(0xFF141826);
  static const Color cardBorder = Color(0xFF232838);
  static const Color rowDivider = Color(0xFF1C2130);

  static const Color blue = Color(0xFF3B82F6);
  static const Color green = Color(0xFF22C55E);
  static const Color purple = Color(0xFF8B5CF6);
  static const Color orange = Color(0xFFF59E0B);

  static const Color textPrimary = Colors.white;
  static const Color textSecondary = Color(0xFF8B93A7);
}

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
  final ScrollController _verticalController = ScrollController();
  final ScrollController _horizontalController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

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
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text);
    });
    _load(date: selectedDate);
  }

  @override
  void dispose() {
    _verticalController.dispose();
    _horizontalController.dispose();
    _searchController.dispose();
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

  String _fmtDateShort(String s) {
    if (s.isEmpty) return '—';
    try {
      final d = DateTime.parse(s);
      return DateFormat('dd/MM/yyyy').format(d);
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

  String? _extractLastPaymentMethod(Map<String, dynamic> r) {
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

  String _effectivePaymentType(Map<String, dynamic> r) {
    final due = _getDueAmount(r) ?? 0.0;
    if (due <= 0.0001) {
      final last = _extractLastPaymentMethod(r);
      if (last != null && last.isNotEmpty) {
        final l = last.toLowerCase();
        if (l.contains('wallet') || l.contains('محفظ')) return 'wallet';
        if (l.contains('card')) return 'card';
        if (l.contains('cash') || l.contains('نقد')) return 'cash';
        final fakeMap = {'payment_type': last};
        final norm = _normalizePaymentType(fakeMap);
        if (norm.isNotEmpty) return norm;
      }

      final normExisting = _normalizePaymentType(r);
      if (normExisting == 'credit') {
        return 'cash';
      }
      return normExisting;
    } else {
      return _normalizePaymentType(r);
    }
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

  /// هل السند اتدفع على أكتر من دفعة (جزئي) ولا مرة واحدة (كامل)
  bool _isPartialPayment(Map<String, dynamic> r) {
    return _paymentHistory(r).length > 1;
  }

  /// رقم السند المعروض في الجدول
  String _getReceiptNumber(Map<String, dynamic> r, int fallbackIndex) {
    final candidates = ['receipt_number', 'invoice_number', 'code', 'id'];
    for (final k in candidates) {
      final v = r[k];
      if (v == null) continue;
      final s = v.toString().trim();
      if (s.isNotEmpty) {
        final numeric = int.tryParse(s);
        if (numeric != null) {
          return 'PUR-${numeric.toString().padLeft(4, '0')}';
        }
        return s;
      }
    }
    return 'PUR-${(fallbackIndex + 1).toString().padLeft(4, '0')}';
  }

  double? _getDueAmount(Map<String, dynamic> r) {
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

  List<Map<String, dynamic>> get _displayedRows {
    if (_searchQuery.trim().isEmpty) return _rows;
    final q = _searchQuery.trim().toLowerCase();
    final result = <Map<String, dynamic>>[];
    for (var i = 0; i < _rows.length; i++) {
      final r = _rows[i];
      final name = _getProductName(r).toLowerCase();
      final number = _getReceiptNumber(r, i).toLowerCase();
      if (name.contains(q) || number.contains(q)) result.add(r);
    }
    return result;
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

  String _formatSelectedDate(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';

  // ============================= UI =============================

  @override
  Widget build(BuildContext context) {
    final totalPaidAll = _cashTotal + _walletTotal + _cardTotal;

    return Scaffold(
      backgroundColor: AppColorsDark.bgColor,
      appBar: AppBar(
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0.0,
        scrolledUnderElevation: 0.0,
        iconTheme: const IconThemeData(color: _Palette.textPrimary),
        title: const Text(
          'المشتريات المدفوعة',
          style: TextStyle(color: _Palette.textPrimary),
        ),
        actions: [
          IconButton(
            tooltip: "إعادة تحميل (فلتر التاريخ الحالي)",
            onPressed: () => _load(date: selectedDate),
            icon: const Icon(Icons.refresh, color: _Palette.textPrimary),
          )
        ],
      ),
      body: _loading
          ? ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: 6,
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
          children: [
            // ===== التاريخ =====
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 4),
              child: GestureDetector(
                onTap: _pickDate,
                child: Column(
                  children: [
                    const Text('التاريخ',
                        style: TextStyle(
                            color: _Palette.textSecondary,
                            fontSize: 13)),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_formatSelectedDate(selectedDate),
                            style: const TextStyle(
                                color: _Palette.textPrimary,
                                fontSize: 16,
                                fontWeight: FontWeight.bold)),
                        const SizedBox(width: 6),
                        const Icon(Icons.calendar_today_outlined,
                            size: 16, color: _Palette.textSecondary),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text('حدث خطأ: $_error',
                    style: const TextStyle(color: Colors.redAccent)),
              ),

            // ===== كروت الإحصائيات العلوية =====
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: LayoutBuilder(builder: (context, constraints) {
                final cards = [
                  _statCard(
                    icon: Icons.shopping_bag_outlined,
                    iconColor: _Palette.blue,
                    title: 'إجمالي المدفوع اليوم',
                    value: 'EGP ${totalPaidAll.toStringAsFixed(2)}',
                  ),
                  _statCard(
                    icon: Icons.payments_outlined,
                    iconColor: _Palette.green,
                    title: 'إجمالي مدفوع نقدي',
                    value: 'EGP ${_cashTotal.toStringAsFixed(2)}',
                  ),
                  _statCard(
                    icon: Icons.account_balance_wallet_outlined,
                    iconColor: _Palette.purple,
                    title: 'إجمالي مدفوع بمحفظة',
                    value: 'EGP ${_walletTotal.toStringAsFixed(2)}',
                  ),
                  _statCard(
                    icon: Icons.description_outlined,
                    iconColor: _Palette.orange,
                    title: 'عدد السندات',
                    value: '${_rows.length}',
                  ),
                ];
                final isWide = constraints.maxWidth > 800;
                if (isWide) {
                  return Row(
                    children: cards
                        .map((c) => Expanded(
                        child: Padding(
                            padding:
                            const EdgeInsets.symmetric(horizontal: 6),
                            child: c)))
                        .toList(),
                  );
                }
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children:
                  cards.map((c) => SizedBox(width: 260, child: c)).toList(),
                );
              }),
            ),

            // ===== شريط البحث =====
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Container(
                decoration: BoxDecoration(
                  color: _Palette.card,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _Palette.cardBorder),
                ),
                child: TextField(
                  controller: _searchController,
                  style: const TextStyle(color: _Palette.textPrimary),
                  decoration: const InputDecoration(
                    hintText: 'ابحث برقم السند أو اسم المنتج',
                    hintStyle: TextStyle(color: _Palette.textSecondary),
                    prefixIcon:
                    Icon(Icons.search, color: _Palette.textSecondary),
                    border: InputBorder.none,
                    contentPadding:
                    EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 8),

            // ===== الجدول =====
            Expanded(
              child: _rows.isEmpty
                  ? const EmptyStateCard(
                icon: Icons.assignment_turned_in,
                title: 'لا توجد سندات',
                message: 'لا توجد سندات مدفوعة في هذا التاريخ.',
              )
                  : _buildTable(),
            ),

            // ===== كروت الملخص السفلية =====
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: LayoutBuilder(builder: (context, constraints) {
                final wallet = _bottomStatCard(
                  icon: Icons.account_balance_wallet_outlined,
                  color: _Palette.purple,
                  title: 'مدفوع بمحفظة',
                  count: _walletCount,
                  total: _walletTotal,
                );
                final cash = _bottomStatCard(
                  icon: Icons.payments_outlined,
                  color: _Palette.green,
                  title: 'مدفوع نقدي',
                  count: _cashCount,
                  total: _cashTotal,
                );
                final isWide = constraints.maxWidth > 500;
                final children = <Widget>[
                  Expanded(child: wallet),
                  const SizedBox(width: 12, height: 12),
                  Expanded(child: cash),
                ];
                return Column(
                  children: [
                    isWide
                        ? Row(children: children)
                        : Column(
                      children: [
                        wallet,
                        const SizedBox(height: 12),
                        cash,
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.info_outline,
                            size: 14, color: _Palette.textSecondary),
                        SizedBox(width: 6),
                        Text(
                          'يتم تحديث البيانات تلقائياً عند تسجيل أي دفعة جديدة',
                          style: TextStyle(
                              color: _Palette.textSecondary, fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                );
              }),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- كرت إحصائية علوي ----------
  Widget _statCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String value,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _Palette.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _Palette.cardBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: _Palette.textSecondary, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Text(value,
                    style: TextStyle(
                        color: iconColor,
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------- كرت ملخص سفلي ----------
  Widget _bottomStatCard({
    required IconData icon,
    required Color color,
    required String title,
    required int count,
    required double total,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 10),
          Text(title,
              style: const TextStyle(color: _Palette.textSecondary, fontSize: 13)),
          const SizedBox(height: 6),
          Text('$count سند',
              style: const TextStyle(
                  color: _Palette.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 14)),
          const SizedBox(height: 6),
          Text('EGP ${total.toStringAsFixed(2)}',
              style: TextStyle(
                  color: color, fontSize: 20, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  // ---------- الجدول ----------
  // الأوزان النسبية للأعمدة (بتتحول لـ flex لما الجدول ياخد المساحة كلها)
  static const int _fReceipt = 11;
  static const int _fProduct = 23;
  static const int _fDate = 13;
  static const int _fMethod = 14;
  static const int _fType = 10;
  static const int _fAmount = 14;
  static const int _fActions = 15;

  // أقل عرض تقريبي بالبكسل لكل عمود (بيتستخدم فقط لما الجدول محتاج سكرول أفقي
  // على الشاشات الضيقة جدًا)
  static const double _wReceipt = 110;
  static const double _wProduct = 230;
  static const double _wDate = 130;
  static const double _wMethod = 140;
  static const double _wType = 100;
  static const double _wAmount = 140;
  static const double _wActions = 150;

  double get _tableMinWidth =>
      _wReceipt + _wProduct + _wDate + _wMethod + _wType + _wAmount + _wActions;

  Widget _buildTable() {
    final rows = _displayedRows;
    return LayoutBuilder(builder: (context, constraints) {
      // لو المساحة المتاحة كافية، الجدول بياخد عرض الشاشة كلها بدون سكرول أفقي
      final fillAvailableWidth = constraints.maxWidth >= _tableMinWidth;

      final table = SizedBox(
        width: fillAvailableWidth ? constraints.maxWidth : _tableMinWidth,
        child: Column(
          children: [
            _tableHeader(useFlex: fillAvailableWidth),
            Expanded(
              child: rows.isEmpty
                  ? const Padding(
                padding: EdgeInsets.all(24),
                child: Text('لا توجد نتائج مطابقة للبحث',
                    style: TextStyle(color: _Palette.textSecondary)),
              )
                  : Scrollbar(
                controller: _verticalController,
                thumbVisibility: true,
                child: ListView.builder(
                  controller: _verticalController,
                  itemCount: rows.length,
                  itemBuilder: (_, i) =>
                      _tableRow(rows[i], i, useFlex: fillAvailableWidth),
                ),
              ),
            ),
          ],
        ),
      );

      if (fillAvailableWidth) return table;

      return Scrollbar(
        controller: _horizontalController,
        child: SingleChildScrollView(
          controller: _horizontalController,
          scrollDirection: Axis.horizontal,
          child: table,
        ),
      );
    });
  }

  /// خلية جدول: بتاخد عرض ثابت (سكرول أفقي) أو Expanded بنسبة (ملء الشاشة)
  Widget _cell({
    required Widget child,
    required double width,
    required int flex,
    required bool useFlex,
  }) {
    if (useFlex) return Expanded(flex: flex, child: child);
    return SizedBox(width: width, child: child);
  }

  Widget _tableHeader({required bool useFlex}) {
    Widget h(String text, double width, int flex) => _cell(
      width: width,
      flex: flex,
      useFlex: useFlex,
      child: Text(text,
          textAlign: TextAlign.center,
          style: const TextStyle(
              color: _Palette.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w600)),
    );
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _Palette.cardBorder, width: 1)),
      ),
      child: Row(
        children: [
          h('رقم السند', _wReceipt, _fReceipt),
          h('اسم المنتج', _wProduct, _fProduct),
          h('تاريخ الدفع', _wDate, _fDate),
          h('طريقة الدفع', _wMethod, _fMethod),
          h('نوع الدفع', _wType, _fType),
          h('المبلغ المدفوع', _wAmount, _fAmount),
          h('الإجراءات', _wActions, _fActions),
        ],
      ),
    );
  }

  /// اسم المنتج بيتقرا من أول مفتاح موجود وقيمته مش فاضية
  String _getProductName(Map<String, dynamic> r) {
    final candidates = [
      'product_name',
      'productName',
      'name',
      'item_name',
      'itemName',
      'title',
      'barcode',
    ];
    for (final k in candidates) {
      final v = r[k];
      if (v == null) continue;
      final s = v.toString().trim();
      if (s.isNotEmpty) return s;
    }
    return '—';
  }

  Widget _tableRow(Map<String, dynamic> r, int index, {required bool useFlex}) {
    final title = _getProductName(r);
    final paid = _getPaidAmount(r);
    final created = (r['created_at'] ?? r['receipt_date'] ?? '').toString();
    final lastPaymentDate = _paymentHistory(r).isNotEmpty
        ? (_paymentHistory(r).last['created_at'] ?? created).toString()
        : created;
    final paymentType = _displayPaymentType(r);
    final isPartial = _isPartialPayment(r);
    final receiptNumber = _getReceiptNumber(r, index);

    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _Palette.rowDivider, width: 1)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      child: Row(
        children: [
          _cell(
            width: _wReceipt,
            flex: _fReceipt,
            useFlex: useFlex,
            child: Text(receiptNumber,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: _Palette.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
          ),
          _cell(
            width: _wProduct,
            flex: _fProduct,
            useFlex: useFlex,
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: _Palette.blue.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.inventory_2_outlined,
                      size: 16, color: _Palette.blue),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(title,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      style: const TextStyle(
                          color: _Palette.textPrimary, fontSize: 13)),
                ),
              ],
            ),
          ),
          _cell(
            width: _wDate,
            flex: _fDate,
            useFlex: useFlex,
            child: Text(_fmtDateShort(lastPaymentDate),
                textAlign: TextAlign.center,
                style: const TextStyle(color: _Palette.textSecondary, fontSize: 13)),
          ),
          _cell(
            width: _wMethod,
            flex: _fMethod,
            useFlex: useFlex,
            child: Center(child: _paymentMethodChip(paymentType)),
          ),
          _cell(
            width: _wType,
            flex: _fType,
            useFlex: useFlex,
            child: Center(child: _paymentTypeBadge(isPartial)),
          ),
          _cell(
            width: _wAmount,
            flex: _fAmount,
            useFlex: useFlex,
            child: Text('EGP ${paid.toStringAsFixed(2)}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: _Palette.green, fontSize: 13, fontWeight: FontWeight.w700)),
          ),
          _cell(
            width: _wActions,
            flex: _fActions,
            useFlex: useFlex,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _showDetailsDialog(r, receiptNumber),
                  icon: const Icon(Icons.visibility_outlined, size: 16),
                  label: const Text('عرض', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _Palette.textPrimary,
                    side: const BorderSide(color: _Palette.cardBorder),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                ),
                const SizedBox(width: 4),
                PopupMenuButton<String>(
                  color: _Palette.card,
                  icon: const Icon(Icons.more_horiz, color: _Palette.textSecondary),
                  onSelected: (v) {
                    if (v == 'details') _showDetailsDialog(r, receiptNumber);
                    if (v == 'print') {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('ميزة الطباعة قريباً')),
                      );
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                        value: 'details',
                        child: Text('تفاصيل السند',
                            style: TextStyle(color: _Palette.textPrimary))),
                    PopupMenuItem(
                        value: 'print',
                        child: Text('طباعة',
                            style: TextStyle(color: _Palette.textPrimary))),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _paymentMethodChip(String paymentType) {
    IconData icon;
    Color color;
    String label;
    switch (paymentType) {
      case 'wallet':
        icon = Icons.account_balance_wallet_outlined;
        color = _Palette.purple;
        label = 'محفظة';
        break;
      case 'card':
        icon = Icons.credit_card_outlined;
        color = _Palette.orange;
        label = 'بطاقة';
        break;
      case 'mixed':
        icon = Icons.sync_alt;
        color = _Palette.blue;
        label = 'متعدد';
        break;
      default:
        icon = Icons.payments_outlined;
        color = _Palette.green;
        label = 'نقدي';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: color, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _paymentTypeBadge(bool isPartial) {
    final color = isPartial ? _Palette.orange : _Palette.green;
    final label = isPartial ? 'جزئي' : 'كامل';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }

  void _showDetailsDialog(Map<String, dynamic> r, String receiptNumber) {
    final history = _paymentHistory(r);
    final due = _getDueAmount(r) ?? 0.0;
    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: _Palette.card,
          title: Text('تفاصيل السند $receiptNumber',
              style: const TextStyle(color: _Palette.textPrimary)),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _dialogInfoRow('المنتج:', _getProductName(r)),
                _dialogInfoRow('استلم:', _getCashierName(r)),
                _dialogInfoRow('الكمية:',
                    '${r['cartons'] ?? 0} كرتونه + ${r['units'] ?? 0} وحدات'),
                _dialogInfoRow('المدفوع:',
                    'EGP ${_getPaidAmount(r).toStringAsFixed(2)}',
                    color: _Palette.green),
                _dialogInfoRow('التاريخ:',
                    _fmtDate((r['created_at'] ?? r['receipt_date'] ?? '').toString())),
                if (due > 0)
                  _dialogInfoRow('المتبقي:', due.toStringAsFixed(2),
                      color: _Palette.orange),
                if (history.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  const Text('تفاصيل الدفعات:',
                      style: TextStyle(
                          color: _Palette.textSecondary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  ...history.asMap().entries.map((entry) {
                    final i = entry.key + 1;
                    final p = entry.value;
                    final method = _paymentMethodLabel(
                        (p['payment_method'] ?? '').toString());
                    final amount = _getPaidAmount(p);
                    final created = (p['created_at'] ?? '').toString();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        'الدفعة $i: $method - ${amount.toStringAsFixed(2)}'
                            '${created.isEmpty ? '' : ' (${_fmtDate(created)})'}',
                        style: const TextStyle(
                            color: _Palette.textPrimary, fontSize: 13),
                      ),
                    );
                  }),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('إغلاق'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dialogInfoRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
                text: "$label ",
                style: const TextStyle(color: _Palette.textSecondary, fontSize: 14)),
            TextSpan(
                text: value,
                style: TextStyle(
                    color: color ?? _Palette.textPrimary, fontSize: 14)),
          ],
        ),
      ),
    );
  }
}
