import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/product.dart';
import 'database_helper.dart';

class DolibarrService {
  final String baseUrl; // Ex : "https://votre-erp.dolibarr.pro"
  final String apiKey;  // DOLAPIKEY utilisateur Dolibarr

  DolibarrService({
    required this.baseUrl,
    required this.apiKey,
  });

  static get instance => null;

  Future<List<Product>> fetchAndSyncProductsToSqlite() async {
    final cleanUrl = baseUrl.replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$cleanUrl/api/index.php/products?sortfield=t.ref&sortorder=ASC&limit=100');

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
            code: ref,
            label: item['label'] as String? ?? 'Produit Pépinière',
            category: item['category'] as String? ?? 'ERP',
            basePrice: double.tryParse(item['price']?.toString() ?? '0') ?? 99.0,
            description: item['description'] as String? ?? 'Produit synchronisé depuis l\'ERP',
            options: [
              //ProductOption(id: 'opt_garantie_$ref', label: 'Garantie atelier 24 mois', price: 25.0, defaultChecked: false, desc: 'Support pièces et main-d\'œuvre'),
              //ProductOption(id: 'opt_express_$ref', label: 'Livraison express prioritaire 24h', price: 12.0, defaultChecked: true, desc: 'Colisage sécurisé entrepôt'),
            ],
          );

          products.add(product);
          batch.insert('products', product.toMap());
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
