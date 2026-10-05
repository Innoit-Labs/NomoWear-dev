import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nomowear/core/network/api_exception.dart';
import 'package:nomowear/core/utils/api_id_utils.dart';

import 'package:nomowear/features/cart/data/cart_repository.dart';
import 'package:nomowear/features/cart/data/models/remote_cart.dart';
import 'package:nomowear/features/cart/presentation/utils/cart_limits.dart';
import 'package:nomowear/features/cart/presentation/utils/cart_stock.dart';
import 'package:nomowear/features/checkout/data/checkout_session.dart';
import 'package:nomowear/features/checkout/data/subscription_kit_preferences.dart';
import 'package:nomowear/features/checkout/data/wardrobe_booking_session.dart';
import 'package:nomowear/features/products/data/product_cache.dart';
import 'package:nomowear/features/products/data/product_catalog.dart';
import 'package:nomowear/features/products/data/models/product_variant.dart';
import 'package:nomowear/features/products/data/product_mapper.dart';
import 'package:nomowear/features/products/data/product_repository.dart';

void _cartLog(String message) {
  if (kDebugMode) debugPrint('[CART] $message');
}

void _perf(String message) {
  if (kDebugMode) debugPrint('[CART_PERF] $message');
}

void _addUiLog(String message) {
  if (kDebugMode) debugPrint('[CART_ADD_UI] $message');
}

enum CartStatus { initial, loading, loaded, updating, error }

String _resolveItemType({
  String? itemType,
  bool? isKids,
  bool? isEssential,
  bool? isSubscriptionGarment,
}) {
  final explicit = itemType?.trim();
  if (explicit != null && explicit.isNotEmpty) return explicit;
  if (isKids == true) return 'kids';
  if (isEssential == true) return 'essentials';
  if (isSubscriptionGarment == true) return 'subscription';
  if (isSubscriptionGarment == false) return 'non_subscription';
  if (itemType != null) return itemType;
  return 'non_subscription';
}

class CartItem extends Equatable {
  CartItem({
    String? id,
    required this.productId,
    this.variantId,
    required this.title,
    required this.imageUrl,
    this.price,
    this.selectedSize = 'M',
    this.quantity = 1,
    String? itemType,
    bool? isKids,
    bool? isEssential,
    bool? isSubscriptionGarment,
    this.category,
    this.productClass,
    this.unitPrice = 0,
    this.lineTotal = 0,
    this.kitDetails,
  })  : itemType = _resolveItemType(
          itemType: itemType,
          isKids: isKids,
          isEssential: isEssential,
          isSubscriptionGarment: isSubscriptionGarment,
        ),
        id = id ??
            _lineId(
              productId,
              variantId,
              _resolveItemType(
                itemType: itemType,
                isKids: isKids,
                isEssential: isEssential,
                isSubscriptionGarment: isSubscriptionGarment,
              ),
            );

  final String id;
  final String productId;
  final String? variantId;
  final String title;
  final String imageUrl;
  final String? price;
  final String selectedSize;
  final int quantity;
  final String itemType;
  final String? category;
  final String? productClass;
  final num unitPrice;
  final num lineTotal;
  final RemoteCartKitDetails? kitDetails;

  String get productName => title;
  String? get categoryName => category;
  bool get isKids => itemType == 'kids';
  bool get isEssential => itemType == 'essentials' || itemType == 'kids';
  bool get isSubscriptionGarment => itemType == 'subscription';

  CartItem copyWith({
    String? id,
    String? selectedSize,
    int? quantity,
    bool? isSubscriptionGarment,
    bool? isKids,
    bool? isEssential,
    String? itemType,
    String? imageUrl,
    String? price,
  }) {
    final nextType = itemType ??
        (isKids == true
            ? 'kids'
            : isEssential == true
                ? 'essentials'
                : isSubscriptionGarment == true
                    ? 'subscription'
                    : isSubscriptionGarment == false
                        ? 'non_subscription'
                        : this.itemType);
    return CartItem(
      id: id ?? this.id,
      productId: productId,
      variantId: variantId,
      title: title,
      imageUrl: imageUrl ?? this.imageUrl,
      price: price ?? this.price,
      selectedSize: selectedSize ?? this.selectedSize,
      quantity: quantity ?? this.quantity,
      itemType: nextType,
      category: category,
      productClass: productClass,
      unitPrice: unitPrice,
      lineTotal: lineTotal,
      kitDetails: kitDetails,
    );
  }

  @override
  List<Object?> get props =>
      [id, productId, variantId, quantity, selectedSize, itemType];
}

String _lineId(String productId, String? variantId, String itemType) {
  final vid = variantId?.trim();
  final v = (vid == null || vid.isEmpty) ? '-' : vid;
  return '${productId.trim()}_${v}_$itemType';
}

bool _variantsCompatible(String? a, String? b) {
  final va = a?.trim() ?? '';
  final vb = b?.trim() ?? '';
  if (va.isEmpty && vb.isEmpty) return true;
  return va == vb;
}

abstract class CartEvent extends Equatable {
  @override
  List<Object?> get props => [];
}

class LoadCartEvent extends CartEvent {
  LoadCartEvent({this.forceRefresh = false, this.source = 'unknown'});
  final bool forceRefresh;
  final String source;
  @override
  List<Object?> get props => [forceRefresh, source];
}

class AddToCartEvent extends CartEvent {
  AddToCartEvent(this.item);
  final CartItem item;
  @override
  List<Object?> get props => [item];
}

class RemoveFromCartEvent extends CartEvent {
  RemoveFromCartEvent(this.itemId);
  final String itemId;
  @override
  List<Object?> get props => [itemId];
}

class UpdateCartItemSizeEvent extends CartEvent {
  UpdateCartItemSizeEvent(this.itemId, this.size);
  final String itemId;
  final String size;
  @override
  List<Object?> get props => [itemId, size];
}

class UpdateCartItemVariantEvent extends CartEvent {
  UpdateCartItemVariantEvent(this.itemId, this.newVariant);
  final String itemId;
  final ProductVariant newVariant;
  @override
  List<Object?> get props => [itemId, newVariant];
}

class UpdateCartItemQuantityEvent extends CartEvent {
  UpdateCartItemQuantityEvent(this.itemId, this.quantity);
  final String itemId;
  final int quantity;
  @override
  List<Object?> get props => [itemId, quantity];
}

class AdjustCartItemQuantityEvent extends CartEvent {
  AdjustCartItemQuantityEvent(this.itemId, {required this.delta});
  final String itemId;
  final int delta;
  @override
  List<Object?> get props => [itemId, delta];
}

class ClearCartEvent extends CartEvent {}

class ClearLocalCartEvent extends CartEvent {}

class ClearPaidRentalItemsEvent extends CartEvent {}

class SetWardrobeKitDaysEvent extends CartEvent {
  SetWardrobeKitDaysEvent(this.kitDays);
  final int kitDays;
  @override
  List<Object?> get props => [kitDays];
}

class SetWardrobeKitEvent extends CartEvent {
  SetWardrobeKitEvent({
    required this.kitId,
    this.wardrobeKitProductId,
    this.wardrobeKitVariantId,
    required this.kitDays,
    required this.kitName,
    required this.maxGarments,
    this.kitPrice,
    this.wardrobeCategory,
    this.wardrobeCategoryId,
  });
  final String kitId;
  final String? wardrobeKitProductId;
  final String? wardrobeKitVariantId;
  final int kitDays;
  final String kitName;
  final int maxGarments;
  final String? kitPrice;
  final String? wardrobeCategory;
  final String? wardrobeCategoryId;
}

class LockWardrobeCategoryEvent extends CartEvent {
  LockWardrobeCategoryEvent({
    required this.wardrobeCategory,
    this.wardrobeCategoryId,
  });
  final String wardrobeCategory;
  final String? wardrobeCategoryId;
}

class CartState extends Equatable {
  const CartState({
    this.status = CartStatus.initial,
    this.items = const [],
    this.remote = const RemoteCart(id: '', items: []),
    this.errorMessage,
    this.wardrobeKitDays = 1,
    this.wardrobeKitId,
    this.wardrobeKitProductId,
    this.wardrobeKitVariantId,
    this.wardrobeKitName = '',
    this.wardrobeKitMaxGarments = 0,
    this.wardrobeKitPrice,
    this.wardrobeCategory,
    this.wardrobeCategoryId,
    this.pendingLineIds = const {},
    this.outOfStockLineIds = const {},
  });

  final CartStatus status;
  final List<CartItem> items;
  final RemoteCart remote;
  final String? errorMessage;
  final int wardrobeKitDays;
  final String? wardrobeKitId;
  final String? wardrobeKitProductId;
  final String? wardrobeKitVariantId;
  final String wardrobeKitName;
  final int wardrobeKitMaxGarments;
  final String? wardrobeKitPrice;
  final String? wardrobeCategory;
  final String? wardrobeCategoryId;
  final Set<String> pendingLineIds;
  final Set<String> outOfStockLineIds;

  int get apiItemCount => remote.itemCount;
  int get totalItems => items.fold<int>(0, (sum, item) => sum + item.quantity);

  List<CartItem> get subscriptionGarmentItems =>
      items.where((e) => e.itemType == 'subscription').toList();
  List<CartItem> get paidRentalGarmentItems =>
      items.where((e) => e.itemType == 'non_subscription').toList();
  List<CartItem> get essentialsOnlyItems =>
      items.where((e) => e.itemType == 'essentials').toList();
  List<CartItem> get kidsItems =>
      items.where((e) => e.itemType == 'kids').toList();
  List<CartItem> get wardrobeItems => items
      .where((e) =>
          e.itemType == 'subscription' || e.itemType == 'non_subscription')
      .toList();
  List<CartItem> get essentialItems => items
      .where((e) => e.itemType == 'essentials' || e.itemType == 'kids')
      .toList();
  List<CartItem> get purchaseItems => essentialItems;
  List<CartItem> get groupedEssentialItems => essentialsOnlyItems;

  bool get hasMixedWardrobeTypes =>
      subscriptionGarmentItems.isNotEmpty && paidRentalGarmentItems.isNotEmpty;
  bool get hasSubscriptionGarments => subscriptionGarmentItems.isNotEmpty;
  bool get hasPaidRentalGarments => paidRentalGarmentItems.isNotEmpty;

