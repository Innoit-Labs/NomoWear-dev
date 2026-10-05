import 'package:flutter/foundation.dart';
import 'package:nomowear/core/network/api_client.dart';
import 'package:nomowear/core/network/api_constants.dart';
import 'package:nomowear/core/network/api_exception.dart';
import 'package:nomowear/core/services/auth_storage.dart';
import 'package:nomowear/features/checkout/data/checkout_session.dart';
import 'package:nomowear/features/products/data/models/product.dart';
import 'package:nomowear/features/products/data/product_cache.dart';
import 'package:nomowear/features/products/data/product_catalog.dart';
import 'package:nomowear/features/profile/data/profile_cache.dart';
import 'package:nomowear/features/profile/domain/saved_address.dart';
import 'package:nomowear/core/services/google_maps_service.dart';
import 'package:geolocator/geolocator.dart';

class ProductRepository {
  static Future<List<Product>>? _inFlightProductsRequest;

  final ApiClient _apiClient;
  final AuthStorage _authStorage;

  /// Pagination metadata from the most recent [getProducts] call.
  int? lastFetchedPage;
  int? lastTotalPages;
  int? lastTotalItems;
  int? lastRequestedLimit;
  int lastFetchedCount = 0;

  bool get lastHasNextPage {
    final page = lastFetchedPage;
    final totalPages = lastTotalPages;
    if (page != null && totalPages != null && totalPages > 0) {
      return page < totalPages;
    }
    final limit = lastRequestedLimit;
    if (limit != null && limit > 0) {
      return lastFetchedCount >= limit;
    }
    return false;
  }

  ProductRepository({
    ApiClient? apiClient,
    AuthStorage? authStorage,
  })  : _apiClient = apiClient ?? ApiClient(),
        _authStorage = authStorage ?? AuthStorage();

