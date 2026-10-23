import 'package:nomowear/features/plans/data/plan_price_formatter.dart';

class ActiveSubscription {
  const ActiveSubscription({
    required this.id,
    required this.planRef,
    required this.planStatus,
    required this.planName,
    required this.kitDurationDays,
    required this.maxGarments,
    required this.noOfBookings,
    required this.planPrice,
    required this.billingPeriod,
    this.bookingsUsed,
    this.remainingBookings,
    this.usedGarments,
    this.remainingGarments,
    this.remainingKitDays,
    this.startDate,
    this.endDate,
    this.nextRenewalDate,
    this.createdAt,
    this.features = const [],
  });

  final String id;
  final String planRef;
  final String planStatus;
  final String planName;
  final int kitDurationDays;
  final int maxGarments;
  final int noOfBookings;
  final String planPrice;
  final String billingPeriod;
  final int? bookingsUsed;
  final int? remainingBookings;
  /// Garments already consumed in this subscription period (API, when present).
  final int? usedGarments;
  /// Garments still available in this subscription period (API, when present).
  final int? remainingGarments;
  /// Remaining days allowed for wardrobe kits (API, when present).
  final int? remainingKitDays;
  final String? startDate;
  final String? endDate;
  final String? nextRenewalDate;
  final String? createdAt;
  final List<String> features;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'planRef': planRef,
      'planStatus': planStatus,
      'planName': planName,
      'kitDurationDays': kitDurationDays,
      'maxGarments': maxGarments,
      'noOfBookings': noOfBookings,
      'planPrice': planPrice,
      'billingPeriod': billingPeriod,
      if (bookingsUsed != null) 'bookingsUsed': bookingsUsed,
      if (remainingBookings != null) 'remainingBookings': remainingBookings,
      if (usedGarments != null) 'usedGarments': usedGarments,
      if (remainingGarments != null) 'remainingGarments': remainingGarments,
      if (remainingKitDays != null) 'remainingKitDays': remainingKitDays,
      if (startDate != null) 'startDate': startDate,
      if (endDate != null) 'endDate': endDate,
      if (nextRenewalDate != null) 'nextRenewalDate': nextRenewalDate,
      if (createdAt != null) 'createdAt': createdAt,
      'features': features,
    };
  }

  @override
  String toString() =>
      'ActiveSubscription(id: $id, planName: $planName, status: $planStatus, price: $planPrice, billingPeriod: $billingPeriod, bookings: $bookingsUsed/$noOfBookings, garments: $usedGarments/$maxGarments, startDate: $startDate, endDate: $endDate)';

  DateTime? get sortDate {
    for (final iso in [createdAt, startDate, endDate]) {
      if (iso == null || iso.isEmpty) continue;
      try {
        return DateTime.parse(iso);
      } catch (_) {}
    }
    return null;
  }

  /// The single subscription that should be treated as the customer's current plan.
  static ActiveSubscription? pickCurrent(
    Iterable<ActiveSubscription> subscriptions,
  ) {
    final active = subscriptions.where((s) => s.isActive).toList();
    if (active.isEmpty) return null;
    active.sort(compareByRecency);
    return active.first;
  }

  static int compareByRecency(ActiveSubscription a, ActiveSubscription b) {
    final aDate = a.sortDate;
    final bDate = b.sortDate;
    if (aDate != null && bDate != null) {
      final byDate = bDate.compareTo(aDate);
      if (byDate != 0) return byDate;
    } else if (aDate != null) {
      return -1;
    } else if (bDate != null) {
      return 1;
    }
    return b.id.compareTo(a.id);
  }

  bool get isActive {
    final status = planStatus.trim().toUpperCase();
    if (status == 'ACTIVE') return true;
    if (status == 'CANCELLED' ||
        status == 'EXPIRED' ||
        status == 'INACTIVE') {
      return false;
    }
    // Active endpoint returned a record — treat as active unless explicitly inactive.
    return id.isNotEmpty;
  }

  bool get shouldDisplay => id.isNotEmpty && isActive;

  bool get hasRemainingBookings {
    final exhausted = isBookingLimitExhausted;
    if (exhausted != null) return !exhausted;
    return noOfBookings > 0;
  }

  /// true = remaining bookings are known to be 0.
  /// false = remaining bookings are known to be > 0.
  /// null = backend did not send enough fields — do NOT treat as 0.
  bool? get isBookingLimitExhausted {
    final remaining = remainingBookings;
    if (remaining != null) return remaining <= 0;

    final used = bookingsUsed;
    if (used != null && noOfBookings > 0) return used >= noOfBookings;

    return null;
  }

  int get remainingBookingsCount {
    final explicitRemaining = remainingBookings;
    if (explicitRemaining != null) {
      return explicitRemaining < 0 ? 0 : explicitRemaining;
    }

    final used = bookingsUsed;
    if (used != null) return (noOfBookings - used).clamp(0, noOfBookings);

    return noOfBookings < 0 ? 0 : noOfBookings;
  }

  /// Completed bookings in this period from API fields only (never incremented locally).
  int get usedBookingsCount {
    final used = bookingsUsed;
    if (used != null) return used < 0 ? 0 : used;

    final remaining = remainingBookings;
    if (remaining != null) {
      return (noOfBookings - remaining).clamp(0, noOfBookings < 0 ? 0 : noOfBookings);
    }
    return 0;
  }

  /// Remaining garments from API fields only (null when backend did not send usage).
  int? get apiRemainingGarments {
    final explicit = remainingGarments;
    if (explicit != null) return explicit.clamp(0, maxGarments < 0 ? 0 : maxGarments);

    final used = usedGarments;
    if (used != null) {
      final max = maxGarments < 0 ? 0 : maxGarments;
      return (max - used).clamp(0, max);
    }
    return null;
  }

  bool get hasRemainingGarmentsFromApi {
    final remaining = apiRemainingGarments;
    if (remaining == null) return true;
    return remaining > 0;
  }

  bool get isMonthly => billingPeriod.toLowerCase() == 'monthly';

  String get displayTitle {
    final name = planName.trim().toUpperCase();
    if (name.contains('MEMBERSHIP')) return name;
    return '$name MEMBERSHIP';
  }

  String get formattedPrice {
    final amount = num.tryParse(planPrice) ?? 0;
    final periodLabel = isMonthly ? 'month' : 'year';
    return '₹${PlanPriceFormatter.format(amount)} / $periodLabel';
  }

  String get expiryLabel {
    final formatted = formatDisplayDate(endDate ?? nextRenewalDate);
    if (formatted.isEmpty) return '';
    return 'Expires on $formatted';
  }

  factory ActiveSubscription.fromJson(Map<String, dynamic> json) {
    final usage = json['usage'] is Map
        ? Map<String, dynamic>.from(json['usage'] as Map)
        : const <String, dynamic>{};
    final bookingUsage = usage['bookings'] is Map
        ? Map<String, dynamic>.from(usage['bookings'] as Map)
        : const <String, dynamic>{};
    final garmentUsage = usage['garments'] is Map
        ? Map<String, dynamic>.from(usage['garments'] as Map)
        : const <String, dynamic>{};

    return ActiveSubscription(
      id: json['id']?.toString() ?? '',
      planRef: json['planRef']?.toString() ??
          json['plan_ref']?.toString() ??
          '',
      planStatus: json['planStatus']?.toString() ??
          json['plan_status']?.toString() ??
          json['status']?.toString() ??
          '',
      planName: json['planName']?.toString() ??
          json['plan_name']?.toString() ??
          'Membership',
      kitDurationDays: _parseInt(
            json['totalPlanDays'] ??
                json['total_plan_days'] ??
                json['kitDurationDays'] ??
                json['kit_duration_days'],
          ) ??
          0,
      maxGarments:
          _parseInt(
            json['maxGarments'] ??
                json['max_garments'] ??
                json['totalPlanGarments'] ??
                json['total_plan_garments'] ??
                garmentUsage['total'],
          ) ??
          0,
      noOfBookings:
          _parseInt(
            json['noOfBookings'] ??
                json['no_of_bookings'] ??
                json['maxBookings'] ??
                json['max_bookings'] ??
                json['totalBookings'] ??
                json['total_bookings'] ??
                bookingUsage['total'] ??
                usage['totalBookings'],
          ) ??
          0,
      planPrice: json['planPrice']?.toString() ??
          json['plan_price']?.toString() ??
          '0',
      billingPeriod: json['billingPeriod']?.toString() ??
          json['billing_period']?.toString() ??
          'monthly',
      bookingsUsed: _parseInt(
        json['bookingsUsed'] ??
            json['bookings_used'] ??
            json['usedBookings'] ??
            json['used_bookings'] ??
            json['completedBookings'] ??
            json['completed_bookings'] ??
            bookingUsage['used'] ??
            usage['bookingsUsed'],
      ),
      remainingBookings: _parseInt(
        json['remainingBookings'] ??
            json['remaining_bookings'] ??
            json['bookingsRemaining'] ??
            json['bookings_remaining'] ??
            bookingUsage['remaining'] ??
            usage['remainingBookings'],
      ),
      usedGarments: _parseInt(
        json['usedGarments'] ??
            json['used_garments'] ??
            json['garmentsUsed'] ??
            json['garments_used'] ??
            garmentUsage['used'] ??
            usage['usedGarments'],
      ),
      remainingGarments: _parseInt(
        json['remainingGarments'] ??
            json['remaining_garments'] ??
            json['garmentsRemaining'] ??
            json['garments_remaining'] ??
            garmentUsage['remaining'] ??
            usage['remainingGarments'],
      ),
      remainingKitDays: _parseInt(
        json['remainingKitDays'] ??
            json['remaining_kit_days'] ??
            usage['remainingKitDays'],
      ),
      startDate: _nonEmpty(json['startDate'] ?? json['start_date']),
      endDate: _nonEmpty(json['endDate'] ?? json['end_date']),
      nextRenewalDate:
          _nonEmpty(json['nextRenewalDate'] ?? json['next_renewal_date']),
      createdAt: _nonEmpty(json['createdAt'] ?? json['created_at']),
      features: _parseFeatures(
        json['features'] ??
            json['plan_features'] ??
            json['planFeatures'] ??
            (json['plan'] is Map ? (json['plan']['features'] ?? json['plan']['plan_features']) : null),
      ),
    );
  }

  static List<String> _parseFeatures(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .map((e) => e?.toString().trim() ?? '')
        .where((e) => e.isNotEmpty)
        .toList();
  }

  static String formatDisplayDate(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    try {
      final dt = DateTime.parse(iso).toLocal();
      const months = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
    } catch (_) {
      return iso;
    }
  }
}

int? _parseInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

String? _nonEmpty(dynamic value) {
  final s = value?.toString().trim();
  return (s == null || s.isEmpty) ? null : s;
}
