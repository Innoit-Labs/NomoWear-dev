import 'package:nomowear/features/cart/data/models/remote_cart.dart';
import 'package:nomowear/features/cart/presentation/bloc/cart_bloc.dart';
import 'package:nomowear/features/orders/data/models/initiate_order_result.dart';

/// Shared order totals for checkout and payment screens.
class OrderSummary {
  const OrderSummary({
    required this.subtotal,
    required this.deliveryFee,
    required this.discountAmount,
    required this.gst,
    required this.total,
    required this.wardrobeKitAmount,
    required this.essentialsAmount,
    this.securityDepositAmount = 0,
  });

  final int subtotal;
  final int deliveryFee;
  final int discountAmount;
  final int gst;
  final int total;
  final int wardrobeKitAmount;
  final int essentialsAmount;
  final int securityDepositAmount;
}

/// Backend-only payable snapshot: cart breakdown + order-initiate amount (Razorpay).
///
/// CHANGE: Single source of truth for checkout — [initiate.amount] is what the
/// gateway charges; [displayTotalRupees] is derived from that same value.
class CheckoutPayableSnapshot {
  const CheckoutPayableSnapshot({
    required this.remoteCart,
    required this.initiate,
    required this.summary,
    required this.gatewayAmountPaise,
    required this.displayTotalRupees,
  });

  final RemoteCart remoteCart;
  final InitiateOrderResult initiate;
  final OrderSummary summary;

  /// Paise amount passed to Razorpay.
  final int gatewayAmountPaise;

  /// Rupee total shown in Payment Summary (converted from gateway amount).
  final int displayTotalRupees;
}

/// Prefetched checkout payload prepared before navigating to checkout screen.
class CheckoutPrefetchPayload {
  const CheckoutPrefetchPayload({
    required this.snapshot,
    required this.cartFingerprint,
  });

  final CheckoutPayableSnapshot snapshot;
  final String cartFingerprint;
}

class CheckoutPricing {
  CheckoutPricing._();

  static int wardrobeKitPriceFromState(CartState state) {
    final raw = state.wardrobeKitPrice;
    if (raw != null && raw.trim().isNotEmpty) {
      final digits = raw.replaceAll(RegExp(r'[^0-9.]'), '');
      if (digits.isNotEmpty) {
        final parsed = num.tryParse(digits);
        if (parsed != null) {
          final amount = parsed.round();
          if (amount > 0) return amount;
        }
      }
    }
    return 0;
  }

  static int parseItemPrice(String? rawPrice, {required bool isEssential}) {
    if (rawPrice == null || rawPrice.trim().isEmpty) {
      return 0;
    }
    final cleaned = rawPrice.trim();
    // Prefer decimal parse so "1999.0" / "₹ 1,999.50" stay accurate.
    final normalized = cleaned.replaceAll(',', '');
    final asNum = num.tryParse(normalized.replaceAll(RegExp(r'[^\d.]'), ''));
    if (asNum != null) return asNum.round();
    final digits = cleaned.replaceAll(RegExp(r'[^0-9]'), '');
    return int.tryParse(digits) ?? 0;
  }

  /// Converts order-initiate / Razorpay amount (paise) to rupees for UI display.
  static int rupeesFromGatewayAmount(int gatewayAmountPaise) {
    if (gatewayAmountPaise <= 0) return 0;
    return (gatewayAmountPaise / 100).round();
  }

