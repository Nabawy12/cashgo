// lib/screens/admin/card_wallet_activity_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../utils/colors.dart';
import '../../services/db/db_helper.dart';

/// ======================
/// Utility: Total of transfers from drawer to wallet (global)
/// ======================
Future<double> getTotalDrawerToWallet({dynamic database}) async {
  try {
    final db = database ?? await DBHelper.instance.database;

    // today's key e.g. "2025-09-14"
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

    // try SQL filter first (fast when created_at is ISO-like)
    List<Map<String, dynamic>> rows;
    try {
      rows = await db.rawQuery('SELECT * FROM card_wallet WHERE created_at LIKE ?', ['$today%']);
    } catch (_) {
      // fallback to selecting all and filtering in Dart
      rows = await db.rawQuery('SELECT * FROM card_wallet');
    }

    double total = 0.0;
    final fromKeywords = ['درج', 'drawer'];
    final toKeywords = ['محفظة', 'محفظه', 'محفظ', 'wallet'];

    for (final r in rows) {
      // If we selected all in fallback, ensure row is for today
      final createdStr = (r['created_at'] as String?) ?? '';
      bool rowIsToday = false;
      try {
        final dt = DateTime.parse(createdStr);
        rowIsToday = DateFormat('yyyy-MM-dd').format(dt) == today;
      } catch (_) {
        // if parsing failed, also check textual prefix match
        rowIsToday = createdStr.startsWith(today);
      }
      if (!rowIsToday) continue;

      final amt = (r['amount'] as num?)?.toDouble() ?? 0.0;

      if (r.containsKey('transfer_type')) {
        final tt = (r['transfer_type'] as String?) ?? '';
        if (tt == 'drawer_to_wallet' || tt == 'درج_الى_المحفظة') {
          total += amt;
          continue;
        }
      }

      final note = ((r['note'] as String?) ?? '').toLowerCase();
      final hasFrom = fromKeywords.any((k) => note.contains(k));
      final hasTo = toKeywords.any((k) => note.contains(k));
      if (hasFrom && hasTo) {
        total += amt;
      }
    }

    return total;
  } catch (e) {
    return 0.0;
  }
}

class CardWalletActivityScreen extends StatefulWidget {
  const CardWalletActivityScreen({super.key});
  static const routeName = '/card-wallet-activity';

  @override
  State<CardWalletActivityScreen> createState() => _CardWalletActivityScreenState();
}

class _CardWalletActivityScreenState extends State<CardWalletActivityScreen> {
  bool _loading = true;
  String? _error;
  double? _total; // global total (used when no specific day selected)

  // selected day as 'yyyy-MM-dd' if user picks a date
  String? _selectedDayKey;

