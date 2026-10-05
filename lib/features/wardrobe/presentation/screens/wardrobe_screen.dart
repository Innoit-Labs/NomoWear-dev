import 'package:flutter/foundation.dart';
import 'package:nomowear/core/app_export.dart';
import 'package:nomowear/core/network/api_exception.dart';
import 'package:nomowear/core/services/auth_storage.dart';
import 'package:nomowear/core/utils/api_id_utils.dart';
import 'package:nomowear/core/utils/kids_size_utils.dart';
import 'package:nomowear/features/products/data/models/product.dart';
import 'package:nomowear/features/products/data/models/product_variant.dart';
import 'package:nomowear/features/products/data/product_catalog.dart';
import 'package:nomowear/features/products/data/product_cache.dart';
import 'package:nomowear/features/products/data/product_mapper.dart';
import 'package:nomowear/features/products/data/product_repository.dart';
import 'package:nomowear/features/wardrobe/data/filters_repository.dart';
import 'package:nomowear/features/wardrobe/presentation/screens/product_details_screen.dart';
import 'package:nomowear/features/cart/presentation/bloc/cart_bloc.dart';
import 'package:nomowear/features/cart/presentation/utils/cart_stock.dart';
import 'package:nomowear/features/cart/presentation/utils/cart_limits.dart';
import 'package:nomowear/features/wardrobe/presentation/widgets/variant_selection_sheet.dart';
import 'package:nomowear/features/cart/presentation/widgets/wardrobe_limit_dialog.dart';
import 'package:nomowear/features/favorites/presentation/bloc/favorites_bloc.dart';
import 'package:nomowear/features/checkout/data/wardrobe_booking_session.dart';
import 'package:nomowear/features/checkout/data/checkout_session.dart';
import 'package:nomowear/features/profile/domain/saved_address.dart';

/// Normalizes age/size labels so API values like `0-6M` match catalog
/// values like `0-6 Months`.
String _normalizeAgeLabel(String value) {
  return value
      .trim()
      .toLowerCase()
      .replaceAll('months', 'm')
      .replaceAll('month', 'm')
      .replaceAll('years', 'y')
      .replaceAll('year', 'y')
      .replaceAll(RegExp(r'\s+'), '');
}

/// Parses labels like `0-6M`, `2-4Y`, `2-3 Y`, `1-3 years` into inclusive month bounds.
(int minMonths, int maxMonths)? _ageLabelToMonths(String value) {
  final r = kidsSizeToMonthRange(value);
  if (r.$1 != 999) return r;

  final normalized = _normalizeAgeLabel(value);
  final match = RegExp(r'^(\d+)-(\d+)([my])$').firstMatch(normalized);
  if (match == null) return null;

  var min = int.tryParse(match.group(1) ?? '');
  var max = int.tryParse(match.group(2) ?? '');
  if (min == null || max == null) return null;
  if (min > max) {
    final swap = min;
    min = max;
    max = swap;
  }

  final unit = match.group(3)!;
  if (unit == 'y') {
    min *= 12;
    max *= 12;
  }
  return (min, max);
}

bool _rangesOverlap((int, int) a, (int, int) b) =>
    a.$1 <= b.$2 && b.$1 <= a.$2;

/// Maps a product variant size onto the kids filter bucket keys from
/// `getFilters?action=kids` (`0-6M`, `6-24M`, `2-4Y`, `4-6Y`, `6-14Y`).
String? _kidsSizeToFilterBucket(String size) {
  final range = _ageLabelToMonths(size);
  if (range == null) return null;
  final mid = (range.$1 + range.$2) / 2.0;
  if (mid <= 6) return '0-6m';
  if (mid <= 24) return '6-24m';
  if (mid <= 48) return '2-4y';
  if (mid <= 72) return '4-6y';
  return '6-14y';
}

Set<String> _kidsAgeSources(WardrobeItem item) {
  final sources = <String>{
    ...item.ages,
    ...item.sizes,
  };
  for (final variant in item.variants) {
    for (final entry in variant.options.entries) {
      final key = entry.key.trim().toLowerCase();
      if (key != 'size' && key != 'age') continue;
      final value = entry.value.trim();
      if (value.isNotEmpty) sources.add(value);
    }
  }
  return sources;
}

bool _kidsItemMatchesAge(WardrobeItem item, String filterAge) {
  final wantNorm = _normalizeAgeLabel(filterAge);
  if (wantNorm.isEmpty) return false;

  final sources = _kidsAgeSources(item);
  if (sources.isEmpty) return false;

  final wantRange = _ageLabelToMonths(filterAge);

  for (final age in sources) {
    if (_normalizeAgeLabel(age) == wantNorm) return true;

    final bucket = _kidsSizeToFilterBucket(age);
    if (bucket != null && bucket == wantNorm) return true;

    final gotRange = _ageLabelToMonths(age);
    if (wantRange != null &&
        gotRange != null &&
        _rangesOverlap(wantRange, gotRange)) {
      return true;
    }
  }
  return false;
}

bool _adultItemMatchesSize(WardrobeItem item, String filterSize) {
  final want = filterSize.trim().toUpperCase();
  if (want.isEmpty) return true;

  for (final size in item.sizes) {
    if (size.trim().toUpperCase() == want) return true;
  }
  for (final variant in item.variants) {
    final size = variant.options['Size'] ?? variant.options['size'];
    if (size != null && size.trim().toUpperCase() == want) return true;
  }
  return false;
}

String? _wantedGenderTag({
  required String filterGender,
  required bool isKids,
}) {
  final gender = filterGender.trim().toLowerCase();
  if (gender.isEmpty) return null;
  if (isKids) {
    if (gender.startsWith('b')) return 'boy';
    if (gender.startsWith('g')) return 'girl';
    return gender;
  }
  if (gender.startsWith('w')) return 'women';
  if (gender.startsWith('m')) return 'men';
  return gender;
}

