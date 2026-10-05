import 'package:dotted_border/dotted_border.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:nomowear/core/app_export.dart';
import 'package:nomowear/core/network/api_exception.dart';
import 'package:nomowear/core/services/razorpay_service.dart';
import 'package:nomowear/features/cart/data/models/remote_cart.dart';
import 'package:nomowear/features/cart/presentation/bloc/cart_bloc.dart';
import 'package:nomowear/features/cart/presentation/utils/cart_limits.dart';
import 'package:nomowear/features/cart/presentation/widgets/cart_quantity_control.dart';
import 'package:nomowear/features/cart/presentation/widgets/qty_picker_sheet.dart';
import 'package:nomowear/features/checkout/data/checkout_session.dart';
import 'package:nomowear/features/checkout/data/subscription_kit_preferences.dart';
import 'package:nomowear/features/checkout/presentation/utils/checkout_initiate_request.dart';
import 'package:nomowear/features/checkout/presentation/utils/checkout_pricing.dart';
import 'package:nomowear/features/checkout/presentation/utils/subscription_booking_eligibility.dart';
import 'package:nomowear/features/orders/data/models/initiate_order_result.dart';
import 'package:nomowear/features/orders/data/order_repository.dart';
import 'package:nomowear/features/orders/presentation/widgets/no_return_blocked_dialog.dart';
import 'package:nomowear/features/orders/data/orders_cache.dart';
import 'package:nomowear/features/profile/data/profile_cache.dart';
import 'package:nomowear/features/profile/data/profile_repository.dart';
import 'package:nomowear/features/profile/domain/user_order.dart';
import 'package:nomowear/features/profile/presentation/utils/profile_order_guard.dart';
import 'package:nomowear/features/checkout/data/wardrobe_booking_session.dart';
import 'package:nomowear/features/products/data/models/product_variant.dart';
import 'package:nomowear/features/products/data/product_cache.dart';
import 'package:nomowear/features/products/data/product_mapper.dart';
import 'package:nomowear/features/wardrobe/presentation/widgets/variant_selection_sheet.dart';
import 'package:nomowear/features/subscriptions/data/subscription_garment_balance.dart';
import 'package:nomowear/features/subscriptions/data/subscription_repository.dart';
import 'package:nomowear/features/subscriptions/data/subscription_cache.dart';
import 'package:nomowear/features/checkout/presentation/widgets/payment_pending_confirmation_sheet.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

import '../../../cart/presentation/widgets/reusable_product_cart_item.dart';

class EssentialsCheckoutScreen extends StatefulWidget {
  const EssentialsCheckoutScreen({
    Key? key,
    this.initialPrefetch,
  }) : super(key: key);

  final CheckoutPrefetchPayload? initialPrefetch;

  @override
  State<EssentialsCheckoutScreen> createState() =>
      _EssentialsCheckoutScreenState();
}

class _EssentialsCheckoutScreenState extends State<EssentialsCheckoutScreen> {
  final TextEditingController _noteController = TextEditingController();
  final OrderRepository _orderRepository = OrderRepository();
  final SubscriptionRepository _subscriptionRepository =
      SubscriptionRepository();
  final RazorpayService _razorpayService = RazorpayService();

  bool _isPlacingOrder = false;
  bool _wardrobeGarmentsExpanded = false;

  bool _hasOpenedPayment = false;
  String? _activePendingOrderId;
  CheckoutPayableSnapshot? _activePendingSnapshot;

  // CHANGE: Backend-only payable snapshot (initiate-order amount = Razorpay amount).
  CheckoutPayableSnapshot? _payableSnapshot;
  bool _isLoadingPayable = true;
  String? _payableError;
  String? _payableCartFingerprint;
  Future<void>? _payableLoadFuture;

  static const List<String> _allSizes = ['XS', 'S', 'M', 'L', 'XL', 'XXL', 'XXXL'];
  static const int _essentialsMaxQty = 5;

