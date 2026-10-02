import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/order_record.dart';

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
  static String baseUrl = 'https://ais-dev-htkxdseq5au5n5b7y6tb7b-214327717164.europe-west2.run.app';

  static Future<SyncResult> syncOrder(OrderRecord order) async {
    final endpoint = Uri.parse('$baseUrl/api/sync');

    try {
      final payload = jsonEncode(order.toRestPayload());
      
      final response = await http.post(
        endpoint,
        headers: {
          'Content-Type': 'application/json; charset=UTF-8',
          'Accept': 'application/json',
          'X-Client-Platform': 'Flutter-Mobile',
        },
        body: payload,
      ).timeout(const Duration(seconds: 10));

      final responseBody = jsonDecode(response.body);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return SyncResult(
          success: true,
          message: responseBody['message'] ?? 'Synchronisation réussie.',
          syncId: responseBody['syncId'],
          statusCode: response.statusCode,
          data: responseBody,
        );
      } else {
        return SyncResult(
          success: false,
          message: responseBody['message'] ?? 'Erreur serveur ${response.statusCode}',
          statusCode: response.statusCode,
          data: responseBody,
        );
      }
    } catch (e) {
      return SyncResult(
        success: false,
        message: 'Erreur réseau lors de la synchronisation : $e',
        statusCode: 0,
      );
    }
  }

  static Future<bool> checkHealth() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/health')).timeout(const Duration(seconds: 4));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