/// Infers kids gender from listing title when API attributes omit it.
String? _inferKidsGenderTag(WardrobeItem item) {
  if (item.genderTag == 'boy' || item.genderTag == 'girl') {
    return item.genderTag;
  }
  final title = item.title.toLowerCase();
  if (RegExp(r'\bboy(s)?\b').hasMatch(title)) return 'boy';
  if (RegExp(r'\bgirl(s)?\b').hasMatch(title)) return 'girl';
  return item.genderTag;
}


// Data model
class WardrobeItem {
  final String? productId;
  final String title;
  final String description;
  final String imageUrl;
  final String? price;
  final String? costPrice;
  final String? actualPrice;
  final List<String> imageUrls;
  final List<String> colorVariantImages;
  final List<String> colorNames;
  final List<String> sizes;
  final List<String> ages;
  final List<String> productDetails;
  final List<ProductVariant> variants;
  final String stockStatus;
  final String? category;
  final String? itemType;
  /// `'men'` | `'women'` | `'boy'` | `'girl'` — when null, item appears for both gender filters.
  final String? genderTag;

  const WardrobeItem({
    this.productId,
    required this.title,
    required this.description,
    required this.imageUrl,
    this.price,
    this.costPrice,
    this.actualPrice,
    this.imageUrls = const [],
    this.colorVariantImages = const [],
    this.colorNames = const [],
    this.sizes = const [],
    this.ages = const [],
    this.productDetails = const [],
    this.variants = const [],
    this.stockStatus = 'IN_STOCK',
    this.category,
    this.itemType,
    this.genderTag,
  });

  String get favoriteId =>
      productId ?? '${title}_${imageUrl.hashCode}';
}


// Screen
class WardrobeScreen extends StatefulWidget {
  final String category;

  const WardrobeScreen({Key? key, required this.category}) : super(key: key);

  @override
  State<WardrobeScreen> createState() => _WardrobeScreenState();
}

