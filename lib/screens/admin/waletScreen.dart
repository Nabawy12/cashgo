// lib/screens/admin/card_wallet_activity_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../../utils/colors.dart';
import '../../services/db/db_helper.dart';

class CardWalletActivityScreen extends StatefulWidget {
  const CardWalletActivityScreen({super.key});
  static const routeName = '/card-wallet-activity';

  @override
  State<CardWalletActivityScreen> createState() => _CardWalletActivityScreenState();
}

class _CardWalletActivityScreenState extends State<CardWalletActivityScreen> {
  bool _loading = true;
  String? _error;

  // Structure: { '2025-08-26': { 'cashier1': [row, row], 'cashier2': [...] }, ... }
  final Map<String, Map<String, List<Map<String, dynamic>>>> _grouped = {};

  @override
  void initState() {
    super.initState();
    _loadTransactions();
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
          // fallback: treat as now
          dt = DateTime.now();
        }
        final dayKey = DateFormat('yyyy-MM-dd').format(dt);
        final cashier = (r['updated_by'] as String?) ?? 'غير معروف';

        _grouped.putIfAbsent(dayKey, () => {});
        final byCashier = _grouped[dayKey]!;
        byCashier.putIfAbsent(cashier, () => []);
        byCashier[cashier]!.add(Map<String, dynamic>.from(r));
      }

      // Sort lists by time descending inside each cashier
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

      setState(() {
        _loading = false;
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

  double _sumDay(String dayKey) {
    final byCashier = _grouped[dayKey]!;
    double s = 0.0;
    for (final cashier in byCashier.keys) {
      s += _sumListAmounts(byCashier[cashier]!);
    }
    return s;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColorsDark.bgColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('سجل الإيداع والسحب', style: TextStyle(color: Colors.white)),
        centerTitle: true,
        iconTheme: IconThemeData(
          color: Colors.white70
        ),
        actions: [
          IconButton(
            tooltip: 'تحديث',
            icon: const Icon(Icons.refresh),
            onPressed: _loadTransactions,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text('لم يتم اجراء اي عمليه حتي الآن', style: const TextStyle(color: Colors.white,fontSize: 25)))
          : _grouped.isEmpty
          ? const Center(child: Text('لا توجد عمليات حتى الآن', style: TextStyle(color: Colors.white70)))
          : Directionality(
            textDirection: TextDirection.rtl,
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _grouped.keys.length,
              itemBuilder: (ctx, idx) {
                final dayKey = _grouped.keys.elementAt(idx);
                final dayMap = _grouped[dayKey]!;
                final dayTotal = _sumDay(dayKey);

                // human-friendly date
                final parsed = DateTime.tryParse(dayKey + 'T00:00:00');
                final title = parsed != null ? DateFormat('EEEE, dd MMM yyyy', 'ar').format(parsed) : dayKey;

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
                        Text('الإجمالي لليوم: ${dayTotal.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                      ],
                    ),
                    children:

                    [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6),
                        child: Column(
                          children: dayMap.keys.map((cashier) {
                            final list = dayMap[cashier]!;
                            final total = _sumListAmounts(list);
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
                                    Text(total.toStringAsFixed(2), style: const TextStyle(color: Colors.white70)),
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

                                  return ListTile(
                                    dense: true,
                                    tileColor: AppColorsDark.bgColor,
                                    title: Row(
                                      children: [
                                        Expanded(child: Text(note, style: const TextStyle(color: Colors.white))),
                                        const SizedBox(width: 8),
                                        Text('${amt >= 0 ? '+' : ''}${amt.toStringAsFixed(2)}', style: TextStyle(color: amt >= 0 ? Colors.greenAccent : Colors.redAccent, fontWeight: FontWeight.bold)),
                                      ],
                                    ),
                                    subtitle: Text('الوقت: $timeStr', style: const TextStyle(color: Colors.white70)),
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
          ),
    );
  }
}
