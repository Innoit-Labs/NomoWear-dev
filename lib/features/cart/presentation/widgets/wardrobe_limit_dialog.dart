import 'package:nomowear/core/app_export.dart';
import 'package:nomowear/core/utils/api_id_utils.dart';
import 'package:nomowear/features/cart/presentation/bloc/cart_bloc.dart';
import 'package:nomowear/features/cart/presentation/utils/cart_limits.dart';
import 'package:nomowear/features/cart/presentation/utils/cart_state_log.dart';
import 'package:nomowear/features/checkout/data/checkout_session.dart';
import 'package:nomowear/features/checkout/data/wardrobe_booking_session.dart';
import 'package:nomowear/features/home/presentation/bloc/home_bloc.dart';
import 'package:nomowear/features/home/presentation/screens/subscription_tab_widget.dart';
import 'package:nomowear/features/subscriptions/data/subscription_cache.dart';
import 'package:nomowear/features/subscriptions/data/subscription_garment_balance.dart';
import 'package:nomowear/features/products/data/product_cache.dart';
import 'package:flutter/foundation.dart';

Future<void> continueWithoutMembershipFromUnlock(BuildContext context) async {
  CheckoutSession.instance.clearWardrobeCategoryLock();
  CheckoutSession.instance.setDelivery(
    continueWithoutMembership: true,
    bookingMode: CheckoutBookingMode.oneTimeWardrobe,
  );
  await WardrobeBookingSession.instance.beginPaidRentalContinuation();

  CartState cart = const CartState();
  try {
    cart = context.read<CartBloc>().state;
  } catch (_) {}
  logCartState('ContinueWithoutMembership', cart);
  logMixedCart(cart);

  if (!context.mounted) return;
  try {
    context.read<HomeBloc>().add(ChangeBottomNavEvent(0));
  } catch (_) {}
  Navigator.pushNamedAndRemoveUntil(
    context,
    AppRoutes.homeScreen,
    (route) => false,
  );
}

Future<void> _continueWithoutMembershipFromLimitReached(BuildContext context, BuildContext dialogContext) async {
  Navigator.pop(dialogContext);

  CheckoutSession.instance.setDelivery(
    continueWithoutMembership: true,
    bookingMode: CheckoutBookingMode.oneTimeWardrobe,
  );
  
  await WardrobeBookingSession.instance.continuePaidRentalWithoutClearingCategory();

  final session = WardrobeBookingSession.instance;
  if (session.wardrobeCategory != null && session.wardrobeCategory!.isNotEmpty) {
    CheckoutSession.instance.lockNonSubWardrobeCategory(
      session.wardrobeCategory!,
      categoryId: session.wardrobeCategoryId,
    );
  }

  if (!context.mounted) return;
  try {
    context.read<HomeBloc>().add(ChangeBottomNavEvent(0));
  } catch (_) {}
  Navigator.pushNamedAndRemoveUntil(
    context,
    AppRoutes.homeScreen,
    (route) => false,
  );
}

Future<void> _clearPaidRental(
  BuildContext context,
  BuildContext dialogContext, {
  VoidCallback? onClearSuccess,
}) async {
  CartBloc? cartBloc;
  try {
    cartBloc = context.read<CartBloc>();
  } catch (_) {}

  Navigator.pop(dialogContext);

  cartBloc?.add(ClearPaidRentalItemsEvent());
  await WardrobeBookingSession.instance.onUnpaidNonSubscriptionCartCleared();

  if (onClearSuccess != null) {
    onClearSuccess();
  }
}

Widget _dialogShell({required List<Widget> children}) {
  return Dialog(
    backgroundColor: Colors.transparent,
    child: Container(
      width: double.maxFinite,
      padding: EdgeInsets.symmetric(horizontal: 18.w, vertical: 22.h),
      decoration: BoxDecoration(
        color: const Color(0xFF050816),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFE6C279).withOpacity(0.35),
            blurRadius: 20,
            spreadRadius: 1,
          ),
        ],
        border: Border.all(
          color: const Color(0xFFE6C279),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    ),
  );
}

