import 'dart:convert';

class OrderPickupDetails {
  const OrderPickupDetails({
    this.addressId,
    this.pickupDate,
    this.pickupTime,
    this.note,
    this.fullName,
    this.mobile,
  });

  final String? addressId;
  final String? pickupDate;
  final String? pickupTime;
  final String? note;
  final String? fullName;
  final String? mobile;

  factory OrderPickupDetails.fromJson(Map<String, dynamic> json) {
    return OrderPickupDetails(
      addressId: json['addressId']?.toString() ??
          json['address_id']?.toString(),
      pickupDate: json['pickup_date']?.toString() ??
          json['pickupDate']?.toString(),
      pickupTime: json['pickup_time']?.toString() ??
          json['pickupTime']?.toString(),
      note: json['note']?.toString(),
      fullName: json['fullName']?.toString() ?? json['full_name']?.toString(),
      mobile: json['mobile']?.toString() ?? json['phone']?.toString(),
    );
  }
}

class OrderHistoryItem {
  const OrderHistoryItem({
    required this.id,
    required this.orderNumber,
    this.invoiceNumber,
    this.orderType,
    this.totalAmount = 0,
    this.paymentStatus,
    this.paymentMethod,
    this.orderStatus,
    this.createdAt,
    this.deliveryDate,
    this.deliveryTime,
    this.actualDeliveredAt,
    this.returnedAt,
    this.kitDurationDays,
    this.daysLeft,
    this.returnStatus,
    this.rentalEndDate,
    this.orderItems = const [],
    this.customerAddressId,
    this.statusHistory = const [],
    this.orderStatusConfig = const [],
    this.deliveryPartnerName,
    this.deliveryPartnerPhone,
    this.returnDeliveryPartnerName,
    this.returnDeliveryPartnerPhone,
    this.pickupDetails,
    this.subtotal = 0,
    this.deliveryCharge = 0,
    this.taxAmount = 0,
    this.discountAmount = 0,
    this.securityDepositAmount = 0,
    this.securityDepositRefundStatus,
    this.securityDepositRefundAmount = 0,
    this.razorpayPaymentId,
    this.razorpayOrderId,
    this.deliveryAddress,
    this.deliveryAddressSnapshot,
    this.deliveryAddressJson,
    this.customerAddress,
    this.canReattemptReturn = false,
    this.rejectionReason,
    this.isReturnWaitlisted = false,
    this.refundStatus,
  });

  final String id;
  final String orderNumber;
  final String? invoiceNumber;
  final String? orderType;
  final num totalAmount;
  final String? paymentStatus;
  final String? paymentMethod;
  final String? orderStatus;
  final DateTime? createdAt;
  final String? deliveryDate;
  final String? deliveryTime;
  final DateTime? actualDeliveredAt;
  final DateTime? returnedAt;
  final int? kitDurationDays;
  final int? daysLeft;
  final String? returnStatus;
  final DateTime? rentalEndDate;
  final List<OrderHistoryLineItem> orderItems;
  final String? customerAddressId;
  final List<OrderStatusHistoryEntry> statusHistory;
  final List<OrderStatusConfigItem> orderStatusConfig;
  final String? deliveryPartnerName;
  final String? deliveryPartnerPhone;
  final String? returnDeliveryPartnerName;
  final String? returnDeliveryPartnerPhone;
  final OrderPickupDetails? pickupDetails;
  final num subtotal;
  final num deliveryCharge;
  final num taxAmount;
  final num discountAmount;
  final num securityDepositAmount;
  final String? securityDepositRefundStatus;
  final num securityDepositRefundAmount;
  final String? razorpayPaymentId;
  final String? razorpayOrderId;
  final String? deliveryAddress;
  final String? deliveryAddressSnapshot;
  final String? deliveryAddressJson;
  final String? customerAddress;
  final bool canReattemptReturn;
  final String? rejectionReason;
  final bool isReturnWaitlisted;
  final String? refundStatus;

  static const _returnFlowStatuses = {
    'RETURN_REQUESTED',
    'RETURN_APPROVED',
    'RETURNED',
    'APPROVED',
    'RETURN_PENDING',
    'PICKUP_SCHEDULED',
  };

