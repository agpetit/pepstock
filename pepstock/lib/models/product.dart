import 'dart:convert';

class ProductOption {
  final String id;
  final String label;
  final double price;
  final bool defaultChecked;
  final String desc;
  bool isSelected;

  ProductOption({
    required this.id,
    required this.label,
    required this.price,
    required this.defaultChecked,
    required this.desc,
    this.isSelected = false,
  });

  factory ProductOption.fromJson(Map<String, dynamic> json) {
    final defaultVal = json['defaultChecked'] as bool? ?? false;
    return ProductOption(
      id: json['id'] as String,
      label: json['label'] as String,
      price: (json['price'] as num).toDouble(),
      defaultChecked: defaultVal,
      desc: json['desc'] as String? ?? '',
      isSelected: defaultVal,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'label': label,
      'price': price,
      'defaultChecked': defaultChecked,
      'desc': desc,
      'isSelected': isSelected,
    };
  }

  ProductOption copyWith({bool? isSelected}) {
    return ProductOption(
      id: id,
      label: label,
      price: price,
      defaultChecked: defaultChecked,
      desc: desc,
      isSelected: isSelected ?? this.isSelected,
    );
  }
}

class Product {
  final String code;
  final String label;
  final String category;
  final double basePrice;
  final double stock;
  final String description;
  final List<ProductOption> options;

  Product({
    required this.code,
    required this.label,
    required this.category,
    required this.basePrice,
    this.stock = 0.0,
    required this.description,
    required this.options,
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    List<ProductOption> optionsList = [];
    if (json['options_json'] != null) {
      final List<dynamic> decoded = jsonDecode(json['options_json'] as String);
      optionsList = decoded.map((o) => ProductOption.fromJson(o)).toList();
    } else if (json['options'] != null) {
      final List<dynamic> raw = json['options'] as List<dynamic>;
      optionsList = raw.map((o) => ProductOption.fromJson(o)).toList();
    }

    return Product(
      code: (json['code'] as String).toUpperCase(),
      label: json['label'] as String,
      category: json['category'] as String? ?? 'Général',
      basePrice: (json['base_price'] ?? json['basePrice'] as num).toDouble(),
      stock: (json['stock_reel'] ?? json['stock'] as num?)?.toDouble() ?? 0.0,
      description: json['description'] as String? ?? '',
      options: optionsList,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'code': code.toUpperCase(),
      'label': label,
      'category': category,
      'base_price': basePrice,
      'stock': stock,
      'description': description,
      'options_json': jsonEncode(options.map((o) => o.toJson()).toList()),
    };
  }

  @override
  String toString() => '$code - $label (Stock: $stock)';
}
