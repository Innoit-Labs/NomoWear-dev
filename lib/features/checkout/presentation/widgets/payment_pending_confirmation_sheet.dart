import 'package:nomowear/core/app_export.dart';

/// Displays a confirmation bottom sheet when payment is dismissed or incomplete,
/// offering the customer the choice to either retry payment or cancel the pending order.
Future<void> showPaymentPendingConfirmationSheet(
  BuildContext context, {
  required String orderId,
  int? amountRupees,
  required VoidCallback onRetry,
  required Future<void> Function() onCancel,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: const Color(0xFF16181D),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (modalContext) {
      bool isCancelling = false;

      return StatefulBuilder(
        builder: (context, setModalState) {
          return PopScope(
            canPop: !isCancelling,
            child: SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(20.w, 12.h, 20.w, 20.h),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Handle bar
                    Container(
                      width: 40.w,
                      height: 4.h,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                    SizedBox(height: 18.h),

                    // Alert Icon with glowing gold circle
                    Container(
                      width: 56.h,
                      height: 56.h,
                      decoration: BoxDecoration(
                        color: AppColours.primary.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColours.primary.withValues(alpha: 0.35),
                          width: 1.5,
                        ),
                      ),
                      child: Icon(
                        Icons.payment_outlined,
                        color: AppColours.primary,
                        size: 28,
                      ),
                    ),
                    SizedBox(height: 14.h),

                    // Title
                    Text(
                      'Payment Incomplete',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18.fSize,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 8.h),

                    // Subtitle / message
                    Text(
                      'Your payment was not completed and your order is currently pending. Would you like to retry payment or cancel this order to release the reserved items?',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13.fSize,
                        height: 1.4,
                      ),
                    ),

                    if (amountRupees != null && amountRupees > 0) ...[
                      SizedBox(height: 14.h),
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F1012),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Order Amount',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 13.fSize,
                              ),
                            ),
                            Row(
                              children: [
                                Text(
                                  '₹ $amountRupees',
                                  style: TextStyle(
                                    color: AppColours.primary,
                                    fontSize: 15.fSize,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                SizedBox(width: 8.w),
                                Container(
                                  padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                                  decoration: BoxDecoration(
                                    color: Colors.amber.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: Colors.amber.withValues(alpha: 0.5)),
                                  ),
                                  child: Text(
                                    'PENDING',
                                    style: TextStyle(
                                      color: Colors.amber,
                                      fontSize: 10.fSize,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],

                    SizedBox(height: 22.h),

                    // Button 1: Retry Payment (Primary)
                    SizedBox(
                      width: double.maxFinite,
                      height: 48.h,
                      child: ElevatedButton(
                        onPressed: isCancelling
                            ? null
                            : () {
                                Navigator.pop(modalContext);
                                onRetry();
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColours.primary,
                          disabledBackgroundColor: Colors.white24,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          elevation: 0,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.replay_rounded, color: Colors.black, size: 18),
                            SizedBox(width: 8.w),
                            Text(
                              'RETRY PAYMENT',
                              style: TextStyle(
                                color: Colors.black,
                                fontSize: 13.fSize,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: 10.h),

                    // Button 2: Cancel Order (Outlined danger)
                    SizedBox(
                      width: double.maxFinite,
                      height: 48.h,
                      child: OutlinedButton(
                        onPressed: isCancelling
                            ? null
                            : () async {
                                setModalState(() => isCancelling = true);
                                try {
                                  if (modalContext.mounted) {
                                    Navigator.pop(modalContext);
                                  }
                                  await onCancel();
                                } catch (_) {
                                  if (modalContext.mounted) {
                                    setModalState(() => isCancelling = false);
                                  }
                                }
                              },
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                            color: Colors.redAccent.withValues(alpha: 0.6),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: isCancelling
                            ? SizedBox(
                                width: 20.h,
                                height: 20.h,
                                child: const CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.redAccent,
                                ),
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.close_rounded,
                                    color: Colors.redAccent.shade100,
                                    size: 18,
                                  ),
                                  SizedBox(width: 8.w),
                                  Text(
                                    'CANCEL ORDER',
                                    style: TextStyle(
                                      color: Colors.redAccent.shade100,
                                      fontSize: 13.fSize,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );
}