  /// `returnStatus` values that mean a return is actually in progress.
  /// `ACTIVE` = eligible to return; `NOT_DELIVERED` = order not delivered yet.
  static const _returnFlowReturnStatuses = {
    'RETURN_REQUESTED',
    'RETURN_PENDING',
    'PICKUP_SCHEDULED',
    'RETURN_APPROVED',
    'APPROVED',
    'RETURNED',
    'WAITLISTED',
  };

  String get normalizedOrderStatus {
    final status = orderStatus?.trim().toUpperCase() ?? '';
    if (status == 'RETURN_APPROVED') return 'APPROVED';
    return status;
  }

  bool get isDelivered {
    final status = orderStatus?.trim().toUpperCase() ?? '';
    if (status == 'DELIVERED' || status == 'COMPLETED') return true;
    if (_returnFlowStatuses.contains(status)) return true;
    if (actualDeliveredAt != null) return true;
    return statusHistory.any(
      (entry) => entry.status.trim().toUpperCase() == 'DELIVERED',
    );
  }

  /// A later successful drop-off overrides an earlier failed pickup.
  bool get isReturnSettled {
    final status = orderStatus?.trim().toUpperCase() ?? '';
    final rs = returnStatus?.trim().toUpperCase() ?? '';
    const settled = {'RETURNED', 'RETURNED_TO_IAP'};
    return settled.contains(status) || settled.contains(rs);
  }

  bool get hasReturnFailed {
    if (isReturnSettled) return false;
    final status = orderStatus?.trim().toUpperCase() ?? '';
    final rs = returnStatus?.trim().toUpperCase() ?? '';
    if (status == 'RETURN_FAILED' || rs == 'RETURN_FAILED') return true;
    if (statusHistory.isEmpty) return false;
    return statusHistory.last.status.trim().toUpperCase() == 'RETURN_FAILED';
  }

  bool get isInReturnFlow {
    if (canReattemptReturn || hasReturnFailed) return false;
    final status = orderStatus?.trim().toUpperCase() ?? '';
    if (_returnFlowStatuses.contains(status)) return true;
    final rs = returnStatus?.trim().toUpperCase();
    if (rs == null || rs.isEmpty) return false;
    return _returnFlowReturnStatuses.contains(rs);
  }

  /// True once Super Admin has approved the return (or return is underway).
  /// Waitlisted / pending requests should NOT show return timeline steps yet.
  bool get shouldShowReturnTimeline {
    if (canReattemptReturn || hasReturnFailed) return false;
    if (!isDelivered && !_returnFlowStatuses.contains(
          orderStatus?.trim().toUpperCase() ?? '',
        )) {
      return false;
    }
    if (isReturnComplete) return true;
    final status = orderStatus?.trim().toUpperCase() ?? '';
    if (_returnFlowStatuses.contains(status)) return true;
    final rs = returnStatus?.trim().toUpperCase() ?? '';
    if (rs.isEmpty ||
        rs == 'ACTIVE' ||
        rs == 'NOT_DELIVERED' ||
        rs == 'WAITLISTED') {
      return false;
    }
    return _returnFlowReturnStatuses.contains(rs);
  }

  /// Effective status for tracking UI (prefers return status once approved).
  String get trackingCurrentStatus {
    if (hasReturnFailed) return 'RETURN_FAILED';
    final order = normalizedOrderStatus;
    if (_returnFlowStatuses.contains(order)) return order;
    final rs = returnStatus?.trim().toUpperCase() ?? '';
    if (shouldShowReturnTimeline &&
        rs.isNotEmpty &&
        rs != 'ACTIVE' &&
        rs != 'NOT_DELIVERED' &&
        rs != 'WAITLISTED') {
      if (rs == 'RETURN_APPROVED') return 'APPROVED';
      return rs;
    }
    return order;
  }

  bool get isReturnComplete {
    if (hasReturnFailed) return false;
    if (returnedAt != null) return true;
    final status = orderStatus?.trim().toUpperCase() ?? '';
    if (status == 'RETURNED' ||
        status == 'RETURN_APPROVED' ||
        status == 'APPROVED') {
      return true;
    }
    final rs = returnStatus?.trim().toUpperCase() ?? '';
    return rs == 'RETURN_APPROVED' || rs == 'RETURNED' || rs == 'APPROVED';
  }

