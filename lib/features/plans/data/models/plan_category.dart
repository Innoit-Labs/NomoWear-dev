import 'package:nomowear/features/plans/data/models/wardrobe_plan.dart';

class PlanCategory {
  final String id;
  final String name;
  final String? description;
  final int displayOrder;
  final bool isActive;
  final List<String> features;
  final List<WardrobePlan> plans;

  const PlanCategory({
    required this.id,
    required this.name,
    this.description,
    this.displayOrder = 0,
    this.isActive = true,
    this.features = const [],
    this.plans = const [],
  });

  factory PlanCategory.fromJson(Map<String, dynamic> json) {
    final plansRaw = json['plans'] ?? json['wardrobePlans'] ?? json['items'];
    final plans = <WardrobePlan>[];
    if (plansRaw is List) {
      for (final item in plansRaw) {
        if (item is Map<String, dynamic>) {
          plans.add(WardrobePlan.fromJson(item));
        }
      }
    }

    plans.sort((a, b) => a.displayOrder.compareTo(b.displayOrder));

    final id = json['id']?.toString() ??
        json['_id']?.toString() ??
        json['categoryId']?.toString() ??
        json['category_id']?.toString() ??
        '';

    final name = json['name']?.toString() ??
        json['categoryName']?.toString() ??
        json['category_name']?.toString() ??
        '';

    final activeVal = json['isActive'] ??
        json['is_active'] ??
        (json['status'] != null
            ? json['status'].toString().toUpperCase() == 'ACTIVE'
            : true);

    return PlanCategory(
      id: id,
      name: name,
      description: _nonEmpty(json['description']),
      displayOrder:
          _parseInt(json['displayOrder'] ?? json['display_order']) ?? 0,
      isActive: _parseBool(activeVal),
      features: (json['features'] as List?)?.map((e) => e.toString()).toList() ??
          [],
      plans: plans.where((p) => p.isActive && p.id.isNotEmpty).toList(),
    );
  }
}

bool _parseBool(dynamic value) {
  if (value is bool) return value;
  if (value is int) return value != 0;
  if (value is String) {
    return value == '1' || value.toLowerCase() == 'true';
  }
  return true;
}

int? _parseInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

String? _nonEmpty(dynamic value) {
  final s = value?.toString().trim();
  return (s == null || s.isEmpty) ? null : s;
}
