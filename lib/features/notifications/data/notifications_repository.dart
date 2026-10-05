import 'package:flutter/foundation.dart';
import 'package:nomowear/core/network/api_client.dart';
import 'package:nomowear/core/network/api_constants.dart';
import 'package:nomowear/core/network/api_exception.dart';
import 'package:nomowear/core/services/auth_storage.dart';
import 'package:nomowear/features/notifications/data/models/customer_notification.dart';

class NotificationsRepository {
  final ApiClient _apiClient;
  final AuthStorage _authStorage;

  NotificationsRepository({
    ApiClient? apiClient,
    AuthStorage? authStorage,
  })  : _apiClient = apiClient ?? ApiClient(),
        _authStorage = authStorage ?? AuthStorage();

  Future<List<CustomerNotification>> getNotifications() async {
    final authToken = await _authStorage.getAuthToken();
    if (authToken == null || authToken.isEmpty) {
      throw const ApiException('Please login to view notifications');
    }

    Map<String, dynamic> json;
    try {
      json = await _apiClient.get(
        ApiConstants.customerNotificationsPath,
        authToken: authToken,
      );
    } on ApiException catch (e) {
      if (kDebugMode) {
        debugPrint('[NOTIFICATIONS] Primary endpoint failed: ${e.message}. Trying fallback.');
      }
      // Fallback path without 'api/v1/' in case the backend route is mounted at 'mobile/v1/'
      try {
        json = await _apiClient.get(
          'mobile/v1/customers/notifications',
          authToken: authToken,
        );
      } catch (_) {
        rethrow;
      }
    }

    if (json['success'] != true && json['data'] == null) {
      throw ApiException(
        json['message']?.toString() ?? 'Failed to load notifications',
      );
    }

    final dynamic rawData = json['data'];
    if (rawData is List) {
      return rawData
          .whereType<Map<String, dynamic>>()
          .map((item) => CustomerNotification.fromJson(item))
          .toList();
    }

    return [];
  }

  Future<bool> clearAllNotifications() async {
    final authToken = await _authStorage.getAuthToken();
    if (authToken == null || authToken.isEmpty) {
      throw const ApiException('Please login to clear notifications');
    }

    Map<String, dynamic>? json;
    dynamic lastError;

    // 1. Try DELETE on primary path
    try {
      json = await _apiClient.delete(
        ApiConstants.clearAllNotificationsPath,
        authToken: authToken,
      );
    } catch (e) {
      lastError = e;
      if (kDebugMode) {
        debugPrint('[NOTIFICATIONS] DELETE primary failed: $e');
      }
    }

    // 2. Try POST on primary path if DELETE didn't succeed
    if (json == null || json['success'] != true) {
      try {
        json = await _apiClient.post(
          ApiConstants.clearAllNotificationsPath,
          {},
          authToken: authToken,
        );
      } catch (e) {
        lastError = e;
        if (kDebugMode) {
          debugPrint('[NOTIFICATIONS] POST primary failed: $e');
        }
      }
    }

    // 3. Fallback to 'mobile/v1/notifications/clear-all' if needed
    if (json == null || json['success'] != true) {
      try {
        json = await _apiClient.delete(
          'mobile/v1/notifications/clear-all',
          authToken: authToken,
        );
      } catch (_) {
        try {
          json = await _apiClient.post(
            'mobile/v1/notifications/clear-all',
            {},
            authToken: authToken,
          );
        } catch (e) {
          lastError = e;
        }
      }
    }

    if (json != null && (json['success'] == true || json['data'] != null)) {
      return true;
    }

    if (lastError is ApiException) {
      throw lastError;
    }
    throw ApiException(
      json?['message']?.toString() ?? 'Failed to clear notifications',
    );
  }

  Future<bool> markNotificationsAsRead(List<String> notificationIds) async {
    if (notificationIds.isEmpty) return true;

    final authToken = await _authStorage.getAuthToken();
    if (authToken == null || authToken.isEmpty) {
      return false;
    }

    final body = <String, dynamic>{
      'notificationIds': notificationIds,
      if (notificationIds.isNotEmpty) 'id': notificationIds.first,
    };

    final paths = [
      ApiConstants.markNotificationsReadPath, // 'api/v1/mobile/customers/notifications/mark-read'
      'mobile/v1/customers/notifications/mark-read',
      'api/v1/mobile/notifications/mark-read',
      'mobile/v1/notifications/mark-read',
    ];

    for (final path in paths) {
      // 1. Try PUT
      try {
        final json = await _apiClient.put(
          path,
          body,
          authToken: authToken,
        );
        if (json['success'] == true || json['data'] != null) {
          if (kDebugMode) {
            debugPrint('[NOTIFICATIONS] Successfully marked read via PUT $path');
          }
          return true;
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[NOTIFICATIONS] PUT $path failed: $e');
        }
      }

      // 2. Try POST
      try {
        final json = await _apiClient.post(
          path,
          body,
          authToken: authToken,
        );
        if (json['success'] == true || json['data'] != null) {
          if (kDebugMode) {
            debugPrint('[NOTIFICATIONS] Successfully marked read via POST $path');
          }
          return true;
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[NOTIFICATIONS] POST $path failed: $e');
        }
      }
    }

    return false;
  }

  Future<bool> hasUnreadNotifications() async {
    try {
      final list = await getNotifications();
      return list.any((item) => !item.isRead);
    } catch (_) {
      return false;
    }
  }
}
