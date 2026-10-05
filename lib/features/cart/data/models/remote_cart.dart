class RemoteCartKitDetails {
  const RemoteCartKitDetails({
    this.gender,
    this.bodyType,
    this.kitType,
    this.deliveryDate,
    this.deliveryTime,
    this.customerAddressId,
    this.height,
    this.weight,
    this.wardrobeKitId,
    this.wardrobeKitProductId,
    this.wardrobeKitVariantId,
    this.durationDays,
    this.selectedItems,
  });

  final String? gender;
  final String? bodyType;
  final String? kitType;
  final String? deliveryDate;
  final String? deliveryTime;
  final String? customerAddressId;
  final String? height;
  final String? weight;
  final String? wardrobeKitId;
  final String? wardrobeKitProductId;
  final String? wardrobeKitVariantId;
  final int? durationDays;
  final List<dynamic>? selectedItems;

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};
    if (gender != null && gender!.isNotEmpty) map['gender'] = gender;
    if (bodyType != null && bodyType!.isNotEmpty) map['bodyType'] = bodyType;
    if (kitType != null && kitType!.isNotEmpty) map['kit_type'] = kitType;
    if (deliveryDate != null && deliveryDate!.isNotEmpty) {
      map['delivery_date'] = deliveryDate;
      map['deliveryDate'] = deliveryDate;
    }
    if (deliveryTime != null && deliveryTime!.isNotEmpty) {
      map['delivery_time'] = deliveryTime;
      map['deliveryTime'] = deliveryTime;
    }
    if (customerAddressId != null && customerAddressId!.isNotEmpty) {
      map['customerAddressId'] = customerAddressId;
    }
    if (height != null && height!.isNotEmpty) map['height'] = height;
    if (weight != null && weight!.isNotEmpty) map['weight'] = weight;
    if (wardrobeKitId != null && wardrobeKitId!.isNotEmpty) {
      map['wardrobe_kit_id'] = wardrobeKitId;
      map['kitId'] = wardrobeKitId;
    }
    if (wardrobeKitProductId != null && wardrobeKitProductId!.isNotEmpty) {
      map['wardrobe_kit_product_id'] = wardrobeKitProductId;
    }
    if (wardrobeKitVariantId != null && wardrobeKitVariantId!.isNotEmpty) {
      map['wardrobe_kit_variant_id'] = wardrobeKitVariantId;
    }
    if (durationDays != null && durationDays! > 0) {
      map['duration_days'] = durationDays;
      map['durationDays'] = durationDays;
    }
    // Always send selectedItems when provided — including [] so a kit clear
    // replaces garments instead of leaving the previous selection on the server.
    if (selectedItems != null) {
      map['selectedItems'] = selectedItems;
    }
    return map;
  }
}

class RemoteCartItem {
  const RemoteCartItem({
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.itemType,
    this.variantId,
    this.imageUrl,
    this.categoryName,
    this.productClass,
    this.unitPrice = 0,
    this.lineTotal = 0,
    this.size,
    this.kitDetails,
  });

  final String productId;
  final String productName;
  final String? variantId;
  final String? imageUrl;
  final String? categoryName;
  final String? productClass;
  final String itemType;
  final int quantity;
  final num unitPrice;
  final num lineTotal;
  final String? size;
  final RemoteCartKitDetails? kitDetails;