class _WardrobeScreenState extends State<WardrobeScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ProductRepository _productRepository = ProductRepository();
  final AuthStorage _authStorage = AuthStorage();

  int? _selectedIndex;
  String _searchQuery = '';
  String? _filterSize;
  String? _filterGender;
  List<WardrobeItem> _apiItems = [];
  bool _isLoading = true;
  bool _loadFailed = false;
  bool _isLoadingMore = false;
  bool _hasNextPage = false;
  int _currentPage = 1;
  static const int _pageSize = 20;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadProducts();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<FavoritesBloc>().add(LoadWishlistEvent());
    });
  }

  @override
  void didUpdateWidget(covariant WardrobeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.category != widget.category) {
      _resetListingState();
      _loadProducts(forceRefresh: true);
    }
  }

  void _resetListingState() {
    _apiItems = [];
    _currentPage = 1;
    _hasNextPage = false;
    _isLoadingMore = false;
    _searchQuery = '';
    _filterSize = null;
    _filterGender = null;
    _selectedIndex = null;
    _searchController.clear();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_isLoading || _isLoadingMore || !_hasNextPage) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 240) {
      _loadMoreProducts();
    }
  }

  Future<void> _loadProducts({
    bool forceRefresh = false,
    String? action,
    String? age,
    String? gender,
    bool loadMore = false,
  }) async {
    if (loadMore) {
      if (_isLoadingMore || !_hasNextPage || _isLoading) return;
      if (mounted) setState(() => _isLoadingMore = true);
    } else {
      if (mounted) {
        setState(() {
          _isLoading = true;
          _currentPage = 1;
          _hasNextPage = false;
        });
      }
    }

    final token = await _authStorage.getAuthToken();
    if (token == null || token.isEmpty) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isLoadingMore = false;
        });
      }
      return;
    }

    final pageToLoad = loadMore ? _currentPage + 1 : 1;

    try {
      final mappedTab = ProductCatalog.apiTabForCategory(widget.category);
      final selectedName = widget.category.trim();
      final tab = (mappedTab != null && mappedTab.isNotEmpty)
          ? mappedTab
          : (selectedName.isEmpty ? null : selectedName);
          
      final isNearby = (tab?.toLowerCase().contains('kids') == true) || 
                       (tab?.toLowerCase().contains('essentials') == true) || 
                       (action?.toLowerCase() == 'kids') ||
                       (WardrobeBookingSession.instance.kitSelected);

      final isKidsOrEssentials = (tab?.toLowerCase().contains('kids') == true) || 
                                 (tab?.toLowerCase().contains('essentials') == true) || 
                                 (action?.toLowerCase() == 'kids');
                                 
      if (!loadMore && !isKidsOrEssentials) {
        if (kDebugMode) {
          debugPrint('SAVED_ADDRESS_DEBUG');
          debugPrint('Comfort Wear screen opened');
          debugPrint('Fetching saved addresses...');
          debugPrint('Saved address API started');
        }
        await loadSavedAddressesFromProfile();
        if (kDebugMode) {
          debugPrint('SAVED_ADDRESS_DEBUG');
          debugPrint('Saved address API status = Success');
          debugPrint('savedAddressCount = ${userSavedAddresses.length}');
          debugPrint('selectedAddressId = ${CheckoutSession.instance.addressId}');
        }
      }

      final products = await _productRepository.getProducts(
        forceRefresh: forceRefresh || loadMore,
        useNearbyLocation: isNearby,
        action: action,
        age: age,
        gender: gender,
        tab: tab,
        page: pageToLoad,
        limit: _pageSize,
      );
      _applyListing(
        products,
        append: loadMore,
        apiCount: products.length,
        page: pageToLoad,
      );
      _currentPage = pageToLoad;
      _hasNextPage = _productRepository.lastHasNextPage;
      _loadFailed = false;
    } on ApiException catch (e) {
      if (!loadMore) {
        _apiItems = [];
        _loadFailed = true;
      }
      if (e.message.contains('Location is missing') && mounted) {
        final mappedTab = ProductCatalog.apiTabForCategory(widget.category);
        final tab = (mappedTab != null && mappedTab.isNotEmpty)
            ? mappedTab
            : (widget.category.trim().isEmpty ? null : widget.category.trim());
            
        final isKidsOrEssentials = (tab?.toLowerCase().contains('kids') == true) || 
                                   (tab?.toLowerCase().contains('essentials') == true) || 
                                   (action?.toLowerCase() == 'kids');
        
        if (isKidsOrEssentials) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.message)),
          );
        } else {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: const Color(0xFF1A1D21),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Text(
                'Address Required',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColours.primary,
                ),
              ),
              content: const Text(
                'Please select a saved address to view these products.',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white70,
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: Colors.white54, fontWeight: FontWeight.w600),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.pushNamed(context, AppRoutes.myAddressesScreen);
                  },
                  child: Text(
                    'Select Address',
                    style: TextStyle(color: AppColours.primary, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          );
        }
      }
    } catch (_) {
      if (!loadMore) {
        _apiItems = [];
        _loadFailed = true;
      }
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
        _isLoadingMore = false;
      });
    }
  }

  Future<void> _loadMoreProducts() async {
    await _loadProducts(
      forceRefresh: true,
      loadMore: true,
      action: _isKidsCategory ? 'kids' : null,
      age: _filterSize,
      gender: _filterGender,
    );
  }

  /// Kids listing API: always hits network with `action=kids` (+ age/gender).
  Future<void> _loadKidsListing({
    String? age,
    String? gender,
  }) async {
    await _loadProducts(
      forceRefresh: true,
      action: 'kids',
      age: age,
      gender: gender,
    );
  }

  void _applyListing(
    List<Product> products, {
    required bool append,
    required int apiCount,
    required int page,
  }) {
    for (final p in products) {
      ProductCache.instance.upsert(p);
    }
    final listing = ProductCatalog.wardrobeListingItems(
      products,
      widget.category,
    );
    final mapped = listing
        .map(
          (product) => ProductMapper.toWardrobeItem(
            product,
            category: widget.category,
          ),
        )
        .toList(growable: false);

    if (!append) {
      _apiItems = mapped;
    } else {
      final seen = <String>{
        for (final item in _apiItems)
          if (item.productId != null && item.productId!.isNotEmpty)
            item.productId!,
      };
      final merged = List<WardrobeItem>.from(_apiItems);
      for (final item in mapped) {
        final id = item.productId?.trim() ?? '';
        if (id.isEmpty) {
          merged.add(item);
          continue;
        }
        if (seen.add(id)) {
          merged.add(item);
        } else if (kDebugMode) {
          debugPrint(
            '[PRODUCT_LIST_FILTER] category=${widget.category} '
            'productId=$id productName=${item.title} reason=duplicate_page_item',
          );
        }
      }
      _apiItems = merged;
    }

    if (kDebugMode) {
      debugPrint('[PRODUCT_LIST_COUNTS]');
      debugPrint('Category: ${widget.category}');
      debugPrint('API product count: $apiCount');
      debugPrint('Parsed product count: $apiCount');
      debugPrint('Filtered product count: ${listing.length}');
      debugPrint('Displayed product count: ${_apiItems.length}');
      debugPrint('Current page: $page');
      debugPrint('Has next page: ${_productRepository.lastHasNextPage}');
      debugPrint('totalItems=${_productRepository.lastTotalItems}');
      debugPrint('totalPages=${_productRepository.lastTotalPages}');
    }
  }

  bool get _isKidsCategory {
    final category = widget.category.trim().toLowerCase();
    return category == 'kids wardrobe' || category.contains('kids');
  }

  List<WardrobeItem> get _items => _apiItems;

  ProductVariant? _defaultVariantForItem(WardrobeItem item) {
    if (item.variants.isEmpty) return null;
    return item.variants.first;
  }

  String _cartItemIdFor(WardrobeItem item, ProductVariant? variant) {
    if (variant != null &&
        isApiUuid(item.productId) &&
        isApiUuid(variant.id)) {
      return '${item.productId}_${variant.id}';
    }
    return item.productId ?? item.favoriteId;
  }

  String _selectedSizeForItem(WardrobeItem item, ProductVariant? variant) {
    final variantSize = variant?.options['Size']?.trim();
    if (variantSize != null && variantSize.isNotEmpty) return variantSize;
    if (item.sizes.isNotEmpty) return item.sizes.first;
    return 'M';
  }

  bool _isOutOfStockStatus(String status) {
    final normalized = status.trim().toUpperCase();
    if (normalized.isEmpty) return false;
    return normalized == 'OUT_OF_STOCK' ||
        normalized == 'OUT OF STOCK' ||
        normalized == 'OOS';
  }

  bool _isVariantAvailableForListing(WardrobeItem item, ProductVariant? variant) {
    if (item.variants.isNotEmpty) {
      // Show product when ANY variant is sellable. Do not require stockOnHand>0
      // when backend marks the variant IN_STOCK.
      final availableVariants = item.variants.where(_isVariantSellable).length;
      final hasAvailableVariant = availableVariants > 0;
      final isProductOutOfStock = !hasAvailableVariant;
      
      if (kDebugMode) {
        debugPrint('[PRODUCT_LIST_STOCK]');
        debugPrint('productId=${item.productId}');
        debugPrint('totalVariants=${item.variants.length}');
        debugPrint('availableVariants=$availableVariants');
        debugPrint('unavailableVariants=${item.variants.length - availableVariants}');
        debugPrint('isProductOutOfStock=$isProductOutOfStock');
      }
      
      return hasAvailableVariant;
    }
    if (_isOutOfStockStatus(item.stockStatus)) {
      return false;
    }
    return true;
  }

  bool _isVariantSellable(ProductVariant variant) {
    if (!_isOutOfStockStatus(variant.stockStatus)) return true;
    return variant.stockOnHand > 0;
  }


  List<WardrobeItem> get _filtered {
    Iterable<WardrobeItem> list = _items;
    final q = _searchQuery.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where(
        (e) =>
            e.title.toLowerCase().contains(q) ||
            e.description.toLowerCase().contains(q),
      );
    }
    if (_filterSize != null && _filterSize!.trim().isNotEmpty) {
      if (_isKidsCategory) {
        list = list.where(
          (e) => _kidsItemMatchesAge(e, _filterSize!),
        );
      } else {
        list = list.where(
          (e) => _adultItemMatchesSize(e, _filterSize!),
        );
      }
    }
    if (_filterGender != null && _filterGender!.trim().isNotEmpty) {
      final want = _wantedGenderTag(
        filterGender: _filterGender!,
        isKids: _isKidsCategory,
      );
      if (want != null) {
        if (_isKidsCategory) {
          list = list.where((e) => _inferKidsGenderTag(e) == want);
        } else {
          // Adults path unchanged.
          list = list.where((e) {
            if (e.genderTag == want) return true;
            if (e.genderTag == null) return true;
            return false;
          });
        }
      }
    }
    return list.toList();
  }

  Future<void> _openFilterSheet() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final result = await showModalBottomSheet<_WardrobeFilterResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => WardrobeFilterSheet(
        isKidsMode: _isKidsCategory,
        initialSize: _filterSize,
        initialGender: _filterGender,
      ),
    );
    if (!mounted || result == null) return;

    final size = result.size?.trim();
    final gender = result.gender?.trim();
    final nextSize = (size == null || size.isEmpty) ? null : size;
    final nextGender = (gender == null || gender.isEmpty) ? null : gender;

    setState(() {
      _filterSize = nextSize;
      _filterGender = nextGender;
    });

    if (result.isKidsMode || _isKidsCategory) {
      // Kids: GET /mobile/v1/products?action=kids&age=...&gender=...
      await _loadKidsListing(
        age: nextSize,
        gender: nextGender,
      );
    } else {
      // Adults: keep existing behaviour (reload + local size/gender filter).
      await _loadProducts(forceRefresh: true);
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isKidsOrEssentials = isKidsCategory(widget.category) ||
        isEssentialCategory(widget.category) ||
        widget.category.toLowerCase().contains('kid') ||
        widget.category.toLowerCase().contains('essential');

    return BlocListener<CartBloc, CartState>(
      listenWhen: (prev, curr) =>
          curr.errorMessage != null &&
          curr.errorMessage != prev.errorMessage &&
          isSubscriptionQuotaError(curr.errorMessage),
      listener: (context, state) {
        _showSubscriptionQuotaDialog(context, state.errorMessage!);
      },
      child: PopScope(
        canPop: isKidsOrEssentials,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          Navigator.popUntil(context, ModalRoute.withName(AppRoutes.homeScreen));
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
            SizedBox(height: 26,),
            _buildSearchBar(),

            Expanded(
              child: RefreshIndicator(
                color: AppColours.primary,
                onRefresh: () {
                  if (_isKidsCategory) {
                    return _loadKidsListing(
                      age: _filterSize,
                      gender: _filterGender,
                    );
                  }
                  return _loadProducts(forceRefresh: true);
                },
                child: _isLoading
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          SizedBox(
                            height: MediaQuery.sizeOf(context).height * 0.5,
                            child: Center(
                              child: CircularProgressIndicator(
                                color: AppColours.primary,
                              ),
                            ),
                          ),
                        ],
                      )
                    : _filtered.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              SizedBox(
                                height:
                                    MediaQuery.sizeOf(context).height * 0.5,
                                child: _buildEmptyState(),
                              ),
                            ],
                          )
                        : GridView.builder(
                            controller: _scrollController,
                            physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(16.w, 4.h, 16.w, 24.h),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 16.h,
                        crossAxisSpacing: 12.w,
                        childAspectRatio: 0.62,
                      ),
                      itemCount: _filtered.length,
                      itemBuilder: (context, index) {
                        final item = _filtered[index];
                        final isSelected = _selectedIndex == index;

                        return BlocBuilder<FavoritesBloc, FavoritesState>(
                          builder: (context, favoritesState) {
                            final isWishlisted =
                                favoritesState.isFavorite(item.favoriteId);
                            return _buildProductCard(
                              item: item,
                              index: index,
                              isSelected: isSelected,
                              isWishlisted: isWishlisted,
                            );
                          },
                        );
                      },
                    ),
              ),
            ),
          ],
        ),
      ),
    ),
    ),
    );
  }

  String get _screenTitle {
    if (widget.category == 'Essentials Wardrobe') {
      return 'Essentials';
    }

    if (widget.category == 'Kids Wardrobe') {
      return 'Kids Wear';
    }

    final cached = ProductCache.instance.products;
    if (cached != null) {
      final kit = ProductCatalog.findWardrobeKit(cached, widget.category);
      final categoryName = kit?.categoryName;
      if (categoryName != null && categoryName.isNotEmpty) {
        return categoryName.replaceAll(' Wardrobe', ' Wear');
      }
    }

    return widget.category.replaceAll(' Wardrobe', ' Wear');
  }

  Widget _buildAppBar() {
    final isKidsOrEssentials = isKidsCategory(widget.category) ||
        isEssentialCategory(widget.category) ||
        widget.category.toLowerCase().contains('kid') ||
        widget.category.toLowerCase().contains('essential');

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
      child: Row(
        children: [
          GestureDetector(
            onTap: () {
              if (isKidsOrEssentials) {
                Navigator.pop(context);
              } else {
                Navigator.popUntil(context, ModalRoute.withName(AppRoutes.homeScreen));
              }
            },
            child: Icon(
              Icons.arrow_back,
              color: AppColours.primary,
              size: 28,
            ),
          ),
          Expanded(
            child: Text(
              _screenTitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColours.primary,
                fontSize: 18.fSize,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ),
          GestureDetector(
            onTap: () => Navigator.pushNamed(context, AppRoutes.favoritesScreen),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColours.primary.withOpacity(0.3)),
              ),
              child: Icon(Icons.favorite_border,
                  color: AppColours.primary, size: 22),
            ),
          ),
          SizedBox(width: 8.w),
          BlocBuilder<CartBloc, CartState>(
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
                        border: Border.all(
                            color: AppColours.primary.withOpacity(0.3)),
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
                                fontWeight: FontWeight.bold),
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

  Widget _buildSearchBar() {
    return Padding(
      padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 12.h),
      child: Container(
        height: 48.h,
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColours.primary),
        ),
        child: Row(
          children: [
            SizedBox(width: 14.w),
            Icon(Icons.search, color: AppColours.primary.withOpacity(0.6),
                size: 20),
            SizedBox(width: 10.w),
            Expanded(
              child: TextField(
                controller: _searchController,
                style: TextStyle(color: Colors.white, fontSize: 14.fSize),
                decoration: InputDecoration(
                  hintText: 'Search garments',
                  hintStyle: TextStyle(
                      color: Colors.white38, fontSize: 14.fSize),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                onChanged: (v) => setState(() => _searchQuery = v),
              ),
            ),
            IconButton(
              padding: EdgeInsets.zero,
              constraints: BoxConstraints.tightFor(width: 44.w, height: 44.h),
              icon: Icon(
                Icons.tune,
                color: AppColours.primary.withOpacity(0.85),
                size: 22,
              ),
              tooltip: 'Filter',
              onPressed: _openFilterSheet,
            ),
          ],
        ),
      ),
    );
  }

  bool get _shouldShowPrice =>
      ProductCatalog.shouldShowPrice(category: widget.category);

  Widget _buildPriceRow(ResolvedPrice prices) {
    if (!_shouldShowPrice) return const SizedBox.shrink();
    if (prices.hasDiscount) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            prices.discountedPrice,
            style: TextStyle(
              color: AppColours.primary,
              fontSize: 14.fSize,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(width: 6.w),
          Text(
            prices.actualPrice,
            style: TextStyle(
              color: Colors.white54,
              fontSize: 12.fSize,
              decoration: TextDecoration.lineThrough,
              decorationColor: Colors.white54,
            ),
          ),
        ],
      );
    } else {
      return Text(
        prices.discountedPrice,
        style: TextStyle(
          color: AppColours.primary,
          fontSize: 14.fSize,
          fontWeight: FontWeight.bold,
        ),
      );
    }
  }

  Widget _buildProductCard({
    required WardrobeItem item,
    required int index,
    required bool isSelected,
    required bool isWishlisted,
  }) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ProductDetailsScreen(product: item),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0F1012),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColours.primary),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: ProductImage(
                          imageUrl: item.imageUrl,
                          width: double.infinity,
                          height: double.infinity,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () {
                          final favoriteId = item.favoriteId;
                          final wasWishlisted = context
                              .read<FavoritesBloc>()
                              .state
                              .isFavorite(favoriteId);
                          final favItem = FavoriteItem(
                            id: favoriteId,
                            title: item.title,
                            subtitle: item.description,
                            imageUrl: item.imageUrl,
                          );
                          context
                              .read<FavoritesBloc>()
                              .add(ToggleFavoriteEvent(favItem));

                          ScaffoldMessenger.of(context).clearSnackBars();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                wasWishlisted
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
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: isWishlisted
                                ? AppColours.primary
                                : Colors.black.withValues(alpha: 0.55),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColours.primary,
                              width: isWishlisted ? 2 : 1,
                            ),
                            boxShadow: isWishlisted
                                ? [
                                    BoxShadow(
                                      color: AppColours.primary
                                          .withValues(alpha: 0.45),
                                      blurRadius: 8,
                                      spreadRadius: 1,
                                    ),
                                  ]
                                : null,
                          ),
                          child: Icon(
                            isWishlisted ? Icons.favorite : Icons.favorite_border,
                            color: isWishlisted ? Colors.black : AppColours.primary,
                            size: 18,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 8.h),
            Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColours.primary,
                fontSize: 14.fSize,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 2.h),
            Text(
              item.description,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white60,
                fontSize: 11.fSize,
              ),
            ),
            if (_shouldShowPrice) ...[
              SizedBox(height: 4.h),
              _buildPriceRow(ProductMapper.resolvePrice(item, variant: _defaultVariantForItem(item))),
            ],
            SizedBox(height: 8.h),
            BlocBuilder<CartBloc, CartState>(
              buildWhen: (previous, current) {
                final variant = _defaultVariantForItem(item);
                final productId = item.productId ?? item.favoriteId;
                final itemType =
                    CartLimits.cartItemTypeForListing(itemType: item.itemType);
                final variantId =
                    isApiUuid(variant?.id) ? variant!.id : null;
                return previous.quantityForListingCard(
                          productId: productId,
                          variantId: variantId,
                          itemType: itemType,
                        ) !=
                        current.quantityForListingCard(
                          productId: productId,
                          variantId: variantId,
                          itemType: itemType,
                        ) ||
                    previous.isProductPending(
                          productId: productId,
                          variantId: variantId,
                          itemType: itemType,
                        ) !=
                        current.isProductPending(
                          productId: productId,
                          variantId: variantId,
                          itemType: itemType,
                        ) ||
                    previous.isVariantOutOfStock(
                          productId: productId,
                          variantId: variantId,
                          itemType: itemType,
                        ) !=
                        current.isVariantOutOfStock(
                          productId: productId,
                          variantId: variantId,
                          itemType: itemType,
                        );
              },
              builder: (context, cartState) {
                final variant = _defaultVariantForItem(item);
                final productId = item.productId ?? item.favoriteId;
                final fallbackItemId = _cartItemIdFor(item, variant);
                final itemType =
                    CartLimits.cartItemTypeForListing(itemType: item.itemType);
                final variantId =
                    isApiUuid(variant?.id) ? variant!.id : null;
                final existingLine = cartState.lineForListingCard(
                  productId: productId,
                  variantId: variantId,
                  itemType: itemType,
                );
                final itemId = existingLine?.id ?? fallbackItemId;
                final qty = cartState.quantityForListingCard(
                  productId: productId,
                  variantId: variantId,
                  itemType: itemType,
                );
                final pending = cartState.isProductPending(
                  productId: productId,
                  variantId: variantId,
                  itemType: itemType,
                );
                final outOfStockFromCart = cartState.isVariantOutOfStock(
                  productId: productId,
                  variantId: variantId,
                  itemType: itemType,
                );
                final outOfStockFromProduct =
                    !_isVariantAvailableForListing(item, variant);
                final outOfStock = outOfStockFromProduct || outOfStockFromCart;
                final buttonState = qty > 0
                    ? 'QTY'
                    : pending
                        ? 'LOADING'
                        : outOfStock
                            ? 'OUT_OF_STOCK'
                            : 'ADD_TO_CART';
                if (kDebugMode) {
                  debugPrint('[STOCK_DEBUG]');
                  debugPrint('productId=$productId');
                  debugPrint('variantId=${variantId ?? '-'}');
                  debugPrint('size=${_selectedSizeForItem(item, variant)}');
                  debugPrint('stockQuantity=${variant?.stockOnHand}');
                  debugPrint(
                    'isAvailable=${_isVariantAvailableForListing(item, variant)}',
                  );
                  debugPrint('buttonState=$buttonState');
                }

                if (outOfStock && qty <= 0) {
                  return SizedBox(
                    width: double.maxFinite,
                    height: 32.h,
                    child: ElevatedButton(
                      onPressed: null,
                      style: ElevatedButton.styleFrom(
                        elevation: 0,
                        disabledBackgroundColor: const Color(0xFF2A2A2A),
                        disabledForegroundColor: Colors.white38,
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: Colors.white.withOpacity(0.12),
                            width: 1,
                          ),
                        ),
                      ),
                      child: Text(
                        'Out of Stock',
                        style: TextStyle(
                          color: Colors.white38,
                          fontSize: 12.fSize,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  );
                }

                if (qty > 0) {
                  return Container(
                    width: double.maxFinite,
                    height: 32.h,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE6C27A), width: 1),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            borderRadius: const BorderRadius.horizontal(left: Radius.circular(12)),
                            onTap: () {
                              context.read<CartBloc>().add(
                                    AdjustCartItemQuantityEvent(
                                      itemId,
                                      delta: -1,
                                    ),
                                  );
                            },
                            child: Icon(Icons.remove, color: AppColours.primary, size: 18),
                          ),
                        ),
                        Container(width: 1, color: const Color(0xFFE6C27A).withOpacity(0.35)),
                        Expanded(
                          flex: 2,
                          child: Center(
                            child: Text(
                              '$qty',
                              style: TextStyle(
                                color: AppColours.primary,
                                fontSize: 12.fSize,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        Container(width: 1, color: const Color(0xFFE6C27A).withOpacity(0.35)),
                        Expanded(
                          child: InkWell(
                            borderRadius: const BorderRadius.horizontal(right: Radius.circular(12)),
                            onTap: () async {
                              if (existingLine != null) {
                                final added = tryAddToCart(context, existingLine);
                                if (!added) return;
                                return;
                              }

                              final itemType =
                                  CartLimits.cartItemTypeForListing(
                                      itemType: item.itemType);
                              
                              ProductVariant? selectedVariant = variant;
                              String? finalSize = existingLine?.selectedSize ?? _selectedSizeForItem(item, variant);
                              
                              var product = ProductCache.instance.findById(item.productId ?? '');
                              if (product == null && isApiUuid(item.productId)) {
                                if (item.variants.isNotEmpty) {
                                  product = Product(
                                    id: item.productId!,
                                    productName: item.title,
                                    productSlug: item.productId!,
                                    productClass: 'single_item',
                                    hasVariants: item.variants.isNotEmpty,
                                    categoryName: item.category ?? widget.category,
                                    primaryImageUrl: item.imageUrl,
                                    imageUrls: item.imageUrls,
                                    variants: item.variants,
                                    actualPrice: item.actualPrice ?? item.price ?? '0',
                                    costPrice: item.costPrice,
                                    itemType: item.itemType ?? '',
                                    stockStatus: item.stockStatus,
                                  );
                                  ProductCache.instance.upsert(product);
                                } else {
                                  try {
                                    product = await _productRepository.getProductById(item.productId!);
                                  } catch (_) {}
                                }
                              }

                              if (product != null && product.variants.isNotEmpty) {
                                final result = await VariantSelectionSheet.show(context, product);
                                if (result == null) return;
                                selectedVariant = result;
                                finalSize = ProductMapper.optionValue(result, 'Size') ?? finalSize;
                              }

                              final isKids = itemType == 'kids' ||
                                  isKidsCategory(widget.category) ||
                                  isKidsCategory(item.category);
                              final isEssential = isKids ||
                                  itemType == 'essentials' ||
                                  isEssentialCategory(widget.category) ||
                                  isEssentialCategory(item.category);
                              final effectiveItemType = isKids
                                  ? 'kids'
                                  : (isEssential ? 'essentials' : itemType);

                              final prices = ProductMapper.resolvePrice(item, variant: selectedVariant);
                              final cartItem = CartItem(
                                productId: productId,
                                variantId: isApiUuid(selectedVariant?.id) ? selectedVariant!.id : null,
                                title: item.title,
                                imageUrl: item.imageUrl,
                                price: prices.discountedPrice,
                                selectedSize:
                                    isKids ? formatKidsSize(finalSize) : finalSize,
                                quantity: 1,
                                isEssential: isEssential,
                                isKids: isKids,
                                isSubscriptionGarment: !isEssential && effectiveItemType == 'subscription',
                                itemType: effectiveItemType,
                                category: widget.category,
                              );
                              final added = tryAddToCart(context, cartItem);
                              if (!added) return;
                            },
                            child: Icon(Icons.add, color: AppColours.primary, size: 18),
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return SizedBox(
                  width: double.maxFinite,
                  height: 32.h,
                  child: ElevatedButton(
                    onPressed: pending
                        ? null
                        : () async {
                      if (!isApiUuid(item.productId)) {
                        ScaffoldMessenger.of(context).clearSnackBars();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'This product cannot be ordered. Please refresh the catalog.',
                            ),
                          ),
                        );
                        return;
                      }

                      final itemType =
                          CartLimits.cartItemTypeForListing(itemType: item.itemType);
                          
                      ProductVariant? selectedVariant = variant;
                      String? finalSize = _selectedSizeForItem(item, variant);

                      var product = ProductCache.instance.findById(item.productId ?? '');
                      if (product == null && isApiUuid(item.productId)) {
                        if (item.variants.isNotEmpty) {
                          product = Product(
                            id: item.productId!,
                            productName: item.title,
                            productSlug: item.productId!,
                            productClass: 'single_item',
                            hasVariants: item.variants.isNotEmpty,
                            categoryName: item.category ?? widget.category,
                            primaryImageUrl: item.imageUrl,
                            imageUrls: item.imageUrls,
                            variants: item.variants,
                            actualPrice: item.actualPrice ?? item.price ?? '0',
                            costPrice: item.costPrice,
                            itemType: item.itemType ?? '',
                            stockStatus: item.stockStatus,
                          );
                          ProductCache.instance.upsert(product);
                        } else {
                          try {
                            product = await _productRepository.getProductById(item.productId!);
                          } catch (_) {}
                        }
                      }

                      if (product != null && product.variants.isNotEmpty) {
                        final result = await VariantSelectionSheet.show(context, product);
                        if (result == null) return; // User closed sheet
                        selectedVariant = result;
                        finalSize = ProductMapper.optionValue(result, 'Size') ?? finalSize;
                      }

                      final isKids = itemType == 'kids' ||
                          isKidsCategory(widget.category) ||
                          isKidsCategory(item.category);
                      final isEssential = isKids ||
                          itemType == 'essentials' ||
                          isEssentialCategory(widget.category) ||
                          isEssentialCategory(item.category);
                      final effectiveItemType = isKids
                          ? 'kids'
                          : (isEssential ? 'essentials' : itemType);

                      final prices = ProductMapper.resolvePrice(item, variant: selectedVariant);
                      final cartItem = CartItem(
                        productId: productId,
                        variantId: isApiUuid(selectedVariant?.id) ? selectedVariant!.id : null,
                        title: item.title,
                        imageUrl: item.imageUrl,
                        price: prices.discountedPrice,
                        selectedSize:
                            isKids ? formatKidsSize(finalSize) : finalSize,
                        isEssential: isEssential,
                        isKids: isKids,
                        isSubscriptionGarment: !isEssential && effectiveItemType == 'subscription',
                        itemType: effectiveItemType,
                        category: widget.category,
                      );

                      final added = tryAddToCart(context, cartItem);
                      if (!added) return;
                    },
                    style: ElevatedButton.styleFrom(
                      elevation: 0,
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      disabledBackgroundColor: Colors.transparent,
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(
                          color: Color(0xFFE6C27A),
                          width: 1,
                        ),
                      ),
                    ),
                    child: Ink(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        gradient: const LinearGradient(
                          colors: [
                            Color(0xFFE6C27A),
                            Color(0xFFB8934D),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: Container(
                        height: 48.h,
                        alignment: Alignment.center,
                        child: pending
                            ? SizedBox(
                                width: 16.fSize,
                                height: 16.fSize,
                                child: const CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.black,
                                ),
                              )
                            : Text(
                                "Add to cart",
                                style: TextStyle(
                                  color: Colors.black,
                                  fontSize: 12.fSize,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
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

  Widget _buildEmptyState() {
    final noCatalogProducts = _apiItems.isEmpty &&
        _searchQuery.trim().isEmpty &&
        _filterSize == null &&
        _filterGender == null;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _loadFailed ? Icons.cloud_off : Icons.search_off,
            color: AppColours.primary.withOpacity(0.4),
            size: 64,
          ),
          SizedBox(height: 16.h),
          Text(
            _loadFailed
                ? 'Unable to load products'
                : noCatalogProducts
                    ? 'No products available'
                    : 'No items found',
            style: TextStyle(color: Colors.white54, fontSize: 16.fSize),
          ),
          if (noCatalogProducts) ...[
            SizedBox(height: 8.h),
            Text(
              'Pull down to refresh',
              style: TextStyle(color: Colors.white38, fontSize: 12.fSize),
            ),
          ],
        ],
      ),
    );
  }
}

class _WardrobeFilterResult {
  const _WardrobeFilterResult({
    this.size,
    this.gender,
    this.isKidsMode = false,
  });

  final String? size;
  final String? gender;
  final bool isKidsMode;
}

class WardrobeFilterSheet extends StatefulWidget {
  const WardrobeFilterSheet({
    super.key,
    this.isKidsMode = false,
    this.initialSize,
    this.initialGender,
  });

  final bool isKidsMode;
  final String? initialSize;
  final String? initialGender;

  @override
  State<WardrobeFilterSheet> createState() => _WardrobeFilterSheetState();
}

class _WardrobeFilterSheetState extends State<WardrobeFilterSheet> {
  late String? _draftSize;
  late String? _draftGender;
  final FiltersRepository _filtersRepository = FiltersRepository();

  List<String> _sizeOptions = const [];
  List<String> _genderOptions = const [];
  bool _isLoading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _draftSize = widget.initialSize;
    _draftGender = widget.initialGender;
    _loadFilters();
  }

  Future<void> _loadFilters() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    try {
      final options = await _filtersRepository.getFilters(
        action: widget.isKidsMode ? 'kids' : 'adults',
      );
      if (!mounted) return;
      setState(() {
        _sizeOptions = options.age;
        _genderOptions = options.gender;
        _isLoading = false;
        // Drop selections that are no longer offered by the API.
        if (_draftSize != null && !_sizeOptions.contains(_draftSize)) {
          _draftSize = null;
        }
        if (_draftGender != null && !_genderOptions.contains(_draftGender)) {
          _draftGender = null;
        }
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _sizeOptions = const [];
        _genderOptions = const [];
        _isLoading = false;
        _loadError = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _sizeOptions = const [];
        _genderOptions = const [];
        _isLoading = false;
        _loadError = 'Unable to load filters. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF12151E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(20.w, 10.h, 20.w, 12.h + bottomInset),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36.w,
                  height: 4.h,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              SizedBox(height: 16.h),
              Text(
                'Filter',
                style: TextStyle(
                  color: AppColours.primary,
                  fontSize: 18.fSize,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 18.h),
              if (_isLoading)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 28.h),
                  child: Center(
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: AppColours.primary,
                      ),
                    ),
                  ),
                )
              else ...[
                Text(
                  'SIZE',
                  style: CustomTextStyles.montserratBold.copyWith(
                    color: AppColours.primary,
                    fontSize: 12.fSize,
                    letterSpacing: 1.2,
                  ),
                ),
                SizedBox(height: 10.h),
                if (_sizeOptions.isEmpty)
                  Text(
                    _loadError ?? 'No size filters available.',
                    style: CustomTextStyles.openSansRegular.copyWith(
                      color: Colors.white54,
                      fontSize: 12.fSize,
                    ),
                  )
                else
                  Wrap(
                    spacing: 8.w,
                    runSpacing: 8.h,
                    children: _sizeOptions.map(_buildDimensionChip).toList(),
                  ),
                SizedBox(height: 16.h),
                Divider(height: 1, color: Colors.white.withValues(alpha: 0.12)),
                SizedBox(height: 14.h),
                Text(
                  'Gender',
                  style: CustomTextStyles.montserratBold.copyWith(
                    color: AppColours.primary,
                    fontSize: 14.fSize,
                  ),
                ),
                SizedBox(height: 10.h),
                if (_genderOptions.isEmpty)
                  Text(
                    _loadError ?? 'No gender filters available.',
                    style: CustomTextStyles.openSansRegular.copyWith(
                      color: Colors.white54,
                      fontSize: 12.fSize,
                    ),
                  )
                else
                  for (var i = 0; i < _genderOptions.length; i++) ...[
                    if (i > 0) SizedBox(height: 6.h),
                    _buildGenderRow(_genderOptions[i]),
                  ],
              ],
              SizedBox(height: 18.h),
              Divider(height: 1, color: Colors.white.withValues(alpha: 0.12)),
              SizedBox(height: 16.h),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 48.h,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(
                            context,
                            _WardrobeFilterResult(
                              size: null,
                              gender: null,
                              isKidsMode: widget.isKidsMode,
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColours.secondary,
                          foregroundColor: Colors.black,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          'Clear Filters',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14.fSize,
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: SizedBox(
                      height: 48.h,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(
                            context,
                            _WardrobeFilterResult(
                              size: _draftSize,
                              gender: _draftGender,
                              isKidsMode: widget.isKidsMode,
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColours.primary,
                          foregroundColor: Colors.black,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          'Apply Filters',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14.fSize,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDimensionChip(String value) {
    final selected = _draftSize == value;
    return GestureDetector(
      onTap: () =>
          setState(() => _draftSize = _draftSize == value ? null : value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
        decoration: BoxDecoration(
          color: selected ? AppColours.secondary : const Color(0xFF1A1C23),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColours.primary, width: 1),
        ),
        child: Text(
          value,
          style: TextStyle(
            color: selected ? Colors.black : AppColours.primary,
            fontWeight: FontWeight.w600,
            fontSize: 13.fSize,
          ),
        ),
      ),
    );
  }

  Widget _buildGenderRow(String label) {
    final selected = _draftGender == label;
    return InkWell(
      onTap: () => setState(() {
        _draftGender = selected ? null : label;
      }),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 6.h),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_off,
              color: AppColours.primary,
              size: 22,
            ),
            SizedBox(width: 10.w),
            Text(
              label,
              style: TextStyle(
                color: AppColours.primary,
                fontSize: 14.fSize,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