  // Structure: { '2025-08-26': { 'cashier1': [row, row], ... }, ... }
  final Map<String, Map<String, List<Map<String, dynamic>>>> _grouped = {};

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _loadTransactions();
  }

  /// Helper: true if the row is a drawer->wallet transfer
  bool _isDrawerToWalletRow(Map<String, dynamic> r) {
    final fromKeywords = ['درج', 'drawer'];
    final toKeywords = ['محفظة', 'محفظه', 'محفظ', 'wallet'];

    if (r.containsKey('transfer_type')) {
      final tt = (r['transfer_type'] as String?) ?? '';
      if (tt == 'drawer_to_wallet' || tt == 'درج_الى_المحفظة') return true;
    }

    final note = ((r['note'] as String?) ?? '').toLowerCase();
    final hasFrom = fromKeywords.any((k) => note.contains(k));
    final hasTo = toKeywords.any((k) => note.contains(k));
    if (hasFrom && hasTo) return true;

    return false;
  }

  Future<void> _loadTransactions() async {
    setState(() {
      _loading = true;
      _error = null;
      _grouped.clear();
    });

    try {
      final db = await DBHelper.instance.database;
      final rows = await db.rawQuery('SELECT * FROM card_wallet ORDER BY created_at DESC');

      for (final r in rows) {
        final created = (r['created_at'] as String?) ?? '';
        DateTime dt;
        try {
          dt = DateTime.parse(created);
        } catch (_) {
          dt = DateTime.now();
        }
        final dayKey = DateFormat('yyyy-MM-dd').format(dt);
        final cashier = (r['updated_by'] as String?) ?? 'Unknown';

        _grouped.putIfAbsent(dayKey, () => {});
        final byCashier = _grouped[dayKey]!;
        byCashier.putIfAbsent(cashier, () => []);
        byCashier[cashier]!.add(Map<String, dynamic>.from(r));
      }

      // Sort each cashier list by created_at descending
      for (final day in _grouped.keys) {
        final byCashier = _grouped[day]!;
        for (final cashier in byCashier.keys) {
          byCashier[cashier]!.sort((a, b) {
            final ta = (a['created_at'] as String?) ?? '';
            final tb = (b['created_at'] as String?) ?? '';
            return tb.compareTo(ta);
          });
        }
      }

      // compute top AppBar total: either total for selected day (only if >0) or global total
      double computedTotal;
      if (_selectedDayKey != null && _grouped.containsKey(_selectedDayKey)) {
        computedTotal = _sumDayDrawer(_selectedDayKey!);
      } else {
        computedTotal = await getTotalDrawerToWallet();
      }

      setState(() {
        _loading = false;
        _total = computedTotal;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  double _sumListAmounts(List<Map<String, dynamic>> list) {
    double s = 0.0;
    for (final r in list) {
      s += (r['amount'] as num?)?.toDouble() ?? 0.0;
    }
    return s;
  }

  /// Sum only rows that are drawer->wallet in the provided list
  double _sumListDrawerToWallet(List<Map<String, dynamic>> list) {
    double s = 0.0;
    for (final r in list) {
      if (_isDrawerToWalletRow(r)) {
        s += (r['amount'] as num?)?.toDouble() ?? 0.0;
      }
    }
    return s;
  }

  /// Day total for drawer->wallet only
  double _sumDayDrawer(String dayKey) {
    if (!_grouped.containsKey(dayKey)) return 0.0;
    final byCashier = _grouped[dayKey]!;
    double s = 0.0;
    for (final cashier in byCashier.keys) {
      s += _sumListDrawerToWallet(byCashier[cashier]!);
    }
    return s;
  }

  Future<double> getDrawerToWalletTotal() async {
    return await getTotalDrawerToWallet();
  }

  /// Pick a date (default Flutter picker)
  Future<void> _pickDate() async {
    final initial = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );

    if (picked == null) return;

    final key = DateFormat('yyyy-MM-dd').format(picked);

    // store selection
    setState(() {
      _selectedDayKey = key;
    });

    // if grouped not loaded or day not present -> reload; else compute from memory
    if (_grouped.isEmpty || !_grouped.containsKey(key)) {
      setState(() {
        _loading = true;
      });
      await _loadTransactions();
    } else {
      setState(() {
        _total = _sumDayDrawer(key); // we compute and show it only if > 0 in build
      });
    }
  }

  /// Clear selected day (show all)
  Future<void> _clearSelectedDate() async {
    setState(() {
      _selectedDayKey = null;
      _loading = true;
    });
    await _loadTransactions();
  }

  @override
  Widget build(BuildContext context) {
    // day keys sorted descending
    final dayKeys = _grouped.keys.toList()..sort((a, b) => b.compareTo(a));
    // if selected day specified, display only that day (even if it has no records)
    final displayKeys = _selectedDayKey != null ? [_selectedDayKey!] : dayKeys;

    // AppBar title logic:
    // - If a day is selected and that day has drawer->wallet total > 0 -> show that day's total.
    // - If a day is selected but total == 0 -> do NOT show a total (only screen title).
    // - If no day selected -> show global total (_total).
    double? selectedDayTotal;
    if (_selectedDayKey != null && _grouped.containsKey(_selectedDayKey)) {
      selectedDayTotal = _sumDayDrawer(_selectedDayKey!);
    }

    return Scaffold(
      backgroundColor: AppColorsDark.bgColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Column(
          children: [
            if (_selectedDayKey != null)
            // selected day: show total only when > 0
              if ((selectedDayTotal ?? 0.0) > 0.0)
                Text(
                  selectedDayTotal!.toStringAsFixed(2),
                  style: const TextStyle(color: Colors.white),
                )
              else
                const Text('Card Wallet Activity', style: TextStyle(color: Colors.white))
            else
            // no selected day -> show global total (could be zero)
              Text(_total != null ? _total!.toStringAsFixed(2) : '...', style: const TextStyle(color: Colors.white)),
            if (_selectedDayKey != null)
              Text(
                DateFormat('EEEE, dd MMM yyyy', 'en').format(DateTime.parse(_selectedDayKey! + 'T00:00:00')),
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
          ],
        ),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white70),
        actions: [
          IconButton(
            tooltip: 'Pick date',
            icon: const Icon(Icons.calendar_today),
            onPressed: _pickDate,
          ),
          IconButton(
            tooltip: 'Clear selection',
            icon: const Icon(Icons.clear),
            onPressed: _clearSelectedDate,
          ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _loadTransactions,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
        child: Text(
          'Error: $_error',
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
      )
          : displayKeys.isEmpty
          ? const Center(child: Text('No transactions yet', style: TextStyle(color: Colors.white70)))
          : ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: displayKeys.length,
        itemBuilder: (ctx, idx) {
          final dayKey = displayKeys.elementAt(idx);

          // if chosen day has no records at all
          if (!_grouped.containsKey(dayKey)) {
            final parsed = DateTime.tryParse(dayKey + 'T00:00:00');
            final title = parsed != null ? DateFormat('EEEE, dd MMM yyyy', 'en').format(parsed) : dayKey;
            return Card(
              color: AppColorsDark.bgCardColor,
              margin: const EdgeInsets.symmetric(vertical: 8),
              child: ListTile(
                title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                subtitle: const Text('No transactions for this day', style: TextStyle(color: Colors.white70)),
              ),
            );
          }

          final dayMap = _grouped[dayKey]!;
          final dayDrawerTotal = _sumDayDrawer(dayKey);

          final parsed = DateTime.tryParse(dayKey + 'T00:00:00');
          final title = parsed != null ? DateFormat('EEEE, dd MMM yyyy', 'en').format(parsed) : dayKey;

          return Card(
            color: AppColorsDark.bgCardColor,
            margin: const EdgeInsets.symmetric(vertical: 8),
            child: ExpansionTile(
              collapsedIconColor: Colors.white70,
              iconColor: Colors.white,
              tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  // show day's Drawer->Wallet total only when > 0
                  if (dayDrawerTotal > 0)
                    Text('Drawer→Wallet total for the day: ${dayDrawerTotal.toStringAsFixed(2)}',
                        style: const TextStyle(color: Colors.white70, fontSize: 13)),
                ],
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6),
                  child: Column(
                    children: dayMap.keys.map((cashier) {
                      final list = dayMap[cashier]!;
                      final cashierDrawerTotal = _sumListDrawerToWallet(list);

                      return Container(
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColorsDark.bgColor,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: ExpansionTile(
                          title: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(cashier, style: const TextStyle(color: Colors.white, fontSize: 15)),
                              // show cashier subtotal only when > 0
                              if (cashierDrawerTotal > 0)
                                Text(cashierDrawerTotal.toStringAsFixed(2), style: const TextStyle(color: Colors.white70))
                              else
                                const SizedBox.shrink(),
                            ],
                          ),
                          children: list.map((row) {
                            final amt = (row['amount'] as num?)?.toDouble() ?? 0.0;
                            final note = (row['note'] as String?) ?? '';
                            final timeStr = () {
                              try {
                                final t = DateTime.parse((row['created_at'] as String?) ?? '');
                                return DateFormat('hh:mm a', 'en').format(t);
                              } catch (_) {
                                return '';
                              }
                            }();

                            final isDW = _isDrawerToWalletRow(row);

                            return ListTile(
                              dense: true,
                              tileColor: AppColorsDark.bgColor,
                              title: Row(
                                children: [
                                  Expanded(child: Text(note, style: const TextStyle(color: Colors.white))),
                                  const SizedBox(width: 8),
                                  if (isDW)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(4),
                                        color: Colors.white10,
                                      ),
                                      child: const Text('Drawer→Wallet', style: TextStyle(color: Colors.white70, fontSize: 11)),
                                    ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${amt >= 0 ? '+' : ''}${amt.toStringAsFixed(2)}',
                                    style: TextStyle(
                                        color: amt >= 0 ? Colors.greenAccent : Colors.redAccent, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                              subtitle: Text('Time: $timeStr', style: const TextStyle(color: Colors.white70)),
                            );
                          }).toList(),
                        ),
                      );
                    }).toList(),
                  ),
                )
              ],
            ),
          );
        },
      ),
    );
  }
}