  bool get isSubscription =>
      orderType?.trim().toUpperCase() == 'SUBSCRIPTION';

  bool get canReturn {
    if (returnedAt != null || isReturnComplete) return false;
    if (canReattemptReturn || hasReturnFailed) return true;
    if (!isDelivered) return false;
    final rs = returnStatus?.trim().toUpperCase();
    if (rs == null || rs.isEmpty) return true;
    return rs == 'ACTIVE';
  }

  Map<String, DateTime?> get trackingTimestampsByStatus {
    final map = <String, DateTime?>{
      for (final entry in statusHistory)
        entry.status.trim().toUpperCase(): entry.timestamp,
    };

    if (actualDeliveredAt != null) {
      map.putIfAbsent('DELIVERED', () => actualDeliveredAt);
    }

    if (returnedAt != null) {
      map['RETURNED'] = returnedAt;
      map['APPROVED'] = returnedAt;
      map['RETURN_APPROVED'] = returnedAt;
    }

    return map;
  }

  String? get resolvedDeliveryDate {
    final top = deliveryDate?.trim();
    if (top != null && top.isNotEmpty) return top;
    for (final item in orderItems) {
      final fromKit = item.kitDetails?.deliveryDate?.trim();
      if (fromKit != null && fromKit.isNotEmpty) return fromKit;
    }
    return null;
  }

  String? get resolvedDeliveryTime {
    final top = deliveryTime?.trim();
    if (top != null && top.isNotEmpty) return top;
    for (final item in orderItems) {
      final fromKit = item.kitDetails?.deliveryTime?.trim();
      if (fromKit != null && fromKit.isNotEmpty) return fromKit;
    }
    return null;
  }

  int? get resolvedKitDurationDays {
    if (kitDurationDays != null && kitDurationDays! > 0) return kitDurationDays;
    for (final item in orderItems) {
      final days = item.kitDetails?.durationDays;
      if (days != null && days > 0) return days;
    }
    return null;
  }

  String? get resolvedCustomerAddressId {
    final top = customerAddressId?.trim();
    if (top != null && top.isNotEmpty) return top;
    for (final item in orderItems) {
      final fromKit = item.kitDetails?.customerAddressId?.trim();
      if (fromKit != null && fromKit.isNotEmpty) return fromKit;
    }
    return null;
  }

