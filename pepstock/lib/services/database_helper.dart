import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../models/product.dart';
import '../models/order_record.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;
  static bool _ffiInitialized = false;

  DatabaseHelper._init();

  /// Initialise la factory SQLite FFI sur Desktop (Windows, macOS, Linux)
  static void ensureInitialized() {
    if (_ffiInitialized) return;
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    _ffiInitialized = true;
  }

  Future<Database> get database async {
    if (_database != null) return _database!;
    ensureInitialized();
    _database = await _initDB('product_inventory_2.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    ensureInitialized();
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    // 1. Table Produits
    await db.execute('''
      CREATE TABLE products (
        id INTEGER,
        code TEXT PRIMARY KEY,
        label TEXT NOT NULL,
        category TEXT NOT NULL,
        base_price REAL NOT NULL,
        stock REAL NOT NULL DEFAULT 0,
        description TEXT NOT NULL,
        options_json TEXT NOT NULL
      )
    ''');

    // 2. Table Commandes locales synchronisées
    await db.execute('''
      CREATE TABLE orders (
        id TEXT PRIMARY KEY,
        product_code TEXT NOT NULL,
        product_label TEXT NOT NULL,
        category TEXT NOT NULL,
        base_price REAL NOT NULL,
        items_json TEXT,
        selected_options_json TEXT NOT NULL,
        total_price REAL NOT NULL,
        total_quantity INTEGER DEFAULT 1,
        customer_ref TEXT,
        notes TEXT,
        created_at TEXT NOT NULL,
        sync_status TEXT NOT NULL,
        sync_timestamp TEXT,
        api_response TEXT
      )
    ''');

    await _seedFromLocalAsset(db);
  }

  Future<void> _seedFromLocalAsset(Database db) async {
    try {
      final jsonString = await rootBundle.loadString('assets/products.json');
      final List<dynamic> jsonData = jsonDecode(jsonString);

      final batch = db.batch();
      for (final item in jsonData) {
        final product = Product.fromJson(item as Map<String, dynamic>);
        batch.insert(
          'products',
          product.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
      print('SQLite initialisé : ${jsonData.length} produits importés du fichier local.');
    } catch (e) {
      print('Erreur lors du chargement du fichier local SQLite : $e');
    }
  }

  Future<List<Product>> restoreFromLocalAsset() async {
    final db = await database;
    await db.delete('products');
    await _seedFromLocalAsset(db);
    return await searchProducts('');
  }


  Future<List<Product>> searchProducts(String query) async {
    final db = await database;
    final cleanQuery = query.trim().toUpperCase();

    if (cleanQuery.isEmpty) {
      final res = await db.query('products', limit: 20);
      return res.map((e) => Product.fromJson(e)).toList();
    }

    // Filtrage SQL insensible à la casse avec priorité sur le code
    final results = await db.rawQuery('''
      SELECT * FROM products
      WHERE UPPER(code) LIKE ? OR UPPER(label) LIKE ?
      ORDER BY 
        CASE 
          WHEN UPPER(code) = ? THEN 1
          WHEN UPPER(code) LIKE ? THEN 2
          ELSE 3
        END,
        code ASC
      LIMIT 10
    ''', ['%$cleanQuery%', '%$cleanQuery%', cleanQuery, '$cleanQuery%']);

    return results.map((e) => Product.fromJson(e)).toList();
  }

  Future<Product?> getProductByCode(String code) async {
    final db = await database;
    final results = await db.query(
      'products',
      where: 'UPPER(code) = ?',
      whereArgs: [code.trim().toUpperCase()],
      limit: 1,
    );

    if (results.isNotEmpty) {
      return Product.fromJson(results.first);
    }
    return null;
  }

  Future<void> insertOrder(OrderRecord order) async {
    final db = await database;
    await db.insert(
      'orders',
      order.toSqliteMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateSyncStatus({
    required String orderId,
    required String status,
    required DateTime syncTimestamp,
    String? apiResponse,
  }) async {
    final db = await database;
    await db.update(
      'orders',
      {
        'sync_status': status,
        'sync_timestamp': syncTimestamp.toIso8601String(),
        'api_response': apiResponse,
      },
      where: 'id = ?',
      whereArgs: [orderId],
    );
  }

  Future<List<OrderRecord>> getOrders() async {
    final db = await database;
    final results = await db.query('orders', orderBy: 'created_at DESC');
    return results.map((m) => OrderRecord.fromSqliteMap(m)).toList();
  }
}