  factory RemoteCartItem.fromJson(
    Map<String, dynamic> json, {
    String defaultType = '',
  }) {
    final kitRaw = json['kitDetails'] ?? json['kit_details'];
    return RemoteCartItem(
      productId: json['productId']?.toString() ??
          json['product_id']?.toString() ??
          '',
      productName: json['productName']?.toString() ??
          json['product_name']?.toString() ??
          'Product',
      variantId: _nonEmpty(json['variantId'] ?? json['variant_id']),
      imageUrl: _nonEmpty(
        json['imageUrl'] ??
            json['image_url'] ??
            json['primaryImageUrl'] ??
            json['primary_image_url'],
      ),
      categoryName: _nonEmpty(
        json['categoryName'] ?? json['category_name'] ?? json['category'],
      ),
      productClass: _nonEmpty(json['productClass'] ?? json['product_class']),
      itemType: _normalizeItemType(
        json['item_type'] ?? json['itemType'] ?? defaultType,
      ),
      quantity: _parseInt(json['quantity']) ?? 0,
      unitPrice: _parseNum(json['unitPrice'] ?? json['unit_price'] ?? json['price']) ?? 0,
      lineTotal: _parseNum(json['lineTotal'] ?? json['line_total'] ?? json['price']) ?? 0,
      size: _nonEmpty(json['size'] ?? json['selectedSize']),
      kitDetails: kitRaw is Map
          ? RemoteCartKitDetails(
              gender: _nonEmpty(kitRaw['gender']),
              bodyType: _nonEmpty(kitRaw['bodyType'] ?? kitRaw['body_type']),
              kitType: _nonEmpty(kitRaw['kit_type'] ?? kitRaw['kitType']),
              deliveryDate:
                  _nonEmpty(kitRaw['delivery_date'] ?? kitRaw['deliveryDate']),
              deliveryTime:
                  _nonEmpty(kitRaw['delivery_time'] ?? kitRaw['deliveryTime']),
              customerAddressId: _nonEmpty(
                kitRaw['customerAddressId'] ?? kitRaw['customer_address_id'],
              ),
              height: _nonEmpty(kitRaw['height']),
              weight: _nonEmpty(kitRaw['weight']),
              wardrobeKitId: _nonEmpty(
                kitRaw['wardrobe_kit_id'] ??
                    kitRaw['wardrobeKitId'] ??
                    kitRaw['kitId'] ??
                    kitRaw['selectedKitId'] ??
                    kitRaw['selected_kit_id'],
              ),
              wardrobeKitProductId: _nonEmpty(
                kitRaw['wardrobe_kit_product_id'] ??
                    kitRaw['wardrobeKitProductId'],
              ),
              wardrobeKitVariantId: _nonEmpty(
                kitRaw['wardrobe_kit_variant_id'] ??
                    kitRaw['wardrobeKitVariantId'],
              ),
              durationDays: _parseInt(
                kitRaw['duration_days'] ?? kitRaw['durationDays'],
              ),
              selectedItems: () {
                final raw = kitRaw['selectedItems'] ?? kitRaw['selected_items'];
                return raw is List ? List.from(raw) : null;
              }(),
            )
          : null,
    );
  }
}

class RemoteCart {
  const RemoteCart({
    required this.id,
    required this.items,
    this.customerAddressId,
    this.subtotal = 0,
    this.deliveryCharge = 0,
    this.discountAmount = 0,
    this.taxAmount = 0,
    this.totalAmount = 0,
    this.itemCount = 0,
    this.cartStatus = 'active',
    this.updatedAt,
    this.subscriptionCount = 0,
    this.nonSubscriptionCount = 0,
    this.essentialsCount = 0,
    this.kidsCount = 0,
    this.activeKitPrice = 0,
    this.securityDepositAmount = 0,
  });

  final String id;
  final List<RemoteCartItem> items;
  final String? customerAddressId;
  final num subtotal;
  final num deliveryCharge;
  final num discountAmount;
  final num taxAmount;
  final num totalAmount;
  final int itemCount;
  final String cartStatus;
  final String? updatedAt;
  final int subscriptionCount;
  final int nonSubscriptionCount;
  final int essentialsCount;
  final int kidsCount;
  final num activeKitPrice;
  final num securityDepositAmount;

  bool get isEmpty => itemCount <= 0 && items.isEmpty;

