// lib/services/db/db_helper.dart
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DBHelper {
  static final DBHelper instance = DBHelper._init();
  static Database? _database;

  DBHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('pos_system.db_v2.35'); // keep your version
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

    // sales
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
        return_note TEXT
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
  }) async {
    final db = await instance.database;
    final now = DateTime.now().toIso8601String();
    final id = await db.insert('sales', {
      'total': total,
      'date': now,
      'cashier_username': cashierUsername,
      'paid_amount': paidAmount,
      'change_amount': changeAmount,
      'is_credit': isCredit ? 1 : 0,
      'is_return': isReturn ? 1 : 0,
      'return_of_sale_id': returnOfSaleId,
      'return_note': returnNote ?? '',
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

        // reduce product stock by qtyAdd
        final newTotalAfter = currentTotal - qtyAdd;
        final newCartonsAfter = unitsInCarton > 0 ? (newTotalAfter ~/ unitsInCarton) : 0;
        final newRemainderAfter = unitsInCarton > 0 ? (newTotalAfter % unitsInCarton) : newTotalAfter;
        await txn.update('products', {
          'quantity': newCartonsAfter,
          'units_remainder': newRemainderAfter,
        }, where: 'id = ?', whereArgs: [pid]);
      }

      // 3) Recompute sale total from sale_items (current state)
      final sumRow = await txn.rawQuery('SELECT SUM(quantity * price) AS sum_total FROM sale_items WHERE sale_id = ?', [saleId]);
      final newTotal = (sumRow.isNotEmpty && sumRow.first['sum_total'] != null) ? (sumRow.first['sum_total'] as num).toDouble() : 0.0;

      // 4) Adjust paid_amount by paidDelta (positive -> increase paid, negative -> cashier refunded)
      double newPaid = oldPaid + paidDelta;
      if (newPaid < 0) newPaid = 0.0;

      // 5) compute change and is_credit
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

      // 6) update sales row (mark as return and update totals/payments)
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

}