  int get subscriptionGarmentCount => subscriptionGarmentItems.fold<int>(
        0,
        (sum, item) => sum + item.quantity,
      );
  int get paidRentalGarmentCount => paidRentalGarmentItems.fold<int>(
        0,
        (sum, item) => sum + item.quantity,
      );
  int get wardrobeGarmentCount => wardrobeItems.fold<int>(
        0,
        (sum, item) => sum + item.quantity,
      );

  int get currentBookingSelectedGarments => subscriptionGarmentCount;
  int get currentKitLimit {
    if (wardrobeKitMaxGarments > 0) return wardrobeKitMaxGarments;
    final sessionLimit = WardrobeBookingSession.instance.kitGarmentLimit;
    if (sessionLimit > 0) return sessionLimit;
    final prefLimit = SubscriptionKitPreferences.instance.wardrobeKitMaxGarments;
    if (prefLimit > 0) return prefLimit;
    return maxWardrobeGarments;
  }

  int get currentBookingRemaining {
    final remaining = currentKitLimit - currentBookingSelectedGarments;
    return remaining < 0 ? 0 : remaining;
  }

  bool get shouldGroupEssentialsUnderWardrobe => false;

  int get maxWardrobeGarments {
    if (wardrobeKitMaxGarments > 0) return wardrobeKitMaxGarments;
    final sessionLimit = WardrobeBookingSession.instance.kitGarmentLimit;
    if (sessionLimit > 0) return sessionLimit;
    final prefLimit = SubscriptionKitPreferences.instance.wardrobeKitMaxGarments;
    if (prefLimit > 0) return prefLimit;
    final days = wardrobeKitDays > 0
        ? wardrobeKitDays
        : SubscriptionKitPreferences.instance.wardrobeKitDays;
    if (days == 1) return 4;
    if (days == 3) return 7;
    if (days == 7) return 10;
    if (days > 0) return 4;
    if (wardrobeItems.isNotEmpty ||
        WardrobeBookingSession.instance.kitSelected ||
        SubscriptionKitPreferences.instance.isKitConfigured) {
      return 4;
    }
    return 0;
  }

  String get wardrobeKitTitle => wardrobeKitName.isNotEmpty &&
          wardrobeKitName.toLowerCase() != 'custom' &&
          wardrobeKitName.toLowerCase() != 'standard'
      ? wardrobeKitName
      : '$wardrobeKitDays Day wardrobe kit';

  bool get isEmpty => items.isEmpty;
  bool get isConfirmedEmpty =>
      (status == CartStatus.loaded || status == CartStatus.updating) &&
      items.isEmpty;
  bool get isSyncing =>
      status == CartStatus.loading || status == CartStatus.updating;
  bool get hasLoadedRemote =>
      status == CartStatus.loaded ||
      status == CartStatus.updating ||
      status == CartStatus.error;
  bool get showLoading =>
      status == CartStatus.initial ||
      (status == CartStatus.loading && items.isEmpty);

  bool isLinePending(String lineId) => pendingLineIds.contains(lineId);

  bool isProductPending({
    String? productId,
    String? variantId,
    String? itemType,
  }) {
    final pid = productId?.trim() ?? '';
    if (pid.isEmpty) return false;
    final type =
        (itemType == null || itemType.isEmpty) ? 'non_subscription' : itemType;
    if (pendingLineIds.contains(_lineId(pid, variantId, type))) return true;
    if (pendingLineIds.contains(_lineId(pid, null, type))) return true;
    final prefix = '${pid}_';
    for (final key in pendingLineIds) {
      if (key.startsWith(prefix)) return true;
    }
    return false;
  }

  bool isVariantOutOfStock({
    String? productId,
    String? variantId,
    String? itemType,
  }) {
    final pid = productId?.trim() ?? '';
    if (pid.isEmpty) return false;
    final type =
        (itemType == null || itemType.isEmpty) ? 'non_subscription' : itemType;
    return outOfStockLineIds.contains(_lineId(pid, variantId, type));
  }

  int quantityForListingCard({
    String? productId,
    String? variantId,
    String? itemType,
  }) {
    final exact = quantityForProduct(
      productId,
      variantId: variantId,
      itemType: itemType,
    );
    if (exact > 0) return exact;
    return quantityForProduct(productId, variantId: variantId);
  }

  CartItem? lineForListingCard({
    String? productId,
    String? variantId,
    String? itemType,
  }) {
    return lineForProduct(
          productId,
          variantId: variantId,
          itemType: itemType,
        ) ??
        lineForProduct(
          productId,
          variantId: variantId,
        );
  }

  CartItem? lineForProduct(
    String? productId, {
    String? variantId,
    String? itemType,
    bool? isEssential,
    bool? isSubscriptionGarment,
  }) {
    final pid = productId?.trim() ?? '';
    if (pid.isEmpty) return null;
    final vid = variantId?.trim();
    String? type = itemType;
    if (type == null) {
      if (isSubscriptionGarment == true) type = 'subscription';
      if (isEssential == true) type = 'essentials';
      if (isSubscriptionGarment == false && isEssential == false) {
        type = 'non_subscription';
      }
    }
    CartItem? fallback;
    for (final item in items) {
      if (item.productId.trim() != pid) continue;
      if (vid != null &&
          vid.isNotEmpty &&
          !_variantsCompatible(item.variantId, vid) &&
          item.id != '${pid}_$vid') {
        continue;
      }
      if (type != null && item.itemType != type) continue;
      if (vid != null &&
          vid.isNotEmpty &&
          (_variantsCompatible(item.variantId, vid) ||
              item.id == '${pid}_$vid')) {
        return item;
      }
      fallback ??= item;
    }
    return fallback;
  }

  int quantityForProduct(
    String? productId, {
    String? variantId,
    String? itemType,
  }) {
    final pid = productId?.trim() ?? '';
    if (pid.isEmpty) return 0;
    final vid = variantId?.trim();
    return items.where((item) {
      if (item.productId.trim() != pid) return false;
      if (itemType != null && item.itemType != itemType) return false;
      if (vid == null || vid.isEmpty) return true;
      return _variantsCompatible(item.variantId, vid) ||
          item.id == '${pid}_$vid';
    }).fold<int>(0, (sum, item) => sum + item.quantity);
  }

  CartState copyWith({
    CartStatus? status,
    List<CartItem>? items,
    RemoteCart? remote,
    String? errorMessage,
    int? wardrobeKitDays,
    String? wardrobeKitId,
    String? wardrobeKitProductId,
    String? wardrobeKitVariantId,
    String? wardrobeKitName,
    int? wardrobeKitMaxGarments,
    String? wardrobeKitPrice,
    String? wardrobeCategory,
    String? wardrobeCategoryId,
    Set<String>? pendingLineIds,
    Set<String>? outOfStockLineIds,
    bool clearWardrobeKit = false,
    bool clearError = false,
  }) {
    return CartState(
      status: status ?? this.status,
      items: items ?? this.items,
      remote: remote ?? this.remote,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      wardrobeKitDays: wardrobeKitDays ?? this.wardrobeKitDays,
      wardrobeKitId:
          clearWardrobeKit ? null : wardrobeKitId ?? this.wardrobeKitId,
      wardrobeKitProductId: clearWardrobeKit
          ? null
          : wardrobeKitProductId ?? this.wardrobeKitProductId,
      wardrobeKitVariantId: clearWardrobeKit
          ? null
          : wardrobeKitVariantId ?? this.wardrobeKitVariantId,
      wardrobeKitName:
          clearWardrobeKit ? '' : wardrobeKitName ?? this.wardrobeKitName,
      wardrobeKitMaxGarments: clearWardrobeKit
          ? 0
          : wardrobeKitMaxGarments ?? this.wardrobeKitMaxGarments,
      wardrobeKitPrice: clearWardrobeKit
          ? null
          : wardrobeKitPrice ?? this.wardrobeKitPrice,
      wardrobeCategory: wardrobeCategory ?? this.wardrobeCategory,
      wardrobeCategoryId: wardrobeCategoryId ?? this.wardrobeCategoryId,
      pendingLineIds: pendingLineIds ?? this.pendingLineIds,
      outOfStockLineIds: outOfStockLineIds ?? this.outOfStockLineIds,
    );
  }

  @override
  List<Object?> get props => [
        status,
        items,
        remote.itemCount,
        remote.id,
        errorMessage,
        wardrobeKitId,
        wardrobeKitProductId,
        wardrobeKitVariantId,
        wardrobeKitDays,
        wardrobeCategory,
        pendingLineIds.join(','),
        outOfStockLineIds.join(','),
      ];
}

class CartBloc extends Bloc<CartEvent, CartState> {
  CartBloc({CartRepository? repository})
      : _repository = repository ?? CartRepository(),
        super(const CartState()) {
    on<LoadCartEvent>(_onLoad);
    on<AddToCartEvent>(_onAdd);
    on<RemoveFromCartEvent>(_onRemove);
    on<UpdateCartItemSizeEvent>(_onSize);
    on<UpdateCartItemVariantEvent>(_onUpdateVariant);
    on<UpdateCartItemQuantityEvent>(_onQty);
    on<AdjustCartItemQuantityEvent>(_onAdjust);
    on<ClearCartEvent>(_onClear);
    on<ClearLocalCartEvent>(_onClearLocal);
    on<ClearPaidRentalItemsEvent>(_onClearPaid);
    on<SetWardrobeKitDaysEvent>((event, emit) {
      emit(state.copyWith(wardrobeKitDays: event.kitDays));
    });
    on<SetWardrobeKitEvent>((event, emit) {
      emit(state.copyWith(
        wardrobeKitId: event.kitId,
        wardrobeKitProductId: event.wardrobeKitProductId,
        wardrobeKitVariantId: event.wardrobeKitVariantId,
        wardrobeKitDays: event.kitDays,
        wardrobeKitName: event.kitName,
        wardrobeKitMaxGarments: event.maxGarments,
        wardrobeKitPrice: event.kitPrice,
        wardrobeCategory: event.wardrobeCategory,
        wardrobeCategoryId: event.wardrobeCategoryId,
      ));
    });
    on<LockWardrobeCategoryEvent>((event, emit) {
      final category = event.wardrobeCategory.trim();
      if (category.isEmpty) return;
      emit(state.copyWith(
        wardrobeCategory: category,
        wardrobeCategoryId: event.wardrobeCategoryId,
      ));
    });
  }

