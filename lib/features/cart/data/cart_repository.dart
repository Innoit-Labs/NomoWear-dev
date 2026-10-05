import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:nomowear/core/network/api_client.dart';
import 'package:nomowear/core/network/api_constants.dart';
import 'package:nomowear/core/network/api_exception.dart';
import 'package:nomowear/core/services/auth_storage.dart';
import 'package:nomowear/core/utils/api_id_utils.dart';
import 'package:nomowear/features/cart/data/models/remote_cart.dart';
import 'package:nomowear/features/checkout/data/checkout_session.dart';
import 'package:nomowear/features/checkout/data/subscription_kit_preferences.dart';
import 'package:nomowear/features/products/data/product_cache.dart';
import 'package:nomowear/features/products/data/product_repository.dart';
import 'package:nomowear/features/profile/data/profile_cache.dart';
import 'package:nomowear/features/profile/data/profile_repository.dart';

void _log(String message) {
  if (kDebugMode) debugPrint('[CART_API] $message');
}

class CartWriteResult {
  const CartWriteResult({
    required this.remote,
    required this.isAuthoritative,
    required this.durationMs,
  });

  final RemoteCart remote;
  final bool isAuthoritative;
  final int durationMs;
}

bool cartPayloadLooksAuthoritative(Map<String, dynamic> data) {
  return data.containsKey('cartItems') ||
      data.containsKey('cart_items') ||
      data.containsKey('sections') ||
      data.containsKey('summary') ||
      data.containsKey('item_count') ||
      data.containsKey('itemCount');
}

class CartWriteRequest {
  const CartWriteRequest({
    required this.productId,
    required this.quantity,
    required this.itemType,
    this.variantId,
    this.size,
    this.categoryName,
    this.kitDetails,
    this.productClass,
    this.productName,
  });

  final String productId;
  final int quantity;
  final String itemType;
  final String? variantId;
  final String? size;
  final String? categoryName;
  final Map<String, dynamic>? kitDetails;
  final String? productClass;

  /// Debug-only. Not sent in the POST body.
  final String? productName;
}

class CartRepository {
  CartRepository({
    ApiClient? apiClient,
    AuthStorage? authStorage,
    ProfileRepository? profileRepository,
  })  : _apiClient = apiClient ?? ApiClient(),
        _authStorage = authStorage ?? AuthStorage(),
        _profileRepository = profileRepository ?? ProfileRepository();

  final ApiClient _apiClient;
  final AuthStorage _authStorage;
  final ProfileRepository _profileRepository;

  int _nextRequestId = 0;

  int nextRequestId() => ++_nextRequestId;

  Future<String> _token() async {
    final sw = Stopwatch()..start();
    if (kDebugMode) {
      debugPrint(
        '[CART_NETWORK] TOKEN_LOOKUP_START timestamp=${DateTime.now().toIso8601String()}',
      );
    }
    final authToken = await _authStorage.getAuthToken();
    sw.stop();
    if (kDebugMode) {
      debugPrint(
        '[CART_NETWORK] TOKEN_LOOKUP_END duration=${sw.elapsedMilliseconds}ms found=${authToken != null && authToken.isNotEmpty}',
      );
    }
    if (authToken == null || authToken.isEmpty) {
      throw const ApiException('Not logged in. Please login again.');
    }
    return authToken;
  }

  Future<RemoteCart> getCart({
    required int requestId,
    required String source,
  }) async {
    _log(
      'API GET START requestId=$requestId source=$source '
      'ts=${DateTime.now().toIso8601String()}',
    );
    if (kDebugMode) debugPrint('[CART_PERF] GET START requestId=$requestId source=$source');
    final sw = Stopwatch()..start();

    var addressId = CheckoutSession.instance.addressId?.trim();
    if (addressId == null || addressId.isEmpty) {
      for (final addr in ProfileCache.instance.customer?.addresses ?? const []) {
        final id = addr.id?.trim();
        if (id != null && id.isNotEmpty) {
          addressId = id;
          break;
        }
      }
    }

    final path = (addressId != null && addressId.isNotEmpty && isApiUuid(addressId))
        ? '${ApiConstants.cartPath}?addressId=$addressId'
        : ApiConstants.cartPath;

    final json = await _apiClient.get(
      path,
      authToken: await _token(),
    );
    _printCartDebugGet(json: json, requestId: requestId, source: source);
    sw.stop();
    if (kDebugMode) {
      debugPrint(
        '[CART_PERF] GET END duration=${sw.elapsedMilliseconds}ms '
        'requestId=$requestId source=$source',
      );
    }
    if (json['success'] != true) {
      throw ApiException(json['message']?.toString() ?? 'Failed to load cart');
    }

    final data = json['data'];
    if (data is! Map<String, dynamic>) {
      _log('API GET RESPONSE requestId=$requestId itemCount=0 (no data)');
      return const RemoteCart(id: '', items: []);
    }

    final remote = RemoteCart.fromJson(data);
    _log(
      'API GET RESPONSE requestId=$requestId source=$source '
      'cartId=${remote.id} updatedAt=${remote.updatedAt ?? '-'} '
      'itemCount=${remote.itemCount} '
      'subscription=${remote.subscriptionCount} '
      'non_subscription=${remote.nonSubscriptionCount} '
      'essentials=${remote.essentialsCount} '
      'kids=${remote.kidsCount}',
    );
    return remote;
  }