  /// Builds checkout summary using backend cart lines and initiate-order total.
  ///
  /// Grand total always comes from [payableTotalRupees] (initiate-order amount),
  /// not from local math, so UI and Razorpay stay aligned.
  static CheckoutPayableSnapshot payableSnapshot({
    required RemoteCart remoteCart,
    required InitiateOrderResult initiate,
    required CartState cartState,
    bool wardrobeCoveredBySubscription = false,
  }) {
    final wardrobeKitAmount = wardrobeCoveredBySubscription
        ? 0
        : wardrobeKitAmountFromRemote(
            remoteCart,
            cartState.wardrobeKitProductId ?? cartState.wardrobeKitId,
          );

    final remoteSubtotal = remoteCart.subtotal.round();
    final remoteDelivery = remoteCart.deliveryCharge.round();
    final remoteDiscount = remoteCart.discountAmount.round();
    final remoteGst = remoteCart.taxAmount.round();
    final remoteTotal = remoteCart.totalAmount.round();

    final effectiveSubtotal = remoteSubtotal > 0
        ? remoteSubtotal
        : (initiate.displayRupees > 0 ? initiate.displayRupees : 0);
    final effectiveDelivery = remoteDelivery;
    final effectiveDiscount = remoteDiscount;
    final effectiveGst = remoteGst;

    // API total_amount is strictly the source of truth for total payable
    final effectiveTotal = remoteTotal > 0
        ? remoteTotal
        : (initiate.displayRupees > 0
            ? initiate.displayRupees
            : (effectiveSubtotal + effectiveDelivery + effectiveGst - effectiveDiscount));

    final depositFromCart = remoteCart.securityDepositAmount.round();
    final baseWithoutDeposit =
        effectiveSubtotal + effectiveDelivery + effectiveGst - effectiveDiscount;
    final computedDeposit = effectiveTotal > baseWithoutDeposit
        ? (effectiveTotal - baseWithoutDeposit)
        : 0;
    final effectiveDeposit =
        depositFromCart > 0 ? depositFromCart : computedDeposit;

    final summary = OrderSummary(
      subtotal: effectiveSubtotal,
      deliveryFee: effectiveDelivery,
      discountAmount: effectiveDiscount,
      gst: effectiveGst,
      total: effectiveTotal,
      wardrobeKitAmount: wardrobeKitAmount,
      essentialsAmount: 0,
      securityDepositAmount: effectiveDeposit,
    );

    final gatewayPaise = initiate.amount > 0
        ? initiate.amount
        : (effectiveTotal * 100);

    return CheckoutPayableSnapshot(
      remoteCart: remoteCart,
      initiate: initiate,
      summary: summary,
      gatewayAmountPaise: gatewayPaise,
      displayTotalRupees: effectiveTotal,
    );
  }

  /// Wardrobe kit line total from synced backend cart (no local price table).
  static int wardrobeKitAmountFromRemote(
    RemoteCart cart,
    String? kitProductId,
  ) {
    final id = kitProductId?.trim();
    if (id == null || id.isEmpty) return 0;

    for (final item in cart.items) {
      if (item.productId == id) {
        final line = item.lineTotal.round();
        if (line > 0) return line;
        return (item.unitPrice * item.quantity).round();
      }
    }
    return 0;
  }

  /// Fingerprint of cart contents — reload payable snapshot when this changes.
  static String cartFingerprint(CartState state) {
    final parts = <String>[
      state.wardrobeKitId ?? '',
      state.wardrobeKitProductId ?? '',
      '${state.wardrobeKitDays}',
    ];
    for (final item in state.items) {
      parts.add('${item.id}|${item.quantity}|${item.selectedSize}');
    }
    return parts.join(';');
  }

  static String formatMoney(num value) {
    final intVal = value.round();
    final isNegative = intVal < 0;
    final absVal = intVal.abs().toString();
    if (absVal.length <= 3) {
      return '${isNegative ? "-₹" : "₹"}$absVal';
    }
    final lastThree = absVal.substring(absVal.length - 3);
    final otherNumbers = absVal.substring(0, absVal.length - 3);
    final formattedOther = otherNumbers.replaceAllMapped(
      RegExp(r'(\d)(?=(\d{2})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
    return '${isNegative ? "-₹" : "₹"}$formattedOther,$lastThree';
  }
}

class _NormalizedPayable {
  const _NormalizedPayable({
    required this.gatewayAmountPaise,
    required this.displayRupees,
  });

  final int gatewayAmountPaise;
  final int displayRupees;
}
