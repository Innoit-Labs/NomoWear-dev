import 'package:nomowear/features/profile/domain/order_action.dart';

/// Single garment line inside a kit / multi-item order (order details).
class OrderLineItem {
  final String productId;
  final String productName;
  final String orderIdDisplay;
  final String sizeLabel;
  final String statusText;
  final bool isDelivered;
  final String imageAsset;
  final String? category;
  final String? itemType;
  final int quantity;
  final num unitPrice;
  final num lineTotal;

  const OrderLineItem({
    required this.productId,
    required this.productName,
    required this.orderIdDisplay,
    required this.sizeLabel,
    required this.statusText,
    required this.isDelivered,
    required this.imageAsset,
    this.category,
    this.itemType,
    this.quantity = 1,
    this.unitPrice = 0,
    this.lineTotal = 0,
  });
}

/// One order shown in My Orders and Order Details.
class UserOrder {
  final String id;
  final String title;
  /// Thumbnails: one asset for a simple row, or four for a 2×2 grid.
  final List<String> coverImageAssets;
  final String orderIdDisplay;
  final String attributeLabel;
  final String attributeValue;
  final String statusLabel;
  final String statusDate;
  final bool isDelivered;
  /// When true and [isDelivered], list/details show "Return This Order".
  final bool canReturn;
  /// Order is in return pickup / approval flow (not eligible for a new return).
  final bool isInReturnFlow;
  final List<OrderLineItem>? lineItems;
  final String addressLabel;
  final String addressLines;
  final String mobileDisplay;
  /// When [isDelivered] is true, order details summary uses Return if true, else Track.
  final bool deliveredSummaryShowsReturn;
  final bool isWardrobeKit;
  final int totalGarmentsCount;
  final String? deliveryDateFormatted;
  final DateTime? deliveryDate;
  final num totalAmount;
  final String? invoiceNumber;
  final String? orderType;
  final String? paymentStatus;
  final String? paymentMethod;
  final num subtotal;
  final num deliveryCharge;
  final num taxAmount;
  final num discountAmount;
  final num securityDepositAmount;
  final String? securityDepositRefundStatus;
  final num securityDepositRefundAmount;
  final String? transactionId;
  final DateTime? createdAt;
  final String? deliveryTime;
  final String? orderStatusRaw;
  final num kitPrice;
  final String? pickupDate;
  final String? pickupTime;
  final String? pickupNote;
  final String? pickupMobile;
  final String? pickupFullName;
  final String actionLabel;
  final bool actionEnabled;
  final OrderActionFlow actionFlow;
  final String? returnStatus;
  final int? daysLeft;
  final String? customerAddressId;

  const UserOrder({
    required this.id,
    required this.title,
    required this.coverImageAssets,
    required this.orderIdDisplay,
    required this.attributeLabel,
    required this.attributeValue,
    required this.statusLabel,
    required this.statusDate,
    required this.isDelivered,
    this.canReturn = false,
    this.isInReturnFlow = false,
    this.lineItems,
    required this.addressLabel,
    required this.addressLines,
    required this.mobileDisplay,
    this.deliveredSummaryShowsReturn = true,
    this.isWardrobeKit = false,
    this.totalGarmentsCount = 0,
    this.deliveryDateFormatted,
    this.deliveryDate,
    this.totalAmount = 0,
    this.invoiceNumber,
    this.orderType,
    this.paymentStatus,
    this.paymentMethod,
    this.subtotal = 0,
    this.deliveryCharge = 0,
    this.taxAmount = 0,
    this.discountAmount = 0,
    this.securityDepositAmount = 0,
    this.securityDepositRefundStatus,
    this.securityDepositRefundAmount = 0,
    this.transactionId,
    this.createdAt,
    this.deliveryTime,
    this.orderStatusRaw,
    this.kitPrice = 0,
    this.pickupDate,
    this.pickupTime,
    this.pickupNote,
    this.pickupMobile,
    this.pickupFullName,
    this.actionLabel = 'Track Your Order',
    this.actionEnabled = true,
    this.actionFlow = OrderActionFlow.forward,
    this.returnStatus,
    this.refundStatus,
    this.daysLeft,
    this.customerAddressId,
    this.hasReturnFailed = false,
    this.canReattemptReturn = false,
    this.rejectionReason,
    this.returnResolutionStatus,
    this.customerId,
    this.waitlistNumber,
    this.returnReattemptCount = 0,
  });

