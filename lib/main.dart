import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:nomowear/core/app_export.dart';
import 'package:nomowear/core/services/app_version_gate.dart';
import 'package:nomowear/core/services/auth_storage.dart';
import 'package:nomowear/core/services/firebase_messaging_service.dart';
import 'package:nomowear/features/auth/presentation/screens/splash_screen.dart';
import 'package:nomowear/features/cart/presentation/bloc/cart_bloc.dart';
import 'package:nomowear/features/checkout/data/subscription_kit_preferences.dart';
import 'package:nomowear/features/checkout/data/wardrobe_booking_session.dart';
import 'package:nomowear/features/favorites/presentation/bloc/favorites_bloc.dart';

/// Matches native Android launch background (`splash_background` in colors.xml).
const Color _splashBackground = Color(0xFF0F1012);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase and Cloud Messaging
  try {
    await Firebase.initializeApp();
    await FirebaseMessagingService.instance.initialize();
  } catch (e) {
    debugPrint('Firebase initialization failed: $e');
  }

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: _splashBackground,
      systemNavigationBarColor: _splashBackground,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  // Run version gate before UI so a new APK never boots into a stale session.
  // (SplashBloc also runs this as a safety net.)
  await AppVersionGate.ensureFreshInstallSession();
  await SubscriptionKitPreferences.instance.restore();
  await WardrobeBookingSession.instance.restore();

  if (kDebugMode) {
    await AuthStorage().logStoredToken(source: 'app_start');
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<CartBloc>(create: (_) => CartBloc()),
        BlocProvider<FavoritesBloc>(create: (_) => FavoritesBloc()),
      ],
      child: Sizer(
        builder: (context, orientation, deviceType) {
          return MaterialApp(
            scaffoldMessengerKey: CustomAppSnackBar.scaffoldMessengerKey,
            theme: ThemeHelper.themeDataData,
            title: 'nomowear',
            debugShowCheckedModeBanner: false,
            initialRoute: AppRoutes.splashScreen,
            routes: AppRoutes.routes,
            onGenerateInitialRoutes: (_) => [
              MaterialPageRoute(
                builder: SplashScreen.builder,
                settings: const RouteSettings(name: AppRoutes.splashScreen),
              ),
            ],
          );
        },
      ),
    );
  }
}
