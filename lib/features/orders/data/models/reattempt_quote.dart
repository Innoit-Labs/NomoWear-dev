class ReattemptQuote {
  final String orderId;
  final num deliveryCharge;
  final num distanceKm;
  final bool isFreeReattempt;
  final num totalPayable;

  const ReattemptQuote({
    required this.orderId,
    this.deliveryCharge = 0,
    this.distanceKm = 0,
    this.isFreeReattempt = false,
    this.totalPayable = 0,
  });

  factory ReattemptQuote.fromJson(Map<String, dynamic> json) {
    num parseNum(dynamic value) {
      if (value is num) return value;
      if (value is String) return num.tryParse(value) ?? 0;
      return 0;
    }

    bool parseBool(dynamic value) {
      if (value is bool) return value;
      if (value is num) return value == 1;
      if (value is String) {
        final s = value.trim().toLowerCase();
        return s == 'true' || s == '1';
      }
      return false;
    }

    final dCharge = parseNum(json['deliveryCharge'] ?? json['delivery_charge']);
    final totPayable = parseNum(
      json['totalPayable'] ?? json['total_payable'] ?? dCharge,
    );

    return ReattemptQuote(
      orderId: (json['orderId'] ?? json['order_id'] ?? '').toString(),
      deliveryCharge: dCharge,
      distanceKm: parseNum(
        json['distance_km'] ?? json['distanceKm'] ?? json['distance'],
      ),
      isFreeReattempt: parseBool(
            json['isFreeReattempt'] ?? json['is_free_reattempt'],
          ) ||
          totPayable <= 0,
      totalPayable: totPayable,
    );
  }
}
