import 'package:nomowear/core/app_export.dart';
import 'package:nomowear/core/network/api_exception.dart';
import 'package:nomowear/core/services/razorpay_service.dart';
import 'package:nomowear/core/utils/api_id_utils.dart';
import 'package:nomowear/features/auth/data/models/customer.dart';
import 'package:nomowear/features/orders/data/models/reattempt_quote.dart';
import 'package:nomowear/features/orders/data/models/refund_status_result.dart';
import 'package:nomowear/features/orders/data/order_repository.dart';
import 'package:nomowear/features/orders/data/pending_refund_store.dart';
import 'package:nomowear/features/orders/data/pending_return_store.dart';
import 'package:nomowear/features/orders/data/user_order_mapper.dart';
import 'package:nomowear/features/products/data/product_cache.dart';
import 'package:nomowear/features/products/data/product_mapper.dart';
import 'package:nomowear/features/products/data/product_repository.dart';
import 'package:nomowear/features/profile/data/profile_repository.dart';
import 'package:nomowear/features/profile/domain/order_action.dart';
import 'package:nomowear/features/profile/domain/user_order.dart';
import 'package:nomowear/features/orders/presentation/widgets/no_return_blocked_dialog.dart';
import 'package:nomowear/features/profile/domain/saved_address.dart';
import 'package:nomowear/features/wardrobe/presentation/screens/product_details_screen.dart';
import 'package:nomowear/features/wardrobe/presentation/screens/wardrobe_screen.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

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
  final RazorpayService _razorpayService = RazorpayService();
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

  String? _pendingReattemptOrderId;
  String? _pendingReattemptDeliveryDate;
  String? _pendingReattemptDeliveryTime;
  bool _isReattemptActionLoading = false;
  RefundStatusResult? _refundStatus;

  @override
  void initState() {
    super.initState();
    _itemsExpanded = true;
    _subItemsExpanded = true;
    _nonSubItemsExpanded = true;
    _kidsItemsExpanded = true;
    _depositExpanded = true;
    _razorpayService.init(
      onSuccess: _onRazorpayPaymentSuccess,
      onFailure: _onRazorpayPaymentFailure,
    );
    _loadOrder();
  }

  @override
  void dispose() {
    _razorpayService.dispose();
    super.dispose();
  }

  Future<void> _loadOrder() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await PendingReturnStore.instance.ensureLoaded();
      await PendingRefundStore.instance.ensureLoaded();
      final detail = await _orderRepository.getOrderDetail(widget.orderId);
      final customer = await _profileRepository.getProfile();
      final mapped = UserOrderMapper.fromHistoryItem(detail, customer: customer);
      final ratedRatings = await _loadRatedProductRatings(mapped);

      RefundStatusResult? refundStatus;
      final waitlistNum = mapped.waitlistNumber ??
          PendingRefundStore.instance.getWaitlistNumber(mapped.id);
      if (waitlistNum != null && waitlistNum.trim().isNotEmpty) {
        try {
          refundStatus = await _orderRepository.getRefundStatus(waitlistNum);
        } catch (_) {
          refundStatus = RefundStatusResult(
            status: 'PENDING',
            waitlistNumber: waitlistNum,
          );
        }
      }

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
        _refundStatus = refundStatus;
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
          if (order.isReturnEscalated) ...[
            SizedBox(height: 12.h),
            _buildReturnEscalatedWarningCard(order),
          ],
          if (_refundStatus != null) ...[
            SizedBox(height: 12.h),
            _buildRefundStatusCard(_refundStatus!, order),
          ],
          if (order.isDeliveryReattemptEligible) ...[
            SizedBox(height: 12.h),
            _buildDeliveryReattemptBanner(order),
          ],
          if (order.isReturnReattemptPending) ...[
            SizedBox(height: 12.h),
            _buildReturnReattemptPendingBanner(),
          ] else if (order.isReturnFailed && !_isReturnSettled(order)) ...[
            SizedBox(height: 12.h),
            _buildReturnFailedBanner(order),
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
          _buildActionButtons(order),
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

  Widget _buildRefundStatusCard(RefundStatusResult status, UserOrder order) {
    Color badgeColor;
    Color badgeBg;
    String badgeText;
    IconData badgeIcon;
    String descText;

    if (status.isApproved) {
      badgeColor = const Color(0xFF10B981);
      badgeBg = const Color(0xFF10B981).withValues(alpha: 0.15);
      badgeText = 'REFUND APPROVED';
      badgeIcon = Icons.check_circle_rounded;
      descText =
          'Your refund request has been approved. The amount will be credited to your original payment method.';
    } else if (status.isRejected) {
      badgeColor = const Color(0xFFEF4444);
      badgeBg = const Color(0xFFEF4444).withValues(alpha: 0.15);
      badgeText = 'REFUND REJECTED';
      badgeIcon = Icons.cancel_rounded;
      descText =
          'Your refund request could not be approved. Please contact customer support for further assistance.';
    } else {
      badgeColor = const Color(0xFFF59E0B);
      badgeBg = const Color(0xFFF59E0B).withValues(alpha: 0.15);
      badgeText = 'REFUND PENDING APPROVAL';
      badgeIcon = Icons.hourglass_top_rounded;
      descText =
          'Your cancellation & refund request is under review by our operations team. You will be notified once processed.';
    }

    return Container(
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: const Color(0xFF12141C),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: badgeColor.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: badgeColor.withValues(alpha: 0.6)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(badgeIcon, color: badgeColor, size: 14),
                    SizedBox(width: 5.w),
                    Text(
                      badgeText,
                      style: TextStyle(
                        color: badgeColor,
                        fontSize: 10.5.fSize,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Text(
                'REFUND',
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: 10.fSize,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
          SizedBox(height: 10.h),
          Text(
            descText,
            style: TextStyle(
              color: Colors.white70,
              fontSize: 12.fSize,
              height: 1.35,
            ),
          ),
          SizedBox(height: 10.h),
          Divider(color: Colors.white.withValues(alpha: 0.08), height: 1),
          SizedBox(height: 10.h),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'WAITLIST NUMBER',
                    style: TextStyle(
                      color: Colors.white38,
                      fontSize: 9.5.fSize,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                    ),
                  ),
                  SizedBox(height: 2.h),
                  Text(
                    status.waitlistNumber,
                    style: TextStyle(
                      color: const Color(0xFFD8B26A),
                      fontSize: 13.fSize,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'REFUND AMOUNT',
                    style: TextStyle(
                      color: Colors.white38,
                      fontSize: 9.5.fSize,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                    ),
                  ),
                  SizedBox(height: 2.h),
                  Text(
                    '₹${status.amount ?? order.totalAmount}',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13.fSize,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDeliveryReattemptBanner(UserOrder order) {
    return Container(
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFF261D10),
            Color(0xFF1A1510),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFD8B26A).withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36.w,
                height: 36.w,
                decoration: BoxDecoration(
                  color: const Color(0xFFD8B26A).withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFFD8B26A).withValues(alpha: 0.5),
                  ),
                ),
                child: const Icon(
                  Icons.replay_rounded,
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
                      'Delivery Attempt Failed / Returned',
                      style: TextStyle(
                        color: const Color(0xFFD8B26A),
                        fontSize: 13.5.fSize,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 2.h),
                    Text(
                      'Schedule a new delivery date and time slot to receive your items.',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 11.5.fSize,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildReturnEscalatedWarningCard(UserOrder order) {
    return Container(
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: const Color(0xFF281216),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFEF4444),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFEF4444).withValues(alpha: 0.18),
            blurRadius: 16,
            spreadRadius: 1,
          ),
        ],
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
                  color: const Color(0xFFEF4444).withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFFEF4444).withValues(alpha: 0.5),
                  ),
                ),
                child: const Center(
                  child: Text(
                    '⚠️',
                    style: TextStyle(fontSize: 18),
                  ),
                ),
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 8.w,
                        vertical: 3.h,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF45151A),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: const Color(0xFFEF4444).withValues(alpha: 0.4),
                        ),
                      ),
                      child: Text(
                        'NO RETURN = NO NEXT DISPATCH',
                        style: TextStyle(
                          color: const Color(0xFFFCA5A5),
                          fontSize: 9.5.fSize,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.7,
                        ),
                      ),
                    ),
                    SizedBox(height: 5.h),
                    Text(
                      'Action Required: Return Escalated',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13.5.fSize,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 10.h),
          Text(
            'Multiple pickup attempts have failed. Under our NO RETURN = NO NEXT DISPATCH policy, new bookings and deliveries are currently blocked until this kit is returned.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 12.fSize,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReturnFailedBanner(UserOrder order) {
    final scheduledDate = order.pickupDate?.trim().isNotEmpty == true
        ? order.pickupDate!.trim()
        : (order.deliveryDateFormatted?.trim().isNotEmpty == true
            ? order.deliveryDateFormatted!.trim()
            : 'Scheduled Date');
    final scheduledTime = order.pickupTime?.trim().isNotEmpty == true
        ? order.pickupTime!.trim()
        : (order.deliveryTime?.trim().isNotEmpty == true
            ? order.deliveryTime!.trim()
            : 'Scheduled Slot');
    final cleanReason = order.rejectionReason?.trim();

    return Container(
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1416),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFEF4444).withValues(alpha: 0.5),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36.w,
                height: 36.w,
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFFEF4444).withValues(alpha: 0.4),
                  ),
                ),
                child: const Icon(
                  Icons.error_outline_rounded,
                  color: Color(0xFFEF4444),
                  size: 20,
                ),
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'RETURN FAILED',
                      style: TextStyle(
                        color: const Color(0xFFEF4444),
                        fontSize: 13.5.fSize,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                      ),
                    ),
                    SizedBox(height: 2.h),
                    Text(
                      'Pickup scheduled for $scheduledDate at $scheduledTime was not completed.',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 11.5.fSize,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (cleanReason != null && cleanReason.isNotEmpty) ...[
            SizedBox(height: 8.h),
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
              decoration: BoxDecoration(
                color: const Color(0xFF28181A),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Failure Reason: $cleanReason',
                style: TextStyle(
                  color: Colors.white60,
                  fontSize: 11.fSize,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildReturnReattemptPendingBanner() {
    return Container(
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1A10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFF59E0B).withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36.w,
            height: 36.w,
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.4),
              ),
            ),
            child: const Icon(
              Icons.hourglass_top_rounded,
              color: Color(0xFFF59E0B),
              size: 18,
            ),
          ),
          SizedBox(width: 10.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pickup Reschedule In Progress',
                  style: TextStyle(
                    color: const Color(0xFFF59E0B),
                    fontSize: 13.fSize,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 3.h),
                Text(
                  'Your request to reschedule the return pickup has been submitted and is currently being processed by our operations team.',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 11.5.fSize,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(UserOrder order) {
    final isDeliveryReattempt = order.isDeliveryReattemptEligible;
    final isReturnPending = order.isReturnReattemptPending;
    final isReturnReattempt =
        !isReturnPending && order.isReturnFailed && !_isReturnSettled(order);
    final opensReturn =
        !isReturnReattempt && order.actionFlow == OrderActionFlow.delivered;
    final opensTracking = !isDeliveryReattempt &&
        !isReturnReattempt &&
        (order.actionFlow == OrderActionFlow.forward ||
            order.actionFlow == OrderActionFlow.reverse);

    final showRefundButton = order.isRefundEligible && _refundStatus == null;

    String primaryButtonLabel;
    IconData primaryButtonIcon;
    VoidCallback? onPrimaryPressed;

    if (isDeliveryReattempt) {
      primaryButtonLabel = 'Schedule Delivery Reattempt';
      primaryButtonIcon = Icons.replay_rounded;
      onPrimaryPressed = _isReattemptActionLoading
          ? null
          : () => _startDeliveryReattemptFlow(order);
    } else if (isReturnPending) {
      primaryButtonLabel = 'Pickup Reschedule In Progress';
      primaryButtonIcon = Icons.hourglass_top_rounded;
      onPrimaryPressed = null;
    } else if (isReturnReattempt) {
      primaryButtonLabel = '⇪ REATTEMPT PICKUP';
      primaryButtonIcon = Icons.upgrade_rounded;
      onPrimaryPressed = () => _openReattemptPickupBottomSheet(order);
    } else if (opensReturn) {
      primaryButtonLabel = 'Request Kit Return Pickup';
      primaryButtonIcon = Icons.refresh_rounded;
      onPrimaryPressed = () => _openReturnOrder(order);
    } else if (opensTracking) {
      primaryButtonLabel = order.actionLabel;
      primaryButtonIcon = Icons.near_me_outlined;
      onPrimaryPressed = () => Navigator.pushNamed(
            context,
            AppRoutes.orderTrackingScreen,
            arguments: order.id,
          );
    } else {
      primaryButtonLabel = order.actionLabel;
      primaryButtonIcon = Icons.near_me_outlined;
      onPrimaryPressed = null;
    }

    return Column(
      children: [
        SizedBox(
          height: 48.h,
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: onPrimaryPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD8B26A),
              disabledBackgroundColor: const Color(0xFF4A402D),
              foregroundColor: Colors.black,
              disabledForegroundColor: Colors.white38,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 2,
            ),
            icon: Icon(primaryButtonIcon, size: 18),
            label: Text(
              primaryButtonLabel,
              style: TextStyle(
                fontSize: 13.fSize,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),
        if (showRefundButton) ...[
          SizedBox(height: 12.h),
          SizedBox(
            height: 44.h,
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _openRefundBottomSheet(order),
              style: OutlinedButton.styleFrom(
                side: BorderSide(
                  color: const Color(0xFFD8B26A).withValues(alpha: 0.6),
                ),
                foregroundColor: const Color(0xFFD8B26A),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.currency_rupee_rounded, size: 17),
              label: Text(
                'Request Refund / Cancellation',
                style: TextStyle(
                  fontSize: 12.5.fSize,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ),
        ],
      ],
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

  Future<void> _openRescheduleReturnOrder(UserOrder order) async {
    final submitted = await Navigator.pushNamed(
      context,
      AppRoutes.returnOrderScreen,
      arguments: <String, dynamic>{
        'orderId': order.id,
        'orderNumber': order.orderIdDisplay,
        'isReattempt': true,
        'failureReason': order.rejectionReason,
      },
    );
    if (submitted == true && mounted) {
      await _loadOrder();
    }
  }

  Future<void> _openReattemptPickupBottomSheet(UserOrder order) async {
    List<SavedAddress> addresses = List<SavedAddress>.from(userSavedAddresses);
    if (addresses.isEmpty) {
      try {
        await loadSavedAddressesFromProfile();
        addresses = List<SavedAddress>.from(userSavedAddresses);
      } catch (_) {}
    }

    String? selectedAddressId;
    final orderAddrId = order.customerAddressId?.trim();
    if (orderAddrId != null &&
        orderAddrId.isNotEmpty &&
        addresses.any((a) => a.id == orderAddrId)) {
      selectedAddressId = orderAddrId;
    } else if (addresses.isNotEmpty) {
      selectedAddressId = addresses.first.id;
    }

    DateTime selectedDate = DateTime.now().add(const Duration(days: 1));
    const returnSlots = [
      '09:00 AM - 12:00 PM',
      '12:00 PM - 03:00 PM',
      '03:00 PM - 06:00 PM',
    ];
    String selectedSlot = returnSlots.first;
    final noteController = TextEditingController();
    bool isSubmitting = false;

    final reattemptCount = order.returnReattemptCount;
    final isFirstReattempt = reattemptCount <= 0;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF12141A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (modalContext, setModalState) {
            final bottomPadding = MediaQuery.of(modalContext).viewInsets.bottom;
            final selectedAddress = addresses.firstWhere(
              (a) => a.id == selectedAddressId,
              orElse: () => addresses.isNotEmpty
                  ? addresses.first
                  : const SavedAddress(
                      id: '',
                      title: 'Delivery Address',
                      addressLines: 'Address will be confirmed',
                      mobileDisplay: '',
                    ),
            );

            return Padding(
              padding: EdgeInsets.fromLTRB(
                20.w,
                16.h,
                20.w,
                24.h + bottomPadding,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Handle bar
                    Center(
                      child: Container(
                        width: 44.w,
                        height: 4.h,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    SizedBox(height: 16.h),

                    // Header row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Schedule Return Pickup',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 17.fSize,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(sheetContext).pop(),
                          icon: const Icon(
                            Icons.close,
                            color: Colors.white70,
                            size: 20,
                          ),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                    SizedBox(height: 12.h),

                    // Reattempt Quota Badge (Requirement 2.1)
                    if (isFirstReattempt) ...[
                      Container(
                        width: double.infinity,
                        padding: EdgeInsets.symmetric(
                          horizontal: 12.w,
                          vertical: 8.h,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0D2818),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: const Color(0xFF10B981)
                                .withValues(alpha: 0.6),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.verified_outlined,
                              color: Color(0xFF10B981),
                              size: 18,
                            ),
                            SizedBox(width: 8.w),
                            Expanded(
                              child: Text(
                                'Free Reattempt (1/1 Remaining)',
                                style: TextStyle(
                                  color: const Color(0xFF34D399),
                                  fontSize: 12.fSize,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      Container(
                        width: double.infinity,
                        padding: EdgeInsets.symmetric(
                          horizontal: 12.w,
                          vertical: 8.h,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF351508),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: const Color(0xFFF59E0B)
                                .withValues(alpha: 0.6),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.warning_amber_rounded,
                              color: Color(0xFFF59E0B),
                              size: 18,
                            ),
                            SizedBox(width: 8.w),
                            Expanded(
                              child: Text(
                                'Final attempt before account dispatch hold is triggered.',
                                style: TextStyle(
                                  color: const Color(0xFFFBBF24),
                                  fontSize: 12.fSize,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    SizedBox(height: 16.h),

                    // Pickup Address Selector
                    Text(
                      'PICKUP ADDRESS',
                      style: TextStyle(
                        color: const Color(0xFFD8B26A),
                        fontSize: 11.fSize,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.0,
                      ),
                    ),
                    SizedBox(height: 8.h),
                    Container(
                      padding: EdgeInsets.all(12.w),
                      decoration: BoxDecoration(
                        color: const Color(0xFF191B24),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.1),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.location_on_outlined,
                            color: Color(0xFFD8B26A),
                            size: 20,
                          ),
                          SizedBox(width: 10.w),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  selectedAddress.title.isNotEmpty
                                      ? selectedAddress.title
                                      : 'Pickup Location',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 13.fSize,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                SizedBox(height: 2.h),
                                Text(
                                  selectedAddress.addressLines.isNotEmpty
                                      ? selectedAddress.addressLines
                                      : (order.addressLines.isNotEmpty
                                          ? order.addressLines
                                          : 'Default Delivery Address'),
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11.5.fSize,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          if (addresses.length > 1) ...[
                            TextButton(
                              onPressed: () async {
                                final pickedId = await showDialog<String>(
                                  context: modalContext,
                                  builder: (dialogCtx) => SimpleDialog(
                                    backgroundColor: const Color(0xFF16181F),
                                    title: Text(
                                      'Select Pickup Address',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 15.fSize,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    children: addresses.map((addr) {
                                      final isSelected =
                                          addr.id == selectedAddressId;
                                      return ListTile(
                                        title: Text(
                                          addr.title,
                                          style: TextStyle(
                                            color: isSelected
                                                ? const Color(0xFFD8B26A)
                                                : Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13.fSize,
                                          ),
                                        ),
                                        subtitle: Text(
                                          addr.addressLines,
                                          style: TextStyle(
                                            color: Colors.white60,
                                            fontSize: 11.fSize,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        trailing: isSelected
                                            ? const Icon(
                                                Icons.check_circle_rounded,
                                                color: Color(0xFFD8B26A),
                                                size: 20,
                                              )
                                            : null,
                                        onTap: () =>
                                            Navigator.pop(dialogCtx, addr.id),
                                      );
                                    }).toList(),
                                  ),
                                );
                                if (pickedId != null) {
                                  setModalState(
                                      () => selectedAddressId = pickedId);
                                }
                              },
                              child: Text(
                                'Change',
                                style: TextStyle(
                                  color: const Color(0xFFD8B26A),
                                  fontSize: 12.fSize,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    SizedBox(height: 16.h),

                    // Date Picker
                    Text(
                      'PICKUP DATE',
                      style: TextStyle(
                        color: const Color(0xFFD8B26A),
                        fontSize: 11.fSize,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.0,
                      ),
                    ),
                    SizedBox(height: 8.h),
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: modalContext,
                          initialDate: selectedDate,
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now()
                              .add(const Duration(days: 14)),
                          builder: (context, child) {
                            return Theme(
                              data: ThemeData.dark().copyWith(
                                colorScheme: const ColorScheme.dark(
                                  primary: Color(0xFFD8B26A),
                                  onPrimary: Colors.black,
                                  surface: Color(0xFF1E2028),
                                  onSurface: Colors.white,
                                ),
                              ),
                              child: child!,
                            );
                          },
                        );
                        if (picked != null) {
                          setModalState(() => selectedDate = picked);
                        }
                      },
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 14.w,
                          vertical: 12.h,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF191B24),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.1),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.calendar_today_outlined,
                                  color: Color(0xFFD8B26A),
                                  size: 18,
                                ),
                                SizedBox(width: 10.w),
                                Text(
                                  '${selectedDate.day.toString().padLeft(2, '0')}/${selectedDate.month.toString().padLeft(2, '0')}/${selectedDate.year}',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 13.5.fSize,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              'Change Date',
                              style: TextStyle(
                                color: const Color(0xFFD8B26A),
                                fontSize: 12.fSize,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: 16.h),

                    // Time Slot Selector
                    Text(
                      'PICKUP TIME SLOT',
                      style: TextStyle(
                        color: const Color(0xFFD8B26A),
                        fontSize: 11.fSize,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.0,
                      ),
                    ),
                    SizedBox(height: 8.h),
                    Wrap(
                      spacing: 8.w,
                      runSpacing: 8.h,
                      children: returnSlots.map((slot) {
                        final isSelected = slot == selectedSlot;
                        return ChoiceChip(
                          label: Text(
                            slot,
                            style: TextStyle(
                              color: isSelected ? Colors.black : Colors.white70,
                              fontSize: 11.5.fSize,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                          selected: isSelected,
                          selectedColor: const Color(0xFFD8B26A),
                          backgroundColor: const Color(0xFF1A1D27),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: BorderSide(
                              color: isSelected
                                  ? const Color(0xFFD8B26A)
                                  : Colors.white.withValues(alpha: 0.15),
                            ),
                          ),
                          onSelected: (_) {
                            setModalState(() => selectedSlot = slot);
                          },
                        );
                      }).toList(),
                    ),
                    SizedBox(height: 16.h),

                    // Notes / Instructions
                    Text(
                      'NOTES / INSTRUCTIONS (OPTIONAL)',
                      style: TextStyle(
                        color: const Color(0xFFD8B26A),
                        fontSize: 11.fSize,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.0,
                      ),
                    ),
                    SizedBox(height: 8.h),
                    TextField(
                      controller: noteController,
                      maxLines: 2,
                      style:
                          TextStyle(color: Colors.white, fontSize: 13.fSize),
                      decoration: InputDecoration(
                        hintText:
                            'Add landmarks or pickup notes (e.g., Available at home)...',
                        hintStyle: TextStyle(
                          color: Colors.white30,
                          fontSize: 12.fSize,
                        ),
                        filled: true,
                        fillColor: const Color(0xFF1A1D27),
                        contentPadding: EdgeInsets.all(12.w),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    SizedBox(height: 20.h),

                    // Submit Button
                    SizedBox(
                      width: double.infinity,
                      height: 48.h,
                      child: ElevatedButton(
                        onPressed: isSubmitting
                            ? null
                            : () async {
                                setModalState(() => isSubmitting = true);
                                try {
                                  Customer? customer;
                                  try {
                                    customer =
                                        await _profileRepository.getProfile();
                                  } catch (_) {}

                                  final dateStr =
                                      '${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}';

                                  final result =
                                      await _orderRepository.reattemptReturn(
                                    orderId: order.id,
                                    pickupDate: dateStr,
                                    pickupTime: selectedSlot,
                                    addressId: selectedAddressId,
                                    note: noteController.text.trim(),
                                    fullName: customer?.fullName ??
                                        order.pickupFullName ??
                                        'Customer',
                                    mobile: customer?.mobile ??
                                        order.pickupMobile ??
                                        '',
                                  );

                                  await PendingReturnStore.instance
                                      .mark(order.id);
                                  markUserOrderReturnSubmitted(order.id);

                                  if (!mounted) return;
                                  Navigator.of(sheetContext).pop();

                                  CustomAppSnackBar.showSuccess(
                                    context,
                                    result.message.isNotEmpty
                                        ? result.message
                                        : 'Return pickup scheduled successfully.',
                                  );

                                  if (mounted) {
                                    await _loadOrder();
                                  }
                                } on ApiException catch (e) {
                                  if (e.isNoReturnBlocked) {
                                    if (!mounted) return;
                                    Navigator.of(sheetContext).pop();
                                    await showNoReturnBlockedDialog(
                                      context,
                                      overdueOrderNumber:
                                          e.overdueOrderNumber,
                                      message: e.message,
                                    );
                                  } else {
                                    setModalState(() => isSubmitting = false);
                                    if (!mounted) return;
                                    CustomAppSnackBar.showError(
                                        context, e.message);
                                  }
                                } catch (_) {
                                  setModalState(() => isSubmitting = false);
                                  if (!mounted) return;
                                  CustomAppSnackBar.showError(
                                    context,
                                    'Failed to schedule return pickup. Please try again.',
                                  );
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFD8B26A),
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          elevation: 2,
                        ),
                        child: isSubmitting
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.black,
                                ),
                              )
                            : Text(
                                'Confirm Return Pickup',
                                style: TextStyle(
                                  fontSize: 14.fSize,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _startDeliveryReattemptFlow(UserOrder order) async {
    setState(() => _isReattemptActionLoading = true);
    try {
      final quote = await _orderRepository.getReattemptQuote(order.id);
      if (!mounted) return;
      setState(() => _isReattemptActionLoading = false);
      _showReattemptQuoteSheet(order, quote);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _isReattemptActionLoading = false);
      CustomAppSnackBar.showError(context, e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isReattemptActionLoading = false);
      CustomAppSnackBar.showError(
        context,
        'Unable to retrieve delivery reattempt quote. Please try again.',
      );
    }
  }

  Future<void> _showReattemptQuoteSheet(
    UserOrder order,
    ReattemptQuote quote,
  ) async {
    DateTime selectedDate = DateTime.now().add(const Duration(days: 1));
    const slots = [
      '10:00 AM - 01:00 PM',
      '01:00 PM - 04:00 PM',
      '04:00 PM - 07:00 PM',
      '07:00 PM - 10:00 PM',
    ];
    String selectedSlot = slots.first;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF12141A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final y = selectedDate.year;
            final m = selectedDate.month.toString().padLeft(2, '0');
            final d = selectedDate.day.toString().padLeft(2, '0');
            final apiDateStr = '$y-$m-$d';
            final displayDateStr = '$d/$m/$y';

            return Padding(
              padding: EdgeInsets.only(
                left: 20.w,
                right: 20.w,
                top: 20.h,
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 20.h,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40.w,
                        height: 4.h,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    SizedBox(height: 16.h),
                    Row(
                      children: [
                        const Icon(
                          Icons.local_shipping_outlined,
                          color: Color(0xFFD8B26A),
                          size: 22,
                        ),
                        SizedBox(width: 8.w),
                        Text(
                          'Schedule Delivery Reattempt',
                          style: TextStyle(
                            color: const Color(0xFFD8B26A),
                            fontSize: 16.fSize,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 14.h),
                    Container(
                      padding: EdgeInsets.all(14.w),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1D27),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFFD8B26A).withValues(alpha: 0.35),
                        ),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Delivery Charge',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12.5.fSize,
                                ),
                              ),
                              Text(
                                quote.isFreeReattempt || quote.deliveryCharge <= 0
                                    ? 'FREE'
                                    : '₹${quote.deliveryCharge}',
                                style: TextStyle(
                                  color: quote.isFreeReattempt ||
                                          quote.deliveryCharge <= 0
                                      ? const Color(0xFF10B981)
                                      : Colors.white,
                                  fontSize: 13.fSize,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          if (quote.distanceKm > 0) ...[
                            SizedBox(height: 8.h),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Delivery Distance',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12.5.fSize,
                                  ),
                                ),
                                Text(
                                  '${quote.distanceKm} km',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 13.fSize,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ],
                          SizedBox(height: 10.h),
                          Divider(
                            color: Colors.white.withValues(alpha: 0.1),
                            height: 1,
                          ),
                          SizedBox(height: 10.h),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Total Payable',
                                style: TextStyle(
                                  color: const Color(0xFFD8B26A),
                                  fontSize: 13.5.fSize,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                quote.totalPayable <= 0
                                    ? 'FREE'
                                    : '₹${quote.totalPayable}',
                                style: TextStyle(
                                  color: quote.totalPayable <= 0
                                      ? const Color(0xFF10B981)
                                      : const Color(0xFFD8B26A),
                                  fontSize: 16.fSize,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 18.h),
                    Text(
                      'SELECT DELIVERY DATE',
                      style: TextStyle(
                        color: const Color(0xFFD8B26A),
                        fontSize: 11.fSize,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.0,
                      ),
                    ),
                    SizedBox(height: 8.h),
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: selectedDate,
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(const Duration(days: 14)),
                          builder: (context, child) {
                            return Theme(
                              data: Theme.of(context).copyWith(
                                colorScheme: const ColorScheme.dark(
                                  primary: Color(0xFFD8B26A),
                                  onPrimary: Colors.black,
                                  surface: Color(0xFF1A1D27),
                                  onSurface: Colors.white,
                                ),
                              ),
                              child: child!,
                            );
                          },
                        );
                        if (picked != null) {
                          setSheetState(() => selectedDate = picked);
                        }
                      },
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding:
                            EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1D27),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: const Color(0xFFD8B26A).withValues(alpha: 0.4),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.calendar_today_rounded,
                              color: Color(0xFFD8B26A),
                              size: 18,
                            ),
                            SizedBox(width: 10.w),
                            Text(
                              displayDateStr,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13.5.fSize,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              'Change',
                              style: TextStyle(
                                color: const Color(0xFFD8B26A),
                                fontSize: 12.fSize,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: 18.h),
                    Text(
                      'SELECT DELIVERY TIME SLOT',
                      style: TextStyle(
                        color: const Color(0xFFD8B26A),
                        fontSize: 11.fSize,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.0,
                      ),
                    ),
                    SizedBox(height: 8.h),
                    Wrap(
                      spacing: 8.w,
                      runSpacing: 8.h,
                      children: slots.map((slot) {
                        final isSelected = selectedSlot == slot;
                        return ChoiceChip(
                          label: Text(
                            slot,
                            style: TextStyle(
                              color: isSelected ? Colors.black : Colors.white70,
                              fontSize: 11.5.fSize,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                          selected: isSelected,
                          selectedColor: const Color(0xFFD8B26A),
                          backgroundColor: const Color(0xFF1A1D27),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: BorderSide(
                              color: isSelected
                                  ? const Color(0xFFD8B26A)
                                  : Colors.white12,
                            ),
                          ),
                          onSelected: (val) {
                            if (val) {
                              setSheetState(() => selectedSlot = slot);
                            }
                          },
                        );
                      }).toList(),
                    ),
                    SizedBox(height: 24.h),
                    SizedBox(
                      width: double.infinity,
                      height: 48.h,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          _submitDeliveryReorder(
                            order,
                            quote,
                            apiDateStr,
                            selectedSlot,
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFD8B26A),
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          elevation: 2,
                        ),
                        child: Text(
                          quote.totalPayable > 0
                              ? 'Pay ₹${quote.totalPayable} & Schedule'
                              : 'Schedule Delivery Reattempt',
                          style: TextStyle(
                            fontSize: 13.5.fSize,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _submitDeliveryReorder(
    UserOrder order,
    ReattemptQuote quote,
    String deliveryDate,
    String deliveryTime,
  ) async {
    setState(() => _isReattemptActionLoading = true);

    try {
      final res = await _orderRepository.reorderDelivery(
        orderId: order.id,
        deliveryDate: deliveryDate,
        deliveryTime: deliveryTime,
      );

      if (res.paymentRequired) {
        _pendingReattemptOrderId = order.id;
        _pendingReattemptDeliveryDate = deliveryDate;
        _pendingReattemptDeliveryTime = deliveryTime;

        Customer? customer;
        try {
          customer = await _profileRepository.getProfile();
        } catch (_) {}

        final keyId = res.razorpayKeyId ?? 'rzp_test_51O2aL2a';
        final amountPaise = res.amount > 0
            ? res.amount
            : (quote.totalPayable * 100).round();

        _razorpayService.openCheckout(
          keyId: keyId,
          orderId: res.razorpayOrderId ?? '',
          amount: amountPaise,
          currency: res.currency,
          name: customer?.fullName,
          email: customer?.email,
          contact: customer?.mobile,
          description: 'Delivery reattempt for Order #${order.orderIdDisplay}',
        );
      } else {
        if (!mounted) return;
        setState(() => _isReattemptActionLoading = false);

        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF16181D),
            title: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981)),
                const SizedBox(width: 8),
                Text(
                  'Reattempt Scheduled',
                  style: TextStyle(
                    color: AppColours.primary,
                    fontSize: 16.fSize,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            content: Text(
              res.message ??
                  'Your delivery reattempt has been scheduled for $deliveryDate ($deliveryTime).',
              style: TextStyle(color: Colors.white70, fontSize: 14.fSize),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('OK', style: TextStyle(color: AppColours.primary)),
              ),
            ],
          ),
        );

        await _loadOrder();
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _isReattemptActionLoading = false);
      CustomAppSnackBar.showError(context, e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isReattemptActionLoading = false);
      CustomAppSnackBar.showError(
        context,
        'Failed to schedule delivery reattempt. Please try again.',
      );
    }
  }

  Future<void> _onRazorpayPaymentSuccess(
    PaymentSuccessResponse response,
  ) async {
    final orderId = _pendingReattemptOrderId ?? widget.orderId;
    final date = _pendingReattemptDeliveryDate ?? '';
    final time = _pendingReattemptDeliveryTime ?? '';

    final paymentId = response.paymentId?.trim() ?? '';
    final razorpayOrderId = response.orderId?.trim() ?? '';
    final signature = response.signature?.trim() ?? '';

    setState(() => _isReattemptActionLoading = true);

    try {
      final res = await _orderRepository.reorderDelivery(
        orderId: orderId,
        deliveryDate: date,
        deliveryTime: time,
        razorpayPaymentId: paymentId,
        razorpayOrderId: razorpayOrderId,
        razorpaySignature: signature,
      );

      if (!mounted) return;
      setState(() => _isReattemptActionLoading = false);

      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF16181D),
          title: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981)),
              const SizedBox(width: 8),
              Text(
                'Payment Confirmed',
                style: TextStyle(
                  color: AppColours.primary,
                  fontSize: 16.fSize,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: Text(
            res.message ??
                'Payment verified! Delivery reattempt has been scheduled successfully.',
            style: TextStyle(color: Colors.white70, fontSize: 14.fSize),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('OK', style: TextStyle(color: AppColours.primary)),
            ),
          ],
        ),
      );

      await _loadOrder();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _isReattemptActionLoading = false);
      CustomAppSnackBar.showError(context, e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isReattemptActionLoading = false);
      CustomAppSnackBar.showError(
        context,
        'Failed to confirm delivery reattempt payment.',
      );
    }
  }

  void _onRazorpayPaymentFailure(PaymentFailureResponse response) {
    if (!mounted) return;
    setState(() => _isReattemptActionLoading = false);
    final msg = response.message?.trim();
    CustomAppSnackBar.showError(
      context,
      (msg != null && msg.isNotEmpty)
          ? 'Payment failed: $msg'
          : 'Payment cancelled or failed. Please try again.',
    );
  }

  Future<void> _openRefundBottomSheet(UserOrder order) async {
    const reasons = [
      'Order placed by mistake',
      'Delivery time too late',
      'Need to change delivery address or items',
      'Found a better alternative',
      'Other',
    ];

    String selectedReason = reasons.first;
    final notesController = TextEditingController();
    bool isSubmitting = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF12141A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (bottomSheetContext) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20.w,
                right: 20.w,
                top: 20.h,
                bottom:
                    MediaQuery.of(bottomSheetContext).viewInsets.bottom + 20.h,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40.w,
                        height: 4.h,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    SizedBox(height: 16.h),
                    Row(
                      children: [
                        const Icon(
                          Icons.currency_rupee_rounded,
                          color: Color(0xFFD8B26A),
                          size: 22,
                        ),
                        SizedBox(width: 8.w),
                        Text(
                          'Request Refund / Cancellation',
                          style: TextStyle(
                            color: const Color(0xFFD8B26A),
                            fontSize: 16.fSize,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 14.h),
                    Container(
                      padding: EdgeInsets.all(12.w),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1D27),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: const Color(0xFFD8B26A).withValues(alpha: 0.3),
                        ),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Order Number',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12.fSize,
                                ),
                              ),
                              Text(
                                order.orderIdDisplay,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12.5.fSize,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 8.h),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Refund Amount',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12.fSize,
                                ),
                              ),
                              Text(
                                '₹${order.totalAmount}',
                                style: TextStyle(
                                  color: const Color(0xFF10B981),
                                  fontSize: 14.fSize,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 16.h),
                    Text(
                      'SELECT REASON',
                      style: TextStyle(
                        color: const Color(0xFFD8B26A),
                        fontSize: 11.fSize,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.0,
                      ),
                    ),
                    SizedBox(height: 8.h),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 12.w),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1D27),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: selectedReason,
                          isExpanded: true,
                          dropdownColor: const Color(0xFF1E222D),
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13.fSize,
                          ),
                          items: reasons
                              .map(
                                (r) => DropdownMenuItem(
                                  value: r,
                                  child: Text(r),
                                ),
                              )
                              .toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setModalState(() => selectedReason = val);
                            }
                          },
                        ),
                      ),
                    ),
                    SizedBox(height: 14.h),
                    Text(
                      'ADDITIONAL DETAILS (OPTIONAL)',
                      style: TextStyle(
                        color: const Color(0xFFD8B26A),
                        fontSize: 11.fSize,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.0,
                      ),
                    ),
                    SizedBox(height: 8.h),
                    TextField(
                      controller: notesController,
                      maxLines: 3,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13.fSize,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Enter more details regarding your request...',
                        hintStyle: TextStyle(
                          color: Colors.white30,
                          fontSize: 12.fSize,
                        ),
                        filled: true,
                        fillColor: const Color(0xFF1A1D27),
                        contentPadding: EdgeInsets.all(12.w),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    SizedBox(height: 20.h),
                    SizedBox(
                      width: double.infinity,
                      height: 46.h,
                      child: ElevatedButton(
                        onPressed: isSubmitting
                            ? null
                            : () async {
                                setModalState(() => isSubmitting = true);
                                final combinedReason = notesController.text.trim().isNotEmpty
                                    ? '$selectedReason - ${notesController.text.trim()}'
                                    : selectedReason;

                                try {
                                  Customer? customer;
                                  try {
                                    customer = await _profileRepository.getProfile();
                                  } catch (_) {}

                                  final waitlistNum =
                                      await _orderRepository.submitRefundRequest(
                                    orderId: order.id,
                                    orderNumber: order.orderIdDisplay,
                                    customerId:
                                        order.customerId ?? customer?.id ?? '',
                                    reason: combinedReason,
                                    amount: order.totalAmount,
                                    fullName: customer?.fullName ?? 'Customer',
                                    mobile: customer?.mobile ?? '',
                                    email: customer?.email,
                                  );

                                  if (!mounted) return;
                                  Navigator.of(bottomSheetContext).pop();

                                  if (!mounted) return;
                                  await showDialog<void>(
                                    context: context,
                                    builder: (dialogCtx) => AlertDialog(
                                      backgroundColor: const Color(0xFF16181D),
                                      title: Row(
                                        children: [
                                          const Icon(
                                            Icons.check_circle_rounded,
                                            color: Color(0xFF10B981),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            'Refund Submitted',
                                            style: TextStyle(
                                              color: AppColours.primary,
                                              fontSize: 16.fSize,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                      content: Text(
                                        'Your refund request for ₹${order.totalAmount} has been registered.\n\nWaitlist Reference: $waitlistNum\n\nOur team is reviewing your request.',
                                        style: TextStyle(
                                          color: Colors.white70,
                                          fontSize: 13.5.fSize,
                                          height: 1.4,
                                        ),
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(dialogCtx),
                                          child: Text(
                                            'OK',
                                            style: TextStyle(
                                              color: AppColours.primary,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );

                                  if (!mounted) return;
                                  await _loadOrder();
                                } on ApiException catch (e) {
                                  setModalState(() => isSubmitting = false);
                                  if (!mounted) return;
                                  CustomAppSnackBar.showError(context, e.message);
                                } catch (_) {
                                  setModalState(() => isSubmitting = false);
                                  if (!mounted) return;
                                  CustomAppSnackBar.showError(
                                    context,
                                    'Failed to submit refund request. Please try again.',
                                  );
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFD8B26A),
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: isSubmitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.black,
                                ),
                              )
                            : Text(
                                'Submit Refund Request',
                                style: TextStyle(
                                  fontSize: 13.5.fSize,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
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
