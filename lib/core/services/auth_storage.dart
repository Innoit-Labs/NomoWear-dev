import 'package:flutter/foundation.dart';
import 'package:nomowear/core/services/session_cleanup.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthStorage {
  static const _customerIdKey = 'auth_customer_id';
  static const _userTokenKey = 'auth_user_token';
  static const _authTokenKey = 'auth_token';
  static const _mobileKey = 'auth_mobile';
  static const _profileCompleteKey = 'profile_complete';
  static const _profileDataKey = 'auth_profile_data';

  Future<void> savePendingOtpSession({
    required String customerId,
    required String userToken,
    required String mobileNumber,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_customerIdKey, customerId);
    await prefs.setString(_userTokenKey, userToken);
    await prefs.setString(_mobileKey, mobileNumber);
  }

  static String? _cachedAuthToken;

  Future<void> saveAuthenticatedSession({
    required String authToken,
    required String customerId,
    required String mobileNumber,
    bool profileComplete = false,
  }) async {
    _cachedAuthToken = authToken;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_authTokenKey, authToken);
    await prefs.setString(_customerIdKey, customerId);
    await prefs.setString(_mobileKey, mobileNumber);
    if (profileComplete) {
      await prefs.setBool(_profileCompleteKey, true);
    }
    if (kDebugMode) {
      debugPrint('════════ AUTH TOKEN SAVED ════════');
      debugPrint('Token: $authToken');
      debugPrint('Customer ID: $customerId');
      debugPrint('Mobile: $mobileNumber');
      debugPrint('Profile complete: $profileComplete');
      debugPrint('══════════════════════════════════');
    }
  }

  Future<void> saveProfileData(String profileJson) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_profileDataKey, profileJson);
  }

  Future<String?> getProfileData() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_profileDataKey);
  }

  Future<bool> isLoggedIn() async {
    final token = await getAuthToken();
    return token != null && token.isNotEmpty;
  }

  Future<bool> isProfileCompleteCached() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_profileCompleteKey) ?? false;
  }

  Future<void> markProfileComplete(bool complete) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_profileCompleteKey, complete);
  }

  Future<String?> getAuthToken() async {
    if (_cachedAuthToken != null && _cachedAuthToken!.isNotEmpty) {
      return _cachedAuthToken;
    }
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_authTokenKey);
    if (token != null && token.isNotEmpty) {
      _cachedAuthToken = token;
    }
    return token;
  }

  /// Prints the persisted auth token (debug builds only).
  Future<void> logStoredToken({String source = 'app'}) async {
    if (!kDebugMode) return;

    final token = await getAuthToken();
    final mobile = await getMobileNumber();
    final prefs = await SharedPreferences.getInstance();
    final customerId = prefs.getString(_customerIdKey);

    if (token == null || token.isEmpty) {
      debugPrint('[$source] No auth token stored.');
      return;
    }

    debugPrint('════════ STORED AUTH TOKEN ($source) ════════');
    debugPrint('Token: $token');
    debugPrint('Customer ID: $customerId');
    debugPrint('Mobile: $mobile');
    debugPrint('════════════════════════════════════════════');
  }

  Future<String?> getMobileNumber() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_mobileKey);
  }

  /// Clears auth + all user-scoped local caches/singletons/image cache.
  /// Prefer [SessionCleanup.clearUserSessionAndBlocs] from UI so Cart/Favorites
  /// Blocs are also reset.
  Future<void> clear() async {
    _cachedAuthToken = null;
    await SessionCleanup.clearUserSession();
  }
}