  Future<CartWriteResult> upsert({
    required CartWriteRequest request,
    required int requestId,
    required String source,
  }) async {
    if (!isApiUuid(request.productId)) {
      throw const ApiException(
        'Invalid product in cart. Remove it and add items from the catalog again.',
      );
    }

    var variantId = (request.variantId != null &&
            request.variantId!.trim().isNotEmpty &&
            request.variantId!.trim() != '-')
        ? request.variantId!.trim()
        : null;

    // Only invent a variant for wardrobe-kit POSTs. For garments/essentials,
    // a wrong first-variant fallback creates duplicate / incorrect cart lines.
    final isKitWrite =
        request.kitDetails != null || request.productClass == 'wardrobe_kit';
    if ((variantId == null || variantId.isEmpty) && isKitWrite) {
      final cachedProduct = ProductCache.instance.findById(request.productId);
      if (cachedProduct != null && cachedProduct.variants.isNotEmpty) {
        variantId = cachedProduct.variants.first.id;
      }

      if (variantId == null || variantId.isEmpty) {
        if (request.productId ==
            SubscriptionKitPreferences.instance.wardrobeKitProductId) {
          variantId = SubscriptionKitPreferences.instance.wardrobeKitVariantId;
        }
      }

      if ((variantId == null || variantId.isEmpty) &&
          isApiUuid(request.productId)) {
        try {
          final fetched =
              await ProductRepository().getProductById(request.productId);
          if (fetched.variants.isNotEmpty) {
            variantId = fetched.variants.first.id;
          }
        } catch (e) {
          _log('Failed to fetch product for variant in upsert: $e');
        }
      }
    }

    var kitDetails = (request.kitDetails != null && request.kitDetails!.isNotEmpty)
        ? request.kitDetails
        : null;

    if (kitDetails == null &&
        (request.itemType == 'subscription' ||
            request.itemType == 'non_subscription')) {
      final kitId = SubscriptionKitPreferences.instance.wardrobeKitId;
      final kitPid = SubscriptionKitPreferences.instance.wardrobeKitProductId ?? request.productId;
      kitDetails = await subscriptionKitDetails(
        wardrobeKitId: kitId,
        wardrobeKitProductId: kitPid,
        durationDays: SubscriptionKitPreferences.instance.wardrobeKitDays > 0
            ? SubscriptionKitPreferences.instance.wardrobeKitDays
            : 1,
        kitName: SubscriptionKitPreferences.instance.wardrobeKitName.isNotEmpty
            ? SubscriptionKitPreferences.instance.wardrobeKitName
            : 'Wardrobe Kit',
        selectedItems: const [],
      );
      if (kitDetails != null) {
        kitDetails['non_subscription'] = request.itemType == 'non_subscription';
        kitDetails['cart_section'] = request.itemType;
      }
    }

    final body = <String, dynamic>{
      'productId': request.productId,
      'quantity': request.quantity,
      if (variantId != null && variantId.isNotEmpty) 'variantId': variantId,
      if (kitDetails != null) 'kitDetails': kitDetails,
    };

    if (request.itemType.isNotEmpty) {
      body['item_type'] = request.itemType;
    }

    // Removed extra fields (size, categoryName, product_class) 
    // to strictly match the exact backend POST /mobile/v1/cart schema.

    final encoded = jsonEncode(body);
    _log('API POST START requestId=$requestId source=$source');
    _printSingleItemCartDebug(
      request: request,
      body: body,
      encoded: encoded,
      source: source,
      requestId: requestId,
    );
    _printCartDebugPostRequest(
      request: request,
      body: body,
      encoded: encoded,
      source: source,
      requestId: requestId,
    );
    if (kDebugMode) {
      debugPrint(
        '[CART_PERF] POST START requestId=$requestId source=$source '
        'productId=${request.productId} qty=${request.quantity} '
        'itemType=${request.itemType}',
      );
      debugPrint('[CART_NETWORK] POST_REQUEST_ID=$requestId source=$source');
    }
    final sw = Stopwatch()..start();

    final json = await _apiClient.post(
      ApiConstants.cartPath,
      body,
      authToken: await _token(),
    );
    sw.stop();
    _printCartDebugPostResponse(json: json, requestId: requestId, source: source);
    if (kDebugMode) {
      debugPrint(
        '[CART_PERF] POST END duration=${sw.elapsedMilliseconds}ms '
        'requestId=$requestId source=$source',
      );
    }
    if (json['success'] != true) {
      throw ApiException(
        json['message']?.toString() ?? 'Failed to update cart',
      );
    }
    final data = json['data'];
    if (data is Map<String, dynamic>) {
      final authoritative = cartPayloadLooksAuthoritative(data);
      final parseSw = Stopwatch()..start();
      final remote = RemoteCart.fromJson(data);
      parseSw.stop();
      if (kDebugMode) {
        debugPrint(
          '[CART_PERF] POST CART authoritative=$authoritative '
          'itemCount=${remote.itemCount} items=${remote.items.length} '
          'remoteParse=${parseSw.elapsedMilliseconds}ms',
        );
      }
      return CartWriteResult(
        remote: remote,
        isAuthoritative: authoritative,
        durationMs: sw.elapsedMilliseconds,
      );
    }
    if (kDebugMode) {
      debugPrint('[CART_PERF] POST CART authoritative=false (no data)');
    }
    return CartWriteResult(
      remote: const RemoteCart(id: '', items: []),
      isAuthoritative: false,
      durationMs: sw.elapsedMilliseconds,
    );
  }