  /// [action] is `kids` or `adults` (same as filter options API).
  /// [tab] is the Admin wardrobe category query (e.g. `Professional wardrobe`).
  /// [age] / [gender] match filter API field names (`data.age`, `data.gender`).
  /// Tab / filter / action-scoped requests bypass the unfiltered product cache.
  Future<List<Product>> getProducts({
    bool forceRefresh = false,
    bool useNearbyLocation = false,
    String? action,
    String? age,
    String? gender,
    String? tab,
    int? page,
    int? limit,
  }) async {
    final actionParam = action?.trim().toLowerCase();
    final ageParam = age?.trim();
    final genderParam = gender?.trim();
    var tabParam = tab?.trim();
    if (tabParam != null && tabParam.toLowerCase() == 'kidswardrobe') {
      tabParam = 'Kids Wardrobe';
    }
    final hasAction =
        actionParam != null &&
        actionParam.isNotEmpty &&
        actionParam != 'all';
    final hasTab = tabParam != null && tabParam.isNotEmpty;
    final hasFilters = (ageParam != null && ageParam.isNotEmpty) ||
        (genderParam != null && genderParam.isNotEmpty) ||
        hasAction ||
        hasTab;

    if (!hasFilters && !forceRefresh) {
      final cached = ProductCache.instance.products;
      if (cached != null) return cached;
    }

    // Deduplicate only unfiltered catalogue fetches.
    if (!hasFilters && _inFlightProductsRequest != null) {
      return _inFlightProductsRequest!;
    }

    final request = () async {
      final authToken = await _authStorage.getAuthToken();
      if (authToken == null || authToken.isEmpty) {
        throw const ApiException('Not logged in. Please login again.');
      }

      final query = <String, String>{};
      String apiPath = ApiConstants.productsPath;

      if (useNearbyLocation || hasTab || hasAction) {
        final profile = ProfileCache.instance.customer;
        final checkoutAddressId = CheckoutSession.instance.addressId;
        
        final isKidsOrEssentials = (tabParam != null && 
            (tabParam.toLowerCase() == 'kids wardrobe' || tabParam.toLowerCase() == 'essentials wardrobe')) ||
            (actionParam == 'kids');

        double? activeLatitude;
        double? activeLongitude;
        String locationSource = '';

        if (isKidsOrEssentials) {
          // ── Device GPS location for Kids / Essentials ────────────────
          // Strategy:
          //  1. getLastKnownPosition() — instant, cached by the OS
          //  2. getCurrentPosition() with 10 s timeout
          //  3. One retry if the first attempt times out
          //  4. Fall back to last-known if fresh location fails

          final categoryLabel = tabParam ?? actionParam ?? 'unknown';

          var permission = await Geolocator.checkPermission();
          if (permission == LocationPermission.denied) {
            permission = await Geolocator.requestPermission();
          }

          final serviceEnabled = await Geolocator.isLocationServiceEnabled();

          if (kDebugMode) {
            debugPrint('[LOCATION_DEBUG]');
            debugPrint('category=$categoryLabel');
            debugPrint('permission=$permission');
            debugPrint('serviceEnabled=$serviceEnabled');
          }

          if (permission != LocationPermission.whileInUse &&
              permission != LocationPermission.always) {
            if (kDebugMode) {
              debugPrint('[LOCATION_DEBUG] callingApi=false reason=Permission denied');
            }
            throw const ApiException(
              'Location is missing. Please grant location permission.',
            );
          }

          if (!serviceEnabled) {
            if (kDebugMode) {
              debugPrint('[LOCATION_DEBUG] callingApi=false reason=Location service disabled');
            }
            throw const ApiException(
              'Location is missing. Location services are disabled.',
            );
          }

          // Step 1: last-known position (instant, may be null on first use)
          Position? lastKnown;
          try {
            lastKnown = await Geolocator.getLastKnownPosition();
          } catch (_) {}

          if (kDebugMode) {
            debugPrint('[LOCATION_DEBUG] lastKnownLocation='
                '${lastKnown != null ? '${lastKnown.latitude},${lastKnown.longitude}' : 'null'}');
          }

          // Step 2: fresh GPS position with reasonable timeout
          const locationTimeout = Duration(seconds: 10);
          Position? freshPosition;

          for (var attempt = 1; attempt <= 2; attempt++) {
            try {
              if (kDebugMode) {
                debugPrint('[LOCATION_DEBUG] requestingCurrentLocation=true '
                    'attempt=$attempt timeout=${locationTimeout.inSeconds}s');
              }
              freshPosition = await Geolocator.getCurrentPosition(
                desiredAccuracy: LocationAccuracy.medium,
                timeLimit: locationTimeout,
              );
              if (kDebugMode) {
                debugPrint('[LOCATION_DEBUG] currentLocation='
                    '${freshPosition.latitude},${freshPosition.longitude} '
                    'attempt=$attempt');
              }
              break; // success — no retry needed
            } catch (e) {
              if (kDebugMode) {
                debugPrint('[LOCATION_DEBUG] attempt=$attempt failed=${e.runtimeType}: $e');
              }
              // Only retry on timeout; other errors (e.g. permission revoked) fail immediately
              final isTimeout = e.toString().contains('TimeoutException');
              if (!isTimeout || attempt == 2) break;
              // brief pause before retry to let GPS settle
              await Future<void>.delayed(const Duration(milliseconds: 500));
            }
          }

          // Step 3: pick the best available location
          if (freshPosition != null) {
            activeLatitude = freshPosition.latitude;
            activeLongitude = freshPosition.longitude;
            locationSource = 'current_device';
          } else if (lastKnown != null) {
            activeLatitude = lastKnown.latitude;
            activeLongitude = lastKnown.longitude;
            locationSource = 'last_known';
          }

          if (kDebugMode) {
            debugPrint('[LOCATION_DEBUG] '
                'latitude=$activeLatitude '
                'longitude=$activeLongitude '
                'locationSource=$locationSource');
          }
        } else {
          // ── Wardrobe product listing: use the selected delivery address ───────
          // Priority:
          //  1. Coordinates stored in CheckoutSession when user confirmed kit/address
          //  2. Matching saved address lat/lng from userSavedAddresses
          //  3. Profile lat/lng
          //  4. Google Maps geocode of address text

          // 1. CheckoutSession coordinates (set when user tapped NEXT in Kit screen)
          final sessionLat = CheckoutSession.instance.addressLatitude;
          final sessionLng = CheckoutSession.instance.addressLongitude;
          if (sessionLat != null && sessionLng != null) {
            activeLatitude = sessionLat;
            activeLongitude = sessionLng;
            locationSource = 'session_address';
          }

          // 2. Saved address lookup (if session coords missing)
          if (activeLatitude == null || activeLongitude == null) {
            SavedAddress? selectedAddress;
            if (checkoutAddressId != null && userSavedAddresses.isNotEmpty) {
              for (final a in userSavedAddresses) {
                if (a.id == checkoutAddressId) {
                  selectedAddress = a;
                  break;
                }
              }
            }
            if (selectedAddress == null && userSavedAddresses.isNotEmpty) {
              selectedAddress = userSavedAddresses.first;
            }
            if (selectedAddress != null &&
                selectedAddress.latitude != null &&
                selectedAddress.longitude != null) {
              activeLatitude = selectedAddress.latitude;
              activeLongitude = selectedAddress.longitude;
              locationSource = 'saved_address';
            } else if (profile != null &&
                profile.latitude != null &&
                profile.longitude != null) {
              // 3. Profile lat/lng
              activeLatitude = profile.latitude;
              activeLongitude = profile.longitude;
              locationSource = 'profile';
            } else {
              // 4. Google Maps geocode fallback
              // Use the address text from the matched address, or fall back to
              // CheckoutSession.addressLines (set from the Kit screen NEXT button).
              final addressText = (selectedAddress != null && selectedAddress.addressLines.trim().isNotEmpty)
                  ? selectedAddress.addressLines
                  : (selectedAddress != null && selectedAddress.title.trim().isNotEmpty)
                      ? selectedAddress.title
                      : CheckoutSession.instance.addressLines;
              if (addressText != null && addressText.isNotEmpty) {
                try {
                  final mapsService = GoogleMapsService();
                  final predictions =
                      await mapsService.searchPlaces(addressText);
                  if (predictions.isNotEmpty) {
                    final resolved =
                        await mapsService.resolvePlace(predictions.first.placeId);
                    if (resolved != null) {
                      activeLatitude = resolved.latitude;
                      activeLongitude = resolved.longitude;
                      locationSource = 'geocode';
                      // Cache the resolved coordinates in CheckoutSession so
                      // the next screen load doesn't need to geocode again.
                      CheckoutSession.instance.setDelivery(
                        addressLatitude: activeLatitude,
                        addressLongitude: activeLongitude,
                      );
                    }
                  }
                } catch (_) {}
              }
            }
          }
        }

        if (kDebugMode) {
          debugPrint('CATEGORY_LOCATION_DEBUG');
          debugPrint('category = ${tabParam ?? actionParam ?? "unknown"}');
          debugPrint('locationSource = $locationSource');
          debugPrint('latitude = $activeLatitude');
          debugPrint('longitude = $activeLongitude');
        }

        if (activeLatitude == null || activeLongitude == null) {
          if (isKidsOrEssentials) {
            throw const ApiException('Location is missing. Please enable device location.');
          } else {
            throw const ApiException('Location is missing. Please select a delivery address.');
          }
        }

        query['latitude'] = activeLatitude.toString();
        query['longitude'] = activeLongitude.toString();
        query['nearestOnly'] = 'true';
        apiPath = ApiConstants.productsNearbyPath;
        if ((limit ?? 0) <= 0) {
          limit = 50;
        }
      }

      if (tabParam != null && tabParam.isNotEmpty) {
        query['tab'] = tabParam;
      }
      if (page != null && page > 0) {
        query['page'] = '$page';
      }
      final finalLimit = limit;
      if (finalLimit != null && finalLimit > 0) {
        query['limit'] = '$finalLimit';
      }
      if (actionParam != null && actionParam.isNotEmpty) {
        query['action'] = actionParam;
      }
      if (ageParam != null && ageParam.isNotEmpty) {
        query['age'] = ageParam;
      }
      if (genderParam != null && genderParam.isNotEmpty) {
        query['gender'] = genderParam;
      }

      final isKidsOrEssentialsLogging = (tabParam != null && 
          (tabParam.toLowerCase() == 'kids wardrobe' || tabParam.toLowerCase() == 'essentials wardrobe')) ||
          (actionParam == 'kids');
      
      if (isKidsOrEssentialsLogging && useNearbyLocation && kDebugMode) {
        debugPrint('[NEARBY_PRODUCTS_DEBUG]');
        debugPrint('category=${query['tab'] ?? actionParam ?? 'unknown'}');
        debugPrint('latitude=${query['latitude']}');
        debugPrint('longitude=${query['longitude']}');
        debugPrint('callingApi=true');
      }

      final json = await _apiClient.get(
        apiPath,
        authToken: authToken,
        queryParameters: query.isEmpty ? null : query,
      );

      if (json['success'] != true) {
        throw ApiException(
          json['message']?.toString() ?? 'Failed to load products',
        );
      }

      if (useNearbyLocation) {
        if (kDebugMode) {
          debugPrint('[NEARBY_API_RESPONSE] status=200');
        }
        ProductCache.instance.lastNearbyMetadata = {
          'nearbyStores': json['nearbyStores'],
          'visibilityRadius': json['visibilityRadius'],
          'userLocation': json['userLocation'],
          'pagination': json['pagination'],
        };
      }

      final dataRaw = json['data'];
      final dataArray = dataRaw is List ? dataRaw : (dataRaw is Map ? (dataRaw['items'] ?? dataRaw['products'] ?? dataRaw['results'] ?? dataRaw['data'] ?? []) : []);
      final paginationInfo = json['pagination'] ?? {};

      if (useNearbyLocation && kDebugMode) {
        debugPrint('');
        debugPrint('[NEARBY_RESPONSE_DEBUG]');
        debugPrint('dataLength=${dataArray is List ? dataArray.length : 0}');
        debugPrint('totalItems=${paginationInfo['totalItems']}');
        debugPrint('totalPages=${paginationInfo['totalPages']}');
        
        final isProfessional = (tabParam != null && tabParam.toLowerCase().contains('professional')) || 
                               (actionParam != null && actionParam.toLowerCase().contains('professional'));
        
        if (isProfessional && dataArray is List) {
          debugPrint('PROFESSIONAL_PRODUCTS_DEBUG');
          debugPrint('rawResponseCount = ${dataArray.length}');
          
          final productIds = <String>[];
          final productNames = <String>[];
          final storeIds = <String>[];
          final distances = <String>[];
          final categoryNames = <String>[];
          final stockStatuses = <String>[];
          
          for (int i = 0; i < dataArray.length; i++) {
            final item = dataArray[i];
            if (item is Map) {
              final productJson = item['product'] is Map ? item['product'] : item;
              productIds.add(productJson['id']?.toString() ?? 'null');
              productNames.add(productJson['productName']?.toString() ?? 'null');
              categoryNames.add(productJson['categoryName']?.toString() ?? 'null');
              stockStatuses.add(productJson['stockStatus']?.toString() ?? 'null');
              
              storeIds.add(item['storeId']?.toString() ?? item['store_id']?.toString() ?? 'null');
              distances.add(item['distanceKm']?.toString() ?? item['distance_km']?.toString() ?? 'null');
            }
          }
          
          debugPrint('productIds = $productIds');
          debugPrint('productNames = $productNames');
          debugPrint('storeIds = $storeIds');
          debugPrint('distanceKm = $distances');
          debugPrint('categoryName = $categoryNames');
          debugPrint('stockStatus = $stockStatuses');
        } else if (dataArray is List) {
          for (int i = 0; i < dataArray.length; i++) {
            final item = dataArray[i];
            final productJson = item is Map && item['product'] is Map ? item['product'] : item;
            if (productJson is Map) {
              debugPrint('[NEARBY_PRODUCT]');
              debugPrint('index=$i');
              debugPrint('productId=${productJson['id']}');
              debugPrint('productName=${productJson['productName']}');
            }
          }
        }
      }

      final products = _parseProductList(json['data']);
      _capturePaginationMeta(
        pagination: paginationInfo,
        page: page,
        limit: limit,
        fetchedCount: products.length,
      );

      if (!hasFilters) {
        ProductCache.instance.set(products);
      } else {
        for (final product in products) {
          ProductCache.instance.upsert(product);
        }
      }
      return products;
    }();

    if (!hasFilters) {
      _inFlightProductsRequest = request;
    }
    try {
      return await request;
    } finally {
      if (!hasFilters) {
        _inFlightProductsRequest = null;
      }
    }
  }

