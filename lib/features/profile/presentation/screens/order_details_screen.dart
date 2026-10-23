import 'dart:async';
import 'dart:math' show pi;

import 'package:flutter_svg/flutter_svg.dart';
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

const _addNewPickupAddressId = '__add_new_pickup_address__';

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
  bool _essentialsItemsExpanded = true;
  bool _depositExpanded = true;

  String? _pendingReattemptOrderId;
  String? _pendingReattemptDeliveryDate;
  String? _pendingReattemptDeliveryTime;
  bool _isReattemptActionLoading = false;
  ({
    String date,
    String time,
    String? location,
    String? note,
  })? _rescheduledPickup;
  bool _reattemptLoaderVisible = false;
  ValueNotifier<_ReattemptDialogView>? _reattemptDialogView;
  Completer<void>? _reattemptDialogClosed;
  RefundStatusResult? _refundStatus;

  @override
  void initState() {
    super.initState();
    _itemsExpanded = true;
    _subItemsExpanded = true;
    _nonSubItemsExpanded = true;
    _kidsItemsExpanded = true;
    _essentialsItemsExpanded = true;
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
      final mapped = _withRescheduledPickup(
        UserOrderMapper.fromHistoryItem(detail, customer: customer),
      );
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
      resizeToAvoidBottomInset: false,
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
          if (order.isRefundCompleted) ...[
            if (_hasCompletedRefundDetails(order)) ...[
            SizedBox(height: 12.h),
              _buildRefundCompletedCard(order),
            ],
          ] else if (_refundStatus != null) ...[
            SizedBox(height: 12.h),
            _buildRefundStatusCard(_refundStatus!, order),
          ],
          if (order.isReorderRequested &&
              !order.isRefundCompleted &&
              (_refundStatus == null || _refundStatus!.isRejected)) ...[
            SizedBox(height: 12.h),
            _buildReorderRequestedBanner(),
          ] else if (order.isDeliveryReattemptEligible &&
              !order.isRefundCompleted &&
              (_refundStatus == null || _refundStatus!.isRejected)) ...[
            SizedBox(height: 12.h),
            _buildDeliveryReattemptBanner(order),
          ],
          if (order.isReturnReattemptPending &&
              !order.isRefundCompleted &&
              (_refundStatus == null || _refundStatus!.isRejected)) ...[
            SizedBox(height: 12.h),
            _buildReturnReattemptPendingBanner(),
          ] else if (order.isReturnFailed &&
              !_isReturnSettled(order) &&
              !order.isRefundCompleted &&
              (_refundStatus == null || _refundStatus!.isRejected)) ...[
            SizedBox(height: 12.h),
            _buildReturnFailedBanner(order),
          ],
          SizedBox(height: 20.h),
          _buildItemsHeader(),
          SizedBox(height: 14.h),
          ..._buildSeparatedKitItemsCards(order),
          if (!order.isReturnComplete) ...[
          SizedBox(height: 18.h),
            _buildActionButtons(order),
          ],
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

  bool _isPurchaseSection(String badgeLabel) {
    return badgeLabel == 'KIDS NON RETURNABLE' ||
        badgeLabel == 'ESSENTIALS NON RETURNABLE';
  }

  bool _isItemEssentials(OrderLineItem item) {
    if (_isItemKids(item)) return false;
    final type = item.itemType?.trim().toLowerCase();
    if (type == 'essentials' || type == 'essential') return true;
    final cat = item.category?.trim().toLowerCase() ?? '';
    if (cat.contains('essential')) return true;
    final name = item.productName.trim().toLowerCase();
    return name.contains('essential');
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
    final essentialItems = items.where(_isItemEssentials).toList();
    final subItems = items
        .where((it) =>
            !_isItemKids(it) &&
            !_isItemEssentials(it) &&
            _isItemSubscription(it, order))
        .toList();
    final nonSubItems = items
        .where((it) =>
            !_isItemKids(it) &&
            !_isItemEssentials(it) &&
            !_isItemSubscription(it, order))
        .toList();

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

    if (essentialItems.isNotEmpty) {
      if (widgets.isNotEmpty) {
        widgets.add(SizedBox(height: 14.h));
      }
      widgets.add(
        _buildSingleKitItemsCard(
          order: order,
          items: essentialItems,
          badgeLabel: 'ESSENTIALS NON RETURNABLE',
          pricePrefix: 'Subtotal',
          isSubscription: false,
          isExpanded: _essentialsItemsExpanded,
          onToggleExpanded: () =>
              setState(() => _essentialsItemsExpanded = !_essentialsItemsExpanded),
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
      if (itemsTotal <= 0 && !_isPurchaseSection(badgeLabel)) {
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
                      !_isPurchaseSection(badgeLabel) &&
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

  UserOrder _withRescheduledPickup(UserOrder order) {
    final local = _rescheduledPickup;
    if (local == null) {
      if (UserOrderMapper.isIapAddress(order.pickupAddress)) {
        return order.copyWith(pickupAddress: null);
      }
      return order;
    }

    String? keep(String? current, String? fallback) {
      final text = current?.trim() ?? '';
      if (text.isNotEmpty && text.toLowerCase() != 'null') return current;
      final next = fallback?.trim() ?? '';
      return next.isEmpty ? current : fallback;
    }

    final effectiveLocation = keep(order.pickupAddress, local.location);
    return order.copyWith(
      pickupDate: keep(order.pickupDate, local.date),
      pickupTime: keep(order.pickupTime, local.time),
      pickupAddress: UserOrderMapper.isIapAddress(effectiveLocation) ? null : effectiveLocation,
      pickupNote: keep(order.pickupNote, local.note),
    );
  }

  bool _hasCompletedRefundDetails(UserOrder order) {
    final note = order.refundCompletedNote?.trim() ?? '';
    return order.refundAmountLabel != null ||
        order.refundedAt != null ||
        note.isNotEmpty;
  }

  Widget _buildRefundCompletedCard(UserOrder order) {
    final amount = order.refundAmountLabel;
    final note = order.refundCompletedNote?.trim();
    final refundedAt = order.refundedAt;
    final time = refundedAt == null
        ? null
        : UserOrderMapper.formatTrackingTimestamp(refundedAt);

    const badgeColor = Color(0xFF10B981);
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
                  color: badgeColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: badgeColor.withValues(alpha: 0.6)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.check_circle_rounded,
                      color: badgeColor,
                      size: 14,
                    ),
                    SizedBox(width: 5.w),
                    Text(
                      'REFUND COMPLETED',
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
          if (amount != null) ...[
            SizedBox(height: 12.h),
            _refundDetailLine('REFUND AMOUNT', amount),
          ],
          if (time != null && time != 'Pending') ...[
            SizedBox(height: 8.h),
            _refundDetailLine('REFUNDED ON', time),
          ],
          if (note != null && note.isNotEmpty) ...[
            SizedBox(height: 8.h),
            _refundDetailLine('NOTE', note),
          ],
        ],
      ),
    );
  }

  Widget _refundDetailLine(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white38,
            fontSize: 9.5.fSize,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.8,
          ),
        ),
        SizedBox(height: 2.h),
        Text(
          value,
          style: TextStyle(
            color: label == 'REFUND AMOUNT'
                ? Colors.white
                : const Color(0xFFD8B26A),
            fontSize: 13.fSize,
            fontWeight: FontWeight.bold,
            height: 1.35,
          ),
        ),
      ],
    );
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
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: const Color(0xFFD8B26A),
                  fontSize: 13.fSize,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 8.h),
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
    );
  }

  Widget _buildReorderRequestedBanner() {
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
              Icons.schedule_rounded,
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
                  'Reorder Requested',
                  style: TextStyle(
                    color: const Color(0xFFF59E0B),
                    fontSize: 13.fSize,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 3.h),
                Text(
                  'Your delivery reattempt request is in progress. Another delivery cannot be scheduled until this request is completed.',
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
    if (order.isReturnComplete) {
      return const SizedBox.shrink();
    }
    final isDeliveryReattempt = order.isDeliveryReattemptEligible;
    final isReturnPending = order.isReturnReattemptPending;
    final isReturnReattempt =
        !isReturnPending && order.isReturnFailed && !_isReturnSettled(order);
    final isReturnApprovedPendingSchedule = !order.isReturnComplete &&
        (order.returnStatus?.toUpperCase() == 'RETURN_APPROVED' ||
            order.orderStatusRaw?.toUpperCase() == 'RETURN_APPROVED') &&
        (order.pickupDate == null || order.pickupDate!.trim().isEmpty);
    final opensReturn = !isReturnReattempt &&
        (order.actionFlow == OrderActionFlow.delivered ||
            order.canReturn ||
            isReturnApprovedPendingSchedule);
    final opensTracking = !isDeliveryReattempt &&
        !isReturnReattempt &&
        !isReturnApprovedPendingSchedule &&
        (order.actionFlow == OrderActionFlow.forward ||
            order.actionFlow == OrderActionFlow.reverse);

    final inReturnFlow = order.isInReturnFlow ||
        order.isReturnFailed ||
        order.isReturnComplete ||
        isReturnReattempt ||
        isReturnPending ||
        PendingReturnStore.instance.contains(order.id) ||
        (order.returnStatus != null &&
            order.returnStatus!.isNotEmpty &&
            order.returnStatus!.toUpperCase() != 'ACTIVE' &&
            order.returnStatus!.toUpperCase() != 'NOT_DELIVERED');

    final showRefundButton =
        !inReturnFlow && order.isRefundEligible && _refundStatus == null;
    final refundInReview =
        _refundStatus != null && !_refundStatus!.isRejected;
    final primaryIsTracking = refundInReview ||
        (!isDeliveryReattempt &&
            !isReturnPending &&
            !isReturnReattempt &&
            !opensReturn &&
            opensTracking);
    final returnStatus = (order.returnStatus ?? '').trim().toUpperCase();
    final orderStatus = (order.orderStatusRaw ?? '').trim().toUpperCase();
    const returnRequestedStatuses = {
      'RETURN_REQUESTED',
      'RETURN_PENDING',
      'PICKUP_SCHEDULED',
      'WAITLISTED',
      'RETURN_APPROVED',
      'APPROVED',
    };
    final inReturnRequest = order.isInReturnFlow ||
        isReturnPending ||
        isReturnApprovedPendingSchedule ||
        PendingReturnStore.instance.contains(order.id) ||
        returnRequestedStatuses.contains(orderStatus) ||
        returnRequestedStatuses.contains(returnStatus);

    String primaryButtonLabel;
    IconData primaryButtonIcon;
    VoidCallback? onPrimaryPressed;

    if (refundInReview) {
      primaryButtonLabel = 'Refund Tracking';
      primaryButtonIcon = Icons.near_me_outlined;
      onPrimaryPressed = () => Navigator.pushNamed(
            context,
            AppRoutes.orderTrackingScreen,
            arguments: order.id,
          );
    } else if (isDeliveryReattempt) {
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
      primaryButtonLabel = isReturnApprovedPendingSchedule
          ? 'Schedule Return Pickup'
          : 'Request Kit Return Pickup';
      primaryButtonIcon = isReturnApprovedPendingSchedule
          ? Icons.calendar_today_outlined
          : Icons.refresh_rounded;
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
        if (isReturnReattempt || (inReturnRequest && !primaryIsTracking)) ...[
          SizedBox(height: 12.h),
          SizedBox(
            height: 44.h,
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => Navigator.pushNamed(
                context,
                AppRoutes.orderTrackingScreen,
                arguments: order.id,
              ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(
                  color: const Color(0xFFD8B26A).withValues(alpha: 0.6),
                ),
                foregroundColor: const Color(0xFFD8B26A),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.near_me_outlined, size: 17),
              label: Text(
                'Track Your Order',
                style: TextStyle(
                  fontSize: 12.5.fSize,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ),
        ],
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

  Future<SavedAddress?> _addPickupAddress() async {
    final location = await Navigator.pushNamed(
      context,
      AppRoutes.selectAddressScreen,
    );
    if (!mounted || location == null) return null;

    final result = await Navigator.pushNamed(
      context,
      AppRoutes.addNewAddressScreen,
      arguments: location is Map ? location : null,
    );
    if (!mounted || result is! Map) return null;

    try {
      final payload = result.map(
        (key, value) => MapEntry(key.toString(), value?.toString() ?? ''),
      );
      return await createAndAppendSavedAddress(payload);
    } on ApiException catch (error) {
      if (mounted) CustomAppSnackBar.showError(context, error.message);
      return null;
    } catch (_) {
      if (mounted) {
        CustomAppSnackBar.showError(
          context,
          'Unable to save address. Please try again.',
        );
      }
      return null;
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

    DateTime? selectedDate;
    String? selectedSlot;
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
              padding: EdgeInsets.fromLTRB(20.w, 16.h, 20.w, 24.h),
              child: SingleChildScrollView(
                padding: EdgeInsets.only(bottom: bottomPadding),
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
                                    children: [
                                      ...addresses.map((addr) {
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
                                      }),
                                      const Divider(color: Colors.white12),
                                      ListTile(
                                        leading: const Icon(
                                          Icons.add_location_alt_outlined,
                                          color: Color(0xFFD8B26A),
                                        ),
                                        title: Text(
                                          '+ Add New Address',
                                          style: TextStyle(
                                            color: const Color(0xFFD8B26A),
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13.fSize,
                                          ),
                                        ),
                                        onTap: () => Navigator.pop(
                                          dialogCtx,
                                          _addNewPickupAddressId,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                                if (pickedId == null || !mounted) return;
                                if (pickedId == _addNewPickupAddressId) {
                                  final saved = await _addPickupAddress();
                                  if (!mounted || saved == null) return;
                                  setModalState(() {
                                    addresses = List<SavedAddress>.from(
                                      userSavedAddresses,
                                    );
                                    selectedAddressId = saved.id;
                                  });
                                  return;
                                }
                                setModalState(
                                    () => selectedAddressId = pickedId);
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
                      ),
                    ),
                    SizedBox(height: 16.h),

                    _DeliveryReattemptScheduleFields(
                      dateHeader: 'SELECT PICKUP DATE',
                      timeHeader: 'SELECT PICKUP TIME',
                      dateHint: 'Select Pickup Date',
                      timeHint: 'Select Pickup Time',
                      initialDate: selectedDate,
                      initialTime: selectedSlot,
                      allowToday: false,
                      onChanged: (date, time) {
                        setModalState(() {
                          selectedDate = date;
                          selectedSlot = time;
                        });
                      },
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
                                final date = selectedDate;
                                final time = selectedSlot?.trim() ?? '';
                                if (date == null || time.isEmpty) {
                                  CustomAppSnackBar.showError(
                                    sheetContext,
                                    'Please select a pickup date and time.',
                                  );
                                  return;
                                }
                                setModalState(() => isSubmitting = true);
                                try {
                                  Customer? customer;
                                  try {
                                    customer =
                                        await _profileRepository.getProfile();
                                  } catch (_) {}

                                  final dateStr =
                                      '${date.year.toString().padLeft(4, '0')}-'
                                      '${date.month.toString().padLeft(2, '0')}-'
                                      '${date.day.toString().padLeft(2, '0')}';
                                  SavedAddress? pickedAddress;
                                  for (final address in addresses) {
                                    if (address.id == selectedAddressId) {
                                      pickedAddress = address;
                                      break;
                                    }
                                  }
                                  final locationText =
                                      pickedAddress?.addressLines.trim() ?? '';
                                  final noteText = noteController.text.trim();

                                  final result =
                                      await _orderRepository.reattemptReturn(
                                    orderId: order.id,
                                    pickupDate: dateStr,
                                    pickupTime: time,
                                    addressId: selectedAddressId,
                                    note: noteText,
                                    fullName: customer?.fullName ??
                                        order.pickupFullName ??
                                        'Customer',
                                    mobile: customer?.mobile ??
                                        order.pickupMobile ??
                                        '',
                                  );

                                  _rescheduledPickup = (
                                    date: dateStr,
                                    time: time,
                                    location: locationText.isEmpty
                                        ? pickedAddress?.title.trim()
                                        : locationText,
                                    note: noteText,
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
    if (order.isReorderRequested) return;
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
    DateTime? selectedDate;
    String? selectedSlot;
    final notesController = TextEditingController();
    var notesDisposed = false;
    void disposeNotes() {
      if (notesDisposed) return;
      notesDisposed = true;
      notesController.dispose();
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF12141A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return _RunOnDispose(
          action: disposeNotes,
          child: StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(20.w, 20.h, 20.w, 20.h),
              child: SingleChildScrollView(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
                ),
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
                    if (quote.isFreeReattempt) ...[
                      Container(
                        width: double.infinity,
                        padding: EdgeInsets.symmetric(
                          horizontal: 12.w,
                          vertical: 10.h,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: const Color(0xFF10B981).withValues(alpha: 0.45),
                          ),
                        ),
                        child: Text(
                          'Free Reattempt (Included with your Prime/Subscription membership)',
                          style: TextStyle(
                            color: const Color(0xFF10B981),
                            fontSize: 12.5.fSize,
                            fontWeight: FontWeight.w600,
                            height: 1.35,
                          ),
                        ),
                      ),
                      SizedBox(height: 12.h),
                    ],
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
                          if (!quote.isFreeReattempt) ...[
                            _reattemptChargeRow(
                              'Reattempt Charge',
                              _formatReattemptAmount(quote.reattemptCharge),
                            ),
                            SizedBox(height: 8.h),
                            _reattemptChargeRow(
                              'Unpaid Previous Charges',
                              _formatReattemptAmount(quote.unpaidPreviousCharges),
                            ),
                            SizedBox(height: 10.h),
                            Divider(
                              color: Colors.white.withValues(alpha: 0.1),
                              height: 1,
                            ),
                            SizedBox(height: 10.h),
                          ],
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Total Amount to Pay',
                                style: TextStyle(
                                  color: const Color(0xFFD8B26A),
                                  fontSize: 13.5.fSize,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                quote.isFreeReattempt
                                    ? '₹0'
                                    : _formatReattemptAmount(quote.totalPayable),
                                style: TextStyle(
                                  color: quote.isFreeReattempt
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
                    _DeliveryReattemptScheduleFields(
                      onChanged: (date, time) {
                        setSheetState(() {
                          selectedDate = date;
                          selectedSlot = time;
                        });
                      },
                    ),
                    SizedBox(height: 16.h),
                    Text(
                      'DELIVERY NOTES',
                      style: TextStyle(
                        color: AppColours.primary,
                        fontSize: 10.fSize,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.1,
                      ),
                    ),
                    SizedBox(height: 8.h),
                    TextField(
                      controller: notesController,
                      maxLines: 2,
                      style: TextStyle(color: Colors.white, fontSize: 13.fSize),
                      decoration: InputDecoration(
                        hintText: 'Optional delivery instructions',
                        hintStyle: TextStyle(
                          color: Colors.white38,
                          fontSize: 12.fSize,
                        ),
                        filled: true,
                        fillColor: const Color(0xFF16181D),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12.w,
                          vertical: 12.h,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(
                            color: AppColours.primary.withValues(alpha: 0.6),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: AppColours.primary),
                        ),
                      ),
                    ),
                    SizedBox(height: 24.h),
                    SizedBox(
                      width: double.infinity,
                      height: 48.h,
                      child: ElevatedButton(
                        onPressed: () async {
                          final date = selectedDate;
                          final time = selectedSlot?.trim() ?? '';
                          if (date == null || time.isEmpty) {
                            CustomAppSnackBar.showError(
                              sheetContext,
                              'Please select a delivery date and time.',
                            );
                            return;
                          }
                          final apiDateStr =
                              '${date.year.toString().padLeft(4, '0')}-'
                              '${date.month.toString().padLeft(2, '0')}-'
                              '${date.day.toString().padLeft(2, '0')}';
                          final notes = notesController.text.trim();
                          FocusManager.instance.primaryFocus?.unfocus();
                          final sheetRoute = ModalRoute.of(sheetContext);
                          Navigator.pop(sheetContext);
                          await _waitUntilRouteDismissed(sheetRoute);
                          if (!mounted) return;
                          await _submitDeliveryReorder(
                            order,
                            quote,
                            apiDateStr,
                            time,
                            notes: notes,
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
                          quote.isFreeReattempt
                              ? 'Schedule Delivery Reattempt'
                              : 'Pay ${_formatReattemptAmount(quote.totalPayable)} & Schedule',
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
          ),
        );
      },
    );
  }

  Future<void> _waitUntilRouteDismissed(ModalRoute<dynamic>? route) async {
    final animation = route?.animation;
    if (animation == null || animation.status == AnimationStatus.dismissed) {
      return;
    }
    final completer = Completer<void>();
    void listener(AnimationStatus status) {
      if (status == AnimationStatus.dismissed && !completer.isCompleted) {
        animation.removeStatusListener(listener);
        completer.complete();
      }
    }

    animation.addStatusListener(listener);
    if (animation.status == AnimationStatus.dismissed) {
      animation.removeStatusListener(listener);
      return;
    }
    await completer.future;
  }

  String _formatReattemptAmount(num value) {
    if (value == value.roundToDouble()) return '₹${value.toInt()}';
    return '₹${value.toStringAsFixed(2)}';
  }

  Widget _reattemptChargeRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white70,
            fontSize: 12.5.fSize,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: Colors.white,
            fontSize: 13.fSize,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  void _showReattemptLoader() {
    if (!mounted || _reattemptLoaderVisible) return;
    _reattemptLoaderVisible = true;
    final view = ValueNotifier<_ReattemptDialogView>(
      const _ReattemptDialogView.loading(),
    );
    final closed = Completer<void>();
    _reattemptDialogView = view;
    _reattemptDialogClosed = closed;
    showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.72),
      builder: (dialogContext) {
        return ValueListenableBuilder<_ReattemptDialogView>(
          valueListenable: view,
          builder: (context, model, _) {
            if (model.loading) {
              return const _ReattemptLoadingDialog();
            }
            return _buildReattemptSuccessCard(
              message: model.message,
              deliveryDate: model.deliveryDate,
              deliveryTime: model.deliveryTime,
              onOk: () => Navigator.of(dialogContext).pop(),
            );
          },
        );
      },
    ).whenComplete(() {
      _reattemptLoaderVisible = false;
      if (identical(_reattemptDialogView, view)) {
        _reattemptDialogView = null;
      }
      if (identical(_reattemptDialogClosed, closed)) {
        _reattemptDialogClosed = null;
      }
      view.dispose();
      if (!closed.isCompleted) closed.complete();
    });
  }

  void _showReattemptResult({
    required String message,
    required String deliveryDate,
    required String deliveryTime,
  }) {
    final view = _reattemptDialogView;
    if (view == null) return;
    view.value = _ReattemptDialogView.success(
      message: message.trim().isEmpty
          ? 'Successfully joined waitlist'
          : message.trim(),
      deliveryDate: deliveryDate,
      deliveryTime: deliveryTime,
    );
  }

  Future<void> _closeReattemptDialog() async {
    final closed = _reattemptDialogClosed;
    if (_reattemptLoaderVisible && mounted) {
      final navigator = Navigator.of(context, rootNavigator: true);
      if (navigator.canPop()) {
        navigator.pop();
      }
    }
    if (closed != null) {
      await closed.future;
    }
  }

  Future<void> _submitDeliveryReorder(
    UserOrder order,
    ReattemptQuote quote,
    String deliveryDate,
    String deliveryTime, {
    String? notes,
  }) async {
    setState(() => _isReattemptActionLoading = true);
    _showReattemptLoader();

    try {
      if (quote.isFreeReattempt) {
        final message = await _orderRepository.submitReorderRequest(
          orderId: order.id,
          deliveryDate: deliveryDate,
          deliveryTime: deliveryTime,
          notes: notes,
        );
        if (!mounted) return;
        setState(() => _isReattemptActionLoading = false);
        _showReattemptResult(
          message: message,
          deliveryDate: deliveryDate,
          deliveryTime: deliveryTime,
        );
        await _reattemptDialogClosed?.future;
        if (!mounted) return;
        await _loadOrder();
        return;
      }

      final setup = await _orderRepository.reorderDelivery(
        orderId: order.id,
        deliveryDate: deliveryDate,
        deliveryTime: deliveryTime,
      );

      final razorpayOrderId = setup.razorpayOrderId?.trim() ?? '';
      final keyId = setup.razorpayKeyId?.trim() ?? '';
      if (!setup.paymentRequired || razorpayOrderId.isEmpty || keyId.isEmpty) {
        if (!mounted) return;
        setState(() => _isReattemptActionLoading = false);
        _showReattemptResult(
          message: setup.message ??
              'Your delivery reattempt has been scheduled for $deliveryDate ($deliveryTime).',
          deliveryDate: deliveryDate,
          deliveryTime: deliveryTime,
        );
        await _reattemptDialogClosed?.future;
        if (!mounted) return;
        if (!mounted) return;
        Navigator.pushNamed(
          context,
          AppRoutes.orderTrackingScreen,
          arguments: order.id,
        );
        return;
      }

      _pendingReattemptOrderId = order.id;
      _pendingReattemptDeliveryDate = deliveryDate;
      _pendingReattemptDeliveryTime = deliveryTime;

      Customer? customer;
      try {
        customer = await _profileRepository.getProfile();
      } catch (_) {}

      final payablePaise = (quote.totalPayable * 100).round();
      final amountPaise =
          setup.amount >= payablePaise ? setup.amount : payablePaise;

      if (mounted) setState(() => _isReattemptActionLoading = false);
      await _closeReattemptDialog();
      if (!mounted) return;
      _razorpayService.openCheckout(
        keyId: keyId,
        orderId: razorpayOrderId,
        amount: amountPaise,
        currency: setup.currency,
        name: customer?.fullName,
        email: customer?.email,
        contact: customer?.mobile,
        description: 'Delivery reattempt for Order #${order.orderIdDisplay}',
      );
    } on ApiException catch (e) {
      if (mounted) setState(() => _isReattemptActionLoading = false);
      await _closeReattemptDialog();
      if (!mounted) return;
      CustomAppSnackBar.showError(context, e.message);
    } catch (_) {
      if (mounted) setState(() => _isReattemptActionLoading = false);
      await _closeReattemptDialog();
      if (!mounted) return;
      CustomAppSnackBar.showError(
        context,
        'Failed to schedule delivery reattempt. Please try again.',
      );
    }
  }

  String _formatReattemptDateLabel(String raw) {
    final parts = raw.trim().split('-');
    if (parts.length != 3) return raw;
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year == null ||
        month == null ||
        day == null ||
        month < 1 ||
        month > 12) {
      return raw;
    }
    return '${day.toString().padLeft(2, '0')} ${months[month - 1]} $year';
  }

  Future<void> _showReattemptScheduledDialog(
    String message, {
    String? deliveryDate,
    String? deliveryTime,
  }) {
    final date = deliveryDate?.trim() ?? '';
    final time = deliveryTime?.trim() ?? '';
    final text = message.trim().isEmpty
        ? 'Successfully joined waitlist'
        : message.trim();

    return showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (ctx) => _buildReattemptSuccessCard(
        message: text,
        deliveryDate: date,
        deliveryTime: time,
        onOk: () => Navigator.of(ctx).pop(),
      ),
    );
  }

  Widget _buildReattemptSuccessCard({
    required String message,
    required String deliveryDate,
    required String deliveryTime,
    required VoidCallback onOk,
  }) {
    final date = deliveryDate.trim();
    final time = deliveryTime.trim();
    return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.symmetric(horizontal: 24.w),
        child: Container(
          padding: EdgeInsets.fromLTRB(18.w, 22.h, 18.w, 16.h),
          decoration: BoxDecoration(
            color: const Color(0xFF16181D),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: const Color(0xFF10B981).withValues(alpha: 0.35),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64.w,
                height: 64.w,
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.check_circle_rounded,
                  color: const Color(0xFF10B981),
                  size: 36.fSize,
                ),
              ),
              SizedBox(height: 14.h),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16.fSize,
                  fontWeight: FontWeight.bold,
                  height: 1.3,
                ),
              ),
              if (date.isNotEmpty || time.isNotEmpty) ...[
                SizedBox(height: 16.h),
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 12.h),
                  decoration: BoxDecoration(
                    color: const Color(0xFF12141C),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: const Color(0xFFD8B26A).withValues(alpha: 0.35),
                    ),
                  ),
                  child: Column(
                    children: [
                      if (date.isNotEmpty)
                        _reattemptSuccessRow(
                          icon: Icons.calendar_month_rounded,
                          label: 'Delivery Date',
                          value: _formatReattemptDateLabel(date),
                        ),
                      if (date.isNotEmpty && time.isNotEmpty)
                        Padding(
                          padding: EdgeInsets.symmetric(vertical: 10.h),
                          child: Divider(
                            color: Colors.white.withValues(alpha: 0.08),
                            height: 1,
                          ),
                        ),
                      if (time.isNotEmpty)
                        _reattemptSuccessRow(
                          icon: Icons.schedule_rounded,
                          label: 'Delivery Time',
                          value: time,
                        ),
                    ],
                  ),
                ),
              ],
              SizedBox(height: 18.h),
              SizedBox(
                width: double.infinity,
                height: 44.h,
                child: ElevatedButton(
                  onPressed: onOk,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFD8B26A),
          foregroundColor: Colors.black,
                    elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
                  child: Text(
                    'OK',
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
  }

  Widget _reattemptSuccessRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Container(
          width: 36.w,
          height: 36.w,
          decoration: BoxDecoration(
            color: const Color(0xFFD8B26A).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: const Color(0xFFD8B26A), size: 18),
        ),
        SizedBox(width: 12.w),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.toUpperCase(),
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: 9.5.fSize,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.7,
                ),
              ),
              SizedBox(height: 2.h),
              Text(
                value,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14.fSize,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ],
    );
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

      await _showReattemptScheduledDialog(
        res.message ??
            'Payment verified! Delivery reattempt has been scheduled successfully.',
        deliveryDate: date,
        deliveryTime: time,
      );
      if (!mounted) return;
      Navigator.pushNamed(
        context,
        AppRoutes.orderTrackingScreen,
        arguments: orderId,
      );
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
              padding: EdgeInsets.fromLTRB(20.w, 20.h, 20.w, 20.h),
              child: SingleChildScrollView(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(bottomSheetContext).viewInsets.bottom,
                ),
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
    final essentialItems = items.where(_isItemEssentials).toList();
    final subItems = items
        .where((it) =>
            !_isItemKids(it) &&
            !_isItemEssentials(it) &&
            _isItemSubscription(it, order))
        .toList();
    final nonSubItems = items
        .where((it) =>
            !_isItemKids(it) &&
            !_isItemEssentials(it) &&
            !_isItemSubscription(it, order))
        .toList();
    final isSub = order.orderType?.trim().toUpperCase() == 'SUBSCRIPTION' ||
        order.title.toLowerCase().contains('subscription');
    final garmentCount = items.isNotEmpty
        ? items.fold<int>(0, (sum, it) => sum + (it.quantity > 0 ? it.quantity : 1))
        : (order.totalGarmentsCount > 0 ? order.totalGarmentsCount : 1);
    final subCount = subItems.fold<int>(0, (s, i) => s + (i.quantity > 0 ? i.quantity : 1));
    final nonSubCount = nonSubItems.fold<int>(0, (s, i) => s + (i.quantity > 0 ? i.quantity : 1));
    final kidsCount = kidsItems.fold<int>(0, (s, i) => s + (i.quantity > 0 ? i.quantity : 1));
    final essentialsCount =
        essentialItems.fold<int>(0, (s, i) => s + (i.quantity > 0 ? i.quantity : 1));
    num lineAmount(List<OrderLineItem> lines) {
      return lines.fold<num>(
        0,
        (sum, item) =>
            sum + (item.lineTotal > 0 ? item.lineTotal : (item.unitPrice * item.quantity)),
      );
    }

    final kidsAmount = lineAmount(kidsItems);
    final essentialsAmount = lineAmount(essentialItems);
    num kitOnlyAmount = order.kitPrice;
    if (kitOnlyAmount <= 0) {
      final extras = kidsAmount + essentialsAmount;
      if (order.subtotal > extras) {
        kitOnlyAmount = order.subtotal - extras;
      } else {
        kitOnlyAmount = lineAmount(nonSubItems);
      }
    }

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
                    _formatCurrency(kitOnlyAmount),
                  ),
                if (kidsItems.isNotEmpty)
                  _billingSummaryRow(
                    'Kids Collection ($kidsCount ${kidsCount == 1 ? 'item' : 'items'})',
                    _formatCurrency(kidsAmount),
                  ),
                if (essentialItems.isNotEmpty)
                  _billingSummaryRow(
                    'Essentials ($essentialsCount ${essentialsCount == 1 ? 'item' : 'items'})',
                    _formatCurrency(essentialsAmount),
                  ),
                if (subItems.isEmpty &&
                    nonSubItems.isEmpty &&
                    kidsItems.isEmpty &&
                    essentialItems.isEmpty)
                  _billingSummaryRow(
                    'Kit Garments ($garmentCount ${garmentCount == 1 ? 'item' : 'items'})',
                    _formatCurrency(kitOnlyAmount),
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
    final isReturnComplete = order.isReturnComplete;
    final rawStatus = isReturnComplete
        ? 'COMPLETED'
        : (order.isReorderRequested
            ? 'REORDER_REQUESTED'
            : (order.isInReturnFlow
            ? (order.orderStatusRaw ?? 'PICKUP SCHEDULED')
            : (order.orderStatusRaw ??
                    (order.isDelivered ? 'DELIVERED' : 'CONFIRMED'))));
    final statusText = isReturnComplete
        ? 'COMPLETED'
        : rawStatus.replaceAll('_', ' ').toUpperCase();

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
                Align(
                  alignment: Alignment.centerLeft,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 10.w,
                        vertical: 3.h,
                      ),
                  decoration: BoxDecoration(
                        color: isReturnComplete
                            ? const Color(0xFF0D2818)
                            : const Color(0xFF1B160C),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                          color: isReturnComplete
                              ? const Color(0xFF34D399).withValues(alpha: 0.6)
                              : const Color(0xFFD8B26A).withValues(alpha: 0.5),
                    ),
                  ),
                  child: Text(
                    'ORDER STATUS : $statusText',
                        maxLines: 1,
                        softWrap: false,
                    style: TextStyle(
                          color: isReturnComplete
                              ? const Color(0xFF34D399)
                              : const Color(0xFFE6C27A),
                      fontSize: 10.fSize,
                      fontWeight: FontWeight.bold,
                          letterSpacing: 0.4,
                        ),
                      ),
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

class _ReattemptLoadingDialog extends StatefulWidget {
  const _ReattemptLoadingDialog();

  @override
  State<_ReattemptLoadingDialog> createState() =>
      _ReattemptLoadingDialogState();
}

class _ReattemptLoadingDialogState extends State<_ReattemptLoadingDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 230.w,
            padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 24.h),
            decoration: BoxDecoration(
              color: const Color(0xFF16181D),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: const Color(0xFFD8B26A).withValues(alpha: 0.7),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 72.w,
                  height: 72.w,
                  child: AnimatedBuilder(
                    animation: _controller,
                    builder: (context, child) {
                      final pulse = 0.9 +
                          (0.1 *
                              (1 - ((_controller.value - 0.5).abs() * 2)));
                      return Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            width: 72.w,
                            height: 72.w,
                            child: CircularProgressIndicator(
                              strokeWidth: 3,
                              color: const Color(0xFFD8B26A),
                              backgroundColor: const Color(0xFFD8B26A)
                                  .withValues(alpha: 0.18),
                            ),
                          ),
                          Transform.scale(scale: pulse, child: child),
                        ],
                      );
                    },
                    child: Icon(
                      Icons.local_shipping_rounded,
                      color: const Color(0xFFD8B26A),
                      size: 28.w,
                    ),
                  ),
                ),
                SizedBox(height: 16.h),
                Text(
                  'Scheduling delivery',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: const Color(0xFFD8B26A),
                    fontSize: 15.fSize,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 6.h),
                Text(
                  'Please wait while we confirm your reattempt.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12.fSize,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ),
    );
  }
}

