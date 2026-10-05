import 'package:flutter/material.dart';
import 'package:nomowear/features/auth/presentation/screens/splash_screen.dart';
import 'package:nomowear/features/auth/presentation/screens/login_screen.dart';
import 'package:nomowear/features/auth/presentation/screens/otp_screen.dart';
import 'package:nomowear/features/profile/presentation/screens/profile_screen.dart';
import 'package:nomowear/features/profile/presentation/screens/edit_profile_screen.dart';
import 'package:nomowear/features/home/presentation/screens/home_screen.dart';
import 'package:nomowear/features/notifications/presentation/screens/notifications_screen.dart';
import 'package:nomowear/features/categories/presentation/screens/categories_screen.dart';
import 'package:nomowear/features/wardrobe/presentation/screens/wardrobe_screen.dart';
import 'package:nomowear/features/auth/presentation/screens/choose_your_wardrobe_kit_screen.dart';
import 'package:nomowear/features/auth/presentation/screens/add_new_address_screen.dart';
import 'package:nomowear/features/auth/presentation/screens/select_address_screen.dart';
import 'package:nomowear/features/profile/presentation/screens/membership_purchase_screen.dart';
import 'package:nomowear/features/profile/presentation/screens/membership_upgrade_screen.dart';
import 'package:nomowear/features/checkout/presentation/screens/order_success_screen.dart';
import 'package:nomowear/features/checkout/presentation/screens/order_tracking_screen.dart';
import 'package:nomowear/features/profile/presentation/screens/about_us_screen.dart';
import 'package:nomowear/features/profile/presentation/screens/privacy_policy_screen.dart';
import 'package:nomowear/features/profile/presentation/screens/help_support_screen.dart';
import 'package:nomowear/features/profile/presentation/screens/terms_conditions_screen.dart';
import 'package:nomowear/features/favorites/presentation/screens/favorites_screen.dart';
import 'package:nomowear/features/cart/presentation/screens/cart_screen.dart';
import 'package:nomowear/features/checkout/presentation/screens/essentials_checkout_screen.dart';
import 'package:nomowear/features/checkout/presentation/utils/checkout_pricing.dart';
import 'package:nomowear/features/profile/presentation/screens/my_subscriptions_screen.dart';
import 'package:nomowear/features/profile/presentation/screens/my_orders_screen.dart';
import 'package:nomowear/features/profile/presentation/screens/my_addresses_screen.dart';
import 'package:nomowear/features/profile/presentation/screens/order_details_screen.dart';
import 'package:nomowear/features/profile/presentation/screens/return_order_screen.dart';
import 'package:nomowear/features/profile/domain/saved_address.dart';






class AppRoutes {
  static const String splashScreen = '/splash_screen';
  static const String loginScreen = '/login_screen';
  static const String otpScreen = '/otp_screen';
  static const String profileScreen = '/profile_screen';
  static const String editProfileScreen = '/edit_profile_screen';
  static const String homeScreen = '/home_screen';
  static const String notificationsScreen = '/notifications_screen';
  static const String categoriesScreen = '/categories_screen';
  static const String wardrobeScreen = '/wardrobe_screen';
  static const String chooseYourWardrobeKitScreen = '/choose_your_wardrobe_kit_screen';
  static const String screenshotScreen = chooseYourWardrobeKitScreen;
  static const String addNewAddressScreen = '/add_new_address_screen';
  static const String selectAddressScreen = '/select_address_screen';
  static const String membershipPurchaseScreen = '/membership_purchase_screen';
  static const String membershipUpgradeScreen = '/membership_upgrade_screen';
  static const String orderSuccessScreen = '/order_success_screen';
  static const String orderTrackingScreen = '/order_tracking_screen';
  static const String aboutUsScreen = '/about_us_screen';
  static const String privacyPolicyScreen = '/privacy_policy_screen';
  static const String helpSupportScreen = '/help_support_screen';
  static const String termsConditionsScreen = '/terms_conditions_screen';
  static const String favoritesScreen = '/favorites_screen';
  static const String cartScreen = '/cart_screen';
  static const String essentialsCheckoutScreen = '/essentials_checkout_screen';
  static const String mySubscriptionsScreen = '/my_subscriptions_screen';
  static const String myOrdersScreen = '/my_orders_screen';
  static const String myAddressesScreen = '/my_addresses_screen';
  static const String orderDetailsScreen = '/order_details_screen';
  static const String returnOrderScreen = '/return_order_screen';






