import 'package:nomowear/core/app_export.dart';
import 'package:nomowear/core/network/api_exception.dart';
import 'package:nomowear/core/utils/api_id_utils.dart';
import 'package:nomowear/features/orders/data/order_repository.dart';
import 'package:nomowear/features/orders/data/pending_return_store.dart';
import 'package:nomowear/features/orders/data/user_order_mapper.dart';
import 'package:nomowear/features/products/data/product_cache.dart';
import 'package:nomowear/features/products/data/product_mapper.dart';
import 'package:nomowear/features/products/data/product_repository.dart';
import 'package:nomowear/features/profile/data/profile_repository.dart';
import 'package:nomowear/features/profile/domain/order_action.dart';
import 'package:nomowear/features/profile/domain/user_order.dart';
import 'package:nomowear/features/wardrobe/presentation/screens/product_details_screen.dart';
import 'package:nomowear/features/wardrobe/presentation/screens/wardrobe_screen.dart';

class OrderDetailsScreen extends StatefulWidget {
  final String orderId;

  const OrderDetailsScreen({super.key, required this.orderId});

  @override
  State<OrderDetailsScreen> createState() => _OrderDetailsScreenState();
}

class _OrderDetailsScreenState extends State<OrderDetailsScreen> {
  final OrderRepository _orderRepository = OrderRepository();
  final ProductRepository _productRepository = ProductRepository();
  final ProfileRepository _profileRepository = ProfileRepository();
  final Set<String> _ratedProductIds = <String>{};
  final Map<String, int> _ratedProductValues = <String, int>{};

  bool _isLoading = true;
  String? _errorMessage;
  UserOrder? _order;
  bool _itemsExpanded = true;
  bool _subItemsExpanded = true;
  bool _nonSubItemsExpanded = true;
  bool _kidsItemsExpanded = true;
  bool _depositExpanded = true;

  @override
  void initState() {
    super.initState();
    _itemsExpanded = true;
    _subItemsExpanded = true;
    _nonSubItemsExpanded = true;
    _kidsItemsExpanded = true;
    _depositExpanded = true;
    _loadOrder();
  }

  Future<void> _loadOrder() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await PendingReturnStore.instance.ensureLoaded();
      final detail = await _orderRepository.getOrderDetail(widget.orderId);
      final customer = await _profileRepository.getProfile();
      final mapped = UserOrderMapper.fromHistoryItem(detail, customer: customer);
      final ratedRatings = await _loadRatedProductRatings(mapped);

      final existingIndex =
          userOrdersList.indexWhere((order) => order.id == mapped.id);
      if (existingIndex >= 0) {
        userOrdersList[existingIndex] = mapped;
      } else {
        userOrdersList.insert(0, mapped);
      }

