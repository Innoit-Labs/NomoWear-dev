import 'package:flutter/foundation.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:nomowear/core/app_export.dart';
import 'package:nomowear/core/network/api_exception.dart';
import 'package:nomowear/core/utils/api_id_utils.dart';
import 'package:nomowear/core/utils/kids_size_utils.dart';
import 'package:nomowear/features/products/data/product_mapper.dart';
import 'package:nomowear/features/products/data/product_repository.dart';
import 'package:nomowear/features/products/data/models/product_variant.dart';
import 'package:nomowear/features/products/data/product_catalog.dart';
import 'package:nomowear/features/wardrobe/presentation/screens/wardrobe_screen.dart';
import 'package:nomowear/features/cart/presentation/bloc/cart_bloc.dart';
import 'package:nomowear/features/cart/presentation/utils/cart_limits.dart';
import 'package:nomowear/features/cart/presentation/utils/cart_stock.dart';
import 'package:nomowear/features/cart/presentation/widgets/wardrobe_limit_dialog.dart';

import '../../../favorites/presentation/bloc/favorites_bloc.dart';

class ProductDetailsScreen extends StatefulWidget {
  final WardrobeItem product;

  const ProductDetailsScreen({Key? key, required this.product})
      : super(key: key);



  @override
  State<ProductDetailsScreen> createState() => _ProductDetailsScreenState();
}

class _ProductDetailsScreenState extends State<ProductDetailsScreen> {
  int _currentImage = 0;
  int _selectedColorIndex = 0;
  String _selectedSize = 'M';
  bool _isLoadingDetails = false;
  WardrobeItem? _loadedProduct;
  static const List<String> _adultSizeOrder = [
    'XS',
    'S',
    'M',
    'L',
    'XL',
    'XXL',
    'XXXL',
  ];

  late PageController _pageController;

  WardrobeItem get _product => _loadedProduct ?? widget.product;

  bool get _isKidsProduct {
    final category = (_product.category ?? '').toLowerCase();
    if (category.contains('kids')) return true;
    if (_product.ages.isNotEmpty) return true;
    if (_product.genderTag == 'boy' || _product.genderTag == 'girl') {
      return true;
    }
    final title = _product.title.toLowerCase();
    if (RegExp(r'\b(kids?|boys?|girls?)\b').hasMatch(title)) {
      return true;
    }
    // Infer from variant size labels like 0-3M / 2-4Y or kids age sizes.
    for (final variant in _product.variants) {
      final size = _variantOptionValue(variant.options, 'Size');
      if (size != null && (isKidsAgeSize(size) || _looksLikeKidsAgeSize(size))) {
        return true;
      }
    }
    for (final size in _product.sizes) {
      if (isKidsAgeSize(size) || _looksLikeKidsAgeSize(size)) return true;
    }
    return false;
  }

  static bool _isAdultLetterSize(String size) {
    return _adultSizeOrder.contains(size.trim().toUpperCase());
  }

  static bool _looksLikeKidsAgeSize(String size) {
    return RegExp(
      r'^\d+\s*-\s*\d+\s*(M|Y|Months?|Years?)?$',
      caseSensitive: false,
    ).hasMatch(size.trim());
  }

  List<String> get _colorImages =>
      _product.colorVariantImages.isNotEmpty
          ? _product.colorVariantImages
          : [_product.imageUrl];

  List<String> get _allImages {
    if (_product.imageUrls.length > 1) return _product.imageUrls;
    return _colorImages.length > 1 ? _colorImages : [_product.imageUrl];
  }

  String? _variantOptionValue(Map<String, String> options, String key) {
    for (final entry in options.entries) {
      if (entry.key.toLowerCase() == key.toLowerCase()) {
        return entry.value.trim();
      }
    }
    return null;
  }

  List<String> get _availableColors {
    if (_product.variants.isNotEmpty) {
      final colors = <String>[];
      for (final variant in _product.variants) {
        final color = _variantOptionValue(variant.options, 'Color');
        if (color == null || color.isEmpty) continue;
        final label = color.toUpperCase();
        if (!colors.contains(label)) colors.add(label);
      }
      if (colors.isNotEmpty) return colors;
    }
    return _product.colorNames.map((c) => c.toUpperCase()).toList(growable: false);
  }

