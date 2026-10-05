class RefundStatusResult {
  final String status; // PENDING, APPROVED, REJECTED
  final String waitlistNumber;
  final String? message;
  final num? amount;
  final String? reason;
  final DateTime? createdAt;
  final Map<String, dynamic>? raw;

  const RefundStatusResult({
    required this.status,
    required this.waitlistNumber,
    this.message,
    this.amount,
    this.reason,
    this.createdAt,
    this.raw,
  });

  bool get isPending => status.toUpperCase() == 'PENDING';
  bool get isApproved => status.toUpperCase() == 'APPROVED';
  bool get isRejected => status.toUpperCase() == 'REJECTED';

  factory RefundStatusResult.fromJson(
    Map<String, dynamic> json,
    String idOrNumber,
  ) {
    final data = json['data'] is Map<String, dynamic>
        ? json['data'] as Map<String, dynamic>
        : (json['data'] is Map
            ? Map<String, dynamic>.from(json['data'])
            : json);

    final rawStatus = (data['status'] ?? json['status'] ?? 'PENDING')
        .toString()
        .toUpperCase();
    final waitlistNum = (data['waitlist_number'] ??
            data['waitlistNumber'] ??
            data['number'] ??
            data['id'] ??
            idOrNumber)
        .toString();

    num? parseNum(dynamic v) {
      if (v is num) return v;
      if (v is String) return num.tryParse(v);
      return null;
    }

    DateTime? parseDate(dynamic v) {
      if (v == null) return null;
      if (v is DateTime) return v;
      return DateTime.tryParse(v.toString());
    }

    return RefundStatusResult(
      status: rawStatus,
      waitlistNumber: waitlistNum,
      message: (json['message'] ?? data['message'])?.toString(),
      amount: parseNum(
        data['amount'] ?? data['totalAmount'] ?? data['total_amount'],
      ),
      reason: (data['reason'] ?? data['cancellation_reason'])?.toString(),
      createdAt: parseDate(data['createdAt'] ?? data['created_at']),
      raw: data,
    );
  }
}
