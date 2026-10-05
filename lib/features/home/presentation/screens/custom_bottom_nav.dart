import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:nomowear/core/app_export.dart';
import 'package:nomowear/core/services/auth_storage.dart';
import 'package:nomowear/features/home/presentation/bloc/home_bloc.dart';
import 'package:nomowear/features/cart/presentation/bloc/cart_bloc.dart';

class CustomBottomNav extends StatelessWidget {
  final int currentIndex;

  const CustomBottomNav({
    Key? key,
    required this.currentIndex,
  }) : super(key: key);



  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CartBloc, CartState>(
      buildWhen: (previous, current) => previous.totalItems != current.totalItems,
      builder: (context, cartState) {
        if (kDebugMode) {
          debugPrint('[CART_PERF] REBUILD badge total=${cartState.totalItems}');
        }
        return Container(
          margin: EdgeInsets.fromLTRB(16.w, 0, 16.w, 16.h),
          height: 72.h,
          decoration: BoxDecoration(
            color: const Color(0xFF16181D),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColours.primary.withOpacity(0.30)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFCFAF6E).withOpacity(0.3),
                blurRadius: 8,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _navItem(context, IconConstant.Home, "Home", 0),
              _navItem(context, IconConstant.Categories, "Categories", 1),
              _cartItem(context, cartState.totalItems),
              _navItem(context, IconConstant.Subscription, "Subscription", 3),
              _navItem(context, IconConstant.Profile, "Profile", 4),
            ],
          ),
        );
      },
    );
  }

  Widget _navItem(
      BuildContext context, String icon, String label, int index) {
    final isActive = currentIndex == index;

    return GestureDetector(
      onTap: () {
        if (index == 0) {
          AuthStorage().getAuthToken().then((token) {
            // ignore: avoid_print
            print('════════════ AUTH TOKEN ════════════');
            // ignore: avoid_print
            print(token ?? 'No token stored');
            // ignore: avoid_print
            print('════════════════════════════════════');
          });
        }
        context.read<HomeBloc>().add(ChangeBottomNavEvent(index));
      },
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 8.h),
        decoration: BoxDecoration(
          color: isActive ? Colors.white.withOpacity(0.08) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SvgPicture.asset(
              icon,
              height: 22.fSize,
              width: 22.fSize,
              colorFilter: ColorFilter.mode(
                isActive ? AppColours.primary : Colors.white38,
                BlendMode.srcIn,
              ),
            ),
            SizedBox(height: 4.h),
            Text(
              label,
              style: TextStyle(
                color: isActive ? AppColours.primary : Colors.white38,
                fontSize: 10.fSize,
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cartItem(BuildContext context, int count) {
    final isActive = currentIndex == 2;

    return GestureDetector(
      onTap: () {
        context.read<HomeBloc>().add(ChangeBottomNavEvent(2));
      },
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 8.h),
        decoration: BoxDecoration(
          color: isActive ? Colors.white.withOpacity(0.08) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                SvgPicture.asset(
                  IconConstant.Cart,
                  color: isActive ? AppColours.primary : Colors.white38,
                  height: 22.fSize,
                  width: 22.fSize,
                ),
                if (count > 0)
                  Positioned(
                    top: -4,
                    right: -4,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: AppColours.secondary,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '$count',
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 8.fSize,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            SizedBox(height: 4.h),
            Text(
              'Cart',
              style: TextStyle(
                color: isActive ? AppColours.primary : Colors.white38,
                fontSize: 10.fSize,
              ),
            ),
          ],
        ),
      ),
    );
  }



}