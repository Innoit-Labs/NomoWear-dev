import 'package:flutter/material.dart';
import 'package:nomowear/core/app_export.dart';
import 'package:nomowear/core/network/api_exception.dart';
import 'package:nomowear/features/orders/data/models/order_history.dart';
import 'package:nomowear/features/orders/data/order_repository.dart';
import 'package:nomowear/features/orders/data/pending_return_store.dart';
import 'package:nomowear/features/orders/data/user_order_mapper.dart';
import 'package:nomowear/features/profile/data/profile_repository.dart';

class OrderTrackingScreen extends StatefulWidget {
  final String orderId;

  const OrderTrackingScreen({super.key, required this.orderId});

  @override
  State<OrderTrackingScreen> createState() => _OrderTrackingScreenState();
}

class _OrderTrackingScreenState extends State<OrderTrackingScreen> {
  final OrderRepository _orderRepository = OrderRepository();
  final ProfileRepository _profileRepository = ProfileRepository();

  bool _isLoading = true;
  String? _errorMessage;
  OrderHistoryItem? _order;
  String _addressLines = '';
  String _contactName = '';

  @override
  void initState() {
    super.initState();
    _loadOrder();
  }

  Future<void> _loadOrder() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final detail = await _orderRepository.getOrderDetail(widget.orderId);
      final customer = await _profileRepository.getProfile();
      await PendingReturnStore.instance.ensureLoaded();
      final mapped = UserOrderMapper.fromHistoryItem(detail, customer: customer);

