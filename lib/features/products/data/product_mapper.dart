import 'package:nomowear/core/utils/kids_size_utils.dart';
import 'package:nomowear/features/products/data/models/product.dart';
import 'package:nomowear/features/products/data/product_catalog.dart';
import 'package:nomowear/features/products/data/models/product_variant.dart';
import 'package:nomowear/features/wardrobe/presentation/screens/wardrobe_screen.dart';

class ProductMapper {
  ProductMapper._();

  static WardrobeItem toWardrobeItem(
    Product product, {
    String? category,
  }) {
    final listingCategory = category ?? product.categoryName;
    final images = _productImages(product);
    final imageUrl = images.isNotEmpty ? images.first : '';
    final variantInfo = _extractVariantInfo(product, images);
    final isKids = ProductCatalog.isKidsProduct(product) ||
        (listingCategory?.toLowerCase().contains('kids') ?? false);

    final prices = resolveProductPrice(product);
    return WardrobeItem(
      productId: product.id,
      title: product.productName,
      description: _descriptionFor(product),
      imageUrl: imageUrl,
      // Selling / discounted price from backend `actual_price`.
      price: prices.discountedPrice,
      // Keep raw backend amounts so resolvePrice can re-evaluate per variant.
      costPrice: product.costPrice,
      actualPrice: product.actualPrice,
      colorVariantImages: variantInfo.colorImages,
      colorNames: variantInfo.colorNames,
      sizes: variantInfo.sizes,
      ages: isKids ? variantInfo.sizes : const [],
      genderTag: _genderTagFor(product),
      productDetails: _productDetailsFor(product),
      category: listingCategory,
      imageUrls: images,
      variants: product.variants,
      stockStatus: product.stockStatus,
      itemType: product.itemType,
    );
  }

  static List<String> _productImages(Product product) {
    if (product.imageUrls.isNotEmpty) return product.imageUrls;
    if (product.primaryImageUrl != null) {
      return [product.primaryImageUrl!];
    }
    return const [];
  }

  static String _descriptionFor(Product product) {
    return product.displayDescription ?? '';
  }

  static String formatPrice(String actualPrice) => _formatPrice(actualPrice);

  /// Parses backend / display price strings (e.g. `"349.00"`, `"₹ 349"`).
  static double? parseAmount(String? raw) {
    if (raw == null) return null;
    final cleaned = raw.replaceAll(RegExp(r'[^\d.]'), '').trim();
    if (cleaned.isEmpty) return null;
    return double.tryParse(cleaned);
  }

  static String _formatPrice(String raw) {
    final parsed = parseAmount(raw);
    if (parsed == null) return '₹ 0';
    if (parsed == parsed.roundToDouble()) {
      return '₹ ${parsed.round()}';
    }
    return '₹ ${parsed.toStringAsFixed(2)}';
  }

  /// Backend price semantics for product / variant payloads:
  /// - [actualPrice] (`actual_price`) = final / discounted selling price
  /// - [costPrice] (`cost_price`) = original / compare-at price when higher
  ///
  /// [ResolvedPrice.discountedPrice] is always the customer-facing selling price.
  /// [ResolvedPrice.actualPrice] is the original price (for strikethrough) when
  /// a discount applies; otherwise it matches the selling price.
  static ResolvedPrice resolveRawPrices({
    required String? actualPrice,
    String? costPrice,
  }) {
    final selling = parseAmount(actualPrice);
    final original = parseAmount(costPrice);

    if (selling != null && selling > 0) {
      final showOriginal =
          original != null && original > 0 && original > selling;
      return ResolvedPrice(
        discountedPrice: _formatPrice(selling.toString()),
        actualPrice: showOriginal
            ? _formatPrice(original.toString())
            : _formatPrice(selling.toString()),
      );
    }

    // No valid discounted/selling `actual_price` → fall back to cost_price.
    if (original != null && original > 0) {
      final formatted = _formatPrice(original.toString());
      return ResolvedPrice(
        discountedPrice: formatted,
        actualPrice: formatted,
      );
    }

    return const ResolvedPrice(
      discountedPrice: '₹ 0',
      actualPrice: '₹ 0',
    );
  }

  static ResolvedPrice resolveProductPrice(Product product) =>
      resolveRawPrices(
        actualPrice: product.actualPrice,
        costPrice: product.costPrice,
      );