  @override
  void initState() {
    super.initState();
    final savedNote = CheckoutSession.instance.orderNote;
    if (savedNote != null && savedNote.isNotEmpty) {
      _noteController.text = savedNote;
    }
    final initial = widget.initialPrefetch;
    if (initial != null) {
      _payableSnapshot = initial.snapshot;
      _payableCartFingerprint = initial.cartFingerprint;
      _isLoadingPayable = false;
      _payableError = null;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final state = context.read<CartBloc>().state;
      if (state.isEmpty) {
        context.read<CartBloc>().add(
              LoadCartEvent(source: 'EssentialsCheckout.initState'),
            );
        return;
      }
      final fp = CheckoutPricing.cartFingerprint(state);
      // Prefetch can be stale if qty changed on Place Order before opening this screen.
      if (_payableSnapshot == null || _payableCartFingerprint != fp) {
        _loadAuthoritativePayable(state);
      }
    });
    _razorpayService.init(
      onSuccess: _onPaymentSuccess,
      onFailure: _onPaymentFailure,
    );
  }

  @override
  void dispose() {
    _razorpayService.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _onPaymentSuccess(PaymentSuccessResponse response) {
    _completePaymentVerification(response);
  }

  Future<void> _completePaymentVerification(
    PaymentSuccessResponse response,
  ) async {
    final orderId = response.orderId?.trim() ?? '';
    final paymentId = response.paymentId?.trim() ?? '';
    final signature = response.signature?.trim() ?? '';

    if (orderId.isEmpty || paymentId.isEmpty || signature.isEmpty) {
      if (!mounted) return;
      setState(() => _isPlacingOrder = false);
      CustomAppSnackBar.showError(
        context,
        'Payment details incomplete. Please contact support.',
      );
      return;
    }

    setState(() => _isPlacingOrder = true);

    try {
      final verified = await _orderRepository.verifyPayment(
        razorpayOrderId: orderId,
        razorpayPaymentId: paymentId,
        razorpaySignature: signature,
      );
      if (!mounted) return;
      _finishOrderSuccess(
        verified.orderId,
        orderNumber: verified.orderNumber,
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _isPlacingOrder = false);
      CustomAppSnackBar.showError(context, e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isPlacingOrder = false);
      CustomAppSnackBar.showError(
        context,
        'Unable to verify payment. Please try again.',
      );
    }
  }

  void _onPaymentFailure(PaymentFailureResponse response) {
    if (!mounted) return;
    setState(() => _isPlacingOrder = false);

    final pendingId = _activePendingOrderId;
    final pendingSnapshot = _activePendingSnapshot ?? _payableSnapshot;

    if (pendingId != null && pendingId.isNotEmpty && pendingSnapshot != null) {
      _showPendingOrderConfirmation(
        orderId: pendingId,
        snapshot: pendingSnapshot,
      );
    } else {
      CustomAppSnackBar.showInfo(
        context,
        response.message ?? 'Payment cancelled or failed',
      );
    }
  }

  void _showPendingOrderConfirmation({
    required String orderId,
    required CheckoutPayableSnapshot snapshot,
  }) {
    if (!mounted) return;
    final state = context.read<CartBloc>().state;
    final displayAmt = snapshot.initiate.displayRupees > 0
        ? snapshot.initiate.displayRupees
        : (snapshot.gatewayAmountPaise / 100).round();

    showPaymentPendingConfirmationSheet(
      context,
      orderId: orderId,
      amountRupees: displayAmt,
      onRetry: () {
        _openRazorpayForSnapshot(snapshot, state);
      },
      onCancel: () async {
        try {
          final res = await _orderRepository.cancelPendingOrder(orderId);
          final message =
              res['message']?.toString() ?? 'Order cancelled successfully';
          if (!mounted) return;
          setState(() {
            _activePendingOrderId = null;
            _activePendingSnapshot = null;
            _hasOpenedPayment = false;
          });
          // Refresh cart on cancel so reserved stock is freed
          context.read<CartBloc>().refresh(source: 'CancelPendingOrder');
          if (mounted && Navigator.canPop(context)) {
            Navigator.pop(context);
          }
          CustomAppSnackBar.showSuccess(
            context,
            message,
            title: 'Order Cancelled',
          );
        } on ApiException catch (e) {
          if (!mounted) return;
          CustomAppSnackBar.showError(context, e.message);
          rethrow;
        } catch (_) {
          if (!mounted) return;
          CustomAppSnackBar.showError(
            context,
            'Failed to cancel order. Please try again.',
          );
          rethrow;
        }
      },
    );
  }

  void _finishOrderSuccess(
    String orderId, {
    String? orderNumber,
    bool wasSubscriptionBooking = false,
  }) async {
    _hasOpenedPayment = false;
    _activePendingOrderId = null;
    _activePendingSnapshot = null;
    if (kDebugMode) {
      debugPrint('[PAYMENT_FLOW] PAYMENT_SUCCESS');
    }
    var displayNumber = orderNumber?.trim() ?? '';
    if (displayNumber.isEmpty) {
      try {
        final detail = await _orderRepository.getOrderDetail(orderId);
        if (detail.orderNumber.trim().isNotEmpty) {
          displayNumber = detail.orderNumber.trim();
        }
      } catch (_) {
        // Fall back to internal id when lookup fails.
      }
    }
    if (displayNumber.isEmpty) displayNumber = orderId;

    if (wasSubscriptionBooking) {
      await SubscriptionKitPreferences.instance
          .markFirstSubscriptionBookingCompleted();
    }

    if (!mounted) return;
    final completedBookingGarments =
        context.read<CartBloc>().state.currentBookingSelectedGarments;
    if (kDebugMode) {
      debugPrint(
        '[PAYMENT_SUCCESS] completedBookingGarments=$completedBookingGarments',
      );
    }

    await WardrobeBookingSession.instance.markPaymentCompleted();
    await WardrobeBookingSession.instance.startNewBooking();

    if (!mounted) return;
    OrdersCache.instance.clear();
    userOrdersList.clear();
    CheckoutSession.instance.clearDeliveryDetails();
    CheckoutSession.instance.clearOrderNote();
    CheckoutSession.instance.clearWardrobeCategoryLock();
    // Reset temporary booking-mode flags so the next Home visit shows fresh
    // subscription options instead of locking into the previous flow.
    CheckoutSession.instance.clearBookingModeSelection();
    if (kDebugMode) {
      debugPrint(
        '[SUBSCRIPTION_FLOW] paymentSuccess=true '
        'continueWithoutMembership=${CheckoutSession.instance.continueWithoutMembership} '
        'useSubscriptionBooking=${CheckoutSession.instance.useSubscriptionBooking} '
        'bookingMode=${CheckoutSession.instance.bookingMode.name} '
        'wardrobeSessionPath=${WardrobeBookingSession.instance.selectedPath.name}',
      );
    }
    final remaining =
        await SubscriptionGarmentBalance.resolveAndCache(forceRefresh: true);
    final active = SubscriptionCache.instance.activeSubscription;
    if (kDebugMode) {
      debugPrint(
        '[PAYMENT_SUCCESS] booking completed '
        'subscription remaining garments=$remaining '
        'totalBookings=${active?.noOfBookings} '
        'usedBookings=${active?.bookingsUsed} '
        'remainingBookings=${active?.remainingBookings} '
        'booking session closed',
      );
    }
    if (!mounted) return;

    // Refresh cart from backend (which should now be empty after payment)
    // instead of sending individual DELETE requests for each item.
    if (kDebugMode) {
      debugPrint('[CART_AFTER_PAYMENT] REFRESH_START');
    }
    try {
      final remote =
          await context.read<CartBloc>().refresh(source: 'payment_success');
      if (kDebugMode) {
        debugPrint(
          '[CART_AFTER_PAYMENT] REFRESH_COMPLETE item_count=${remote.items.length}',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[CART_AFTER_PAYMENT] REFRESH_ERROR $e');
      }
    }

    if (!mounted) return;
    if (kDebugMode) {
      debugPrint('[PAYMENT_FLOW] NAVIGATING_TO_ORDER_SUCCESS');
    }
    Navigator.pushReplacementNamed(
      context,
      AppRoutes.orderSuccessScreen,
      arguments: {
        'orderId': orderId,
        'orderNumber': displayNumber,
      },
    );
  }

  /// Pure subscription wardrobe booking — no paid rental or purchase lines.
  bool _isSubscriptionWardrobeBooking(CartState state) {
    if (state.wardrobeItems.isEmpty) return false;
    if (state.essentialItems.isNotEmpty) return false;
    if (state.hasPaidRentalGarments) return false;
    if (state.hasMixedWardrobeTypes) return false;
    if (CheckoutSession.instance.continueWithoutMembership) return false;
    return CheckoutSession.instance.useSubscriptionBooking;
  }

  bool get _isInteractionLocked =>
      _isPlacingOrder ||
      (_isLoadingPayable && _payableSnapshot == null) ||
      (_payableLoadFuture != null && _payableSnapshot == null);

  Future<void> _loadAuthoritativePayable(CartState state) async {
    if (_isSubscriptionWardrobeBooking(state)) {
      if (!mounted) return;
      setState(() {
        _isLoadingPayable = false;
        _payableSnapshot = null;
        _payableError = null;
      });
      return;
    }

    var fingerprint = CheckoutPricing.cartFingerprint(state);
    if (_payableSnapshot != null &&
        _payableCartFingerprint == fingerprint &&
        !_isLoadingPayable &&
        _payableLoadFuture == null) {
      return;
    }

    if (mounted) {
      setState(() {
        _isLoadingPayable = true;
        _payableError = null;
      });
    }

    if (_payableLoadFuture != null) {
      await _payableLoadFuture;
      if (!mounted) return;
      final latest = context.read<CartBloc>().state;
      final latestFp = CheckoutPricing.cartFingerprint(latest);
      if (_payableSnapshot != null &&
          _payableCartFingerprint == latestFp &&
          !_isLoadingPayable) {
        return;
      }
      state = latest;
      fingerprint = latestFp;
      if (mounted) {
        setState(() {
          _isLoadingPayable = true;
          _payableError = null;
        });
      }
    }

    _payableLoadFuture = _fetchAuthoritativePayable(state, fingerprint);
    try {
      await _payableLoadFuture;
    } finally {
      _payableLoadFuture = null;
    }
  }

  /// Syncs cart with backend, initiates order once, stores payable for UI + Razorpay.
  Future<void> _fetchAuthoritativePayable(
    CartState state,
    String fingerprint,
  ) async {
    try {
      final remoteCart =
          await context.read<CartBloc>().refresh(source: 'EssentialsCheckout.ensure');
      final initiate = await _initiateCheckoutOrder(state);
      if (!mounted) return;

      // Cart may have changed again while this request was in flight.
      final latest = context.read<CartBloc>().state;
      final latestFp = CheckoutPricing.cartFingerprint(latest);
      if (latestFp != fingerprint) {
        setState(() {
          _isLoadingPayable = true;
        });
        await _fetchAuthoritativePayable(latest, latestFp);
        return;
      }

      if (!initiate.canOpenRazorpay) {
        setState(() {
          _isLoadingPayable = false;
          _payableError = initiate.requiresPayment
              ? 'Payment details missing from server. Please try again.'
              : 'Unable to load payable amount. Please try again.';
        });
        return;
      }

      final snapshot = CheckoutPricing.payableSnapshot(
        remoteCart: remoteCart.isEmpty
            ? const RemoteCart(id: '', items: [])
            : remoteCart,
        initiate: initiate,
        cartState: state,
      );

      setState(() {
        _payableSnapshot = snapshot;
        _payableCartFingerprint = fingerprint;
        _isLoadingPayable = false;
        _payableError = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingPayable = false;
        _payableError = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoadingPayable = false;
        _payableError = 'Unable to load order total. Please try again.';
      });
    }
  }

  Future<InitiateOrderResult> _initiateCheckoutOrder(CartState state) async {
    final note = _currentOrderNote();
    CheckoutSession.instance.setOrderNote(note);
    final req = CheckoutInitiateRequest.fromCart(state);
    return _orderRepository.initiateOrder(
      checkoutType: req.checkoutType,
      nonSubscription: req.nonSubscription,
      productClass: req.productClass,
      wardrobeKitId: req.wardrobeKitId,
      orderNote: note,
    );
  }

  String? _currentOrderNote() {
    final note = _noteController.text.trim();
    return note.isEmpty ? null : note;
  }

  bool _canProceedToPaymentFor(CartState state) {
    final fp = CheckoutPricing.cartFingerprint(state);
    return !_isLoadingPayable &&
        _payableLoadFuture == null &&
        _payableError == null &&
        _payableSnapshot != null &&
        _payableCartFingerprint == fp &&
        _payableSnapshot!.initiate.canOpenRazorpay;
  }

  OrderSummary? _displaySummary(CartState state) {
    if (_isSubscriptionWardrobeBooking(state)) return null;

    final fp = CheckoutPricing.cartFingerprint(state);
    final snapshot = _payableSnapshot;
    if (snapshot != null && _payableCartFingerprint == fp) {
      return snapshot.summary;
    }
    if (state.remote.totalAmount > 0 || state.remote.subtotal > 0) {
      final sub = state.remote.subtotal.round();
      final del = state.remote.deliveryCharge.round();
      final disc = state.remote.discountAmount.round();
      final gst = state.remote.taxAmount.round();
      final tot = state.remote.totalAmount.round();
      return OrderSummary(
        subtotal: sub,
        deliveryFee: del,
        discountAmount: disc,
        gst: gst,
        total: tot > 0 ? tot : (sub + del + gst - disc),
        wardrobeKitAmount: 0,
        essentialsAmount: 0,
      );
    }
    return snapshot?.summary;
  }

  Future<void> _placeOrder(CartState state) async {
    if (_isPlacingOrder) return;

    final canPlaceOrder = await ProfileOrderGuard.ensureCompleteProfile(context);
    if (!canPlaceOrder || !mounted) return;

    // Ensure payable matches latest qty before opening Razorpay.
    final fp = CheckoutPricing.cartFingerprint(state);
    if (!_isSubscriptionWardrobeBooking(state) &&
        (_payableSnapshot == null ||
            _payableCartFingerprint != fp ||
            _isLoadingPayable ||
            _payableLoadFuture != null)) {
      await _loadAuthoritativePayable(state);
      if (!mounted) return;
      state = context.read<CartBloc>().state;
      if (!_canProceedToPaymentFor(state)) {
        CustomAppSnackBar.showError(
          context,
          _payableError ??
              'Unable to refresh payment amount. Please try again.',
        );
        return;
      }
    }

    setState(() => _isPlacingOrder = true);

    final useSubscriptionWardrobeBooking =
        _isSubscriptionWardrobeBooking(state);

    try {
      if (useSubscriptionWardrobeBooking) {
        final eligibility = await SubscriptionBookingEligibility.check(
          repository: _subscriptionRepository,
          forceRefresh: true,
        );
        if (!mounted) return;

        if (!eligibility.canBookWithSubscription) {
          setState(() => _isPlacingOrder = false);
          CustomAppSnackBar.showError(context, eligibility.unavailableMessage);
          return;
        }

        final wardrobeKitId =
            state.wardrobeKitProductId ?? state.wardrobeKitId;
        final note = _currentOrderNote();
        CheckoutSession.instance.setOrderNote(note);
        final bookingResult = await _orderRepository.initiateOrder(
          checkoutType: 'kit',
          nonSubscription: false,
          productClass: 'wardrobe_kit',
          wardrobeKitId: wardrobeKitId,
          orderNote: note,
        );

        if (!mounted) return;

        if (bookingResult.canOpenRazorpay) {
          final remoteCart = await context
              .read<CartBloc>()
              .refresh(source: 'EssentialsCheckout.subscriptionBooking');
          if (!mounted) return;
          final snapshot = CheckoutPricing.payableSnapshot(
            remoteCart: remoteCart,
            initiate: bookingResult,
            cartState: state,
          );
          setState(() {
            _payableSnapshot = snapshot;
            _payableCartFingerprint = CheckoutPricing.cartFingerprint(state);
            _isPlacingOrder = false;
          });
          await _openRazorpayForSnapshot(snapshot, state);
          return;
        }

        if (bookingResult.orderId.isNotEmpty &&
            (bookingResult.isFreeSubscriptionBooking ||
                bookingResult.isConfirmed ||
                !bookingResult.requiresPayment)) {
          _finishOrderSuccess(
            bookingResult.orderId,
            orderNumber: bookingResult.orderNumber,
            wasSubscriptionBooking: true,
          );
          return;
        }

        setState(() => _isPlacingOrder = false);
        CustomAppSnackBar.showError(
          context,
          bookingResult.requiresPayment
              ? 'Payment details missing from server. Please try again.'
              : 'Unable to confirm wardrobe booking. Please try again.',
        );
        return;
      }

      // Re-initiate with the latest order note before payment.
      final note = _currentOrderNote();
      CheckoutSession.instance.setOrderNote(note);
      final req = CheckoutInitiateRequest.fromCart(state);
      final freshInitiate = await _orderRepository.initiateOrder(
        checkoutType: req.checkoutType,
        nonSubscription: req.nonSubscription,
        productClass: req.productClass,
        wardrobeKitId: req.wardrobeKitId,
        orderNote: note,
      );

      if (!mounted) return;
      if (!freshInitiate.canOpenRazorpay) {
        setState(() => _isPlacingOrder = false);
        CustomAppSnackBar.showError(
          context,
          freshInitiate.requiresPayment
              ? 'Payment details missing from server. Please try again.'
              : 'Unable to start payment. Please try again.',
        );
        return;
      }

      final remoteCart = await context.read<CartBloc>().refresh(
            source: 'EssentialsCheckout.placeOrder',
          );
      if (!mounted) return;

      final snapshot = CheckoutPricing.payableSnapshot(
        remoteCart: remoteCart.isEmpty
            ? const RemoteCart(id: '', items: [])
            : remoteCart,
        initiate: freshInitiate,
        cartState: state,
      );

      setState(() => _isPlacingOrder = false);
      await _openRazorpayForSnapshot(snapshot, state);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _isPlacingOrder = false);
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
      if (!mounted) return;
      setState(() => _isPlacingOrder = false);
      CustomAppSnackBar.showError(
        context,
        'Unable to place order. Please try again.',
      );
    }
  }

  Future<void> _openRazorpayForSnapshot(
    CheckoutPayableSnapshot snapshot,
    CartState state,
  ) async {
    _hasOpenedPayment = true;
    _activePendingSnapshot = snapshot;
    _activePendingOrderId = snapshot.initiate.orderId;

    final result = snapshot.initiate;
    var customer = ProfileCache.instance.customer;
    if (customer == null) {
      try {
        customer = await ProfileRepository().getProfile();
      } catch (_) {
        customer = null;
      }
    }

    _razorpayService.openCheckout(
      keyId: result.razorpayKeyId!,
      orderId: result.razorpayOrderId!,
      amount: snapshot.gatewayAmountPaise,
      currency: result.currency,
      name: customer?.fullName,
      email: customer?.email,
      contact: customer?.mobile,
      description: state.wardrobeItems.isNotEmpty
          ? 'Nomowear wardrobe kit order'
          : 'Nomowear essentials order',
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<CartBloc, CartState>(
      listenWhen: (previous, current) {
        if (previous.items.isNotEmpty && current.isEmpty) return true;
        if (previous.items.isEmpty && current.items.isNotEmpty) return true;
        return CheckoutPricing.cartFingerprint(previous) !=
            CheckoutPricing.cartFingerprint(current);
      },
      listener: (context, state) {
        if (_isPlacingOrder) return;
        if (state.isEmpty && Navigator.canPop(context)) {
          Navigator.pop(context);
          return;
        }
        // Reload backend payable when cart contents change (size/qty/items).
        if (!state.isEmpty) {
          _loadAuthoritativePayable(state);
        }
      },
      builder: (context, state) {
        if (state.isEmpty && !_isPlacingOrder) {
          return Scaffold(
            backgroundColor: const Color(0xFF0F1012),
            body: const SizedBox.shrink(),
          );
        }

        final subscriptionBooking = _isSubscriptionWardrobeBooking(state);
        final summary = _displaySummary(state);

        return PopScope(
          canPop: !_hasOpenedPayment ||
              _activePendingOrderId == null ||
              _activePendingOrderId!.isEmpty,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;
            if (_hasOpenedPayment &&
                _activePendingOrderId != null &&
                _activePendingOrderId!.isNotEmpty) {
              final pendingSnapshot =
                  _activePendingSnapshot ?? _payableSnapshot;
              if (pendingSnapshot != null) {
                _showPendingOrderConfirmation(
                  orderId: _activePendingOrderId!,
                  snapshot: pendingSnapshot,
                );
              }
            }
          },
          child: Scaffold(
            backgroundColor: const Color(0xFF0F1012),
            body: Stack(
            children: [
              AbsorbPointer(
                absorbing: _isInteractionLocked,
                child: SafeArea(
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
                      SizedBox(height: 30,),
                      Expanded(
                        child: SingleChildScrollView(
                          padding: EdgeInsets.fromLTRB(16.w, 14.h, 16.w, 20.h),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [

                              _buildSelectedGarments(state),
                              SizedBox(height: 20.h),
                              _buildDeliveryDetails(),
                              SizedBox(height: 20.h),
                              _buildAddNote(),
                              SizedBox(height: 20.h),
                              _buildOrderSummary(
                                subtotal: summary?.subtotal ?? 0,
                                deliveryFee: summary?.deliveryFee ?? 0,
                                discountAmount: summary?.discountAmount ?? 0,
                                gst: summary?.gst ?? 0,
                                total: summary?.total ?? 0,
                                wardrobeKitAmount: summary?.wardrobeKitAmount ?? 0,
                                subscriptionBooking: subscriptionBooking,
                                kitTitle: state.wardrobeKitTitle,
                                hasWardrobeKit: state.wardrobeItems.isNotEmpty,
                                isLoadingPayable:
                                    !subscriptionBooking &&
                                        (_isLoadingPayable ||
                                            (_payableSnapshot == null &&
                                                _payableError == null)),
                                payableError: _payableError,
                              ),
                              SizedBox(height: 16.h),
                              _buildTermsText(context),
                              SizedBox(height: 38.h),

                              Divider(height: 1,color: AppColours.primary,thickness: 0.2,),

                            ],
                          ),
                        ),
                      ),
                      _buildProceedButton(state.items.isNotEmpty, state, subscriptionBooking),
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

  Widget _buildAppBar() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColours.primary.withOpacity(0.15)),
        ),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () {
              if (_hasOpenedPayment &&
                  _activePendingOrderId != null &&
                  _activePendingOrderId!.isNotEmpty) {
                final pendingSnapshot =
                    _activePendingSnapshot ?? _payableSnapshot;
                if (pendingSnapshot != null) {
                  _showPendingOrderConfirmation(
                    orderId: _activePendingOrderId!,
                    snapshot: pendingSnapshot,
                  );
                  return;
                }
              }
              Navigator.pop(context);
            },
            child: Icon(Icons.arrow_back, color: AppColours.primary, size: 20),
          ),
          Expanded(
            child: Text(
              'Cart',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColours.primary,
                fontSize: 16.fSize,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          SizedBox(width: 20.w),

        ],
      ),
    );
  }

  Widget _buildSelectedGarments(CartState state) {
    final subscriptionItems = state.subscriptionGarmentItems;
    final paidRentalItems = state.paidRentalGarmentItems;
    final essentialItems = state.essentialsOnlyItems;
    final kidsItems = state.kidsItems;
    final hasWardrobe =
        subscriptionItems.isNotEmpty || paidRentalItems.isNotEmpty;
    final hasPurchase = essentialItems.isNotEmpty || kidsItems.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (subscriptionItems.isNotEmpty) ...[
          _buildWardrobeKitSection(
            state,
            subscriptionItems,
            sectionTitle: 'SUBSCRIPTION ITEMS',
            showPrice: false,
          ),
          SizedBox(height: 20.h),
        ],
        if (paidRentalItems.isNotEmpty) ...[
          if (subscriptionItems.isNotEmpty)
            Divider(
              height: 1,
              color: AppColours.primary,
              thickness: 0.2,
            ),
          if (subscriptionItems.isNotEmpty) SizedBox(height: 20.h),
          _buildWardrobeKitSection(
            state,
            paidRentalItems,
            sectionTitle: 'NON-SUBSCRIPTION ITEMS',
            showPrice: true,
          ),
          SizedBox(height: 20.h),
        ],
        if (essentialItems.isNotEmpty) ...[
          if (hasWardrobe)
            Divider(
              height: 1,
              color: AppColours.primary,
              thickness: 0.2,
            ),
          if (hasWardrobe) SizedBox(height: 20.h),
          _buildSectionHeader(
            'ESSENTIALS',
            '${essentialItems.fold<int>(0, (s, i) => s + i.quantity)} Item${essentialItems.length == 1 ? '' : 's'}',
            isNonReturnable: true,
          ),
          SizedBox(height: 10.h),
          ...essentialItems.map(
            (item) => _buildSelectedItemCard(
              item,
              state: state,
              showPrice: true,
            ),
          ),
        ],
        if (kidsItems.isNotEmpty) ...[
          if (hasWardrobe || essentialItems.isNotEmpty)
            Divider(
              height: 1,
              color: AppColours.primary,
              thickness: 0.2,
            ),
          if (hasWardrobe || essentialItems.isNotEmpty) SizedBox(height: 20.h),
          _buildSectionHeader(
            'KIDS',
            '${kidsItems.fold<int>(0, (s, i) => s + i.quantity)} Item${kidsItems.length == 1 ? '' : 's'}',
            isNonReturnable: true,
          ),
          SizedBox(height: 10.h),
          ...kidsItems.map(
            (item) => _buildSelectedItemCard(
              item,
              state: state,
              showPrice: true,
            ),
          ),
        ],
        if (hasPurchase) ...[
          SizedBox(height: 20.h),
          Divider(
            height: 1,
            color: AppColours.primary,
            thickness: 0.2,
          ),
        ],
      ],
    );
  }

  Widget _buildCheckoutGarmentList(
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
          '$garmentCount Item${garmentCount == 1 ? '' : 's'}',
        ),
        SizedBox(height: 10.h),
        ...items.map(
          (item) => _buildSelectedItemCard(
            item,
            state: state,
            showPrice: showPrice,
          ),
        ),
      ],
    );
  }

  Widget _buildWardrobeKitSection(
    CartState state,
    List<CartItem> wardrobeItems, {
    String sectionTitle = 'SUBSCRIPTION ITEMS',
    bool showPrice = false,
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
        ),
        if (_wardrobeGarmentsExpanded) ...[
          SizedBox(height: 24.h),
          _buildSectionHeader(
            'SELECTED GARMENTS',
            '$garmentCount Item${garmentCount == 1 ? '' : 's'}',
          ),
          SizedBox(height: 10.h),
          ...wardrobeItems.map(
            (item) => _buildSelectedItemCard(
              item,
              state: state,
              showPrice: showPrice || !item.isSubscriptionGarment,
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
  }) {
    return GestureDetector(
      onTap: () =>
          setState(() => _wardrobeGarmentsExpanded = !_wardrobeGarmentsExpanded),
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
              turns: _wardrobeGarmentsExpanded ? 0.5 : 0,
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
                    const SizedBox(width: 2),
                    Expanded(
                      child: cell(
                        images[1],
                        radius: const BorderRadius.only(topRight: Radius.circular(8)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 2),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: cell(
                        images[2],
                        radius:
                            const BorderRadius.only(bottomLeft: Radius.circular(8)),
                      ),
                    ),
                    const SizedBox(width: 2),
                    Expanded(
                      child: cell(
                        images[3],
                        radius:
                            const BorderRadius.only(bottomRight: Radius.circular(8)),
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


  Widget _buildSectionHeader(
    String title,
    String count, {
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
          count,
          style: TextStyle(color: Colors.white54, fontSize: 11.fSize),
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

  Widget _buildSelectedItemCard(
    CartItem item, {
    required CartState state,
    required bool showPrice,
  }) {
    return ReusableProductCartItem(
      item: item,
      state: state,
      showPrice: showPrice,
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
      padding: EdgeInsets.symmetric(horizontal: 8.w),
      decoration: BoxDecoration(
        color: AppColours.secondary,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColours.primary.withOpacity(0.4)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isDense: true,
          menuMaxHeight: 220.h,
          dropdownColor: AppColours.secondary,
          icon: Icon(Icons.arrow_drop_down, color: Colors.black, size: 18),
          style: TextStyle(color: Colors.white, fontSize: 11.fSize),
          onChanged: onChanged,
          items: items
              .map((s) => DropdownMenuItem<T>(
                    value: s,
                    child: Text(
                      '$prefix$s',
                      style: CustomTextStyles.montserratSemiBold
                          .copyWith(color: Colors.black, fontSize: 10),
                    ),
                  ))
              .toList(),
        ),
      ),
    );
  }

  Widget _buildDeliveryDetails() {
    final session = CheckoutSession.instance;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'DELIVERY DETAILS',
          style: CustomTextStyles.montserratBold.copyWith(fontSize: 12,color: AppColours.primary,letterSpacing: 2.4),
        ),
        SizedBox(height: 10.h),
        _infoRow(
          icon: Icons.location_on_outlined,
          label: 'DELIVERY ADDRESS',
          value: session.addressDisplay,
        ),
        SizedBox(height: 10.h),
        _infoRow(
          icon: Icons.calendar_today_outlined,
          label: 'DELIVERY DATE',
          value: session.deliveryDateDisplay,
        ),
      ],
    );
  }

  Widget _infoRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppColours.primary.withOpacity(0.9), size: 20),
        SizedBox(width: 8.w),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: CustomTextStyles.openSansSemiBold.copyWith(fontSize: 12,color: Color(0xffF5E6C899).withOpacity(0.4),letterSpacing: 1.2),
              ),
              SizedBox(height: 2.h),
              Text(
                value,
                style:CustomTextStyles.openSansRegular.copyWith(fontSize: 14),
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
        SizedBox(height: 8.h),
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
                hintStyle: CustomTextStyles.openSansRegular.copyWith(fontSize: 12,color: Color(0xFFF5E6C8).withOpacity(0.6)),
                border: InputBorder.none, // ❗ IMPORTANT
              ),
            ),
          ),
        )
      ],
    );
  }

  Widget _buildOrderSummary({
    required int subtotal,
    required int deliveryFee,
    required int discountAmount,
    required int gst,
    required int total,
    required int wardrobeKitAmount,
    required bool subscriptionBooking,
    required String kitTitle,
    required bool hasWardrobeKit,
    required bool isLoadingPayable,
    String? payableError,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ORDER SUMMARY',
          style: CustomTextStyles.montserratBold.copyWith(
            fontSize: 12,
            color: AppColours.primary,
            letterSpacing: 2.0,
          ),
        ),
        SizedBox(height: 24.h),
        if (subscriptionBooking) ...[
          _summaryRow(kitTitle, 'Included in membership'),
          SizedBox(height: 14.h),
          _summaryRow('Delivery Fee', 'Free'),
          SizedBox(height: 14.h),
          Divider(color: Colors.white.withOpacity(0.15), height: 1),
          SizedBox(height: 18.h),
          _summaryRow('Total Amount Payable', '₹0', highlight: true),
        ] else if (isLoadingPayable) ...[
          // CHANGE: No interim local amounts — show loading until backend total is ready.
          Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 24.h),
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColours.primary,
                ),
              ),
            ),
          ),
        ] else if (payableError != null) ...[
          _addressAlert(payableError),
        ] else ...[
          _summaryRow('Items Subtotal', CheckoutPricing.formatMoney(subtotal)),
          SizedBox(height: 14.h),
          _summaryRow(
            'Delivery Fee',
            deliveryFee > 0 ? CheckoutPricing.formatMoney(deliveryFee) : '₹0',
          ),
          if (discountAmount > 0) ...[
            SizedBox(height: 14.h),
            _summaryRow(
              'Discount',
              '-${CheckoutPricing.formatMoney(discountAmount)}',
              valueColor: const Color(0xFF4CAF50),
            ),
          ],
          SizedBox(height: 14.h),
          _summaryRow('Taxes (GST 18%)', CheckoutPricing.formatMoney(gst)),
          SizedBox(height: 16.h),
          Divider(color: Colors.white.withOpacity(0.15), height: 1),
          SizedBox(height: 18.h),
          _summaryRow(
            'Total Amount Payable',
            CheckoutPricing.formatMoney(total),
            highlight: true,
          ),
        ],
      ],
    );
  }

  Widget _summaryRow(
    String title,
    String value, {
    bool highlight = false,
    Color? valueColor,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          title,
          style: highlight
              ? CustomTextStyles.montserratBold.copyWith(
                  fontSize: 16.fSize,
                  color: AppColours.primary,
                )
              : CustomTextStyles.openSansRegular.copyWith(
                  fontSize: 14.fSize,
                  color: AppColours.secondary.withOpacity(0.85),
                ),
        ),
        Text(
          value,
          style: highlight
              ? CustomTextStyles.montserratBold.copyWith(
                  fontSize: 20.fSize,
                  color: AppColours.primary,
                )
              : CustomTextStyles.openSansSemiBold.copyWith(
                  fontSize: 14.fSize,
                  color: valueColor ?? AppColours.secondary,
                ),
        ),
      ],
    );
  }

  Widget _addressAlert(String message) {
    return Container(
      width: double.maxFinite,
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 8.h),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1C23),
        border: Border.all(color: const Color(0xFFE6C279).withOpacity(0.6)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: CustomTextStyles.openSansSemiBold.copyWith(
            fontSize: 12,
            color: AppColours.primary,
          ),
        ),
      ),
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

  Widget _buildProceedButton(
    bool canProceed,
    CartState state,
    bool subscriptionBooking,
  ) {
    final paymentReady =
        subscriptionBooking ||
            (_canProceedToPaymentFor(state) && canProceed);

    return Container(
      width: double.maxFinite,
      margin: EdgeInsets.fromLTRB(16.w, 0, 16.w, 14.h),
      height: 44.h,
      child: ElevatedButton(
        onPressed: paymentReady && !_isPlacingOrder
            ? () => _placeOrder(state)
            : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColours.primary,
          disabledBackgroundColor: Colors.white24,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          elevation: 0,
        ),
        child: _isPlacingOrder
            ? SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.black,
                ),
              )
            : Text(
                subscriptionBooking ? 'CONFIRM BOOKING' : 'PROCEED TO PAYMENT',
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 13.fSize,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
      ),
    );
  }
}