  Future<Map<String, dynamic>?> subscriptionKitDetails({
    required String? wardrobeKitId,
    required String? wardrobeKitProductId,
    required int durationDays,
    required String kitName,
    List<dynamic>? selectedItems,
  }) async {
    final session = CheckoutSession.instance;
    var addressId = session.addressId?.toString().trim();
    if (addressId == null || addressId.isEmpty) {
      addressId = SubscriptionKitPreferences.instance.addressId;
    }

    var customer = ProfileCache.instance.customer;
    if ((addressId == null || addressId.isEmpty) && customer == null) {
      try {
        customer = await _profileRepository.getProfile();
      } catch (_) {
        customer = ProfileCache.instance.customer;
      }
    }

    if (addressId == null || addressId.isEmpty) {
      for (final address in customer?.addresses ?? const []) {
        final id = address.id?.trim();
        if (id != null && id.isNotEmpty) {
          addressId = id;
          break;
        }
      }
    }

    final rawType = (session.kitType ?? kitName).trim();
    final String resolvedKitType;
    if (rawType.isNotEmpty &&
        rawType.toLowerCase() != 'custom' &&
        rawType.toLowerCase() != 'standard') {
      resolvedKitType = rawType;
    } else if (durationDays > 0) {
      resolvedKitType = '$durationDays-Day wardrobe Kit';
    } else {
      resolvedKitType = rawType.isNotEmpty ? rawType : 'Wardrobe Kit';
    }

    final details = RemoteCartKitDetails(
      gender: session.gender ?? 'male',
      bodyType: session.bodyType ?? 'regular',
      kitType: resolvedKitType,
      deliveryDate: session.apiDeliveryDate,
      deliveryTime: session.deliveryTime,
      customerAddressId: addressId,
      height: customer?.height,
      weight: customer?.weight,
      wardrobeKitId: wardrobeKitId,
      wardrobeKitProductId: wardrobeKitProductId,
      durationDays: durationDays,
      selectedItems: selectedItems,
    );
    final json = details.toJson();
    return json.isEmpty ? null : json;
  }
}

void _printSingleItemCartDebug({
  required CartWriteRequest request,
  required Map<String, dynamic> body,
  required String encoded,
  required String source,
  required int requestId,
}) {
  if (!kDebugMode) return;
  debugPrint('========== SINGLE ITEM CART DEBUG ==========');
  debugPrint('[CART DEBUG] POST REQUEST');
  debugPrint('source=$source requestId=$requestId');
  debugPrint('Product ID: ${body['productId']}');
  debugPrint('Product Name: ${request.productName ?? '-'}');
  debugPrint('Product Class: ${body['product_class']}');
  debugPrint('Category: ${body['categoryName'] ?? '-'}');
  debugPrint('Variant ID: ${body['variantId'] ?? '-'}');
  debugPrint('Quantity: ${body['quantity']}');
  debugPrint('Size: ${body['size'] ?? '-'}');
  debugPrint('item_type: ${body['item_type']}');
  debugPrint('itemType: ${body['itemType']}');
  debugPrint(
    'cart_section: ${body['cart_section'] ?? body['cartSection'] ?? '-'}',
  );
  debugPrint(
    'kitDetails: ${body.containsKey('kitDetails') ? jsonEncode(body['kitDetails']) : '-'}',
  );
  debugPrint('FINAL POST BODY:');
  _printLong(encoded);
  debugPrint('============================================');
}