      if (!mounted) return;
      setState(() {
        _order = mapped;
        _ratedProductIds
          ..clear()
          ..addAll(ratedRatings.keys);
        _ratedProductValues
          ..clear()
          ..addAll(ratedRatings);
        _isLoading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Unable to load order details. Please try again.';
      });
    }
  }

  UserOrder? get o => _order;

  Future<Map<String, int>> _loadRatedProductRatings(UserOrder order) async {
    final lineItems = order.lineItems ?? const <OrderLineItem>[];
    final productIds = lineItems
        .map((item) => item.productId.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    if (productIds.isEmpty) return const <String, int>{};
    try {
      return await _orderRepository.getMyProductRatings(productIds: productIds);
    } catch (_) {
      // Keep order-details loading resilient even if rating status API fails.
      return const <String, int>{};
    }
  }

  Future<void> _refreshRatedProductIds() async {
    final order = _order;
    if (order == null) return;
    final ratedRatings = await _loadRatedProductRatings(order);
    if (!mounted) return;
    if (ratedRatings.isEmpty) return;
    setState(() {
      _ratedProductIds
        ..clear()
        ..addAll(ratedRatings.keys);
      _ratedProductValues
        ..clear()
        ..addAll(ratedRatings);
    });
  }

  WardrobeItem _productFromOrderLineItem(OrderLineItem item) {
    final productId = item.productId.trim();
    if (productId.isNotEmpty) {
      final cached = ProductCache.instance.findById(productId);
      if (cached != null) {
        final mapped = ProductMapper.toWardrobeItem(
          cached,
          category: item.category,
        );
        return WardrobeItem(
          productId: mapped.productId,
          title: mapped.title,
          description: mapped.description,
          imageUrl: _isNetworkImage(item.imageAsset)
              ? item.imageAsset
              : mapped.imageUrl,
          price: mapped.price,
          imageUrls: mapped.imageUrls,
          colorVariantImages: mapped.colorVariantImages,
          colorNames: mapped.colorNames,
          sizes: mapped.sizes,
          ages: mapped.ages,
          productDetails: mapped.productDetails,
          variants: mapped.variants,
          category: item.category ?? mapped.category,
          genderTag: mapped.genderTag,
        );
      }
    }

    return WardrobeItem(
      productId: isApiUuid(productId) ? productId : null,
      title: item.productName,
      description: '',
      imageUrl: item.imageAsset,
      sizes: item.sizeLabel != '-' ? [item.sizeLabel] : const [],
      category: item.category,
    );
  }

  bool _isNetworkImage(String source) {
    return source.startsWith('http://') || source.startsWith('https://');
  }

  Future<void> _openProductDetails(OrderLineItem item) async {
    final productId = item.productId.trim();
    if (!isApiUuid(productId)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Product details are not available for this item.'),
        ),
      );
      return;
    }

    try {
      await _productRepository.getProductById(productId);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.message.isNotEmpty
                ? e.message
                : 'This product is no longer available.',
          ),
        ),
      );
      return;
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to open product details. Please try again.'),
        ),
      );
      return;
    }

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProductDetailsScreen(
          product: _productFromOrderLineItem(item),
        ),
      ),
    );
  }

  Future<void> _onRateTap(OrderLineItem item) async {
    final productId = item.productId.trim();
    if (productId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Product id missing for this item.')),
      );
      return;
    }

    if (_ratedProductIds.contains(productId)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You already rated this product.')),
      );
      return;
    }

    final draft = await _showRatingDialog(item.productName);
    if (draft == null) return;

    try {
      final message = await _orderRepository.submitProductRating(
        productId: productId,
        rating: draft.rating,
        review: draft.review,
      );
      if (!mounted) return;
      setState(() {
        _ratedProductIds.add(productId);
        _ratedProductValues[productId] = draft.rating;
      });
      await _refreshRatedProductIds();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to submit rating. Please try again.')),
      );
    }
  }

  Future<_RatingDraft?> _showRatingDialog(String productName) async {
    final reviewController = TextEditingController();
    var selectedRating = 1;
    try {
      return await showDialog<_RatingDraft>(
        context: context,
        useRootNavigator: true,
        barrierDismissible: true,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (builderContext, setDialogState) {
              return AlertDialog(
                backgroundColor: const Color(0xFF111319),
                title: Text(
                  'Rate Product',
                  style: TextStyle(color: AppColours.primary, fontSize: 16.fSize),
                ),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        productName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: List.generate(5, (index) {
                          final value = index + 1;
                          return IconButton(
                            onPressed: () {
                              setDialogState(() => selectedRating = value);
                            },
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            icon: Icon(
                              value <= selectedRating ? Icons.star : Icons.star_border,
                              color: AppColours.primary,
                              size: 24,
                            ),
                          );
                        }),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: reviewController,
                        maxLines: 3,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Write a review (optional)',
                          hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                          filled: true,
                          fillColor: const Color(0xFF1A1D24),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: AppColours.primary.withOpacity(0.3)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: AppColours.primary.withOpacity(0.3)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: AppColours.primary),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      FocusScope.of(dialogContext).unfocus();
                      Navigator.of(
                        dialogContext,
                        rootNavigator: true,
                      ).pop();
                    },
                    child: const Text('Cancel'),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      FocusScope.of(dialogContext).unfocus();
                      Navigator.of(
                        dialogContext,
                        rootNavigator: true,
                      ).pop(
                        _RatingDraft(
                          rating: selectedRating,
                          review: reviewController.text.trim(),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColours.primary,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      minimumSize: const Size(88, 40),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text('Submit'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      // Dispose after dialog teardown completes.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        reviewController.dispose();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 8.h),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.arrow_back, color: AppColours.primary),
                  ),
                  Expanded(
                    child: Text(
                      'Order Details',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColours.primary,
                        fontSize: 18.fSize,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  SizedBox(width: 48.w),
                ],
              ),
            ),
            Container(
              height: 2,
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    Color(0xFFE6C27A).withValues(alpha: 0.15),
                    Color(0xFFE6C27A),
                    Color(0xFFE6C27A).withValues(alpha: 0.15),
                  ],
                ),
              ),
            ),
            Expanded(
              child: _buildBody(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(color: AppColours.primary),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 24.w),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 14.fSize),
              ),
              SizedBox(height: 16.h),
              OutlinedButton(
                onPressed: _loadOrder,
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: AppColours.primary.withValues(alpha: 0.9)),
                  foregroundColor: AppColours.primary,
                ),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final order = o;
    if (order == null) {
      return Center(
        child: Text(
          'Order not found',
          style: TextStyle(color: Colors.white70, fontSize: 14.fSize),
        ),
      );
    }

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 32.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SummaryCard(
            order: order,
            deliveryDateText: _formatDeliveryDate(order),
          ),
          // SizedBox(height: 14.h),
          // _JourneyTabBar(
          //   order: order,
          //   onTrackTap: () => Navigator.pushNamed(
          //     context,
          //     AppRoutes.orderTrackingScreen,
          //     arguments: order.id,
          //   ),
          // ),
          if (order.hasReturnFailed && !_isReturnSettled(order)) ...[
            SizedBox(height: 12.h),
            _ReturnFailedNotice(
              reason: order.rejectionReason,
            ),
          ] else if (order.isInReturnFlow) ...[
            if (_hasPickupDetails(order)) ...[
              SizedBox(height: 14.h),
              _buildPickupDetailsCard(order),
            ],
          ],
          SizedBox(height: 20.h),
          _buildItemsHeader(),
          SizedBox(height: 14.h),
          ..._buildSeparatedKitItemsCards(order),
          SizedBox(height: 18.h),
          _buildTrackButton(order),
          SizedBox(height: 24.h),
          _buildAmountPaidSummaryCard(order),
          SizedBox(height: 24.h),
          _buildDeliveryAddressSection(order),
        ],
      ),
    );
  }

  String _formatDeliveryDate(UserOrder order) {
    final dt = order.deliveryDate;
    final timeSlot = order.deliveryTime?.trim();
    if (dt != null) {
      final dd = dt.day.toString().padLeft(2, '0');
      final mm = dt.month.toString().padLeft(2, '0');
      final yy = (dt.year % 100).toString().padLeft(2, '0');
      if (timeSlot != null && timeSlot.isNotEmpty) {
        return '$dd/$mm/$yy ($timeSlot)';
      }
      return '$dd/$mm/$yy';
    }
    if (order.deliveryDateFormatted != null && order.deliveryDateFormatted != '-') {
      if (timeSlot != null && timeSlot.isNotEmpty) {
        return '${order.deliveryDateFormatted} ($timeSlot)';
      }
      return order.deliveryDateFormatted!;
    }
    return timeSlot?.isNotEmpty == true ? timeSlot! : '-';
  }

  String _formatOrderPlaced(DateTime? dt) {
    if (dt == null) return '-';
    final local = dt.toLocal();
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final month = months[local.month - 1];
    final day = local.day;
    final year = local.year;
    final hour12 = local.hour == 0 ? 12 : (local.hour > 12 ? local.hour - 12 : local.hour);
    final minute = local.minute.toString().padLeft(2, '0');
    final ampm = local.hour >= 12 ? 'PM' : 'AM';
    return '$month $day, $year, ${hour12.toString().padLeft(2, '0')}:$minute $ampm';
  }

  String _formatCurrency(num value) {
    return '₹ ${value.toStringAsFixed(value.truncateToDouble() == value ? 0 : 2)}';
  }

  Widget _buildItemsHeader() {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 1,
            color: const Color(0xFFD8B26A).withValues(alpha: 0.35),
          ),
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 12.w),
          child: Text(
            'ITEMS IN THIS ORDER',
            style: TextStyle(
              color: const Color(0xFFD8B26A),
              fontSize: 12.5.fSize,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
            ),
          ),
        ),
        Expanded(
          child: Container(
            height: 1,
            color: const Color(0xFFD8B26A).withValues(alpha: 0.35),
          ),
        ),
      ],
    );
  }

  bool _isItemKids(OrderLineItem item) {
    final type = item.itemType?.trim().toLowerCase();
    if (type == 'kids' || type == 'kid') return true;
    final cat = item.category?.trim().toLowerCase() ?? '';
    if (cat.contains('kids') || cat.contains('kid')) return true;
    final name = item.productName.trim().toLowerCase();
    if (name.contains('kids') ||
        name.contains('kid ') ||
        name.contains('baby') ||
        name.contains('infant') ||
        name.contains('girls') ||
        name.contains('boys')) {
      return true;
    }
    return false;
  }

  bool _isItemSubscription(OrderLineItem item, UserOrder order) {
    if (_isItemKids(item)) return false;
    final type = item.itemType?.trim().toLowerCase();
    if (type != null && type.isNotEmpty) {
      if (type == 'subscription') return true;
      if (type == 'non_subscription') return false;
    }
    final orderType = order.orderType?.trim().toUpperCase();
    if (orderType == 'SUBSCRIPTION') return true;
    if (orderType == 'NON_SUBSCRIPTION') return false;
    return order.title.toLowerCase().contains('subscription');
  }

  List<Widget> _buildSeparatedKitItemsCards(UserOrder order) {
    final items = order.lineItems ?? [];
    if (items.isEmpty) {
      final isSubOrder = order.orderType?.trim().toUpperCase() == 'SUBSCRIPTION' ||
          order.title.toLowerCase().contains('subscription');
      return [
        _buildSingleKitItemsCard(
          order: order,
          items: const [],
          badgeLabel: isSubOrder ? 'SUBSCRIPTION PLAN' : 'NON-SUBSCRIPTION PLAN',
          isSubscription: isSubOrder,
          isExpanded: _itemsExpanded,
          onToggleExpanded: () => setState(() => _itemsExpanded = !_itemsExpanded),
        ),
      ];
    }

    final kidsItems = items.where(_isItemKids).toList();
    final subItems = items.where((it) => !_isItemKids(it) && _isItemSubscription(it, order)).toList();
    final nonSubItems = items.where((it) => !_isItemKids(it) && !_isItemSubscription(it, order)).toList();

    final widgets = <Widget>[];

    if (subItems.isNotEmpty) {
      widgets.add(
        _buildSingleKitItemsCard(
          order: order,
          items: subItems,
          badgeLabel: 'SUBSCRIPTION PLAN',
          isSubscription: true,
          isExpanded: _subItemsExpanded,
          onToggleExpanded: () => setState(() => _subItemsExpanded = !_subItemsExpanded),
        ),
      );
    }

    if (nonSubItems.isNotEmpty) {
      if (widgets.isNotEmpty) {
        widgets.add(SizedBox(height: 14.h));
      }
      widgets.add(
        _buildSingleKitItemsCard(
          order: order,
          items: nonSubItems,
          badgeLabel: 'NON-SUBSCRIPTION PLAN',
          isSubscription: false,
          isExpanded: _nonSubItemsExpanded,
          onToggleExpanded: () => setState(() => _nonSubItemsExpanded = !_nonSubItemsExpanded),
        ),
      );
    }

    if (kidsItems.isNotEmpty) {
      if (widgets.isNotEmpty) {
        widgets.add(SizedBox(height: 14.h));
      }
      widgets.add(
        _buildSingleKitItemsCard(
          order: order,
          items: kidsItems,
          badgeLabel: 'KIDS NON RETURNABLE',
          pricePrefix: 'Subtotal',
          isSubscription: false,
          isExpanded: _kidsItemsExpanded,
          onToggleExpanded: () => setState(() => _kidsItemsExpanded = !_kidsItemsExpanded),
        ),
      );
    }

    return widgets;
  }

  Widget _buildSingleKitItemsCard({
    required UserOrder order,
    required List<OrderLineItem> items,
    required String badgeLabel,
    required bool isSubscription,
    required bool isExpanded,
    required VoidCallback onToggleExpanded,
    String? pricePrefix,
  }) {
    final garmentCount = items.isNotEmpty
        ? items.fold<int>(0, (sum, it) => sum + (it.quantity > 0 ? it.quantity : 1))
        : (order.totalGarmentsCount > 0 ? order.totalGarmentsCount : 1);
    num itemsTotal = 0;
    if (!isSubscription) {
      for (final item in items) {
        itemsTotal += item.lineTotal > 0 ? item.lineTotal : (item.unitPrice * item.quantity);
      }
      if (itemsTotal <= 0 && badgeLabel != 'KIDS NON RETURNABLE') {
        itemsTotal = order.subtotal > 0 ? order.subtotal : order.kitPrice;
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0C0D14),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFD8B26A).withValues(alpha: 0.30),
        ),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: onToggleExpanded,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
              child: Row(
                children: [
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                    decoration: BoxDecoration(
                      color: const Color(0xFF261E10),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: const Color(0xFFD8B26A).withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      badgeLabel,
                      style: TextStyle(
                        color: const Color(0xFFD8B26A),
                        fontSize: 9.fSize,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  SizedBox(width: 8.w),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1B1D28),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '$garmentCount ${garmentCount == 1 ? 'Garment' : 'Garments'}',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 10.fSize,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: const Color(0xFFD8B26A),
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
          if (isExpanded) ...[
            Container(
              height: 1,
              color: const Color(0xFFD8B26A).withValues(alpha: 0.15),
            ),
            Padding(
              padding: EdgeInsets.all(12.w),
              child: Column(
                children: items.map((item) {
                  return Padding(
                    padding: EdgeInsets.only(bottom: 12.h),
                    child: _LineItemRow(
                      item: item,
                      isSubscription: isSubscription,
                      showReviewRating: order.isDelivered,
                      alreadyRated: _ratedProductIds.contains(item.productId.trim()),
                      ratingValue: _ratedProductValues[item.productId.trim()],
                      onRateTap: _ratedProductIds.contains(item.productId.trim())
                          ? null
                          : () => _onRateTap(item),
                      onProductTap: () => _openProductDetails(item),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
          if (isSubscription || itemsTotal > 0) ...[
            Container(
              height: 1,
              color: const Color(0xFFD8B26A).withValues(alpha: 0.15),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
              child: Column(
                children: [
                  if (!isSubscription &&
                      badgeLabel != 'KIDS NON RETURNABLE' &&
                      order.securityDepositAmount > 0) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Security Deposit (Refundable)',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 11.5.fSize,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          '₹${order.securityDepositAmount.toInt()}',
                          style: TextStyle(
                            color: const Color(0xFFE6C27A),
                            fontSize: 12.fSize,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 6.h),
                  ],
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        isSubscription
                            ? 'Plan Coverage'
                            : (pricePrefix ?? 'Subtotal'),
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12.5.fSize,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (isSubscription)
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 7.w, vertical: 3.h),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0D2820),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '✓ Covered · ₹0',
                            style: TextStyle(
                              color: const Color(0xFF34D399),
                              fontSize: 10.5.fSize,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        )
                      else
                        Text(
                          _formatCurrency(itemsTotal),
                          style: TextStyle(
                            color: const Color(0xFFD8B26A),
                            fontSize: 14.fSize,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  bool _isReturnSettled(UserOrder order) {
    final status = (order.orderStatusRaw ?? '').trim().toUpperCase();
    final ret = (order.returnStatus ?? '').trim().toUpperCase();
    const settled = {'RETURNED', 'RETURNED_TO_IAP'};
    return settled.contains(status) || settled.contains(ret);
  }

  bool _hasPickupDetails(UserOrder order) {
    bool filled(String? value) => value != null && value.trim().isNotEmpty;
    return filled(order.pickupDate) ||
        filled(order.pickupTime) ||
        filled(order.pickupNote) ||
        filled(order.pickupMobile) ||
        filled(order.pickupFullName);
  }

  String _formatPickupDate(String raw) {
    final parsed = DateTime.tryParse(raw.trim());
    if (parsed == null) return raw.trim();
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final day = parsed.day.toString().padLeft(2, '0');
    return '$day ${months[parsed.month - 1]} ${parsed.year}';
  }

  Widget _buildPickupDetailsCard(UserOrder order) {
    final name = _cleanPickupValue(order.pickupFullName);
    final mobile = _cleanPickupValue(order.pickupMobile);
    final date = _cleanPickupValue(order.pickupDate);
    final time = _cleanPickupValue(order.pickupTime);
    final note = _cleanPickupValue(order.pickupNote);
    final address = _cleanPickupValue(order.addressLines);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: const Color(0xFF0C0D14),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFD8B26A).withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.assignment_return_outlined,
                color: const Color(0xFFD8B26A),
                size: 18.w,
              ),
              SizedBox(width: 8.w),
              Text(
                'PICKUP DETAILS',
                style: TextStyle(
                  color: const Color(0xFFD8B26A),
                  fontSize: 12.fSize,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          if (date != null || time != null) ...[
            SizedBox(height: 14.h),
            Row(
              children: [
                if (date != null)
                  Expanded(
                    child: _pickupValueTile(
                      label: 'PICKUP DATE',
                      value: _formatPickupDate(date),
                      icon: Icons.calendar_today_outlined,
                    ),
                  ),
                if (date != null && time != null) SizedBox(width: 10.w),
                if (time != null)
                  Expanded(
                    child: _pickupValueTile(
                      label: 'PICKUP TIME',
                      value: time,
                      icon: Icons.schedule_outlined,
                    ),
                  ),
              ],
            ),
          ],
          if (name != null) ...[
            SizedBox(height: 12.h),
            _pickupTextBlock('NAME', name),
          ],
          if (mobile != null) ...[
            SizedBox(height: 12.h),
            _pickupTextBlock('MOBILE', mobile),
          ],
          if (address != null) ...[
            SizedBox(height: 12.h),
            _pickupTextBlock('PICKUP ADDRESS', address),
          ],
          if (note != null) ...[
            SizedBox(height: 12.h),
            _pickupTextBlock('NOTE', note),
          ],
        ],
      ),
    );
  }

  Widget _pickupValueTile({
    required String label,
    required String value,
    required IconData icon,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: const Color(0xFF16181D),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFD8B26A).withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: const Color(0xFFD8B26A), size: 13),
              SizedBox(width: 6.w),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: const Color(0xFFD8B26A),
                    fontSize: 9.fSize,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 6.h),
          Text(
            value,
            style: TextStyle(
              color: Colors.white,
              fontSize: 13.fSize,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _pickupTextBlock(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: const Color(0xFFD8B26A),
            fontSize: 9.fSize,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
        SizedBox(height: 4.h),
        Text(
          value,
          style: TextStyle(
            color: Colors.white,
            fontSize: 13.fSize,
            fontWeight: FontWeight.w600,
            height: 1.35,
          ),
        ),
      ],
    );
  }

  String? _cleanPickupValue(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty || text.toLowerCase() == 'null') return null;
    return text;
  }

  Widget _buildTrackButton(UserOrder order) {
    final opensReturn = order.actionFlow == OrderActionFlow.delivered;
    final opensTracking = order.actionFlow == OrderActionFlow.forward ||
        order.actionFlow == OrderActionFlow.reverse;

    return SizedBox(
      height: 46.h,
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: opensReturn
            ? () => _openReturnOrder(order)
            : opensTracking
                ? () => Navigator.pushNamed(
                      context,
                      AppRoutes.orderTrackingScreen,
                      arguments: order.id,
                    )
                : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFD8B26A),
          disabledBackgroundColor: const Color(0xFFD8B26A),
          foregroundColor: Colors.black,
          disabledForegroundColor: Colors.black54,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 2,
        ),
        icon: Icon(
          opensReturn ? Icons.refresh_rounded : Icons.near_me_outlined,
          size: 18,
        ),
        label: Text(
          order.actionLabel,
          style: TextStyle(
            fontSize: 13.fSize,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }

  Future<void> _openReturnOrder(UserOrder order) async {
    final submitted = await Navigator.pushNamed(
      context,
      AppRoutes.returnOrderScreen,
      arguments: <String, dynamic>{
        'orderId': order.id,
        'orderNumber': order.orderIdDisplay,
      },
    );
    if (submitted == true && mounted) {
      await _loadOrder();
      if (!mounted) return;
      Navigator.pushNamed(
        context,
        AppRoutes.orderTrackingScreen,
        arguments: order.id,
      );
    }
  }

  Widget _buildAmountPaidSummaryCard(UserOrder order) {
    final items = order.lineItems ?? [];
    final kidsItems = items.where(_isItemKids).toList();
    final subItems = items.where((it) => !_isItemKids(it) && _isItemSubscription(it, order)).toList();
    final nonSubItems = items.where((it) => !_isItemKids(it) && !_isItemSubscription(it, order)).toList();
    final isSub = order.orderType?.trim().toUpperCase() == 'SUBSCRIPTION' ||
        order.title.toLowerCase().contains('subscription');
    final garmentCount = items.isNotEmpty
        ? items.fold<int>(0, (sum, it) => sum + (it.quantity > 0 ? it.quantity : 1))
        : (order.totalGarmentsCount > 0 ? order.totalGarmentsCount : 1);
    final subCount = subItems.fold<int>(0, (s, i) => s + (i.quantity > 0 ? i.quantity : 1));
    final nonSubCount = nonSubItems.fold<int>(0, (s, i) => s + (i.quantity > 0 ? i.quantity : 1));
    final kidsCount = kidsItems.fold<int>(0, (s, i) => s + (i.quantity > 0 ? i.quantity : 1));

    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: const Color(0xFF0C0D14),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFD8B26A).withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38.w,
                height: 38.w,
                decoration: BoxDecoration(
                  color: const Color(0xFF261F12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: const Color(0xFFD8B26A).withValues(alpha: 0.6),
                  ),
                ),
                child: const Icon(
                  Icons.credit_card_rounded,
                  color: Color(0xFFD8B26A),
                  size: 20,
                ),
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AMOUNT PAID SUMMARY',
                      style: TextStyle(
                        color: const Color(0xFFD8B26A),
                        fontSize: 14.5.fSize,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.0,
                      ),
                    ),
                    SizedBox(height: 2.h),
                    Text(
                      'Payment receipt & billing summary',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 10.5.fSize,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 7.w, vertical: 3.h),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D2820),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFF10B981).withValues(alpha: 0.6),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.check_circle_outline_rounded,
                      color: Color(0xFF34D399),
                      size: 13,
                    ),
                    SizedBox(width: 4.w),
                    Text(
                      isSub ? 'COVERED BY MEMBERSHIP' : 'PAID ONLINE',
                      style: TextStyle(
                        color: const Color(0xFF34D399),
                        fontSize: 9.fSize,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 16.h),
          Container(
            height: 1,
            color: const Color(0xFFD8B26A).withValues(alpha: 0.20),
          ),
          SizedBox(height: 14.h),
          Container(
            padding: EdgeInsets.all(12.w),
            decoration: BoxDecoration(
              color: const Color(0xFF11121A),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: const Color(0xFFD8B26A).withValues(alpha: 0.25),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'PAYMENT INFORMATION',
                  style: TextStyle(
                    color: const Color(0xFFD8B26A),
                    fontSize: 11.5.fSize,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                SizedBox(height: 10.h),
                _paymentInfoRow(
                  'Payment Method',
                  isSub
                      ? 'Wardrobe Membership Plan'
                      : (order.paymentMethod?.isNotEmpty == true
                          ? (order.paymentMethod!.toUpperCase() == 'ONLINE'
                              ? 'Online Payment'
                              : order.paymentMethod!)
                          : 'Online Payment'),
                ),
                _paymentInfoRow(
                  'Invoice Number',
                  order.invoiceNumber?.isNotEmpty == true
                      ? order.invoiceNumber!
                      : 'INV-${order.orderIdDisplay}',
                ),
                _paymentInfoRow(
                  'Transaction ID',
                  order.transactionId?.isNotEmpty == true
                      ? order.transactionId!
                      : (order.orderIdDisplay),
                  isGold: true,
                ),
                _paymentInfoRow(
                  'Order Placed',
                  _formatOrderPlaced(order.createdAt),
                ),
                _paymentInfoRow(
                  'Delivery Slot',
                  _formatDeliveryDate(order),
                ),
              ],
            ),
          ),
          SizedBox(height: 12.h),
          Container(
            padding: EdgeInsets.all(12.w),
            decoration: BoxDecoration(
              color: const Color(0xFF11121A),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: const Color(0xFFD8B26A).withValues(alpha: 0.25),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'BILLING SUMMARY',
                  style: TextStyle(
                    color: const Color(0xFFD8B26A),
                    fontSize: 11.5.fSize,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                SizedBox(height: 10.h),
                if (subItems.isNotEmpty)
                  _billingSummaryRow(
                    'Subscription Kit Garments ($subCount ${subCount == 1 ? 'item' : 'items'})',
                    '₹0 (Plan Included)',
                    isGreen: true,
                  ),
                if (nonSubItems.isNotEmpty)
                  _billingSummaryRow(
                    'Non-Subscription Garments ($nonSubCount ${nonSubCount == 1 ? 'item' : 'items'})',
                    _formatCurrency(order.subtotal > 0 ? order.subtotal : order.kitPrice),
                  ),
                if (kidsItems.isNotEmpty)
                  _billingSummaryRow(
                    'Kids Collection ($kidsCount ${kidsCount == 1 ? 'item' : 'items'})',
                    _formatCurrency(kidsItems.fold<num>(0, (sum, i) => sum + (i.lineTotal > 0 ? i.lineTotal : (i.unitPrice * i.quantity)))),
                  ),
                if (subItems.isEmpty && nonSubItems.isEmpty && kidsItems.isEmpty)
                  _billingSummaryRow(
                    'Kit Garments ($garmentCount ${garmentCount == 1 ? 'item' : 'items'})',
                    _formatCurrency(order.subtotal > 0 ? order.subtotal : order.kitPrice),
                  ),
                _billingSummaryRow(
                  'Delivery Fee',
                  order.deliveryCharge > 0
                      ? _formatCurrency(order.deliveryCharge)
                      : 'FREE',
                  isGreen: order.deliveryCharge <= 0,
                ),
                _billingSummaryRow(
                  'Taxes (GST)',
                  order.taxAmount > 0
                      ? _formatCurrency(order.taxAmount)
                      : 'Included',
                ),
                if (order.securityDepositAmount > 0) ...[
                  SizedBox(height: 8.h),
                  Container(
                    padding: EdgeInsets.all(10.w),
                    decoration: BoxDecoration(
                      color: const Color(0xFF161824),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: const Color(0xFFD8B26A).withValues(alpha: 0.5),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        InkWell(
                          onTap: () => setState(() => _depositExpanded = !_depositExpanded),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.shield_outlined,
                                color: Color(0xFFD8B26A),
                                size: 16,
                              ),
                              SizedBox(width: 6.w),
                              Expanded(
                                child: Text(
                                  'Refundable Security Deposit (Temporary Hold)',
                                  style: TextStyle(
                                    color: const Color(0xFFD8B26A),
                                    fontSize: 11.fSize,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              Text(
                                _formatCurrency(order.securityDepositAmount),
                                style: TextStyle(
                                  color: const Color(0xFFD8B26A),
                                  fontSize: 12.fSize,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(width: 4.w),
                              Icon(
                                _depositExpanded
                                    ? Icons.keyboard_arrow_up_rounded
                                    : Icons.keyboard_arrow_down_rounded,
                                color: const Color(0xFFD8B26A),
                                size: 18,
                              ),
                            ],
                          ),
                        ),
                        if (_depositExpanded) ...[
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
                              SizedBox(width: 8.w),
                              Container(
                                padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF2A2214),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: const Color(0xFFD8B26A).withValues(alpha: 0.5),
                                  ),
                                ),
                                child: Text(
                                  order.securityDepositRefundStatus == 'REFUNDED'
                                      ? 'REFUNDED'
                                      : 'HOLD ACTIVE · REFUNDABLE',
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
                                color: const Color(0xFF10B981).withValues(alpha: 0.35),
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
                                      color: const Color(0xFF34D399),
                                      fontSize: 10.5.fSize,
                                      fontWeight: FontWeight.w500,
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
              ],
            ),
          ),
          SizedBox(height: 14.h),
          Container(
            height: 1,
            color: const Color(0xFFD8B26A).withValues(alpha: 0.20),
          ),
          SizedBox(height: 14.h),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Total Amount Paid',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14.fSize,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 2.h),
                    Text(
                      'Paid via Secure Payment',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 10.5.fSize,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 8.w),
              Text(
                _formatCurrency(order.totalAmount),
                style: TextStyle(
                  color: const Color(0xFFD8B26A),
                  fontSize: 22.fSize,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _paymentInfoRow(String label, String value, {bool isGold = false}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120.w,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.white60,
                fontSize: 11.5.fSize,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: isGold ? const Color(0xFFD8B26A) : Colors.white,
                fontSize: 11.5.fSize,
                fontWeight: isGold ? FontWeight.bold : FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _billingSummaryRow(
    String label,
    String value, {
    bool isGreen = false,
    bool isBold = false,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4.h),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: isBold ? Colors.white : Colors.white70,
                fontSize: 12.fSize,
                fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ),
          SizedBox(width: 8.w),
          Text(
            value,
            style: TextStyle(
              color: isGreen
                  ? const Color(0xFF34D399)
                  : (isBold ? const Color(0xFFD8B26A) : Colors.white),
              fontSize: 12.fSize,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeliveryAddressSection(UserOrder order) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Delivery Addresses',
          style: CustomTextStyles.montserratSemiBold.copyWith(
            fontSize: 15,
            color: Colors.white,
          ),
        ),
        SizedBox(height: 10.h),
        Text(
          order.addressLabel,
          style: TextStyle(
            color: AppColours.primary,
            fontSize: 15.fSize,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: 6.h),
        Text(
          order.addressLines.isNotEmpty
              ? order.addressLines
              : 'Address not available',
          style: CustomTextStyles.montserratSemiBold.copyWith(
            fontSize: 13.5,
            color: Colors.white70,
          ),
        ),
        if (order.mobileDisplay.isNotEmpty) ...[
          SizedBox(height: 6.h),
          Text(
            'Mobile Number: ${order.mobileDisplay}',
            style: CustomTextStyles.montserratSemiBold.copyWith(
              fontSize: 12,
              color: Colors.white70,
            ),
          ),
        ],
        SizedBox(height: 20.h),
        Container(
          height: 1,
          color: AppColours.primary.withValues(alpha: 0.35),
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final UserOrder order;
  final String deliveryDateText;

  const _SummaryCard({
    required this.order,
    required this.deliveryDateText,
  });

  Widget _buildCoverImage(String source) {
    final isNetwork =
        source.startsWith('http://') || source.startsWith('https://');
    if (isNetwork) {
      return Image.network(source, fit: BoxFit.cover);
    }
    return Image.asset(source, fit: BoxFit.cover);
  }

  Widget _buildCoverThumb() {
    final paths = order.coverImageAssets;
    const thumbW = 96.0;
    const thumbH = 96.0;

    Widget child;
    if (paths.isEmpty) {
      child = ColoredBox(
        color: const Color(0xFF1A1A22),
        child: const Center(
          child: Icon(
            Icons.shopping_bag_outlined,
            color: Color(0xFFD8B26A),
            size: 32,
          ),
        ),
      );
    } else if (paths.length == 1) {
      child = _buildCoverImage(paths.first);
    } else {
      child = GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        itemCount: 4,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 1,
          mainAxisSpacing: 1,
          childAspectRatio: 1.0,
        ),
        itemBuilder: (context, index) {
          final path = paths[index % paths.length];
          return _buildCoverImage(path);
        },
      );
    }

    return SizedBox(
      width: thumbW.w,
      height: thumbH.w,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFD8B26A), width: 1.2),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(9),
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final statusText = (order.isInReturnFlow
            ? (order.orderStatusRaw ?? 'PICKUP SCHEDULED')
            : (order.orderStatusRaw ??
                (order.isDelivered ? 'DELIVERED' : 'CONFIRMED')))
        .replaceAll('_', ' ')
        .toUpperCase();

    return Container(
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: const Color(0xFF0C0D14),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFD8B26A).withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCoverThumb(),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  order.title,
                  style: TextStyle(
                    color: const Color(0xFFD8B26A),
                    fontSize: 16.fSize,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 6.h),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6.w,
                  runSpacing: 4.h,
                  children: [
                    Text(
                      'Order Id: ${order.orderIdDisplay}',
                      style: CustomTextStyles.montserratSemiBold.copyWith(
                        fontSize: 12,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 4.h),
                Builder(
                  builder: (_) {
                    final lineItems = order.lineItems;
                    final totalGarments = (lineItems != null && lineItems.isNotEmpty)
                        ? lineItems.fold<int>(
                            0,
                            (sum, it) => sum + (it.quantity > 0 ? it.quantity : 1),
                          )
                        : (order.totalGarmentsCount > 0
                            ? order.totalGarmentsCount
                            : (int.tryParse(order.attributeValue) ?? 1));
                    return Text(
                      'No of Garments: $totalGarments',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12.fSize,
                        fontWeight: FontWeight.w500,
                      ),
                    );
                  },
                ),
                SizedBox(height: 4.h),
                Text(
                  'Delivery Date: $deliveryDateText',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12.fSize,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(height: 8.h),
                Container(
                  padding:
                      EdgeInsets.symmetric(horizontal: 10.w, vertical: 3.h),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1B160C),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: const Color(0xFFD8B26A).withValues(alpha: 0.5),
                    ),
                  ),
                  child: Text(
                    'ORDER STATUS : $statusText',
                    style: TextStyle(
                      color: const Color(0xFFE6C27A),
                      fontSize: 10.fSize,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _JourneyTabBar extends StatelessWidget {
  final UserOrder order;
  final VoidCallback onTrackTap;

  const _JourneyTabBar({
    required this.order,
    required this.onTrackTap,
  });

  @override
  Widget build(BuildContext context) {
    final inReturn = order.isInReturnFlow;

    return Container(
      padding: EdgeInsets.all(4.w),
      decoration: BoxDecoration(
        color: const Color(0xFF0C0D14),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: const Color(0xFFD8B26A).withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: onTrackTap,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 8.h),
                decoration: BoxDecoration(
                  color: inReturn ? Colors.transparent : const Color(0xFF181A24),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.inventory_2_outlined,
                        size: 14,
                        color: inReturn ? Colors.white70 : const Color(0xFFD8B26A),
                      ),
                      SizedBox(width: 4.w),
                      Text(
                        'DELIVERY JOURNEY',
                        style: TextStyle(
                          color: inReturn ? Colors.white70 : const Color(0xFFD8B26A),
                          fontSize: 10.5.fSize,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(width: 5.w),
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 5.w, vertical: 1.h),
                        decoration: BoxDecoration(
                          color: const Color(0xFF202A44),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          inReturn ? 'DONE' : 'ACTIVE',
                          style: TextStyle(
                            color: const Color(0xFF60A5FA),
                            fontSize: 9.fSize,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SizedBox(width: 4.w),
          Expanded(
            child: InkWell(
              onTap: onTrackTap,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 8.h),
                decoration: BoxDecoration(
                  color: inReturn ? const Color(0xFF9E782F) : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.cached_rounded,
                        size: 15,
                        color: inReturn ? Colors.black : Colors.white60,
                      ),
                      SizedBox(width: 4.w),
                      Text(
                        'RETURN & SUPPORT',
                        style: TextStyle(
                          color: inReturn ? Colors.black : Colors.white70,
                          fontSize: 10.5.fSize,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (inReturn) ...[
                        SizedBox(width: 5.w),
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 5.w, vertical: 1.h),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'IN PROGRESS',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 9.fSize,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReturnFailedNotice extends StatelessWidget {
  final String? reason;

  const _ReturnFailedNotice({this.reason});

  @override
  Widget build(BuildContext context) {
    final cleanReason = reason?.trim();
    return Container(
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1416),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.redAccent.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36.w,
            height: 36.w,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.redAccent.withValues(alpha: 0.15),
              border: Border.all(
                color: Colors.redAccent.withValues(alpha: 0.4),
              ),
            ),
            child: const Icon(
              Icons.error_outline_rounded,
              color: Colors.redAccent,
              size: 20,
            ),
          ),
          SizedBox(width: 10.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Return Attempt Failed',
                  style: TextStyle(
                    color: Colors.redAccent,
                    fontSize: 13.fSize,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 2.h),
                Text(
                  (cleanReason != null && cleanReason.isNotEmpty)
                      ? 'Reason: $cleanReason. You can reattempt returning your order below.'
                      : 'Your previous return attempt could not be completed. You can reattempt returning your order below.',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 11.fSize,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReturnInProgressNotice extends StatelessWidget {
  final UserOrder order;
  final VoidCallback onTrackTap;

  const _ReturnInProgressNotice({
    required this.order,
    required this.onTrackTap,
  });

  @override
  Widget build(BuildContext context) {
    final pickupDateStr = order.pickupDate?.trim();
    final pickupTimeStr = order.pickupTime?.trim();
    final pickupFormatted = (pickupDateStr != null && pickupDateStr.isNotEmpty)
        ? '$pickupDateStr at ${pickupTimeStr ?? ''}'.trim()
        : 'Scheduled for return';

    return Container(
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: const Color(0xFF0E0E18),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFD8B26A).withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36.w,
            height: 36.w,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF2A2214),
              border: Border.all(
                color: const Color(0xFFD8B26A).withValues(alpha: 0.5),
              ),
            ),
            child: const Icon(
              Icons.sync_rounded,
              color: Color(0xFFD8B26A),
              size: 20,
            ),
          ),
          SizedBox(width: 10.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding:
                          EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2B2212),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        (order.orderStatusRaw ?? 'PICKUP SCHEDULED')
                            .replaceAll('_', ' '),
                        style: TextStyle(
                          color: const Color(0xFFE6C27A),
                          fontSize: 9.5.fSize,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    // SizedBox(width: 6.w),
                    // Flexible(
                    //   child: Text(
                    //     'RETURN IN PROGRESS',
                    //     overflow: TextOverflow.ellipsis,
                    //     style: TextStyle(
                    //       color: const Color(0xFFD8B26A),
                    //       fontSize: 11.fSize,
                    //       fontWeight: FontWeight.bold,
                    //     ),
                    //   ),
                    // ),
                  ],
                ),
                SizedBox(height: 4.h),
                Text(
                  'Pickup scheduled for $pickupFormatted',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 11.fSize,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: 8.w),
          OutlinedButton(
            onPressed: onTrackTap,
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFFD8B26A)),
              padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'TRACK LIVE',
                  style: TextStyle(
                    color: const Color(0xFFD8B26A),
                    fontSize: 10.fSize,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(width: 4.w),
                const Icon(
                  Icons.arrow_forward_rounded,
                  color: Color(0xFFD8B26A),
                  size: 12,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LineItemRow extends StatelessWidget {
  final OrderLineItem item;
  final bool isSubscription;
  final bool showReviewRating;
  final bool alreadyRated;
  final int? ratingValue;
  final VoidCallback? onRateTap;
  final VoidCallback? onProductTap;

  const _LineItemRow({
    required this.item,
    this.isSubscription = false,
    required this.showReviewRating,
    this.alreadyRated = false,
    this.ratingValue,
    this.onRateTap,
    this.onProductTap,
  });

  Widget _buildImage() {
    final source = item.imageAsset;
    final isNetwork =
        source.startsWith('http://') || source.startsWith('https://');
    if (isNetwork) {
      return Image.network(
        source,
        width: 62.w,
        height: 62.w,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _placeholder(),
      );
    }
    if (source.isNotEmpty) {
      return Image.asset(
        source,
        width: 62.w,
        height: 62.w,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _placeholder(),
      );
    }
    return _placeholder();
  }

  Widget _placeholder() {
    return ColoredBox(
      color: const Color(0xFF1A1A22),
      child: SizedBox(
        width: 62.w,
        height: 62.w,
        child: const Icon(
          Icons.checkroom_rounded,
          color: Color(0xFFD8B26A),
          size: 24,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: InkWell(
            onTap: onProductTap,
            borderRadius: BorderRadius.circular(8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: const Color(0xFFD8B26A).withValues(alpha: 0.35),
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: _buildImage(),
                  ),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.productName,
                        style: TextStyle(
                          color: const Color(0xFFD8B26A),
                          fontSize: 14.fSize,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 4.h),
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8.w,
                        children: [
                          Text(
                            'Size: ${item.sizeLabel != '-' ? item.sizeLabel : 'Standard'}',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 11.5.fSize,
                            ),
                          ),
                          Text(
                            'Qty: ${item.quantity}',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 11.5.fSize,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (showReviewRating) ...[
          SizedBox(width: 8.w),
          _RateProductBox(
            alreadyRated: alreadyRated,
            ratingValue: ratingValue,
            onTap: onRateTap,
          ),
        ] else if (isSubscription) ...[
          SizedBox(width: 8.w),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 7.w, vertical: 3.h),
            decoration: BoxDecoration(
              color: const Color(0xFF0D2820),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '₹0 Covered',
              style: TextStyle(
                color: const Color(0xFF34D399),
                fontSize: 10.fSize,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _RateProductBox extends StatelessWidget {
  final bool alreadyRated;
  final int? ratingValue;
  final VoidCallback? onTap;

  const _RateProductBox({
    this.alreadyRated = false,
    this.ratingValue,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: alreadyRated ? null : onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 106.w,
        padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 7.h),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: AppColours.primary.withValues(alpha: 0.40),
          ),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                5,
                (i) => Padding(
                  padding: EdgeInsets.symmetric(horizontal: 0.5.w),
                  child: Icon(
                    i < (ratingValue ?? 0) ? Icons.star : Icons.star_border,
                    color: AppColours.primary,
                    size: 14,
                  ),
                ),
              ),
            ),
            SizedBox(height: 4.h),
            Text(
              alreadyRated
                  ? ((ratingValue ?? 0) > 0
                      ? 'Rated ${ratingValue!}/5'
                      : 'Rated')
                  : 'Rate this Product',
              textAlign: TextAlign.center,
              style: CustomTextStyles.montserratRegular.copyWith(
                fontSize: 10,
                color: const Color(0xFFF5E6C8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RatingDraft {
  final int rating;
  final String review;

  const _RatingDraft({
    required this.rating,
    required this.review,
  });
}
