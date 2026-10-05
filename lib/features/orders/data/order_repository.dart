import 'package:nomowear/core/network/api_client.dart';
import 'package:nomowear/core/network/api_constants.dart';
import 'package:nomowear/core/network/api_exception.dart';
import 'package:nomowear/core/services/auth_storage.dart';
import 'package:nomowear/features/checkout/data/checkout_session.dart';
import 'package:nomowear/features/orders/data/models/initiate_order_result.dart';
import 'package:nomowear/features/orders/data/models/order_history.dart';
import 'package:nomowear/features/orders/data/models/order_return_result.dart';
import 'package:nomowear/features/orders/data/models/reattempt_quote.dart';
import 'package:nomowear/features/orders/data/models/refund_status_result.dart';
import 'package:nomowear/features/orders/data/models/reorder_result.dart';
import 'package:nomowear/features/orders/data/orders_cache.dart';
import 'package:nomowear/features/orders/data/pending_refund_store.dart';
import 'package:nomowear/features/profile/data/profile_cache.dart';
import 'package:nomowear/features/profile/data/profile_repository.dart';
import 'package:nomowear/features/subscriptions/data/subscription_cache.dart';
import 'package:nomowear/features/subscriptions/data/subscription_repository.dart';

class OrderRepository {
  OrderRepository({
    ApiClient? apiClient,
    AuthStorage? authStorage,
    SubscriptionRepository? subscriptionRepository,
    ProfileRepository? profileRepository,
  })  : _apiClient = apiClient ?? ApiClient(),
        _authStorage = authStorage ?? AuthStorage(),
        _subscriptionRepository =
            subscriptionRepository ?? SubscriptionRepository(),
        _profileRepository = profileRepository ?? ProfileRepository();

  final ApiClient _apiClient;
  final AuthStorage _authStorage;
  final SubscriptionRepository _subscriptionRepository;
  final ProfileRepository _profileRepository;

  Future<List<OrderHistoryItem>> getOrderHistory({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      final cached = OrdersCache.instance.orders;
      if (cached.isNotEmpty) return cached;
    }

    final authToken = await _authStorage.getAuthToken();
    if (authToken == null || authToken.isEmpty) {
      throw const ApiException('Not logged in. Please login again.');
    }

    final json = await _apiClient.get(
      ApiConstants.ordersPath,
      authToken: authToken,
    );

    if (json['success'] != true) {
      throw ApiException(
        json['message']?.toString() ?? 'Failed to load orders',
      );
    }

    final orders = _parseOrderHistory(json['data']);
    OrdersCache.instance.setOrders(orders);
    return orders;
  }

  List<OrderHistoryItem> _parseOrderHistory(dynamic data) {
    if (data is! List) return [];

    final orders = data
        .whereType<Map>()
        .map((item) => OrderHistoryItem.fromJson(
              Map<String, dynamic>.from(item),
            ))
        .where((order) => order.id.isNotEmpty)
        .toList();

    orders.sort((a, b) {
      final aDate = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bDate = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bDate.compareTo(aDate);
    });

    return orders;
  }

  Future<OrderHistoryItem> getOrderDetail(String orderId) async {
    final trimmedId = orderId.trim();
    if (trimmedId.isEmpty) {
      throw const ApiException('Invalid order id');
    }

    final authToken = await _authStorage.getAuthToken();
    if (authToken == null || authToken.isEmpty) {
      throw const ApiException('Not logged in. Please login again.');
    }

    final json = await _apiClient.get(
      '${ApiConstants.ordersPath}/$trimmedId',
      authToken: authToken,
    );

    if (json['success'] != true) {
      throw ApiException(
        json['message']?.toString() ?? 'Failed to load order details',
      );
    }

    final data = json['data'];
    if (data is! Map<String, dynamic>) {
      throw const ApiException('Invalid order details response');
    }

    final detail = OrderHistoryItem.fromJson(data);
    if (detail.id.isEmpty) {
      throw const ApiException('Invalid order details response');
    }

    OrdersCache.instance.upsertOrder(detail);
    return detail;
  }

