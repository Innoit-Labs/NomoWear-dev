import 'package:nomowear/core/app_export.dart';
import 'package:nomowear/features/home/presentation/bloc/home_bloc.dart';
import 'package:nomowear/features/home/presentation/screens/active_subscription_widget.dart';
import 'package:nomowear/features/home/presentation/screens/membership_plans_widget.dart';
import 'package:nomowear/features/home/presentation/screens/subscription_plans_widget.dart';
import 'package:nomowear/features/plans/data/models/plan_category.dart';
import 'package:nomowear/features/subscriptions/presentation/bloc/subscription_bloc.dart';

class SubscriptionTabWidget extends StatefulWidget {
  static const int subscriptionTabIndex = 3;

  const SubscriptionTabWidget({super.key});

  @override
  State<SubscriptionTabWidget> createState() => _SubscriptionTabWidgetState();
}

class _SubscriptionTabWidgetState extends State<SubscriptionTabWidget> {
  bool _showSubscriptionPlans = false;
  PlanCategory? _selectedPlanCategory;

  @override
  void initState() {
    super.initState();
    debugPrint('[SUBSCRIPTION TAB] Tab opened -> initializing...');
  }

  void _reloadSubscription({bool forceRefresh = false}) {
    context.read<SubscriptionBloc>().add(
          LoadActiveSubscriptionEvent(forceRefresh: forceRefresh),
        );
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<HomeBloc, HomeState>(
      listenWhen: (previous, current) =>
          current.bottomNavIndex == SubscriptionTabWidget.subscriptionTabIndex &&
          previous.bottomNavIndex != current.bottomNavIndex,
      listener: (_, __) {
        debugPrint('[SUBSCRIPTION TAB] Switched to Subscription tab');
        _reloadSubscription();
      },
      child: BlocConsumer<SubscriptionBloc, SubscriptionState>(
        listener: (context, state) {
          if (state is SubscriptionError) {
            debugPrint('[SUBSCRIPTION TAB] Error: ${state.message}');
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(state.message)),
            );
          }
          if (state is SubscriptionActive) {
            debugPrint('================ [ACTIVE SUBSCRIPTION DATA] ================');
            debugPrint('Subscription ID: ${state.subscription.id}');
            debugPrint('Plan Name: ${state.subscription.planName}');
            debugPrint('Plan Status: ${state.subscription.planStatus} (isActive: ${state.subscription.isActive})');
            debugPrint('Plan Price: ${state.subscription.planPrice} / ${state.subscription.billingPeriod}');
            debugPrint('Valid Period: ${state.subscription.startDate} -> ${state.subscription.endDate}');
            debugPrint('Bookings: ${state.subscription.bookingsUsed ?? 0}/${state.subscription.noOfBookings} (remaining: ${state.subscription.remainingBookings ?? 0})');
            debugPrint('Garments: ${state.subscription.usedGarments ?? 0}/${state.subscription.maxGarments} (remaining: ${state.subscription.remainingGarments ?? 0})');
            debugPrint('Details: ${state.subscription.toMap()}');
            debugPrint('============================================================');
            setState(() {
              _showSubscriptionPlans = false;
              _selectedPlanCategory = null;
            });
          }
          if (state is SubscriptionInactive) {
            debugPrint('[SUBSCRIPTION TAB] User currently has no active subscription.');
          }
        },
        builder: (context, state) {
          if (state is SubscriptionLoading || state is SubscriptionInitial) {
            return _buildLoading();
          }

          if (state is SubscriptionActive) {
            return ActiveSubscriptionWidget(
              subscription: state.subscription,
              onRefresh: () async => _reloadSubscription(forceRefresh: true),
            );
          }

          if (state is SubscriptionError) {
            return _buildError(state.message);
          }

          if (_showSubscriptionPlans && _selectedPlanCategory != null) {
            return SubscriptionPlansWidget(
              category: _selectedPlanCategory!,
              onBack: () {
                setState(() {
                  _showSubscriptionPlans = false;
                  _selectedPlanCategory = null;
                });
              },
            );
          }

          return MembershipPlansWidget(
            onOpenPlans: (category) {
              setState(() {
                _selectedPlanCategory = category;
                _showSubscriptionPlans = true;
              });
            },
            onRefresh: () async => _reloadSubscription(forceRefresh: true),
          );
        },
      ),
    );
  }

  Widget _buildLoading() {
    return Container(
      margin: EdgeInsets.fromLTRB(16.w, 0, 16.w, 16.h),
      child: Column(
        children: [
          SizedBox(height: 12.h),
          Text(
            'Subscription',
            style: CustomTextStyles.openSansSemiBold.copyWith(
              fontSize: 16,
              color: AppColours.primary,
            ),
          ),
          SizedBox(height: 24.h),
          const Expanded(child: MembershipCardShimmer()),
        ],
      ),
    );
  }

  Widget _buildError(String message) {
    return RefreshIndicator(
      color: AppColours.primary,
      backgroundColor: const Color(0xFF16181D),
      onRefresh: () async => _reloadSubscription(forceRefresh: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 16.h),
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
          SizedBox(height: 120.h),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: CustomTextStyles.openSansRegular.copyWith(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
                SizedBox(height: 16.h),
                ElevatedButton(
                  onPressed: () => _reloadSubscription(forceRefresh: true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColours.primary,
                  ),
                  child: Text(
                    'Retry',
                    style: CustomTextStyles.openSansSemiBold.copyWith(
                      color: Colors.black,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