  final CartRepository _repository;
  Future<void> _ops = Future.value();
  /// Bumped at the *start* of every cart write/GET that may apply remote state.
  /// Completing ops with an older id must not overwrite newer results.
  int _writeGeneration = 0;
  int _latestApplyId = 0;
  final Map<String, Future<void>> _lineOps = {};
  final Set<String> _inflightLines = {};
  final Set<String> _qtyFlushing = {};
  final Map<String, int> _desiredQty = {};
  final Map<String, int> _serverQty = {};
  final Map<String, CartItem> _lastKnownItems = {};
  final List<Completer<RemoteCart>> _refreshWaiters = [];

  bool _isKitItemType(String type) =>
      type == 'subscription' || type == 'non_subscription';

  Future<void> _enqueueWrite(
    String lineKey,
    String itemType,
    Future<void> Function() action,
  ) async {
    // Wardrobe kit POSTs rewrite the whole kit — must be global, not per-line,
    // or parallel removes race and a slower response resurrects deleted items.
    if (_isKitItemType(itemType)) {
      await _enqueue(action);
    } else {
      await _enqueueLine(lineKey, action);
    }
  }

  Future<void> _enqueue(Future<void> Function() action) async {
    final previous = _ops;
    final gate = Completer<void>();
    _ops = gate.future;
    await previous;
    try {
      await action();
    } finally {
      if (!gate.isCompleted) gate.complete();
    }
  }

  Future<void> _enqueueLine(String key, Future<void> Function() action) async {
    final previous = _lineOps[key] ?? Future.value();
    final gate = Completer<void>();
    _lineOps[key] = gate.future;
    await previous;
    try {
      await action();
    } finally {
      if (!gate.isCompleted) gate.complete();
      if (identical(_lineOps[key], gate.future)) {
        _lineOps.remove(key);
      }
    }
  }

  Set<String> _pendingPlus(String lineId) => {...state.pendingLineIds, lineId};

  Set<String> _pendingMinus(String lineId) {
    final next = {...state.pendingLineIds}..remove(lineId);
    return next;
  }

  void _emitClearPending(
    Emitter<CartState> emit,
    String lineId,
    String source,
  ) {
    if (emit.isDone) {
      _addUiLog('CLEAR LOADING skipped emit.done productKey=$lineId');
      return;
    }
    if (!state.pendingLineIds.contains(lineId)) {
      _addUiLog('CLEAR LOADING already-clear productKey=$lineId');
      return;
    }
    final remainingPending = _pendingMinus(lineId);
    _emitLogged(
      emit,
      state.copyWith(
        status: remainingPending.isEmpty ? CartStatus.loaded : CartStatus.updating,
        pendingLineIds: remainingPending,
      ),
      source,
    );
  }

  void _completeRefreshWaiters(RemoteCart remote, [Object? error, StackTrace? st]) {
    final waiters = List<Completer<RemoteCart>>.from(_refreshWaiters);
    _refreshWaiters.clear();
    for (final waiter in waiters) {
      if (waiter.isCompleted) continue;
      if (error != null) {
        waiter.completeError(error, st);
      } else {
        waiter.complete(remote);
      }
    }
  }

  Future<RemoteCart> refresh({required String source}) {
    final completer = Completer<RemoteCart>();
    _refreshWaiters.add(completer);
    add(LoadCartEvent(forceRefresh: true, source: source));
    return completer.future;
  }

  void _emitLogged(Emitter<CartState> emit, CartState next, String source) {
    _cartLog(
      'CART_STATE status=${next.status.name} source=$source '
      'subscription=${next.subscriptionGarmentCount} '
      'non_subscription=${next.paidRentalGarmentCount} '
      'essentials=${next.essentialsOnlyItems.fold<int>(0, (n, e) => n + e.quantity)} '
      'kids=${next.kidsItems.fold<int>(0, (n, e) => n + e.quantity)} '
      'total=${next.totalItems}',
    );
    emit(next);
  }

  Future<RemoteCart> _applyRemote(
    Emitter<CartState> emit, {
    required RemoteCart remote,
    required String source,
    int? expectedApplyId,
    String? clearLineId,
  }) async {
    if (expectedApplyId != null && expectedApplyId != _writeGeneration) {
      _perf(
        'SKIP STALE APPLY expected=$expectedApplyId current=$_writeGeneration source=$source',
      );
      return state.remote;
    }
    final mapped = _mapRemote(remote);
    final kit = _kitFrom(remote);
    final pending = clearLineId == null
        ? state.pendingLineIds
        : ({...state.pendingLineIds}..remove(clearLineId));
    final outOfStock = clearLineId == null
        ? state.outOfStockLineIds
        : ({...state.outOfStockLineIds}..remove(clearLineId));
    if (clearLineId != null) {
      _addUiLog('CLEAR LOADING productKey=$clearLineId source=$source');
    }
    final stateSw = Stopwatch()..start();
    final resolvedMaxGarments = state.wardrobeKitMaxGarments > 0
        ? state.wardrobeKitMaxGarments
        : (WardrobeBookingSession.instance.kitGarmentLimit > 0
            ? WardrobeBookingSession.instance.kitGarmentLimit
            : SubscriptionKitPreferences.instance.wardrobeKitMaxGarments);

    // Keep latest remote qty per line id (never sum — duplicates are API noise).
    final preservedItems = <CartItem>[];
    final existingItems = state.items;
    final newItemsMap = <String, CartItem>{};
    for (final item in mapped) {
      newItemsMap[item.id] = item;
    }
    for (final existing in existingItems) {
      if (newItemsMap.containsKey(existing.id)) {
        preservedItems.add(newItemsMap[existing.id]!);
        newItemsMap.remove(existing.id);
      }
    }
    preservedItems.addAll(newItemsMap.values);

    final nextState = state.copyWith(
      status: CartStatus.loaded,
      items: preservedItems,
      remote: remote,
      clearError: true,
      wardrobeKitId: kit.kitId ?? state.wardrobeKitId,
      wardrobeKitProductId: kit.productId ?? state.wardrobeKitProductId,
      wardrobeKitVariantId: kit.variantId ?? state.wardrobeKitVariantId,
      wardrobeKitDays: kit.days ?? state.wardrobeKitDays,
      wardrobeKitName: kit.name ?? state.wardrobeKitName,
      wardrobeKitMaxGarments:
          resolvedMaxGarments > 0 ? resolvedMaxGarments : null,
      pendingLineIds: pending,
      outOfStockLineIds: outOfStock,
    );
    _emitLogged(emit, nextState, source);
    stateSw.stop();
    _perf(
      'STATE UPDATE duration=${stateSw.elapsedMilliseconds}ms source=$source',
    );
    
    // Clear stale Kids/Essentials session state if their cart items were removed
    if (CheckoutSession.instance.bookingMode == CheckoutBookingMode.essentials) {
      if (nextState.essentialsOnlyItems.isEmpty && nextState.kidsItems.isEmpty) {
        _cartLog('CLEARING stale Essentials/Kids bookingMode because cart section is empty');
        CheckoutSession.instance.clearEssentialsBookingMode();
      }
    }

    // Reset booking mode selection if cart transitions from having items to empty
    if (state.items.isNotEmpty && remote.items.isEmpty) {
      _cartLog('Cart transitioned from items -> zero items. Resetting booking mode selection.');
      CheckoutSession.instance.clearBookingModeSelection();
      WardrobeBookingSession.instance.startNewBooking();
    }

    _completeRefreshWaiters(remote);
    return remote;
  }

  Future<RemoteCart> _getAuthoritative(
    Emitter<CartState> emit, {
    required String source,
    int? applyId,
    String? clearLineId,
    bool apply = true,
  }) async {
    final expected = applyId ?? ++_writeGeneration;
    _latestApplyId = expected;
    final requestId = _repository.nextRequestId();
    _perf('GET START requestId=$requestId source=$source');
    _addUiLog('GET START productKey=${clearLineId ?? '-'}');
    _cartLog('CART_API GET START requestId=$requestId source=$source');
    final remote = await _repository.getCart(
      requestId: requestId,
      source: source,
    );
    _addUiLog('GET COMPLETE productKey=${clearLineId ?? '-'}');
    if (!apply) return remote;
    return _applyRemote(
      emit,
      remote: remote,
      source: 'GET response $requestId',
      expectedApplyId: expected,
      clearLineId: clearLineId,
    );
  }

  /// Backend cart responses often include historical wardrobe-kit snapshots.
  /// After a kit write, trust the POST selectedItems (including []) over GET noise.
  /// After a product-level quantity:0 remove, drop that exact line from remote.
  RemoteCart _reconcileRemoteWithKitWrite(
    RemoteCart remote,
    CartWriteRequest request,
  ) {
    // Product-level remove: strip this exact product/variant/type so historical
    // kit rows in GET cannot resurrect a deleted line.
    if (request.kitDetails == null && request.quantity <= 0) {
      final vid = request.variantId?.trim() ?? '';
      final filtered = remote.items.where((i) {
        if (i.productId.trim() != request.productId.trim()) return true;
        if (request.itemType.isNotEmpty &&
            i.itemType.isNotEmpty &&
            i.itemType != request.itemType) {
          return true;
        }
        final itemVid = i.variantId?.trim() ?? '';
        if (vid.isEmpty && itemVid.isEmpty) return false;
        if (vid.isNotEmpty && itemVid == vid) return false;
        // No variant on the write — remove all variants of this product+type.
        if (vid.isEmpty) return false;
        return true;
      }).toList();
      if (filtered.length != remote.items.length) {
        _perf(
          'PRODUCT RECONCILE remove productId=${request.productId} '
          'variantId=${request.variantId ?? '-'} '
          'dropped=${remote.items.length - filtered.length}',
        );
        return _remoteWithItems(remote, filtered);
      }
      return remote;
    }

    if (request.kitDetails == null) return remote;
    final type = request.itemType.trim();
    if (type != 'subscription' && type != 'non_subscription') return remote;

    final rawSelected = request.kitDetails!['selectedItems'];
    final postedIds = <String>{};
    if (rawSelected is List) {
      for (final row in rawSelected) {
        if (row is! Map) continue;
        final id = (row['productId'] ?? row['product_id'])?.toString().trim();
        if (id != null && id.isNotEmpty) postedIds.add(id);
      }
    }

    final others = remote.items.where((i) => i.itemType != type).toList();

    // Clear kit: drop every wardrobe garment of this section even if GET still
    // echoes older kit rows.
    if (request.quantity <= 0 || postedIds.isEmpty) {
      _perf(
        'KIT RECONCILE clear type=$type dropped='
        '${remote.items.length - others.length}',
      );
      return _remoteWithItems(remote, others);
    }

    // Strip resurrected garments that were not in this POST's selectedItems.
    // (Backend often returns historical kit snapshots with old products.)
    final kept = remote.items
        .where((i) => i.itemType == type && postedIds.contains(i.productId))
        .toList();
    final merged = [...others, ...kept];
    final before = remote.items.where((i) => i.itemType == type).length;
    if (kept.length != before) {
      _perf(
        'KIT RECONCILE strip type=$type posted=${postedIds.length} '
        'before=$before after=${kept.length}',
      );
      return _remoteWithItems(remote, merged);
    }
    return remote;
  }