  final String? refundStatus;
  final bool hasReturnFailed;
  final bool canReattemptReturn;
  final String? rejectionReason;
  final String? returnResolutionStatus;
  final String? customerId;
  final String? waitlistNumber;
  final int returnReattemptCount;

  bool get isDeliveryReattemptEligible {
    final status = (orderStatusRaw ?? '').trim().toUpperCase();
    return status == 'NOT_DELIVERED' ||
        status == 'DELIVERY_FAILED' ||
        status == 'RETURNED_TO_IAP';
  }

  bool get isReturnFailed {
    final status = (orderStatusRaw ?? '').trim().toUpperCase();
    return status == 'RETURN_FAILED' ||
        status == 'RETURN_REJECTED' ||
        hasReturnFailed;
  }

  bool get isReturnEscalated {
    final status = (orderStatusRaw ?? '').trim().toUpperCase();
    return returnReattemptCount >= 2 || status == 'ESCALATION_ACTIVE';
  }

  bool get isRefundEligible {
    final isNonSub = orderType?.trim().toUpperCase() == 'NON_SUBSCRIPTION';
    if (!isNonSub) return false;
    final status = (orderStatusRaw ?? '').trim().toUpperCase();
    const disallowed = [
      'READY_FOR_DELIVERY',
      'DISPATCHED',
      'SHIPPED',
      'DELIVERED',
      'COMPLETED',
      'CANCELLED',
      'REFUNDED',
    ];
    if (disallowed.contains(status)) return false;
    if (refundStatus?.trim().toUpperCase() == 'REFUNDED') return false;
    return true;
  }

  bool get isReturnReattemptPending =>
      returnResolutionStatus?.trim().toUpperCase() == 'RETURN_REATTEMPT_PENDING';

  bool get hasLineItems => lineItems != null && lineItems!.isNotEmpty;

  bool get useCoverGrid => coverImageAssets.length >= 4;

  /// Order details: “Return This Order” — show review stars + expand when [hasLineItems].
  bool get isReturnOrderDetails => isDelivered && deliveredSummaryShowsReturn;

  /// Order details: tracking (no stars). Opposite of [isReturnOrderDetails] for rating UI.
  bool get isTrackOrderDetails => !isReturnOrderDetails;

