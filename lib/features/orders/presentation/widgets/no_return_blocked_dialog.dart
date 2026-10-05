import 'package:flutter/material.dart';
import 'package:nomowear/core/app_export.dart';

/// Shows the "NO RETURN = NO NEXT DISPATCH" blocking dialog when order placement
/// or wardrobe booking is rejected because a previous order hasn't been returned.
Future<void> showNoReturnBlockedDialog(
  BuildContext context, {
  String? overdueOrderNumber,
  String? message,
}) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogCtx) => _NoReturnBlockedDialog(
      overdueOrderNumber: overdueOrderNumber,
      message: message,
    ),
  );
}

class _NoReturnBlockedDialog extends StatelessWidget {
  final String? overdueOrderNumber;
  final String? message;

  const _NoReturnBlockedDialog({
    this.overdueOrderNumber,
    this.message,
  });

  @override
  Widget build(BuildContext context) {
    final cleanOrderNumber = overdueOrderNumber?.trim();
    final cleanMessage = message?.trim();

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 24.h),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF14161E),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: const Color(0xFFEF4444).withValues(alpha: 0.6),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.7),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
            BoxShadow(
              color: const Color(0xFFEF4444).withValues(alpha: 0.15),
              blurRadius: 20,
              spreadRadius: 2,
            ),
          ],
        ),
        padding: EdgeInsets.all(20.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Warning Icon with animated pulse glow look
            Container(
              width: 58.w,
              height: 58.w,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                border: Border.all(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.5),
                  width: 2,
                ),
              ),
              child: const Center(
                child: Icon(
                  Icons.report_problem_rounded,
                  color: Color(0xFFEF4444),
                  size: 30,
                ),
              ),
            ),
            SizedBox(height: 14.h),

            // Policy Tag
            Container(
              padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
              decoration: BoxDecoration(
                color: const Color(0xFF2B1315),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.3),
                ),
              ),
              child: Text(
                'NO RETURN = NO NEXT DISPATCH',
                style: TextStyle(
                  color: const Color(0xFFF87171),
                  fontSize: 10.fSize,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                ),
              ),
            ),
            SizedBox(height: 10.h),

            // Title
            Text(
              'Dispatch Hold Active',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 18.fSize,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 10.h),

            // Overdue Order banner if available
            if (cleanOrderNumber != null && cleanOrderNumber.isNotEmpty) ...[
              Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                decoration: BoxDecoration(
                  color: const Color(0xFF1B1D26),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: const Color(0xFFD8B26A).withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.inventory_2_outlined,
                      color: Color(0xFFD8B26A),
                      size: 16,
                    ),
                    SizedBox(width: 8.w),
                    Flexible(
                      child: Text(
                        'Overdue Order: $cleanOrderNumber',
                        style: TextStyle(
                          color: const Color(0xFFD8B26A),
                          fontSize: 12.5.fSize,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 12.h),
            ],

            // Detailed explanation
            Text(
              cleanMessage != null && cleanMessage.isNotEmpty
                  ? cleanMessage
                  : 'Your previous order has not been returned. Under our policy, new bookings and order dispatches are currently paused until your active kit is returned.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white70,
                fontSize: 13.fSize,
                height: 1.45,
              ),
            ),
            SizedBox(height: 8.h),
            Text(
              'Please schedule a return pickup to unlock new wardrobe bookings.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white38,
                fontSize: 11.5.fSize,
              ),
            ),
            SizedBox(height: 22.h),

            // Primary Action: View Orders / Return
            SizedBox(
              width: double.infinity,
              height: 46.h,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.pushNamed(context, AppRoutes.myOrdersScreen);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD8B26A),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 2,
                ),
                icon: const Icon(Icons.keyboard_return_rounded, size: 18),
                label: Text(
                  'View Order & Schedule Return',
                  style: TextStyle(
                    fontSize: 13.fSize,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            SizedBox(height: 10.h),

            // Secondary: Dismiss
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'I Understand',
                style: TextStyle(
                  color: Colors.white60,
                  fontSize: 12.5.fSize,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