  factory OrderHistoryItem.fromJson(Map<String, dynamic> json) {
    return OrderHistoryItem(
      id: json['id']?.toString() ?? '',
      orderNumber: json['orderNumber']?.toString() ??
          json['order_number']?.toString() ??
          '',
      invoiceNumber: json['invoice_number']?.toString() ??
          json['invoiceNumber']?.toString(),
      orderType: json['order_type']?.toString() ?? json['orderType']?.toString(),
      totalAmount: _num(json['total_amount'] ?? json['totalAmount']),
      paymentStatus: json['payment_status']?.toString() ??
          json['paymentStatus']?.toString(),
      paymentMethod: json['payment_method']?.toString() ??
          json['paymentMethod']?.toString(),
      orderStatus: json['orderStatus']?.toString() ??
          json['order_status']?.toString(),
      createdAt: _dateTime(json['created_at'] ?? json['createdAt']),
      deliveryDate: json['delivery_date']?.toString() ??
          json['deliveryDate']?.toString(),
      deliveryTime: json['delivery_time']?.toString() ??
          json['deliveryTime']?.toString(),
      actualDeliveredAt: _dateTime(
        json['actual_delivered_at'] ?? json['actualDeliveredAt'],
      ),
      returnedAt: _dateTime(json['returned_at'] ?? json['returnedAt']),
      kitDurationDays: _int(json['kit_duration_days'] ?? json['kitDurationDays']),
      daysLeft: _int(json['daysLeft'] ?? json['days_left']),
      returnStatus: json['returnStatus']?.toString() ??
          json['return_status']?.toString(),
      rentalEndDate: _dateTime(json['rentalEndDate'] ?? json['rental_end_date']),
      orderItems: _parseItems(json['orderItems'] ?? json['order_items']),
      customerAddressId: json['customer_address_id']?.toString() ??
          json['customerAddressId']?.toString(),
      statusHistory: _parseStatusHistory(
        json['statusHistory'] ?? json['status_history'],
      ),
      orderStatusConfig: _parseStatusConfig(
        json['orderStatusConfig'] ?? json['order_status_config'],
      ),
      deliveryPartnerName: json['delivery_partner_name']?.toString() ??
          json['deliveryPartnerName']?.toString(),
      deliveryPartnerPhone: json['delivery_partner_phone']?.toString() ??
          json['deliveryPartnerPhone']?.toString(),
      returnDeliveryPartnerName:
          json['return_delivery_partner_name']?.toString(),
      returnDeliveryPartnerPhone:
          json['return_delivery_partner_phone']?.toString(),
      pickupDetails: _parsePickupDetails(
        json['pickup_details'] ?? json['pickupDetails'],
      ),
      subtotal: _num(json['subtotal']),
      deliveryCharge: _num(json['delivery_charge'] ?? json['deliveryCharge']),
      taxAmount: _num(json['tax_amount'] ?? json['taxAmount']),
      discountAmount: _num(json['discount_amount'] ?? json['discountAmount']),
      securityDepositAmount: _num(
        json['security_deposit_amount'] ?? json['securityDepositAmount'],
      ),
      securityDepositRefundStatus:
          json['security_deposit_refund_status']?.toString() ??
          json['securityDepositRefundStatus']?.toString(),
      securityDepositRefundAmount: _num(
        json['security_deposit_refund_amount'] ??
        json['securityDepositRefundAmount'],
      ),
      razorpayPaymentId: json['razorpay_payment_id']?.toString() ??
          json['razorpayPaymentId']?.toString(),
      razorpayOrderId: json['razorpay_order_id']?.toString() ??
          json['razorpayOrderId']?.toString(),
      deliveryAddress: json['delivery_address']?.toString() ??
          json['address']?.toString(),
      deliveryAddressSnapshot: json['delivery_address_snapshot']?.toString(),
      deliveryAddressJson: json['delivery_address_json']?.toString(),
      customerAddress: json['customer_address']?.toString(),
      canReattemptReturn: json['can_reattempt_return'] == true ||
          json['canReattemptReturn'] == true ||
          json['can_reattempt_return']?.toString() == '1',
      rejectionReason: json['rejection_reason']?.toString() ??
          json['rejectionReason']?.toString(),
      isReturnWaitlisted: _bool(
        json['is_return_waitlisted'] ?? json['isReturnWaitlisted'],
      ),
      refundStatus: json['refund_status']?.toString() ??
          json['refundStatus']?.toString(),
    );
  }

  static OrderPickupDetails? _parsePickupDetails(dynamic raw) {
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        raw = jsonDecode(raw);
      } catch (_) {
        return null;
      }
    }
    if (raw is! Map) return null;
    return OrderPickupDetails.fromJson(Map<String, dynamic>.from(raw));
  }

  static List<OrderHistoryLineItem> _parseItems(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => OrderHistoryLineItem.fromJson(
              Map<String, dynamic>.from(item),
            ))
        .toList();
  }

  static List<OrderStatusHistoryEntry> _parseStatusHistory(dynamic raw) {
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((item) => OrderStatusHistoryEntry.fromJson(
                Map<String, dynamic>.from(item),
              ))
          .toList();
    }

    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          return decoded
              .whereType<Map>()
              .map((item) => OrderStatusHistoryEntry.fromJson(
                    Map<String, dynamic>.from(item),
                  ))
              .toList();
        }
      } catch (_) {
        return const [];
      }
    }

    return const [];
  }

  static List<OrderStatusConfigItem> _parseStatusConfig(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => OrderStatusConfigItem.fromJson(
              Map<String, dynamic>.from(item),
            ))
        .where((item) => item.enabled)
        .toList();
  }

  static num _num(dynamic value) {
    if (value is num) return value;
    return num.tryParse(value?.toString() ?? '') ?? 0;
  }

  static int? _int(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '');
  }

  static bool _bool(dynamic value) {
    if (value == true || value == 1) return true;
    final text = value?.toString().trim().toLowerCase();
    return text == 'true' || text == '1';
  }

  static DateTime? _dateTime(dynamic value) {
    final raw = value?.toString().trim();
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }
}

