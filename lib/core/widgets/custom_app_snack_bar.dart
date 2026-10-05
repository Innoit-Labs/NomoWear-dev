import 'package:nomowear/core/app_export.dart';

enum SnackBarType { success, error, info, warning }

class CustomAppSnackBar {
  static final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  static void show(
    BuildContext? context, {
    required String message,
    String? title,
    SnackBarType type = SnackBarType.success,
    Duration duration = const Duration(seconds: 3),
  }) {
    final messenger =
        (context != null ? ScaffoldMessenger.maybeOf(context) : null) ??
            scaffoldMessengerKey.currentState;
    if (messenger == null) return;

    messenger.hideCurrentSnackBar();

    Color accentColor;
    Color iconBgColor;
    IconData iconData;

    switch (type) {
      case SnackBarType.success:
        accentColor = AppColours.primary;
        iconBgColor = AppColours.primary.withValues(alpha: 0.18);
        iconData = Icons.check_circle_rounded;
        break;
      case SnackBarType.error:
        accentColor = const Color(0xFFEF5350);
        iconBgColor = const Color(0xFFEF5350).withValues(alpha: 0.18);
        iconData = Icons.error_outline_rounded;
        break;
      case SnackBarType.warning:
        accentColor = AppColours.primary;
        iconBgColor = AppColours.primary.withValues(alpha: 0.18);
        iconData = Icons.warning_amber_rounded;
        break;
      case SnackBarType.info:
        accentColor = AppColours.primary;
        iconBgColor = AppColours.primary.withValues(alpha: 0.18);
        iconData = Icons.info_outline_rounded;
        break;
    }

    final snackBar = SnackBar(
      elevation: 0,
      behavior: SnackBarBehavior.floating,
      backgroundColor: Colors.transparent,
      padding: EdgeInsets.zero,
      margin: EdgeInsets.symmetric(horizontal: 16.w, vertical: 18.h),
      duration: duration,
      content: Container(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
        decoration: BoxDecoration(
          color: const Color(0xFF16181D),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: accentColor.withValues(alpha: 0.6),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.65),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
            BoxShadow(
              color: accentColor.withValues(alpha: 0.15),
              blurRadius: 12,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(7.w),
              decoration: BoxDecoration(
                color: iconBgColor,
                shape: BoxShape.circle,
                border: Border.all(
                  color: accentColor.withValues(alpha: 0.5),
                  width: 1,
                ),
              ),
              child: Icon(
                iconData,
                color: accentColor,
                size: 20.w,
              ),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title != null && title.isNotEmpty) ...[
                    Text(
                      title,
                      style: CustomTextStyles.montserratBold.copyWith(
                        fontSize: 13,
                        color: accentColor,
                        letterSpacing: 0.5,
                      ),
                    ),
                    SizedBox(height: 2.h),
                  ],
                  Text(
                    message,
                    style: CustomTextStyles.openSansRegular.copyWith(
                      fontSize: 13,
                      color: AppColours.secondary,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: 8.w),
            GestureDetector(
              onTap: () => messenger.hideCurrentSnackBar(),
              child: Padding(
                padding: EdgeInsets.all(4.w),
                child: Icon(
                  Icons.close_rounded,
                  color: AppColours.primary.withValues(alpha: 0.6),
                  size: 18.w,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    messenger.showSnackBar(snackBar);
  }

  static void showSuccess(
    BuildContext? context,
    String message, {
    String? title,
    Duration duration = const Duration(seconds: 3),
  }) {
    show(
      context,
      message: message,
      title: title,
      type: SnackBarType.success,
      duration: duration,
    );
  }

  static void showError(
    BuildContext? context,
    String message, {
    String? title,
    Duration duration = const Duration(seconds: 4),
  }) {
    show(
      context,
      message: message,
      title: title,
      type: SnackBarType.error,
      duration: duration,
    );
  }

  static void showInfo(
    BuildContext? context,
    String message, {
    String? title,
    Duration duration = const Duration(seconds: 3),
  }) {
    show(
      context,
      message: message,
      title: title,
      type: SnackBarType.info,
      duration: duration,
    );
  }

  static void showWarning(
    BuildContext? context,
    String message, {
    String? title,
    Duration duration = const Duration(seconds: 3),
  }) {
    show(
      context,
      message: message,
      title: title,
      type: SnackBarType.warning,
      duration: duration,
    );
  }
}