  static Map<String, WidgetBuilder> routes = {
    splashScreen: SplashScreen.builder,
    loginScreen: (context) => const LoginScreen(),
    otpScreen: (context) => const OtpScreen(),
    profileScreen: (context) => const ProfileScreen(),
    editProfileScreen: (context) => const EditProfileScreen(),
    homeScreen: (context) {
      final args = ModalRoute.of(context)?.settings.arguments;
      var initialTabIndex = 0;
      var refreshHomeOnEnter = false;
      var refreshSource = 'navigation';
      if (args is int) {
        initialTabIndex = args;
      } else if (args is Map) {
        final tab = args['initialTabIndex'];
        if (tab is int) initialTabIndex = tab;
        refreshHomeOnEnter = args['refreshHome'] == true;
        final source = args['refreshSource']?.toString().trim();
        if (source != null && source.isNotEmpty) {
          refreshSource = source;
        }
      }
      return HomeScreen(
        initialTabIndex: initialTabIndex,
        refreshHomeOnEnter: refreshHomeOnEnter,
        refreshSource: refreshSource,
      );
    },
    notificationsScreen: (context) => const NotificationsScreen(),
    categoriesScreen: (context) => const CategoriesScreen(),
    wardrobeScreen: (context) {
      final category =
          ModalRoute.of(context)!.settings.arguments as String? ?? '';
      return WardrobeScreen(category: category);
    },
    chooseYourWardrobeKitScreen: (context) {
      final category =
          ModalRoute.of(context)!.settings.arguments as String? ?? '';
      return ChooseYourWardrobeKitScreen(wardrobeCategory: category);
    },
    addNewAddressScreen: (context) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is SavedAddress) {
        return AddNewAddressScreen(initialAddress: args);
      }
      if (args is Map) {
        double? readCoord(dynamic value) {
          if (value is double) return value;
          if (value is num) return value.toDouble();
          if (value is String) return double.tryParse(value);
          return null;
        }

        return AddNewAddressScreen(
          initialLocationDetails: args['locationDetails']?.toString(),
          initialAreaTitle: args['areaTitle']?.toString(),
          initialLatitude: readCoord(args['latitude']),
          initialLongitude: readCoord(args['longitude']),
          initialBuildingNumber: args['buildingNumber']?.toString(),
          initialStreetName: args['streetName']?.toString(),
        );
      }
      return const AddNewAddressScreen();
    },
    selectAddressScreen: (context) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is Map) {
        double? readCoord(dynamic value) {
          if (value is double) return value;
          if (value is num) return value.toDouble();
          if (value is String) return double.tryParse(value);
          return null;
        }

        return SelectAddressScreen(
          initialLatitude: readCoord(args['latitude']),
          initialLongitude: readCoord(args['longitude']),
        );
      }
      return const SelectAddressScreen();
    },
    membershipPurchaseScreen: (context) {
      final args =
          ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>? ??
              {};
      final period = args['period']?.toString() ?? 'year';
      return MembershipPurchaseScreen(
        planRef: args['planRef']?.toString() ??
            args['planId']?.toString() ??
            '',
        planId: args['planId']?.toString() ??
            args['planRef']?.toString() ??
            '',
        planTitle: args['title']?.toString() ?? 'Prime',
        priceString: args['price']?.toString() ?? '4,499',
        period: period,
        billingPeriod: args['billingPeriod']?.toString() ??
            (period == 'month' ? 'MONTHLY' : 'YEARLY'),
        features: (args['features'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
      );
    },
    membershipUpgradeScreen: (context) {
      final args =
          ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>? ??
              {};
      final period = args['period']?.toString() ?? 'month';
      return MembershipUpgradeScreen(
        planRef: args['planRef']?.toString() ??
            args['planId']?.toString() ??
            '',
        planTitle: args['title']?.toString() ?? 'Plan',
        period: period,
        billingPeriod: args['billingPeriod']?.toString() ??
            (period == 'year' ? 'yearly' : 'monthly'),
      );
    },
    orderSuccessScreen: (context) {
      final args = ModalRoute.of(context)?.settings.arguments;
      var orderId = '#NMW-829410';
      var orderIdDisplay = orderId;
      var isSubscription = false;
      var continueToWardrobeKit = false;
      if (args is Map) {
        isSubscription = args['isSubscription'] == true;
        continueToWardrobeKit = args['continueToWardrobeKit'] == true;
        orderId = args['orderId']?.toString() ?? orderId;
        orderIdDisplay = args['orderNumber']?.toString() ?? orderId;
      } else if (args is String && args.isNotEmpty) {
        orderId = args;
        orderIdDisplay = args;
      }
      return OrderSuccessScreen(
        orderId: orderId,
        orderIdDisplay: orderIdDisplay,
        isSubscription: isSubscription,
        continueToWardrobeKit: continueToWardrobeKit,
      );
    },
    orderTrackingScreen: (context) {
      final orderId = ModalRoute.of(context)?.settings.arguments as String? ?? '';
      return OrderTrackingScreen(orderId: orderId);
    },
    aboutUsScreen: (context) => const AboutUsScreen(),
    privacyPolicyScreen: (context) => const PrivacyPolicyScreen(),
    helpSupportScreen: (context) => const HelpSupportScreen(),
    termsConditionsScreen: (context) => const TermsConditionsScreen(),
    favoritesScreen: (context) => const FavoritesScreen(),
    cartScreen: (context) => const CartScreen(),
    essentialsCheckoutScreen: (context) {
      final args = ModalRoute.of(context)?.settings.arguments;
      final initialPrefetch = args is CheckoutPrefetchPayload ? args : null;
      return EssentialsCheckoutScreen(initialPrefetch: initialPrefetch);
    },
    mySubscriptionsScreen: (context) => const MySubscriptionsScreen(),
    myOrdersScreen: (context) => const MyOrdersScreen(),
    myAddressesScreen: (context) => const MyAddressesScreen(),
    orderDetailsScreen: (context) {
      final id = ModalRoute.of(context)?.settings.arguments as String? ?? '';
      return OrderDetailsScreen(orderId: id);
    },
    returnOrderScreen: (context) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is Map) {
        return ReturnOrderScreen(
          orderId: args['orderId']?.toString() ?? '',
          orderNumber: args['orderNumber']?.toString(),
        );
      }
      return ReturnOrderScreen(orderId: args?.toString() ?? '');
    },
  };
}