  factory RemoteCart.fromJson(Map<String, dynamic> json) {
    final sectionsRaw = json['sections'];
    final summary = json['summary'];
    final cartItems = _parseItemList(
      json['cartItems'] ?? json['cart_items'] ?? json['items'],
    );
    final sectionItems = _itemsFromSections(sectionsRaw);
    final items = _canonicalCartLines(cartItems, sectionItems);

    // Determine canonical kit prices if any active wardrobe kits exist
    num activeKitPrice = 0;
    num activeKitPreAuth = 0;
    final rawCartItems = json['cartItems'] ?? json['cart_items'] ?? json['items'];
    if (rawCartItems is List) {
      for (final raw in rawCartItems) {
        if (raw is Map) {
          final kitRaw = raw['kitDetails'] ?? raw['kit_details'];
          if (kitRaw is Map &&
              (kitRaw['selectedItems'] is List ||
                  kitRaw['selected_items'] is List)) {
            final p = _parseNum(raw['unitPrice'] ?? raw['unit_price'] ?? raw['price'] ?? kitRaw['price'] ?? kitRaw['kit_price']);
            if (p != null && p > 0) activeKitPrice = p;
            final preAuth = _parseNum(raw['pre_auth_amount'] ?? raw['current_amount'] ?? kitRaw['pre_auth_amount']);
            if (preAuth != null && preAuth > 0) activeKitPreAuth = preAuth;
          }
        }
      }
    }

    final hasPaidWardrobe = items.any((it) => it.itemType == 'non_subscription');
    final directItemsTotal = items
        .where((it) => it.itemType != 'subscription' && it.itemType != 'non_subscription')
        .fold<num>(0, (sum, it) => sum + (it.unitPrice > 0 ? it.unitPrice * it.quantity : it.lineTotal));

    final rawSubtotal = _parseNum(json['subtotal']) ?? 0;
    num canonicalSubtotal = rawSubtotal;
    if (hasPaidWardrobe && activeKitPrice > 0) {
      final expectedSubtotal = activeKitPrice + directItemsTotal;
      if (rawSubtotal > expectedSubtotal) {
        canonicalSubtotal = expectedSubtotal;
      }
    } else if (!hasPaidWardrobe && items.isNotEmpty) {
      canonicalSubtotal = directItemsTotal;
    }

    final rawTax = _parseNum(json['tax_amount'] ?? json['taxAmount']) ?? 0;
    num canonicalTax = rawTax;
    if (rawSubtotal > 0 && canonicalSubtotal < rawSubtotal) {
      canonicalTax = (canonicalSubtotal * (rawTax / rawSubtotal)).roundToDouble();
    }

    final rawDelivery = _parseNum(json['delivery_charge'] ?? json['deliveryCharge']) ?? 0;
    final rawDiscount = _parseNum(
      json['discount_amount'] ??
          json['discountAmount'] ??
          (summary is Map
              ? (summary['discount_amount'] ?? summary['discountAmount'])
              : null),
    ) ?? 0;

    final rawTotal = _parseNum(json['total_amount'] ?? json['totalAmount']) ?? 0;
    num canonicalTotal = rawTotal;
    if (rawSubtotal > 0 && canonicalSubtotal < rawSubtotal) {
      final orderTotal = canonicalSubtotal + rawDelivery + canonicalTax - rawDiscount;
      canonicalTotal = orderTotal + activeKitPreAuth;
    }

    final subCount = items.where((it) => it.itemType == 'subscription').fold<int>(0, (s, i) => s + i.quantity);
    final nonSubCount = items.where((it) => it.itemType == 'non_subscription').fold<int>(0, (s, i) => s + i.quantity);
    final essCount = items.where((it) => it.itemType == 'essentials').fold<int>(0, (s, i) => s + i.quantity);
    final kdCount = items.where((it) => it.itemType == 'kids').fold<int>(0, (s, i) => s + i.quantity);
    final qtySum = items.fold<int>(0, (sum, item) => sum + item.quantity);

    final topLevelDeposit = _parseNum(
      json['security_deposit_amount'] ??
          json['securityDepositAmount'] ??
          json['security_deposit'] ??
          json['securityDeposit'] ??
          (summary is Map
              ? (summary['security_deposit_amount'] ??
                  summary['securityDepositAmount'] ??
                  summary['security_deposit'] ??
                  summary['securityDeposit'] ??
                  summary['pre_auth_amount'] ??
                  summary['preAuthAmount'])
              : null),
    ) ?? 0;
    final effectiveDeposit = topLevelDeposit > 0 ? topLevelDeposit : activeKitPreAuth;

    return RemoteCart(
      id: json['id']?.toString() ?? '',
      items: items,
      customerAddressId: _nonEmpty(
        json['customer_address_id'] ?? json['customerAddressId'],
      ),
      subtotal: canonicalSubtotal,
      deliveryCharge: rawDelivery,
      discountAmount: rawDiscount,
      taxAmount: canonicalTax,
      totalAmount: canonicalTotal,
      itemCount: qtySum,
      cartStatus: json['cart_status']?.toString() ??
          json['cartStatus']?.toString() ??
          'active',
      updatedAt: _nonEmpty(json['updated_at'] ?? json['updatedAt']),
      subscriptionCount: subCount,
      nonSubscriptionCount: nonSubCount,
      essentialsCount: essCount,
      kidsCount: kdCount,
      activeKitPrice: activeKitPrice,
      securityDepositAmount: effectiveDeposit,
    );
  }
}