  RemoteCart _remoteWithItems(RemoteCart remote, List<RemoteCartItem> items) {
    final computedSubtotal = items.fold<num>(
      0,
      (s, i) => s + (i.unitPrice > 0 ? (i.unitPrice * i.quantity) : i.lineTotal),
    );
    final effectiveSubtotal = computedSubtotal > 0 ? computedSubtotal : remote.subtotal;
    final effectiveTotal = effectiveSubtotal +
        remote.deliveryCharge +
        remote.taxAmount -
        remote.discountAmount;
    return RemoteCart(
      id: remote.id,
      items: items,
      customerAddressId: remote.customerAddressId,
      subtotal: effectiveSubtotal,
      deliveryCharge: remote.deliveryCharge,
      discountAmount: remote.discountAmount,
      taxAmount: remote.taxAmount,
      totalAmount: effectiveTotal > 0 ? effectiveTotal : remote.totalAmount,
      itemCount: items.fold<int>(0, (s, i) => s + i.quantity),
      cartStatus: remote.cartStatus,
      updatedAt: remote.updatedAt,
      subscriptionCount: items
          .where((i) => i.itemType == 'subscription')
          .fold<int>(0, (s, i) => s + i.quantity),
      nonSubscriptionCount: items
          .where((i) => i.itemType == 'non_subscription')
          .fold<int>(0, (s, i) => s + i.quantity),
      essentialsCount: items
          .where((i) => i.itemType == 'essentials')
          .fold<int>(0, (s, i) => s + i.quantity),
      kidsCount: items
          .where((i) => i.itemType == 'kids')
          .fold<int>(0, (s, i) => s + i.quantity),
      activeKitPrice: remote.activeKitPrice,
      securityDepositAmount: remote.securityDepositAmount,
    );
  }

  Future<RemoteCart> _writeThenGet(
    Emitter<CartState> emit, {
    required CartWriteRequest request,
    required String source,
    String? postedType,
    String? productName,
    String? lineId,
  }) async {
    // Capture generation *before* the network call so a slower older write
    // cannot apply after a newer empty/remove response.
    final writeId = ++_writeGeneration;
    _latestApplyId = writeId;
    _perf('REQUEST START source=$source productId=${request.productId} writeId=$writeId');
    final postId = _repository.nextRequestId();
    final result = await _repository.upsert(
      request: request,
      requestId: postId,
      source: source,
    );
    _perf(
      'REQUEST END duration=${result.durationMs}ms source=$source writeId=$writeId',
    );
    _addUiLog('POST COMPLETE productKey=${lineId ?? request.productId}');

    if (writeId != _writeGeneration) {
      _perf(
        'SKIP STALE WRITE RESULT writeId=$writeId current=$_writeGeneration source=$source',
      );
      if (lineId != null) {
        _emitClearPending(emit, lineId, '$source.staleSkip');
      }
      return state.remote;
    }

    // Fast-path: clear pending loader immediately upon successful write
    if (lineId != null && source == 'UpdateQuantity') {
      _emitClearPending(emit, lineId, '$source.postImmediateDone');
    }

    late final RemoteCart remote;
    // Incomplete authoritative payloads (empty after a write that should keep
    // items) force a GET so Product/Cart screens don't desync.
    final postLooksIncomplete = request.quantity > 0 &&
        result.remote.items.isEmpty &&
        state.items.isNotEmpty;

    // Fast-path for quantity updates: if POST succeeded, avoid blocking UI on a slow GET.
    // Reconcile locally and fire GET in background without holding any spinner.
    final isQtyUpdate = source == 'UpdateQuantity';
    if (isQtyUpdate && !result.isAuthoritative && state.items.isNotEmpty) {
      _perf('GET DEFERRED reason=POST_INCOMPLETE_QTY source=$source');
      final updatedRemoteItems = state.remote.items.map((i) {
        final matches = i.productId == request.productId &&
            _variantsCompatible(i.variantId, request.variantId);
        if (matches) {
          final unit = i.unitPrice > 0
              ? i.unitPrice
              : (i.lineTotal / (i.quantity > 0 ? i.quantity : 1));
          return RemoteCartItem(
            productId: i.productId,
            productName: i.productName,
            variantId: i.variantId,
            imageUrl: i.imageUrl,
            categoryName: i.categoryName,
            productClass: i.productClass,
            itemType: i.itemType,
            quantity: request.quantity,
            unitPrice: unit,
            lineTotal: unit * request.quantity,
            size: i.size,
            kitDetails: i.kitDetails,
          );
        }
        return i;
      }).toList();
      remote = await _applyRemote(
        emit,
        remote: _remoteWithItems(state.remote, updatedRemoteItems),
        source: '$source.reconciledFast',
        expectedApplyId: writeId,
        clearLineId: lineId,
      );
      // Run authoritative GET in background silently without blocking the UI or setting any pending line
      _enqueue(() async {
        try {
          await _getAuthoritative(
            emit,
            source: '$source.backgroundSync',
            applyId: writeId,
            clearLineId: null,
            apply: true,
          );
        } catch (_) {}
      });
      return remote;
    }

    // Prefer the POST cart when it already includes lines. Only force a follow-up
    // GET when POST is incomplete/non-authoritative (avoids ~2x latency on add).
    final usePostCart = result.isAuthoritative && !postLooksIncomplete;
    if (usePostCart) {
      _perf(
        'GET SKIPPED reason=POST_AUTHORITATIVE source=$source '
        'kit=${request.kitDetails != null}',
      );
      _addUiLog(
        'GET COMPLETE productKey=${lineId ?? request.productId} skipped=true',
      );
      remote = await _applyRemote(
        emit,
        remote: _reconcileRemoteWithKitWrite(result.remote, request),
        source: '$source.postCart',
        expectedApplyId: writeId,
        clearLineId: lineId,
      );
    } else {
      if (postLooksIncomplete) {
        _perf('GET FORCED reason=POST_INCOMPLETE source=$source');
      } else {
        _perf('GET FORCED reason=POST_NOT_AUTHORITATIVE source=$source');
      }
      final fetched = await _getAuthoritative(
        emit,
        source: '$source.afterPost',
        applyId: writeId,
        clearLineId: lineId,
        // Defer apply so we can reconcile kit write intent first.
        apply: false,
      );
      if (writeId != _writeGeneration) {
        _perf(
          'SKIP STALE WRITE AFTER GET writeId=$writeId current=$_writeGeneration source=$source',
        );
        if (lineId != null) {
          _emitClearPending(emit, lineId, '$source.staleSkipAfterGet');
        }
        return state.remote;
      }
      remote = await _applyRemote(
        emit,
        remote: _reconcileRemoteWithKitWrite(fetched, request),
        source: '$source.afterPost.reconciled',
        expectedApplyId: writeId,
        clearLineId: lineId,
      );
    }

    final matched = remote.items.any((item) =>
        item.productId == request.productId &&
        _variantsCompatible(item.variantId, request.variantId));
    _addUiLog(
      'CART MATCH productKey=${lineId ?? request.productId} $matched',
    );

    if (postedType != null && request.quantity > 0) {
      if (usePostCart) {
        _cartLog(
          'TYPE CHECK product=${productName ?? request.productId} '
          'POST=$postedType GET=SKIPPED reason=POST_AUTHORITATIVE '
          'status=NOT_APPLICABLE',
        );
        return remote;
      }
      RemoteCartItem? found;
      for (final item in remote.items) {
        if (item.productId == request.productId &&
            (request.variantId == null ||
                (item.variantId ?? '') == (request.variantId ?? ''))) {
          found = item;
          if (item.itemType == postedType) break;
        }
      }
      final got = found?.itemType ?? '-';
      if (postedType != got) {
        _cartLog(
          'BACKEND TYPE MISMATCH product=${productName ?? request.productId} '
          'POST=$postedType GET=$got — Flutter will not rewrite GET',
        );
      } else {
        _cartLog(
          'TYPE CHECK product=${productName ?? request.productId} '
          'POST=$postedType GET=$got status=MATCH',
        );
      }
    }
    return remote;
  }

  ({String? kitId, String? productId, String? variantId, int? days, String? name}) _kitFrom(
    RemoteCart remote,
  ) {
    for (final item in remote.items) {
      final kit = item.kitDetails;
      if (kit == null) continue;
      return (
        kitId: kit.wardrobeKitId,
        productId: kit.wardrobeKitProductId,
        variantId: kit.wardrobeKitVariantId,
        days: kit.durationDays,
        name: kit.kitType,
      );
    }
    return (kitId: null, productId: null, variantId: null, days: null, name: null);
  }