  String? get _selectedColor {
    final colors = _availableColors;
    if (colors.isEmpty) return null;
    final index = _selectedColorIndex.clamp(0, colors.length - 1);
    return colors[index];
  }

  String get _selectedColorName => _selectedColor ?? 'DEFAULT';

  List<String> get _sizes {
    final selectedColor = _selectedColor;
    final fromVariants = <String>{};

    if (_product.variants.isNotEmpty) {
      for (final variant in _product.variants) {
        final color =
            _variantOptionValue(variant.options, 'Color')?.toUpperCase();
        final size = _variantOptionValue(variant.options, 'Size');
        if (size == null || size.isEmpty) continue;
        if (selectedColor != null && color != null && color != selectedColor) {
          continue;
        }
        fromVariants.add(size.trim());
      }

      if (fromVariants.isEmpty && selectedColor != null) {
        for (final variant in _product.variants) {
          final size = _variantOptionValue(variant.options, 'Size');
          if (size != null && size.isNotEmpty) {
            fromVariants.add(size.trim());
          }
        }
      }
    }

    List<String> normalize(Iterable<String> raw) {
      final sizes = raw
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      if (_isKidsProduct) {
        sizes.removeWhere(_isAdultLetterSize);
      }
      sizes.sort(_compareSizes);
      return sizes;
    }

    if (fromVariants.isNotEmpty) {
      return normalize(fromVariants);
    }

    if (_product.sizes.isNotEmpty) {
      return normalize(_product.sizes);
    }
    if (_isKidsProduct && _product.ages.isNotEmpty) {
      return normalize(_product.ages);
    }
    if (_isKidsProduct) return const [];
    return List<String>.from(_adultSizeOrder.skip(1)); // S..XXXL fallback
  }

  int _compareSizes(String a, String b) {
    if (_isKidsProduct) {
      return compareKidsSizes(a, b);
    }
    final ai = _adultSizeOrder.indexOf(a.toUpperCase());
    final bi = _adultSizeOrder.indexOf(b.toUpperCase());
    if (ai == -1 && bi == -1) return a.compareTo(b);
    if (ai == -1) return 1;
    if (bi == -1) return -1;
    return ai.compareTo(bi);
  }

  List<String> get _displaySizes {
    final available = _sizes;
    if (_isKidsProduct) {
      // Kids: only age-based sizes from the product (no S/M/L placeholders).
      return available;
    }
    const base = ['S', 'M', 'L', 'XL', 'XXL', 'XXXL'];
    final display = <String>[...base];
    for (final size in available) {
      final label = size.toUpperCase();
      if (!display.contains(label)) display.add(label);
    }
    return display;
  }

  ProductVariant? get _selectedVariant => ProductMapper.matchingVariant(
        variants: _product.variants,
        selectedColor: _selectedColor,
        selectedSize: _selectedSize,
      );

  bool _isOutOfStockStatus(String status) {
    final normalized = status.trim().toUpperCase();
    if (normalized.isEmpty) return false;
    return normalized == 'OUT_OF_STOCK' ||
        normalized == 'OUT OF STOCK' ||
        normalized == 'OOS';
  }

  bool _isSelectedVariantAvailable() {
    final variant = _selectedVariant;
    if (variant != null) {
      if (_isOutOfStockStatus(variant.stockStatus)) return false;
      if (variant.stockOnHand <= 0) return false;
      return true;
    }
    if (_isOutOfStockStatus(_product.stockStatus)) {
      return false;
    }
    return true;
  }



  List<String> get _details {
    final extraDetails = _product.productDetails.where((line) {
      final lower = line.toLowerCase();
      return !lower.startsWith('stock:') && !lower.startsWith('category:');
    }).toList(growable: false);
    return extraDetails.take(4).toList(growable: false);
  }

