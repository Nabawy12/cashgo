import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DBHelper {
  static final DBHelper instance = DBHelper._init();
  static Database? _database;

  DBHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('pos_system.db_v2.148'); // keep your version
    return _database!;
  }

  Future<Database> _initDB(String fileName) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, fileName);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
      onOpen: (db) async {
        try {
          await _ensureUnitsRemainderColumn(db);
        } catch (_) {}
        try {
          await _ensureSaleColumns(db);
        } catch (_) {}
        try {
          await _ensureProductDatesColumns(db);
        } catch (_) {}
        try {
          await _ensureExpirySeenColumn(db);
        } catch (_) {}
        try {
          await _ensureLowStockSeenColumn(db);
        } catch (_) {}
        try {
          await _ensurePurchaseReceiptsTable(db);
        } catch (_) {}
        try {
          await _ensurePurchaseReceiptsColumns(db);
        } catch (_) {}
        try { await _ensureCashDrawerTable(db); } catch (_) {}

        try { await _ensureIsCurrentUserColumn(db); } catch (_) {}

        try { await _ensureSalePaymentMethodColumn(db); } catch (_) {}

        try { await _ensureSaleCardTransferredColumn(db); } catch (_) {}

        try { await _ensureSaleDiscountColumns(db); } catch (_) {}
        try { await _ensureProductDatesColumns(db); } catch (_) {}






      },
    );
  }

  Future _createDB(Database db, int version) async {
    // users
    await db.execute(
      """CREATE TABLE users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT NOT NULL UNIQUE,
        password TEXT NOT NULL,
        role TEXT NOT NULL
      )""",
    );

    // products
    await db.execute(
      """CREATE TABLE products (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        barcode TEXT,
        name TEXT NOT NULL,
        purchase_price REAL NOT NULL,
        selling_price REAL NOT NULL,
        quantity INTEGER NOT NULL,
        units_in_carton INTEGER NOT NULL,
        units_remainder INTEGER NOT NULL DEFAULT 0,
        production_date TEXT,
        expiry_date TEXT,
        low_stock_seen INTEGER NOT NULL DEFAULT 0,
        expiry_seen INTEGER NOT NULL DEFAULT 0
      )""",
    );

// داخل _createDB -> CREATE TABLE sales ( ... )
    await db.execute(
      """CREATE TABLE sales (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    total REAL NOT NULL,
    date TEXT NOT NULL,
    cashier_username TEXT,
    paid_amount REAL NOT NULL DEFAULT 0,
    change_amount REAL NOT NULL DEFAULT 0,
    is_credit INTEGER NOT NULL DEFAULT 0,
    is_return INTEGER NOT NULL DEFAULT 0,
    return_of_sale_id INTEGER,
    return_note TEXT,
    customer_name TEXT,
    payment_method TEXT NOT NULL DEFAULT 'cash',
    discount_type TEXT NOT NULL DEFAULT 'fixed',   -- NEW
    discount_value REAL NOT NULL DEFAULT 0        -- NEW
  )""",
    );


    // sale_items
    await db.execute(
      """CREATE TABLE sale_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sale_id INTEGER NOT NULL,
        product_id INTEGER NOT NULL,
        quantity INTEGER NOT NULL,
        price REAL NOT NULL,
        FOREIGN KEY (sale_id) REFERENCES sales(id),
        FOREIGN KEY (product_id) REFERENCES products(id)
      )""",
    );

    // sale_returns
    await db.execute(
      """CREATE TABLE sale_returns (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sale_id INTEGER NOT NULL,
        date TEXT NOT NULL,
        cashier_username TEXT,
        paid_delta REAL NOT NULL DEFAULT 0,
        note TEXT
      )""",
    );

    // sale_return_items
    await db.execute(
      """CREATE TABLE sale_return_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        return_id INTEGER NOT NULL,
        product_id INTEGER NOT NULL,
        qty INTEGER NOT NULL,
        is_replacement INTEGER NOT NULL DEFAULT 0,
        price REAL NOT NULL,
        FOREIGN KEY (return_id) REFERENCES sale_returns(id),
        FOREIGN KEY (product_id) REFERENCES products(id)
      )""",
    );

    // purchase_receipts (log of supplier receipts) - includes payment tracking
    await db.execute(
      """CREATE TABLE purchase_receipts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id INTEGER,
        product_name TEXT,
        barcode TEXT,
        received_by TEXT,
        cartons INTEGER NOT NULL DEFAULT 0,
        units INTEGER NOT NULL DEFAULT 0,
        units_in_carton INTEGER NOT NULL DEFAULT 1,
        purchase_price_per_carton REAL,
        purchase_price_per_unit REAL,
        payment_type TEXT NOT NULL DEFAULT 'cash',
        paid_amount REAL NOT NULL DEFAULT 0,
        due_amount REAL NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        FOREIGN KEY(product_id) REFERENCES products(id)
      )""",
    );

    // default users
    await db.insert('users', {
      'username': 'admin',
      'password': '1234',
      'role': 'admin',
    });
    await db.insert('users', {
      'username': 'cashier',
      'password': '1234',
      'role': 'cashier',
    });
  }

  // ----------------- migrations helpers (same as before) -----------------
  Future<void> _ensureUnitsRemainderColumn(Database db) async {
    final cols = await db.rawQuery("PRAGMA table_info(products);");
    final has = cols.any((c) => c['name'] == 'units_remainder');
    if (!has) {
      await db.execute('ALTER TABLE products ADD COLUMN units_remainder INTEGER NOT NULL DEFAULT 0;');
      await db.update('products', {'units_remainder': 0});
    }
  }

  Future<void> ensureUnitsRemainderColumn() async {
    final db = await instance.database;
    await _ensureUnitsRemainderColumn(db);
  }

  Future<void> _ensureSaleColumns(Database db) async {
    final cols = await db.rawQuery("PRAGMA table_info(sales);");

    Future<void> addIfMissing(String name, String sql) async {
      final has = cols.any((c) => c['name'] == name);
      if (!has) {
        await db.execute(sql);
      }
    }

    await addIfMissing('paid_amount', 'ALTER TABLE sales ADD COLUMN paid_amount REAL NOT NULL DEFAULT 0;');
    await addIfMissing('change_amount', 'ALTER TABLE sales ADD COLUMN change_amount REAL NOT NULL DEFAULT 0;');
    await addIfMissing('is_credit', 'ALTER TABLE sales ADD COLUMN is_credit INTEGER NOT NULL DEFAULT 0;');
    await addIfMissing('is_return', 'ALTER TABLE sales ADD COLUMN is_return INTEGER NOT NULL DEFAULT 0;');
    await addIfMissing('return_of_sale_id', 'ALTER TABLE sales ADD COLUMN return_of_sale_id INTEGER;');
    await addIfMissing('return_note', "ALTER TABLE sales ADD COLUMN return_note TEXT;");
    // new: customer_name column
    await addIfMissing('customer_name', "ALTER TABLE sales ADD COLUMN customer_name TEXT;");
  }

  Future<void> ensureSaleColumns() async {
    final db = await instance.database;
    await _ensureSaleColumns(db);
  }

  Future<void> _ensureProductDatesColumns(Database db) async {
    final cols = await db.rawQuery("PRAGMA table_info(products);");

    if (!cols.any((c) => c['name'] == 'production_date')) {
      await db.execute('ALTER TABLE products ADD COLUMN production_date TEXT;');
    }

    if (!cols.any((c) => c['name'] == 'expiry_date')) {
      await db.execute('ALTER TABLE products ADD COLUMN expiry_date TEXT;');
    }
  }

  Future<void> ensureProductDatesColumns() async {
    final db = await instance.database;
    await _ensureProductDatesColumns(db);
  }

  Future<void> _ensureExpirySeenColumn(Database db) async {
    final cols = await db.rawQuery("PRAGMA table_info(products);");
    final hasColumn = cols.any((c) => c['name'] == 'expiry_seen');

    if (!hasColumn) {
      await db.execute('ALTER TABLE products ADD COLUMN expiry_seen INTEGER NOT NULL DEFAULT 0;');
      await db.update('products', {'expiry_seen': 0});
    }
  }

  Future<void> ensureExpirySeenColumn() async {
    final db = await instance.database;
    await _ensureExpirySeenColumn(db);
  }

  Future<void> _ensureLowStockSeenColumn(Database db) async {
    final cols = await db.rawQuery("PRAGMA table_info(products);");
    final hasColumn = cols.any((c) => c['name'] == 'low_stock_seen');

    if (!hasColumn) {
      await db.execute('ALTER TABLE products ADD COLUMN low_stock_seen INTEGER NOT NULL DEFAULT 0;');
      await db.update('products', {'low_stock_seen': 0});
    }
  }

  Future<void> ensureLowStockSeenColumn() async {
    final db = await instance.database;
    await _ensureLowStockSeenColumn(db);
  }

  // Ensure purchase_receipts table exists (for migrations)
  Future<void> _ensurePurchaseReceiptsTable(Database db) async {
    final tables = await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name='purchase_receipts';");
    final exists = tables.isNotEmpty;
    if (!exists) {
      await db.execute(
        """CREATE TABLE purchase_receipts (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          product_id INTEGER,
          product_name TEXT,
          barcode TEXT,
          received_by TEXT,
          cartons INTEGER NOT NULL DEFAULT 0,
          units INTEGER NOT NULL DEFAULT 0,
          units_in_carton INTEGER NOT NULL DEFAULT 1,
          purchase_price_per_carton REAL,
          purchase_price_per_unit REAL,
          payment_type TEXT NOT NULL DEFAULT 'cash',
          paid_amount REAL NOT NULL DEFAULT 0,
          due_amount REAL NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL,
          FOREIGN KEY(product_id) REFERENCES products(id)
        )""",
      );
    }
  }

  Future<void> ensurePurchaseReceiptsTable() async {
    final db = await instance.database;
    await _ensurePurchaseReceiptsTable(db);
  }

  // Ensure purchase_receipts columns (for older table versions)
  Future<void> _ensurePurchaseReceiptsColumns(Database db) async {
    final cols = await db.rawQuery("PRAGMA table_info(purchase_receipts);");
    if (cols.isEmpty) return; // table might not exist (handled elsewhere)

    Future<void> addIfMissing(String name, String sql) async {
      final has = cols.any((c) => c['name'] == name);
      if (!has) {
        await db.execute(sql);
      }
    }

    await addIfMissing('payment_type', "ALTER TABLE purchase_receipts ADD COLUMN payment_type TEXT NOT NULL DEFAULT 'cash';");
    await addIfMissing('paid_amount', "ALTER TABLE purchase_receipts ADD COLUMN paid_amount REAL NOT NULL DEFAULT 0;");
    await addIfMissing('due_amount', "ALTER TABLE purchase_receipts ADD COLUMN due_amount REAL NOT NULL DEFAULT 0;");
  }

  Future<void> ensurePurchaseReceiptsColumns() async {
    final db = await instance.database;
    await _ensurePurchaseReceiptsColumns(db);
  }

  // ----------------- auth / CRUD / helpers (mostly same as previous) -----------------
  Future<Map<String, dynamic>?> login(String username, String password) async {
    final db = await instance.database;
    final result = await db.query(
      'users',
      where: 'username = ? AND password = ?',
      whereArgs: [username, password],
    );
    if (result.isNotEmpty) return result.first;
    return null;
  }

  Future<int> changePassword(String username, String newPassword) async {
    final db = await instance.database;
    return await db.update(
      'users',
      {'password': newPassword},
      where: 'username = ?',
      whereArgs: [username],
    );
  }

  Future<int> insertProduct(Map<String, dynamic> product) async {
    final db = await instance.database;
    return await db.insert('products', {
      'barcode': product['barcode'] ?? '',
      'name': product['name'] ?? '',
      'purchase_price': (product['purchase_price'] ?? 0).toDouble(),
      'selling_price': (product['selling_price'] ?? 0).toDouble(),
      'units_in_carton': product['units_in_carton'] ?? 0,
      'quantity': product['quantity'] ?? 0,
      'units_remainder': product['units_remainder'] ?? 0,
      'production_date': product['production_date'] ?? '',
      'expiry_date': product['expiry_date'] ?? '',
      'low_stock_seen': product['low_stock_seen'] ?? 0,
      'expiry_seen': product['expiry_seen'] ?? 0,
    });
  }

  Future<List<Map<String, dynamic>>> getAllProducts() async {
    final db = await instance.database;
    final products = await db.query('products', orderBy: 'name');

    return products.map((product) {
      final cartons = (product['quantity'] as num).toInt();
      final unitsInCarton = (product['units_in_carton'] as num).toInt();
      final remainder = (product['units_remainder'] as num?)?.toInt() ?? 0;
      final totalUnits = cartons * unitsInCarton + remainder;
      return {
        ...product,
        'units_remainder': remainder,
        'total_units': totalUnits,
      };
    }).toList();
  }

  Future<int> updateProduct(Map<String, dynamic> product) async {
    final db = await instance.database;
    return await db.update(
      'products',
      {
        'barcode': product['barcode'],
        'name': product['name'],
        'purchase_price': product['purchase_price'],
        'selling_price': product['selling_price'],
        'units_in_carton': product['units_in_carton'],
        'quantity': product['quantity'],
        'units_remainder': product['units_remainder'] ?? 0,
        'production_date': product['production_date'],
        'expiry_date': product['expiry_date'],
      },
      where: 'id = ?',
      whereArgs: [product['id']],
    );
  }

  Future<int> deleteProduct(int id) async {
    final db = await instance.database;
    return await db.delete('products', where: 'id = ?', whereArgs: [id]);
  }

  Future<Map<String, dynamic>?> getProductByBarcode(String barcode) async {
    final db = await instance.database;
    final res = await db.query('products', where: 'barcode = ?', whereArgs: [barcode], limit: 1);
    if (res.isNotEmpty) {
      final product = Map<String, dynamic>.from(res.first);
      final cartons = (product['quantity'] as num).toInt();
      final unitsInCarton = (product['units_in_carton'] as num).toInt();
      final remainder = (product['units_remainder'] as num?)?.toInt() ?? 0;
      product['units_remainder'] = remainder;
      product['total_units'] = cartons * unitsInCarton + remainder;
      return product;
    }
    return null;
  }

  // ----------------- sales & sale_items -----------------
  Future<int> createSale({
    required double total,
    required String cashierUsername,
    double paidAmount = 0.0,
    double changeAmount = 0.0,
    bool isCredit = false,
    bool isReturn = false,
    int? returnOfSaleId,
    String? returnNote,
    String? customerName,
    String paymentMethod = 'cash',
    String discountType = 'fixed', // 'fixed' | 'percent'
    double discountValue = 0.0,
  }) async {
    final db = await instance.database;
    final now = DateTime.now().toIso8601String();

    // حساب قيمة الخصم وتطبيقها على المجموع الممرّر
    double discountAmount = 0.0;
    if (discountType == 'percent') {
      discountAmount = total * (discountValue / 100.0);
    } else {
      discountAmount = discountValue;
    }
    if (discountAmount < 0) discountAmount = 0.0;
    if (discountAmount > total) discountAmount = total;

    final finalTotal = (total - discountAmount);

    final id = await db.insert('sales', {
      'total': finalTotal,
      'date': now,
      'cashier_username': cashierUsername,
      'paid_amount': paidAmount,
      'change_amount': changeAmount,
      'is_credit': isCredit ? 1 : 0,
      'is_return': isReturn ? 1 : 0,
      'return_of_sale_id': returnOfSaleId,
      'return_note': returnNote ?? '',
      'customer_name': customerName ?? '',
      'payment_method': paymentMethod,
      'discount_type': discountType,
      'discount_value': discountValue,
    });
    return id;
  }



  Future<int> insertSaleItem({
    required int saleId,
    required int productId,
    required int quantity,
    required double price,
  }) async {
    final db = await instance.database;
    return await db.insert('sale_items', {
      'sale_id': saleId,
      'product_id': productId,
      'quantity': quantity,
      'price': price,
    });
  }

  Future<int> reduceProductStockByUnits(int productId, int unitsSold) async {
    if (unitsSold <= 0) return 0;
    final db = await instance.database;
    final res = await db.query('products', where: 'id = ?', whereArgs: [productId], limit: 1);
    if (res.isEmpty) return 0;
    final product = Map<String, dynamic>.from(res.first);

    final unitsInCarton = (product['units_in_carton'] as num).toInt();
    final currentCartons = (product['quantity'] as num).toInt();
    final currentRemainder = (product['units_remainder'] as num?)?.toInt() ?? 0;
    final currentTotalUnits = currentCartons * unitsInCarton + currentRemainder;

    final remainingUnits = (currentTotalUnits - unitsSold).clamp(0, currentTotalUnits);

    final newCartons = unitsInCarton > 0 ? (remainingUnits ~/ unitsInCarton) : 0;
    final newRemainder = unitsInCarton > 0 ? (remainingUnits % unitsInCarton) : remainingUnits;

    return await db.update(
      'products',
      {
        'quantity': newCartons,
        'units_remainder': newRemainder,
      },
      where: 'id = ?',
      whereArgs: [productId],
    );
  }

  Future<int> increaseProductStockByUnits(int productId, int unitsToAdd) async {
    if (unitsToAdd <= 0) return 0;
    final db = await instance.database;
    final res = await db.query('products', where: 'id = ?', whereArgs: [productId], limit: 1);
    if (res.isEmpty) return 0;
    final product = Map<String, dynamic>.from(res.first);

    final unitsInCarton = (product['units_in_carton'] as num).toInt();
    final currentCartons = (product['quantity'] as num).toInt();
    final currentRemainder = (product['units_remainder'] as num?)?.toInt() ?? 0;
    final currentTotalUnits = currentCartons * unitsInCarton + currentRemainder;

    final newTotalUnits = currentTotalUnits + unitsToAdd;

    final newCartons = unitsInCarton > 0 ? (newTotalUnits ~/ unitsInCarton) : 0;
    final newRemainder = unitsInCarton > 0 ? (newTotalUnits % unitsInCarton) : newTotalUnits;

    return await db.update(
      'products',
      {
        'quantity': newCartons,
        'units_remainder': newRemainder,
      },
      where: 'id = ?',
      whereArgs: [productId],
    );
  }

  double calculateTotalProfit({
    required double cartonPurchasePrice,
    required double unitSellingPrice,
    required int unitsInCarton,
    required int cartonsQuantity,
  }) {
    double totalSelling = unitSellingPrice * unitsInCarton * cartonsQuantity;
    double totalPurchase = cartonPurchasePrice * cartonsQuantity;
    return totalSelling - totalPurchase;
  }

  Future<int> getLowStockUnseenCount() async {
    final db = await instance.database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM products WHERE (quantity * units_in_carton + units_remainder) < ? AND COALESCE(low_stock_seen, 0) = 0',
      [5],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<List<Map<String, dynamic>>> getLowStockUnseenProducts() async {
    final db = await instance.database;
    final rows = await db.rawQuery(
      'SELECT *, COALESCE(low_stock_seen,0) as low_stock_seen, (quantity * units_in_carton + units_remainder) as total_units FROM products WHERE (quantity * units_in_carton + units_remainder) < ? AND COALESCE(low_stock_seen, 0) = 0 ORDER BY total_units ASC',
      [5],
    );
    return rows;
  }

  Future<int> setProductLowStockSeen(int productId, bool seen) async {
    final db = await instance.database;
    return await db.update(
      'products',
      {'low_stock_seen': seen ? 1 : 0},
      where: 'id = ?',
      whereArgs: [productId],
    );
  }

  Future<int> markAllLowStockSeen() async {
    final db = await instance.database;
    return await db.update(
      'products',
      {'low_stock_seen': 1},
      where: '(quantity * units_in_carton + units_remainder) < ?',
      whereArgs: [5],
    );
  }

  Future<int> getExpiringUnseenCount({required int daysThreshold}) async {
    final db = await instance.database;
    final now = DateTime.now();
    final thresholdDate = now.add(Duration(days: daysThreshold));
    final thresholdStr = thresholdDate.toIso8601String().split('T').first;

    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM products WHERE expiry_date IS NOT NULL AND expiry_date != ? AND date(expiry_date) <= ? AND COALESCE(expiry_seen, 0) = 0',
      ['', thresholdStr],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<List<Map<String, dynamic>>> getExpiringUnseenProducts({required int daysThreshold}) async {
    final db = await instance.database;
    final now = DateTime.now();
    final thresholdDate = now.add(Duration(days: daysThreshold));
    final thresholdStr = thresholdDate.toIso8601String().split('T').first;

    final rows = await db.rawQuery(
      'SELECT *, COALESCE(expiry_seen, 0) as expiry_seen FROM products WHERE expiry_date IS NOT NULL AND expiry_date != ? AND date(expiry_date) <= ? AND COALESCE(expiry_seen, 0) = 0 ORDER BY date(expiry_date) ASC',
      ['', thresholdStr],
    );
    return rows;
  }

  Future<int> setProductExpirySeen(int productId, bool seen) async {
    final db = await instance.database;
    return await db.update(
      'products',
      {'expiry_seen': seen ? 1 : 0},
      where: 'id = ?',
      whereArgs: [productId],
    );
  }

  Future<int> markAllExpirySeen({required int daysThreshold}) async {
    final db = await instance.database;
    final now = DateTime.now();
    final thresholdDate = now.add(Duration(days: daysThreshold));
    final thresholdStr = thresholdDate.toIso8601String().split('T').first;

    return await db.rawUpdate(
      'UPDATE products SET expiry_seen = 1 WHERE expiry_date IS NOT NULL AND expiry_date != ? AND date(expiry_date) <= ?',
      ['', thresholdStr],
    );
  }

  // ----------------- sales listing and sale_items -----------------
  Future<List<Map<String, dynamic>>> getAllSales() async {
    final db = await instance.database;
    final rows = await db.query('sales', orderBy: 'date DESC');
    return rows;
  }

  Future<List<Map<String, dynamic>>> getSaleItemsBySaleId(int saleId) async {
    final db = await instance.database;
    final rows = await db.rawQuery(
      '''
    SELECT si.*, p.name as product_name, p.barcode as product_barcode
    FROM sale_items si
    LEFT JOIN products p ON p.id = si.product_id
    WHERE si.sale_id = ?
    ''',
      [saleId],
    );
    return rows;
  }

  // get sale_returns rows for a sale
  Future<List<Map<String, dynamic>>> getSaleReturnsBySaleId(int saleId) async {
    final db = await instance.database;
    final rows = await db.query('sale_returns', where: 'sale_id = ?', whereArgs: [saleId], orderBy: 'date DESC');
    return rows;
  }

  // get sale_return_items for a sale (join with sale_returns)
  Future<List<Map<String, dynamic>>> getSaleReturnItemsForSale(int saleId) async {
    final db = await instance.database;
    final rows = await db.rawQuery(
      '''
      SELECT sri.*, sr.date as return_date, sr.paid_delta as paid_delta, sr.note as return_note,
             p.name as product_name, p.barcode as product_barcode
      FROM sale_return_items sri
      JOIN sale_returns sr ON sr.id = sri.return_id
      LEFT JOIN products p ON p.id = sri.product_id
      WHERE sr.sale_id = ?
      ''',
      [saleId],
    );
    return rows;
  }

  Future<double> getTotalForDate(String dateOnly) async {
    final db = await instance.database;
    final rows = await db.rawQuery(
      "SELECT SUM(total) as day_total FROM sales WHERE date LIKE ?",
      ['$dateOnly%'],
    );
    return (rows.isNotEmpty && rows.first['day_total'] != null)
        ? (rows.first['day_total'] as num).toDouble()
        : 0.0;
  }

  Future<int> markSaleAsReturn(int originalSaleId, {required int returnSaleId, String? note}) async {
    final db = await instance.database;
    return await db.update(
      'sales',
      {
        'is_return': 1,
        'return_of_sale_id': returnSaleId,
        'return_note': note ?? '',
      },
      where: 'id = ?',
      whereArgs: [originalSaleId],
    );
  }

  /// Apply return/exchange WITHOUT modifying the original sale rows.
  /// - We create a sale_returns row and sale_return_items (is_replacement = 0 for returned items,
  ///   is_replacement = 1 for replacements)
  /// - Adjust product stock accordingly (restore returned units, reduce replacement units)
  /// - We set a flag is_return = 1 and append return_note on the original sale (so UI knows there's a return),
  ///   but we DO NOT modify sale_items nor sales.total/paid_amount/change_amount.
  /// Apply return/exchange and MODIFY the original sale row and sale_items,
  /// while still logging the action in sale_returns / sale_return_items.
  Future<void> applyReturnExchangeToSale({
    required int saleId,
    required Map<int, int> returnsMap, // productId -> qtyReturned
    required Map<int, int> additionsMap, // productId -> qtyAdded (replacements)
    required double paidDelta,
    required String note,
  }) async {
    final db = await instance.database;

    await db.transaction((txn) async {
      // load sale
      final saleRows = await txn.query('sales', where: 'id = ?', whereArgs: [saleId], limit: 1);
      if (saleRows.isEmpty) throw 'Original sale not found';
      final sale = saleRows.first;
      final oldPaid = (sale['paid_amount'] as num?)?.toDouble() ?? 0.0;
      final oldNote = (sale['return_note'] ?? '').toString();

      // create a sale_returns row to log this action
      final now = DateTime.now().toIso8601String();
      final returnRowId = await txn.insert('sale_returns', {
        'sale_id': saleId,
        'date': now,
        'cashier_username': sale['cashier_username'] ?? '',
        'paid_delta': paidDelta,
        'note': note,
      });

      // 1) Process returns: decrement quantities in sale_items and restore stock
      for (final entry in returnsMap.entries) {
        final pid = entry.key;
        final qtyReturn = entry.value;
        if (qtyReturn <= 0) continue;

        // find the sale_item in the original sale (current state)
        final items = await txn.query(
          'sale_items',
          where: 'sale_id = ? AND product_id = ?',
          whereArgs: [saleId, pid],
          limit: 1,
        );

        if (items.isEmpty) {
          // If original sale didn't have that product, still log the return (fallback price)
          final prodRows = await txn.query('products', where: 'id = ?', whereArgs: [pid], limit: 1);
          if (prodRows.isEmpty) throw 'Product id $pid not found';
          final fallbackPrice = (prodRows.first['selling_price'] as num?)?.toDouble() ?? 0.0;

          await txn.insert('sale_return_items', {
            'return_id': returnRowId,
            'product_id': pid,
            'qty': qtyReturn,
            'is_replacement': 0,
            'price': fallbackPrice,
          });
        } else {
          final item = items.first;
          final itemId = (item['id'] as num).toInt();
          final origQty = (item['quantity'] as num?)?.toInt() ?? 0;
          final price = (item['price'] as num?)?.toDouble() ?? 0.0;

          final newQty = origQty - qtyReturn;
          if (newQty > 0) {
            await txn.update('sale_items', {'quantity': newQty}, where: 'id = ?', whereArgs: [itemId]);
          } else {
            await txn.delete('sale_items', where: 'id = ?', whereArgs: [itemId]);
          }

          // log returned item
          await txn.insert('sale_return_items', {
            'return_id': returnRowId,
            'product_id': pid,
            'qty': qtyReturn,
            'is_replacement': 0,
            'price': price,
          });
        }

        // restore product stock by units
        final prodRows = await txn.query('products', where: 'id = ?', whereArgs: [pid], limit: 1);
        if (prodRows.isEmpty) throw 'Product $pid not found in products table';
        final prod = Map<String, dynamic>.from(prodRows.first);
        final unitsInCarton = (prod['units_in_carton'] as num).toInt();
        final currentCartons = (prod['quantity'] as num).toInt();
        final currentRemainder = (prod['units_remainder'] as num?)?.toInt() ?? 0;
        final currentTotal = currentCartons * unitsInCarton + currentRemainder;
        final newTotal = currentTotal + qtyReturn;
        final newCartons = unitsInCarton > 0 ? (newTotal ~/ unitsInCarton) : 0;
        final newRemainder = unitsInCarton > 0 ? (newTotal % unitsInCarton) : newTotal;
        await txn.update('products', {
          'quantity': newCartons,
          'units_remainder': newRemainder,
        }, where: 'id = ?', whereArgs: [pid]);
      }

      // 2) Process additions (replacement items): add/increase sale_items and reduce stock
      for (final entry in additionsMap.entries) {
        final pid = entry.key;
        final qtyAdd = entry.value;
        if (qtyAdd <= 0) continue;

        // check product exists and availability
        final prodRows = await txn.query('products', where: 'id = ?', whereArgs: [pid], limit: 1);
        if (prodRows.isEmpty) throw 'Replacement product $pid not found';
        final prod = Map<String, dynamic>.from(prodRows.first);
        final unitsInCarton = (prod['units_in_carton'] as num).toInt();
        final currentCartons = (prod['quantity'] as num).toInt();
        final currentRemainder = (prod['units_remainder'] as num?)?.toInt() ?? 0;
        final currentTotal = currentCartons * unitsInCarton + currentRemainder;
        if (qtyAdd > currentTotal) throw 'Not enough stock for replacement product ${prod['name']}';

        final price = (prod['selling_price'] as num?)?.toDouble() ?? 0.0;

        // find existing sale_item for this product in the sale
        final items = await txn.query('sale_items', where: 'sale_id = ? AND product_id = ?', whereArgs: [saleId, pid], limit: 1);
        if (items.isEmpty) {
          // insert new sale_item row
          await txn.insert('sale_items', {
            'sale_id': saleId,
            'product_id': pid,
            'quantity': qtyAdd,
            'price': price,
          });
        } else {
          final item = items.first;
          final itemId = (item['id'] as num).toInt();
          final origQty = (item['quantity'] as num?)?.toInt() ?? 0;
          final newQty = origQty + qtyAdd;
          await txn.update('sale_items', {'quantity': newQty}, where: 'id = ?', whereArgs: [itemId]);
        }

        // log this replacement item (is_replacement = 1)
        await txn.insert('sale_return_items', {
          'return_id': returnRowId,
          'product_id': pid,
          'qty': qtyAdd,
          'is_replacement': 1,
          'price': price,
        });

        final newTotalAfter = currentTotal - qtyAdd;
        final newCartonsAfter = unitsInCarton > 0 ? (newTotalAfter ~/ unitsInCarton) : 0;
        final newRemainderAfter = unitsInCarton > 0 ? (newTotalAfter % unitsInCarton) : newTotalAfter;
        await txn.update('products', {
          'quantity': newCartonsAfter,
          'units_remainder': newRemainderAfter,
        }, where: 'id = ?', whereArgs: [pid]);
      }

      final sumRow = await txn.rawQuery('SELECT SUM(quantity * price) AS sum_total FROM sale_items WHERE sale_id = ?', [saleId]);
      final newTotal = (sumRow.isNotEmpty && sumRow.first['sum_total'] != null) ? (sumRow.first['sum_total'] as num).toDouble() : 0.0;

      double newPaid = oldPaid + paidDelta;
      if (newPaid < 0) newPaid = 0.0;

      double newChange = 0.0;
      int isCredit = 0;
      if (newPaid >= newTotal) {
        newChange = newPaid - newTotal;
        isCredit = 0;
      } else {
        newChange = 0.0;
        isCredit = 1;
      }

      final combinedNote = (oldNote.isEmpty ? '' : (oldNote + ' | ')) + note;

      await txn.update('sales', {
        'total': newTotal,
        'paid_amount': newPaid,
        'change_amount': newChange,
        'is_credit': isCredit,
        'is_return': 1,
        'return_note': combinedNote,
      }, where: 'id = ?', whereArgs: [saleId]);
    });
  }


  Future<List<Map<String, dynamic>>> getProductsByName(String query) async {
    final db = await instance.database;
    final q = query.trim();
    if (q.isEmpty) return [];

    final like = '%$q%';
    final rows = await db.query(
      'products',
      where: 'name LIKE ? COLLATE NOCASE OR barcode LIKE ?',
      whereArgs: [like, like],
      orderBy: 'name',
    );

    return rows.map((product) {
      final cartons = (product['quantity'] as num).toInt();
      final unitsInCarton = (product['units_in_carton'] as num).toInt();
      final remainder = (product['units_remainder'] as num?)?.toInt() ?? 0;
      final totalUnits = cartons * unitsInCarton + remainder;
      return {
        ...product,
        'units_remainder': remainder,
        'total_units': totalUnits,
      };
    }).toList();
  }

  Future<List<Map<String, dynamic>>> getTopSellingProducts({
    required String period, // 'day' | 'week' | 'month' | 'year'
    int limit = 10,
  }) async {
    final db = await instance.database;
    final now = DateTime.now();

    DateTime start;
    final end = DateTime(now.year, now.month, now.day); // date-only for today

    switch (period) {
      case 'day':
        start = end;
        break;
      case 'week':
        start = end.subtract(const Duration(days: 6)); // آخر 7 أيام (بما فيها اليوم)
        break;
      case 'month':
        start = DateTime(now.year, now.month, 1);
        break;
      case 'year':
        start = DateTime(now.year, 1, 1);
        break;
      default:
        start = end;
    }

    final startStr = start.toIso8601String().split('T').first;
    final endStr = end.toIso8601String().split('T').first;

    final rows = await db.rawQuery(
      '''
    SELECT p.id as product_id, p.name as product_name, p.barcode as product_barcode,
           SUM(si.quantity) as units_sold,
           SUM(si.quantity * si.price) as revenue
    FROM sale_items si
    JOIN sales s ON s.id = si.sale_id
    JOIN products p ON p.id = si.product_id
    WHERE date(s.date) BETWEEN ? AND ?
    GROUP BY p.id
    ORDER BY units_sold DESC
    LIMIT ?
    ''',
      [startStr, endStr, limit],
    );

    return rows.map((r) {
      return {
        'product_id': r['product_id'],
        'product_name': r['product_name'],
        'product_barcode': r['product_barcode'],
        'units_sold': (r['units_sold'] as num?)?.toInt() ?? 0,
        'revenue': (r['revenue'] as num?)?.toDouble() ?? 0.0,
      };
    }).toList();
  }

  Future<Map<String, dynamic>> receiveFromSupplier({
    String? barcode,
    String? name,
    required int cartons,
    required int units,
    double? purchasePricePerCarton,
    double? purchasePricePerUnit,
    double? sellingPricePerUnitIfNew,
    int unitsInCartonIfNew = 1,
    required String receivedBy,
    String paymentType = 'cash',
    double paidAmount = 0.0,
  }) async {
    final db = await instance.database;

    final b = (barcode ?? '').trim();
    final n = (name ?? '').trim();

    Map<String, dynamic>? found;
    if (b.isNotEmpty) {
      final res = await db.query('products', where: 'barcode = ?', whereArgs: [b], limit: 1);
      if (res.isNotEmpty) found = Map<String, dynamic>.from(res.first);
    }
    if (found == null && n.isNotEmpty) {
      final res = await db.query('products', where: 'name LIKE ? COLLATE NOCASE', whereArgs: [n], limit: 1);
      if (res.isNotEmpty) found = Map<String, dynamic>.from(res.first);
    }

    final now = DateTime.now().toIso8601String();

    if (found != null) {
      final pid = (found['id'] as num).toInt();
      final unitsInCarton = (found['units_in_carton'] as num).toInt();
      final totalUnitsToAdd = cartons * unitsInCarton + units;

      if (totalUnitsToAdd > 0) {
        await increaseProductStockByUnits(pid, totalUnitsToAdd);
      }


      double unitPrice = 0.0;
      if (purchasePricePerUnit != null) {
        unitPrice = purchasePricePerUnit;
      } else if (purchasePricePerCarton != null && unitsInCarton > 0) {
        unitPrice = purchasePricePerCarton / unitsInCarton;
      } else if ((found['purchase_price'] as num?) != null && (found['purchase_price'] as num) > 0 && unitsInCarton > 0) {
        // fallback to stored purchase price (assumed carton price)
        unitPrice = (found['purchase_price'] as num).toDouble() / (unitsInCarton > 0 ? unitsInCarton : 1);
      }

      double? newCartonPrice;
      if (purchasePricePerCarton != null) {
        newCartonPrice = purchasePricePerCarton;
      } else if (purchasePricePerUnit != null) {
        newCartonPrice = purchasePricePerUnit * (unitsInCarton > 0 ? unitsInCarton : 1);
      }

      if (newCartonPrice != null) {
        await db.update('products', {'purchase_price': newCartonPrice}, where: 'id = ?', whereArgs: [pid]);
      }

      final totalCost = unitPrice * totalUnitsToAdd;
      double due = totalCost - paidAmount;
      if (due < 0) due = 0.0;

      await db.insert('purchase_receipts', {
        'product_id': pid,
        'product_name': found['name'] ?? '',
        'barcode': found['barcode'] ?? '',
        'received_by': receivedBy,
        'cartons': cartons,
        'units': units,
        'units_in_carton': unitsInCarton,
        'purchase_price_per_carton': newCartonPrice,
        'purchase_price_per_unit': unitPrice > 0 ? unitPrice : null,
        'payment_type': paymentType,
        'paid_amount': paidAmount,
        'due_amount': due,
        'created_at': now,
      });

      return {
        'status': 'ok',
        'product_created': false,
        'product_id': pid,
        'added_units': totalUnitsToAdd,
        'total_cost': totalCost,
        'paid_amount': paidAmount,
        'due_amount': due,
      };
    } else {
      if (sellingPricePerUnitIfNew == null) {
        return {
          'status': 'need_selling_price',
          'message': 'Product not found. Please provide sellingPricePerUnitIfNew and unitsInCartonIfNew to create.',
          'suggested_name': n,
          'suggested_barcode': b,
        };
      }

      final cartonPrice = purchasePricePerCarton ??
          (purchasePricePerUnit != null ? purchasePricePerUnit * unitsInCartonIfNew : null) ??
          0.0;

      final initialCartons = cartons;
      final initialRemainder = units;
      final totalUnits = initialCartons * unitsInCartonIfNew + initialRemainder;

      final unitPrice = purchasePricePerUnit ?? (unitsInCartonIfNew > 0 ? (cartonPrice / unitsInCartonIfNew) : 0.0);
      final totalCost = unitPrice * totalUnits;
      double due = totalCost - paidAmount;
      if (due < 0) due = 0.0;

      final newId = await db.insert('products', {
        'barcode': b,
        'name': n,
        'purchase_price': cartonPrice,
        'selling_price': sellingPricePerUnitIfNew,
        'units_in_carton': unitsInCartonIfNew,
        'quantity': initialCartons,
        'units_remainder': initialRemainder,
        'production_date': '',
        'expiry_date': '',
        'low_stock_seen': 0,
        'expiry_seen': 0,
      });

      // log receipt
      await db.insert('purchase_receipts', {
        'product_id': newId,
        'product_name': n,
        'barcode': b,
        'received_by': receivedBy,
        'cartons': cartons,
        'units': units,
        'units_in_carton': unitsInCartonIfNew,
        'purchase_price_per_carton': cartonPrice,
        'purchase_price_per_unit': unitPrice > 0 ? unitPrice : null,
        'payment_type': paymentType,
        'paid_amount': paidAmount,
        'due_amount': due,
        'created_at': now,
      });

      return {
        'status': 'ok',
        'product_created': true,
        'product_id': newId,
        'added_units': totalUnits,
        'total_cost': totalCost,
        'paid_amount': paidAmount,
        'due_amount': due,
      };
    }
  }

  Future<List<Map<String, dynamic>>> getPaidPurchaseReceipts() async {
    final db = await instance.database;
    final rows = await db.query('purchase_receipts', where: 'due_amount = 0 OR (paid_amount IS NOT NULL AND paid_amount > 0 AND due_amount = 0)', orderBy: 'created_at DESC');
    return rows;
  }

  Future<List<Map<String, dynamic>>> getCreditPurchaseReceipts() async {
    final db = await instance.database;
    final rows = await db.query('purchase_receipts', where: 'due_amount > 0', orderBy: 'created_at DESC');
    return rows;
  }

  Future<int> addPaymentToPurchase(int receiptId, double amount) async {
    if (amount <= 0) return 0;
    final db = await instance.database;
    return await db.transaction((txn) async {
      final rows = await txn.query('purchase_receipts', where: 'id = ?', whereArgs: [receiptId], limit: 1);
      if (rows.isEmpty) throw 'Receipt not found';
      final r = Map<String, dynamic>.from(rows.first);
      final currentPaid = (r['paid_amount'] as num?)?.toDouble() ?? 0.0;
      final currentDue = (r['due_amount'] as num?)?.toDouble() ?? 0.0;
      final newPaid = currentPaid + amount;
      double newDue = currentDue - amount;
      if (newDue < 0) newDue = 0.0;
      final updated = await txn.update('purchase_receipts', {'paid_amount': newPaid, 'due_amount': newDue}, where: 'id = ?', whereArgs: [receiptId]);
      return updated;
    });
  }

// داخل DBHelper class

  Future<void> _ensureCashDrawerTable(Database db) async {
    final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='cash_drawer';"
    );
    final exists = tables.isNotEmpty;
    if (!exists) {
      await db.execute('''
      CREATE TABLE IF NOT EXISTS cash_drawer (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        amount REAL NOT NULL,
        updated_by TEXT,
        note TEXT,
        created_at TEXT NOT NULL
      )
    ''');
    }
  }


  Future<void> ensureCashDrawerTable() async {
    final db = await instance.database;
    await _ensureCashDrawerTable(db);
  }

  Future<double> getLatestDrawerStartingAmount() async {
    final db = await instance.database;
    final rows = await db.rawQuery('SELECT amount FROM cash_drawer ORDER BY id DESC LIMIT 1');
    if (rows.isEmpty) return 0.0;
    return (rows.first['amount'] as num?)?.toDouble() ?? 0.0;
  }

  Future<int> setDrawerStartingAmount(double amount, String updatedBy, {String note = ''}) async {
    final db = await instance.database;
    // تأكد أن الجدول موجود (مفيد لو نسيت استدعاءه في onOpen)
    await _ensureCashDrawerTable(db);
    final now = DateTime.now().toIso8601String();
    return await db.insert('cash_drawer', {
      'amount': amount,
      'updated_by': updatedBy,
      'note': note,
      'created_at': now,
    });
  }

  Future<Map<String, double>> getDrawerTotals({String? fromDate, String? toDate}) async {
    final db = await instance.database;

    String dateCondition = '';
    List<Object?> args = [];
    if (fromDate != null && toDate != null) {
      dateCondition = "AND date(date) BETWEEN ? AND ?";
      args = [fromDate, toDate];
    } else if (fromDate != null) {
      dateCondition = "AND date(date) >= ?";
      args = [fromDate];
    } else if (toDate != null) {
      dateCondition = "AND date(date) <= ?";
      args = [toDate];
    }
    final salesRow = await db.rawQuery(
      'SELECT SUM(COALESCE(paid_amount,0) - COALESCE(change_amount,0)) as sales_net_cash FROM sales WHERE payment_method = ? $dateCondition',
      ['cash', ...args],
    );
    final salesNetCash = (salesRow.isNotEmpty && salesRow.first['sales_net_cash'] != null)
        ? (salesRow.first['sales_net_cash'] as num).toDouble()
        : 0.0;

    final cardRow = await db.rawQuery(
      'SELECT SUM(COALESCE(paid_amount,0) - COALESCE(change_amount,0)) as sales_net_card FROM sales WHERE payment_method = ? $dateCondition',
      ['card', ...args],
    );
    final salesNetCard = (cardRow.isNotEmpty && cardRow.first['sales_net_card'] != null)
        ? (cardRow.first['sales_net_card'] as num).toDouble()
        : 0.0;

    String purchaseDateCond = '';
    List<Object?> purchaseArgs = [];
    if (fromDate != null && toDate != null) {
      purchaseDateCond = "AND date(created_at) BETWEEN ? AND ?";
      purchaseArgs = [fromDate, toDate];
    } else if (fromDate != null) {
      purchaseDateCond = "AND date(created_at) >= ?";
      purchaseArgs = [fromDate];
    } else if (toDate != null) {
      purchaseDateCond = "AND date(created_at) <= ?";
      purchaseArgs = [toDate];
    }
    final purchaseRow = await db.rawQuery(
      'SELECT SUM(COALESCE(paid_amount,0)) as purchase_paid_cash FROM purchase_receipts WHERE payment_type = ? $purchaseDateCond',
      ['cash', ...purchaseArgs],
    );
    final purchasePaidCash = (purchaseRow.isNotEmpty && purchaseRow.first['purchase_paid_cash'] != null)
        ? (purchaseRow.first['purchase_paid_cash'] as num).toDouble()
        : 0.0;

    String returnsDateCond = '';
    List<Object?> returnsArgs = [];
    if (fromDate != null && toDate != null) {
      returnsDateCond = "WHERE date(date) BETWEEN ? AND ?";
      returnsArgs = [fromDate, toDate];
    } else if (fromDate != null) {
      returnsDateCond = "WHERE date(date) >= ?";
      returnsArgs = [fromDate];
    } else if (toDate != null) {
      returnsDateCond = "WHERE date(date) <= ?";
      returnsArgs = [toDate];
    }

    final returnsRow = await db.rawQuery('SELECT SUM(COALESCE(paid_delta,0)) as returns_delta FROM sale_returns $returnsDateCond', returnsArgs);
    final returnsDelta = (returnsRow.isNotEmpty && returnsRow.first['returns_delta'] != null)
        ? (returnsRow.first['returns_delta'] as num).toDouble()
        : 0.0;

    return {
      'sales_net_cash': salesNetCash,
      'sales_net_card': salesNetCard,
      'purchase_paid_cash': purchasePaidCash,
      'returns_delta': returnsDelta,
    };
  }

  Future<double> computeCurrentDrawerAmount({String? fromDate, String? toDate}) async {
    final starting = await getLatestDrawerStartingAmount();
    final totals = await getDrawerTotals(fromDate: fromDate, toDate: toDate);

    final salesNetCash = totals['sales_net_cash'] ?? 0.0; // فقط النقد
    final purchasePaidCash = totals['purchase_paid_cash'] ?? 0.0;
    final returnsDelta = totals['returns_delta'] ?? 0.0;

    // formula: current = starting + sales_net_cash + returns_delta - purchase_paid_cash
    final current = starting + salesNetCash + returnsDelta - purchasePaidCash;
    return current;
  }

  Future<List<Map<String, dynamic>>> getCreditSales() async {
    final db = await instance.database;
    final rows = await db.query('sales', where: 'is_credit = ?', whereArgs: [1], orderBy: 'date DESC');
    return rows;
  }

  Future<List<Map<String, dynamic>>> searchCreditSalesByCustomer(String query) async {
    final db = await instance.database;
    final q = query.trim();
    if (q.isEmpty) return getCreditSales();
    final like = '%$q%';
    final rows = await db.query(
      'sales',
      where: "is_credit = 1 AND (customer_name LIKE ? COLLATE NOCASE)",
      whereArgs: [like],
      orderBy: 'date DESC',
    );
    return rows;
  }

  Future<int> markSaleAsPaid(int saleId, {String paymentMethod = 'cash', double? paidAmount}) async {
    final db = await instance.database;
    final rows = await db.query('sales', where: 'id = ?', whereArgs: [saleId], limit: 1);
    if (rows.isEmpty) throw 'Sale not found';
    final total = (rows.first['total'] as num?)?.toDouble() ?? 0.0;
    final paid = paidAmount ?? total;
    final change = (paid >= total) ? (paid - total) : 0.0;
    final updated = await db.update(
      'sales',
      {
        'is_credit': 0,
        'paid_amount': paid,
        'change_amount': change,
        'payment_method': paymentMethod,
      },
      where: 'id = ?',
      whereArgs: [saleId],
    );
    return updated;
  }

  Future<void> _ensureIsCurrentUserColumn(Database db) async {
    final cols = await db.rawQuery("PRAGMA table_info(users);");
    final has = cols.any((c) => c['name'] == 'is_current');
    if (!has) {
      await db.execute('ALTER TABLE users ADD COLUMN is_current INTEGER NOT NULL DEFAULT 0;');
      await db.update('users', {'is_current': 0});
    }
  }

  Future<void> ensureIsCurrentUserColumn() async {
    final db = await instance.database;
    await _ensureIsCurrentUserColumn(db);
  }

  Future<void> setCurrentUserByUsername(String username) async {
    final db = await instance.database;
    await db.transaction((txn) async {
      await txn.update('users', {'is_current': 0});
      await txn.update('users', {'is_current': 1}, where: 'username = ?', whereArgs: [username]);
    });
  }

  Future<Map<String, dynamic>?> getCurrentUser() async {
    final db = await instance.database;
    final rows = await db.query('users', where: 'is_current = ?', whereArgs: [1], limit: 1);
    if (rows.isNotEmpty) return rows.first;
    return null;
  }

  Future<int> clearCurrentUser() async {
    final db = await instance.database;
    return await db.update('users', {'is_current': 0});
  }

  Future<int> renameUserAndPropagate(int userId, String newUsername) async {
    final db = await instance.database;

    final rows = await db.query('users', where: 'id = ?', whereArgs: [userId], limit: 1);
    if (rows.isEmpty) throw 'User not found';
    final oldUsername = (rows.first['username'] ?? '').toString();

    if (oldUsername == newUsername) return 0;

    return await db.transaction<int>((txn) async {
      final updatedUser = await txn.update('users', {'username': newUsername}, where: 'id = ?', whereArgs: [userId]);
      await txn.update('sales', {'cashier_username': newUsername}, where: 'cashier_username = ?', whereArgs: [oldUsername]);
      await txn.update('sale_returns', {'cashier_username': newUsername}, where: 'cashier_username = ?', whereArgs: [oldUsername]);
      await txn.update('purchase_receipts', {'received_by': newUsername}, where: 'received_by = ?', whereArgs: [oldUsername]);
      await txn.update('cash_drawer', {'updated_by': newUsername}, where: 'updated_by = ?', whereArgs: [oldUsername]);

      return updatedUser;
    });
  }

  Future<void> _ensureSalePaymentMethodColumn(Database db) async {
    final cols = await db.rawQuery("PRAGMA table_info(sales);");
    final has = cols.any((c) => c['name'] == 'payment_method');
    if (!has) {
      await db.execute("ALTER TABLE sales ADD COLUMN payment_method TEXT NOT NULL DEFAULT 'cash';");
      await db.update('sales', {'payment_method': 'cash'});
    }
  }

  Future<void> ensureSalePaymentMethodColumn() async {
    final db = await instance.database;
    await _ensureSalePaymentMethodColumn(db);
  }

  Future<void> _ensureSaleCardTransferredColumn(Database db) async {
    final cols = await db.rawQuery("PRAGMA table_info(sales);");
    final has = cols.any((c) => c['name'] == 'card_transferred');
    if (!has) {
      await db.execute('ALTER TABLE sales ADD COLUMN card_transferred INTEGER NOT NULL DEFAULT 0;');
      await db.update('sales', {'card_transferred': 0});
    }
  }

  Future<void> ensureSaleCardTransferredColumn() async {
    final db = await instance.database;
    await _ensureSaleCardTransferredColumn(db);
  }

  Future<double> getUntransferredCardAmount({String? fromDate, String? toDate}) async {
    final db = await instance.database;

    String dateCondition = '';
    List<Object?> args = [];
    if (fromDate != null && toDate != null) {
      dateCondition = "AND date(date) BETWEEN ? AND ?";
      args = [fromDate, toDate];
    } else if (fromDate != null) {
      dateCondition = "AND date(date) >= ?";
      args = [fromDate];
    } else if (toDate != null) {
      dateCondition = "AND date(date) <= ?";
      args = [toDate];
    }

    final row = await db.rawQuery(
      'SELECT SUM(COALESCE(paid_amount,0) - COALESCE(change_amount,0)) as card_untransferred FROM sales WHERE payment_method = ? AND COALESCE(card_transferred,0) = 0 $dateCondition',
      ['card', ...args],
    );

    return (row.isNotEmpty && row.first['card_untransferred'] != null)
        ? (row.first['card_untransferred'] as num).toDouble()
        : 0.0;
  }

  Future<List<Map<String, dynamic>>> getProductsByBarcodeList(String barcode) async {
    final db = await instance.database;
    final b = barcode.trim();
    if (b.isEmpty) return [];

    final rows = await db.query(
      'products',
      where: 'barcode = ?',
      whereArgs: [b],
      orderBy: 'name',
    );

    return rows.map((product) {
      final cartons = (product['quantity'] as num).toInt();
      final unitsInCarton = (product['units_in_carton'] as num).toInt();
      final remainder = (product['units_remainder'] as num?)?.toInt() ?? 0;
      final totalUnits = cartons * unitsInCarton + remainder;
      return {
        ...product,
        'units_remainder': remainder,
        'total_units': totalUnits,
      };
    }).toList();
  }

  Future<String?> getLastDrawerEntryByUser(String username) async {
    final db = await instance.database;
    final rows = await db.rawQuery(
      'SELECT created_at FROM cash_drawer WHERE updated_by = ? ORDER BY id DESC LIMIT 1',
      [username],
    );
    if (rows.isNotEmpty) return (rows.first['created_at'] as String?);
    return null;
  }

  Future<List<Map<String, dynamic>>> getSalesByCashierBetweenDates({
    required String cashierUsername,
    required String fromDate,
    required String toDate,
  }) async {
    final db = await instance.database;
    final rows = await db.rawQuery(
      'SELECT * FROM sales WHERE cashier_username = ? AND date(date) BETWEEN ? AND ? ORDER BY date ASC',
      [cashierUsername, fromDate, toDate],
    );
    return rows;
  }

  Future<List<Map<String, dynamic>>> getPurchaseReceiptsByUserBetweenDates({
    required String username,
    required String fromDate,
    required String toDate,
  }) async {
    final db = await instance.database;
    final rows = await db.rawQuery(
      'SELECT * FROM purchase_receipts WHERE received_by = ? AND date(created_at) BETWEEN ? AND ? ORDER BY created_at ASC',
      [username, fromDate, toDate],
    );
    return rows;
  }


  Future<double> getCardAmountByCashierBetweenDates({
    required String cashierUsername,
    required String fromDate,
    required String toDate,
  }) async {
    final db = await instance.database;
    final rows = await db.rawQuery(
      '''
    SELECT SUM(COALESCE(paid_amount,0) - COALESCE(change_amount,0)) as sum_card
    FROM sales
    WHERE payment_method = 'card'
      AND cashier_username = ?
      AND date(date) BETWEEN ? AND ?
    ''',
      [cashierUsername, fromDate, toDate],
    );
    return (rows.isNotEmpty && rows.first['sum_card'] != null) ? (rows.first['sum_card'] as num).toDouble() : 0.0;
  }

  Future<double> getCreditOutstandingByCashierBetweenDates({
    required String cashierUsername,
    required String fromDate,
    required String toDate,
  }) async {
    final db = await instance.database;
    final rows = await db.rawQuery(
      '''
    SELECT SUM(COALESCE(total,0) - COALESCE(paid_amount,0)) as credit_out
    FROM sales
    WHERE is_credit = 1
      AND cashier_username = ?
      AND date(date) BETWEEN ? AND ?
    ''',
      [cashierUsername, fromDate, toDate],
    );
    final val = (rows.isNotEmpty && rows.first['credit_out'] != null) ? (rows.first['credit_out'] as num).toDouble() : 0.0;
    return val < 0 ? 0.0 : val;
  }

  Future<double> getPurchaseReceiptsOutstandingByUserBetweenDates({
    required String username,
    required String fromDate,
    required String toDate,
  }) async {
    final db = await instance.database;
    final rows = await db.rawQuery(
      '''
    SELECT SUM(COALESCE(due_amount,0)) as total_due
    FROM purchase_receipts
    WHERE received_by = ?
      AND date(created_at) BETWEEN ? AND ?
    ''',
      [username, fromDate, toDate],
    );
    return (rows.isNotEmpty && rows.first['total_due'] != null) ? (rows.first['total_due'] as num).toDouble() : 0.0;
  }

  Future<double> getNetCardSales({String? fromDate, String? toDate, String? cashierUsername}) async {
    final db = await instance.database;

    String dateCondition = '';
    final args = <Object?>['wallet'];

    if (fromDate != null && toDate != null) {
      dateCondition = ' AND date(date) BETWEEN ? AND ?';
      args.addAll([fromDate, toDate]);
    } else if (fromDate != null) {
      dateCondition = ' AND date(date) >= ?';
      args.add(fromDate);
    } else if (toDate != null) {
      dateCondition = ' AND date(date) <= ?';
      args.add(toDate);
    }

    if (cashierUsername != null && cashierUsername.trim().isNotEmpty) {
      dateCondition += ' AND cashier_username = ?';
      args.add(cashierUsername.trim());
    }

    final rows = await db.rawQuery(
      '''
    SELECT SUM(COALESCE(paid_amount,0) - COALESCE(change_amount,0)) as card_net
    FROM sales
    WHERE payment_method = ?
    $dateCondition
    ''',
      args,
    );

    final val = (rows.isNotEmpty && rows.first['card_net'] != null)
        ? (rows.first['card_net'] as num).toDouble()
        : 0.0;
    return val < 0 ? 0.0 : val;
  }
  Future<void> _ensureCardWalletTable(Database db) async {
    final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='card_wallet';"
    );
    final exists = tables.isNotEmpty;
    if (!exists) {
      await db.execute('''
      CREATE TABLE IF NOT EXISTS card_wallet (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        amount REAL NOT NULL,
        updated_by TEXT,
        note TEXT,
        created_at TEXT NOT NULL
      )
    ''');
    }
  }

  Future<void> ensureCardWalletTable() async {
    final db = await instance.database;
    await _ensureCardWalletTable(db);
  }

  Future<double> getLatestCardWalletAmount() async {
    final db = await instance.database;
    final rows = await db.rawQuery('SELECT SUM(COALESCE(amount,0)) as sum_amount FROM card_wallet');
    if (rows.isEmpty) return 0.0;
    final val = rows.first['sum_amount'];
    return (val != null) ? (val as num).toDouble() : 0.0;
  }

  Future<int> setCardWalletAmount(double amount, String updatedBy, {String note = ''}) async {
    final db = await instance.database;
    await _ensureCardWalletTable(db);
    final now = DateTime.now().toIso8601String();
    return await db.insert('card_wallet', {
      'amount': amount,
      'updated_by': updatedBy,
      'note': note,
      'created_at': now,
    });
  }


  Future<int> changeCardWalletBy(double delta, String updatedBy, {String note = ''}) async {
    // ledger behavior: just insert the delta
    if (delta == 0) return 0;
    return await setCardWalletAmount(delta, updatedBy, note: note);
  }
  Future<void> transferUntransferredSalesAndWithdraw(double amount, String username, {String? note}) async {
    final db = await instance.database;
    await db.transaction((txn) async {
      final rowsAvail = await txn.rawQuery(
          '''SELECT SUM(COALESCE(paid_amount,0) - COALESCE(change_amount,0)) as untransferred
           FROM sales WHERE payment_method = 'card' AND COALESCE(card_transferred,0) = 0'''
      );
      final available = (rowsAvail.isNotEmpty && rowsAvail.first['untransferred'] != null)
          ? (rowsAvail.first['untransferred'] as num).toDouble()
          : 0.0;

      if (available + 0.000001 < amount) {
        throw 'لا يوجد ما يكفي من مبالغ الكارت غير المحولة (المتوفر: ${available.toStringAsFixed(2)})';
      }

      double remaining = amount;

      final rows = await txn.rawQuery(
          '''SELECT id, (COALESCE(paid_amount,0) - COALESCE(change_amount,0)) AS net FROM sales
           WHERE payment_method = 'card' AND COALESCE(card_transferred,0) = 0
           ORDER BY date ASC'''
      );

      final List<int> toMark = [];

      for (final r in rows) {
        final int id = (r['id'] as num).toInt();
        final double net = (r['net'] as num).toDouble();
        if (net <= 0) continue;
        if (net <= remaining + 0.000001) {
          toMark.add(id);
          remaining -= net;
          if (remaining <= 0) break;
        } else {
          throw 'قاعدة البيانات لا تسمح بتحويل جزء من فاتورة واحدة. الرجاء تحويل مبلغ أكبر أو ترقية السكيمة.';
        }
      }

      if (remaining > 0.000001) {
        throw 'فشل تغطية المبلغ من مبالغ الكارت الغير محوّلة';
      }

      for (final id in toMark) {
        await txn.rawUpdate('UPDATE sales SET card_transferred = 1 WHERE id = ?', [id]);
      }

      final now = DateTime.now().toIso8601String();

      await txn.insert('card_wallet', {
        'amount': amount,
        'updated_by': username,
        'note': note ?? 'تحويل من مبالغ الكارت غير المحولة',
        'created_at': now,
      });

      await txn.insert('card_wallet', {
        'amount': -amount,
        'updated_by': username,
        'note': 'سحب بواسطة الكاشير (من مبالغ الكارت المحوّلة)',
        'created_at': now,
      });

    });
  }

  Future<double> getLatestDrawerStartingAmountByUser(String username) async {
    final db = await instance.database;
    final rows = await db.rawQuery(
      'SELECT amount FROM cash_drawer WHERE updated_by = ? ORDER BY id DESC LIMIT 1',
      [username],
    );
    if (rows.isNotEmpty && rows.first['amount'] != null) {
      return (rows.first['amount'] as num).toDouble();
    }
    return 0.0;
  }

  Future<double> getSalesNetCashByCashierBetweenDates({
    required String cashierUsername,
    required String fromDate,
    required String toDate,
  }) async {
    final db = await instance.database;
    final rows = await db.rawQuery(
      '''
    SELECT SUM(COALESCE(paid_amount,0) - COALESCE(change_amount,0)) as sales_net_cash
    FROM sales
    WHERE payment_method = 'cash'
      AND cashier_username = ?
      AND date(date) BETWEEN ? AND ?
    ''',
      [cashierUsername, fromDate, toDate],
    );
    return (rows.isNotEmpty && rows.first['sales_net_cash'] != null)
        ? (rows.first['sales_net_cash'] as num).toDouble()
        : 0.0;
  }

  Future<double> getReturnsDeltaByCashierBetweenDates({
    required String cashierUsername,
    required String fromDate,
    required String toDate,
  }) async {
    final db = await instance.database;
    final rows = await db.rawQuery(
      '''
    SELECT SUM(COALESCE(paid_delta,0)) as returns_delta
    FROM sale_returns
    WHERE cashier_username = ?
      AND date(date) BETWEEN ? AND ?
    ''',
      [cashierUsername, fromDate, toDate],
    );
    return (rows.isNotEmpty && rows.first['returns_delta'] != null)
        ? (rows.first['returns_delta'] as num).toDouble()
        : 0.0;
  }

  Future<double> getPurchasePaidCashByUserBetweenDates({
    required String username,
    required String fromDate,
    required String toDate,
  }) async {
    final db = await instance.database;
    final rows = await db.rawQuery(
      '''
    SELECT SUM(COALESCE(paid_amount,0)) as purchase_paid
    FROM purchase_receipts
    WHERE received_by = ?
      AND date(created_at) BETWEEN ? AND ?
    ''',
      [username, fromDate, toDate],
    );
    return (rows.isNotEmpty && rows.first['purchase_paid'] != null)
        ? (rows.first['purchase_paid'] as num).toDouble()
        : 0.0;
  }

