import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:nomowear/core/network/api_client.dart';
import 'package:nomowear/core/network/api_constants.dart';
import 'package:nomowear/core/services/auth_storage.dart';

/// Top-level background message handler for FCM.
/// Must be annotated with `@pragma('vm:entry-point')` so Flutter can invoke it
/// even when the app is in the background or terminated.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint('FCM [Background]: ${message.messageId} - ${message.notification?.title}');
}

class FirebaseMessagingService {
  FirebaseMessagingService._();
  static final FirebaseMessagingService instance = FirebaseMessagingService._();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final ApiClient _apiClient = ApiClient();
  final AuthStorage _authStorage = AuthStorage();
  String? _fcmToken;

  String? get fcmToken => _fcmToken;

  /// Initializes FCM permissions, token fetching, token refresh, and listeners.
  Future<void> initialize() async {
    // 1. Set background messaging handler
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // 2. Request notification permissions (required for iOS & Android 13+)
    await _requestPermissions();

    // 3. Foreground notification presentation options (iOS/macOS & supported Android)
    await _fcm.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    // 4. Retrieve & print the FCM Token
    await _initToken();

    // 5. Setup foreground & user interaction listeners
    _setupMessageHandlers();

    // 6. If user is already authenticated, register token with backend
    await sendTokenToServer();
  }

  Future<void> _requestPermissions() async {
    try {
      final NotificationSettings settings = await _fcm.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );

      debugPrint(
        'FCM: Notification authorization status: ${settings.authorizationStatus}',
      );
    } catch (e) {
      debugPrint('FCM: Failed to request notification permission: $e');
    }
  }

  Future<void> _initToken() async {
    try {
      _fcmToken = await _fcm.getToken();
      debugPrint('================ FCM TOKEN ================');
      debugPrint(_fcmToken ?? 'Failed to retrieve FCM Token');
      debugPrint('===========================================');
    } catch (e) {
      debugPrint('FCM: Error getting token: $e');
    }

    // Handle token refresh
    _fcm.onTokenRefresh.listen((String newToken) {
      _fcmToken = newToken;
      debugPrint('================ FCM TOKEN REFRESHED ================');
      debugPrint(newToken);
      debugPrint('====================================================');
      sendTokenToServer(token: newToken);
    });
  }

  /// Sends the FCM token to backend POST `/mobile/v1/fcm-token`
  /// Headers:
  /// `Authorization: Bearer <customer_jwt_token>`
  /// `Content-Type: application/json`
  /// Body:
  /// ```json
  /// {
  ///   "fcmToken": "...",
  ///   "deviceType": "android"
  /// }
  /// ```
  Future<bool> sendTokenToServer({String? token, String? authToken}) async {
    final fcm = token ?? _fcmToken ?? await _fcm.getToken();
    if (fcm == null || fcm.isEmpty) {
      debugPrint('FCM: No FCM token available to send to server.');
      return false;
    }

    final auth = authToken ?? await _authStorage.getAuthToken();
    if (auth == null || auth.isEmpty) {
      debugPrint('FCM: User not authenticated. Skipping backend token sync until login.');
      return false;
    }

    final String deviceType;
    if (kIsWeb) {
      deviceType = 'web';
    } else if (Platform.isIOS) {
      deviceType = 'ios';
    } else {
      deviceType = 'android';
    }

    try {
      debugPrint('FCM: Syncing token with server (deviceType: $deviceType)...');
      final response = await _apiClient.post(
        ApiConstants.fcmTokenPath,
        {
          'fcmToken': fcm,
          'deviceType': deviceType,
        },
        authToken: auth,
      );

      debugPrint('FCM: Token successfully synced with backend: $response');
      return true;
    } catch (e) {
      debugPrint('FCM: Error syncing token with backend: $e');
      return false;
    }
  }

  void _setupMessageHandlers() {
    // Foreground messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint(
        'FCM [Foreground]: ${message.notification?.title ?? "No title"} - ${message.notification?.body ?? ""}',
      );
    });

    // Background to Foreground (when user taps on notification banner)
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint(
        'FCM [OpenedApp]: ${message.notification?.title ?? "No title"} (ID: ${message.messageId})',
      );
    });

    // Terminated state to Foreground (when app is launched by tapping notification)
    _checkInitialMessage();
  }

  Future<void> _checkInitialMessage() async {
    try {
      final RemoteMessage? initialMessage = await _fcm.getInitialMessage();
      if (initialMessage != null) {
        debugPrint(
          'FCM [InitialMessage]: Launched from terminated state - ${initialMessage.notification?.title ?? "No title"}',
        );
      }
    } catch (e) {
      debugPrint('FCM: Error retrieving initial message: $e');
    }
  }
}
