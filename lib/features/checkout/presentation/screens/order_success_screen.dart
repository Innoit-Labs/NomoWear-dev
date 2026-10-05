import 'package:flutter_svg/svg.dart';
import 'package:nomowear/core/app_export.dart';
import 'package:nomowear/features/checkout/data/wardrobe_booking_session.dart';
import 'package:nomowear/features/checkout/presentation/utils/wardrobe_booking_flow.dart';

class OrderSuccessScreen extends StatelessWidget {
  final String orderId;
  final String orderIdDisplay;
  final bool isSubscription;
  final bool continueToWardrobeKit;

  const OrderSuccessScreen({
    Key? key,
    this.orderId = "#NMW-829410",
    String? orderIdDisplay,
    this.isSubscription = false,
    this.continueToWardrobeKit = false,
  })  : orderIdDisplay = orderIdDisplay ?? orderId,
        super(key: key);

  Future<void> _leaveSuccessScreen(BuildContext context) async {
    // Wardrobe booking lifecycle ends when the user leaves order success.
    // Keep the session open when subscription purchase still requires kit setup.
    if (!continueToWardrobeKit) {
      await WardrobeBookingSession.instance.closeCurrentBooking();
    }

    if (!context.mounted) return;
    Navigator.pushNamedAndRemoveUntil(
      context,
      AppRoutes.homeScreen,
      (route) => false,
      arguments: const {
        'initialTabIndex': 0,
        'refreshHome': true,
        'refreshSource': 'payment_success',
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _leaveSuccessScreen(context);
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0B0C10),
        body: SafeArea(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 24.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(height: 180.h),
                SvgPicture.asset(IconConstant.success),
                Text(
                  "SUCCESS!",
                  style: CustomTextStyles.montserratBold.copyWith(
                    fontSize: 20,
                    letterSpacing: 1.5,
                  ),
                ),
                SizedBox(height: 12.h),
                Text(
                  isSubscription
                      ? "Your subscription has been activated successfully."
                      : "Your order has been placed successfully!",
                  textAlign: TextAlign.center,
                  style: CustomTextStyles.openSansRegular.copyWith(fontSize: 14),
                ),
                if (!isSubscription) ...[
                  SizedBox(height: 12.h),
                  Container(
                    width: double.maxFinite,
                    padding: EdgeInsets.symmetric(vertical: 22.h),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1D21).withOpacity(0.6),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.05),
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(
                          "ORDER ID",
                          style: CustomTextStyles.openSansRegular.copyWith(
                            fontSize: 12,
                            letterSpacing: 1.2,
                          ),
                        ),
                        SizedBox(height: 8.h),
                        Text(
                          orderIdDisplay,
                          style: CustomTextStyles.openSansBold.copyWith(
                            fontSize: 20,
                            color: AppColours.primary,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 40.h),
                  Container(
                    width: double.maxFinite,
                    height: 44.h,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppColours.primary.withOpacity(0.9),
                          AppColours.primary,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pushNamed(
                          context,
                          AppRoutes.orderTrackingScreen,
                          arguments: orderId,
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        "TRACK ORDER",
                        style: CustomTextStyles.montserratBold.copyWith(
                          fontSize: 14,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: 16.h),
                ] else ...[
                  SizedBox(height: 40.h),
                  if (continueToWardrobeKit) ...[
                    Container(
                      width: double.maxFinite,
                      height: 44.h,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppColours.primary.withOpacity(0.9),
                            AppColours.primary,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ElevatedButton(
                        onPressed: () {
                          WardrobeBookingFlow.continueToWardrobeKitAfterSubscription(
                            context,
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          "SET UP WARDROBE",
                          style: CustomTextStyles.montserratBold.copyWith(
                            fontSize: 14,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: 16.h),
                  ],
                ],
                SizedBox(
                  width: double.maxFinite,
                  height: 54.h,
                  child: OutlinedButton(
                    onPressed: () => _leaveSuccessScreen(context),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                        color: AppColours.primary.withOpacity(0.3),
                        width: 1.2,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      "BACK TO HOMESCREEN",
                      style: CustomTextStyles.montserratBold.copyWith(
                        fontSize: 14,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 48.h),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
