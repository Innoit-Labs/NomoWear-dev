import 'package:nomowear/features/products/data/models/product_variant.dart';

class ProductKitItem {
  final String id;
  final int quantity;

  const ProductKitItem({required this.id, required this.quantity});

  factory ProductKitItem.fromJson(Map<String, dynamic> json) {
    return ProductKitItem(
      id: json['id']?.toString() ??
          json['product_id']?.toString() ??
          json['productId']?.toString() ??
          '',
      quantity: _parseInt(json['quantity']) ?? 1,
    );
  }
}

class Product {
  final String id;
  final String productName;
  final String productSlug;
  final String productClass;
  final String? itemType;
  final bool hasVariants;
  final String actualPrice;
  final String? costPrice;
  final String? description;
  final String? primaryImageUrl;
  final List<String> imageUrls;
  final String? categoryName;
  final String stockStatus;
  final Map<String, String> attributes;
  final List<ProductKitItem> kitItems;
  final List<Product> items;
  final List<ProductVariant> variants;

  const Product({
    required this.id,
    required this.productName,
    required this.productSlug,
    required this.productClass,
    this.itemType,
    required this.hasVariants,
    required this.actualPrice,
    this.costPrice,
    this.description,
    this.primaryImageUrl,
    this.imageUrls = const [],
    this.categoryName,
    this.stockStatus = 'IN_STOCK',
    this.attributes = const {},
    this.kitItems = const [],
    this.items = const [],
    this.variants = const [],
  });

  String? get displayImageUrl {
    if (primaryImageUrl != null && primaryImageUrl!.trim().isNotEmpty) {
      return primaryImageUrl;
    }
    if (imageUrls.isNotEmpty) return imageUrls.first;
    return null;
  }

  String? get displayDescription {
    final value = description?.trim();
    if (value == null || value.isEmpty) return null;
    return value;
  }

  bool get isWardrobeKit => productClass == 'wardrobe_kit';

  bool get isSingleItem => productClass == 'single_item';

  factory Product.fromJson(Map<String, dynamic> json) {
    final kitRaw = json['kit_items'] ?? json['kitItems'];
    final kitItems = <ProductKitItem>[];
    if (kitRaw is List) {
      for (final item in kitRaw) {
        if (item is Map) {
          kitItems.add(ProductKitItem.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }

    final imageUrlsRaw = json['image_urls'] ?? json['imageUrls'];
    final imageUrls = <String>[];
    if (imageUrlsRaw is List) {
      for (final url in imageUrlsRaw) {
        final value = _nonEmpty(url);
        if (value != null) imageUrls.add(value);
      }
    }

    final itemsRaw = json['items'];
    final items = <Product>[];
    if (itemsRaw is List) {
      for (final item in itemsRaw) {
        if (item is Map) {
          items.add(Product.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }

    final variantsRaw = json['variants'];
    final variants = <ProductVariant>[];
    if (variantsRaw is List) {
      for (final variant in variantsRaw) {
        if (variant is Map) {
          variants.add(ProductVariant.fromJson(Map<String, dynamic>.from(variant)));
        }
      }
    }

    final attributesRaw = json['attributes'];
    final attributes = <String, String>{};
    if (attributesRaw is Map) {
      attributesRaw.forEach((key, value) {
        final k = key.toString().trim();
        final v = value?.toString().trim() ?? '';
        if (k.isNotEmpty && v.isNotEmpty) {
          attributes[k] = v;
        }
      });
    }

    return Product(
      id: json['id']?.toString() ?? '',
      productName: json['product_name']?.toString() ??
          json['productName']?.toString() ??
          '',
      productSlug: json['product_slug']?.toString() ??
          json['productSlug']?.toString() ??
          '',
      productClass: json['product_class']?.toString() ??
          json['productClass']?.toString() ??
          '',
      itemType: _nonEmpty(json['item_type'] ?? json['itemType']),
      hasVariants: _parseBool(json['has_variants'] ?? json['hasVariants']),
      actualPrice: json['actual_price']?.toString() ??
          json['actualPrice']?.toString() ??
          '0',
      costPrice: json['cost_price']?.toString() ??
          json['costPrice']?.toString(),
      description: _nonEmpty(json['description']),
      primaryImageUrl: _nonEmpty(
        json['primary_image_url'] ?? json['primaryImageUrl'],
      ),
      imageUrls: imageUrls,
      categoryName: _nonEmpty(json['category_name'] ?? json['categoryName']),
      stockStatus: json['stock_status']?.toString() ??
          json['stockStatus']?.toString() ??
          'IN_STOCK',
      attributes: attributes,
      kitItems: kitItems,
      items: items,
      variants: variants,
    );
  }
}

bool _parseBool(dynamic value) {
  if (value is bool) return value;
  if (value is int) return value != 0;
  if (value is String) return value == '1' || value.toLowerCase() == 'true';
  return false;
}

int? _parseInt(dynamic value) {
  if (value is int) return value;
  if (value is String) return int.tryParse(value);
  return null;
}

String? _nonEmpty(dynamic value) {
  final s = value?.toString().trim();
  return (s == null || s.isEmpty) ? null : s;
}
