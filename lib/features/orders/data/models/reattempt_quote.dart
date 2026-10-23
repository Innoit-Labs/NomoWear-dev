class ReattemptQuote {
  final String orderId;
  final bool isFree;
  final num reattemptCharge;
  final num unpaidPreviousCharges;
  final num totalPayable;
  final String? membershipTierName;
  final bool isSubscriptionUser;
  final bool isPrimeCustomer;

  const ReattemptQuote({
    required this.orderId,
    this.isFree = false,
    this.reattemptCharge = 0,
    this.unpaidPreviousCharges = 0,
    this.totalPayable = 0,
    this.membershipTierName,
    this.isSubscriptionUser = false,
    this.isPrimeCustomer = false,
  });

  /// Free when the quote says so, or when nothing is payable.
  bool get isFreeReattempt => isFree || totalPayable <= 0;

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

    final total = parseNum(json['totalPayable'] ?? json['total_payable']);

    return ReattemptQuote(
      orderId: (json['orderId'] ?? json['order_id'] ?? '').toString(),
      isFree: parseBool(json['isFree'] ?? json['is_free']),
      reattemptCharge: parseNum(
        json['reattemptCharge'] ?? json['reattempt_charge'],
      ),
      unpaidPreviousCharges: parseNum(
        json['unpaidPreviousCharges'] ?? json['unpaid_previous_charges'],
      ),
      totalPayable: total,
      membershipTierName: (json['membershipTierName'] ??
              json['membership_tier_name'])
          ?.toString(),
      isSubscriptionUser: parseBool(
        json['isSubscriptionUser'] ?? json['is_subscription_user'],
      ),
      isPrimeCustomer: parseBool(
        json['isPrimeCustomer'] ?? json['is_prime_customer'],
      ),
    );
  }
}
