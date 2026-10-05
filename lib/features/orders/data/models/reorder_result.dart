class ReorderResult {
  final bool success;
  final bool paymentRequired;
  final String? razorpayOrderId;
  final String? razorpayKeyId;
  final int amount; // in paise
  final String currency;
  final String? message;
  final Map<String, dynamic>? data;

  const ReorderResult({
    required this.success,
    this.paymentRequired = false,
    this.razorpayOrderId,
    this.razorpayKeyId,
    this.amount = 0,
    this.currency = 'INR',
    this.message,
    this.data,
  });

  factory ReorderResult.fromJson(Map<String, dynamic> json) {
    final data = json['data'] is Map<String, dynamic>
        ? json['data'] as Map<String, dynamic>
        : (json['data'] is Map ? Map<String, dynamic>.from(json['data']) : json);

    bool parseBool(dynamic v) {
      if (v is bool) return v;
      if (v is num) return v == 1;
      if (v is String) {
        final s = v.trim().toLowerCase();
        return s == 'true' || s == '1';
      }
      return false;
    }

    final paymentReq = parseBool(
      data['paymentRequired'] ?? data['payment_required'],
    );
    final rzpOrderId = (data['razorpayOrderId'] ??
            data['razorpay_order_id'] ??
            data['orderId'] ??
            data['order_id'])
        ?.toString();
    final rzpKeyId = (data['razorpayKeyId'] ??
            data['razorpay_key_id'] ??
            data['keyId'] ??
            data['key_id'] ??
            json['keyId'] ??
            json['key_id'])
        ?.toString();

    final rawAmount = data['amount'] ?? json['amount'];
    int parsedAmount = 0;
    if (rawAmount is num) {
      parsedAmount = rawAmount.round();
    } else if (rawAmount is String) {
      final n = double.tryParse(rawAmount) ?? 0;
      parsedAmount = n.round();
    }

    return ReorderResult(
      success: json['success'] == true || data['success'] == true,
      paymentRequired:
          paymentReq || (rzpOrderId != null && rzpOrderId.isNotEmpty),
      razorpayOrderId: rzpOrderId,
      razorpayKeyId: rzpKeyId,
      amount: parsedAmount,
      currency: (data['currency'] ?? json['currency'] ?? 'INR').toString(),
      message: (json['message'] ?? data['message'])?.toString(),
      data: data,
    );
  }
}