  /// Loads Home wardrobe cards by calling each Admin tab. Empty tabs are omitted.
  Future<({List<Product> wardrobeCards, Product? essentials})>
      getHomeWardrobeSections({bool forceRefresh = true}) async {
    final results = await Future.wait(
      ProductCatalog.wardrobeApiTabs.map((tab) async {
        try {
          final isNearby = tab.toLowerCase().contains('kids') || tab.toLowerCase().contains('essentials');
          return await getProducts(
            tab: tab,
            page: 1,
            limit: 12,
            forceRefresh: forceRefresh,
            useNearbyLocation: isNearby,
          );
        } catch (e) {
          return <Product>[];
        }
      }),
    );

    final wardrobeCards = <Product>[];
    Product? essentials;
    for (var i = 0; i < ProductCatalog.wardrobeApiTabs.length; i++) {
      final tab = ProductCatalog.wardrobeApiTabs[i];
      final card = ProductCatalog.cardFromTabProducts(results[i]);
      if (card == null) continue;
      if (ProductCatalog.isEssentialsTab(tab)) {
        essentials = card;
      } else {
        wardrobeCards.add(card);
      }
    }
    return (wardrobeCards: wardrobeCards, essentials: essentials);
  }

  Future<Product> getProductById(String id) async {
    final authToken = await _authStorage.getAuthToken();
    if (authToken == null || authToken.isEmpty) {
      throw const ApiException('Not logged in. Please login again.');
    }

    final json = await _apiClient.get(
      '${ApiConstants.productsPath}/$id',
      authToken: authToken,
    );

    if (json['success'] != true) {
      throw ApiException(
        json['message']?.toString() ?? 'Failed to load product',
      );
    }

    final data = json['data'];
    if (data is! Map) {
      throw const ApiException('Invalid product response');
    }

    final product = Product.fromJson(Map<String, dynamic>.from(data));
    if (product.id.isEmpty) {
      throw const ApiException('Invalid product response');
    }

    ProductCache.instance.upsert(product);
    return product;
  }