class OrderHistoryLineItem {
  const OrderHistoryLineItem({
    this.productId,
    this.productName,
    this.size,
    this.quantity = 1,
    this.unitPrice = 0,
    this.lineTotal = 0,
    this.imageUrl,
    this.productClass,
    this.kitDetails,
    this.itemType,
    this.cartSection,
  });

  final String? productId;
  final String? productName;
  final String? size;
  final int quantity;
  final num unitPrice;
  final num lineTotal;
  final String? imageUrl;
  final String? productClass;
  final OrderLineKitDetails? kitDetails;
  final String? itemType;
  final String? cartSection;

  factory OrderHistoryLineItem.fromJson(Map<String, dynamic> json) {
    final kitRaw = json['kitDetails'] ?? json['kit_details'];
    final variantRaw = json['variant'];
    final variant = _asMap(variantRaw);
    final options = _asMap(json['options']) ??
        _asMap(variant?['options']) ??
        _asMap(variant?['option']);
    final variantName = _stringFromCandidates(
      json,
      const ['variant_name', 'variantName'],
    ) ??
        _stringFromCandidates(
          variant,
          const ['variant_name', 'variantName', 'name'],
        );
    return OrderHistoryLineItem(
      productId: json['productId']?.toString() ?? json['product_id']?.toString(),
      productName: json['product_name']?.toString() ??
          json['productName']?.toString() ??
          json['name']?.toString(),
      size: json['size']?.toString() ??
          json['sizeLabel']?.toString() ??
          json['size_label']?.toString() ??
          json['selected_size']?.toString() ??
          json['selectedSize']?.toString() ??
          json['variant_size']?.toString() ??
          json['variantSize']?.toString() ??
          _optionValue(options, const ['Size', 'size']) ??
          _sizeFromVariantName(variantName) ??
          variantName ??
          json['option_value']?.toString() ??
          json['optionValue']?.toString(),
      quantity: OrderHistoryItem._int(json['quantity']) ?? 1,
      unitPrice: OrderHistoryItem._num(json['unitPrice'] ?? json['unit_price']),
      lineTotal: OrderHistoryItem._num(json['lineTotal'] ?? json['line_total']),
      imageUrl: json['image_url']?.toString() ??
          json['imageUrl']?.toString() ??
          json['primary_image_url']?.toString() ??
          json['primaryImageUrl']?.toString() ??
          _stringFromCandidates(
            variant,
            const [
              'primary_image_url',
              'primaryImageUrl',
              'image_url',
              'imageUrl',
              'product_image',
            ],
          ) ??
          json['product_image']?.toString(),
      productClass: json['product_class']?.toString() ??
          json['productClass']?.toString(),
      kitDetails: kitRaw is Map
          ? OrderLineKitDetails.fromJson(Map<String, dynamic>.from(kitRaw))
          : null,
      itemType: json['item_type']?.toString() ??
          json['itemType']?.toString(),
      cartSection: json['cart_section']?.toString() ??
          json['cartSection']?.toString(),
    );
  }

