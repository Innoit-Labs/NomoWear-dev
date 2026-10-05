import 'package:flutter/material.dart';
import 'package:nomowear/core/utils/size_utils.dart';
import 'package:nomowear/theme/theme_helper.dart';
import 'package:shimmer/shimmer.dart';

/// Dark-theme shimmer base used across API loading states.
class AppShimmer extends StatelessWidget {
  const AppShimmer({super.key, required this.child});

  final Widget child;

  static const Color baseColor = Color(0xFF1A1D21);
  static const Color highlightColor = Color(0xFF2E333B);

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: baseColor,
      highlightColor: highlightColor,
      period: const Duration(milliseconds: 1200),
      child: child,
    );
  }

  static Widget box({
    double? width,
    double? height,
    double borderRadius = 8,
  }) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: baseColor,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }

  static Widget circle(double size) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: baseColor,
        shape: BoxShape.circle,
      ),
    );
  }
}

class HomeHeaderShimmer extends StatelessWidget {
  const HomeHeaderShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return AppShimmer(
      child: Row(
        children: [
          AppShimmer.circle(48.h),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppShimmer.box(width: 72.w, height: 12.h, borderRadius: 4),
                SizedBox(height: 8.h),
                AppShimmer.box(width: 120.w, height: 14.h, borderRadius: 4),
              ],
            ),
          ),
          AppShimmer.circle(28.h),
        ],
      ),
    );
  }
}

class BannerShimmer extends StatelessWidget {
  const BannerShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return AppShimmer(
      child: Container(
        height: 180.h,
        width: double.maxFinite,
        decoration: BoxDecoration(
          color: AppShimmer.baseColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppColours.primary.withOpacity(0.25),
            width: 0.4,
          ),
        ),
        padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 12.h),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            AppShimmer.box(width: 180.w, height: 20.h, borderRadius: 6),
            SizedBox(height: 8.h),
            AppShimmer.box(width: 220.w, height: 12.h, borderRadius: 4),
            SizedBox(height: 12.h),
            AppShimmer.box(width: 138.w, height: 44.h, borderRadius: 8),
            SizedBox(height: 8.h),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                3,
                (_) => Padding(
                  padding: EdgeInsets.symmetric(horizontal: 2.w),
                  child: AppShimmer.box(width: 10.w, height: 6.h, borderRadius: 8),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class WardrobeGridShimmer extends StatelessWidget {
  const WardrobeGridShimmer({super.key, this.rows = 2});

  final int rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(rows, (rowIndex) {
        return Padding(
          padding: EdgeInsets.only(top: rowIndex == 0 ? 0 : 24.h),
          child: Row(
            children: [
              Expanded(child: _WardrobeCardShimmer()),
              SizedBox(width: 20.w),
              Expanded(child: _WardrobeCardShimmer()),
            ],
          ),
        );
      }),
    );
  }
}

class _WardrobeCardShimmer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return AppShimmer(
      child: Container(
        height: 180.h,
        decoration: BoxDecoration(
          color: AppShimmer.baseColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColours.primary.withOpacity(0.55),
            width: 0.5,
          ),
        ),
        padding: EdgeInsets.all(12.w),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            AppShimmer.box(width: double.infinity, height: 12.h, borderRadius: 4),
            SizedBox(height: 6.h),
            AppShimmer.box(width: 80.w, height: 8.h, borderRadius: 4),
            SizedBox(height: 12.h),
            AppShimmer.box(width: 80.w, height: 28.h, borderRadius: 6),
          ],
        ),
      ),
    );
  }
}

class EssentialsBannerShimmer extends StatelessWidget {
  const EssentialsBannerShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return AppShimmer(
      child: Container(
        width: double.maxFinite,
        height: 180.h,
        decoration: BoxDecoration(
          color: AppShimmer.baseColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: AppColours.primary.withOpacity(0.25),
            width: 1.2,
          ),
        ),
        padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 14.h),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppShimmer.box(width: 140.w, height: 16.h, borderRadius: 4),
                  SizedBox(height: 8.h),
                  AppShimmer.box(width: 180.w, height: 8.h, borderRadius: 4),
                ],
              ),
            ),
            AppShimmer.box(width: 100.w, height: 30.h, borderRadius: 8),
          ],
        ),
      ),
    );
  }
}

class HomeScreenShimmer extends StatelessWidget {
  const HomeScreenShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 20.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: 20.h),
          const HomeHeaderShimmer(),
          SizedBox(height: 16.h),
          AppShimmer(
            child: AppShimmer.box(
              width: double.infinity,
              height: 2,
              borderRadius: 1,
            ),
          ),
          SizedBox(height: 16.h),
          const BannerShimmer(),
          SizedBox(height: 32.h),
          AppShimmer(
            child: AppShimmer.box(width: 210.w, height: 22.h, borderRadius: 6),
          ),
          SizedBox(height: 20.h),
          const WardrobeGridShimmer(rows: 2),
          SizedBox(height: 24.h),
          const EssentialsBannerShimmer(),
          SizedBox(height: 40.h),
        ],
      ),
    );
  }
}

