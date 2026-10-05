/// Action button shown on the order card and the order details page.
enum OrderActionFlow { forward, reverse, completed, cancelled, delivered }

class OrderActionDecision {
  const OrderActionDecision({
    required this.label,
    required this.enabled,
    required this.flow,
  });

  final String label;
  final bool enabled;
  final OrderActionFlow flow;

  static const trackOrder = OrderActionDecision(
    label: 'Track Your Order',
    enabled: true,
    flow: OrderActionFlow.forward,
  );

  static const trackReturn = OrderActionDecision(
    label: 'Track Your Return Order',
    enabled: true,
    flow: OrderActionFlow.reverse,
  );

  static const completed = OrderActionDecision(
    label: 'Completed',
    enabled: false,
    flow: OrderActionFlow.completed,
  );

  static const returnOrder = OrderActionDecision(
    label: 'Return Order',
    enabled: true,
    flow: OrderActionFlow.delivered,
  );

  static const cancelled = OrderActionDecision(
    label: 'Order Cancelled',
    enabled: false,
    flow: OrderActionFlow.cancelled,
  );

  static const reattemptPickup = OrderActionDecision(
    label: 'Reattempt Pickup',
    enabled: true,
    flow: OrderActionFlow.reverse,
  );

  static const reschedulePending = OrderActionDecision(
    label: 'Pickup Reschedule In Progress',
    enabled: false,
    flow: OrderActionFlow.reverse,
  );

  static const reattemptDelivery = OrderActionDecision(
    label: 'Schedule Delivery Reattempt',
    enabled: true,
    flow: OrderActionFlow.forward,
  );
}

/// Picks the order action from the current status, not from older history rows.
class OrderActionResolver {
  OrderActionResolver._();

  static const _reverseActive = {
    'RETURN_REQUESTED',
    'RETURN_APPROVED',
    'PICKUP_SCHEDULED',
    'OUT_FOR_PICKUP',
    'ITEM_RECEIVED',
    'RETURN_IN_TRANSIT',
  };

  /// Delivery is still open, including a reattempt or a failed attempt.
  static const _forwardOpen = {
    'PENDING',
    'CONFIRMED',
    'PROCESSING',
    'DISPATCHED',
    'OUT_FOR_DELIVERY',
    'READY_FOR_DELIVERY',
    'REORDER_REQUESTED',
  };

  static const _returnSettled = {
    'RETURNED',
    'RETURNED_TO_IAP',
  };

  static OrderActionDecision resolve({
    String? orderStatus,
    String? returnStatus,
    bool isReturnWaitlisted = false,
    bool wasDelivered = false,
    bool hasReturnedAt = false,
    String? refundStatus,
    int? daysLeft,
    bool pendingReturn = false,
    bool returnFailed = false,
    String? returnResolutionStatus,
  }) {
    final status = orderStatus?.trim().toUpperCase() ?? '';
    final ret = returnStatus?.trim().toUpperCase() ?? '';
    final refund = refundStatus?.trim().toUpperCase() ?? '';
    final resStatus = returnResolutionStatus?.trim().toUpperCase() ?? '';

    if (status == 'CANCELLED') return OrderActionDecision.cancelled;

    final isDeliveryReattempt = status == 'NOT_DELIVERED' ||
        status == 'DELIVERY_FAILED' ||
        status == 'RETURNED_TO_IAP';
    if (isDeliveryReattempt) return OrderActionDecision.reattemptDelivery;

    if (resStatus == 'RETURN_REATTEMPT_PENDING') {
      return OrderActionDecision.reschedulePending;
    }

    final failedNow = returnFailed ||
        status == 'RETURN_FAILED' ||
        ret == 'RETURN_FAILED' ||
        status == 'RETURN_REJECTED' ||
        ret == 'RETURN_REJECTED';
    final settled =
        _returnSettled.contains(status) || _returnSettled.contains(ret);
    if (failedNow && !settled) return OrderActionDecision.reattemptPickup;

    final reverseActive = pendingReturn ||
        isReturnWaitlisted ||
        _reverseActive.contains(status) ||
        _reverseActive.contains(ret);
    final forwardOpen = _forwardOpen.contains(status) && !reverseActive;

    if (reverseActive) return OrderActionDecision.trackReturn;
    if (forwardOpen) return OrderActionDecision.trackOrder;

    final returnFinished = _returnSettled.contains(status) ||
        _returnSettled.contains(ret) ||
        hasReturnedAt ||
        refund == 'REFUNDED';
    if (wasDelivered && returnFinished) return OrderActionDecision.completed;

    final deliveredNow =
        status == 'DELIVERED' || status == 'COMPLETED' || wasDelivered;
    if (deliveredNow) {
      final inWindow = ret == 'ACTIVE' || (daysLeft != null && daysLeft > 0);
      if (inWindow) return OrderActionDecision.returnOrder;
      return OrderActionDecision.completed;
    }

    return OrderActionDecision.trackOrder;
  }
}