  static ResolvedPrice resolveVariantPrice(ProductVariant variant) =>
      resolveRawPrices(
        actualPrice: variant.actualPrice,
        costPrice: variant.costPrice,
      );

  static List<String> _productDetailsFor(Product product) {
    final details = <String>[];
    if (product.stockStatus.isNotEmpty) {
      details.add('Stock: ${product.stockStatus.replaceAll('_', ' ')}');
    }
    if (product.categoryName != null) {
      details.add('Category: ${product.categoryName}');
    }
    if (product.attributes.isNotEmpty) {
      product.attributes.forEach((key, value) {
        details.add('$key: $value');
      });
    }
    return details;
  }

  /// Resolves `'men' | 'women' | 'boy' | 'girl'` from attributes or product name.
  static String? _genderTagFor(Product product) {
    for (final entry in product.attributes.entries) {
      if (entry.key.toLowerCase() != 'gender' &&
          entry.key.toLowerCase() != 'sex') {
        continue;
      }
      final tag = _normalizeGenderLabel(entry.value);
      if (tag != null) return tag;
    }

    return _normalizeGenderLabel(product.productName);
  }

  static String? _normalizeGenderLabel(String raw) {
    final value = raw.trim().toLowerCase();
    if (value.isEmpty) return null;

    if (RegExp(r'\bboy(s)?\b').hasMatch(value) || value == 'b') {
      return 'boy';
    }
    if (RegExp(r'\bgirl(s)?\b').hasMatch(value) || value == 'g') {
      return 'girl';
    }
    if (RegExp(r'\bwom[ae]n\b').hasMatch(value) ||
        value == 'w' ||
        value == 'female') {
      return 'women';
    }
    if (RegExp(r'\bmen\b').hasMatch(value) ||
        RegExp(r'\bman\b').hasMatch(value) ||
        value == 'm' ||
        value == 'male') {
      return 'men';
    }
    return null;
  }

  static _VariantInfo _extractVariantInfo(
    Product product,
    List<String> fallbackImages,
  ) {
    if (product.variants.isEmpty) {
      return _VariantInfo(
        colorNames: const [],
        colorImages: const [],
        sizes: _sizesFromAttributes(product),
      );
    }

    final sizes = <String>{};
    final colors = <String>[];

    for (final variant in product.variants) {
      for (final entry in variant.options.entries) {
        final key = entry.key.trim().toLowerCase();
        final value = entry.value.trim();
        if (value.isEmpty) continue;

        if (key == 'size' || key == 'age' || _isSizeValue(value)) {
          // Keep original casing for kids ages like `2-3Y`.
          sizes.add(value);
        } else if (key == 'color' || key == 'colour') {
          final label = value.toUpperCase();
          if (!colors.contains(label)) colors.add(label);
        }
      }
    }

    // Color-only variants: still expose color swatches from images.
    final images = fallbackImages.isNotEmpty
        ? fallbackImages
        : product.variants
            .map((v) => v.primaryImageUrl)
            .whereType<String>()
            .toList();

    if (sizes.isEmpty) {
      sizes.addAll(_sizesFromAttributes(product));
    }

    return _VariantInfo(
      colorNames: colors,
      colorImages: images.isNotEmpty ? images : fallbackImages,
      sizes: sizes.toList(growable: false),
    );
  }

  static List<String> _sizesFromAttributes(Product product) {
    final sizes = <String>[];
    for (final entry in product.attributes.entries) {
      final key = entry.key.trim().toLowerCase();
      if (key != 'size' && key != 'age' && key != 'ages') continue;
      final value = entry.value.trim();
      if (value.isEmpty) continue;
      sizes.add(value);
    }
    return sizes;
  }

  static bool _isSizeValue(String value) {
    final upper = value.toUpperCase().trim();
    const adult = {'XS', 'S', 'M', 'L', 'XL', 'XXL', 'XXXL'};
    if (adult.contains(upper)) return true;
    // Kids age-style sizes: 0-6M, 2-4Y, 2-3 Y, etc.
    return RegExp(
      r'^\d+\s*-\s*\d+\s*(M|Y|Months?|Years?)?$',
      caseSensitive: false,
    ).hasMatch(value.trim());
  }