String _normalizeItemType(dynamic raw) {
  final type = raw?.toString().trim().toLowerCase() ?? '';
  if (type == 'subscription') return 'subscription';
  if (type == 'non_subscription' ||
      type == 'non-subscription' ||
      type == 'paid' ||
      type == 'paid_rental') {
    return 'non_subscription';
  }
  if (type == 'essentials' || type == 'essential') return 'essentials';
  if (type == 'kids' || type == 'kid') return 'kids';
  return '';
}

bool _sameVariant(String? a, String? b) {
  final va = a?.trim() ?? '';
  final vb = b?.trim() ?? '';
  if (va.isEmpty && vb.isEmpty) return true;
  return va == vb;
}

List<RemoteCartItem> _deduplicateItems(List<RemoteCartItem> items) {
  final result = <RemoteCartItem>[];
  for (final item in items) {
    if (item.productId.isEmpty || item.quantity <= 0) continue;
    final pid = item.productId.trim();
    final vid = item.variantId?.trim() ?? '';
    final type = item.itemType.trim();

    final existingIndex = result.indexWhere((r) =>
        r.productId.trim() == pid &&
        (r.variantId?.trim() ?? '') == vid &&
        (type.isEmpty || r.itemType.trim().isEmpty || r.itemType.trim() == type));

    if (existingIndex >= 0) {
      final existing = result[existingIndex];
      final finalQty = item.quantity > 0 ? item.quantity : existing.quantity;
      final unit = existing.unitPrice > 0 ? existing.unitPrice : item.unitPrice;
      result[existingIndex] = RemoteCartItem(
        productId: existing.productId,
        productName: existing.productName.isNotEmpty
            ? existing.productName
            : item.productName,
        variantId: existing.variantId ?? item.variantId,
        imageUrl: (existing.imageUrl != null && existing.imageUrl!.isNotEmpty)
            ? existing.imageUrl
            : item.imageUrl,
        categoryName: existing.categoryName ?? item.categoryName,
        productClass: existing.productClass ?? item.productClass,
        itemType: existing.itemType.isNotEmpty
            ? existing.itemType
            : item.itemType,
        quantity: finalQty,
        unitPrice: unit,
        lineTotal: unit > 0 ? unit * finalQty : item.lineTotal,
        size: existing.size ?? item.size,
        kitDetails: existing.kitDetails ?? item.kitDetails,
      );
    } else {
      result.add(item);
    }
  }
  return result;
}

List<RemoteCartItem> _canonicalCartLines(
  List<RemoteCartItem> cartItems,
  List<RemoteCartItem> sectionItems,
) {
  if (sectionItems.isEmpty) return _deduplicateItems(cartItems);
  final extras = <RemoteCartItem>[];
  for (final item in cartItems) {
    final inSection = sectionItems.any(
      (section) =>
          section.productId.trim() == item.productId.trim() &&
          _sameVariant(section.variantId, item.variantId) &&
          (section.itemType.isEmpty ||
              item.itemType.isEmpty ||
              section.itemType == item.itemType),
    );
    if (!inSection) extras.add(item);
  }
  return _deduplicateItems([...sectionItems, ...extras]);
}

void _flattenAndAdd(
  RemoteCartItem parsed,
  List<RemoteCartItem> items,
  String defaultType,
) {
  if (parsed.productId.isEmpty || parsed.quantity <= 0) return;

  final selectedItems = parsed.kitDetails?.selectedItems;
  if (selectedItems != null && selectedItems.isNotEmpty) {
    for (final sub in selectedItems) {
      if (sub is Map) {
        final subMap = Map<String, dynamic>.from(sub);
        subMap['item_type'] = subMap['item_type'] ?? parsed.itemType;
        
        // Preserve the parent kit details (which contains the Master Kit Product ID)
        // so that CartBloc can still look up state.wardrobeKitProductId!
        if (parsed.kitDetails != null && 
            !subMap.containsKey('kitDetails') && 
            !subMap.containsKey('kit_details')) {
          final kitJson = parsed.kitDetails!.toJson();
          // We don't want to deeply nest the garments onto each garment!
          kitJson.remove('selectedItems');
          
          // INJECT the Master Kit's Product ID so CartBloc knows it!
          kitJson['wardrobe_kit_product_id'] = parsed.productId;
          if (parsed.variantId != null && parsed.variantId!.isNotEmpty) {
            kitJson['wardrobe_kit_variant_id'] = parsed.variantId;
          }
          
          subMap['kitDetails'] = kitJson;
        }

        final subParsed = RemoteCartItem.fromJson(
          subMap,
          defaultType: defaultType,
        );
        if (subParsed.productId.isNotEmpty && subParsed.quantity > 0) {
          items.add(subParsed);
        }
      }
    }
  } else {
    items.add(parsed);
  }
}