// 1) داخل كلاس DBHelper: دالة الترحيل الخاصة بخصم الفاتورة
  Future<void> _ensureSaleDiscountColumns(Database db) async {
    final cols = await db.rawQuery("PRAGMA table_info(sales);");

    Future<void> addIfMissing(String name, String sql) async {
      final has = cols.any((c) => c['name'] == name);
      if (!has) {
        await db.execute(sql);
      }
    }

    await addIfMissing(
      'discount_type',
      "ALTER TABLE sales ADD COLUMN discount_type TEXT NOT NULL DEFAULT 'fixed';",
    );
    await addIfMissing(
      'discount_value',
      "ALTER TABLE sales ADD COLUMN discount_value REAL NOT NULL DEFAULT 0;",
    );
  }

// 2) غلاف عام للنداء من خارج الكلاس (مثلاً: من _saveSale أو init)
  Future<void> ensureSaleDiscountColumns() async {
    final db = await instance.database;
    await _ensureSaleDiscountColumns(db);
  }




  Future<Map<String, double>> computeSaleTotalWithDiscountFromItems(int saleId, {String? discountType, double? discountValue}) async {
    final db = await instance.database;
    final rows = await db.rawQuery('SELECT SUM(quantity * price) as subtotal FROM sale_items WHERE sale_id = ?', [saleId]);
    final subtotal = (rows.isNotEmpty && rows.first['subtotal'] != null) ? (rows.first['subtotal'] as num).toDouble() : 0.0;

    // إذا لم يُمرّر نوع/قيمة خصم، حاول قراءته من جدول sales
    String dType = discountType ?? 'fixed';
    double dValue = discountValue ?? 0.0;
    if (discountType == null || discountValue == null) {
      final sRows = await db.query('sales', where: 'id = ?', whereArgs: [saleId], limit: 1);
      if (sRows.isNotEmpty) {
        dType = (sRows.first['discount_type'] ?? 'fixed').toString();
        dValue = (sRows.first['discount_value'] as num?)?.toDouble() ?? 0.0;
      }
    }

    double discountAmount = 0.0;
    if (dType == 'percent') {
      discountAmount = subtotal * (dValue / 100.0);
    } else {
      discountAmount = dValue;
    }
    if (discountAmount < 0) discountAmount = 0.0;
    if (discountAmount > subtotal) discountAmount = subtotal;

    final finalTotal = subtotal - discountAmount;
    return {
      'subtotal': subtotal,
      'discount': discountAmount,
      'total': finalTotal,
    };
  }
  Future<int> applyDiscountToSale({
    required int saleId,
    required String discountType, // 'fixed' | 'percent'
    required double discountValue,
  }) async {
    final db = await instance.database;
    return await db.transaction((txn) async {
      final saleRows = await txn.query('sales', where: 'id = ?', whereArgs: [saleId], limit: 1);
      if (saleRows.isEmpty) throw 'Sale not found';
      final sale = saleRows.first;
      final oldPaid = (sale['paid_amount'] as num?)?.toDouble() ?? 0.0;
      final oldNote = (sale['return_note'] ?? '').toString();

      // حساب subtotal من sale_items
      final sumRow = await txn.rawQuery('SELECT SUM(quantity * price) AS subtotal FROM sale_items WHERE sale_id = ?', [saleId]);
      final subtotal = (sumRow.isNotEmpty && sumRow.first['subtotal'] != null) ? (sumRow.first['subtotal'] as num).toDouble() : 0.0;

      // حساب قيمة الخصم
      double discountAmount = 0.0;
      if (discountType == 'percent') {
        discountAmount = subtotal * (discountValue / 100.0);
      } else {
        discountAmount = discountValue;
      }
      if (discountAmount < 0) discountAmount = 0.0;
      if (discountAmount > subtotal) discountAmount = subtotal;

      final newTotal = subtotal - discountAmount;

      double newPaid = oldPaid;
      if (newPaid < 0) newPaid = 0.0;

      double newChange = 0.0;
      int isCredit = 0;
      if (newPaid >= newTotal) {
        newChange = newPaid - newTotal;
        isCredit = 0;
      } else {
        newChange = 0.0;
        isCredit = 1;
      }

      final updated = await txn.update('sales', {
        'total': newTotal,
        'discount_type': discountType,
        'discount_value': discountValue,
        'paid_amount': newPaid,
        'change_amount': newChange,
        'is_credit': isCredit,
      }, where: 'id = ?', whereArgs: [saleId]);

      return updated;
    });
  }




}