class _ReattemptDialogView {
  const _ReattemptDialogView.loading()
      : loading = true,
        message = '',
        deliveryDate = '',
        deliveryTime = '';

  const _ReattemptDialogView.success({
    required this.message,
    required this.deliveryDate,
    required this.deliveryTime,
  }) : loading = false;

  final bool loading;
  final String message;
  final String deliveryDate;
  final String deliveryTime;
}

class _RunOnDispose extends StatefulWidget {
  const _RunOnDispose({required this.action, required this.child});

  final VoidCallback action;
  final Widget child;

  @override
  State<_RunOnDispose> createState() => _RunOnDisposeState();
}

class _RunOnDisposeState extends State<_RunOnDispose> {
  @override
  void dispose() {
    final action = widget.action;
    WidgetsBinding.instance.addPostFrameCallback((_) => action());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _DeliveryReattemptScheduleFields extends StatefulWidget {
  const _DeliveryReattemptScheduleFields({
    super.key,
    required this.onChanged,
    this.dateHeader = 'SELECT DELIVERY DATE',
    this.timeHeader = 'SELECT DELIVERY TIME',
    this.dateHint = 'Select Delivery Date',
    this.timeHint = 'Select Delivery Time',
    this.initialDate,
    this.initialTime,
    this.allowToday = false,
  });

  final void Function(DateTime? date, String? time) onChanged;
  final String dateHeader;
  final String timeHeader;
  final String dateHint;
  final String timeHint;
  final DateTime? initialDate;
  final String? initialTime;
  final bool allowToday;

  @override
  State<_DeliveryReattemptScheduleFields> createState() =>
      _DeliveryReattemptScheduleFieldsState();
}

class _DeliveryReattemptScheduleFieldsState
    extends State<_DeliveryReattemptScheduleFields> {
  DateTime? _selectedDeliveryDate;
  late DateTime _calendarMonth;
  bool _showCalendar = false;
  bool _showTimePicker = false;
  int _selectedHour = 12;
  int _selectedMinute = 40;
  bool _isAM = false;
  String? _selectedTimeLabel;
  late final FixedExtentScrollController _hourController;
  late final FixedExtentScrollController _minuteController;
  late final FixedExtentScrollController _periodController;

  DateTime get _todayDateOnly {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  @override
  void initState() {
    super.initState();
    _selectedDeliveryDate = widget.initialDate;
    _selectedTimeLabel = widget.initialTime;
    if (_selectedTimeLabel != null) {
      _parseInitialTime(_selectedTimeLabel!);
    }
    final now = DateTime.now();
    _calendarMonth = _selectedDeliveryDate != null
        ? DateTime(_selectedDeliveryDate!.year, _selectedDeliveryDate!.month, 1)
        : DateTime(now.year, now.month, 1);
    _hourController = FixedExtentScrollController(initialItem: _selectedHour - 1);
    _minuteController = FixedExtentScrollController(initialItem: _selectedMinute);
    _periodController = FixedExtentScrollController(initialItem: _isAM ? 1 : 0);
  }

  void _parseInitialTime(String time) {
    final match = RegExp(r'^(\d{1,2}):(\d{2})\s*(AM|PM)$', caseSensitive: false)
        .firstMatch(time.trim());
    if (match != null) {
      final h = int.tryParse(match.group(1)!) ?? 12;
      final m = int.tryParse(match.group(2)!) ?? 0;
      final p = match.group(3)!.toUpperCase();
      _selectedHour = (h >= 1 && h <= 12) ? h : 12;
      _selectedMinute = (m >= 0 && m <= 59) ? m : 0;
      _isAM = p == 'AM';
    }
  }

  @override
  void dispose() {
    _hourController.dispose();
    _minuteController.dispose();
    _periodController.dispose();
    super.dispose();
  }

  void _notify() {
    widget.onChanged(_selectedDeliveryDate, _selectedTimeLabel);
  }

  String _formatDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day.toString().padLeft(2, '0')} ${months[d.month - 1]} ${d.year}';
  }

  String _monthYearLabel(DateTime m) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return '${months[m.month - 1]} ${m.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.dateHeader,
                    style: TextStyle(
                      color: AppColours.primary,
                      fontSize: 10.fSize,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.1,
                    ),
                  ),
                  SizedBox(height: 12.h),
                  _buildDeliveryDateField(),
                ],
              ),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.timeHeader,
                    style: TextStyle(
                      color: AppColours.primary,
                      fontSize: 10.fSize,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.1,
                    ),
                  ),
                  SizedBox(height: 12.h),
                  _buildDeliveryTimeField(),
                ],
              ),
            ),
          ],
        ),
        if (_showCalendar) ...[
          SizedBox(height: 10.h),
          _buildInlineCalendar(),
        ],
        if (_showTimePicker) ...[
          SizedBox(height: 8.h),
          _buildInlineTimePicker(),
        ],
      ],
    );
  }

  Widget _buildDeliveryDateField() {
    return GestureDetector(
      onTap: () => setState(() {
        _showCalendar = !_showCalendar;
        if (_showCalendar) _showTimePicker = false;
      }),
      child: Container(
        height: 50.h,
        padding: EdgeInsets.symmetric(horizontal: 12.w),
        decoration: BoxDecoration(
          color: const Color(0xFF16181D),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColours.primary, width: 0.6),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _selectedDeliveryDate != null
                    ? _formatDate(_selectedDeliveryDate!)
                    : widget.dateHint,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _selectedDeliveryDate != null
                      ? Colors.white
                      : AppColours.hintcolor,
                  fontSize: 12.fSize,
                ),
              ),
            ),
            Icon(
              Icons.calendar_today_outlined,
              color: AppColours.primary,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeliveryTimeField() {
    return GestureDetector(
      onTap: () => setState(() {
        _showTimePicker = !_showTimePicker;
        if (_showTimePicker) _showCalendar = false;
      }),
      child: Container(
        height: 50.h,
        padding: EdgeInsets.symmetric(horizontal: 12.w),
        decoration: BoxDecoration(
          color: const Color(0xFF16181D),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColours.primary, width: 0.6),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _selectedTimeLabel ?? widget.timeHint,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _selectedTimeLabel != null
                      ? Colors.white
                      : AppColours.hintcolor,
                  fontSize: 12.fSize,
                ),
              ),
            ),
            SizedBox(
              width: 16.w,
              height: 16.w,
              child: Transform.rotate(
                angle: _showTimePicker ? 0 : pi,
                child: SvgPicture.asset(
                  IconConstant.dropDown1,
                  width: 16.w,
                  height: 16.w,
                  fit: BoxFit.contain,
                  colorFilter: ColorFilter.mode(
                    AppColours.primary,
                    BlendMode.srcIn,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInlineTimePicker() {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 12.h, horizontal: 12.w),
      decoration: BoxDecoration(
        color: const Color(0xFF16181D),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColours.primary.withOpacity(0.5)),
      ),
      child: Column(
        children: [
          Text(
            'Select Time',
            style: TextStyle(
              color: AppColours.primary,
              fontSize: 14.fSize,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 8.h),
          SizedBox(
            height: 160.h,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildWheel(
                  controller: _hourController,
                  itemCount: 12,
                  labelBuilder: (i) => '${i + 1}'.padLeft(2, '0'),
                  selectedIndex: _selectedHour - 1,
                  onChanged: (i) => setState(() => _selectedHour = i + 1),
                ),
                Text(
                  ':',
                  style: TextStyle(
                    color: AppColours.primary,
                    fontSize: 20.fSize,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                _buildWheel(
                  controller: _minuteController,
                  itemCount: 60,
                  labelBuilder: (i) => i.toString().padLeft(2, '0'),
                  selectedIndex: _selectedMinute,
                  onChanged: (i) => setState(() => _selectedMinute = i),
                ),
                _buildWheel(
                  controller: _periodController,
                  itemCount: 2,
                  labelBuilder: (i) => i == 0 ? 'PM' : 'AM',
                  selectedIndex: _isAM ? 1 : 0,
                  onChanged: (i) => setState(() => _isAM = i == 1),
                  width: 48,
                ),
              ],
            ),
          ),
          SizedBox(height: 8.h),
          GestureDetector(
            onTap: () {
              setState(() {
                final period = _isAM ? 'AM' : 'PM';
                _selectedTimeLabel =
                    '${_selectedHour.toString().padLeft(2, '0')}:${_selectedMinute.toString().padLeft(2, '0')} $period';
                _showTimePicker = false;
              });
              _notify();
            },
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(vertical: 10.h),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColours.primary,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Save',
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 13.fSize,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInlineCalendar() {
    final nowMonthStart = DateTime(_todayDateOnly.year, _todayDateOnly.month, 1);
    final isCurrentMonth = _calendarMonth.year == nowMonthStart.year &&
        _calendarMonth.month == nowMonthStart.month;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 14.h),
      decoration: BoxDecoration(
        color: const Color(0xFF16181D),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColours.primary.withOpacity(0.6)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                onPressed: isCurrentMonth
                    ? null
                    : () {
                        setState(() {
                          _calendarMonth = DateTime(
                            _calendarMonth.year,
                            _calendarMonth.month - 1,
                          );
                        });
                      },
                icon: Icon(
                  Icons.chevron_left,
                  color: isCurrentMonth ? Colors.white24 : AppColours.primary,
                  size: 26,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
              Text(
                _monthYearLabel(_calendarMonth),
                style: TextStyle(
                  color: AppColours.primary,
                  fontSize: 15.fSize,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                onPressed: () {
                  setState(() {
                    _calendarMonth = DateTime(
                      _calendarMonth.year,
                      _calendarMonth.month + 1,
                    );
                  });
                },
                icon: Icon(
                  Icons.chevron_right,
                  color: AppColours.primary,
                  size: 26,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
            ],
          ),
          SizedBox(height: 8.h),
          Row(
            children: ['S', 'M', 'T', 'W', 'T', 'F', 'S']
                .map(
                  (d) => Expanded(
                    child: Center(
                      child: Text(
                        d,
                        style: TextStyle(
                          color: AppColours.primary,
                          fontSize: 11.fSize,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          SizedBox(height: 8.h),
          _buildCalendarGrid(),
        ],
      ),
    );
  }

  Widget _buildCalendarGrid() {
    final y = _calendarMonth.year;
    final m = _calendarMonth.month;
    final first = DateTime(y, m, 1);
    final daysInMonth = DateTime(y, m + 1, 0).day;
    final leading = first.weekday % 7;
    final totalCells = ((leading + daysInMonth + 6) ~/ 7) * 7;
    final cells = <Widget>[];

    for (int i = 0; i < totalCells; i++) {
      final dayNum = i - leading + 1;
      if (dayNum < 1 || dayNum > daysInMonth) {
        cells.add(const SizedBox(height: 40));
      } else {
        final date = DateTime(y, m, dayNum);
        final earliest = widget.allowToday
            ? _todayDateOnly
            : _todayDateOnly.add(const Duration(days: 1));
        final isPastDate = date.isBefore(earliest);
        final isSelected = _selectedDeliveryDate != null &&
            _selectedDeliveryDate!.year == date.year &&
            _selectedDeliveryDate!.month == date.month &&
            _selectedDeliveryDate!.day == date.day;
        cells.add(
          GestureDetector(
            onTap: isPastDate
                ? null
                : () {
                    setState(() => _selectedDeliveryDate = date);
                    _notify();
                  },
            child: SizedBox(
              height: 40,
              child: Center(
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected ? AppColours.primary : Colors.transparent,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '$dayNum',
                    style: TextStyle(
                      color: isSelected
                          ? Colors.black
                          : (isPastDate ? Colors.white24 : Colors.white70),
                      fontSize: 14.fSize,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }
    }

    return GridView.count(
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 4,
      children: cells,
    );
  }

  Widget _buildWheel({
    required FixedExtentScrollController controller,
    required int itemCount,
    required String Function(int) labelBuilder,
    required int selectedIndex,
    required ValueChanged<int> onChanged,
    double width = 52,
  }) {
    return SizedBox(
      width: width.w,
      child: ListWheelScrollView.useDelegate(
        controller: controller,
        itemExtent: 36.h,
        perspective: 0.003,
        diameterRatio: 1.6,
        physics: const FixedExtentScrollPhysics(),
        onSelectedItemChanged: onChanged,
        childDelegate: ListWheelChildBuilderDelegate(
          childCount: itemCount,
          builder: (context, index) {
            final isSelected = index == selectedIndex;
            return Center(
              child: Text(
                labelBuilder(index),
                style: TextStyle(
                  color: isSelected ? AppColours.primary : AppColours.secondary,
                  fontSize: isSelected ? 18.fSize : 14.fSize,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            );
          },
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
