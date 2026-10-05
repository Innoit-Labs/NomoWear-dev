import 'package:dotted_border/dotted_border.dart';
import 'package:flutter/gestures.dart';
import 'package:nomowear/core/app_export.dart';
import 'package:nomowear/core/network/api_exception.dart';
import 'package:nomowear/features/cart/presentation/bloc/cart_bloc.dart';
import 'package:nomowear/features/cart/presentation/utils/cart_limits.dart';
import 'package:nomowear/features/cart/presentation/widgets/qty_picker_sheet.dart';
import 'package:nomowear/features/checkout/data/checkout_session.dart';
import 'package:nomowear/features/checkout/presentation/utils/checkout_initiate_request.dart';
import 'package:nomowear/features/checkout/presentation/utils/checkout_pricing.dart';
import 'package:nomowear/features/profile/presentation/utils/profile_order_guard.dart';
import 'package:nomowear/features/home/presentation/bloc/home_bloc.dart';
import 'package:nomowear/features/orders/data/order_repository.dart';
import 'package:nomowear/features/orders/presentation/widgets/no_return_blocked_dialog.dart';
import 'package:nomowear/features/profile/data/profile_cache.dart';
import 'package:nomowear/features/products/data/product_cache.dart';
import 'package:nomowear/features/products/data/models/product_variant.dart';
import 'package:nomowear/features/products/data/product_mapper.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:nomowear/features/wardrobe/presentation/screens/product_details_screen.dart';
import 'package:nomowear/features/wardrobe/presentation/widgets/variant_selection_sheet.dart';
import 'package:nomowear/features/cart/presentation/widgets/cart_quantity_control.dart';
import 'package:nomowear/features/wardrobe/presentation/screens/wardrobe_screen.dart';
import 'package:nomowear/features/cart/presentation/widgets/reusable_product_cart_item.dart';

class CartScreen extends StatefulWidget {
  const CartScreen({Key? key, this.isActive = true}) : super(key: key);

  /// Home tab passes the visible index. Named routes leave this true.
  final bool isActive;

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  final TextEditingController _noteController = TextEditingController();
  final OrderRepository _orderRepository = OrderRepository();
  bool _isSubscriptionKitExpanded = false;
  bool _isNonSubscriptionKitExpanded = false;
  bool _isEssentialsExpanded = true;
  bool _isKidsExpanded = true;
  bool _isPreparingCheckout = false;
  bool _isKitBreakdownExpanded = false;
  bool _isDepositExpanded = false;

  static const List<String> _allSizes = ['XS', 'S', 'M', 'L', 'XL', 'XXL', 'XXXL'];
  static const int _essentialsMaxQty = 5;

  ProductVariant? _resolveVariant(CartItem item) {
    final product = ProductCache.instance.findById(item.productId);
    if (product == null) return null;

    String? currentColor;
    if (item.variantId != null) {
      final oldVariant = product.variants.where((v) => v.id == item.variantId).firstOrNull;
      if (oldVariant != null) {
        currentColor = ProductMapper.optionValue(oldVariant, 'Color');
      }
    }

    return ProductMapper.matchingVariant(
      variants: product.variants,
      selectedColor: currentColor,
      selectedSize: item.selectedSize,
    );
  }

