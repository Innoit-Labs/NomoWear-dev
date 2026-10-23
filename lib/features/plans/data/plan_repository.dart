import 'package:nomowear/core/network/api_client.dart';
import 'package:nomowear/core/network/api_constants.dart';
import 'package:nomowear/core/network/api_exception.dart';
import 'package:nomowear/core/services/auth_storage.dart';
import 'package:nomowear/features/plans/data/models/plan_category.dart';
import 'package:nomowear/features/plans/data/models/wardrobe_plan.dart';
import 'package:nomowear/features/plans/data/plan_cache.dart';

class PlanRepository {
  final ApiClient _apiClient;
  final AuthStorage _authStorage;

  PlanRepository({
    ApiClient? apiClient,
    AuthStorage? authStorage,
  })  : _apiClient = apiClient ?? ApiClient(),
        _authStorage = authStorage ?? AuthStorage();

  Future<List<PlanCategory>> getPlanCategories({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      final cached = PlanCache.instance.categories;
      if (cached != null) return cached;
    }

    final authToken = await _requireAuthToken();
    final json = await _apiClient.get(
      ApiConstants.planCategoriesPath,
      authToken: authToken,
    );

    if (json['success'] != true) {
      throw ApiException(
        json['message']?.toString() ?? 'Failed to load plan categories',
      );
    }

    final categories = _parseCategories(json['data']);
    PlanCache.instance.setCategories(categories);
    for (final category in categories) {
      if (category.plans.isNotEmpty) {
        PlanCache.instance.setPlansForCategory(category.id, category.plans);
      }
    }
    return categories;
  }

  Future<List<WardrobePlan>> getPlansByCategoryId(
    String categoryId, {
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      final cached = PlanCache.instance.plansForCategory(categoryId);
      if (cached != null) return cached;
    }

    final authToken = await _requireAuthToken();
    final json = await _apiClient.get(
      ApiConstants.plansPath,
      authToken: authToken,
      queryParameters: {
        'category_id': categoryId,
        'catgory_id': categoryId,
        'categoryId': categoryId,
      },
    );

    if (json['success'] != true) {
      throw ApiException(
        json['message']?.toString() ?? 'Failed to load plans',
      );
    }

    final plans = _parsePlans(json['data']);
    PlanCache.instance.setPlansForCategory(categoryId, plans);
    return plans;
  }

  Future<String> _requireAuthToken() async {
    final authToken = await _authStorage.getAuthToken();
    if (authToken == null || authToken.isEmpty) {
      throw const ApiException('Not logged in. Please login again.');
    }
    return authToken;
  }

  List<PlanCategory> _parseCategories(dynamic data) {
    dynamic listData = data;
    if (listData is Map<String, dynamic>) {
      listData = listData['categories'] ??
          listData['data'] ??
          listData['rows'] ??
          listData['items'];
    }

    if (listData is! List) {
      throw const ApiException('Invalid plan categories response');
    }

    final categories = listData
        .whereType<Map<String, dynamic>>()
        .map(PlanCategory.fromJson)
        .where((c) => c.name.isNotEmpty && c.isActive)
        .toList();

    categories.sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
    return categories;
  }

  List<WardrobePlan> _parsePlans(dynamic data) {
    dynamic listData = data;
    if (listData is Map<String, dynamic>) {
      listData = listData['plans'] ??
          listData['data'] ??
          listData['rows'] ??
          listData['items'];
    }

    if (listData is! List) {
      throw const ApiException('Invalid plans response');
    }

    final plans = listData
        .whereType<Map<String, dynamic>>()
        .map(WardrobePlan.fromJson)
        .where((p) => (p.id.isNotEmpty || p.name.isNotEmpty) && p.isActive)
        .toList();

    plans.sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
    return plans;
  }
}
