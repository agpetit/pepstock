import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/order_record.dart';
import 'dolibarr_service.dart'; // Import indispensable pour récupérer la session

class SyncResult {
  final bool success;
  final String message;
  final String? syncId;
  final int statusCode;
  final Map<String, dynamic>? data;

  SyncResult({
    required this.success,
    required this.message,
    this.syncId,
    required this.statusCode,
    this.data,
  });
}

class ApiService {
  static int defaultWarehouseId = 18;

  static Future<SyncResult> syncStockMovements(OrderRecord order) async {
    // 1. Récupération dynamique de la configuration depuis DolibarrService
    final baseUrl = DolibarrService.instance.baseUrl;
    final apiKey = DolibarrService.instance.apiKey;

    if (apiKey == null) {
      return SyncResult(
        success: false,
        message: 'Erreur : Aucune session active (clé API manquante). Veuillez vous reconnecter.',
        statusCode: 401,
      );
    }

    // 2. Construction de l'URL pour les mouvements de stock
    final cleanUrl = baseUrl.replaceAll(RegExp(r'/+$'), '');
    final endpoint = Uri.parse('$cleanUrl/api/index.php/stockmovements');

    bool allSuccess = true;
    List<String> errorMessages = [];
    int successCount = 0;

    for (var item in order.items) {
      int stockQty = -(item.quantity);

      String movementLabel = item.movementLabel;
      if (order.notes.trim().isNotEmpty) {
        movementLabel += ' - ${order.notes.trim()}';
      }

      print(order.id);

      final payload = jsonEncode({
        'product_id': item.productId,
        'warehouse_id': defaultWarehouseId,
        'qty': stockQty,
        'label': movementLabel, // UTILISATION DU NOUVEAU CHAMP
        'movementcode': order.id,
      });

      try {
        final response = await http.post(
          endpoint,
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'DOLAPIKEY': apiKey, // Utilisation de la clé dynamique mise en cache
          },
          body: payload,
        ).timeout(const Duration(seconds: 10));

        if (response.statusCode == 200 || response.statusCode == 201) {
          successCount++;
        } else {
          allSuccess = false;
          final errorData = jsonDecode(response.body);
          final msg = errorData['error']?['message'] ?? 'Erreur HTTP ${response.statusCode}';
          errorMessages.add('${item.productCode} : $msg');
        }
      } catch (e) {
        allSuccess = false;
        errorMessages.add('${item.productCode} : Erreur réseau ($e)');
      }
    }

    if (allSuccess) {
      return SyncResult(
        success: true,
        message: '$successCount mouvement(s) de stock synchronisé(s) avec succès.',
        statusCode: 200,
      );
    } else {
      return SyncResult(
        success: false,
        message: 'Échecs partiels ou totaux :\n${errorMessages.join("\n")}',
        statusCode: 500,
      );
    }
  }
  static Future<bool> checkHealth() async {
    final baseUrl = DolibarrService.instance.baseUrl;
    final cleanUrl = baseUrl.replaceAll(RegExp(r'/+$'), '');

    try {
      final response = await http.get(Uri.parse('$cleanUrl/api/index.php/status')).timeout(const Duration(seconds: 4));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}