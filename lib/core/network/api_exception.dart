class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final String? code;
  final String? overdueOrderNumber;
  final Map<String, dynamic>? rawResponse;

  const ApiException(
    this.message, {
    this.statusCode,
    this.code,
    this.overdueOrderNumber,
    this.rawResponse,
  });

  bool get isNoReturnBlocked {
    if (code?.trim().toUpperCase() == 'NO_RETURN_BOOKING_BLOCKED') return true;
    final msg = message.toLowerCase();
    return msg.contains('no return') ||
        msg.contains('not been returned') ||
        msg.contains('previous order has not been returned') ||
        msg.contains('cannot place a new order');
  }

  @override
  String toString() => message;
}