  static String? _optionValue(
    Map<String, dynamic>? options,
    List<String> keys,
  ) {
    if (options == null || options.isEmpty) return null;
    for (final key in keys) {
      final value = options[key]?.toString().trim();
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
    final lowered = <String, dynamic>{};
    options.forEach((key, value) {
      lowered[key.toLowerCase()] = value;
    });
    for (final key in keys) {
      final value = lowered[key.toLowerCase()]?.toString().trim();
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
    return null;
  }

  static String? _sizeFromVariantName(String? variantName) {
    final value = variantName?.trim();
    if (value == null || value.isEmpty) return null;
    final sizeMatch = RegExp(r'(?i)size\s*:\s*([^/|,]+)').firstMatch(value);
    if (sizeMatch == null) return null;
    final parsed = sizeMatch.group(1)?.trim();
    if (parsed == null || parsed.isEmpty) return null;
    return parsed;
  }

  static Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is String && value.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map<String, dynamic>) return decoded;
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  static String? _stringFromCandidates(
    Map<String, dynamic>? source,
    List<String> keys,
  ) {
    if (source == null || source.isEmpty) return null;
    for (final key in keys) {
      final value = source[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }
}

class OrderLineKitDetails {
  const OrderLineKitDetails({
    this.gender,
    this.bodyType,
    this.kitType,
    this.deliveryDate,
    this.deliveryTime,
    this.customerAddressId,
    this.durationDays,
    this.height,
    this.weight,
    this.price = 0,
    this.selectedItems = const [],
  });

  final String? gender;
  final String? bodyType;
  final String? kitType;
  final String? deliveryDate;
  final String? deliveryTime;
  final String? customerAddressId;
  final int? durationDays;
  final String? height;
  final String? weight;
  final num price;
  final List<OrderKitSelectedItem> selectedItems;

  factory OrderLineKitDetails.fromJson(Map<String, dynamic> json) {
    return OrderLineKitDetails(
      gender: json['gender']?.toString(),
      bodyType: json['bodyType']?.toString() ?? json['body_type']?.toString(),
      kitType: json['kit_type']?.toString() ?? json['kitType']?.toString(),
      deliveryDate: json['delivery_date']?.toString() ??
          json['deliveryDate']?.toString(),
      deliveryTime: json['delivery_time']?.toString() ??
          json['deliveryTime']?.toString(),
      customerAddressId: json['customerAddressId']?.toString() ??
          json['customer_address_id']?.toString(),
      durationDays: OrderHistoryItem._int(
        json['duration_days'] ?? json['durationDays'],
      ),
      height: json['height']?.toString(),
      weight: json['weight']?.toString(),
      price: OrderHistoryItem._num(json['price'] ?? json['kit_price']),
      selectedItems: _parseSelectedItems(
        json['selectedItems'] ?? json['selected_items'],
      ),
    );
  }

  static List<OrderKitSelectedItem> _parseSelectedItems(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map(
          (item) => OrderKitSelectedItem.fromJson(
            Map<String, dynamic>.from(item),
          ),
        )
        .toList();
  }
}

class OrderKitSelectedItem {
  const OrderKitSelectedItem({
    this.productId,
    this.productName,
    this.size,
    this.primaryImageUrl,
    this.price = 0,
    this.quantity = 1,
  });

  final String? productId;
  final String? productName;
  final String? size;
  final String? primaryImageUrl;
  final num price;
  final int quantity;

  factory OrderKitSelectedItem.fromJson(Map<String, dynamic> json) {
    return OrderKitSelectedItem(
      productId: json['productId']?.toString() ?? json['product_id']?.toString(),
      productName: json['product_name']?.toString() ?? json['productName']?.toString(),
      size: json['size']?.toString() ??
          json['sizeLabel']?.toString() ??
          json['size_label']?.toString(),
      primaryImageUrl: json['primary_image_url']?.toString() ??
          json['primaryImageUrl']?.toString() ??
          json['image_url']?.toString() ??
          json['imageUrl']?.toString(),
      price: OrderHistoryItem._num(json['price']),
      quantity: OrderHistoryItem._int(json['quantity']) ?? 1,
    );
  }
}

class OrderStatusHistoryEntry {
  const OrderStatusHistoryEntry({
    required this.status,
    this.timestamp,
  });

  final String status;
  final DateTime? timestamp;

  factory OrderStatusHistoryEntry.fromJson(Map<String, dynamic> json) {
    return OrderStatusHistoryEntry(
      status: json['status']?.toString() ?? '',
      timestamp: OrderHistoryItem._dateTime(json['timestamp']),
    );
  }
}

class OrderStatusConfigItem {
  const OrderStatusConfigItem({
    required this.status,
    required this.label,
    this.enabled = true,
    this.description,
  });

  final String status;
  final String label;
  final bool enabled;
  final String? description;

  factory OrderStatusConfigItem.fromJson(Map<String, dynamic> json) {
    return OrderStatusConfigItem(
      status: json['status']?.toString() ?? '',
      label: json['label']?.toString() ?? json['status']?.toString() ?? '',
      enabled: json['enabled'] == true ||
          json['enabled']?.toString() == '1' ||
          json['enabled'] == null,
      description: json['desc']?.toString() ?? json['description']?.toString(),
    );
  }
}
