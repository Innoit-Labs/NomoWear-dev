import 'package:nomowear/core/app_export.dart';
import 'package:nomowear/core/network/api_exception.dart';
import 'package:nomowear/features/home/presentation/screens/subscription_plans_widget.dart';
import 'package:nomowear/features/plans/data/models/plan_category.dart';
import 'package:nomowear/features/plans/data/models/wardrobe_plan.dart';
import 'package:nomowear/features/plans/data/plan_cache.dart';
import 'package:nomowear/features/plans/data/plan_repository.dart';
import 'package:nomowear/features/subscriptions/data/models/active_subscription.dart';
import 'package:nomowear/features/subscriptions/presentation/widgets/subscription_plan_card.dart';

class ActiveSubscriptionWidget extends StatefulWidget {
  const ActiveSubscriptionWidget({
    super.key,
    required this.subscription,
    this.onRefresh,
  });

  final ActiveSubscription subscription;
  final Future<void> Function()? onRefresh;

  @override
  State<ActiveSubscriptionWidget> createState() =>
      _ActiveSubscriptionWidgetState();
}

class _ActiveSubscriptionWidgetState extends State<ActiveSubscriptionWidget> {
  final PlanRepository _planRepository = PlanRepository();

  List<PlanCategory> _categories = [];
  bool _isLoadingCategories = true;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    try {
      final cached = PlanCache.instance.categories;
      if (cached != null && cached.isNotEmpty) {
        if (mounted) {
          setState(() {
            _categories = cached;
            _isLoadingCategories = false;
          });
        }
        _refreshCategories();
        return;
      }
      await _refreshCategories();
    } catch (_) {
      if (mounted) setState(() => _isLoadingCategories = false);
    }
  }

  Future<void> _refreshCategories() async {
    try {
      final categories = await _planRepository.getPlanCategories(
        forceRefresh: false,
      );
      if (!mounted) return;
      setState(() {
        _categories = categories;
        _isLoadingCategories = false;
      });
    } on ApiException {
      if (!mounted) return;
      setState(() => _isLoadingCategories = false);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingCategories = false);
    }
  }

  num get _currentPrice =>
      num.tryParse(widget.subscription.planPrice) ?? 0;

  bool get _isYearly =>
      widget.subscription.billingPeriod.toLowerCase().contains('year');

  List<PlanCategory> get _upgradeCategories {
    final result = <PlanCategory>[..._categories];
    result.sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
    return result;
  }

  bool _hasUpgradePlan(PlanCategory category) {
    if (category.plans.isEmpty) return true;
    return category.plans.any((plan) => _planPrice(plan) > _currentPrice);
  }

  num _planPrice(WardrobePlan plan) {
    if (plan.price > 0) return plan.price;
    return _isYearly ? plan.yearPrice : plan.monthPrice;
  }

  List<String> _featuresForCategory(PlanCategory category) {
    if (category.features.isNotEmpty) {
      return category.features;
    }
    return const [];
  }

  void _openUpgradePlans(PlanCategory category) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => _UpgradePlansPage(
          category: category,
          currentSubscription: widget.subscription,
        ),
      ),
    );
  }

  List<String>? _matchedCurrentPlanFeatures() {
    if (_categories.isEmpty) return null;
    
    final planRef = widget.subscription.planRef;
    final planName = widget.subscription.planName;
    
    for (final category in _categories) {
      for (final plan in category.plans) {
        if (plan.id == planRef || plan.planRef == planRef || plan.planCode == planRef || (planRef.isEmpty && plan.name == planName)) {
          debugPrint('CURRENT SUBSCRIPTION PLAN REF = $planRef');
          debugPrint('MATCHED PLAN ID = ${plan.id}');
          debugPrint('MATCHED PLAN CODE = ${plan.planCode}');
          debugPrint('CURRENT PLAN FEATURES = ${plan.features}');
          return plan.features.isNotEmpty ? plan.features : null;
        }
      }
    }
    return null;
  }

  Future<void> _handleRefresh() async {
    debugPrint('[ACTIVE SUBSCRIPTION] Pull to refresh triggered');
    await Future.wait([
      _refreshCategories(),
      if (widget.onRefresh != null) widget.onRefresh!(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final upgradeCategories = _upgradeCategories;
    final upgradeEligible = upgradeCategories.where(_hasUpgradePlan);
    final highlightCategoryId = upgradeEligible.isNotEmpty
        ? upgradeEligible.last.id
        : (upgradeCategories.isNotEmpty ? upgradeCategories.last.id : null);

    return RefreshIndicator(
      color: AppColours.primary,
      backgroundColor: const Color(0xFF16181D),
      onRefresh: _handleRefresh,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 24.h),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: 12.h),
            Text(
              'Subscription',
              textAlign: TextAlign.center,
              style: CustomTextStyles.openSansSemiBold.copyWith(
                fontSize: 16,
                color: AppColours.primary,
              ),
            ),
            SizedBox(height: 8.h),
            _headerDivider(),
            SizedBox(height: 20.h),
            SubscriptionPlanCard(
              subscription: widget.subscription,
              showCurrentPlanBadge: true,
              matchedFeatures: _matchedCurrentPlanFeatures(),
            ),
            if (_isLoadingCategories) ...[
              SizedBox(height: 24.h),
              Center(
                child: CircularProgressIndicator(
                  color: AppColours.primary,
                  strokeWidth: 2,
                ),
              ),
            ] else ...[
              ...upgradeCategories.map(
                (category) => Padding(
                  padding: EdgeInsets.only(top: 16.h),
                  child: _UpgradeMembershipCard(
                    category: category,
                    features: _featuresForCategory(category),
                    highlight: category.id == highlightCategoryId,
                    onUpgrade: () => _openUpgradePlans(category),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _headerDivider() {
    return Container(
      height: 2,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFFE6C27A).withOpacity(0.15),
            const Color(0xFFE6C27A),
            const Color(0xFFE6C27A).withOpacity(0.15),
          ],
        ),
      ),
    );
  }
}

class _UpgradeMembershipCard extends StatelessWidget {
  const _UpgradeMembershipCard({
    required this.category,
    required this.features,
    required this.onUpgrade,
    this.highlight = false,
  });

  final PlanCategory category;
  final List<String> features;
  final VoidCallback onUpgrade;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final description = category.description ??
        'Explore curated wardrobe plans tailored for your style.';

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(20.w, 22.h, 20.w, 20.h),
      decoration: BoxDecoration(
        color: const Color(0xFF16181D),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: highlight
              ? AppColours.primary
              : AppColours.primary.withOpacity(0.35),
          width: highlight ? 1.2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            category.name,
            style: CustomTextStyles.montserratBold.copyWith(
              fontSize: 22,
              color: AppColours.primary,
              height: 1.2,
            ),
          ),
          SizedBox(height: 10.h),
          Text(
            description,
            style: CustomTextStyles.openSansRegular.copyWith(
              fontSize: 14,
              color: AppColours.secondary,
              height: 1.4,
            ),
          ),
          SizedBox(height: 18.h),
          ...features.map(_featureRow),
          SizedBox(height: 24.h),
          SizedBox(
            width: double.infinity,
            height: 46.h,
            child: highlight
                ? ElevatedButton(
                    onPressed: onUpgrade,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColours.primary,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'UPGRADE PLAN',
                      style: CustomTextStyles.openSansSemiBold.copyWith(
                        color: Colors.black,
                        letterSpacing: 1.4,
                        fontSize: 13,
                      ),
                    ),
                  )
                : OutlinedButton(
                    onPressed: onUpgrade,
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: AppColours.primary, width: 1.2),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'UPGRADE PLAN',
                      style: CustomTextStyles.openSansSemiBold.copyWith(
                        color: AppColours.primary,
                        letterSpacing: 1.4,
                        fontSize: 13,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _featureRow(String feature) {
    return Padding(
      padding: EdgeInsets.only(bottom: 12.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(top: 2.h),
            child: Icon(Icons.check, color: AppColours.primary, size: 16),
          ),
          SizedBox(width: 10.w),
          Expanded(
            child: Text(
              feature,
              style: CustomTextStyles.openSansRegular.copyWith(
                fontSize: 14,
                color: AppColours.secondary,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Full-screen plan picker when a membership category has multiple upgrade options.
class _UpgradePlansPage extends StatelessWidget {
  const _UpgradePlansPage({
    required this.category,
    required this.currentSubscription,
  });

  final PlanCategory category;
  final ActiveSubscription currentSubscription;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1012),
      body: SafeArea(
        child: SubscriptionPlansWidget(
          category: category,
          currentSubscription: currentSubscription,
          onBack: () => Navigator.pop(context),
        ),
      ),
    );
  }
}
