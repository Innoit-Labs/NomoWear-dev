class ProductVariant {
  final String id;
  final String productId;
  final String variantName;
  final String actualPrice;
  final String? costPrice;
  final String? primaryImageUrl;
  final int stockOnHand;
  final String stockStatus;
  final Map<String, String> options;

  const ProductVariant({
    required this.id,
    required this.productId,
    required this.variantName,
    required this.actualPrice,
    this.costPrice,
    this.primaryImageUrl,
    this.stockOnHand = 0,
    this.stockStatus = 'IN_STOCK',
    this.options = const {},
  });

  factory ProductVariant.fromJson(Map<String, dynamic> json) {
    final options = <String, String>{};

    void addOption(dynamic k, dynamic v) {
      final keyStr = k?.toString().trim();
      final valStr = v?.toString().trim();
      if (keyStr != null && keyStr.isNotEmpty && valStr != null && valStr.isNotEmpty) {
        options[keyStr] = valStr;
      }
    }

    final optionsRaw = json['options'] ??
        json['variant_options'] ??
        json['variantOptions'] ??
        json['attributes'];
    if (optionsRaw is Map) {
      optionsRaw.forEach((key, value) => addOption(key, value));
    } else if (optionsRaw is List) {
      for (final item in optionsRaw) {
        if (item is Map) {
          final k = item['name'] ??
              item['key'] ??
              item['title'] ??
              item['option_name'] ??
              item['optionName'];
          final v = item['value'] ??
              item['val'] ??
              item['option_value'] ??
              item['optionValue'];
          if (k != null && v != null) {
            addOption(k, v);
          }
        }
      }
    }

    // Direct fields on variant json
    if (json['size'] != null) addOption('Size', json['size']);
    if (json['color'] != null) addOption('Color', json['color']);
    if (json['colour'] != null) addOption('Color', json['colour']);
    if (json['age'] != null) addOption('Age', json['age']);

    final variantName = json['variant_name']?.toString() ??
        json['variantName']?.toString() ??
        '';

    // Parse size & color from variantName if options are missing them
    if (variantName.isNotEmpty) {
      final parts = variantName.split(RegExp(r'[/,|]')).map((s) => s.trim()).toList();
      for (final part in parts) {
        if (part.isEmpty) continue;
        if (part.contains(':')) {
          final kv = part.split(':');
          if (kv.length >= 2) {
            final key = kv[0].trim();
            final val = kv.sublist(1).join(':').trim();
            final hasKey = options.keys.any((k) => k.toLowerCase() == key.toLowerCase());
            if (!hasKey && key.isNotEmpty && val.isNotEmpty) {
              addOption(key, val);
            }
          }
        } else {
          final upper = part.toUpperCase();
          const sizeKeywords = {'XS', 'S', 'M', 'L', 'XL', 'XXL', 'XXXL', 'FREE SIZE', 'FS'};
          final isAge = RegExp(r'^\d+\s*-\s*\d+\s*(M|Y|Months?|Years?)?$', caseSensitive: false).hasMatch(part);
          if (sizeKeywords.contains(upper) || isAge) {
            if (!options.keys.any((k) => k.toLowerCase() == 'size')) {
              addOption('Size', part);
            }
          } else if (!part.contains(RegExp(r'\d')) && part.length < 25) {
            if (!options.keys.any((k) => k.toLowerCase() == 'color' || k.toLowerCase() == 'colour')) {
              addOption('Color', part);
            }
          }
        }
      }
    }

    return ProductVariant(
      id: json['id']?.toString() ?? '',
      productId: json['product_id']?.toString() ??
          json['productId']?.toString() ??
          '',
      variantName: variantName,
      actualPrice: json['actual_price']?.toString() ??
          json['actualPrice']?.toString() ??
          '0',
      costPrice: json['cost_price']?.toString() ??
          json['costPrice']?.toString(),
      primaryImageUrl: _nonEmpty(
        json['primary_image_url'] ?? json['primaryImageUrl'],
      ),
      stockOnHand: _parseInt(json['stock_on_hand'] ?? json['stockOnHand']) ?? 0,
      stockStatus: json['stock_status']?.toString() ??
          json['stockStatus']?.toString() ??
          'IN_STOCK',
      options: options,
    );
  }
}

String? _nonEmpty(dynamic value) {
  final s = value?.toString().trim();
  return (s == null || s.isEmpty) ? null : s;
}

int? _parseInt(dynamic value) {
  if (value is int) return value;
  if (value is String) return int.tryParse(value);
  return null;
}