  List<CartItem> _mapRemote(RemoteCart remote) {
    final result = <CartItem>[];
    for (final item in remote.items) {
      if (item.quantity <= 0) continue;
      final type = item.itemType;
      if (type.isEmpty) {
        _cartLog(
          'GET item missing item_type productId=${item.productId} '
          'name=${item.productName}',
        );
      }
      String image = (item.imageUrl != null && item.imageUrl!.isNotEmpty)
          ? item.imageUrl!
          : '';
      if (image.isEmpty) {
        final local = state.items.where((e) =>
            e.productId == item.productId &&
            _variantsCompatible(e.variantId, item.variantId)).firstOrNull;
        if (local != null && local.imageUrl.isNotEmpty) {
          image = local.imageUrl;
        } else {
          final cached = ProductCache.instance.findById(item.productId);
          if (cached != null) {
            ProductVariant? v;
            if (item.variantId != null) {
              v = cached.variants.where((vr) => vr.id == item.variantId).firstOrNull;
            }
            image = v?.primaryImageUrl ??
                cached.primaryImageUrl ??
                (cached.imageUrls.isNotEmpty ? cached.imageUrls.first : '');
          }
        }
      }
      final isSub = type == 'subscription';
      final effectiveUnitPrice = isSub ? 0 : item.unitPrice;
      final price = effectiveUnitPrice > 0
          ? '₹ ${effectiveUnitPrice.round()}'
          : null;
      final cartItem = CartItem(
        productId: item.productId,
        variantId: item.variantId,
        title: item.productName,
        imageUrl: image,
        price: price,
        selectedSize: item.size ?? 'M',
        quantity: item.quantity,
        itemType: type,
        category: item.categoryName,
        productClass: item.productClass,
        unitPrice: item.unitPrice,
        lineTotal: item.lineTotal,
        kitDetails: item.kitDetails,
      );

      final existingIndex = result.indexWhere((r) => r.id == cartItem.id);
      if (existingIndex >= 0) {
        // Prefer the later remote row's quantity (matches _deduplicateItems).
        result[existingIndex] = cartItem;
      } else {
        result.add(cartItem);
      }
    }
    return result;
  }

  Future<void> _onLoad(LoadCartEvent event, Emitter<CartState> emit) async {
    await _enqueue(() async {
      if (!event.forceRefresh &&
          (state.status == CartStatus.loading ||
              state.status == CartStatus.loaded ||
              state.status == CartStatus.updating)) {
        _cartLog('GET skipped already-loaded source=${event.source}');
        return;
      }
      if (state.items.isEmpty) {
        _emitLogged(
          emit,
          state.copyWith(status: CartStatus.loading),
          'GET loading ${event.source}',
        );
      } else {
        _emitLogged(
          emit,
          state.copyWith(status: CartStatus.updating),
          'GET updating ${event.source}',
        );
      }
      try {
        await _getAuthoritative(emit, source: event.source);
      } catch (e, st) {
        _completeRefreshWaiters(state.remote, e, st);
        _emitLogged(
          emit,
          state.copyWith(
            status: state.items.isEmpty ? CartStatus.error : CartStatus.loaded,
            errorMessage: e.toString(),
          ),
          'GET error ${event.source}',
        );
      }
    });
  }

  String _resolveAddType(CartItem item) {
    var type = item.itemType.trim();
    if (type.isEmpty) {
      if (item.isKids || isKidsCategory(item.category)) {
        type = 'kids';
      } else if (item.isEssential || isEssentialCategory(item.category)) {
        type = 'essentials';
      }
    }
    if (type.isEmpty && kDebugMode) {
      debugPrint(
        '[CART_ITEM_TYPE] BACKEND MISSING REQUIRED FIELD: item_type in product catalog payload',
      );
    }
    return type;
  }

  bool _isWardrobeKitProduct(CartItem item) {
    final cls = item.productClass?.trim().toLowerCase() ?? '';
    return cls == 'wardrobe_kit' || cls == 'wardrobekit';
  }

  /// Garment nested inside a wardrobe kit (flattened cart line), not essentials/kids
  /// and not the kit parent row itself.
  bool _isGarmentInsideWardrobeKit(CartItem item) {
    if (_isWardrobeKitProduct(item)) return false;
    return item.itemType == 'subscription' || item.itemType == 'non_subscription';
  }

  Future<CartWriteRequest> _buildKitWriteRequest({
    required String itemType,
    required String targetProductId,
    required String? targetVariantId,
    required int targetQuantity,
    required String? targetSize,
    required String? targetCategory,
    required String? targetProductClass,
    required String? targetProductName,
    String? lineIdToSkip,
    CartItem? kitMetaFallback,
  }) async {
    if (itemType != 'subscription' && itemType != 'non_subscription') {
      return CartWriteRequest(
        productId: targetProductId,
        variantId: targetVariantId,
        quantity: targetQuantity <= 0 ? 0 : targetQuantity,
        itemType: itemType,
        size: targetSize,
        categoryName: targetCategory,
        productClass: targetProductClass,
        productName: targetProductName,
      );
    }

    final garments = <Map<String, dynamic>>[];
    final existingGarments = state.items.where((i) {
      if (i.itemType != itemType) return false;
      if (_isWardrobeKitProduct(i)) return false;
      if (i.isKids || isKidsCategory(i.category)) return false;
      if (i.isEssential || isEssentialCategory(i.category)) return false;
      return true;
    });

    for (final g in existingGarments) {
      if (lineIdToSkip != null && g.id == lineIdToSkip) {
        continue;
      }
      if (g.productId == targetProductId &&
          _variantsCompatible(g.variantId, targetVariantId)) {
        continue;
      }
      var garmentVariantId = g.variantId;
      if (garmentVariantId == null || garmentVariantId.isEmpty) {
        final gp = ProductCache.instance.findById(g.productId);
        garmentVariantId = gp?.variants.firstOrNull?.id;
      }
      garments.add({
        'productId': g.productId,
        'quantity': g.quantity,
        'variantId': garmentVariantId,
        'size': g.selectedSize,
        'product_name': g.productName,
        'price': g.unitPrice,
        'primary_image_url': g.imageUrl,
      });
    }

    if (targetQuantity > 0) {
      String targetImageUrl = '';
      num targetPrice = 0;
      final targetProduct = ProductCache.instance.findById(targetProductId);
      if (targetProduct != null) {
        ProductVariant? v;
        if (targetVariantId != null) {
          v = targetProduct.variants
              .where((vr) => vr.id == targetVariantId)
              .firstOrNull;
        }
        targetImageUrl = v?.primaryImageUrl ??
            targetProduct.primaryImageUrl ??
            (targetProduct.imageUrls.isNotEmpty
                ? targetProduct.imageUrls.first
                : '');
        targetPrice = double.tryParse(v?.actualPrice ?? '') ??
            double.tryParse(targetProduct.actualPrice) ??
            0;
      }
      var resolvedTargetVariantId = targetVariantId;
      if (resolvedTargetVariantId == null || resolvedTargetVariantId.isEmpty) {
        resolvedTargetVariantId = targetProduct?.variants.firstOrNull?.id;
      }
      garments.add({
        'productId': targetProductId,
        'quantity': targetQuantity,
        'variantId': resolvedTargetVariantId,
        'size': targetSize,
        'product_name': targetProductName,
        'price': targetPrice,
        'primary_image_url': targetImageUrl,
      });
    }

    String? kitProductId;
    String? kitVariantId;
    String? kitId;
    int? durationDays;
    String? kitName;

    if (existingGarments.isNotEmpty) {
      final existingKit = existingGarments.first.kitDetails;
      kitProductId = existingKit?.wardrobeKitProductId;
      kitVariantId = existingKit?.wardrobeKitVariantId;
      kitId = existingKit?.wardrobeKitId;
      durationDays = existingKit?.durationDays;
      kitName = existingKit?.kitType;
    }

    final fallbackKit = kitMetaFallback?.kitDetails;
    kitProductId ??= fallbackKit?.wardrobeKitProductId;
    kitVariantId ??= fallbackKit?.wardrobeKitVariantId;
    kitId ??= fallbackKit?.wardrobeKitId;
    durationDays ??= fallbackKit?.durationDays;
    kitName ??= fallbackKit?.kitType;

    kitProductId ??= state.wardrobeKitProductId ??
        SubscriptionKitPreferences.instance.wardrobeKitProductId;
    kitVariantId ??= state.wardrobeKitVariantId ??
        SubscriptionKitPreferences.instance.wardrobeKitVariantId;
    kitId ??=
        state.wardrobeKitId ?? SubscriptionKitPreferences.instance.wardrobeKitId;

    if (kitProductId == null || kitProductId.isEmpty) {
      final cachedProducts = ProductCache.instance.products;
      if (cachedProducts != null && cachedProducts.isNotEmpty) {
        final category = state.wardrobeCategory ??
            SubscriptionKitPreferences.instance.wardrobeCategory ??
            '';
        final kitProduct = ProductCatalog.findWardrobeKit(cachedProducts, category) ??
            cachedProducts.where((p) => p.isWardrobeKit).firstOrNull;
        if (kitProduct != null) {
          kitProductId = kitProduct.id;
          kitVariantId ??= kitProduct.variants.firstOrNull?.id;
        }
      }
    }

    if (kitProductId == null || kitProductId.isEmpty) {
      try {
        final products = await ProductRepository().getProducts(forceRefresh: false);
        final category = state.wardrobeCategory ??
            SubscriptionKitPreferences.instance.wardrobeCategory ??
            '';
        final kitProduct = ProductCatalog.findWardrobeKit(products, category) ??
            products.where((p) => p.isWardrobeKit).firstOrNull;
        if (kitProduct != null) {
          kitProductId = kitProduct.id;
          kitVariantId ??= kitProduct.variants.firstOrNull?.id;
        }
      } catch (_) {}
    }

    final resolvedDays = durationDays ??
        (state.wardrobeKitDays > 0
            ? state.wardrobeKitDays
            : SubscriptionKitPreferences.instance.wardrobeKitDays);
    var resolvedKitName = (kitName ?? '').trim();
    if (resolvedKitName.isEmpty) {
      resolvedKitName = state.wardrobeKitName.isNotEmpty
          ? state.wardrobeKitName
          : SubscriptionKitPreferences.instance.wardrobeKitName;
    }

    final resolvedProductId =
        (kitProductId != null && kitProductId.isNotEmpty)
            ? kitProductId
            : targetProductId;

    String? resolvedVariantId;
    if (resolvedProductId == targetProductId &&
        targetVariantId != null &&
        targetVariantId.isNotEmpty) {
      resolvedVariantId = targetVariantId;
    }
    resolvedVariantId ??= kitVariantId;
    if (resolvedVariantId == null || resolvedVariantId.isEmpty) {
      final cached = ProductCache.instance.findById(resolvedProductId);
      resolvedVariantId = cached?.variants.firstOrNull?.id;
    }
    if (resolvedVariantId == null || resolvedVariantId.isEmpty) {
      resolvedVariantId = targetVariantId;
    }
    if ((resolvedVariantId == null || resolvedVariantId.isEmpty) &&
        isApiUuid(resolvedProductId)) {
      try {
        final fetched =
            await ProductRepository().getProductById(resolvedProductId);
        resolvedVariantId = fetched.variants.firstOrNull?.id;
      } catch (e) {
        _cartLog('Failed to fetch product for variant: $e');
      }
    }

    final kit = await _repository.subscriptionKitDetails(
      wardrobeKitId: kitId,
      wardrobeKitProductId: resolvedProductId,
      durationDays: resolvedDays,
      kitName: resolvedKitName,
      selectedItems: garments,
    );

    if (kit != null) {
      kit['non_subscription'] = itemType == 'non_subscription';
      kit['cart_section'] = itemType;
      if (kitId != null && kitId.isNotEmpty) {
        kit['wardrobe_kit_id'] = kitId;
        kit['kitId'] = kitId;
      }
    }

    final remaining = garments.isNotEmpty;
    return CartWriteRequest(
      productId: resolvedProductId,
      variantId: resolvedVariantId,
      // Flow 1: remaining garments → qty 1 + updated selectedItems
      // Last garment / clear kit → qty 0 with kitDetails (empty selectedItems)
      quantity: remaining ? 1 : 0,
      itemType: itemType,
      size: null,
      categoryName: targetCategory,
      kitDetails: kit,
      productClass: 'wardrobe_kit',
      productName: resolvedKitName.isNotEmpty ? resolvedKitName : 'Wardrobe Kit',
    );
  }

