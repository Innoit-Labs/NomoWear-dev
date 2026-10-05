class ApiConstants {
  static const String baseUrl = 'https://nomowear-backend.onrender.com/';
  // static const String baseUrl = 'http://192.168.0.15:5000';
  static const String loginPath = 'mobile/v1/login';
  static const String resendOtpPath = 'mobile/v1/resend-otp';
  static const String verifyOtpPath = 'mobile/v1/verify-otp';
  static const String registerPath = 'mobile/v1/register';
  static const String profilePath = 'mobile/v1/profile';
  static const String productsPath = 'mobile/v1/products';
  static const String productsNearbyPath = 'mobile/v1/products/nearby';
  static const String categoriesPath = 'categories';
  static const String wardrobeKitsPath = 'mobile/v1/wardrobe-kits';
  static String checkEligibilityPath(String kitId) =>
      '$wardrobeKitsPath/${kitId.trim()}/check-eligibility';
  static const String bannersPath = 'mobile/v1/banners';
  static const String planCategoriesPath = 'mobile/v1/plans/categories/';
  static const String plansPath = 'mobile/v1/plans';
  static const String subscriptionsCreateOrderPath =
      'mobile/v1/subscriptions/create-order';
  static const String subscriptionsActivePath =
      'mobile/v1/subscriptions/me/active';
  static const String subscriptionsMePath = 'mobile/v1/subscriptions/me';
  static const String subscriptionsVerifyPaymentPath =
      'mobile/v1/subscriptions/verify-payment';
  static const String subscriptionsUpgradePreviewPath =
      'mobile/v1/subscriptions/upgrade/preview';
  static const String subscriptionsUpgradeCreateOrderPath =
      'mobile/v1/subscriptions/upgrade/create-order';
  static const String subscriptionsUpgradeVerifyPaymentPath =
      'mobile/v1/subscriptions/upgrade/verify-payment';
  static const String ordersPath = 'mobile/v1/orders';
  static const String ordersInitiatePath = 'mobile/v1/orders/initiate';
  static const String ordersVerifyPaymentPath =
      'mobile/v1/orders/verify-payment';

  /// POST mobile/v1/orders/{orderId}/return
  static String orderReturnPath(String orderId) =>
      '$ordersPath/${orderId.trim()}/return';

  /// GET mobile/v1/orders/{orderId}/reattempt-quote
  static String orderReattemptQuotePath(String orderId) =>
      '$ordersPath/${orderId.trim()}/reattempt-quote';

  /// POST mobile/v1/orders/{orderId}/reorder
  static String orderReorderPath(String orderId) =>
      '$ordersPath/${orderId.trim()}/reorder';

  /// POST mobile/v1/orders/{orderId}/reattempt-return
  static String orderReattemptReturnPath(String orderId) =>
      '$ordersPath/${orderId.trim()}/reattempt-return';

  /// POST waitlist
  static const String waitlistPath = 'waitlist';

  /// GET waitlist/status/{idOrNumber}
  static String waitlistStatusPath(String idOrNumber) =>
      'waitlist/status/${idOrNumber.trim()}';

  /// DELETE mobile/v1/orders/{orderId}/cancel-pending
  static String cancelPendingOrderPath(String orderId) =>
      '$ordersPath/${orderId.trim()}/cancel-pending';
  static const String cartPath = 'mobile/v1/cart';
  static const String filtersPath = 'mobile/v1/filters/getFilters';
  static const String productsRatingPath = 'mobile/v1/products/rating';
  static const String productsMyRatingsPath = 'mobile/v1/products/my-ratings';
  static const String wishlistPath = 'wishlist';
  static const String customerAddressesPath = 'mobile/v1/customer-addresses';
  static const String customerAddressesByCustomerPath =
      'mobile/v1/customer-addresses/customer';
  static const String fcmTokenPath = 'mobile/v1/fcm-token';
  static const String customerNotificationsPath =
      'api/v1/mobile/customers/notifications';
  static const String clearAllNotificationsPath =
      'api/v1/mobile/notifications/clear-all';
  static const String markNotificationsReadPath =
      'api/v1/mobile/customers/notifications/mark-read';

  /// Master location lists for Profile Address (State → City/Village).
  /// Using Maps reverse geocoding data locally instead of CountriesNow external API.
}