  Future<InitiateOrderResult> initiateOrder({
    required String checkoutType,
    required bool nonSubscription,
    String? productClass,
    String? wardrobeKitId,
    String? addressId,
    String? deliveryDate,
    String? deliveryTime,
    String? orderNote,
  }) async {
    final authToken = await _authStorage.getAuthToken();
    if (authToken == null || authToken.isEmpty) {
      throw const ApiException('Not logged in. Please login again.');
    }

    final resolvedAddressId = await _resolveAddressId(addressId);
    var resolvedDeliveryDate =
        deliveryDate ?? CheckoutSession.instance.apiDeliveryDate;
    var resolvedDeliveryTime =
        deliveryTime ?? CheckoutSession.instance.deliveryTime?.trim();

    if (resolvedDeliveryDate == null || resolvedDeliveryDate.isEmpty) {
      resolvedDeliveryDate = _defaultDeliveryDate();
    }
    if (resolvedDeliveryTime == null || resolvedDeliveryTime.isEmpty) {
      resolvedDeliveryTime = defaultDeliveryTime;
    }

    final body = <String, dynamic>{
      'addressId': resolvedAddressId,
      'checkout_type': checkoutType,
      'non_subscription': nonSubscription,
      'deliveryDate': resolvedDeliveryDate,
      'deliveryTime': resolvedDeliveryTime,
    };
    final resolvedProductClass = productClass?.trim();
    if (resolvedProductClass != null && resolvedProductClass.isNotEmpty) {
      body['product_class'] = resolvedProductClass;
    }
    final resolvedKitId = wardrobeKitId?.trim();
    if (resolvedKitId != null && resolvedKitId.isNotEmpty) {
      body['kitId'] = resolvedKitId;
      body['wardrobe_kit_id'] = resolvedKitId;
    }
    final trimmedOrderNote = orderNote?.trim();
    if (trimmedOrderNote != null && trimmedOrderNote.isNotEmpty) {
      body['order_note'] = trimmedOrderNote;
    }

    final json = await _apiClient.post(
      ApiConstants.ordersInitiatePath,
      body,
      authToken: authToken,
    );

    if (json['success'] != true) {
      throw ApiException(
        json['message']?.toString() ?? 'Failed to initiate order',
      );
    }

    final data = json['data'];
    if (data is! Map<String, dynamic>) {
      throw const ApiException('Invalid order response');
    }

    final result = InitiateOrderResult.fromJson(data);
    if (result.orderId.isEmpty) {
      throw const ApiException('Invalid order response');
    }
    return result;
  }

  Future<InitiateOrderResult> verifyPayment({
    required String razorpayOrderId,
    required String razorpayPaymentId,
    required String razorpaySignature,
  }) async {
    final authToken = await _authStorage.getAuthToken();
    if (authToken == null || authToken.isEmpty) {
      throw const ApiException('Not logged in. Please login again.');
    }

    final json = await _apiClient.post(
      ApiConstants.ordersVerifyPaymentPath,
      {
        'razorpay_order_id': razorpayOrderId,
        'razorpay_payment_id': razorpayPaymentId,
        'razorpay_signature': razorpaySignature,
      },
      authToken: authToken,
    );

    if (json['success'] != true) {
      throw ApiException(
        json['message']?.toString() ?? 'Payment verification failed',
      );
    }

    final data = json['data'];
    if (data is! Map<String, dynamic>) {
      throw const ApiException('Invalid payment verification response');
    }

    final result = InitiateOrderResult.fromJson(data);
    if (result.orderId.isEmpty) {
      throw const ApiException('Invalid payment verification response');
    }
    return result;
  }

  /// Cancels a pending order and releases reserved stock.
  /// DELETE mobile/v1/orders/:id/cancel-pending
  Future<Map<String, dynamic>> cancelPendingOrder(String orderId) async {
    final authToken = await _authStorage.getAuthToken();
    if (authToken == null || authToken.isEmpty) {
      throw const ApiException('Not logged in. Please login again.');
    }
    final trimmedId = orderId.trim();
    if (trimmedId.isEmpty) {
      throw const ApiException('Invalid order id');
    }
    final json = await _apiClient.delete(
      ApiConstants.cancelPendingOrderPath(trimmedId),
      authToken: authToken,
    );
    if (json['success'] != true) {
      throw ApiException(
        json['message']?.toString() ?? 'Failed to cancel order',
      );
    }
    return json;
  }