Widget _primaryGradientButton({
  required String label,
  required VoidCallback onPressed,
}) {
  return SizedBox(
    width: double.maxFinite,
    height: 46.h,
    child: ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        elevation: 0,
        padding: EdgeInsets.zero,
        backgroundColor: Colors.transparent,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: const LinearGradient(
            colors: [
              Color(0xFFE6C27A),
              Color(0xFFD9B35F),
            ],
          ),
        ),
        child: Container(
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: Colors.black,
              fontSize: 13.fSize,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
        ),
      ),
    ),
  );
}

Widget _secondaryOutlinedButton({
  required String label,
  required VoidCallback onPressed,
}) {
  return SizedBox(
    width: double.maxFinite,
    height: 46.h,
    child: OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: Colors.white.withOpacity(0.55)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: Colors.white,
          fontSize: 12.fSize,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
        ),
      ),
    ),
  );
}

/// A compact benefit bullet row with a gold checkmark icon.
Widget _benefitRow(String text) {
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Icon(
        Icons.check_circle_rounded,
        color: Color(0xFFE6C27A),
        size: 16,
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          text,
          style: CustomTextStyles.openSansRegular.copyWith(
            fontSize: 12,
            color: Colors.white70,
            height: 1.4,
          ),
        ),
      ),
    ],
  );
}

/// Wardrobe kit garment cap reached (not subscription entitlement).
Future<void> showWardrobeLimitReachedDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.black.withOpacity(0.88),
    builder: (dialogContext) {
      return _dialogShell(
        children: [
          Text(
            'Limit reached',
            textAlign: TextAlign.center,
            style: CustomTextStyles.montserratBold.copyWith(
              fontSize: 20,
              color: AppColours.primary,
              letterSpacing: 0.6,
            ),
          ),
          SizedBox(height: 16.h),
          Text(
            'You’ve reached the maximum limit for garments and cannot add more.',
            textAlign: TextAlign.center,
            style: CustomTextStyles.openSansRegular.copyWith(
              fontSize: 13,
              color: Colors.white70,
              height: 1.35,
            ),
          ),
          SizedBox(height: 24.h),
          _primaryGradientButton(
            label: 'OK',
            onPressed: () => Navigator.pop(dialogContext),
          ),
        ],
      );
    },
  );
}

/// Subscription booking entitlement exhausted — upgrade or continue without membership.
Future<void> showUnlockFullAccessDialog(
  BuildContext context, {
  VoidCallback? onContinueWithoutMembership,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.black.withOpacity(0.88),
    builder: (dialogContext) {
      return _dialogShell(
        children: [
          Text(
            'UNLOCK FULL ACCESS',
            textAlign: TextAlign.center,
            style: CustomTextStyles.montserratBold.copyWith(
              fontSize: 20,
              color: AppColours.primary,
              letterSpacing: 0.6,
            ),
          ),
          SizedBox(height: 16.h),
          Text(
            'You\'re currently using the limited garment access available without a membership. Upgrade your membership to unlock more garments and wardrobe options.',
            textAlign: TextAlign.center,
            style: CustomTextStyles.openSansRegular.copyWith(
              fontSize: 13,
              color: Colors.white70,
              height: 1.35,
            ),
          ),
          SizedBox(height: 16.h),
          _benefitRow('Upgrade to unlock more garments and wardrobe options.'),
          SizedBox(height: 24.h),
          _primaryGradientButton(
            label: 'UPGRADE TO MEMBERSHIP',
            onPressed: () {
              Navigator.pop(dialogContext);
              _openSubscriptionPlans(context);
            },
          ),
          SizedBox(height: 12.h),
          _secondaryOutlinedButton(
            label: 'CONTINUE WITHOUT MEMBERSHIP',
            onPressed: () {
              Navigator.pop(dialogContext);
              if (onContinueWithoutMembership != null) {
                onContinueWithoutMembership();
                return;
              }
              continueWithoutMembershipFromUnlock(context);
            },
          ),
        ],
      );
    },
  );
}