class ProfileCardShimmer extends StatelessWidget {
  const ProfileCardShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return AppShimmer(
      child: Container(
        width: double.maxFinite,
        padding: EdgeInsets.symmetric(vertical: 24.h),
        decoration: BoxDecoration(
          color: const Color(0xFF0E1220),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: AppColours.primary.withOpacity(0.25),
            width: 0.8,
          ),
        ),
        child: Column(
          children: [
            AppShimmer.circle(86.h),
            SizedBox(height: 12.h),
            AppShimmer.box(width: 160.w, height: 22.h, borderRadius: 6),
            SizedBox(height: 8.h),
            AppShimmer.box(width: 120.w, height: 12.h, borderRadius: 4),
            SizedBox(height: 8.h),
            AppShimmer.box(width: 100.w, height: 12.h, borderRadius: 4),
          ],
        ),
      ),
    );
  }
}

class MembershipCardShimmer extends StatelessWidget {
  const MembershipCardShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return AppShimmer(
      child: Container(
        padding: EdgeInsets.all(24.w),
        decoration: BoxDecoration(
          color: AppShimmer.baseColor,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: AppColours.primary.withOpacity(0.2),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppShimmer.box(width: 200.w, height: 24.h, borderRadius: 6),
            SizedBox(height: 12.h),
            AppShimmer.box(width: double.infinity, height: 14.h, borderRadius: 4),
            SizedBox(height: 8.h),
            AppShimmer.box(width: double.infinity, height: 14.h, borderRadius: 4),
            SizedBox(height: 20.h),
            ...List.generate(
              3,
              (_) => Padding(
                padding: EdgeInsets.only(bottom: 12.h),
                child: Row(
                  children: [
                    AppShimmer.circle(18.h),
                    SizedBox(width: 12.w),
                    Expanded(
                      child: AppShimmer.box(
                        width: double.infinity,
                        height: 12.h,
                        borderRadius: 4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: 12.h),
            AppShimmer.box(
              width: double.infinity,
              height: 52.h,
              borderRadius: 12,
            ),
          ],
        ),
      ),
    );
  }
}

class PlanGridShimmer extends StatelessWidget {
  const PlanGridShimmer({super.key, this.count = 4});

  final int count;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: count,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12.w,
        mainAxisSpacing: 16.h,
        childAspectRatio: 0.91,
      ),
      itemBuilder: (_, __) => const _PlanCardShimmer(),
    );
  }
}

class _PlanCardShimmer extends StatelessWidget {
  const _PlanCardShimmer();

  @override
  Widget build(BuildContext context) {
    return AppShimmer(
      child: Container(
        padding: EdgeInsets.all(16.w),
        decoration: BoxDecoration(
          color: AppShimmer.baseColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColours.primary.withOpacity(0.2)),
        ),
        child: Column(
          children: [
            AppShimmer.box(width: 80.w, height: 14.h, borderRadius: 4),
            SizedBox(height: 8.h),
            AppShimmer.box(width: 100.w, height: 14.h, borderRadius: 4),
            SizedBox(height: 12.h),
            ...List.generate(
              3,
              (_) => Padding(
                padding: EdgeInsets.only(bottom: 6.h),
                child: AppShimmer.box(
                  width: double.infinity,
                  height: 8.h,
                  borderRadius: 4,
                ),
              ),
            ),
            const Spacer(),
            AppShimmer.box(width: 100.w, height: 28.h, borderRadius: 6),
          ],
        ),
      ),
    );
  }
}

class EditProfileShimmer extends StatelessWidget {
  const EditProfileShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 20.h),
      child: AppShimmer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppShimmer.box(
              width: double.infinity,
              height: 2,
              borderRadius: 2,
            ),
            SizedBox(height: 20.h),
            Center(child: AppShimmer.circle(100.h)),
            SizedBox(height: 24.h),
            ...List.generate(8, (index) {
              return Padding(
                padding: EdgeInsets.only(bottom: 16.h),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppShimmer.box(width: 100.w, height: 10.h, borderRadius: 4),
                    SizedBox(height: 8.h),
                    AppShimmer.box(
                      width: double.infinity,
                      height: 48.h,
                      borderRadius: 10,
                    ),
                  ],
                ),
              );
            }),
            AppShimmer.box(
              width: double.infinity,
              height: 52.h,
              borderRadius: 12,
            ),
          ],
        ),
      ),
    );
  }
}