  /// Requests a pickup/return for a delivered order.
  Future<OrderReturnResult> requestReturn({
    required String orderId,
    required String addressId,
    required String pickupDate,
    required String pickupTime,
    String? note,
  }) async {
    final trimmedOrderId = orderId.trim();
    final trimmedAddressId = addressId.trim();
    final trimmedDate = pickupDate.trim();
    final trimmedTime = pickupTime.trim();

    if (trimmedOrderId.isEmpty) {
      throw const ApiException('Invalid order id');
    }
    if (trimmedAddressId.isEmpty) {
      throw const ApiException('Please select a pickup address.');
    }
    if (trimmedDate.isEmpty || trimmedTime.isEmpty) {
      throw const ApiException('Please select pickup date and time.');
    }

    final authToken = await _authStorage.getAuthToken();
    if (authToken == null || authToken.isEmpty) {
      throw const ApiException('Not logged in. Please login again.');
    }

    final body = <String, dynamic>{
      'addressId': trimmedAddressId,
      'pickup_date': trimmedDate,
      'pickup_time': trimmedTime,
    };
    final trimmedNote = note?.trim();
    if (trimmedNote != null && trimmedNote.isNotEmpty) {
      body['note'] = trimmedNote;
    }

    final json = await _apiClient.post(
      ApiConstants.orderReturnPath(trimmedOrderId),
      body,
      authToken: authToken,
    );

    if (json['success'] != true) {
      throw ApiException(
        json['message']?.toString() ?? 'Failed to submit return request',
      );
    }

    return OrderReturnResult(
      message: json['message']?.toString() ??
          'Return request submitted successfully.',
      waitlisted: json['waitlisted'] == true,
    );
  }

  /// Gets delivery reattempt quote for failed/returned orders.
  /// GET mobile/v1/orders/:id/reattempt-quote
  Future<ReattemptQuote> getReattemptQuote(String orderId) async {
    final trimmedId = orderId.trim();
    if (trimmedId.isEmpty) {
      throw const ApiException('Invalid order id');
    }

    final authToken = await _authStorage.getAuthToken();
    if (authToken == null || authToken.isEmpty) {
      throw const ApiException('Not logged in. Please login again.');
    }

    final json = await _apiClient.get(
      ApiConstants.orderReattemptQuotePath(trimmedId),
      authToken: authToken,
    );

    if (json['success'] != true) {
      throw ApiException(
        json['message']?.toString() ?? 'Failed to get reattempt quote',
      );
    }

    final data = json['data'];
    if (data is! Map<String, dynamic>) {
      throw const ApiException('Invalid reattempt quote response');
    }

    return ReattemptQuote.fromJson(data);
  }

  /// Schedules delivery reattempt / reorder.
  /// POST mobile/v1/orders/:id/reorder
  Future<ReorderResult> reorderDelivery({
    required String orderId,
    required String deliveryDate,
    required String deliveryTime,
    String? razorpayPaymentId,
    String? razorpayOrderId,
    String? razorpaySignature,
  }) async {
    final trimmedId = orderId.trim();
    if (trimmedId.isEmpty) {
      throw const ApiException('Invalid order id');
    }

    final authToken = await _authStorage.getAuthToken();
    if (authToken == null || authToken.isEmpty) {
      throw const ApiException('Not logged in. Please login again.');
    }

    final body = <String, dynamic>{
      'delivery_date': deliveryDate.trim(),
      'delivery_time': deliveryTime.trim(),
    };
    if (razorpayPaymentId != null && razorpayPaymentId.trim().isNotEmpty) {
      body['razorpay_payment_id'] = razorpayPaymentId.trim();
    }
    if (razorpayOrderId != null && razorpayOrderId.trim().isNotEmpty) {
      body['razorpay_order_id'] = razorpayOrderId.trim();
    }
    if (razorpaySignature != null && razorpaySignature.trim().isNotEmpty) {
      body['razorpay_signature'] = razorpaySignature.trim();
    }

    final json = await _apiClient.post(
      ApiConstants.orderReorderPath(trimmedId),
      body,
      authToken: authToken,
    );

    if (json['success'] != true) {
      throw ApiException(
        json['message']?.toString() ?? 'Failed to schedule delivery reattempt',
      );
    }

    return ReorderResult.fromJson(json);
  }