  /// Qty popup: wardrobe → 1..kit garment limit; essentials → 1..5.
  List<int> _qtyOptionsFor(CartState state, CartItem item) {
    int maxQty;
    if (item.isEssential) {
      maxQty = _essentialsMaxQty;
    } else {
      maxQty = CartLimits.effectiveMaxWardrobeGarments(state);
    }

    final variant = _resolveVariant(item);
    if (variant != null && variant.stockOnHand > 0) {
      maxQty = variant.stockOnHand;
    }

    final upper = maxQty < 1 ? 1 : maxQty;
    // ALWAYS strictly regenerate up to the new maxQty
    final qtyOptions = List<int>.generate(upper, (i) => i + 1);

    debugPrint('===== OPEN QUANTITY SELECTOR =====');
    debugPrint('variantId = ${variant?.id ?? item.variantId}');
    debugPrint('variantName = ${variant?.variantName}');
    debugPrint('maxQty = $maxQty');
    debugPrint('optionsCount = ${qtyOptions.length}');
    debugPrint('==================================');

    return qtyOptions;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.isActive) {
        context.read<CartBloc>().add(
              LoadCartEvent(
                source: 'CartScreen.initState',
              ),
            );
      }
    });
  }

  @override
  void didUpdateWidget(covariant CartScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      context.read<CartBloc>().add(
            LoadCartEvent(source: 'CartScreen.didUpdateWidget'),
          );
    }
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<CartBloc, CartState>(
      listenWhen: (previous, current) =>
          previous.items.isNotEmpty && current.isConfirmedEmpty,
      listener: (context, state) {
        if (state.isEmpty) {
          setState(() {
            _isSubscriptionKitExpanded = false;
            _isNonSubscriptionKitExpanded = false;
            _isEssentialsExpanded = true;
            _isKidsExpanded = true;
          });
        }
      },
      builder: (context, state) {
        final showLoading = state.showLoading;
        final isEmpty = state.isConfirmedEmpty;

        return PopScope(
          canPop: !isEmpty,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;
            Navigator.popUntil(context, ModalRoute.withName(AppRoutes.homeScreen));
          },
          child: Scaffold(
          backgroundColor: const Color(0xFF0F1012),
          body: Stack(
            children: [
              AbsorbPointer(
                absorbing: _isPreparingCheckout,
                child: SafeArea(
                  child: Column(
                    children: [
                      _buildAppBar(isEmpty || showLoading ? 0 : state.totalItems),
                      Expanded(
                        child: showLoading
                            ? _buildCartLoading()
                            : RefreshIndicator(
                                color: AppColours.primary,
                                backgroundColor: const Color(0xFF16181D),
                                onRefresh: () => context
                                    .read<CartBloc>()
                                    .refresh(source: 'CartScreen.pullToRefresh'),
                                child: isEmpty
                                    ? _buildEmptyCart()
                                    : _buildCartContent(context, state),
                              ),
                      ),
                      if (!isEmpty && !showLoading)
                        _buildPlaceOrderButton(context, state),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        );
      },
    );
  }

  Future<void> _onPlaceOrderPressed(BuildContext context) async {
    if (_isPreparingCheckout) return;
    final canProceed = await ProfileOrderGuard.ensureCompleteProfile(context);
    if (!canProceed || !context.mounted) return;
    CheckoutSession.instance.setOrderNote(_currentOrderNote());
    await _prefetchCheckoutAndNavigate(context);
  }

  String? _currentOrderNote() {
    final note = _noteController.text.trim();
    return note.isEmpty ? null : note;
  }

  Widget _buildAppBar(int count) {
    return Column(
      children: [
        // 🔹 Top Header (Cart Text)
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 16.h),
          child: Center(
            child: Text(
              'Cart',
              style: TextStyle(
                color: AppColours.primary,
                fontSize: 20.fSize,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),

        // 🔥 Custom Gradient Divider
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
      ],
    );
  }
  Widget _buildCartContent(BuildContext context, CartState state) {
    final subscriptionItems = state.subscriptionGarmentItems;
    final paidRentalItems = state.paidRentalGarmentItems;
    final essentialItems = state.essentialsOnlyItems;
    final kidsItems = state.kidsItems;
    final hasWardrobe = state.wardrobeItems.isNotEmpty;
    final hasPurchase = essentialItems.isNotEmpty || kidsItems.isNotEmpty;

    if (!hasWardrobe && !hasPurchase) {
      return _buildEmptyCart();
    }

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.symmetric(horizontal: 20.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: 16.h),
          _buildBackNavigationRow(context, state),

          if (subscriptionItems.isNotEmpty) ...[
            SizedBox(height: 24.h),
            _buildWardrobeKitSection(
              context,
              state,
              subscriptionItems,
              isExpanded: _isSubscriptionKitExpanded,
              onToggle: () => setState(() => _isSubscriptionKitExpanded = !_isSubscriptionKitExpanded),
              sectionTitle: 'SUBSCRIPTION ITEMS',
              showGarmentPrices: false,
            ),
          ],
          if (paidRentalItems.isNotEmpty) ...[
            if (subscriptionItems.isNotEmpty) SizedBox(height: 24.h),
            if (subscriptionItems.isNotEmpty) Divider(color: Colors.white12),
            SizedBox(height: 16.h),
            _buildWardrobeKitSection(
              context,
              state,
              paidRentalItems,
              isExpanded: _isNonSubscriptionKitExpanded,
              onToggle: () => setState(() => _isNonSubscriptionKitExpanded = !_isNonSubscriptionKitExpanded),
              sectionTitle: 'NON-SUBSCRIPTION ITEMS',
              showGarmentPrices: false,
            ),
          ],
          if (essentialItems.isNotEmpty) ...[
            if (hasWardrobe) SizedBox(height: 24.h),
            if (hasWardrobe) Divider(color: Colors.white12),
            SizedBox(height: 16.h),
            GestureDetector(
              onTap: () => setState(() => _isEssentialsExpanded = !_isEssentialsExpanded),
              behavior: HitTestBehavior.opaque,
              child: _buildSectionHeader(
                'ESSENTIALS',
                '${essentialItems.fold<int>(0, (s, i) => s + i.quantity)} Item${essentialItems.length == 1 ? '' : 's'}',
                isNonReturnable: true,
              ),
            ),
            if (_isEssentialsExpanded) ...[
              SizedBox(height: 16.h),
              ...essentialItems.map(
                (item) => _buildCartItem(
                  context,
                  item,
                  state: state,
                  isWardrobe: false,
                ),
              ),
            ],
          ],
          if (kidsItems.isNotEmpty) ...[
            if (hasWardrobe || essentialItems.isNotEmpty)
              SizedBox(height: 24.h),
            if (hasWardrobe || essentialItems.isNotEmpty)
              Divider(color: Colors.white12),
            SizedBox(height: 16.h),
            GestureDetector(
              onTap: () => setState(() => _isKidsExpanded = !_isKidsExpanded),
              behavior: HitTestBehavior.opaque,
              child: _buildSectionHeader(
                'KIDS',
                '${kidsItems.fold<int>(0, (s, i) => s + i.quantity)} Item${kidsItems.length == 1 ? '' : 's'}',
                isNonReturnable: true,
              ),
            ),
            if (_isKidsExpanded) ...[
              SizedBox(height: 16.h),
              ...kidsItems.map(
                (item) => _buildCartItem(
                  context,
                  item,
                  state: state,
                  isWardrobe: false,
                ),
              ),
            ],
          ],
          SizedBox(height: 28.h),
          _buildDeliveryDetails(),
          SizedBox(height: 28.h),
          _buildAddNote(),
          SizedBox(height: 28.h),
          _buildCartItemsBreakdown(context, state),
          SizedBox(height: 20.h),
          _buildTermsText(context),
          SizedBox(height: 24.h),
        ],
      ),
    );
  }

  Widget _buildGarmentListSection(
    BuildContext context,
    CartState state,
    List<CartItem> items, {
    required String title,
    required bool showPrice,
  }) {
    final garmentCount =
        items.fold<int>(0, (sum, item) => sum + item.quantity);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          title,
          '$garmentCount Garment${garmentCount == 1 ? '' : 's'}',
        ),
        SizedBox(height: 16.h),
        ...items.map(
          (item) => _buildCartItem(
            context,
            item,
            state: state,
            isWardrobe: true,
            showPrice: showPrice,
          ),
        ),
      ],
    );
  }

  String? _resolveListingCategory(CartState state) {
    if (state.wardrobeItems.isNotEmpty) {
      final category = state.wardrobeItems.first.category?.trim();
      if (category != null && category.isNotEmpty) return category;
    }
    if (state.essentialItems.isNotEmpty) {
      final category = state.essentialItems.first.category?.trim();
      if (category != null && category.isNotEmpty) return category;
    }
    return null;
  }

  /// Formats line price from cart API / local item price for display.
  String _formatCartItemPrice(CartItem item) {
    final raw = item.price?.trim() ?? '';
    final unit = CheckoutPricing.parseItemPrice(
      item.price,
      isEssential: item.isEssential,
    );
    if (raw.isEmpty && unit <= 0) return 'Free';
    return CheckoutPricing.formatMoney(unit * item.quantity);
  }

  void _goBackToCategory(BuildContext context) {
    try {
      context.read<HomeBloc>().add(ChangeBottomNavEvent(0));
    } catch (_) {
      Navigator.pushNamedAndRemoveUntil(
        context,
        AppRoutes.homeScreen,
        (route) => false,
      );
    }
  }

  void _goBackToProductListing(BuildContext context, String category) {
    Navigator.pushNamed(
      context,
      AppRoutes.wardrobeScreen,
      arguments: category,
    );
  }

  WardrobeItem _productFromCartItem(CartItem item) {
    final productId = item.id.contains('_')
        ? item.id.split('_').first
        : item.id;
    final cached = ProductCache.instance.findById(productId);
    if (cached != null) {
      final mapped = ProductMapper.toWardrobeItem(
        cached,
        category: item.category,
      );
      // Keep the cart-line thumbnail (selected color), not product primary.
      return WardrobeItem(
        productId: mapped.productId,
        title: mapped.title,
        description: mapped.description,
        imageUrl: item.imageUrl.isNotEmpty ? item.imageUrl : mapped.imageUrl,
        price: item.price ?? mapped.price,
        imageUrls: mapped.imageUrls,
        colorVariantImages: mapped.colorVariantImages,
        colorNames: mapped.colorNames,
        sizes: mapped.sizes,
        ages: mapped.ages,
        productDetails: mapped.productDetails,
        variants: mapped.variants,
        category: mapped.category,
        genderTag: mapped.genderTag,
      );
    }

    return WardrobeItem(
      productId: productId.isNotEmpty ? productId : null,
      title: item.title,
      description: '',
      imageUrl: item.imageUrl,
      price: item.price,
      category: item.category,
    );
  }

  void _openProductDetails(BuildContext context, CartItem item) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProductDetailsScreen(
          product: _productFromCartItem(item),
        ),
      ),
    );
  }

  Widget _buildBackNavigationRow(BuildContext context, CartState state) {
    final category = _resolveListingCategory(state);
    if (category == null) return const SizedBox.shrink();

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildBackNavButton(
                label: 'Back to Category',
                onTap: () => _goBackToCategory(context),
              ),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: _buildBackNavButton(
                label: 'Back to Product Listing',
                onTap: () => _goBackToProductListing(context, category),
              ),
            ),
          ],
        ),
        SizedBox(height: 8.h),
      ],
    );
  }

  Widget _buildBackNavButton({
    required String label,
    required VoidCallback onTap,
  }) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: AppColours.primary.withOpacity(0.45)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: EdgeInsets.symmetric(vertical: 10.h, horizontal: 8.w),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: CustomTextStyles.openSansSemiBold.copyWith(
          fontSize: 10,
          color: AppColours.primary,
        ),
      ),
    );
  }

  Widget _buildSectionHeader(
    String title,
    String trailing, {
    bool isNonReturnable = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: CustomTextStyles.montserratBold.copyWith(
                fontSize: 12,
                color: AppColours.primary,
                letterSpacing: 1,
              ),
            ),
            if (isNonReturnable) ...[
              SizedBox(width: 8.w),
              _buildNonReturnableBadge(),
            ],
          ],
        ),
        Text(
          trailing,
          style: TextStyle(
            color: Colors.white70,
            fontSize: 12.fSize,
          ),
        ),
      ],
    );
  }

  Widget _buildNonReturnableBadge() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
      decoration: BoxDecoration(
        color: const Color(0xFFEA4335).withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFFEA4335).withOpacity(0.6),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.replay_rounded,
            color: const Color(0xFFEA4335),
            size: 11.w,
          ),
          SizedBox(width: 3.w),
          Text(
            'Non-Returnable',
            style: TextStyle(
              color: const Color(0xFFEA4335),
              fontSize: 10.fSize,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWardrobeKitSection(
    BuildContext context,
    CartState state,
    List<CartItem> wardrobeItems, {
    required bool isExpanded,
    required VoidCallback onToggle,
    String sectionTitle = 'SELECTED WARDROBE',
    bool showGarmentPrices = false,
  }) {
    final garmentCount =
        wardrobeItems.fold<int>(0, (sum, item) => sum + item.quantity);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          sectionTitle,
          '$garmentCount Item${garmentCount == 1 ? '' : 's'}',
        ),
        SizedBox(height: 16.h),
        _buildWardrobeKitSummaryCard(
          state: state,
          items: wardrobeItems,
          garmentCount: garmentCount,
          isExpanded: isExpanded,
          onToggle: onToggle,
        ),
        if (isExpanded) ...[
          SizedBox(height: 24.h),
          _buildSectionHeader(
            'SELECTED GARMENTS',
            '$garmentCount Item${garmentCount == 1 ? '' : 's'}',
          ),
          SizedBox(height: 16.h),
          ...wardrobeItems.map(
            (item) => _buildCartItem(
              context,
              item,
              state: state,
              isWardrobe: true,
              showPrice: showGarmentPrices,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildWardrobeKitSummaryCard({
    required CartState state,
    required List<CartItem> items,
    required int garmentCount,
    required bool isExpanded,
    required VoidCallback onToggle,
  }) {
    return GestureDetector(
      onTap: onToggle,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildWardrobeCollage(items),
          SizedBox(width: 14.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  state.wardrobeKitTitle,
                  style: CustomTextStyles.montserratSemiBold.copyWith(
                    color: AppColours.primary,
                    fontSize: 14,
                  ),
                ),
                SizedBox(height: 6.h),
                Text(
                  'No of Garments: $garmentCount',
                  style: CustomTextStyles.openSansRegular.copyWith(
                    fontSize: 12,
                    color: AppColours.secondary.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.only(top: 4.h),
            child: AnimatedRotation(
              turns: isExpanded ? 0.5 : 0,
              duration: const Duration(milliseconds: 200),
              child: Icon(
                Icons.keyboard_arrow_down,
                color: AppColours.primary,
                size: 28,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWardrobeCollage(List<CartItem> items) {
    final images = items
        .map((e) => ProductImage.resolveUrl(e.imageUrl))
        .take(4)
        .toList();
    while (images.length < 4) {
      images.add(images.isNotEmpty ? images.last : '');
    }

    Widget cell(String url, {BorderRadius? radius}) {
      return ClipRRect(
        borderRadius: radius ?? BorderRadius.zero,
        child: ProductImage(
          imageUrl: url,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppColours.primary,
          width: 1.2,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: SizedBox(
          width: 88.w,
          height: 88.w,
          child: Column(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: cell(
                        images[0],
                        radius: const BorderRadius.only(topLeft: Radius.circular(8)),
                      ),
                    ),
                    SizedBox(width: 2),
                    Expanded(
                      child: cell(
                        images[1],
                        radius: const BorderRadius.only(topRight: Radius.circular(8)),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 2),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: cell(
                        images[2],
                        radius: const BorderRadius.only(bottomLeft: Radius.circular(8)),
                      ),
                    ),
                    SizedBox(width: 2),
                    Expanded(
                      child: cell(
                        images[3],
                        radius: const BorderRadius.only(bottomRight: Radius.circular(8)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCartItem(
    BuildContext context,
    CartItem item, {
    required CartState state,
    bool isWardrobe = false,
    bool? showPrice,
  }) {
    return ReusableProductCartItem(
      item: item,
      state: state,
      showPrice: isWardrobe ? false : (showPrice ?? true),
    );
  }

  Widget _buildDropdownChip<T>({
    required T value,
    required List<T> items,
    required String prefix,
    required ValueChanged<T?> onChanged,
  }) {


    return Container(
      height: 28.h,
      padding: EdgeInsets.symmetric(horizontal: 6.w),
      decoration: BoxDecoration(
        color: AppColours.secondary,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColours.primary.withOpacity(0.4)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isDense: true,
          isExpanded: true,
          menuMaxHeight: 220.h,
          dropdownColor: AppColours.secondary,
          icon: Icon(Icons.arrow_drop_down,
              color: Colors.black, size: 18),
          style: TextStyle(color: Colors.white, fontSize: 11.fSize),
          onChanged: onChanged,
          items: items
              .map((s) => DropdownMenuItem<T>(
                    value: s,
                    child: Text(
                      '$prefix$s',
                      style: CustomTextStyles.montserratSemiBold.copyWith(
                        color: Colors.black,
                        fontSize: 10,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ))
              .toList(),
        ),
      ),
    );
  }

  Widget _buildCartLoading() {
    return const Center(
      child: SizedBox(
        width: 28,
        height: 28,
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          color: Color(0xFFE6C27A),
        ),
      ),
    );
  }

  Widget _buildEmptyCart() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(height: 160.h),
        Icon(Icons.shopping_cart_outlined,
            color: AppColours.primary.withOpacity(0.5), size: 64),
        SizedBox(height: 16.h),
        Center(
          child: Text(
            'Your cart is empty',
            style: TextStyle(color: Colors.white, fontSize: 18.fSize),
          ),
        ),
      ],
    );
  }

  Widget _buildDeliveryDetails() {
    final session = CheckoutSession.instance;
    final customer = ProfileCache.instance.customer;
    final selectedAddressId = session.addressId?.trim();
    final matchedAddress = customer == null || customer.addresses.isEmpty
        ? null
        : customer.addresses.firstWhere(
            (a) => a.id?.trim() == selectedAddressId,
            orElse: () => customer.primaryAddress ?? customer.addresses.first,
          );

    final addressText = session.addressLines?.trim().isNotEmpty == true
        ? session.addressLines!.trim()
        : (matchedAddress?.fullAddress?.trim().isNotEmpty == true
            ? matchedAddress!.fullAddress!.trim()
            : session.addressDisplay);

    final deliveryDateText = session.deliveryDate != null
        ? session.deliveryDateDisplay
        : 'Not selected';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'DELIVERY DETAILS',
          style: CustomTextStyles.montserratBold.copyWith(color: AppColours.primary,fontSize: 12),
        ),
        SizedBox(height: 16.h),
        _deliveryItem(
          Icons.location_on_outlined,
          'DELIVERY ADDRESS',
          addressText,
        ),
        SizedBox(height: 16.h),
        _deliveryItem(
          Icons.calendar_today_outlined,
          'DELIVERY DATE',
          deliveryDateText,
        ),
      ],
    );
  }

  Widget _deliveryItem(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppColours.primary, size: 20),
        SizedBox(width: 12.w),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: CustomTextStyles.openSansSemiBold.copyWith(fontSize: 12,letterSpacing: 1.2,color: Color(0xFFF5E6C8).withOpacity(0.6)),
              ),
              SizedBox(height: 4.h),
              Text(
                value,
                style: CustomTextStyles.openSansMedium.copyWith(fontSize: 14),

              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAddNote() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ADD NOTE',
          style: CustomTextStyles.montserratBold.copyWith(fontSize: 12,color: AppColours.primary),

        ),
        SizedBox(height: 12.h),
        DottedBorder(
          borderType: BorderType.RRect,
          radius: const Radius.circular(8),
          dashPattern: const [6, 3], // 🔥 dot size & spacing
          color: Color(0xFFE6C27A).withOpacity(0.6),
          strokeWidth: 1.2,
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 12.w),
            child: TextField(
              controller: _noteController,
              maxLines: 6,
              style: TextStyle(color: Colors.white70, fontSize: 13.fSize),
              decoration: InputDecoration(
                hintText: 'Please leave the order at the doorstep',
                hintStyle: CustomTextStyles.openSansRegular.copyWith(
                  fontSize: 12,
                  color: const Color(0xFFF5E6C8).withOpacity(0.6),
                ),
                border: InputBorder.none,
              ),
              
            ),
          ),
        )
      ],
    );
  }

  Widget _buildTermsText(BuildContext context) {
    return Center(
      child: RichText(
        textAlign: TextAlign.center,
        text: TextSpan(
          style: CustomTextStyles.openSansRegular.copyWith(fontSize: 12),
          children: [
            const TextSpan(
              text: 'By placing this order, you agree to the Nomowear ',
            ),

            // 🔥 Terms & Conditions
            TextSpan(
              text: 'Terms & conditions',
              style: CustomTextStyles.openSansRegular.copyWith(fontSize: 12,color: AppColours.primary),
              recognizer: TapGestureRecognizer()
                ..onTap = () {
                  Navigator.pushNamed(context, AppRoutes.termsConditionsScreen);
                },
            ),

            const TextSpan(text: ' and '),

            // 🔥 Privacy Policy
            TextSpan(
              text: 'Privacy Policy',
              style: TextStyle(
                color: AppColours.primary,
                fontWeight: FontWeight.w600,
              ),
              recognizer: TapGestureRecognizer()
                ..onTap = () {
                  Navigator.pushNamed(context, AppRoutes.privacyPolicyScreen);
                },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceOrderButton(BuildContext context, CartState state) {
    final amounts = _resolveCartBreakdownAmounts(state);
    final buttonLabel = amounts.totalDue > 0
        ? 'Proceed to Payment'
        : 'PLACE ORDER';

    return Container(
      width: double.maxFinite,
      padding: EdgeInsets.all(20.w),
      decoration: BoxDecoration(
        color: const Color(0xFF16181D),
        border: Border(top: BorderSide(color: Colors.white12)),
      ),
      child: ElevatedButton(
        onPressed: _isPreparingCheckout
            ? null
            : () => _onPlaceOrderPressed(context),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColours.primary,
          disabledBackgroundColor: AppColours.primary.withOpacity(0.6),
          minimumSize: Size(double.maxFinite, 54.h),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: _isPreparingCheckout
            ? SizedBox(
                width: 22.w,
                height: 22.w,
                child: const CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: Colors.black,
                ),
              )
            : Text(
                buttonLabel,
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 16.fSize,
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
    );
  }

  _CartBreakdownAmounts _resolveCartBreakdownAmounts(CartState state) {
    final isSubscription = _isSubscriptionWardrobeBooking(state);

    // 1. Kit Price
    num kitPrice = 0;
    if (!isSubscription) {
      if (state.remote.activeKitPrice > 0) {
        kitPrice = state.remote.activeKitPrice;
      } else {
        kitPrice = CheckoutPricing.wardrobeKitPriceFromState(state);
      }
      if (kitPrice <= 0 && state.wardrobeItems.isNotEmpty) {
        kitPrice = state.wardrobeItems.fold<num>(
          0,
          (sum, item) =>
              sum +
              (CheckoutPricing.parseItemPrice(item.price, isEssential: false) *
                  item.quantity),
        );
      }
    }

    // 2. Deposit Amount
    num depositAmount = 0;
    if (!isSubscription) {
      if (state.remote.securityDepositAmount > 0) {
        depositAmount = state.remote.securityDepositAmount;
      }
    }

    // 3. Subtotal
    final directSum = state.essentialItems.fold<num>(
      0,
      (sum, item) =>
          sum +
          (CheckoutPricing.parseItemPrice(item.price, isEssential: item.isEssential) *
              item.quantity),
    );
    num subtotal = isSubscription ? 0 : (kitPrice + directSum);
    if (subtotal <= 0 && state.remote.subtotal > 0) {
      subtotal = state.remote.subtotal;
    }

    // 4. Delivery Fee
    num deliveryFee = state.remote.deliveryCharge;

    // 5. Tax (GST 18%)
    num taxAmount = state.remote.taxAmount;
    if (taxAmount <= 0 && subtotal > 0 && !isSubscription) {
      taxAmount = (subtotal * 0.18);
    }

    // 6. Order Total (Rentals + Delivery + GST)
    num orderTotal = subtotal + deliveryFee + taxAmount - state.remote.discountAmount;
    if (orderTotal < 0) orderTotal = 0;

    // 7. Total Due at Checkout
    num totalDue = orderTotal + depositAmount;
    if (state.remote.totalAmount > 0 && state.remote.totalAmount > totalDue) {
      totalDue = state.remote.totalAmount;
    }

    return _CartBreakdownAmounts(
      kitPrice: kitPrice,
      depositAmount: depositAmount,
      subtotal: subtotal,
      deliveryFee: deliveryFee,
      taxAmount: taxAmount,
      orderTotal: orderTotal,
      totalDue: totalDue,
      isSubscription: isSubscription,
    );
  }

  String _formatCurrency(
    num value, {
    bool forceDecimals = false,
    bool keepDecimalIfPresent = false,
  }) {
    final isNegative = value < 0;
    final absVal = value.abs();

    String numberPart;
    if (forceDecimals) {
      numberPart = absVal.toStringAsFixed(2);
    } else if (keepDecimalIfPresent) {
      if (absVal == absVal.truncateToDouble()) {
        numberPart = absVal.toInt().toString();
      } else {
        final raw = absVal.toString();
        if (raw.contains('.') && raw.split('.')[1].length > 2) {
          numberPart = absVal.toStringAsFixed(2);
        } else {
          numberPart = raw;
        }
      }
    } else {
      if (absVal == absVal.truncateToDouble()) {
        numberPart = absVal.toInt().toString();
      } else {
        numberPart = absVal.toStringAsFixed(2);
      }
    }

    final parts = numberPart.split('.');
    final whole = parts[0];
    final decimal = parts.length > 1 ? '.${parts[1]}' : '';

    String formattedWhole = whole;
    if (whole.length > 3) {
      final lastThree = whole.substring(whole.length - 3);
      final otherNumbers = whole.substring(0, whole.length - 3);
      final formattedOther = otherNumbers.replaceAllMapped(
        RegExp(r'(\d)(?=(\d{2})+(?!\d))'),
        (Match m) => '${m[1]},',
      );
      formattedWhole = '$formattedOther,$lastThree';
    }

    return '${isNegative ? "-₹" : "₹"}$formattedWhole$decimal';
  }

  Widget _buildSummaryRow(String label, String value, {bool isHighlight = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white70,
            fontSize: 13.5.fSize,
            fontWeight: FontWeight.w400,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: isHighlight ? const Color(0xFFE6C27A) : Colors.white,
            fontSize: 13.5.fSize,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildCartItemsBreakdown(BuildContext context, CartState state) {
    final amounts = _resolveCartBreakdownAmounts(state);
    final hasWardrobe = state.wardrobeItems.isNotEmpty;
    final kitGarmentCount = state.wardrobeGarmentCount > 0
        ? state.wardrobeGarmentCount
        : state.totalItems;
    final kitDays = state.wardrobeKitDays > 0 ? state.wardrobeKitDays : 1;
    final kitTitle = state.wardrobeKitTitle.isNotEmpty
        ? state.wardrobeKitTitle
        : '$kitDays-Day wardrobe Kit';
    final wardrobeGarments = state.wardrobeItems;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Header with Dotted Lines
        Row(
          children: [
            Expanded(
              child: _DottedDivider(
                color: const Color(0xFFD8B26A).withOpacity(0.5),
                dashWidth: 4,
                dashSpace: 4,
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 10.w),
              child: Text(
                'CART ITEMS BREAKDOWN',
                style: TextStyle(
                  color: const Color(0xFFD8B26A),
                  fontSize: 12.fSize,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.5,
                ),
              ),
            ),
            Expanded(
              child: _DottedDivider(
                color: const Color(0xFFD8B26A).withOpacity(0.5),
                dashWidth: 4,
                dashSpace: 4,
              ),
            ),
          ],
        ),

        // Wardrobe Kit Card with Dotted Border
        if (hasWardrobe) ...[
          SizedBox(height: 16.h),
          DottedBorder(
            color: const Color(0xFFD8B26A).withOpacity(0.6),
            strokeWidth: 1.2,
            dashPattern: const [5, 4],
            borderType: BorderType.RRect,
            radius: const Radius.circular(12),
            child: Container(
              padding: EdgeInsets.all(14.w),
              decoration: BoxDecoration(
                color: const Color(0xFF161824).withOpacity(0.6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InkWell(
                    onTap: () => setState(() => _isKitBreakdownExpanded = !_isKitBreakdownExpanded),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                kitTitle,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14.5.fSize,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(height: 4.h),
                              Text(
                                '$kitGarmentCount Items',
                                style: TextStyle(
                                  color: Colors.white60,
                                  fontSize: 12.5.fSize,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              amounts.isSubscription
                                  ? '₹0 (Plan)'
                                  : _formatCurrency(amounts.kitPrice, forceDecimals: false),
                              style: TextStyle(
                                color: const Color(0xFFE6C27A),
                                fontSize: 15.fSize,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(width: 4.w),
                            Icon(
                              _isKitBreakdownExpanded
                                  ? Icons.keyboard_arrow_up_rounded
                                  : Icons.keyboard_arrow_down_rounded,
                              color: const Color(0xFFE6C27A),
                              size: 20,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (amounts.depositAmount > 0) ...[
                    SizedBox(height: 8.h),
                    Text(
                      'Deposit Hold: ${_formatCurrency(amounts.depositAmount, forceDecimals: false)} ($kitGarmentCount items)',
                      style: TextStyle(
                        color: const Color(0xFFE59438),
                        fontSize: 11.5.fSize,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                  if (_isKitBreakdownExpanded) ...[
                    SizedBox(height: 12.h),
                    Divider(color: Colors.white12),
                    SizedBox(height: 8.h),
                    ...wardrobeGarments.map((g) => Padding(
                          padding: EdgeInsets.symmetric(vertical: 4.h),
                          child: Row(
                            children: [
                              if (g.imageUrl.isNotEmpty)
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: Image.network(
                                    g.imageUrl,
                                    width: 32.w,
                                    height: 32.w,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                                  ),
                                ),
                              SizedBox(width: 8.w),
                              Expanded(
                                child: Text(
                                  g.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12.fSize,
                                  ),
                                ),
                              ),
                              if (g.selectedSize.isNotEmpty)
                                Text(
                                  'Size: ${g.selectedSize}',
                                  style: TextStyle(
                                    color: Colors.white38,
                                    fontSize: 11.fSize,
                                  ),
                                ),
                            ],
                          ),
                        )),
                  ],
                ],
              ),
            ),
          ),
        ],

        // Dotted Divider
        SizedBox(height: 20.h),
        _DottedDivider(color: Colors.white24, dashWidth: 4, dashSpace: 4),
        SizedBox(height: 16.h),

        // Items Subtotal
        _buildSummaryRow(
          'Items Subtotal',
          _formatCurrency(amounts.subtotal, forceDecimals: true),
        ),
        SizedBox(height: 12.h),

        // Delivery Fee
        _buildSummaryRow(
          'Delivery Fee',
          amounts.deliveryFee > 0
              ? _formatCurrency(amounts.deliveryFee, keepDecimalIfPresent: true)
              : 'FREE',
        ),
        SizedBox(height: 12.h),

        // Taxes (GST 18%)
        _buildSummaryRow(
          'Taxes (GST 18%)',
          _formatCurrency(amounts.taxAmount, forceDecimals: true),
        ),
        SizedBox(height: 16.h),

        // Order Total Container
        Container(
          padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
          decoration: BoxDecoration(
            color: const Color(0xFF1C1F26),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Order Total (Rentals + Delivery + GST)',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.9),
                  fontSize: 12.5.fSize,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                _formatCurrency(amounts.orderTotal, forceDecimals: true),
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13.5.fSize,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),

        // Refundable Security Deposit Card
        if (amounts.depositAmount > 0) ...[
          SizedBox(height: 16.h),
          Container(
            padding: EdgeInsets.all(12.w),
            decoration: BoxDecoration(
              color: const Color(0xFF1B1812),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: const Color(0xFFD8B26A).withOpacity(0.7),
                width: 1.2,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: () => setState(() => _isDepositExpanded = !_isDepositExpanded),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.shield_outlined,
                        color: Color(0xFFD8B26A),
                        size: 20,
                      ),
                      SizedBox(width: 8.w),
                      Expanded(
                        child: RichText(
                          text: TextSpan(
                            children: [
                              TextSpan(
                                text: 'Refundable Security Deposit ',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12.5.fSize,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              TextSpan(
                                text: '(Temporary Hold)',
                                style: TextStyle(
                                  color: Colors.white60,
                                  fontSize: 11.5.fSize,
                                  fontWeight: FontWeight.normal,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Text(
                        _formatCurrency(amounts.depositAmount, forceDecimals: true),
                        style: TextStyle(
                          color: const Color(0xFFE6C27A),
                          fontSize: 13.5.fSize,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(width: 4.w),
                      Icon(
                        _isDepositExpanded
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        color: const Color(0xFFE6C27A),
                        size: 18,
                      ),
                    ],
                  ),
                ),
                if (_isDepositExpanded) ...[
                  SizedBox(height: 10.h),
                  Divider(color: Colors.white12),
                  SizedBox(height: 8.h),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Deposit Status',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 11.fSize,
                          ),
                        ),
                      ),
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2A2214),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: const Color(0xFFD8B26A).withOpacity(0.5),
                          ),
                        ),
                        child: Text(
                          'HOLD ACTIVE · REFUNDABLE',
                          style: TextStyle(
                            color: const Color(0xFFE6C27A),
                            fontSize: 9.5.fSize,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8.h),
                  Container(
                    padding: EdgeInsets.all(8.w),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0A261E),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: const Color(0xFF10B981).withOpacity(0.35),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.lock_outline_rounded,
                          color: Color(0xFFD8B26A),
                          size: 14,
                        ),
                        SizedBox(width: 6.w),
                        Expanded(
                          child: Text(
                            '100% refunded to your payment source upon safe return of garments.',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 10.5.fSize,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],

        // Dotted Divider
        SizedBox(height: 16.h),
        _DottedDivider(color: Colors.white24, dashWidth: 4, dashSpace: 4),
        SizedBox(height: 16.h),

        // Total Due at Checkout
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Total Due at Checkout',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16.fSize,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (amounts.depositAmount > 0) ...[
                  SizedBox(height: 4.h),
                  Text(
                    'Includes ${_formatCurrency(amounts.depositAmount, forceDecimals: false)} refundable hold',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 11.5.fSize,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ],
            ),
            Text(
              _formatCurrency(amounts.totalDue, forceDecimals: true),
              style: TextStyle(
                color: const Color(0xFFE6C27A),
                fontSize: 22.fSize,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ],
    );
  }

  bool _isSubscriptionWardrobeBooking(CartState state) {
    if (state.wardrobeItems.isEmpty) return false;
    if (state.essentialItems.isNotEmpty) return false;
    if (state.hasPaidRentalGarments) return false;
    if (state.hasMixedWardrobeTypes) return false;
    if (CheckoutSession.instance.continueWithoutMembership) return false;
    return CheckoutSession.instance.useSubscriptionBooking;
  }

  Future<void> _prefetchCheckoutAndNavigate(BuildContext context) async {
    if (_isPreparingCheckout) return;
    final state = context.read<CartBloc>().state;
    if (state.isEmpty) return;

    setState(() => _isPreparingCheckout = true);
    try {
      final bloc = context.read<CartBloc>();
      final remoteCart = await bloc.refresh(source: 'CartScreen.checkout');
      if (!context.mounted) return;
      if (remoteCart.isEmpty) {
        CustomAppSnackBar.showInfo(context, 'Your cart is empty');
        return;
      }

      if (_isSubscriptionWardrobeBooking(bloc.state)) {
        CheckoutSession.instance.setOrderNote(_currentOrderNote());
        Navigator.pushNamed(context, AppRoutes.essentialsCheckoutScreen);
        return;
      }

      final stateAfterRefresh = bloc.state;
      final initiateReq = CheckoutInitiateRequest.fromCart(stateAfterRefresh);
      final initiate = await _orderRepository.initiateOrder(
        checkoutType: initiateReq.checkoutType,
        nonSubscription: initiateReq.nonSubscription,
        productClass: initiateReq.productClass,
        wardrobeKitId: initiateReq.wardrobeKitId,
        orderNote: _currentOrderNote(),
      );

      if (!context.mounted) return;

      if (initiate.isFreeSubscriptionBooking && initiate.orderId.isNotEmpty) {
        Navigator.pushNamed(context, AppRoutes.essentialsCheckoutScreen);
        return;
      }

      if (!initiate.canOpenRazorpay) {
        CustomAppSnackBar.showError(
          context,
          initiate.requiresPayment
              ? 'Payment details missing from server. Please try again.'
              : 'Unable to load payable amount. Please try again.',
        );
        return;
      }

      final latestState = bloc.state;
      final snapshot = CheckoutPricing.payableSnapshot(
        remoteCart: remoteCart,
        initiate: initiate,
        cartState: latestState,
      );

      final payload = CheckoutPrefetchPayload(
        snapshot: snapshot,
        cartFingerprint: CheckoutPricing.cartFingerprint(latestState),
      );

      Navigator.pushNamed(
        context,
        AppRoutes.essentialsCheckoutScreen,
        arguments: payload,
      );
    } on ApiException catch (e) {
      if (!context.mounted) return;
      if (e.isNoReturnBlocked) {
        await showNoReturnBlockedDialog(
          context,
          overdueOrderNumber: e.overdueOrderNumber,
          message: e.message,
        );
      } else {
        CustomAppSnackBar.showError(context, e.message);
      }
    } catch (_) {
      if (!context.mounted) return;
      CustomAppSnackBar.showError(
        context,
        'Unable to prepare checkout. Please try again.',
      );
    } finally {
      if (mounted) setState(() => _isPreparingCheckout = false);
    }
  }
}

class _CartBreakdownAmounts {
  const _CartBreakdownAmounts({
    required this.kitPrice,
    required this.depositAmount,
    required this.subtotal,
    required this.deliveryFee,
    required this.taxAmount,
    required this.orderTotal,
    required this.totalDue,
    required this.isSubscription,
  });

  final num kitPrice;
  final num depositAmount;
  final num subtotal;
  final num deliveryFee;
  final num taxAmount;
  final num orderTotal;
  final num totalDue;
  final bool isSubscription;
}

class _DottedDivider extends StatelessWidget {
  const _DottedDivider({
    this.color = Colors.white24,
    this.dashWidth = 4.0,
    this.dashSpace = 4.0,
  });

  final Color color;
  final double dashWidth;
  final double dashSpace;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final boxWidth = constraints.constrainWidth();
        final dashCount = (boxWidth / (dashWidth + dashSpace)).floor();
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(dashCount > 0 ? dashCount : 1, (_) {
            return SizedBox(
              width: dashWidth,
              height: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(color: color),
              ),
            );
          }),
        );
      },
    );
  }
}