/// Subscriber has exceeded their remaining garment balance for this booking period.
/// Shows the Unlock Full Access popup with the dynamic remaining count.
Future<void> showSubscriptionGarmentLimitDialog(
  BuildContext context, {
  required int remainingGarments,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.black.withOpacity(0.88),
    builder: (dialogContext) {
      return _dialogShell(
        children: [
          Text(
            'UNLOCK FULL ACCESS',
            textAlign: TextAlign.center,
            style: CustomTextStyles.montserratBold.copyWith(
              fontSize: 20,
              color: AppColours.primary,
              letterSpacing: 0.6,
            ),
          ),
          SizedBox(height: 16.h),
          Text(
            'You have reached your remaining garment limit. You have only $remainingGarments garment(s) remaining in your subscription.',
            textAlign: TextAlign.center,
            style: CustomTextStyles.openSansRegular.copyWith(
              fontSize: 13,
              color: Colors.white70,
              height: 1.45,
            ),
          ),
          SizedBox(height: 16.h),
          _benefitRow(
            'Upgrade your membership to get access to more garments and higher wardrobe limits.',
          ),
          SizedBox(height: 24.h),
          _primaryGradientButton(
            label: 'UPGRADE TO MEMBERSHIP',
            onPressed: () {
              Navigator.pop(dialogContext);
              _openSubscriptionPlans(context);
            },
          ),
          SizedBox(height: 12.h),
          _secondaryOutlinedButton(
            label: 'CONTINUE WITHOUT MEMBERSHIP',
            onPressed: () {
              Navigator.pop(dialogContext);
              _navigateToHome(context);
            },
          ),
        ],
      );
    },
  );
}

void _openSubscriptionPlans(BuildContext context) {
  try {
    context.read<HomeBloc>().add(
          ChangeBottomNavEvent(SubscriptionTabWidget.subscriptionTabIndex),
        );
  } catch (_) {
    Navigator.pushNamedAndRemoveUntil(
      context,
      AppRoutes.homeScreen,
      (route) => false,
      arguments: SubscriptionTabWidget.subscriptionTabIndex,
    );
  }
}

/// Navigate to the Home tab (index 0) after transitioning to the
/// "Continue Without Membership" path, so that:
///   - The next category selection skips the With/Without Subscription dialog
///   - The user goes directly to: Choose Wardrobe Kit → Products
///
/// Cart items are NOT cleared.
/// Uses beginPaidRentalContinuation() which keeps the non-subscription path
/// active while resetting kitSelected so the Kit screen is not skipped.
void _navigateToHome(BuildContext context) {
  // Mark the session as a non-subscription continuation:
  //  - selectedPath = withoutSubscription (skips path-selection dialog)
  //  - kitSelected = false (forces the Kit selection screen)
  //  - category cleared (user will pick a new one from Home)
  WardrobeBookingSession.instance.beginPaidRentalContinuation();

  // Also set continueWithoutMembership=true in CheckoutSession so
  // _startChooseFlow sees continuingPaidRental=true and goes straight to Kit.
  CheckoutSession.instance.setDelivery(
    continueWithoutMembership: true,
    bookingMode: CheckoutBookingMode.oneTimeWardrobe,
  );

  if (kDebugMode) {
    final hasSub = SubscriptionCache.instance.activeSubscription != null;
    debugPrint(
      '[WARDROBE_FLOW] CONTINUE_WITHOUT_MEMBERSHIP tapped\n'
      '  hasActiveSubscription=$hasSub\n'
      '  currentSelectionMode=WITHOUT_MEMBERSHIP\n'
      '  NOTE: subscription status unchanged, only this selection flow is non-sub',
    );
  }

  try {
    context.read<HomeBloc>().add(ChangeBottomNavEvent(0));
  } catch (_) {
    Navigator.pushNamedAndRemoveUntil(
      context,
      AppRoutes.homeScreen,
      (route) => false,
    );
  }
}

/// Non-subscriber tried to open / add from a different wardrobe category.
Future<void> showSingleCategoryRestrictionDialog(
  BuildContext context, {
  required String currentCategory,
  required String requestedCategory,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.black.withOpacity(0.88),
    builder: (dialogContext) {
      return CategoryLockedDialog(
        currentCategory: currentCategory,
        requestedCategory: requestedCategory,
        onGoToCart: () {
          Navigator.pop(dialogContext);
          Navigator.pushNamed(context, AppRoutes.cartScreen);
        },
        onContinue: () {
          Navigator.pop(dialogContext);
          Navigator.pushNamed(
            context,
            AppRoutes.wardrobeScreen,
            arguments: currentCategory,
          );
        },
      );
    },
  );
}