void _printCartDebugPostRequest({
  required CartWriteRequest request,
  required Map<String, dynamic> body,
  required String encoded,
  required String source,
  required int requestId,
}) {
  if (!kDebugMode) return;
  debugPrint('========== CART ADD DEBUG ==========');
  debugPrint('[CART DEBUG] POST REQUEST');
  debugPrint('source=$source requestId=$requestId');
  debugPrint('Product ID: ${body['productId']}');
  debugPrint('Product Name: ${request.productName ?? '-'}');
  debugPrint('Product Class: ${body['product_class']}');
  debugPrint('Item Type: ${body['item_type']}');
  debugPrint('Item Type (camelCase): ${body['itemType']}');
  debugPrint('Quantity: ${body['quantity']}');
  debugPrint('Variant ID: ${body['variantId'] ?? '-'}');
  debugPrint('Category: ${body['categoryName'] ?? '-'}');
  debugPrint('Size: ${body['size'] ?? '-'}');
  debugPrint(
    'cart_section: ${body['cart_section'] ?? body['cartSection'] ?? '-'}',
  );
  debugPrint(
    'Kit Details: ${body.containsKey('kitDetails') ? jsonEncode(body['kitDetails']) : '-'}',
  );
  debugPrint('------------------------------------');
  debugPrint('FINAL CART POST BODY:');
  _printLong(encoded);
  debugPrint('====================================');
}

void _printCartDebugPostResponse({
  required Map<String, dynamic> json,
  required int requestId,
  required String source,
}) {
  if (!kDebugMode) return;
  debugPrint('[CART DEBUG] POST RESPONSE');
  debugPrint('source=$source requestId=$requestId');
  _printLong(jsonEncode(json));
}

void _printCartDebugGet({
  required Map<String, dynamic> json,
  required int requestId,
  required String source,
}) {
  if (!kDebugMode) return;
  debugPrint('[CART DEBUG] GET CART RESPONSE');
  debugPrint('source=$source requestId=$requestId');
  _printLong(jsonEncode(json));

  final data = json['data'];
  if (data is! Map) {
    debugPrint('========== CART GET DEBUG ==========');
    debugPrint('no data');
    debugPrint('====================================');
    return;
  }
  final map = Map<String, dynamic>.from(data);
  final sections = map['sections'];
  int sectionCount(String key) {
    if (sections is! Map) return 0;
    final block = sections[key];
    if (block is! Map) return 0;
    final listed = block['item_count'] ?? block['itemCount'];
    if (listed is num) return listed.toInt();
    final list = block['items'];
    return list is List ? list.length : 0;
  }

  debugPrint('========== CART GET DEBUG ==========');
  debugPrint('sections.subscription count: ${sectionCount('subscription')}');
  debugPrint(
    'sections.non_subscription count: ${sectionCount('non_subscription')}',
  );
  debugPrint('sections.essentials count: ${sectionCount('essentials')}');
  debugPrint('sections.kids count: ${sectionCount('kids')}');

  void printRow(String origin, Map row) {
    final kit = row['kitDetails'] ?? row['kit_details'];
    debugPrint('--- item ($origin) ---');
    debugPrint('productId: ${row['productId'] ?? row['product_id']}');
    debugPrint(
      'productClass: ${row['productClass'] ?? row['product_class']}',
    );
    debugPrint('item_type: ${row['item_type']}');
    debugPrint('itemType: ${row['itemType']}');
    if (kit is Map) {
      debugPrint(
        'kitDetails.non_subscription: ${kit['non_subscription'] ?? kit['nonSubscription']}',
      );
      debugPrint(
        'kitDetails.cart_section: ${kit['cart_section'] ?? kit['cartSection']}',
      );
    } else {
      debugPrint('kitDetails.non_subscription: -');
      debugPrint('kitDetails.cart_section: -');
    }
  }

  final cartItems = map['cartItems'] ?? map['cart_items'];
  if (cartItems is List) {
    for (final row in cartItems) {
      if (row is Map) printRow('cartItems', Map<String, dynamic>.from(row));
    }
  }
  if (sections is Map) {
    for (final key in [
      'subscription',
      'non_subscription',
      'essentials',
      'kids',
    ]) {
      final block = sections[key];
      if (block is! Map) continue;
      final items = block['items'];
      if (items is! List) continue;
      for (final row in items) {
        if (row is Map) {
          printRow('sections.$key', Map<String, dynamic>.from(row));
        }
      }
    }
  }
  debugPrint('====================================');
}

void _printLong(String text) {
  const chunk = 800;
  if (text.length <= chunk) {
    debugPrint(text);
    return;
  }
  for (var i = 0; i < text.length; i += chunk) {
    final end = i + chunk > text.length ? text.length : i + chunk;
    debugPrint(text.substring(i, end));
  }
}