  UserOrder copyWith({
    String? id,
    String? title,
    List<String>? coverImageAssets,
    String? orderIdDisplay,
    String? attributeLabel,
    String? attributeValue,
    String? statusLabel,
    String? statusDate,
    bool? isDelivered,
    bool? canReturn,
    bool? isInReturnFlow,
    List<OrderLineItem>? lineItems,
    String? addressLabel,
    String? addressLines,
    String? mobileDisplay,
    bool? deliveredSummaryShowsReturn,
    bool? isWardrobeKit,
    int? totalGarmentsCount,
    String? deliveryDateFormatted,
    num? totalAmount,
    bool? hasReturnFailed,
    bool? canReattemptReturn,
    String? rejectionReason,
    String? actionLabel,
    bool? actionEnabled,
    OrderActionFlow? actionFlow,
    String? returnStatus,
    String? refundStatus,
    int? daysLeft,
    String? customerAddressId,
    String? returnResolutionStatus,
    String? customerId,
    String? waitlistNumber,
    int? returnReattemptCount,
  }) {
    return UserOrder(
      id: id ?? this.id,
      title: title ?? this.title,
      coverImageAssets: coverImageAssets ?? this.coverImageAssets,
      orderIdDisplay: orderIdDisplay ?? this.orderIdDisplay,
      attributeLabel: attributeLabel ?? this.attributeLabel,
      attributeValue: attributeValue ?? this.attributeValue,
      statusLabel: statusLabel ?? this.statusLabel,
      statusDate: statusDate ?? this.statusDate,
      isDelivered: isDelivered ?? this.isDelivered,
      canReturn: canReturn ?? this.canReturn,
      isInReturnFlow: isInReturnFlow ?? this.isInReturnFlow,
      lineItems: lineItems ?? this.lineItems,
      addressLabel: addressLabel ?? this.addressLabel,
      addressLines: addressLines ?? this.addressLines,
      mobileDisplay: mobileDisplay ?? this.mobileDisplay,
      deliveredSummaryShowsReturn:
          deliveredSummaryShowsReturn ?? this.deliveredSummaryShowsReturn,
      isWardrobeKit: isWardrobeKit ?? this.isWardrobeKit,
      totalGarmentsCount: totalGarmentsCount ?? this.totalGarmentsCount,
      deliveryDateFormatted: deliveryDateFormatted ?? this.deliveryDateFormatted,
      totalAmount: totalAmount ?? this.totalAmount,
      hasReturnFailed: hasReturnFailed ?? this.hasReturnFailed,
      canReattemptReturn: canReattemptReturn ?? this.canReattemptReturn,
      rejectionReason: rejectionReason ?? this.rejectionReason,
      returnResolutionStatus:
          returnResolutionStatus ?? this.returnResolutionStatus,
      customerId: customerId ?? this.customerId,
      waitlistNumber: waitlistNumber ?? this.waitlistNumber,
      returnReattemptCount: returnReattemptCount ?? this.returnReattemptCount,
      actionLabel: actionLabel ?? this.actionLabel,
      actionEnabled: actionEnabled ?? this.actionEnabled,
      actionFlow: actionFlow ?? this.actionFlow,
      returnStatus: returnStatus ?? this.returnStatus,
      refundStatus: refundStatus ?? this.refundStatus,
      daysLeft: daysLeft ?? this.daysLeft,
      customerAddressId: customerAddressId ?? this.customerAddressId,
      pickupDate: pickupDate,
      pickupTime: pickupTime,
      pickupNote: pickupNote,
      pickupMobile: pickupMobile,
      pickupFullName: pickupFullName,
    );
  }
}

/// In-memory list populated from GET /mobile/v1/orders.
final List<UserOrder> userOrdersList = <UserOrder>[];

UserOrder? findUserOrderById(String id) {
  for (final o in userOrdersList) {
    if (o.id == id) return o;
  }
  return null;
}

void replaceUserOrders(List<UserOrder> orders) {
  userOrdersList
    ..clear()
    ..addAll(orders);
}

void appendUserOrder(UserOrder order) {
  userOrdersList.insert(0, order);
}

void upsertUserOrder(UserOrder order) {
  final index = userOrdersList.indexWhere((o) => o.id == order.id);
  if (index >= 0) {
    userOrdersList[index] = order;
  } else {
    userOrdersList.insert(0, order);
  }
}

/// Marks a locally submitted / waitlisted return on the in-memory order list.
void markUserOrderReturnSubmitted(String orderId) {
  final id = orderId.trim();
  if (id.isEmpty) return;
  final index = userOrdersList.indexWhere((o) => o.id == id);
  if (index < 0) return;
  final current = userOrdersList[index];
  userOrdersList[index] = current.copyWith(
    canReturn: false,
    isInReturnFlow: true,
    deliveredSummaryShowsReturn: false,
    statusLabel: 'Return status',
    statusDate: 'Pending approval',
    actionLabel: OrderActionDecision.trackReturn.label,
    actionEnabled: true,
    actionFlow: OrderActionFlow.reverse,
  );
}