  void _capturePaginationMeta({
    required dynamic pagination,
    required int? page,
    required int? limit,
    required int fetchedCount,
  }) {
    lastFetchedPage = page != null && page > 0 ? page : 1;
    lastRequestedLimit = limit;
    lastFetchedCount = fetchedCount;

    int? asInt(dynamic value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value.trim());
      return null;
    }

    if (pagination is Map) {
      lastTotalPages = asInt(
        pagination['totalPages'] ??
            pagination['total_pages'] ??
            pagination['pages'],
      );
      lastTotalItems = asInt(
        pagination['totalItems'] ??
            pagination['total_items'] ??
            pagination['total'] ??
            pagination['count'],
      );
    } else {
      lastTotalPages = null;
      lastTotalItems = null;
    }
  }

  static List<Product> _parseProductList(dynamic data) {
    Iterable raw = const [];
    if (data is List) {
      raw = data;
    } else if (data is Map) {
      final nested = data['items'] ??
          data['products'] ??
          data['results'] ??
          data['data'];
      if (nested is List) raw = nested;
    }

    final products = <Product>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final productJson = item['product'] is Map ? item['product'] : item;
      if (productJson is! Map) continue;
      final product =
          Product.fromJson(Map<String, dynamic>.from(productJson));
      if (product.id.isEmpty) {
        if (kDebugMode) {
          debugPrint(
            '[PRODUCT_PARSE_FILTER] reason=empty_product_id '
            'productName=${product.productName}',
          );
        }
        continue;
      }
      if (product.productName.trim().isEmpty) {
        if (kDebugMode) {
          debugPrint(
            '[PRODUCT_PARSE_FILTER] reason=empty_product_name '
            'productId=${product.id}',
          );
        }
        continue;
      }
      products.add(product);
    }
    return products;
  }
}
