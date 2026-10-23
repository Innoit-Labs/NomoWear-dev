class WardrobePlan {
  final String id;
  final String categoryId;
  final String? categoryName;
  final String name;
  final String planCode;
  final String planRef;
  final String? description;
  final int durationDays;
  final int maxGarments;
  final int noOfBookings;
  final num monthPrice;
  final num yearPrice;
  final num price;
  final String billingPeriod;
  final List<String> features;
  final int displayOrder;
  final bool isActive;

  const WardrobePlan({
    required this.id,
    required this.categoryId,
    this.categoryName,
    required this.name,
    required this.planCode,
    required this.planRef,
    this.description,
    required this.durationDays,
    required this.maxGarments,
    required this.noOfBookings,
    required this.monthPrice,
    required this.yearPrice,
    required this.price,
    this.billingPeriod = '',
    this.features = const [],
    this.displayOrder = 0,
    this.isActive = true,
  });

  bool get isYearlyPlan {
    final n = name.toLowerCase();
    if (n.contains('year') || n.contains('annual')) return true;

    final bp = billingPeriod.toLowerCase();
    if (bp.contains('year') || bp.contains('annual')) return true;

    final code = planCode.toLowerCase();
    if (code.contains('year') || code.contains('annual')) return true;

    final ref = planRef.toLowerCase();
    if (ref.contains('year') || ref.contains('annual')) return true;

    if (durationDays >= 300) return true;

    if (features.any((f) {
      final fl = f.toLowerCase();
      return fl.contains('/ year') ||
          fl.contains('/year') ||
          fl.contains('per year') ||
          fl.contains('bookings / year') ||
          fl.contains('days / year');
    })) {
      return true;
    }

    if (yearPrice > 0 && monthPrice <= 0) return true;

    return false;
  }

  bool get isMonthlyPlan {
    // If it is explicitly a yearly plan, it cannot be considered a monthly plan
    if (isYearlyPlan) return false;

    final n = name.toLowerCase();
    if (n.contains('month')) return true;

    final bp = billingPeriod.toLowerCase();
    if (bp.contains('month')) return true;

    final code = planCode.toLowerCase();
    if (code.contains('month')) return true;

    final ref = planRef.toLowerCase();
    if (ref.contains('month')) return true;

    if (features.any((f) {
      final fl = f.toLowerCase();
      return fl.contains('/ month') ||
          fl.contains('/month') ||
          fl.contains('per month') ||
          fl.contains('bookings / month') ||
          fl.contains('days / month');
    })) {
      return true;
    }

    if (monthPrice > 0 && yearPrice <= 0) return true;

    return false;
  }

  factory WardrobePlan.fromJson(Map<String, dynamic> json) {
    final featuresRaw = json['features'];
    final features = <String>[];
    if (featuresRaw is List) {
      for (final item in featuresRaw) {
        final text = item?.toString().trim();
        if (text != null && text.isNotEmpty) features.add(text);
      }
    }

    final id = json['id']?.toString() ??
        json['_id']?.toString() ??
        json['planId']?.toString() ??
        json['plan_id']?.toString() ??
        json['planRef']?.toString() ??
        json['plan_ref']?.toString() ??
        '';

    final name = json['name']?.toString() ??
        json['planName']?.toString() ??
        json['plan_name']?.toString() ??
        json['title']?.toString() ??
        '';

    final billingPeriod = json['billingPeriod']?.toString() ??
        json['billing_period']?.toString() ??
        json['period']?.toString() ??
        json['planType']?.toString() ??
        json['plan_type']?.toString() ??
        json['billing_cycle']?.toString() ??
        json['billingCycle']?.toString() ??
        json['interval']?.toString() ??
        json['frequency']?.toString() ??
        json['type']?.toString() ??
        '';

    final durationDays = _parseInt(
      json['durationDays'] ??
          json['duration_days'] ??
          json['duration'] ??
          json['days'],
    ) ?? 0;

    final bpLower = billingPeriod.toLowerCase();
    final nameLower = name.toLowerCase();
    final planCodeLower = (json['planCode'] ?? json['plan_code'] ?? '').toString().toLowerCase();

    final hasYearFeature = features.any((f) {
      final fl = f.toLowerCase();
      return fl.contains('/ year') ||
          fl.contains('/year') ||
          fl.contains('per year') ||
          fl.contains('bookings / year') ||
          fl.contains('days / year');
    });

    final hasMonthFeature = features.any((f) {
      final fl = f.toLowerCase();
      return fl.contains('/ month') ||
          fl.contains('/month') ||
          fl.contains('per month') ||
          fl.contains('bookings / month') ||
          fl.contains('days / month');
    });

    final isYearly = bpLower.contains('year') ||
        bpLower.contains('annual') ||
        nameLower.contains('year') ||
        nameLower.contains('annual') ||
        planCodeLower.contains('year') ||
        planCodeLower.contains('annual') ||
        durationDays >= 300 ||
        (hasYearFeature && !hasMonthFeature);

    final isMonthly = bpLower.contains('month') ||
        nameLower.contains('month') ||
        planCodeLower.contains('month') ||
        (hasMonthFeature && !hasYearFeature);

    final resolvedBillingPeriod = billingPeriod.isNotEmpty
        ? billingPeriod
        : (isYearly ? 'yearly' : (isMonthly ? 'monthly' : ''));

    final priceRaw = _parseNum(
      json['price'] ??
          json['amount'] ??
          json['planPrice'] ??
          json['plan_price'] ??
          json['cost'],
    ) ?? 0;

    final monthPriceRaw =
        _parseNum(json['monthPrice'] ?? json['month_price']) ?? 0;
    final yearPriceRaw =
        _parseNum(json['yearPrice'] ?? json['year_price']) ?? 0;

    final monthPrice = monthPriceRaw > 0
        ? monthPriceRaw
        : (!isYearly && priceRaw > 0 ? priceRaw : 0);

    final yearPrice = yearPriceRaw > 0
        ? yearPriceRaw
        : (isYearly && priceRaw > 0
            ? priceRaw
            : (!isMonthly && priceRaw > 0 ? priceRaw : 0));

    final finalPrice = priceRaw > 0
        ? priceRaw
        : (monthPrice > 0 ? monthPrice : yearPrice);

    final activeVal = json['isActive'] ??
        json['is_active'] ??
        (json['status'] != null
            ? json['status'].toString().toUpperCase() == 'ACTIVE'
            : true);

    return WardrobePlan(
      id: id,
      categoryId: json['categoryId']?.toString() ??
          json['category_id']?.toString() ??
          json['catgory_id']?.toString() ??
          '',
      categoryName: _nonEmpty(json['categoryName'] ?? json['category_name']),
      name: name,
      planCode: json['planCode']?.toString() ??
          json['plan_code']?.toString() ??
          json['code']?.toString() ??
          '',
      planRef: _nonEmpty(json['planRef'] ?? json['plan_ref']) ??
          (id.isNotEmpty ? id : null) ??
          _nonEmpty(json['planCode'] ?? json['plan_code']) ??
          '',
      description: _nonEmpty(json['description']),
      durationDays: durationDays,
      maxGarments:
          _parseInt(json['maxGarments'] ?? json['max_garments']) ?? 0,
      noOfBookings:
          _parseInt(json['noOfBookings'] ?? json['no_of_bookings']) ?? 0,
      monthPrice: monthPrice,
      yearPrice: yearPrice,
      price: finalPrice,
      billingPeriod: resolvedBillingPeriod,
      features: features,
      displayOrder:
          _parseInt(json['displayOrder'] ?? json['display_order']) ?? 0,
      isActive: _parseBool(activeVal),
    );
  }
}

bool _parseBool(dynamic value) {
  if (value is bool) return value;
  if (value is int) return value != 0;
  if (value is String) {
    final lower = value.toLowerCase().trim();
    return lower == '1' || lower == 'true' || lower == 'active';
  }
  return true;
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

String? _nonEmpty(dynamic value) {
  final s = value?.toString().trim();
  return (s == null || s.isEmpty) ? null : s;
}