class CategoryLockedDialog extends StatelessWidget {
  final String currentCategory;
  final String requestedCategory;
  final VoidCallback onGoToCart;
  final VoidCallback onContinue;

  const CategoryLockedDialog({
    super.key,
    required this.currentCategory,
    required this.requestedCategory,
    required this.onGoToCart,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(horizontal: 24.w),
      child: Container(
        width: double.maxFinite,
        padding: EdgeInsets.all(24.w),
        decoration: BoxDecoration(
          color: const Color(0xFF050816),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFE6C279).withOpacity(0.35),
              blurRadius: 20,
              spreadRadius: 1,
            ),
          ],
          border: Border.all(
            color: const Color(0xFFE6C279),
            width: 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  color: AppColours.primary,
                  size: 28.w,
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'CATEGORY LOCKED',
                        style: CustomTextStyles.montserratBold.copyWith(
                          fontSize: 14,
                          color: AppColours.primary,
                          letterSpacing: 1.2,
                        ),
                      ),
                      SizedBox(height: 4.h),
                      Text(
                        'Single Category Only',
                        style: CustomTextStyles.montserratMedium.copyWith(
                          fontSize: 16,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Icon(Icons.close, color: Colors.white70, size: 24.w),
                ),
              ],
            ),
            SizedBox(height: 24.h),
            
            // Description
            RichText(
              text: TextSpan(
                style: CustomTextStyles.openSansRegular.copyWith(
                  fontSize: 14,
                  color: Colors.white70,
                  height: 1.5,
                ),
                children: [
                  const TextSpan(text: 'You\'re in '),
                  TextSpan(
                    text: 'Non-Subscription mode',
                    style: CustomTextStyles.openSansBold.copyWith(color: AppColours.primary),
                  ),
                  const TextSpan(text: ' with '),
                  TextSpan(
                    text: currentCategory,
                    style: CustomTextStyles.openSansBold.copyWith(color: Colors.white),
                  ),
                  const TextSpan(text: ' locked.\n\n'),
                  const TextSpan(text: 'To browse '),
                  TextSpan(
                    text: requestedCategory,
                    style: CustomTextStyles.openSansBold.copyWith(color: Colors.white),
                  ),
                  TextSpan(text: ', first remove all $currentCategory items from your cart, then start a new non-subscription order.'),
                ],
              ),
            ),
            SizedBox(height: 32.h),

            // Go to Cart Button — gold gradient (matching _primaryGradientButton)
            SizedBox(
              width: double.maxFinite,
              height: 46.h,
              child: ElevatedButton(
                onPressed: onGoToCart,
                style: ElevatedButton.styleFrom(
                  elevation: 0,
                  padding: EdgeInsets.zero,
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Ink(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: const LinearGradient(
                      colors: [
                        Color(0xFFE6C27A),
                        Color(0xFFD9B35F),
                      ],
                    ),
                  ),
                  child: Container(
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.shopping_bag_outlined, color: Colors.black, size: 20.w),
                        SizedBox(width: 8.w),
                        Text(
                          'GO TO CART',
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: 13.fSize,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2,
                          ),
                        ),
                        SizedBox(width: 8.w),
                        Icon(Icons.arrow_forward_rounded, color: Colors.black, size: 20.w),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(height: 24.h),

            // OR Divider
            Row(
              children: [
                Expanded(child: Divider(color: Colors.white.withOpacity(0.2), thickness: 1)),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16.w),
                  child: Text(
                    'OR',
                    style: CustomTextStyles.openSansSemiBold.copyWith(
                      fontSize: 12,
                      color: Colors.white38,
                    ),
                  ),
                ),
                Expanded(child: Divider(color: Colors.white.withOpacity(0.2), thickness: 1)),
              ],
            ),
            SizedBox(height: 24.h),