  /// Reschedules return pickup when previous pickup failed or rejected.
  /// POST mobile/v1/orders/:id/reattempt-return
  Future<OrderReturnResult> reattemptReturn({
    required String orderId,
    required String pickupDate,
    required String pickupTime,
    String? addressId,
    String? note,
    String? fullName,
    String? mobile,
  }) async {
    final trimmedId = orderId.trim();
    if (trimmedId.isEmpty) {
      throw const ApiException('Invalid order id');
    }

    final authToken = await _authStorage.getAuthToken();
    if (authToken == null || authToken.isEmpty) {
      throw const ApiException('Not logged in. Please login again.');
    }

    final body = <String, dynamic>{
      'pickup_date': pickupDate.trim(),
      'pickup_time': pickupTime.trim(),
    };
    if (addressId != null && addressId.trim().isNotEmpty) {
      body['addressId'] = addressId.trim();
    }
    if (note != null && note.trim().isNotEmpty) {
      body['note'] = note.trim();
    }
    if (fullName != null && fullName.trim().isNotEmpty) {
      body['fullName'] = fullName.trim();
    }
    if (mobile != null && mobile.trim().isNotEmpty) {
      body['mobile'] = mobile.trim();
    }

    final json = await _apiClient.post(
      ApiConstants.orderReattemptReturnPath(trimmedId),
      body,
      authToken: authToken,
    );

    if (json['success'] != true) {
      throw ApiException(
        json['message']?.toString() ?? 'Failed to reschedule return pickup',
      );
    }

    return OrderReturnResult(
      message: json['message']?.toString() ??
          'Return pickup rescheduled successfully.',
      waitlisted: json['waitlisted'] == true,
    );
  }

  /// Submits customer refund / cancellation request.
  /// POST waitlist
  Future<String> submitRefundRequest({
    required String orderId,
    required String orderNumber,
    required String customerId,
    required String reason,
    required num amount,
    required String fullName,
    required String mobile,
    String? email,
  }) async {
    final trimmedOrderId = orderId.trim();
    if (trimmedOrderId.isEmpty) {
      throw const ApiException('Invalid order id');
    }

    final authToken = await _authStorage.getAuthToken();
    if (authToken == null || authToken.isEmpty) {
      throw const ApiException('Not logged in. Please login again.');
    }

    final body = <String, dynamic>{
      'waitlist_type': 'CUSTOMER_REFUND_REQUEST',
      'form_data': {
        'orderId': trimmedOrderId,
        'orderNumber': orderNumber.trim(),
        'customerId': customerId.trim(),
        'reason': reason.trim(),
        'amount': amount,
        'fullName': fullName.trim(),
        'mobile': mobile.trim(),
        'email': (email ?? '').trim(),
      },
    };

    final json = await _apiClient.post(
      ApiConstants.waitlistPath,
      body,
      authToken: authToken,
    );

    if (json['success'] != true) {
      throw ApiException(
        json['message']?.toString() ?? 'Failed to submit refund request',
      );
    }

    final data = json['data'] is Map ? json['data'] : null;
    final waitlistNum = (data?['waitlist_number'] ??
            data?['waitlistNumber'] ??
            json['waitlist_number'] ??
            data?['number'] ??
            data?['id'] ??
            json['id'] ??
            '')
        .toString();

    if (waitlistNum.isNotEmpty) {
      await PendingRefundStore.instance.saveRefundRequest(
        orderId: trimmedOrderId,
        waitlistNumber: waitlistNum,
      );
    }

    return waitlistNum.isNotEmpty
        ? waitlistNum
        : (json['message']?.toString() ?? 'Refund request submitted');
  }

  /// Gets status of a waitlist item (e.g. CUSTOMER_REFUND_REQUEST).
  /// GET waitlist/status/:idOrNumber
  Future<RefundStatusResult> getRefundStatus(String idOrNumber) async {
    final trimmed = idOrNumber.trim();
    if (trimmed.isEmpty) {
      throw const ApiException('Invalid waitlist number or id');
    }

    final authToken = await _authStorage.getAuthToken();
    if (authToken == null || authToken.isEmpty) {
      throw const ApiException('Not logged in. Please login again.');
    }

    final json = await _apiClient.get(
      ApiConstants.waitlistStatusPath(trimmed),
      authToken: authToken,
    );

    if (json['success'] != true) {
      throw ApiException(
        json['message']?.toString() ?? 'Failed to get refund status',
      );
    }

    return RefundStatusResult.fromJson(json, trimmed);
  }

