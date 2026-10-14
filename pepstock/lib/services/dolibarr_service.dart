import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/product.dart';
import 'database_helper.dart';
import 'package:sqflite/sqflite.dart';

class DolibarrService {
  final String baseUrl;
  final String apiKey;

  // Singleton correctement initialisé avec votre clé fixe
  static final DolibarrService instance = DolibarrService._internal(
    baseUrl: 'https://www.dolibarr.pepiniere-brehat.com',
    apiKey: 'c1X69fT08f7MQxJfN3iN8AYxW1wTn9cr', // Clé API générée depuis la fiche utilisateur Dolibarr
  );

  DolibarrService._internal({
    required this.baseUrl,
    required this.apiKey,
  });

  /// Récupération des produits avec la base URL et la clé API configurées
  Future<List<Product>> fetchAndSyncProductsToSqlite() async {
    final cleanUrl = baseUrl.replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$cleanUrl/api/index.php/products?sortfield=t.ref&sortorder=ASC&limit=10000');

    try {
      final response = await http.get(
        uri,
        headers: {
          'DOLAPIKEY': apiKey,
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 12));

      if (response.statusCode == 200) {
        final List<dynamic> jsonList = jsonDecode(response.body);
        final List<Product> products = [];

        final db = await DatabaseHelper.instance.database;
        await db.delete('products');
        final batch = db.batch();

        for (final item in jsonList) {
          // Normalisation du code produit Dolibarr (6 lettres majuscules)
          String ref = (item['ref'] as String? ?? '').replaceAll(RegExp(r'[^a-zA-Z]'), '').toUpperCase();
          if (ref.length < 6) {
            ref = (ref + 'PRODXX').substring(0, 6);
          } else if (ref.length > 6) {
            ref = ref.substring(0, 6);
          }

          final product = Product(
            id: int.tryParse(item['id'].toString()) ?? 0,
            code: ref,
            label: item['label'] as String? ?? 'Produit Pépinière',
            category: item['category'] as String? ?? 'ERP',
            basePrice: double.tryParse(item['price']?.toString() ?? '0') ?? 99.0,
            stock: double.tryParse(item['stock'].toString()) ?? 0,
            description: item['description'] as String? ?? 'Produit synchronisé depuis l\'ERP',
            options: [],
          );

          products.add(product);
          batch.insert('products', product.toMap(), conflictAlgorithm: ConflictAlgorithm.replace,);
        }

        await batch.commit(noResult: true);
        return products;
      } else {
        throw Exception('Erreur API ERP HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      throw Exception('Impossible de contacter l\'ERP : $e');
    }
  }
}