  Future<void> _onAdd(AddToCartEvent event, Emitter<CartState> emit) async {
    if (!isApiUuid(event.item.productId)) return;
    final type = _resolveAddType(event.item);
    final key = _lineId(event.item.productId, event.item.variantId, type);
    if (_inflightLines.contains(key) || state.pendingLineIds.contains(key)) {
      _perf('ADD SKIP duplicate line=$key');
      return;
    }
    final opSw = Stopwatch()..start();
    _perf('ADD START line=$key product=${event.item.title}');
    _addUiLog('START productKey=$key');
    _inflightLines.add(key);

    // Immediate optimistic update so user sees instant reaction (0ms delay)
    final qtyToAdd = event.item.quantity > 0 ? event.item.quantity : 1;
    final existingIdx = state.items.indexWhere((it) => it.id == key);
    final previousItem = existingIdx >= 0 ? state.items[existingIdx] : null;
    final prevQty = previousItem?.quantity ?? 0;
    final nextQty = prevQty + qtyToAdd;
    final optimisticItem = event.item.copyWith(
      id: key,
      quantity: nextQty,
      itemType: type,
    );
    _desiredQty[key] = nextQty;
    _serverQty[key] = prevQty;
    _lastKnownItems[key] = previousItem ?? optimisticItem;

    final List<CartItem> nextItems;
    if (existingIdx >= 0) {
      nextItems = state.items.map((it) {
        if (it.id == key) {
          return it.copyWith(quantity: nextQty);
        }
        return it;
      }).toList();
    } else {
      nextItems = [...state.items, optimisticItem];
    }

    _emitLogged(
      emit,
      state.copyWith(
        items: nextItems,
        pendingLineIds: _pendingPlus(key),
      ),
      'AddToCart optimistic',
    );
    try {
      await _enqueueWrite(
        key,
        type,
        () => _handleAdd(event, emit, type: type, targetQty: nextQty),
      );
    } catch (e) {
      _addUiLog('CLEAR LOADING productKey=$key error=true');
      final message = e is ApiException ? e.message : e.toString();
      final isOos = cartVariantOutOfStockMessage(message);
      final isQuota = !isOos && isSubscriptionQuotaError(message);
      if (isOos) {
        logCartStockOut(
          productId: event.item.productId,
          variantId: event.item.variantId,
          size: event.item.selectedSize,
          message: message,
        );
      }
      if (isQuota) {
        logCartQuota(SubscriptionQuotaDetails.parse(message));
      }
      _desiredQty.remove(key);
      _serverQty.remove(key);

      // Revert optimistic add on failure (restore prior qty if line existed).
      final List<CartItem> revertedItems;
      if (previousItem != null) {
        revertedItems = state.items.map((it) {
          if (it.id == key) return previousItem;
          return it;
        }).toList();
      } else {
        revertedItems = state.items.where((it) => it.id != key).toList();
      }
      _emitLogged(
        emit,
        state.copyWith(
          status: CartStatus.loaded,
          items: revertedItems,
          errorMessage: isOos ? null : message,
          pendingLineIds: _pendingMinus(key),
          outOfStockLineIds: isOos
              ? {...state.outOfStockLineIds, key}
              : state.outOfStockLineIds,
        ),
        'AddToCart error rollback',
      );
    } finally {
      _inflightLines.remove(key);
      _emitClearPending(emit, key, 'AddToCart done');
      opSw.stop();
      _perf(
        'UI COMPLETE duration=${opSw.elapsedMilliseconds}ms op=ADD line=$key',
      );
    }
  }

  Future<void> _handleAdd(
    AddToCartEvent event,
    Emitter<CartState> emit, {
    required String type,
    int? targetQty,
  }) async {
    debugPrint('===== CART ADD VARIANT =====');
    debugPrint('productId = ${event.item.productId}');
    debugPrint('variantId = ${event.item.variantId}');
    debugPrint('variantName = ${event.item.title}');

    final key = _lineId(event.item.productId, event.item.variantId, type);
    final desired = _desiredQty[key] ?? targetQty ?? (event.item.quantity > 0 ? event.item.quantity : 1);

    final request = await _buildKitWriteRequest(
      itemType: type,
      targetProductId: event.item.productId,
      targetVariantId: event.item.variantId,
      targetQuantity: desired,
      targetSize: event.item.selectedSize,
      targetCategory: event.item.category,
      targetProductClass: event.item.productClass ?? 'single_item',
      targetProductName: event.item.title,
      lineIdToSkip: key,
    );

    _serverQty[key] = desired;
    await _writeThenGet(
      emit,
      request: request,
      source: 'AddToCart',
      postedType: type,
      productName: event.item.title,
      lineId: key,
    );
    // Authoritative apply won; drop coalesced targets for this line.
    if (_desiredQty[key] == desired) {
      _desiredQty.remove(key);
    }
  }

  CartItem? _line(String itemId) {
    for (final item in state.items) {
      if (item.id == itemId) {
        _lastKnownItems[itemId] = item;
        return item;
      }
    }
    return _lastKnownItems[itemId];
  }

  Future<void> _onRemove(
    RemoveFromCartEvent event,
    Emitter<CartState> emit,
  ) async {
    final item = _line(event.itemId);
    if (item == null) return;
    _desiredQty.remove(item.id);
    _serverQty.remove(item.id);
    if (_qtyFlushing.contains(item.id)) {
      _perf('DELETE COALESCE to qty=0 line=${item.id}');
      return;
    }
    if (_inflightLines.contains(item.id)) {
      _perf('DELETE SKIP duplicate line=${item.id}');
      return;
    }
    final opSw = Stopwatch()..start();
    _perf('DELETE START line=${item.id} product=${item.title}');
    _inflightLines.add(item.id);

    // 1. Immediately remove product from the cart screen (optimistic UI update)
    final nextItems = state.items.where((it) => it.id != item.id).toList();
    _lastKnownItems[item.id] = item;
    _emitLogged(
      emit,
      state.copyWith(
        status: CartStatus.updating,
        items: nextItems,
        pendingLineIds: _pendingPlus(item.id),
      ),
      'RemoveFromCart optimistic',
    );

    try {
      await _enqueueWrite(
        item.id,
        item.itemType,
        () => _handleRemove(item.id, emit, targetItem: item),
      );
    } catch (e) {
      // Restore optimistic remove so Product/Cart stay in sync with server.
      final restored = [...state.items];
      if (!restored.any((it) => it.id == item.id)) {
        restored.add(item);
      }
      _emitLogged(
        emit,
        state.copyWith(
          status: CartStatus.loaded,
          items: restored,
          errorMessage: e.toString(),
          pendingLineIds: _pendingMinus(item.id),
        ),
        'RemoveFromCart error restore',
      );
    } finally {
      _inflightLines.remove(item.id);
      _emitClearPending(emit, item.id, 'RemoveFromCart done');
      _lastKnownItems.remove(item.id);
      opSw.stop();
      _perf(
        'UI COMPLETE duration=${opSw.elapsedMilliseconds}ms op=DELETE line=${item.id}',
      );
    }
  }

  /// Scenario F.2 — delete entire wardrobe kit (no selectedItems).
  Map<String, dynamic> _entireKitDeleteKitDetails({
    required String itemType,
    String? wardrobeKitId,
    String? wardrobeKitProductId,
    String? wardrobeKitVariantId,
  }) {
    final session = CheckoutSession.instance;
    final prefs = SubscriptionKitPreferences.instance;
    final kitId = wardrobeKitId?.trim() ?? state.wardrobeKitId ?? prefs.wardrobeKitId;
    final kitPid = wardrobeKitProductId?.trim() ?? state.wardrobeKitProductId ?? prefs.wardrobeKitProductId;
    final kitVid = wardrobeKitVariantId?.trim() ?? state.wardrobeKitVariantId ?? prefs.wardrobeKitVariantId;
    final addressId = session.addressId?.trim() ?? prefs.addressId;
    final days = state.wardrobeKitDays > 0
        ? state.wardrobeKitDays
        : (prefs.wardrobeKitDays > 0 ? prefs.wardrobeKitDays : 1);
    final kitType = session.kitType ??
        (state.wardrobeKitName.isNotEmpty
            ? state.wardrobeKitName
            : (prefs.kitType ?? '$days-Day wardrobe Kit'));

    final details = <String, dynamic>{
      'gender': session.gender ?? prefs.gender ?? 'male',
      'bodyType': session.bodyType ?? 'regular',
      'kit_type': kitType,
      if (session.apiDeliveryDate != null) 'delivery_date': session.apiDeliveryDate,
      if (session.apiDeliveryDate != null) 'deliveryDate': session.apiDeliveryDate,
      if (session.deliveryTime != null) 'delivery_time': session.deliveryTime,
      if (session.deliveryTime != null) 'deliveryTime': session.deliveryTime,
      if (addressId != null && addressId.isNotEmpty) 'customerAddressId': addressId,
      if (kitId != null && kitId.isNotEmpty) 'wardrobe_kit_id': kitId,
      if (kitId != null && kitId.isNotEmpty) 'kitId': kitId,
      if (kitPid != null && kitPid.isNotEmpty) 'wardrobe_kit_product_id': kitPid,
      if (kitVid != null && kitVid.isNotEmpty) 'wardrobe_kit_variant_id': kitVid,
      'duration_days': days,
      'durationDays': days,
      'selectedItems': const [],
      'non_subscription': itemType == 'non_subscription',
      'cart_section': itemType,
    };
    return details;
  }