  Future<bool> hasActiveSubscription({bool forceRefresh = false}) async {
    try {
      final active = await _subscriptionRepository.getActiveSubscription(
        forceRefresh: forceRefresh,
      );
      return active != null && active.isActive;
    } catch (_) {
      if (forceRefresh) return false;
      final cached = SubscriptionCache.instance.activeSubscription;
      return cached != null && cached.isActive;
    }
  }

  Future<String> submitProductRating({
    required String productId,
    required int rating,
    String? review,
  }) async {
    final trimmedProductId = productId.trim();
    if (trimmedProductId.isEmpty) {
      throw const ApiException('Invalid product id');
    }
    if (rating < 1 || rating > 5) {
      throw const ApiException('Rating must be between 1 and 5.');
    }

    final authToken = await _authStorage.getAuthToken();
    if (authToken == null || authToken.isEmpty) {
      throw const ApiException('Not logged in. Please login again.');
    }

    final body = <String, dynamic>{
      'productId': trimmedProductId,
      'rating': rating,
    };
    final trimmedReview = review?.trim();
    if (trimmedReview != null && trimmedReview.isNotEmpty) {
      body['review'] = trimmedReview;
    }

    final json = await _apiClient.post(
      ApiConstants.productsRatingPath,
      body,
      authToken: authToken,
    );

    if (json['success'] != true) {
      throw ApiException(
        json['message']?.toString() ?? 'Failed to submit rating',
      );
    }

    return json['message']?.toString() ?? 'Rating submitted successfully';
  }

  Future<Set<String>> getMyRatedProductIds({
    required List<String> productIds,
  }) async {
    final ratings = await getMyProductRatings(productIds: productIds);
    return ratings.keys.toSet();
  }

  Future<Map<String, int>> getMyProductRatings({
    required List<String> productIds,
  }) async {
    final normalized = productIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    if (normalized.isEmpty) return const <String, int>{};

    final authToken = await _authStorage.getAuthToken();
    if (authToken == null || authToken.isEmpty) {
      throw const ApiException('Not logged in. Please login again.');
    }

    final json = await _apiClient.post(
      ApiConstants.productsMyRatingsPath,
      <String, dynamic>{'productIds': normalized},
      authToken: authToken,
    );

    if (json['success'] != true) {
      throw ApiException(
        json['message']?.toString() ?? 'Failed to load product ratings',
      );
    }

    final data = json['data'];
    if (data is! Map) return const <String, int>{};

    final ratings = <String, int>{};
    for (final entry in data.entries) {
      final id = entry.key.toString().trim();
      if (id.isEmpty) continue;
      final raw = entry.value;
      final rating = _extractRating(raw);
      if (rating != null && rating >= 1 && rating <= 5) {
        ratings[id] = rating;
      } else {
        ratings[id] = 0;
      }
    }
    return ratings;
  }

  static int? _extractRating(dynamic raw) {
    if (raw == null) return null;
    if (raw is num) return raw.round();
    if (raw is String) return int.tryParse(raw.trim());
    if (raw is Map) {
      final candidates = [
        raw['rating'],
        raw['stars'],
        raw['value'],
      ];
      for (final value in candidates) {
        final parsed = _extractRating(value);
        if (parsed != null) return parsed;
      }
    }
    return null;
  }

  Future<String> _resolveAddressId(String? preferredId) async {
    final trimmed = preferredId?.trim();
    if (trimmed != null && trimmed.isNotEmpty) return trimmed;

    final sessionId = CheckoutSession.instance.addressId?.trim();
    if (sessionId != null && sessionId.isNotEmpty) return sessionId;

    var customer = ProfileCache.instance.customer;
    customer ??= await _profileRepository.getProfile();

    for (final address in customer.addresses) {
      final id = address.id?.trim();
      if (id != null && id.isNotEmpty) return id;
    }

    throw const ApiException(
      'Please add a delivery address in your profile before placing an order.',
    );
  }

  static const String defaultDeliveryTime = '09:00 AM - 12:00 PM';

  String _defaultDeliveryDate() {
    final date = DateTime.now().add(const Duration(days: 1));
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }
}