      if (!mounted) return;
      setState(() {
        _order = detail;
        _addressLines = mapped.addressLines;
        _contactName = customer.fullName ?? '';
        _isLoading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Unable to load order tracking. Please try again.';
      });
    }
  }

  String get _headline {
    final status = _order?.trackingCurrentStatus ?? '';
    switch (status) {
      case 'RETURN_APPROVED':
      case 'APPROVED':
        return 'RETURN APPROVED';
      case 'RETURNED':
        return 'RETURNED';
      case 'RETURN_REQUESTED':
      case 'RETURN_PENDING':
      case 'PICKUP_SCHEDULED':
        return 'RETURN REQUESTED';
      case 'DELIVERED':
      case 'COMPLETED':
        return 'DELIVERED';
      case 'DISPATCHED':
        return 'OUT FOR DELIVERY';
      case 'PROCESSING':
      case 'CONFIRMED':
        return 'PREPARING YOUR ORDER';
      default:
        return 'ARRIVING SOON';
    }
  }

  String get _statusChip {
    final status = _order?.trackingCurrentStatus ?? '';
    switch (status) {
      case 'RETURN_APPROVED':
      case 'APPROVED':
        return 'Return Approved';
      case 'RETURNED':
        return 'Returned';
      case 'RETURN_REQUESTED':
      case 'RETURN_PENDING':
      case 'PICKUP_SCHEDULED':
        return 'Return Requested';
      case 'DELIVERED':
      case 'COMPLETED':
        return 'Delivered';
      case 'DISPATCHED':
        return 'In Transit';
      case 'PROCESSING':
        return 'Processing';
      case 'CONFIRMED':
        return 'Confirmed';
      default:
        return 'Order Placed';
    }
  }

  Color get _statusChipColor {
    final status = _order?.trackingCurrentStatus ?? '';
    if (status == 'RETURN_APPROVED' ||
        status == 'APPROVED' ||
        status == 'RETURNED' ||
        status == 'RETURN_REQUESTED' ||
        status == 'RETURN_PENDING' ||
        status == 'PICKUP_SCHEDULED') {
      return Colors.green;
    }
    if (status == 'DELIVERED' || status == 'COMPLETED') return Colors.green;
    if (status == 'DISPATCHED') return Colors.green;
    return AppColours.primary;
  }

  List<_TrackingStepData> get _deliveryTrackingSteps {
    final order = _order;
    if (order == null) return const [];

    final config = order.orderStatusConfig;
    var deliveryConfig = config
        .where((item) => !UserOrderMapper.isReturnTimelineStatus(item.status))
        .toList(growable: false);

    if (deliveryConfig.isEmpty) {
      final historyDelivery = order.statusHistory
          .where((entry) => !UserOrderMapper.isReturnTimelineStatus(entry.status))
          .toList();
      if (historyDelivery.isNotEmpty) {
        return historyDelivery
            .map(
              (entry) => _TrackingStepData(
                title: entry.status.toUpperCase(),
                subtitle: UserOrderMapper.formatTrackingTimestamp(entry.timestamp),
                isCompleted: true,
                isCurrent: entry.status.toUpperCase() ==
                    order.normalizedOrderStatus,
              ),
            )
            .toList();
      }
      deliveryConfig = const [
        OrderStatusConfigItem(status: 'PENDING', label: 'Order Placed'),
        OrderStatusConfigItem(status: 'CONFIRMED', label: 'Order Confirmed'),
        OrderStatusConfigItem(status: 'PROCESSING', label: 'Processing'),
        OrderStatusConfigItem(status: 'DISPATCHED', label: 'Dispatched'),
        OrderStatusConfigItem(status: 'DELIVERED', label: 'Delivered'),
      ];
    }

    final currentStatus = order.normalizedOrderStatus;
    final currentIndex = deliveryConfig.indexWhere(
      (item) => item.status.trim().toUpperCase() == currentStatus,
    );

    final historyByStatus = order.trackingTimestampsByStatus;
    final isDelivered = order.isDelivered;

    return deliveryConfig.asMap().entries.map((entry) {
      final index = entry.key;
      final item = entry.value;
      final normalized = item.status.trim().toUpperCase();
      final timestamp = historyByStatus[normalized];
      final isCompleted = timestamp != null ||
          isDelivered ||
          (currentIndex >= 0 && index < currentIndex) ||
          (normalized == 'DELIVERED' && isDelivered);
      final isCurrent = !isDelivered && (currentIndex == index);

      return _TrackingStepData(
        title: item.label.toUpperCase(),
        subtitle: timestamp != null
            ? UserOrderMapper.formatTrackingTimestamp(timestamp)
            : (isCompleted
                ? 'Completed'
                : (isCurrent ? 'In progress' : 'Pending')),
        isCompleted: isCompleted,
        isCurrent: isCurrent,
      );
    }).toList();
  }

  List<_TrackingStepData> get _returnTrackingSteps {
    final order = _order;
    if (order == null) return const [];

    int returnStatusRank(String status) {
      final s = status.trim().toUpperCase();
      if (s == 'RETURN_REQUESTED' ||
          s == 'RETURN_PENDING' ||
          s == 'PICKUP_SCHEDULED') {
        return 1;
      }
      if (s == 'APPROVED' || s == 'RETURN_APPROVED') {
        return 2;
      }
      if (s == 'RETURNED' || s == 'RETURNED_TO_IAP') {
        return 3;
      }
      return 4;
    }

    final config = order.orderStatusConfig;
    var returnConfig = config
        .where((item) => UserOrderMapper.isReturnTimelineStatus(item.status))
        .toList();

    if (returnConfig.isEmpty) {
      final historyReturn = order.statusHistory
          .where((entry) => UserOrderMapper.isReturnTimelineStatus(entry.status))
          .toList();
      if (historyReturn.isNotEmpty) {
        returnConfig = historyReturn
            .map(
              (entry) => OrderStatusConfigItem(
                status: entry.status.toUpperCase(),
                label: entry.status.toUpperCase().replaceAll('_', ' '),
              ),
            )
            .toList();
      } else {
        returnConfig = const [
          OrderStatusConfigItem(
            status: 'RETURN_REQUESTED',
            label: 'RETURN REQUESTED',
          ),
          OrderStatusConfigItem(
            status: 'APPROVED',
            label: 'APPROVED',
          ),
          OrderStatusConfigItem(
            status: 'RETURNED',
            label: 'RETURNED',
          ),
        ];
      }
    }

    // Ensure the return steps are strictly in the order:
    // 1. RETURN_REQUESTED
    // 2. APPROVED
    // 3. RETURNED
    returnConfig.sort(
      (a, b) => returnStatusRank(a.status).compareTo(returnStatusRank(b.status)),
    );

    final historyByStatus = order.trackingTimestampsByStatus;
    final returnStatus = order.returnStatus?.trim().toUpperCase() ?? '';
    final orderStatus = order.normalizedOrderStatus;

    final isFinalReturnDone = order.returnedAt != null ||
        returnStatus == 'RETURNED' ||
        returnStatus == 'RETURNED_TO_IAP' ||
        orderStatus == 'RETURNED' ||
        orderStatus == 'RETURNED_TO_IAP';

    int currentReturnIndex = -1;
    if (isFinalReturnDone) {
      currentReturnIndex = returnConfig.indexWhere((item) {
        final s = item.status.trim().toUpperCase();
        return s == 'RETURNED' || s == 'RETURNED_TO_IAP';
      });
    } else if (returnStatus == 'APPROVED' ||
        returnStatus == 'RETURN_APPROVED' ||
        orderStatus == 'APPROVED' ||
        orderStatus == 'RETURN_APPROVED') {
      currentReturnIndex = returnConfig.indexWhere((item) {
        final s = item.status.trim().toUpperCase();
        return s == 'APPROVED' || s == 'RETURN_APPROVED';
      });
    } else if (returnStatus == 'RETURN_REQUESTED' ||
        returnStatus == 'RETURN_PENDING' ||
        returnStatus == 'PICKUP_SCHEDULED' ||
        orderStatus == 'RETURN_REQUESTED' ||
        order.isInReturnFlow ||
        PendingReturnStore.instance.contains(order.id)) {
      currentReturnIndex = returnConfig.indexWhere((item) {
        final s = item.status.trim().toUpperCase();
        return s == 'RETURN_REQUESTED' ||
            s == 'RETURN_PENDING' ||
            s == 'PICKUP_SCHEDULED';
      });
    }

    if (currentReturnIndex < 0 && !isFinalReturnDone) {
      for (int i = returnConfig.length - 1; i >= 0; i--) {
        final s = returnConfig[i].status.trim().toUpperCase();
        if (historyByStatus.containsKey(s) ||
            (s == 'APPROVED' && historyByStatus.containsKey('RETURN_APPROVED')) ||
            (s == 'RETURN_APPROVED' && historyByStatus.containsKey('APPROVED')) ||
            (s == 'RETURNED' && historyByStatus.containsKey('RETURNED_TO_IAP'))) {
          currentReturnIndex = i;
          break;
        }
      }
    }

    return returnConfig.asMap().entries.map((entry) {
      final index = entry.key;
      final item = entry.value;
      final normalized = item.status.trim().toUpperCase();
      final timestamp = historyByStatus[normalized] ??
          (normalized == 'APPROVED'
              ? historyByStatus['RETURN_APPROVED']
              : (normalized == 'RETURN_APPROVED'
                  ? historyByStatus['APPROVED']
                  : (normalized == 'RETURNED'
                      ? historyByStatus['RETURNED_TO_IAP']
                      : null)));

      final isCompleted = timestamp != null ||
          isFinalReturnDone ||
          (currentReturnIndex >= 0 && index < currentReturnIndex);

      final isCurrent = !isFinalReturnDone &&
          !isCompleted &&
          (currentReturnIndex == index);

      return _TrackingStepData(
        title: item.label.toUpperCase(),
        subtitle: timestamp != null
            ? UserOrderMapper.formatTrackingTimestamp(timestamp)
            : (isCompleted
                ? 'Completed'
                : (isCurrent ? 'In progress' : 'Pending')),
        isCompleted: isCompleted,
        isCurrent: isCurrent,
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1012),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F1012),
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppColours.primary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Order Tracking',
          style: TextStyle(
            color: AppColours.primary,
            fontSize: 20.fSize,
            fontWeight: FontWeight.bold,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Container(
            height: 2,
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Color(0xFFE6C27A).withOpacity(0.15),
                  Color(0xFFE6C27A),
                  Color(0xFFE6C27A).withOpacity(0.15),
                ],
              ),
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(color: AppColours.primary),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 24.w),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 14.fSize),
              ),
              SizedBox(height: 16.h),
              OutlinedButton(
                onPressed: _loadOrder,
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

    final order = _order;
    if (order == null) {
      return const Center(
        child: Text('Order not found', style: TextStyle(color: Colors.white70)),
      );
    }

    final deliverySteps = _deliveryTrackingSteps;
    final returnSteps = _returnTrackingSteps;

    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 24.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ORDER ID: ${order.orderNumber}',
            style: TextStyle(
              color: AppColours.primary,
              fontSize: 10.fSize,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          SizedBox(height: 12.h),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _headline,
                style: TextStyle(
                  fontSize: 18.fSize,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                _statusChip,
                style: TextStyle(
                  color: _statusChipColor,
                  fontSize: 14.fSize,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          SizedBox(height: 16.h),
          Container(
            width: double.maxFinite,
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
            decoration: BoxDecoration(
              color: const Color(0xFF16181D),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColours.primary.withOpacity(0.5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'DELIVERY DATE',
                  style: TextStyle(fontSize: 10.fSize),
                ),
                SizedBox(height: 4.h),
                Text(
                  UserOrderMapper.formatDeliveryWindow(order),
                  style: TextStyle(
                    fontSize: 14.fSize,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 24.h),
          if (order.pickupDetails != null &&
              (order.shouldShowReturnTimeline ||
                  order.isInReturnFlow ||
                  PendingReturnStore.instance.contains(order.id))) ...[
            _buildPickupCard(order.pickupDetails!),
            SizedBox(height: 24.h),
          ],
          Divider(color: AppColours.primary, thickness: 0.2),
          SizedBox(height: 24.h),
          Text(
            'ORDER TRACKING',
            style: CustomTextStyles.montserratBold.copyWith(
              color: AppColours.primary,
              fontSize: 14.fSize,
              letterSpacing: 2.0,
            ),
          ),
          SizedBox(height: 32.h),
          ...deliverySteps.asMap().entries.map(
            (entry) => _buildTrackingStep(
              title: entry.value.title,
              subtitle: entry.value.subtitle,
              isCompleted: entry.value.isCompleted,
              isCurrent: entry.value.isCurrent,
              isLast: entry.key == deliverySteps.length - 1,
            ),
          ),
          if (returnSteps.isNotEmpty) ...[
            SizedBox(height: 24.h),
            Divider(color: AppColours.primary, thickness: 0.2),
            SizedBox(height: 24.h),
            Text(
              'RETURN ORDER TRACKING',
              style: CustomTextStyles.montserratBold.copyWith(
                color: AppColours.primary,
                fontSize: 14.fSize,
                letterSpacing: 2.0,
              ),
            ),
            SizedBox(height: 32.h),
            ...returnSteps.asMap().entries.map(
              (entry) => _buildTrackingStep(
                title: entry.value.title,
                subtitle: entry.value.subtitle,
                isCompleted: entry.value.isCompleted,
                isCurrent: entry.value.isCurrent,
                isLast: entry.key == returnSteps.length - 1,
              ),
            ),
          ],
          SizedBox(height: 24.h),
          Divider(color: AppColours.primary, thickness: 0.2),
          SizedBox(height: 32.h),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48.w,
                height: 48.w,
                decoration: BoxDecoration(
                  color: const Color(0xFF16181D),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColours.primary.withOpacity(0.1)),
                ),
                child: Center(
                  child: Icon(
                    Icons.location_on_outlined,
                    color: AppColours.primary,
                    size: 24,
                  ),
                ),
              ),
              SizedBox(width: 20.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'DELIVERY ADDRESS',
                      style: CustomTextStyles.montserratBold.copyWith(
                        color: AppColours.primary,
                        fontSize: 12.fSize,
                        letterSpacing: 1.5,
                      ),
                    ),
                    SizedBox(height: 12.h),
                    if (_contactName.isNotEmpty)
                      Text(
                        _contactName,
                        style: CustomTextStyles.montserratBold.copyWith(
                          fontSize: 16.fSize,
                        ),
                      ),
                    if (_contactName.isNotEmpty) SizedBox(height: 6.h),
                    Text(
                      _addressLines.isNotEmpty
                          ? _addressLines
                          : 'Address not available',
                      style: CustomTextStyles.openSansRegular.copyWith(
                        fontSize: 13.fSize,
                        height: 1.6,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 40.h),
        ],
      ),
    );
  }

  Widget _buildPickupCard(OrderPickupDetails pickup) {
    final date = pickup.pickupDate?.trim();
    final time = pickup.pickupTime?.trim();
    final schedule = [
      if (date != null && date.isNotEmpty) date,
      if (time != null && time.isNotEmpty) time,
    ].join(', ');

    if (schedule.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.maxFinite,
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
      decoration: BoxDecoration(
        color: const Color(0xFF16181D),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColours.primary.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'PICKUP SCHEDULE',
            style: TextStyle(fontSize: 10.fSize),
          ),
          SizedBox(height: 4.h),
          Text(
            schedule,
            style: TextStyle(
              fontSize: 14.fSize,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrackingStep({
    required String title,
    required String subtitle,
    required bool isCompleted,
    required bool isCurrent,
    required bool isLast,
  }) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 26.w,
            child: Column(
              children: [
                _buildTimelineNode(isCompleted, isCurrent),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2.0,
                      color: isCompleted
                          ? AppColours.primary
                          : const Color(0xFF23252A),
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(width: 20.w),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: 36.h),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: CustomTextStyles.montserratBold.copyWith(
                      color: (isCompleted || isCurrent)
                          ? AppColours.secondary
                          : Colors.white38,
                      fontSize: 14.fSize,
                    ),
                  ),
                  SizedBox(height: 4.h),
                  Text(
                    subtitle,
                    style: CustomTextStyles.openSansRegular.copyWith(
                      color: (isCompleted || isCurrent)
                          ? AppColours.secondary
                          : Colors.white38,
                      fontSize: 12.fSize,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineNode(bool isCompleted, bool isCurrent) {
    if (isCompleted) {
      return Container(
        width: 22.w,
        height: 22.w,
        decoration: const BoxDecoration(
          color: AppColours.primary,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.check, color: Colors.black, size: 14),
      );
    }
    if (isCurrent) {
      return Container(
        width: 22.w,
        height: 22.w,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: AppColours.primary, width: 6.5),
        ),
        child: Center(
          child: Container(
            width: 6.w,
            height: 6.w,
            decoration: const BoxDecoration(
              color: Colors.black,
              shape: BoxShape.circle,
            ),
          ),
        ),
      );
    }
    return Container(
      width: 26.w,
      height: 26.w,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF1A1A22).withOpacity(0.3),
        border: Border.all(
          color: const Color(0xFFA0A0A0).withOpacity(0.3),
          width: 1.5,
        ),
      ),
    );
  }
}

class _TrackingStepData {
  const _TrackingStepData({
    required this.title,
    required this.subtitle,
    required this.isCompleted,
    required this.isCurrent,
  });

  final String title;
  final String subtitle;
  final bool isCompleted;
  final bool isCurrent;
}