  Future<void> _handleRemove(
    String itemId,
    Emitter<CartState> emit, {
    CartItem? targetItem,
  }) async {
    final item = targetItem ?? _line(itemId);
    if (item == null) return;
    _desiredQty.remove(item.id);
    _serverQty.remove(item.id);
    _perf('UPDATE/POST START op=DELETE line=$itemId');

    final CartWriteRequest request;

    if (_isGarmentInsideWardrobeKit(item)) {
      // Scenario E: remove one garment from inside a wardrobe kit by rewriting
      // the parent kit with remaining selectedItems (qty 1).
      // If none remain → Scenario F.2 delete entire kit (qty 0).
      var kitRequest = await _buildKitWriteRequest(
        itemType: item.itemType,
        targetProductId: item.productId,
        targetVariantId: item.variantId,
        targetQuantity: 0,
        targetSize: item.selectedSize,
        targetCategory: item.categoryName,
        targetProductClass: item.productClass ?? 'single_item',
        targetProductName: item.productName,
        lineIdToSkip: item.id,
        kitMetaFallback: item,
      );

      if (kitRequest.quantity <= 0) {
        request = (kitRequest.kitDetails != null && kitRequest.kitDetails!.isNotEmpty)
            ? kitRequest
            : CartWriteRequest(
                productId: kitRequest.productId,
                variantId: kitRequest.variantId,
                quantity: 0,
                itemType: item.itemType,
                kitDetails: _entireKitDeleteKitDetails(
                  itemType: item.itemType,
                  wardrobeKitId: item.kitDetails?.wardrobeKitId ?? state.wardrobeKitId,
                  wardrobeKitProductId: kitRequest.productId,
                  wardrobeKitVariantId: kitRequest.variantId,
                ),
                productClass: 'wardrobe_kit',
                productName: kitRequest.productName,
              );
        _perf('DELETE ENTIRE_KIT (last garment) productId=${request.productId}');
      } else {
        request = kitRequest;
        _perf(
          'DELETE KIT_GARMENT parent=${request.productId} '
          'qty=${request.quantity} selected='
          '${(request.kitDetails?['selectedItems'] is List) ? (request.kitDetails!['selectedItems'] as List).length : 0}',
        );
      }
    } else if (_isWardrobeKitProduct(item)) {
      // Scenario F.2: delete entire wardrobe kit card.
      final kitId = item.kitDetails?.wardrobeKitId ?? state.wardrobeKitId;
      final kitPid = item.productId.isNotEmpty ? item.productId : (state.wardrobeKitProductId ?? item.productId);
      request = CartWriteRequest(
        productId: kitPid,
        variantId: state.wardrobeKitVariantId ?? item.variantId,
        quantity: 0,
        itemType: item.itemType,
        kitDetails: _entireKitDeleteKitDetails(
          itemType: item.itemType,
          wardrobeKitId: kitId,
          wardrobeKitProductId: kitPid,
          wardrobeKitVariantId: state.wardrobeKitVariantId ?? item.variantId,
        ),
        productClass: 'wardrobe_kit',
        productName: item.productName,
      );
      _perf('DELETE ENTIRE_KIT productId=${item.productId}');
    } else {
      // Scenario F.1: standalone product (essentials / kids / independent).
      request = CartWriteRequest(
        productId: item.productId,
        variantId: item.variantId,
        quantity: 0,
        itemType: item.itemType,
        productName: item.productName,
      );
      _perf('DELETE STANDALONE productId=${item.productId}');
    }

    await _writeThenGet(
      emit,
      request: request,
      source: 'RemoveFromCart',
      lineId: item.id,
    );
  }

  Future<void> _onSize(
    UpdateCartItemSizeEvent event,
    Emitter<CartState> emit,
  ) async {
    final item = _line(event.itemId);
    if (item == null) return;
    if (_inflightLines.contains(item.id)) return;
    _inflightLines.add(item.id);
    _emitLogged(
      emit,
      state.copyWith(pendingLineIds: _pendingPlus(item.id)),
      'UpdateSize pending',
    );
    try {
      await _enqueueLine(item.id, () => _handleSize(event, emit));
    } catch (e) {
      _emitLogged(
        emit,
        state.copyWith(
          status: CartStatus.loaded,
          errorMessage: e.toString(),
          pendingLineIds: _pendingMinus(item.id),
        ),
        'UpdateSize error',
      );
    } finally {
      _inflightLines.remove(item.id);
      _emitClearPending(emit, item.id, 'UpdateSize done');
    }
  }

  Future<void> _handleSize(
    UpdateCartItemSizeEvent event,
    Emitter<CartState> emit,
  ) async {
    final item = _line(event.itemId);
    if (item == null) return;

    final product = ProductCache.instance.findById(item.productId);
    if (product == null) return;

    String? currentColor;
    if (item.variantId != null) {
      final oldVariant = product.variants.where((v) => v.id == item.variantId).firstOrNull;
      if (oldVariant != null) {
        currentColor = ProductMapper.optionValue(oldVariant, 'Color');
      }
    }

    final newVariant = ProductMapper.matchingVariant(
      variants: product.variants,
      selectedColor: currentColor,
      selectedSize: event.size,
    );

    if (newVariant != null) {
      await _onUpdateVariant(
        UpdateCartItemVariantEvent(item.id, newVariant),
        emit,
      );
    }
  }

  Future<void> _onUpdateVariant(
    UpdateCartItemVariantEvent event,
    Emitter<CartState> emit,
  ) async {
    final item = _line(event.itemId);
    if (item == null) return;
    if (item.variantId == event.newVariant.id) return;

    final newVariant = event.newVariant;
    final newSize = ProductMapper.optionValue(newVariant, 'Size') ?? item.selectedSize;
    int targetQty = item.quantity;
    if (targetQty > newVariant.stockOnHand && newVariant.stockOnHand > 0) {
      targetQty = newVariant.stockOnHand;
    }
    if (targetQty < 1) targetQty = 1;

    final newImageUrl = (newVariant.primaryImageUrl != null && newVariant.primaryImageUrl!.isNotEmpty)
        ? newVariant.primaryImageUrl!
        : item.imageUrl;

    final newPrice = (item.isEssential || !item.isSubscriptionGarment) &&
            newVariant.actualPrice.isNotEmpty &&
            newVariant.actualPrice != '0'
        ? '₹ ${double.tryParse(newVariant.actualPrice)?.round() ?? newVariant.actualPrice}'
        : item.price;

    final newTitle = newVariant.variantName.isNotEmpty ? newVariant.variantName : item.title;
    final newLineId = _lineId(item.productId, newVariant.id, item.itemType);

    // Immediate optimistic update
    final existingIndex = state.items.indexWhere((it) => it.id == newLineId);
    List<CartItem> updatedItems;
    int effectiveTargetQty = targetQty;

    if (existingIndex >= 0 && state.items[existingIndex].id != item.id) {
      // Merge into existing item with the same variant
      final existing = state.items[existingIndex];
      effectiveTargetQty = existing.quantity + targetQty;
      if (newVariant.stockOnHand > 0 && effectiveTargetQty > newVariant.stockOnHand) {
        effectiveTargetQty = newVariant.stockOnHand;
      }
      updatedItems = state.items
          .where((it) => it.id != item.id)
          .map((it) => it.id == newLineId ? it.copyWith(quantity: effectiveTargetQty) : it)
          .toList();
    } else {
      // Replace item in-place
      final updatedItem = CartItem(
        id: newLineId,
        productId: item.productId,
        variantId: newVariant.id,
        title: newTitle,
        imageUrl: newImageUrl,
        price: newPrice,
        selectedSize: newSize,
        quantity: targetQty,
        itemType: item.itemType,
        category: item.category,
        productClass: item.productClass,
        unitPrice: double.tryParse(newVariant.actualPrice) ?? item.unitPrice,
        lineTotal: (double.tryParse(newVariant.actualPrice) ?? item.unitPrice) * targetQty,
        kitDetails: item.kitDetails,
      );
      updatedItems = state.items.map((it) => it.id == item.id ? updatedItem : it).toList();
    }

    // Snapshot pre-variant items for rollback / resync on failure.
    final itemsBeforeVariant = List<CartItem>.from(state.items);

    _inflightLines.add(newLineId);
    _inflightLines.add(item.id);
    _emitLogged(
      emit,
      state.copyWith(
        items: updatedItems,
        pendingLineIds: {...state.pendingLineIds, newLineId, item.id},
      ),
      'UpdateVariant optimistic',
    );

    try {
      await _enqueueWrite(
        newLineId,
        item.itemType,
        () => _handleUpdateVariant(
          item: item,
          newVariant: newVariant,
          newSize: newSize,
          newTitle: newTitle,
          targetQty: effectiveTargetQty,
          newLineId: newLineId,
          emit: emit,
        ),
      );
    } catch (e) {
      try {
        await _getAuthoritative(emit, source: 'UpdateVariant.error');
      } catch (_) {
        _emitLogged(
          emit,
          state.copyWith(
            status: CartStatus.loaded,
            items: itemsBeforeVariant,
            errorMessage: e.toString(),
            pendingLineIds: _pendingMinus(newLineId)..remove(item.id),
          ),
          'UpdateVariant error rollback',
        );
      }
    } finally {
      _inflightLines.remove(newLineId);
      _inflightLines.remove(item.id);
      _emitClearPending(emit, newLineId, 'UpdateVariant done');
      _emitClearPending(emit, item.id, 'UpdateVariant done');
    }
  }

