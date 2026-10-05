import 'package:flutter/material.dart';
import 'package:nomowear/core/network/api_exception.dart';
import 'package:nomowear/core/utils/size_utils.dart';
import 'package:nomowear/theme/theme_helper.dart';
import 'package:nomowear/routes/app_routes.dart';
import 'package:nomowear/features/profile/data/profile_repository.dart';
import 'package:nomowear/features/profile/domain/user_order.dart';
import 'package:nomowear/features/orders/data/order_repository.dart';
import 'package:nomowear/features/orders/data/pending_return_store.dart';
import 'package:nomowear/features/orders/data/user_order_mapper.dart';

class MyOrdersScreen extends StatefulWidget {
  const MyOrdersScreen({super.key});

  @override
  State<MyOrdersScreen> createState() => _MyOrdersScreenState();
}

class _MyOrdersScreenState extends State<MyOrdersScreen> {
  final TextEditingController _search = TextEditingController();
  final OrderRepository _orderRepository = OrderRepository();
  final ProfileRepository _profileRepository = ProfileRepository();

  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    if (userOrdersList.isNotEmpty) {
      _isLoading = false;
      // Re-apply waitlisted return flags against any cached list.
      PendingReturnStore.instance.ensureLoaded().then((_) {
        if (!mounted) return;
        setState(() {});
        _loadOrders(forceRefresh: true);
      });
    } else {
      _loadOrders();
    }
  }

  Future<void> _refreshAfterReturn() async {
    await PendingReturnStore.instance.ensureLoaded();
    if (!mounted) return;
    // Prefer local pending flags immediately; then sync from API.
    setState(() {});
    await _loadOrders(forceRefresh: true);
  }

  Future<void> _loadOrders({bool forceRefresh = false}) async {
    if (!forceRefresh && userOrdersList.isNotEmpty) {
      setState(() {
        _isLoading = false;
        _errorMessage = null;
      });
      return;
    }
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await PendingReturnStore.instance.ensureLoaded();
      final history = await _orderRepository.getOrderHistory(
        forceRefresh: forceRefresh,
      );
      final customer = await _profileRepository.getProfile();
      replaceUserOrders(
        UserOrderMapper.fromHistory(history, customer: customer),
      );
      if (mounted) {
        setState(() => _isLoading = false);
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Unable to load orders. Please try again.';
        });
      }
    }
  }

  List<UserOrder> get _filtered {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return List<UserOrder>.from(userOrdersList);
    return userOrdersList.where((o) {
      return o.title.toLowerCase().contains(q) ||
          o.orderIdDisplay.toLowerCase().contains(q);
    }).toList();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final list = _filtered;
    final hasEscalation = userOrdersList.any((o) => o.isReturnEscalated);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 12.h),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.arrow_back, color: AppColours.primary),
                  ),
                  Expanded(
                    child: Text(
                      'My Orders',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColours.primary,
                        fontSize: 18.fSize,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  SizedBox(width: 48.w),
                ],
              ),
            ),
            Container(
              height: 1,
              margin: EdgeInsets.symmetric(horizontal: 20.w),
              color: AppColours.primary.withOpacity(0.35),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(20.w, 18.h, 20.w, 12.h),
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                style: TextStyle(color: Colors.white, fontSize: 14.fSize),
                decoration: InputDecoration(
                  hintText: 'Search in orders',
                  hintStyle: TextStyle(
                    color: AppColours.primary.withOpacity(0.45),
                    fontSize: 14.fSize,
                  ),
                  prefixIcon: Icon(Icons.search, color: AppColours.primary),
                  filled: true,
                  fillColor: const Color(0xFF16181D),
                  contentPadding: EdgeInsets.symmetric(vertical: 14.h),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColours.primary.withOpacity(0.7)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColours.primary, width: 1.2),
                  ),
                ),
              ),
            ),
            if (hasEscalation) ...[
              Padding(
                padding: EdgeInsets.fromLTRB(20.w, 0, 20.w, 12.h),
                child: _EscalationWarningBanner(
                  order: userOrdersList.firstWhere((o) => o.isReturnEscalated),
                  onTap: () => Navigator.pushNamed(
                    context,
                    AppRoutes.orderDetailsScreen,
                    arguments: userOrdersList
                        .firstWhere((o) => o.isReturnEscalated)
                        .id,
                  ).then((_) => _refreshAfterReturn()),
                ),
              ),
            ],
            Expanded(
              child: _isLoading
                  ? Center(
                      child: CircularProgressIndicator(color: AppColours.primary),
                    )
                  : _errorMessage != null
                      ? _ErrorState(
                          message: _errorMessage!,
                          onRetry: () => _loadOrders(forceRefresh: true),
                        )
                      : list.isEmpty
                          ? Center(
                              child: Text(
                                _search.text.trim().isEmpty
                                    ? 'No orders yet.'
                                    : 'No orders match your search.',
                                style: TextStyle(
                                  color: Colors.white54,
                                  fontSize: 14.fSize,
                                ),
                              ),
                            )
                          : RefreshIndicator(
                              color: AppColours.primary,
                              backgroundColor: const Color(0xFF16181D),
                              onRefresh: () => _loadOrders(forceRefresh: true),
                              child: ListView.separated(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 24.h),
                                itemCount: list.length,
                                separatorBuilder: (_, __) => SizedBox(height: 16.h),
                                itemBuilder: (context, i) => _OrderListTile(
                                  order: list[i],
                                  onReturnSubmitted: _refreshAfterReturn,
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

class _EscalationWarningBanner extends StatelessWidget {
  final UserOrder order;
  final VoidCallback onTap;

  const _EscalationWarningBanner({
    required this.order,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final orderDisplay = order.orderIdDisplay.startsWith('#')
        ? order.orderIdDisplay
        : '#${order.orderIdDisplay}';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
        decoration: BoxDecoration(
          color: const Color(0xFF2E1517),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: const Color(0xFFEF4444).withValues(alpha: 0.6),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              color: Color(0xFFF87171),
              size: 22,
            ),
            SizedBox(width: 10.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'DISPATCH HOLD: RETURN REQUIRED',
                    style: TextStyle(
                      color: const Color(0xFFFCA5A5),
                      fontSize: 11.fSize,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                  SizedBox(height: 2.h),
                  Text(
                    'Pickup for $orderDisplay was not completed. Reattempt pickup to unlock new bookings.',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.85),
                      fontSize: 10.5.fSize,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: 8.w),
            const Icon(
              Icons.arrow_forward_ios_rounded,
              color: Color(0xFFFCA5A5),
              size: 13,
            ),
          ],
        ),
      ),
    );
  }
}

class _OrderListTile extends StatelessWidget {
  final UserOrder order;
  final Future<void> Function()? onReturnSubmitted;

  const _OrderListTile({
    required this.order,
    this.onReturnSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.pushNamed(
        context,
        AppRoutes.orderDetailsScreen,
        arguments: order.id,
      ).then((_) => onReturnSubmitted?.call()),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: EdgeInsets.all(10.w),
        decoration: BoxDecoration(
          color: const Color(0xFF070711),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            /// IMAGE COLLAGE / THUMBNAIL
            _CoverThumb(order: order),

            SizedBox(width: 12.w),

            /// RIGHT SIDE
            Expanded(
              child: order.isWardrobeKit
                  ? _buildWardrobeKitInfo(context)
                  : _buildNormalOrderInfo(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWardrobeKitInfo(BuildContext context) {
    final orderIdFormatted = order.orderIdDisplay.startsWith('#')
        ? order.orderIdDisplay
        : '#${order.orderIdDisplay}';

    final garmentCountText = order.totalGarmentsCount > 0
        ? '${order.totalGarmentsCount}'
        : order.attributeValue;

    final deliveryDateText = order.deliveryDateFormatted != null &&
            order.deliveryDateFormatted != '-'
        ? order.deliveryDateFormatted!
        : order.statusDate;

    final isDeliveryReattempt = order.isDeliveryReattemptEligible;
    final isReturnPending = order.isReturnReattemptPending;
    final isReturnFailed = order.isReturnFailed;
    final isEscalated = order.isReturnEscalated;

    final statusText = isEscalated
        ? '⚠️ Return Escalated'
        : isReturnFailed
            ? 'Return Failed'
            : isReturnPending
                ? 'Reschedule In Progress'
                : isDeliveryReattempt
                    ? 'Delivery Failed'
                    : deliveryDateText;

    final statusColor = isEscalated || isReturnFailed
        ? const Color(0xFFF87171)
        : isReturnPending
            ? const Color(0xFFFBBF24)
            : isDeliveryReattempt
                ? const Color(0xFFE6C27A)
                : Colors.white;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        /// KIT TITLE
        Text(
          order.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: CustomTextStyles.montserratSemiBold.copyWith(
            fontSize: 14.fSize,
            color: AppColours.primary,
          ),
        ),

        SizedBox(height: 6.h),

        /// ORDER ID
        RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: 'Order Id: ',
                style: CustomTextStyles.montserratSemiBold.copyWith(
                  fontSize: 12.fSize,
                  color: Colors.white,
                ),
              ),
              TextSpan(
                text: orderIdFormatted,
                style: CustomTextStyles.montserratSemiBold.copyWith(
                  fontSize: 12.fSize,
                  color: Colors.white.withOpacity(0.85),
                ),
              ),
            ],
          ),
        ),

        SizedBox(height: 4.h),

        /// NO OF GARMENTS
        Text(
          'No of Garments: $garmentCountText',
          style: CustomTextStyles.montserratSemiBold.copyWith(
            fontSize: 12.fSize,
            color: Colors.white,
          ),
        ),

        SizedBox(height: 4.h),

        /// STATUS LINE
        RichText(
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          text: TextSpan(
            children: [
              TextSpan(
                text: '${order.statusLabel}: ',
                style: CustomTextStyles.montserratSemiBold.copyWith(
                  fontSize: 12.fSize,
                  color: Colors.white,
                ),
              ),
              TextSpan(
                text: statusText,
                style: CustomTextStyles.montserratSemiBold.copyWith(
                  fontSize: 12.fSize,
                  color: statusColor,
                  fontWeight: isEscalated || isReturnFailed || isReturnPending || isDeliveryReattempt
                      ? FontWeight.bold
                      : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),

        SizedBox(height: 10.h),

        /// ACTION BUTTON
        SizedBox(
          width: double.infinity,
          height: 38.h,
          child: isDeliveryReattempt
              ? ElevatedButton(
                  onPressed: () => Navigator.pushNamed(
                    context,
                    AppRoutes.orderDetailsScreen,
                    arguments: order.id,
                  ).then((_) => onReturnSubmitted?.call()),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD8B26A),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: EdgeInsets.zero,
                  ),
                  child: Text(
                    'Schedule Delivery Reattempt',
                    style: TextStyle(
                      fontSize: 11.5.fSize,
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                )
              : isReturnPending
                  ? OutlinedButton(
                      onPressed: null,
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: const Color(0xFFF59E0B).withValues(alpha: 0.5),
                          width: 1,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: EdgeInsets.zero,
                      ),
                      child: Text(
                        'Pickup Reschedule In Progress',
                        style: TextStyle(
                          fontSize: 11.fSize,
                          color: const Color(0xFFF59E0B),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    )
                  : isReturnFailed
                      ? ElevatedButton(
                          onPressed: () => Navigator.pushNamed(
                            context,
                            AppRoutes.orderDetailsScreen,
                            arguments: order.id,
                          ).then((_) => onReturnSubmitted?.call()),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFD8B26A),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: EdgeInsets.zero,
                          ),
                          child: Text(
                            '⇪ Reattempt Pickup',
                            style: TextStyle(
                              fontSize: 12.fSize,
                              color: Colors.black,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        )
                      : OutlinedButton(
                          onPressed: () async {
                            if (!order.canReturn) {
                              Navigator.pushNamed(
                                context,
                                AppRoutes.orderTrackingScreen,
                                arguments: order.id,
                              );
                              return;
                            }
                            final submitted = await Navigator.pushNamed(
                              context,
                              AppRoutes.returnOrderScreen,
                              arguments: {
                                'orderId': order.id,
                                'orderNumber': order.orderIdDisplay,
                              },
                            );
                            if (submitted == true && context.mounted) {
                              await onReturnSubmitted?.call();
                              if (!context.mounted) return;
                              Navigator.pushNamed(
                                context,
                                AppRoutes.orderTrackingScreen,
                                arguments: order.id,
                              );
                            }
                          },
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(
                              color: AppColours.primary.withOpacity(0.45),
                              width: 1,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: EdgeInsets.zero,
                          ),
                          child: Text(
                            order.actionLabel,
                            style: CustomTextStyles.openSansSemiBold.copyWith(
                              fontSize: 11.fSize,
                              color: Colors.white,
                            ),
                          ),
                        ),
        ),
      ],
    );
  }

  Widget _buildNormalOrderInfo(BuildContext context) {
    final isDeliveryReattempt = order.isDeliveryReattemptEligible;
    final isReturnPending = order.isReturnReattemptPending;
    final isReturnFailed = order.isReturnFailed;
    final isEscalated = order.isReturnEscalated;

    final statusText = isEscalated
        ? '⚠️ Return Escalated'
        : isReturnFailed
            ? 'Return Failed'
            : isReturnPending
                ? 'Reschedule In Progress'
                : isDeliveryReattempt
                    ? 'Delivery Failed'
                    : order.statusDate;

    final statusColor = isEscalated || isReturnFailed
        ? const Color(0xFFF87171)
        : isReturnPending
            ? const Color(0xFFFBBF24)
            : isDeliveryReattempt
                ? const Color(0xFFE6C27A)
                : Colors.white;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        /// TITLE
        Text(
          order.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: CustomTextStyles.montserratSemiBold.copyWith(
            fontSize: 14.fSize,
            color: AppColours.primary,
          ),
        ),

        SizedBox(height: 4.h),

        /// ORDER ID
        RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: 'Order Id: ',
                style: CustomTextStyles.montserratSemiBold.copyWith(
                  fontSize: 12.fSize,
                  color: Colors.white,
                ),
              ),
              TextSpan(
                text: order.orderIdDisplay.startsWith('#')
                    ? order.orderIdDisplay
                    : '#${order.orderIdDisplay}',
                style: CustomTextStyles.montserratSemiBold.copyWith(
                  fontSize: 12.fSize,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),

        SizedBox(height: 4.h),

        /// ATTRIBUTE
        Text(
          '${order.attributeLabel}: ${order.attributeValue}',
          style: CustomTextStyles.montserratSemiBold.copyWith(
            fontSize: 12.fSize,
            color: Colors.white,
          ),
        ),

        SizedBox(height: 4.h),

        /// STATUS LINE
        RichText(
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          text: TextSpan(
            children: [
              TextSpan(
                text: '${order.statusLabel}: ',
                style: CustomTextStyles.montserratSemiBold.copyWith(
                  fontSize: 12.fSize,
                  color: Colors.white,
                ),
              ),
              TextSpan(
                text: statusText,
                style: CustomTextStyles.montserratSemiBold.copyWith(
                  fontSize: 12.fSize,
                  color: statusColor,
                  fontWeight: isEscalated || isReturnFailed || isReturnPending || isDeliveryReattempt
                      ? FontWeight.bold
                      : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),

        SizedBox(height: 12.h),

        /// BUTTON
        SizedBox(
          width: double.infinity,
          height: 42.h,
          child: isDeliveryReattempt
              ? ElevatedButton(
                  onPressed: () => Navigator.pushNamed(
                    context,
                    AppRoutes.orderDetailsScreen,
                    arguments: order.id,
                  ).then((_) => onReturnSubmitted?.call()),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD8B26A),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'Schedule Delivery Reattempt',
                    style: TextStyle(
                      fontSize: 12.fSize,
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                )
              : isReturnPending
                  ? OutlinedButton(
                      onPressed: null,
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: const Color(0xFFF59E0B).withValues(alpha: 0.5),
                          width: 1,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'Pickup Reschedule In Progress',
                        style: TextStyle(
                          fontSize: 11.fSize,
                          color: const Color(0xFFF59E0B),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    )
                  : isReturnFailed
                      ? ElevatedButton(
                          onPressed: () => Navigator.pushNamed(
                            context,
                            AppRoutes.orderDetailsScreen,
                            arguments: order.id,
                          ).then((_) => onReturnSubmitted?.call()),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFD8B26A),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            '⇪ Reattempt Pickup',
                            style: TextStyle(
                              fontSize: 12.fSize,
                              color: Colors.black,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        )
                      : order.canReturn
                          ? ElevatedButton(
                              onPressed: () async {
                                final submitted = await Navigator.pushNamed(
                                  context,
                                  AppRoutes.returnOrderScreen,
                                  arguments: {
                                    'orderId': order.id,
                                    'orderNumber': order.orderIdDisplay,
                                  },
                                );
                                if (submitted == true && context.mounted) {
                                  await onReturnSubmitted?.call();
                                  if (!context.mounted) return;
                                  Navigator.pushNamed(
                                    context,
                                    AppRoutes.orderTrackingScreen,
                                    arguments: order.id,
                                  );
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFD8B26A),
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: Text(
                                order.actionLabel,
                                style: TextStyle(
                                  color: Colors.black,
                                  fontSize: 13.fSize,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            )
                          : !order.isDelivered || order.isInReturnFlow
                              ? OutlinedButton(
                                  onPressed: () => Navigator.pushNamed(
                                    context,
                                    AppRoutes.orderTrackingScreen,
                                    arguments: order.id,
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    side: BorderSide(
                                      color: order.isInReturnFlow
                                          ? const Color(0xFFD8B26A)
                                          : const Color(0x66E6C27A),
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: Text(
                                    order.actionLabel,
                                    style: CustomTextStyles.openSansSemiBold.copyWith(
                                      fontSize: 10,
                                      color: order.isInReturnFlow
                                          ? Colors.white
                                          : AppColours.secondary,
                                    ),
                                  ),
                                )
                              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

class _CoverThumb extends StatelessWidget {
  final UserOrder order;

  const _CoverThumb({required this.order});

  @override
  Widget build(BuildContext context) {
    const width = 118.0;
    const height = 135.0;
    final images = order.coverImageAssets;

    if (images.isEmpty) {
      return Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: const Color(0xFFD8B26A),
            width: 1.2,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(11),
          child: _OrderImage(
            source: '',
            width: width,
            height: height,
            fit: BoxFit.cover,
          ),
        ),
      );
    }

    if (images.length == 1) {
      return Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: const Color(0xFFD8B26A),
            width: 1.2,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(11),
          child: _OrderImage(
            source: images.first,
            width: width,
            height: height,
            fit: BoxFit.cover,
          ),
        ),
      );
    }

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFD8B26A),
          width: 1.2,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: _buildCollageContent(images),
      ),
    );
  }

  Widget _buildCollageContent(List<String> images) {
    if (images.length == 2) {
      return Row(
        children: [
          Expanded(
            child: _OrderImage(
              source: images[0],
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 1.5),
          Expanded(
            child: _OrderImage(
              source: images[1],
              fit: BoxFit.cover,
            ),
          ),
        ],
      );
    }

    if (images.length == 3) {
      return Column(
        children: [
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: _OrderImage(
                    source: images[0],
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(width: 1.5),
                Expanded(
                  child: _OrderImage(
                    source: images[1],
                    fit: BoxFit.cover,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 1.5),
          Expanded(
            child: _OrderImage(
              source: images[2],
              fit: BoxFit.cover,
            ),
          ),
        ],
      );
    }

    // 4 or more garments
    final showOverlay = images.length > 4;
    final remainingCount = images.length - 3;

    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: _OrderImage(
                  source: images[0],
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 1.5),
              Expanded(
                child: _OrderImage(
                  source: images[1],
                  fit: BoxFit.cover,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 1.5),
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: _OrderImage(
                  source: images[2],
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 1.5),
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _OrderImage(
                      source: images[3],
                      fit: BoxFit.cover,
                    ),
                    if (showOverlay)
                      Container(
                        color: Colors.black.withOpacity(0.65),
                        alignment: Alignment.center,
                        child: Text(
                          '+$remainingCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _OrderImage extends StatelessWidget {
  final String source;
  final double? width;
  final double? height;
  final BoxFit fit;

  const _OrderImage({
    required this.source,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
  });

  bool get _isNetwork =>
      source.startsWith('http://') || source.startsWith('https://');

  @override
  Widget build(BuildContext context) {
    if (_isNetwork) {
      return Image.network(
        source,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (_, __, ___) => _placeholder(),
      );
    }

    return Image.asset(
      source,
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (_, __, ___) => _placeholder(),
    );
  }

  Widget _placeholder() {
    return Container(
      width: width,
      height: height,
      color: const Color(0xFF16181D),
      alignment: Alignment.center,
      child: Icon(Icons.image_outlined, color: AppColours.primary.withOpacity(0.5)),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 24.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 14.fSize),
            ),
            SizedBox(height: 16.h),
            OutlinedButton(
              onPressed: onRetry,
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: AppColours.primary.withOpacity(0.9)),
                foregroundColor: AppColours.primary,
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