            // Continue Button
            GestureDetector(
              onTap: onContinue,
              behavior: HitTestBehavior.opaque,
              child: Container(
                alignment: Alignment.center,
                padding: EdgeInsets.symmetric(vertical: 8.h),
                child: Text(
                  'CONTINUE WITH ${currentCategory.toUpperCase()}',
                  textAlign: TextAlign.center,
                  style: CustomTextStyles.montserratBold.copyWith(
                    fontSize: 13,
                    color: Colors.white70,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

CartItem _resolveCartItemForAdd(CartItem item, CartState cartState) {
  final isKids = item.isKids || item.itemType == 'kids' || isKidsCategory(item.category);
  final isEssential = isKids || item.isEssential || item.itemType == 'essentials' || isEssentialCategory(item.category);
  if (isEssential) {
    return item.copyWith(
      isEssential: true,
      isKids: isKids,
      isSubscriptionGarment: false,
      itemType: isKids ? 'kids' : 'essentials',
    );
  }
  if (item.isSubscriptionGarment || item.itemType == 'subscription') {
    return item;
  }
  final existingPaid = cartState.lineForProduct(
    item.productId,
    variantId: item.variantId,
    isEssential: false,
    isSubscriptionGarment: false,
  );
  if (existingPaid != null &&
      !existingPaid.isKids &&
      existingPaid.itemType == 'non_subscription') {
    return item.copyWith(
      itemType: 'non_subscription',
      isSubscriptionGarment: false,
    );
  }
  if (!CartLimits.shouldAddAsSubscriptionGarment(item)) {
    return item.copyWith(
      itemType: 'non_subscription',
      isSubscriptionGarment: false,
    );
  }
  return item.copyWith(
    isSubscriptionGarment: true,
    itemType: 'subscription',
  );
}

bool checkWardrobeGarmentLimit(
  BuildContext context,
  CartState cartState,
  CartItem item, {
  int delta = 1,
}) {
  if (item.isEssential || item.isKids || isEssentialCategory(item.category)) {
    return true;
  }

  final isSubscription = item.isSubscriptionGarment || item.itemType == 'subscription';
  final kitLimit = CartLimits.currentKitGarmentLimit(cartState);
  final isSubscribed = CartLimits.hasActiveSubscriptionCached();
  final subRemaining = CartLimits.subscriptionRemainingEntitlement();

  if (isSubscription) {
    // 1. Subscription Booking Limit (if user has active subscription but exhausted period bookings)
    if (isSubscribed &&
        !CheckoutSession.instance.continueWithoutMembership &&
        !WardrobeBookingSession.instance.isWithoutSubscriptionPath &&
        CartLimits.isSubscriptionBookingLimitExhausted()) {
      logAddToCartLimitResult('BOOKING_LIMIT_REACHED');
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'You have exhausted your subscription bookings for this period.',
          ),
          backgroundColor: AppColours.primary,
        ),
      );
      return false;
    }

    // 2. Subscription Remaining Garments Limit (if remaining balance is less than kit limit)
    if (isSubscribed &&
        subRemaining != null &&
        subRemaining < kitLimit &&
        !CheckoutSession.instance.continueWithoutMembership &&
        !WardrobeBookingSession.instance.isWithoutSubscriptionPath) {
      final currentSubCount = cartState.subscriptionGarmentCount;
      if (currentSubCount + delta > subRemaining) {
        showSubscriptionGarmentLimitDialog(
          context,
          remainingGarments: subRemaining,
        );
        return false;
      }
    }

    // 3. Kit Max Garment Limit Check (Applies to Subscribers in subscription flow)
    final currentSubCount = cartState.subscriptionGarmentCount;
    if (kitLimit > 0 && currentSubCount + delta > kitLimit) {
      logAddToCartLimitResult('KIT_GARMENT_LIMIT_REACHED');
      showUnlockFullAccessDialog(context);
      return false;
    }
  } else {
    // Non-Subscription (Paid Rental) flow:
    // Validate the non-subscription garments count against the kit limit.
    final currentPaidCount = cartState.paidRentalGarmentCount;
    if (kitLimit > 0 && currentPaidCount + delta > kitLimit) {
      logAddToCartLimitResult('KIT_GARMENT_LIMIT_REACHED');
      showUnlockFullAccessDialog(context);
      return false;
    }
  }

  return true;
}

bool tryAddToCart(BuildContext context, CartItem item) {
  if (!isApiUuid(item.productId)) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'This product cannot be ordered. Please add items from the loaded catalog.',
        ),
      ),
    );
    return false;
  }

  final cartBloc = context.read<CartBloc>();
  final cartState = cartBloc.state;
  final resolvedItem = _resolveCartItemForAdd(item, cartState);

  final violatesCategory = CartLimits.wouldViolateSingleCategoryRule(
    cartState,
    incomingCategory: resolvedItem.category,
    isEssential: resolvedItem.isEssential,
    isSubscriptionGarment: resolvedItem.isSubscriptionGarment,
  );

  String? actualLockedCategory;
  for (final i in cartState.wardrobeItems) {
    final cat = CartLimits.mapToHomeWardrobeKey(i.category);
    if (cat != null) {
      actualLockedCategory = cat;
      break;
    }
  }
  if (actualLockedCategory == null) {
    for (final i in cartState.items) {
      if (i.isEssential || i.isKids || isEssentialCategory(i.category)) continue;
      final cat = CartLimits.mapToHomeWardrobeKey(i.category);
      if (cat != null) {
        actualLockedCategory = cat;
        break;
      }
    }
  }

  final incomingCat = resolvedItem.category;
  final explicitConflict = actualLockedCategory != null && incomingCat != null && incomingCat.isNotEmpty && !CartLimits.categoriesMatch(actualLockedCategory, incomingCat);

  if (violatesCategory || (explicitConflict && !resolvedItem.isEssential)) {
    final locked = actualLockedCategory ?? CartLimits.lockedWardrobeCategory(cartState) ?? 'Another Category';
    final incoming = incomingCat ?? 'the new category';
    showSingleCategoryRestrictionDialog(
      context,
      currentCategory: locked,
      requestedCategory: incoming,
    );
    return false;
  }

  logAddToCartLimitDebug(cartState);
  logSubCartLimit(cartState, resolvedItem);

  // ─── UNIFIED WARDROBE GARMENT LIMIT VALIDATION ───
  // Non-essential / rental garments count towards the active Wardrobe Kit max limit.
  if (!resolvedItem.isEssential && !resolvedItem.isKids) {
    if (!checkWardrobeGarmentLimit(context, cartState, resolvedItem, delta: 1)) {
      return false;
    }
  }

  logAddToCartLimitResult('ALLOWED');

  if (cartState.isVariantOutOfStock(
    productId: resolvedItem.productId,
    variantId: resolvedItem.variantId,
    itemType: resolvedItem.itemType,
  )) {
    return false;
  }

  final existing = cartState.lineForProduct(
    resolvedItem.productId,
    variantId: resolvedItem.variantId,
    itemType: resolvedItem.itemType,
  );
  final lineId = existing?.id ?? resolvedItem.id;
  if (cartState.isLinePending(lineId) ||
      cartState.isProductPending(
        productId: resolvedItem.productId,
        variantId: resolvedItem.variantId,
        itemType: resolvedItem.itemType,
      )) {
    return false;
  }

  if (existing != null) {
    final product = ProductCache.instance.findById(existing.productId);
    if (product != null && existing.variantId != null) {
      final vId = existing.variantId!.trim();
      if (vId.isNotEmpty) {
        for (final v in product.variants) {
          if (v.id == vId) {
            if (v.stockOnHand > 0 && existing.quantity >= v.stockOnHand) {
              ScaffoldMessenger.of(context).clearSnackBars();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Only ${v.stockOnHand} items available in stock.'),
                  backgroundColor: AppColours.primary,
                ),
              );
              return false;
            }
            break;
          }
        }
      }
    }

    cartBloc.add(AdjustCartItemQuantityEvent(existing.id, delta: 1));
  } else {
    cartBloc.add(AddToCartEvent(resolvedItem));
  }
  return true;
}

/// Call when returning from membership upgrade so entitlement reflects the new plan.
Future<void> refreshSubscriptionEntitlementAfterUpgrade() async {
  await SubscriptionGarmentBalance.resolveAndCache(forceRefresh: true);
}
