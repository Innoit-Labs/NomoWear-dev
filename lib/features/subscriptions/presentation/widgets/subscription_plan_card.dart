import 'package:nomowear/core/app_export.dart';
import 'package:nomowear/features/subscriptions/data/models/active_subscription.dart';

class SubscriptionPlanCard extends StatefulWidget {
  const SubscriptionPlanCard({
    super.key,
    required this.subscription,
    this.showCurrentPlanBadge = false,
    this.statusLabel,
    this.matchedFeatures,
    this.onMembershipBooking,
  });

  final ActiveSubscription subscription;
  final bool showCurrentPlanBadge;
  final String? statusLabel;
  final List<String>? matchedFeatures;
  final VoidCallback? onMembershipBooking;

  @override
  State<SubscriptionPlanCard> createState() => _SubscriptionPlanCardState();
}

class _SubscriptionPlanCardState extends State<SubscriptionPlanCard> {
  bool _isExpanded = false;

  List<String> get _effectiveFeatures {
    if (widget.matchedFeatures != null && widget.matchedFeatures!.isNotEmpty) {
      return widget.matchedFeatures!;
    }
    return widget.subscription.features;
  }

  void _toggleExpanded() {
    setState(() {
      _isExpanded = !_isExpanded;
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _toggleExpanded,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(20.w, 22.h, 20.w, 20.h),
        decoration: BoxDecoration(
          color: const Color(0xFF16181D),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColours.primary,
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _buildHeader(),
            SizedBox(height: 18.h),
            Divider(
              color: AppColours.primary.withOpacity(0.35),
              thickness: 0.5,
              height: 0.5,
            ),
            SizedBox(height: 18.h),
            ..._effectiveFeatures.map((f) => _buildFeatureRow(f)),
            AnimatedCrossFade(
              firstChild: const SizedBox(width: double.infinity),
              secondChild: _buildUsageSection(),
              crossFadeState:
                  _isExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 300),
            ),
            if (widget.subscription.isActive) ...[
              SizedBox(height: 20.h),
              Center(
                child: Text(
                  'CURRENT PLAN',
                  style: CustomTextStyles.montserratBold.copyWith(
                    fontSize: 12,
                    color: AppColours.primary.withOpacity(0.8),
                    letterSpacing: 1.4,
                  ),
                ),
              ),
            ]
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            Align(
              alignment: Alignment.center,
              child: Text(
                widget.subscription.displayTitle,
                textAlign: TextAlign.center,
                style: CustomTextStyles.montserratBold.copyWith(
                  fontSize: 16,
                  color: AppColours.primary,
                  letterSpacing: 0.6,
                  height: 1.3,
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Icon(
                _isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                color: AppColours.primary,
                size: 24,
              ),
            ),
          ],
        ),
        SizedBox(height: 18.h),
        Divider(
          color: AppColours.primary.withOpacity(0.35),
          thickness: 0.5,
          height: 0.5,
        ),
        SizedBox(height: 18.h),
        Text(
          widget.subscription.formattedPrice,
          textAlign: TextAlign.center,
          style: CustomTextStyles.openSansSemiBold.copyWith(
            fontSize: 20,
            color: Colors.white,
            height: 1.2,
          ),
        ),
        if (widget.subscription.expiryLabel.isNotEmpty) ...[
          SizedBox(height: 8.h),
          Text(
            widget.subscription.expiryLabel,
            textAlign: TextAlign.center,
            style: CustomTextStyles.openSansRegular.copyWith(
              fontSize: 12,
              color: Colors.white54,
              height: 1.3,
            ),
          ),
        ],
        if (widget.statusLabel != null && widget.statusLabel!.trim().isNotEmpty) ...[
          SizedBox(height: 8.h),
          _statusChip(widget.statusLabel!.trim()),
        ],
      ],
    );
  }

  Widget _buildUsageSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(height: 18.h),
        Divider(
          color: AppColours.primary.withOpacity(0.35),
          thickness: 0.5,
          height: 0.5,
        ),
        SizedBox(height: 18.h),
        Text(
          'YOUR PLAN USAGE',
          style: CustomTextStyles.montserratBold.copyWith(
            fontSize: 14,
            color: AppColours.primary,
            letterSpacing: 1.2,
          ),
        ),
        SizedBox(height: 18.h),
        _buildMetricsRow(widget.subscription),
      ],
    );
  }

  Widget _buildFeatureRow(String feature) {
    return Padding(
      padding: EdgeInsets.only(bottom: 12.h, left: 16.w, right: 16.w),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.check,
            color: Colors.white70,
            size: 16.w,
          ),
          SizedBox(width: 16.w),
          Expanded(
            child: Text(
              feature,
              style: CustomTextStyles.openSansRegular.copyWith(
                fontSize: 13.fSize,
                color: Colors.white,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(String status) {
    final normalized = status.toUpperCase();
    final isActive = normalized == 'ACTIVE';
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
      decoration: BoxDecoration(
        color: isActive
            ? AppColours.primary.withOpacity(0.15)
            : Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isActive
              ? AppColours.primary.withOpacity(0.5)
              : Colors.white24,
        ),
      ),
      child: Text(
        normalized,
        style: TextStyle(
          color: isActive ? AppColours.primary : Colors.white54,
          fontSize: 9.fSize,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      ),
    );
  }

  Widget _buildMetricsRow(ActiveSubscription subscription) {
    final remGarments = subscription.apiRemainingGarments ?? subscription.maxGarments;
    final totalGarments = subscription.maxGarments;

    final remBookings = subscription.remainingBookingsCount;
    final totalBookings = subscription.noOfBookings;

    final remDays = subscription.remainingKitDays ?? subscription.kitDurationDays;
    final totalDays = subscription.kitDurationDays;

    return Row(
      children: [
        Expanded(
          child: _buildMetricItem(
            'MAX GARMENTS',
            '$remGarments / $totalGarments',
          ),
        ),
        Expanded(
          child: _buildMetricItem(
            'BOOKINGS LEFT',
            '$remBookings / $totalBookings',
          ),
        ),
        Expanded(
          child: _buildMetricItem(
            'PLAN DAYS LEFT',
            '$remDays / $totalDays',
          ),
        ),
      ],
    );
  }

  Widget _buildMetricItem(String title, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: CustomTextStyles.openSansSemiBold.copyWith(
            fontSize: 10.fSize,
            color: Colors.white54,
            letterSpacing: 0.5,
          ),
        ),
        SizedBox(height: 6.h),
        Text(
          value,
          style: CustomTextStyles.openSansSemiBold.copyWith(
            fontSize: 14.fSize,
            color: Colors.white,
          ),
        ),
      ],
    );
  }
}
