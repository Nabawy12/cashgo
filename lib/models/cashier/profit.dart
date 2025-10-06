// models/profit.dart
class Profit {
  final int id;
  final String cashierName;
  final double profitValueCash;
  final double profitValueWallet;
  final double total_in_drawer;
  final double total_in_wallet;
  final double cash_with_credit;
  final double purchases_paid;
  final double purchases_credit;
  final double wallet_received;
  final double cash_received;
  final String recordedAt;

  Profit(
       {
    required this.wallet_received,
    required this.cash_received,
    required this.purchases_paid,
    required this.purchases_credit,
    required this.cash_with_credit,
    required this.total_in_wallet,
    required this.total_in_drawer,
    required this.id,
    required this.cashierName,
    required this.profitValueCash,
    required this.profitValueWallet,
    required this.recordedAt,
  }) ;
  factory Profit.fromJson(Map<String, dynamic> json) {
    // guard parsing for different types
    int parseInt(dynamic v) {
      if (v is int) return v;
      if (v is String) return int.tryParse(v) ?? 0;
      if (v is double) return v.toInt();
      return 0;
    }

    double parseDouble(dynamic v) {
      if (v is double) return v;
      if (v is int) return v.toDouble();
      if (v is String) return double.tryParse(v) ?? 0.0;
      return 0.0;
    }

    return Profit(
      id: parseInt(json['id']),
      cashierName: json['cashier_name']?.toString() ?? '',
      profitValueCash: parseDouble(json['profit_value_cash']),
      profitValueWallet: parseDouble(json['profit_value_wallet']),
      total_in_wallet: parseDouble(json['total_in_wallet']),
      total_in_drawer: parseDouble(json['total_in_drawer']),
      cash_with_credit: parseDouble(json['cash_with_credit']),
      purchases_paid: parseDouble(json['purchases_paid']),
      purchases_credit: parseDouble(json['purchases_credit']),
      wallet_received: parseDouble(json['wallet_received']),
      cash_received: parseDouble(json['cash_received']),
      recordedAt: json['recorded_at']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'cashier_name': cashierName,
    'profit_value_cash': profitValueCash,
    'profit_value_wallet': profitValueWallet,
    'total_in_wallet': total_in_wallet,
    'total_in_drawer': total_in_drawer,
    'cash_with_credit': cash_with_credit,
    'purchases_paid': purchases_paid,
    'purchases_credit': purchases_credit,
    'wallet_received': wallet_received,
    'cash_received': cash_received,
    'recorded_at': recordedAt,
  };
}
