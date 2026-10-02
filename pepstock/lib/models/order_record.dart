import 'dart:convert';
import 'product.dart';

class OrderItem {
  final String id;
  final String productCode;
  final String productLabel;
  final String category;
  final double basePrice;
  final int quantity; // De -20 à +20
  final List<ProductOption> selectedOptions;
  final double unitPrice;
  final double lineTotal;

  OrderItem({
    required this.id,
    required this.productCode,
    required this.productLabel,
    required this.category,
    required this.basePrice,
    required this.quantity,
    required this.selectedOptions,
    required this.unitPrice,
    required this.lineTotal,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'productCode': productCode,
      'productLabel': productLabel,
      'category': category,
      'basePrice': basePrice,
      'quantity': quantity,
      'selectedOptions': selectedOptions.map((o) => o.toJson()).toList(),
      'unitPrice': unitPrice,
      'lineTotal': lineTotal,
    };
  }

  factory OrderItem.fromJson(Map<String, dynamic> json) {
    List<ProductOption> options = [];
    if (json['selectedOptions'] != null) {
      final List<dynamic> list = json['selectedOptions'] as List<dynamic>;
      options = list.map((o) => ProductOption.fromJson(o as Map<String, dynamic>)).toList();
    }

    return OrderItem(
      id: json['id'] as String? ?? 'ITEM-${DateTime.now().millisecondsSinceEpoch}',
      productCode: (json['productCode'] ?? json['product_code'] ?? '') as String,
      productLabel: (json['productLabel'] ?? json['product_label'] ?? '') as String,
      category: json['category'] as String? ?? 'Général',
      basePrice: (json['basePrice'] ?? json['base_price'] as num?)?.toDouble() ?? 0.0,
      quantity: (json['quantity'] as num?)?.toInt() ?? 1,
      selectedOptions: options,
      unitPrice: (json['unitPrice'] ?? json['unit_price'] as num?)?.toDouble() ?? 0.0,
      lineTotal: (json['lineTotal'] ?? json['line_total'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class OrderRecord {
  final String id;
  final List<OrderItem> items; // Lignes cumulées de la commande
  final double totalPrice;
  final int totalQuantity;
  final String customerRef;
  final String notes;
  final DateTime createdAt;
  String syncStatus; // 'synced', 'pending', 'failed'
  DateTime? syncTimestamp;
  String? apiResponse;

  OrderRecord({
    required this.id,
    required this.items,
    required this.totalPrice,
    required this.totalQuantity,
    this.customerRef = '',
    this.notes = '',
    required this.createdAt,
    this.syncStatus = 'pending',
    this.syncTimestamp,
    this.apiResponse,
  });

  String get productCode => items.map((i) => i.productCode).join(', ');
  String get productLabel => items.isNotEmpty ? '${items.length} article(s) (${items.map((i) => i.productCode).join(', ')})' : '';
  List<ProductOption> get selectedOptions => items.expand((i) => i.selectedOptions).toList();

  Map<String, dynamic> toSqliteMap() {
    return {
      'id': id,
      'product_code': productCode,
      'product_label': productLabel,
      'category': items.isNotEmpty ? items.first.category : 'Général',
      'base_price': items.isNotEmpty ? items.first.basePrice : 0.0,
      'items_json': jsonEncode(items.map((i) => i.toJson()).toList()),
      'selected_options_json': jsonEncode(selectedOptions.map((o) => o.toJson()).toList()),
      'total_price': totalPrice,
      'total_quantity': totalQuantity,
      'customer_ref': customerRef,
      'notes': notes,
      'created_at': createdAt.toIso8601String(),
      'sync_status': syncStatus,
      'sync_timestamp': syncTimestamp?.toIso8601String(),
      'api_response': apiResponse,
    };
  }

  Map<String, dynamic> toRestPayload() {
    return {
      'id': id,
      'items': items.map((i) => i.toJson()).toList(),
      'totalPrice': totalPrice,
      'totalQuantity': totalQuantity,
      'customerRef': customerRef,
      'notes': notes,
      'clientTimestamp': createdAt.toIso8601String(),
      'deviceInfo': 'Flutter 3.x / Dart 3.x Mobile Client',
    };
  }

  factory OrderRecord.fromSqliteMap(Map<String, dynamic> map) {
    List<OrderItem> itemList = [];
    if (map['items_json'] != null) {
      try {
        final List<dynamic> decoded = jsonDecode(map['items_json'] as String);
        itemList = decoded.map((i) => OrderItem.fromJson(i as Map<String, dynamic>)).toList();
      } catch (_) {}
    }

    if (itemList.isEmpty) {
      // Fallback si ancien format plat
      List<ProductOption> options = [];
      if (map['selected_options_json'] != null) {
        final List<dynamic> decoded = jsonDecode(map['selected_options_json'] as String);
        options = decoded.map((o) => ProductOption.fromJson(o)).toList();
      }
      itemList = [
        OrderItem(
          id: 'LEGACY-${map['id']}',
          productCode: map['product_code'] as String? ?? '',
          productLabel: map['product_label'] as String? ?? '',
          category: map['category'] as String? ?? '',
          basePrice: (map['base_price'] as num?)?.toDouble() ?? 0.0,
          quantity: (map['total_quantity'] as num?)?.toInt() ?? 1,
          selectedOptions: options,
          unitPrice: (map['total_price'] as num?)?.toDouble() ?? 0.0,
          lineTotal: (map['total_price'] as num?)?.toDouble() ?? 0.0,
        )
      ];
    }

    return OrderRecord(
      id: map['id'] as String,
      items: itemList,
      totalPrice: (map['total_price'] as num).toDouble(),
      totalQuantity: (map['total_quantity'] as num?)?.toInt() ?? itemList.fold(0, (acc, item) => acc + item.quantity),
      customerRef: map['customer_ref'] as String? ?? '',
      notes: map['notes'] as String? ?? '',
      createdAt: DateTime.parse(map['created_at'] as String),
      syncStatus: map['sync_status'] as String,
      syncTimestamp: map['sync_timestamp'] != null ? DateTime.parse(map['sync_timestamp'] as String) : null,
      apiResponse: map['api_response'] as String?,
    );
  }
}