List<RemoteCartItem> _extractCanonicalKitAndItems(dynamic itemsRaw, {String defaultType = ''}) {
  if (itemsRaw is! List) return const [];

  final kitEntries = <Map<String, dynamic>>[];
  final directItems = <RemoteCartItem>[];

  for (final raw in itemsRaw) {
    if (raw is! Map) continue;
    final map = Map<String, dynamic>.from(raw);
    final kitRaw = map['kitDetails'] ?? map['kit_details'];
    final selectedItems = kitRaw is Map ? (kitRaw['selectedItems'] ?? kitRaw['selected_items']) : null;

    if (selectedItems is List && selectedItems.isNotEmpty) {
      kitEntries.add(map);
    } else {
      final parsed = RemoteCartItem.fromJson(map, defaultType: defaultType);
      if (parsed.productId.isNotEmpty && parsed.quantity > 0) {
        directItems.add(parsed);
      }
    }
  }

  final result = <RemoteCartItem>[];

  // If duplicate kit entries exist for the same section / kit ID,
  // retain only the CANONICAL latest kit entry.
  // Prefer the last entry (backend appends snapshots). When ties exist in
  // cartItems vs sections, last-writer in each list wins per groupKey.
  if (kitEntries.isNotEmpty) {
    final Map<String, Map<String, dynamic>> latestKitPerGroup = {};
    final Map<String, int> latestIndexPerGroup = {};
    for (var i = 0; i < kitEntries.length; i++) {
      final kitMap = kitEntries[i];
      final kitRaw = (kitMap['kitDetails'] ?? kitMap['kit_details']) as Map;
      final kitId = kitRaw['wardrobe_kit_id'] ??
          kitRaw['wardrobeKitId'] ??
          kitRaw['kitId'] ??
          kitRaw['selectedKitId'] ??
          kitRaw['selected_kit_id'] ??
          kitRaw['kit_type'] ??
          'default_kit';
      final section = _normalizeItemType(
        kitMap['cart_section'] ?? kitMap['item_type'] ?? defaultType,
      );
      // Group by section + kit product id so historical rows collapse to one.
      final kitProductId = kitMap['productId'] ??
          kitMap['product_id'] ??
          kitRaw['wardrobe_kit_product_id'] ??
          kitId;
      final groupKey = '$section|$kitProductId';
      final prevIdx = latestIndexPerGroup[groupKey];
      if (prevIdx == null || i >= prevIdx) {
        latestKitPerGroup[groupKey] = kitMap;
        latestIndexPerGroup[groupKey] = i;
      }
    }

    for (final canonicalKitMap in latestKitPerGroup.values) {
      final parsedKit =
          RemoteCartItem.fromJson(canonicalKitMap, defaultType: defaultType);
      _flattenAndAdd(parsedKit, result, parsedKit.itemType);
    }
  }

  result.addAll(directItems);
  return result;
}

List<RemoteCartItem> _parseItemList(dynamic itemsRaw) {
  return _extractCanonicalKitAndItems(itemsRaw);
}

List<RemoteCartItem> _itemsFromSections(dynamic sections) {
  if (sections is! Map) return const [];
  final map = Map<String, dynamic>.from(sections);
  final items = <RemoteCartItem>[];

  void addSection(String key) {
    final block = map[key];
    if (block is! Map) return;
    final list = block['items'];
    if (list is! List) return;
    items.addAll(_extractCanonicalKitAndItems(list, defaultType: key));
  }

  addSection('subscription');
  addSection('non_subscription');
  addSection('essentials');
  addSection('kids');
  return items;
}

String? _nonEmpty(dynamic value) {
  final text = value?.toString().trim();
  return (text == null || text.isEmpty) ? null : text;
}

int? _parseInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

num? _parseNum(dynamic value) {
  if (value is num) return value;
  if (value is String) return num.tryParse(value);
  return null;
}