  Future<void> _handleUpdateVariant({
    required CartItem item,
    required ProductVariant newVariant,
    required String newSize,
    required String newTitle,
    required int targetQty,
    required String newLineId,
    required Emitter<CartState> emit,
  }) async {
    if (_isGarmentInsideWardrobeKit(item)) {
      // Rewrite parent kit with the new variant in selectedItems.
      final request = await _buildKitWriteRequest(
        itemType: item.itemType,
        targetProductId: item.productId,
        targetVariantId: newVariant.id,
        targetQuantity: targetQty,
        targetSize: newSize,
        targetCategory: item.categoryName,
        targetProductClass: item.productClass ?? 'single_item',
        targetProductName: newTitle,
        lineIdToSkip: item.id,
        kitMetaFallback: item,
      );
      _perf('UPDATE/POST START op=VARIANT_KIT line=$newLineId');
      await _writeThenGet(
        emit,
        request: request,
        source: 'UpdateVariant',
        lineId: newLineId,
      );
      return;
    }

    // Scenario F then A/B: standalone — remove old variant, add/update new.
    if (item.variantId != null &&
        item.variantId!.isNotEmpty &&
        item.variantId != newVariant.id) {
      await _repository.upsert(
        request: CartWriteRequest(
          productId: item.productId,
          variantId: item.variantId,
          quantity: 0,
          itemType: item.itemType,
          productName: item.productName,
        ),
        requestId: _repository.nextRequestId(),
        source: 'UpdateVariant.removeOld',
      );
    }

    final request = CartWriteRequest(
      productId: item.productId,
      variantId: newVariant.id,
      quantity: targetQty,
      itemType: item.itemType,
      size: newSize,
      categoryName: item.categoryName,
      productClass: item.productClass ?? 'single_item',
      productName: newTitle,
    );

    _perf('UPDATE/POST START op=VARIANT_ITEM line=$newLineId');
    await _writeThenGet(
      emit,
      request: request,
      source: 'UpdateVariant',
      lineId: newLineId,
    );
  }

  Future<void> _flushQty(String itemId, Emitter<CartState> emit) async {
    while (true) {
      final item = _line(itemId);
      final desired = _desiredQty[itemId];
      if (item == null || desired == null) return;
      if (_serverQty[itemId] == desired) {
        _desiredQty.remove(itemId);
        return;
      }
      if (desired <= 0) {
        _desiredQty.remove(itemId);
        _serverQty.remove(itemId);
        await _handleRemove(itemId, emit);
        return;
      }

      final CartWriteRequest request;
      if (_isGarmentInsideWardrobeKit(item)) {
        // Kit garment qty change → update parent kit selectedItems (Scenario C/E).
        request = await _buildKitWriteRequest(
          itemType: item.itemType,
          targetProductId: item.productId,
          targetVariantId: item.variantId,
          targetQuantity: desired,
          targetSize: item.selectedSize,
          targetCategory: item.categoryName,
          targetProductClass: item.productClass ?? 'single_item',
          targetProductName: item.productName,
          lineIdToSkip: item.id,
          kitMetaFallback: item,
        );
      } else {
        // Scenario A/B: standalone product quantity update.
        request = CartWriteRequest(
          productId: item.productId,
          variantId: item.variantId,
          quantity: desired,
          itemType: item.itemType,
          productName: item.productName,
        );
      }

      _serverQty[itemId] = desired;
      await _writeThenGet(
        emit,
        request: request,
        source: 'UpdateQuantity',
        lineId: itemId,
      );
    }
  }

  Future<void> _onQty(
    UpdateCartItemQuantityEvent event,
    Emitter<CartState> emit,
  ) async {
    final item = _line(event.itemId);
    if (item == null) return;

    if (event.quantity <= 0) {
      await _onRemove(RemoveFromCartEvent(event.itemId), emit);
      return;
    }

    _desiredQty[item.id] = event.quantity;

    // Immediate optimistic update of item quantity
    final updatedItems = state.items.map((it) {
      if (it.id == item.id) {
        return it.copyWith(quantity: event.quantity);
      }
      return it;
    }).toList();

    _emitLogged(
      emit,
      state.copyWith(
        status: CartStatus.updating,
        items: updatedItems,
        pendingLineIds: _pendingPlus(item.id),
      ),
      'Quantity optimistic ${event.quantity}',
    );

    _perf('QUANTITY START line=${item.id} desired=${event.quantity}');
    if (_qtyFlushing.contains(item.id)) {
      _perf('QUANTITY COALESCE line=${item.id} desired=${event.quantity}');
      return;
    }
    await _runQtyFlush(item.id, emit);
  }

  Future<void> _onAdjust(
    AdjustCartItemQuantityEvent event,
    Emitter<CartState> emit,
  ) async {
    final item = _line(event.itemId);
    if (item == null || event.delta == 0) return;
    final next = (_desiredQty[item.id] ?? item.quantity) + event.delta;
    await _onQty(UpdateCartItemQuantityEvent(event.itemId, next), emit);
  }

  Future<void> _runQtyFlush(String itemId, Emitter<CartState> emit) async {
    final opSw = Stopwatch()..start();
    _qtyFlushing.add(itemId);
    if (!_inflightLines.contains(itemId)) {
      _inflightLines.add(itemId);
      _emitLogged(
        emit,
        state.copyWith(pendingLineIds: _pendingPlus(itemId)),
        'Quantity pending',
      );
    }
    try {
      await _enqueueWrite(itemId, _line(itemId)?.itemType ?? 'non_subscription',
          () async {
        // Debounce slightly to coalesce rapid clicks into a single backend request
        await Future.delayed(const Duration(milliseconds: 150));
        final desired = _desiredQty[itemId] ?? 0;
        if (desired <= 0) {
          _desiredQty.remove(itemId);
          await _handleRemove(itemId, emit);
          return;
        }
        await _flushQty(itemId, emit);
      });
    } catch (e) {
      _emitLogged(
        emit,
        state.copyWith(
          status: CartStatus.loaded,
          errorMessage: e.toString(),
          pendingLineIds: _pendingMinus(itemId),
        ),
        'UpdateQuantity error',
      );
    } finally {
      _qtyFlushing.remove(itemId);
      _inflightLines.remove(itemId);
      _emitClearPending(emit, itemId, 'Quantity done');
      opSw.stop();
      _perf(
        'UI COMPLETE duration=${opSw.elapsedMilliseconds}ms op=QUANTITY line=$itemId',
      );
    }
  }

  Future<void> _onClear(ClearCartEvent event, Emitter<CartState> emit) async {
    await _enqueue(() async {
      try {
        _emitLogged(
          emit,
          state.copyWith(status: CartStatus.updating),
          'ClearCart',
        );
        final clearedKitIds = <String>{};
        for (final item in List<CartItem>.from(state.items)) {
          if (_isGarmentInsideWardrobeKit(item) || _isWardrobeKitProduct(item)) {
            final kitPid = (_isWardrobeKitProduct(item)
                    ? item.productId
                    : (item.kitDetails?.wardrobeKitProductId ??
                        state.wardrobeKitProductId ??
                        ''))
                .trim();
            if (kitPid.isEmpty || clearedKitIds.contains(kitPid)) continue;
            clearedKitIds.add(kitPid);
            await _repository.upsert(
              request: CartWriteRequest(
                productId: kitPid,
                quantity: 0,
                itemType: item.itemType,
                kitDetails: _entireKitDeleteKitDetails(
                  itemType: item.itemType,
                  wardrobeKitId:
                      item.kitDetails?.wardrobeKitId ?? state.wardrobeKitId,
                ),
                productClass: 'wardrobe_kit',
              ),
              requestId: _repository.nextRequestId(),
              source: 'ClearCart.kit',
            );
          } else {
            await _repository.upsert(
              request: CartWriteRequest(
                productId: item.productId,
                variantId: item.variantId,
                quantity: 0,
                itemType: item.itemType,
              ),
              requestId: _repository.nextRequestId(),
              source: 'ClearCart.item',
            );
          }
        }
        await _getAuthoritative(emit, source: 'ClearCart.afterPost');
      } catch (_) {
        try {
          await _getAuthoritative(emit, source: 'ClearCart.error');
        } catch (e, st) {
          _completeRefreshWaiters(state.remote, e, st);
        }
      }
    });
  }

  Future<void> _onClearLocal(
    ClearLocalCartEvent event,
    Emitter<CartState> emit,
  ) async {
    _desiredQty.clear();
    _serverQty.clear();
    _lastKnownItems.clear();
    _inflightLines.clear();
    _qtyFlushing.clear();
    _lineOps.clear();
    _latestApplyId = _repository.nextRequestId();
    _writeGeneration = _latestApplyId;
    _emitLogged(
      emit,
      const CartState(status: CartStatus.loaded),
      'ClearLocalCart',
    );
  }

  Future<void> _onClearPaid(
    ClearPaidRentalItemsEvent event,
    Emitter<CartState> emit,
  ) async {
    await _enqueue(() async {
      final paid = List<CartItem>.from(state.paidRentalGarmentItems);
      if (paid.isEmpty) return;
      try {
        final kitPid = (paid.first.kitDetails?.wardrobeKitProductId ??
                state.wardrobeKitProductId ??
                '')
            .trim();
        if (kitPid.isNotEmpty) {
          await _repository.upsert(
            request: CartWriteRequest(
              productId: kitPid,
              quantity: 0,
              itemType: 'non_subscription',
              kitDetails: _entireKitDeleteKitDetails(
                itemType: 'non_subscription',
                wardrobeKitId: paid.first.kitDetails?.wardrobeKitId ??
                    state.wardrobeKitId,
              ),
              productClass: 'wardrobe_kit',
            ),
            requestId: _repository.nextRequestId(),
            source: 'ClearPaidRental.kit',
          );
        } else {
          for (final item in paid) {
            await _repository.upsert(
              request: CartWriteRequest(
                productId: item.productId,
                variantId: item.variantId,
                quantity: 0,
                itemType: item.itemType,
              ),
              requestId: _repository.nextRequestId(),
              source: 'ClearPaidRental.item',
            );
          }
        }
        await _getAuthoritative(emit, source: 'ClearPaidRental.afterPost');
      } catch (e) {
        _emitLogged(
          emit,
          state.copyWith(status: CartStatus.loaded, errorMessage: e.toString()),
          'ClearPaidRental error',
        );
      }
    });
  }
}

int calculateCurrentSubscriptionGarmentCount(List<CartItem> items) {
  return items.fold<int>(
    0,
    (sum, item) =>
        item.itemType == 'subscription' ? sum + item.quantity : sum,
  );
}
