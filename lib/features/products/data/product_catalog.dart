import 'package:nomowear/features/products/data/models/product.dart';

class ProductCatalog {
  ProductCatalog._();

  /// Exact Admin / backend `tab` query values for `GET /mobile/v1/products`.
  static const wardrobeApiTabs = [
    'Comfort wardrobe',
    'Professional wardrobe',
    'Premium wardrobe',
    'Kids Wardrobe',
    'Essentialswardrobe',
  ];

  /// Non-essentials tabs used for category-lock matching only — not card inventory.
  static List<String> get homeWardrobeKeys => wardrobeApiTabs
      .where((tab) => !isEssentialsTab(tab))
      .toList(growable: false);

  static bool isEssentialsTab(String tab) {
    return tab.trim().toLowerCase().contains('essentials');
  }

  static bool isKidsProduct(Product product) {
    if (!product.isSingleItem) return false;
    final category = product.categoryName?.toLowerCase() ?? '';
    if (category == 'kids wardrobe' ||
        category == 'kidswardrobe' ||
        category.contains('kids')) {
      return true;
    }
    final name = product.productName.toLowerCase();
    if (RegExp(r'\b(kids?|boys?|girls?)\b').hasMatch(name)) {
      return true;
    }
    return false;
  }

  static bool isEssentialsProduct(Product product) {
    if (!product.isSingleItem) return false;
    final cat = product.categoryName?.toLowerCase() ?? '';
    return cat == 'essentials' ||
        cat == 'essentialswardrobe' ||
        cat.contains('essentials');
  }

  /// Single items bought directly (essentials + kids), not via wardrobe kits.
  static bool isDirectPurchaseProduct(Product product) =>
      isEssentialsProduct(product) || isKidsProduct(product);

  /// Returns whether prices should be displayed for a product or category.
  /// Rental/subscription wardrobe categories (e.g. "Professional Wardrobe",
  /// "Comfort Wardrobe", "Premium Wardrobe") do not show item prices because
  /// they are rented as part of a wardrobe kit subscription.
  /// Only direct-purchase items (Daily Essentials, Kids Wear) display prices.
  static bool shouldShowPrice({String? category, Product? product}) {
    final cat = (category ?? product?.categoryName ?? '').trim().toLowerCase();
    if (cat.contains('professional') ||
        cat.contains('comfort') ||
        cat.contains('premium')) {
      return false;
    }
    if (product != null && isDirectPurchaseProduct(product)) {
      return true;
    }
    if (cat.contains('essential') || cat.contains('kid')) {
      return true;
    }
    return false;
  }

  /// Maps a display category (e.g. product name) to the backend `tab` value.
  static String? apiTabForCategory(String category) {
    final needle = category.trim().toLowerCase();
    if (needle.isEmpty) return null;

    for (final tab in wardrobeApiTabs) {
      if (needle == tab.toLowerCase()) return tab;
    }

    // "Kids Essentials" / any essentials label must map to Essentialswardrobe,
    // not Kidswardrobe (which also matches the substring "kids").
    if (needle.contains('essential')) {
      for (final tab in wardrobeApiTabs) {
        if (isEssentialsTab(tab)) return tab;
      }
    }

    // Prefer the longest core match (e.g. "professional" over shorter cores).
    String? best;
    var bestLen = -1;
    for (final tab in wardrobeApiTabs) {
      final core = tab.toLowerCase().replaceAll('wardrobe', '').trim();
      if (core.isEmpty) continue;
      if (needle.contains(core) && core.length > bestLen) {
        best = tab;
        bestLen = core.length;
      }
    }
    return best;
  }

  /// One Home card from a tab response. Empty `data` → no card.
  static Product? cardFromTabProducts(List<Product> products) {
    if (products.isEmpty) return null;
    for (final product in products) {
      if (product.isWardrobeKit) return product;
    }
    return products.first;
  }

  static Product? findWardrobeKit(List<Product> products, String categoryOrName) {
    final kits = products.where((p) => p.isWardrobeKit).toList();
    final needle = categoryOrName.toLowerCase().trim();

    for (final kit in kits) {
      if (kit.productName.toLowerCase() == needle) return kit;
      final category = kit.categoryName?.toLowerCase() ?? '';
      if (category == needle) return kit;
    }

    final normalized = needle.replaceAll('wardrobe', '').trim();
    if (normalized.isNotEmpty) {
      for (final kit in kits) {
        final name = kit.productName.toLowerCase();
        final category = kit.categoryName?.toLowerCase() ?? '';
        if (name.contains(normalized) || category.contains(normalized)) {
          return kit;
        }
      }
    }

    return null;
  }

  static List<Product> essentialsItems(List<Product> products) {
    return products.where(isEssentialsProduct).toList(growable: false);
  }

  static List<Product> kidsItems(List<Product> products) {
    return products.where(isKidsProduct).toList(growable: false);
  }

  static List<Product> kitListingItems(
    Product kit,
    List<Product> allProducts,
  ) {
    final nested = kit.items
        .where((item) => !isDirectPurchaseProduct(item))
        .toList(growable: false);
    if (nested.isNotEmpty) return nested;

    if (kit.kitItems.isEmpty) return const [];

    final byId = {for (final product in allProducts) product.id: product};
    final resolved = <Product>[];
    final seen = <String>{};
    for (final ref in kit.kitItems) {
      final product = byId[ref.id];
      if (product == null || isDirectPurchaseProduct(product)) continue;
      if (seen.add(product.id)) resolved.add(product);
    }
    return resolved;
  }

  /// Products for a wardrobe listing screen.
  ///
  /// The repository already requests products with the correct `tab`. Do not
  /// re-filter by `product_class` / `category_name` here — that silently drops
  /// valid API products (Comfort Wear, Kids, Essentials, etc.).
  static List<Product> wardrobeListingItems(
    List<Product> products,
    String category,
  ) {
    final kept = <Product>[];
    for (final product in products) {
      if (product.id.trim().isEmpty) {
        _logListingFilterDrop(
          category: category,
          productId: product.id,
          productName: product.productName,
          reason: 'empty_product_id',
        );
        continue;
      }
      if (product.productName.trim().isEmpty) {
        _logListingFilterDrop(
          category: category,
          productId: product.id,
          productName: product.productName,
          reason: 'empty_product_name',
        );
        continue;
      }
      kept.add(product);
    }
    return kept;
  }

  static void _logListingFilterDrop({
    required String category,
    required String productId,
    required String productName,
    required String reason,
  }) {
    assert(() {
      // ignore: avoid_print
      print(
        '[PRODUCT_LIST_FILTER] category=$category '
        'productId=$productId productName=$productName reason=$reason',
      );
      return true;
    }());
  }

  static String wardrobeDisplayCategory(Product kit) {
    if (kit.categoryName != null && kit.categoryName!.trim().isNotEmpty) {
      return kit.categoryName!;
    }
    return kit.productName;
  }
}