  static String? optionValue(ProductVariant variant, String key) {
    for (final entry in variant.options.entries) {
      if (entry.key.toLowerCase() == key.toLowerCase()) {
        return entry.value.trim();
      }
    }
    // Check aliases
    final lowerKey = key.toLowerCase();
    if (lowerKey == 'size') {
      for (final entry in variant.options.entries) {
        final k = entry.key.toLowerCase();
        if (k == 'age' || k == 'ages' || k == 'sizes') {
          return entry.value.trim();
        }
      }
    } else if (lowerKey == 'color') {
      for (final entry in variant.options.entries) {
        final k = entry.key.toLowerCase();
        if (k == 'colour' || k == 'colors' || k == 'colours') {
          return entry.value.trim();
        }
      }
    }

    final name = variant.variantName;
    if (name.isNotEmpty) {
      final parts = name.split(RegExp(r'[/,|]')).map((s) => s.trim()).toList();
      for (final part in parts) {
        if (part.contains(':')) {
          final kv = part.split(':');
          if (kv.length >= 2 && kv[0].trim().toLowerCase() == lowerKey) {
            return kv.sublist(1).join(':').trim();
          }
        } else {
          final upper = part.toUpperCase();
          if (lowerKey == 'size') {
            const sizeKeywords = {'XS', 'S', 'M', 'L', 'XL', 'XXL', 'XXXL', 'FREE SIZE', 'FS'};
            final isAge = RegExp(r'^\d+\s*-\s*\d+\s*(M|Y|Months?|Years?)?$', caseSensitive: false).hasMatch(part);
            if (sizeKeywords.contains(upper) || isAge) {
              return part;
            }
          } else if (lowerKey == 'color') {
            if (!part.contains(RegExp(r'\d')) && part.length < 25 && upper != 'M' && upper != 'S' && upper != 'L' && upper != 'XL') {
              return part;
            }
          }
        }
      }
    }
    return null;
  }

  static ProductVariant? matchingVariant({
    required List<ProductVariant> variants,
    String? selectedColor,
    required String selectedSize,
  }) {
    if (variants.isEmpty) return null;



    final wantedColor = selectedColor?.trim().toUpperCase();
    final wantedSize = selectedSize.trim().toUpperCase();

    for (final variant in variants) {
      final color = optionValue(variant, 'Color')?.toUpperCase();
      final size = optionValue(variant, 'Size')?.toUpperCase();

      final colorMatches = wantedColor == null ||
          wantedColor.isEmpty ||
          color == wantedColor;
      final sizeMatches = size == null ||
          size == wantedSize ||
          areKidsSizesEquivalent(size, wantedSize);

      if (colorMatches && sizeMatches) return variant;
    }

    // Fallback 1: keep size, ignore color.
    for (final variant in variants) {
      final size = optionValue(variant, 'Size')?.toUpperCase();
      if (size == wantedSize || areKidsSizesEquivalent(size, wantedSize)) {
        return variant;
      }
    }

    // Fallback 2: keep color, ignore size.
    if (wantedColor != null && wantedColor.isNotEmpty) {
      for (final variant in variants) {
        final color = optionValue(variant, 'Color')?.toUpperCase();
        if (color == wantedColor) return variant;
      }
    }

    return variants.first;
  }

  static ResolvedPrice resolvePrice(WardrobeItem item, {ProductVariant? variant}) {
    if (variant != null) {
      return resolveVariantPrice(variant);
    }
    return resolveRawPrices(
      actualPrice: item.actualPrice ?? item.price,
      costPrice: item.costPrice,
    );
  }
}

class ResolvedPrice {
  /// Original / compare-at price (strikethrough when [hasDiscount] is true).
  final String actualPrice;

  /// Final selling / discounted price shown as the primary price.
  final String discountedPrice;

  const ResolvedPrice({
    required this.actualPrice,
    required this.discountedPrice,
  });

  bool get hasDiscount {
    final selling = ProductMapper.parseAmount(discountedPrice);
    final original = ProductMapper.parseAmount(actualPrice);
    if (selling == null || selling <= 0) return false;
    if (original == null || original <= 0) return false;
    return original > selling;
  }
}

class _VariantInfo {
  final List<String> colorNames;
  final List<String> colorImages;
  final List<String> sizes;

  const _VariantInfo({
    required this.colorNames,
    required this.colorImages,
    required this.sizes,
  });
}