  String get _favoriteId => _product.favoriteId;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    final initialSizes = _sizes;
    if (initialSizes.isNotEmpty) {
      _selectedSize = initialSizes.first;
    }
    _loadProductDetails();
  }

  Future<void> _loadProductDetails() async {
    final productId = widget.product.productId;
    if (productId == null || productId.isEmpty) return;

    setState(() => _isLoadingDetails = true);
    try {
      final product = await ProductRepository().getProductById(productId);
      if (!mounted) return;
      final mapped = ProductMapper.toWardrobeItem(
        product,
      );
      setState(() {
        _loadedProduct = mapped;
        final loadedSizes = _sizes;
        if (loadedSizes.isNotEmpty) {
          final stillMatches = loadedSizes.any((s) => _isKidsProduct
              ? areKidsSizesEquivalent(s, _selectedSize)
              : s.toUpperCase() == _selectedSize.toUpperCase());
          if (!stillMatches) {
            _selectedSize = loadedSizes.first;
          }
        }
        _isLoadingDetails = false;
      });
    } on ApiException {
      if (mounted) setState(() => _isLoadingDetails = false);
    } catch (_) {
      if (mounted) setState(() => _isLoadingDetails = false);
    }
  }

  CartItem _buildCartItem() {
    final selectedImage = _selectedColorIndex < _allImages.length
        ? _allImages[_selectedColorIndex]
        : _product.imageUrl;
    final variant = _selectedVariant;
    final productId = _product.productId;
    final prices = ProductMapper.resolvePrice(_product, variant: variant);
    final price = prices.discountedPrice;

    final itemType = CartLimits.cartItemTypeForListing(itemType: _product.itemType);
    final isKids = itemType == 'kids' ||
        isKidsCategory(_product.category) ||
        _isKidsProduct;
    final isEssential = isKids ||
        itemType == 'essentials' ||
        isEssentialCategory(_product.category);
    final effectiveItemType = isKids
        ? 'kids'
        : (isEssential ? 'essentials' : itemType);

    // Let CartItem build the canonical line id (product_variant_type) so pending
    // checks and CartBloc keys stay in sync with Product ↔ Cart screens.
    final displaySelectedSize =
        isKids ? formatKidsSize(_selectedSize) : _selectedSize;

    return CartItem(
      productId: productId ?? _favoriteId,
      variantId: isApiUuid(variant?.id) ? variant!.id : null,
      title: _product.title,
      imageUrl: selectedImage,
      price: price,
      selectedSize: displaySelectedSize,
      isEssential: isEssential,
      isKids: isKids,
      isSubscriptionGarment: !isEssential && effectiveItemType == 'subscription',
      itemType: effectiveItemType,
      category: _product.category,
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goToImage(int index) {
    if (index < 0 || index >= _allImages.length) return;
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<CartBloc, CartState>(
      listenWhen: (prev, curr) =>
          curr.errorMessage != null &&
          curr.errorMessage != prev.errorMessage &&
          isSubscriptionQuotaError(curr.errorMessage),
      listener: (context, state) {
        _showSubscriptionQuotaDialog(context, state.errorMessage!);
      },
      child: Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      body: SafeArea(
        child: Column(
          children: [
            _buildAppBar(),
            Container(
              height: 2,
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    Color(0xFFE6C27A).withOpacity(0.15),
                    Color(0xFFE6C27A),
                    Color(0xFFE6C27A).withOpacity(0.15),
                  ],
                ),
              ),
            ),
            SizedBox(height: 16.h),

            Expanded(
              child: Stack(
                children: [
                  SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildImageCarousel(),
                        SizedBox(height: 16.h),
                        _buildTitleRow(),
                        if (_shouldShowPrice) ...[
                          SizedBox(height: 6.h),
                          _buildPriceSection(),
                        ],
                        SizedBox(height: 8.h),
                        _buildDescription(),
                        SizedBox(height: 20.h),
                        _buildColorSection(),
                        SizedBox(height: 20.h),
                        _buildSizeSection(),
                        SizedBox(height: 20.h),
                        _buildProductDetailsSection(),
                        SizedBox(height: 30.h),
                      ],
                    ),
                  ),
                  if (_isLoadingDetails)
                    Positioned.fill(
                      child: Container(
                        color: Colors.black45,
                        child: Center(
                          child: CircularProgressIndicator(
                            color: AppColours.primary,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            _buildBottomBar(),
          ],
        ),
      ),
    ),
    );
  }

  // ── App Bar ──────────────────────────────────────────────────────────────
  Widget _buildAppBar() {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),

              child: Icon(Icons.arrow_back,
                  color: AppColours.primary, size: 28),

          ),
          Expanded(
            child: Text(
              'Product Details',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColours.primary,
                fontSize: 18.fSize,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ),
          BlocBuilder<CartBloc, CartState>(
            buildWhen: (previous, current) =>
                previous.totalItems != current.totalItems,
            builder: (context, cartState) {
              final count = cartState.totalItems;
              return GestureDetector(
                onTap: () {
                  Navigator.pushNamed(
                    context,
                    AppRoutes.homeScreen,
                    arguments: 2,
                  );
                },
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1A1A),
                        borderRadius: BorderRadius.circular(10),
                        border:
                            Border.all(color: AppColours.primary.withOpacity(0.3)),
                      ),
                      child: Icon(Icons.shopping_cart_outlined,
                          color: AppColours.primary, size: 22),
                    ),
                    if (count > 0)
                      Positioned(
                        top: -4,
                        right: -4,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: AppColours.primary,
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            '$count',
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: 10.fSize,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // ── Image Carousel ──────────────────────────────────────────────────────
  Widget _buildImageCarousel() {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final height = (width * 11 / 10).clamp(0.0, 220.h);

          return SizedBox(
            width: width,
            height: height,
            child: Stack(
              children: [
                PageView.builder(
                  controller: _pageController,
                  itemCount: _allImages.length,
                  onPageChanged: (i) => setState(() => _currentImage = i),
                  itemBuilder: (_, index) {
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        color: const Color(0xFF1A1A1A),
                        child: ProductImage(
                          imageUrl: _allImages[index],
                          fit: BoxFit.fill,
                          width: double.maxFinite,
                          height: double.maxFinite,
                        ),
                      ),
                    );
                  },
                ),
                if (_currentImage > 0)
                  Positioned(
                    left: 8.w,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: _arrowButton(Icons.chevron_left, () {
                        _goToImage(_currentImage - 1);
                      }),
                    ),
                  ),
                if (_currentImage < _allImages.length - 1)
                  Positioned(
                    right: 8.w,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: _arrowButton(Icons.chevron_right, () {
                        _goToImage(_currentImage + 1);
                      }),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _arrowButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34.w,
        height: 34.h,
        decoration: BoxDecoration(
          color: Colors.black54,
          shape: BoxShape.circle,
          border: Border.all(color: AppColours.primary.withOpacity(0.5)),
        ),
        child: Icon(icon, color: AppColours.primary, size: 22),
      ),
    );
  }

  // ── Title + Heart + Share ───────────────────────────────────────────────
  Widget _buildTitleRow() {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 20.w),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _product.title,
              style: CustomTextStyles.montserratBold.copyWith(fontSize: 16,color: AppColours.primary),
            ),
          ),
          SizedBox(width: 12.w),
          BlocBuilder<FavoritesBloc, FavoritesState>(
            builder: (context, favoritesState) {
              final isFav = favoritesState.isFavorite(_favoriteId);

              return Material(
                color: Colors.transparent,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () {
                    final item = FavoriteItem(
                      id: _favoriteId,
                      title: _product.title,
                      subtitle: _product.description,
                      imageUrl: _product.imageUrl,
                    );
                    context.read<FavoritesBloc>().add(ToggleFavoriteEvent(item));

                    ScaffoldMessenger.of(context).clearSnackBars();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          isFav
                              ? 'Removed from wishlist'
                              : 'Added to wishlist',
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: 13.fSize,
                          ),
                        ),
                        backgroundColor: AppColours.primary,
                        duration: const Duration(seconds: 1),
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    );
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isFav
                          ? AppColours.primary
                          : Colors.transparent,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColours.primary,
                        width: isFav ? 2 : 1,
                      ),
                    ),
                    child: Icon(
                      isFav ? Icons.favorite : Icons.favorite_border,
                      color: isFav ? Colors.black : AppColours.primary,
                      size: 22,
                    ),
                  ),
                ),
              );
            },
          ),
          SizedBox(width: 16.w),
          GestureDetector(
            onTap: () {},
            child: Icon(Icons.share_outlined,
                color: AppColours.primary, size: 22),
          ),
        ],
      ),
    );
  }

  bool get _shouldShowPrice =>
      ProductCatalog.shouldShowPrice(category: _product.category);

  Widget _buildPriceSection() {
    if (!_shouldShowPrice) return const SizedBox.shrink();
    final prices = ProductMapper.resolvePrice(_product, variant: _selectedVariant);

    if (prices.hasDiscount) {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: 20.w),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              prices.discountedPrice,
              style: CustomTextStyles.montserratBold.copyWith(
                fontSize: 18,
                color: AppColours.primary,
              ),
            ),
            SizedBox(width: 8.w),
            Text(
              prices.actualPrice,
              style: TextStyle(
                color: Colors.white54,
                fontSize: 14.fSize,
                decoration: TextDecoration.lineThrough,
                decorationColor: Colors.white54,
              ),
            ),
          ],
        ),
      );
    } else {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: 20.w),
        child: Text(
          prices.discountedPrice,
          style: CustomTextStyles.montserratBold.copyWith(
            fontSize: 18,
            color: AppColours.primary,
          ),
        ),
      );
    }
  }

  // ── Description ─────────────────────────────────────────────────────────
  Widget _buildDescription() {
    if (_product.description.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 20.w),
      child: Text(
        _product.description,
        style: CustomTextStyles.montserratRegular.copyWith(fontSize: 12),
      ),
    );
  }

  // ── Color Section ───────────────────────────────────────────────────────
  Widget _buildColorSection() {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 20.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: 'SELECTED COLOR: ',
                  style: CustomTextStyles.montserratSemiBold.copyWith(fontSize: 14)

                ),
                TextSpan(
                  text: _selectedColorName,
                    style: CustomTextStyles.montserratSemiBold.copyWith(fontSize: 14,color: AppColours.primary)

                ),
              ],
            ),
          ),
          SizedBox(height: 12.h),
          SizedBox(
            height: 62.h,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _availableColors.length,
              separatorBuilder: (_, __) => SizedBox(width: 10.w),
              itemBuilder: (_, index) {
                final isActive = _selectedColorIndex == index;
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedColorIndex = index;
                      final sizes = _sizes;
                      if (sizes.isNotEmpty &&
                          !sizes.any(
                            (s) =>
                                s.toUpperCase() ==
                                _selectedSize.toUpperCase(),
                          )) {
                        _selectedSize = sizes.first;
                      }
                    });
                    if (_allImages.isNotEmpty) {
                      _goToImage(index.clamp(0, _allImages.length - 1));
                    }
                  },
                  child: Container(
                    width: 62.w,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isActive
                            ? AppColours.primary
                            : Colors.white12,
                        width: isActive ? 2 : 1,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(7),
                      child: ProductImage(
                        imageUrl: index < _colorImages.length
                            ? _colorImages[index]
                            : _product.imageUrl,
                        fit: BoxFit.fill,
                        width: double.infinity,
                        height: double.infinity,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── Size Section ────────────────────────────────────────────────────────
  Widget _buildSizeSection() {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 18.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SIZE',
            style: CustomTextStyles.montserratSemiBold.copyWith(fontSize: 14),
          ),
          SizedBox(height: 12.h),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < _displaySizes.length; i++) ...[
                  if (i > 0) SizedBox(width: 10.w),
                  _buildSizeChip(_displaySizes[i]),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSizeChip(String size) {
    final isAvailable = _isKidsProduct
        ? true
        : _sizes.map((s) => s.toUpperCase()).contains(size.toUpperCase());
    final isActive = _isKidsProduct
        ? areKidsSizesEquivalent(_selectedSize, size)
        : _selectedSize.toUpperCase() == size.toUpperCase();
    final isCompact = !_isKidsProduct && _isAdultLetterSize(size);
    final displayLabel = _isKidsProduct ? formatKidsSize(size) : size;

    return GestureDetector(
      onTap: isAvailable ? () => setState(() => _selectedSize = size) : null,
      child: Container(
        width: isCompact ? 48.w : null,
        height: 40.h,
        padding: EdgeInsets.symmetric(horizontal: isCompact ? 0 : 14.w),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isActive ? AppColours.secondary : const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive
                ? AppColours.primary
                : (isAvailable ? AppColours.primary : Colors.white10),
            width: isActive ? 1.5 : 1,
          ),
        ),
        child: Text(
          displayLabel,
          style: TextStyle(
            color: isActive
                ? Colors.black
                : (isAvailable ? AppColours.secondary : Colors.white38),
            fontSize: 13.fSize,
            fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  // ── Product Details Section ─────────────────────────────────────────────
  Widget _buildProductDetailsSection() {
    if (_details.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 20.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [


          

          Text(
            'PRODUCT DETAILS',
            style: CustomTextStyles.montserratBold.copyWith(fontSize: 13,color: AppColours.primary),
          ),
          SizedBox(height: 10.h),
          ..._details.map(
            (d) => Padding(
              padding: EdgeInsets.only(bottom: 6.h),
              child: Row(
                children: [
                  Text(
                    '·  ',
                    style: TextStyle(
                        color: AppColours.secondary, fontSize: 14.fSize),
                  ),
                  Text(
                    d,
                      style: CustomTextStyles.openSansRegular.copyWith(fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Bottom Bar ──────────────────────────────────────────────────────────
  Widget _buildBottomBar() {
    return BlocBuilder<CartBloc, CartState>(
      key: ValueKey('bottom_bar_${_selectedSize}_$_selectedColorIndex'),
      buildWhen: (previous, current) {
        final cartItem = _buildCartItem();
        return previous.quantityForListingCard(
                  productId: cartItem.productId,
                  variantId: cartItem.variantId,
                  itemType: cartItem.itemType,
                ) !=
                current.quantityForListingCard(
                  productId: cartItem.productId,
                  variantId: cartItem.variantId,
                  itemType: cartItem.itemType,
                ) ||
            previous.isProductPending(
                  productId: cartItem.productId,
                  variantId: cartItem.variantId,
                  itemType: cartItem.itemType,
                ) !=
                current.isProductPending(
                  productId: cartItem.productId,
                  variantId: cartItem.variantId,
                  itemType: cartItem.itemType,
                ) ||
            previous.isVariantOutOfStock(
                  productId: cartItem.productId,
                  variantId: cartItem.variantId,
                  itemType: cartItem.itemType,
                ) !=
                current.isVariantOutOfStock(
                  productId: cartItem.productId,
                  variantId: cartItem.variantId,
                  itemType: cartItem.itemType,
                );
      },
      builder: (context, cartState) {
        final cartItem = _buildCartItem();
        final existingLine = cartState.lineForListingCard(
          productId: cartItem.productId,
          variantId: cartItem.variantId,
          itemType: cartItem.itemType,
        );
        final lineId = existingLine?.id ?? cartItem.id;
        final qty = cartState.quantityForListingCard(
          productId: cartItem.productId,
          variantId: cartItem.variantId,
          itemType: cartItem.itemType,
        );
        final pending = cartState.isProductPending(
          productId: cartItem.productId,
          variantId: cartItem.variantId,
          itemType: cartItem.itemType,
        );
        final outOfStock = cartState.isVariantOutOfStock(
          productId: cartItem.productId,
          variantId: cartItem.variantId,
          itemType: cartItem.itemType,
        );
        final outOfStockFromProduct = !_isSelectedVariantAvailable();
        final showOutOfStock = outOfStock || outOfStockFromProduct;
        final buttonState = qty > 0
            ? 'QTY'
            : pending
                ? 'LOADING'
                : showOutOfStock
                    ? 'OUT_OF_STOCK'
                    : 'ADD_TO_CART';
        if (kDebugMode) {
          debugPrint('[STOCK_DEBUG]');
          debugPrint('productId=${cartItem.productId}');
          debugPrint('variantId=${cartItem.variantId ?? '-'}');
          debugPrint('size=${cartItem.selectedSize}');
          debugPrint('stockQuantity=${_selectedVariant?.stockOnHand}');
          debugPrint('isAvailable=${_isSelectedVariantAvailable()}');
          debugPrint('buttonState=$buttonState');
        }

        debugPrint('===== SELECTED VARIANT BEFORE CART =====');
        debugPrint('selected size = $_selectedSize');
        debugPrint('selected color = $_selectedColor');
        debugPrint('selected variant id = ${_selectedVariant?.id}');
        debugPrint('selected variant name = ${_selectedVariant?.variantName}');
        debugPrint('selected variant stock = ${_selectedVariant?.stockOnHand}');
        debugPrint('========================================');

        final syncedCartItem = CartItem(
          id: lineId,
          productId: cartItem.productId,
          variantId: existingLine?.variantId ?? cartItem.variantId,
          title: cartItem.title,
          imageUrl: cartItem.imageUrl,
          price: cartItem.price,
          selectedSize: existingLine?.selectedSize ?? cartItem.selectedSize,
          quantity: 1,
          isEssential: cartItem.isEssential,
          isKids: cartItem.isKids,
          isSubscriptionGarment: cartItem.isSubscriptionGarment,
          itemType: cartItem.itemType,
          category: cartItem.category,
        );

        return Container(
          padding: EdgeInsets.fromLTRB(16.w, 14.h, 16.w, 24.h),
          decoration: BoxDecoration(
            color: const Color(0xFF111111),
            border: Border(
              top: BorderSide(color: AppColours.primary.withOpacity(0.15)),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 50.h,
                  child: showOutOfStock && qty <= 0
                      ? OutlinedButton(
                          onPressed: null,
                          style: OutlinedButton.styleFrom(
                            disabledForegroundColor: Colors.white38,
                            side: BorderSide(
                              color: Colors.white.withOpacity(0.2),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            'Out of Stock',
                            style: CustomTextStyles.montserratBold.copyWith(
                              fontSize: 14,
                              color: Colors.white38,
                            ),
                          ),
                        )
                      : qty > 0
                      ? Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColours.primary),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: InkWell(
                                  borderRadius: const BorderRadius.horizontal(left: Radius.circular(12)),
                                  onTap: () {
                                    context.read<CartBloc>().add(
                                          AdjustCartItemQuantityEvent(
                                            lineId,
                                            delta: -1,
                                          ),
                                        );
                                  },
                                  child: Icon(Icons.remove, color: AppColours.primary),
                                ),
                              ),
                              Container(width: 1, color: AppColours.primary.withOpacity(0.35)),
                              Expanded(
                                flex: 2,
                                child: Center(
                                  child: Text(
                                    '$qty',
                                    style: CustomTextStyles.montserratBold.copyWith(
                                      fontSize: 16,
                                      color: AppColours.primary,
                                    ),
                                  ),
                                ),
                              ),
                              Container(width: 1, color: AppColours.primary.withOpacity(0.35)),
                              Expanded(
                                child: InkWell(
                                  borderRadius: const BorderRadius.horizontal(right: Radius.circular(12)),
                                  onTap: () {
                                    final added = tryAddToCart(context, syncedCartItem);
                                    if (!added) return;
                                  },
                                  child: Icon(Icons.add, color: AppColours.primary),
                                ),
                              ),
                            ],
                          ),
                        )
                      : OutlinedButton.icon(
                          onPressed: pending
                              ? null
                              : () {
                                  final added = tryAddToCart(context, syncedCartItem);
                                  if (!added) return;
                                },
                          icon: pending
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.black,
                                  ),
                                )
                              : SvgPicture.asset(IconConstant.Cart, color: Colors.black),
                          label: Text(
                            pending ? 'Adding...' : 'Add to cart',
                            style: CustomTextStyles.montserratBold.copyWith(fontSize: 14, color: Colors.black),
                          ),
                          style: OutlinedButton.styleFrom(
                            backgroundColor: AppColours.primary,
                            side: BorderSide(color: AppColours.primary),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                ),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: SizedBox(
                  height: 50.h,
                  child: ElevatedButton.icon(
                    onPressed: showOutOfStock
                        ? null
                        : () {
                      final added = tryAddToCart(context, syncedCartItem);
                      if (!added) return;

                      Navigator.pushNamedAndRemoveUntil(
                        context,
                        AppRoutes.homeScreen,
                        (route) => false,
                        arguments: 2,
                      );
                    },
                    icon: SvgPicture.asset(IconConstant.buyNow),
                    label: Text(
                      'Order Now',
                      style: CustomTextStyles.montserratBold.copyWith(fontSize: 14, color: Colors.black),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColours.primary,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showSubscriptionQuotaDialog(BuildContext context, String message) {
    final details = SubscriptionQuotaDetails.parse(message);
    if (kDebugMode) {
      debugPrint('[CART_QUOTA] showing subscription limit dialog');
    }
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1D21),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Subscription Limit Reached',
          style: CustomTextStyles.montserratBold.copyWith(
            fontSize: 18,
            color: AppColours.primary,
          ),
        ),
        content: Text(
          details.userFriendlyMessage,
          style: CustomTextStyles.openSansRegular.copyWith(
            fontSize: 14,
            color: Colors.white70,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'OK',
              style: CustomTextStyles.openSansSemiBold.copyWith(
                color: AppColours.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
