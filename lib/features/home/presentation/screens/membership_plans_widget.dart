import 'package:flutter/material.dart';
import 'package:nomowear/core/app_export.dart';
import 'package:nomowear/core/network/api_exception.dart';
import 'package:nomowear/features/plans/data/models/plan_category.dart';
import 'package:nomowear/features/plans/data/plan_cache.dart';
import 'package:nomowear/features/plans/data/plan_repository.dart';

class MembershipPlansWidget extends StatefulWidget {
  final void Function(PlanCategory category) onOpenPlans;
  final Future<void> Function()? onRefresh;

  const MembershipPlansWidget({
    Key? key,
    required this.onOpenPlans,
    this.onRefresh,
  }) : super(key: key);

  @override
  State<MembershipPlansWidget> createState() =>
      _MembershipPlansWidgetState();
}

class _MembershipPlansWidgetState extends State<MembershipPlansWidget> {
  final PlanRepository _planRepository = PlanRepository();

  List<PlanCategory> _categories = [];
  String? _selectedCategoryId;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories({bool forceRefresh = false}) async {
    if (!forceRefresh) {
      final cached = PlanCache.instance.categories;
      if (cached != null) {
        _applyCategories(cached);
        if (mounted) setState(() => _isLoading = false);
        return;
      }
    }

    try {
      final categories = await _planRepository.getPlanCategories(
        forceRefresh: forceRefresh,
      );
      if (!mounted) return;
      _applyCategories(categories);
      setState(() => _isLoading = false);
    } on ApiException {
      if (!mounted) return;
      setState(() => _isLoading = false);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  void _applyCategories(List<PlanCategory> categories) {
    _categories = [...categories]..sort(_membershipCategoryOrder);
    if (_categories.isNotEmpty &&
        !_categories.any((c) => c.id == _selectedCategoryId)) {
      _selectedCategoryId = _categories.first.id;
    }
  }

  int _membershipCategoryOrder(PlanCategory a, PlanCategory b) {
    int rank(String name) {
      final n = name.toLowerCase();
      if (n.contains('flex')) return 0;
      if (n.contains('prime')) return 1;
      return 2;
    }

    final byRank = rank(a.name).compareTo(rank(b.name));
    if (byRank != 0) return byRank;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }

  List<String> _featuresForCategory(PlanCategory category) {
    if (category.features.isNotEmpty) {
      return category.features;
    }
    return const [];
  }

  String _buttonLabel(PlanCategory category) {
    final shortName = category.name.split(' ').first.toUpperCase();
    return 'CHOOSE $shortName';
  }

  @override
  Widget build(BuildContext context) {
    final body = Container(
      margin: EdgeInsets.fromLTRB(16.w, 0, 16.w, 16.h),
      child: Column(
        children: [
          SizedBox(height: 12.h),
          Text(
            "Membership Plans",
            style: CustomTextStyles.openSansSemiBold.copyWith(
              fontSize: 16,
              color: AppColours.primary,
            ),
          ),
          SizedBox(height: 8.h),
          Container(
            height: 2,
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xFFE6C27A).withOpacity(0.15),
                  Color(0xFFE6C27A),
                  Color(0xFFE6C27A).withOpacity(0.15),
                ],
              ),
            ),
          ),
          SizedBox(height: 12.h),
          Text(
            "CHOOSE YOUR MEMBERSHIP PLAN",
            style: CustomTextStyles.openSansRegular.copyWith(fontSize: 14),
          ),
          SizedBox(height: 12.h),
          Expanded(child: _buildPlansBody()),
        ],
      ),
    );

    return RefreshIndicator(
      color: AppColours.primary,
      backgroundColor: const Color(0xFF16181D),
      onRefresh: () async {
        debugPrint('[MEMBERSHIP PLANS] Pull to refresh triggered');
        await Future.wait([
          _loadCategories(forceRefresh: true),
          if (widget.onRefresh != null) widget.onRefresh!(),
        ]);
      },
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: body,
          ),
        ],
      ),
    );
  }

  Widget _buildPlansBody() {
    if (_isLoading) {
      return Column(
        children: [
          Expanded(child: const MembershipCardShimmer()),
          SizedBox(height: 10.h),
          Expanded(child: const MembershipCardShimmer()),
        ],
      );
    }

    if (_categories.isEmpty) {
      return Center(
        child: Text(
          'No membership plans available right now.',
          textAlign: TextAlign.center,
          style: CustomTextStyles.openSansRegular.copyWith(
            color: Colors.white54,
            fontSize: 14,
          ),
        ),
      );
    }

    return Column(
      children: _categories.asMap().entries.map((entry) {
        final index = entry.key;
        final category = entry.value;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(
              bottom: index < _categories.length - 1 ? 10.h : 0,
            ),
            child: _buildMembershipCard(
              category: category,
              features: _featuresForCategory(category),
              buttonLabel: _buttonLabel(category),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildMembershipCard({
    required PlanCategory category,
    required List<String> features,
    required String buttonLabel,
  }) {
    final isSelected = _selectedCategoryId == category.id;
    final description = category.description ??
        'Explore curated wardrobe plans tailored for your style.';

    return GestureDetector(
      onTap: () => setState(() => _selectedCategoryId = category.id),
      child: Container(
        width: double.infinity,
        height: double.infinity,
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
        decoration: BoxDecoration(
          color: const Color(0xFF16181D),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isSelected
                ? AppColours.primary
                : AppColours.primary.withOpacity(0.30),
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColours.primary.withOpacity(0.1),
                    blurRadius: 15,
                    spreadRadius: 2,
                  ),
                ]
              : [
                  BoxShadow(
                    color: const Color(0xFFCFAF6E).withOpacity(0.3),
                    blurRadius: 8,
                    spreadRadius: 2,
                  ),
                ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              category.name,
              style: CustomTextStyles.montserratBold.copyWith(
                fontSize: 22,
                color: AppColours.primary,
              ),
            ),
            SizedBox(height: 8.h),
            Text(
              description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: CustomTextStyles.openSansRegular.copyWith(fontSize: 14),
            ),
            SizedBox(height: 10.h),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: features.map(
                  (feature) => Padding(
                    padding: EdgeInsets.only(bottom: 8.h),
                    child: Row(
                      children: [
                        Icon(Icons.check, color: AppColours.primary, size: 16),
                        SizedBox(width: 10.w),
                        Expanded(
                          child: Text(
                            feature,
                            style: CustomTextStyles.openSansRegular.copyWith(
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ).toList(),
              ),
            ),
            SizedBox(
              width: double.infinity,
              height: 46.h,
              child: isSelected
                  ? ElevatedButton(
                      onPressed: () => widget.onOpenPlans(category),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColours.primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        buttonLabel,
                        style: CustomTextStyles.openSansSemiBold.copyWith(
                          color: Colors.black,
                          letterSpacing: 1.6,
                        ),
                      ),
                    )
                  : OutlinedButton(
                      onPressed: () => widget.onOpenPlans(category),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: AppColours.primary, width: 1.5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        buttonLabel,
                        style: CustomTextStyles.openSansSemiBold.copyWith(
                          color: AppColours.primary,
                          letterSpacing: 1.6,
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
