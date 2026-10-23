import 'package:nomowear/core/app_export.dart';
import 'package:nomowear/core/network/api_exception.dart';
import 'package:nomowear/features/orders/data/models/order_history.dart';
import 'package:nomowear/features/orders/data/models/refund_status_result.dart';
import 'package:nomowear/features/orders/data/order_repository.dart';
import 'package:nomowear/features/orders/data/pending_refund_store.dart';
import 'package:nomowear/features/orders/data/pending_return_store.dart';
import 'package:nomowear/features/orders/data/user_order_mapper.dart';
import 'package:nomowear/features/profile/data/profile_repository.dart';
import 'package:nomowear/features/profile/domain/user_order.dart';

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
  UserOrder? _userOrder;
  RefundStatusResult? _refundStatus;
  String _addressLines = '';
  String _contactName = '';
  String _contactMobile = '';

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
      await PendingRefundStore.instance.ensureLoaded();
      final mapped = UserOrderMapper.fromHistoryItem(detail, customer: customer);
      final refundStatus = await _loadRefundStatus(detail);

      String resolvedAddress = mapped.addressLines.trim();
      if (resolvedAddress.isEmpty || UserOrderMapper.isIapAddress(resolvedAddress)) {
        if (customer.primaryAddress != null &&
            !UserOrderMapper.isIapAddress(UserOrderMapper.formatAddress(customer.primaryAddress))) {
          resolvedAddress = UserOrderMapper.formatAddress(customer.primaryAddress);
        } else if (customer.addresses.isNotEmpty) {
          for (final a in customer.addresses) {
            final f = UserOrderMapper.formatAddress(a);
            if (f.isNotEmpty && !UserOrderMapper.isIapAddress(f)) {
              resolvedAddress = f;
              break;
            }
          }
        }
      }

      String resolvedName = '';
      if (customer.fullName?.trim().isNotEmpty == true &&
          !UserOrderMapper.isIapAddress(customer.fullName)) {
        resolvedName = customer.fullName!.trim();
      } else if (customer.primaryAddress?.fullName?.trim().isNotEmpty == true &&
          !UserOrderMapper.isIapAddress(customer.primaryAddress!.fullName)) {
        resolvedName = customer.primaryAddress!.fullName!.trim();
      } else if (mapped.pickupFullName?.trim().isNotEmpty == true &&
          !UserOrderMapper.isIapAddress(mapped.pickupFullName)) {
        resolvedName = mapped.pickupFullName!.trim();
      } else {
        for (final a in customer.addresses) {
          final n = a.fullName?.trim() ?? '';
          if (n.isNotEmpty && !UserOrderMapper.isIapAddress(n)) {
            resolvedName = n;
            break;
          }
        }
      }

      String resolvedMobile = '';
      if (customer.mobile.trim().isNotEmpty &&
          !UserOrderMapper.isIapAddress(customer.mobile)) {
        resolvedMobile = customer.mobile.trim();
      } else if (customer.primaryAddress?.phone?.trim().isNotEmpty == true &&
          !UserOrderMapper.isIapAddress(customer.primaryAddress!.phone)) {
        resolvedMobile = customer.primaryAddress!.phone!.trim();
      } else if (mapped.mobileDisplay.trim().isNotEmpty &&
          !UserOrderMapper.isIapAddress(mapped.mobileDisplay)) {
        resolvedMobile = mapped.mobileDisplay.trim();
      } else {
        for (final a in customer.addresses) {
          final p = a.phone?.trim() ?? '';
          if (p.isNotEmpty && !UserOrderMapper.isIapAddress(p)) {
            resolvedMobile = p;
            break;
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _order = detail;
        _userOrder = mapped;
        _refundStatus = refundStatus;
        _addressLines = resolvedAddress;
        _contactName = resolvedName;
        _contactMobile = resolvedMobile;
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

  Future<RefundStatusResult?> _loadRefundStatus(OrderHistoryItem order) async {
    final stored = PendingRefundStore.instance.getWaitlistNumber(order.id);
    final fromRefundRequest = stored != null && stored.trim().isNotEmpty;
    final waitlist = fromRefundRequest
        ? stored.trim()
        : order.waitlistNumber?.trim();
    if (waitlist == null || waitlist.isEmpty) return null;
    try {
      final result = await _orderRepository.getRefundStatus(waitlist);
      if (fromRefundRequest || _isRefundWaitlist(result)) return result;
      return null;
    } catch (_) {
      if (!fromRefundRequest) return null;
      return RefundStatusResult(
        status: 'PENDING',
        waitlistNumber: waitlist,
      );
    }
  }

  bool _isRefundWaitlist(RefundStatusResult result) {
    final type = (result.raw?['waitlist_type'] ?? result.raw?['waitlistType'] ?? '')
        .toString()
        .trim()
        .toUpperCase();
    return type.contains('REFUND');
  }

  String get _headline {
    final status = _order?.trackingCurrentStatus ?? '';
    switch (status) {
      case 'RETURN_APPROVED':
      case 'APPROVED':
        return 'RETURN APPROVED';
      case 'RETURNED':
      case 'RETURNED_TO_IAP':
        return 'RETURN COMPLETED';
      case 'RETURN_REQUESTED':
      case 'RETURN_PENDING':
      case 'PICKUP_SCHEDULED':
        return 'RETURN REQUESTED';
      case 'RETURN_FAILED':
      case 'RETURN_REJECTED':
        return 'RETURN FAILED';
      case 'NOT_DELIVERED':
      case 'DELIVERY_FAILED':
        return 'DELIVERY FAILED';
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
      case 'RETURNED_TO_IAP':
        return 'Return Completed';
      case 'RETURN_REQUESTED':
      case 'RETURN_PENDING':
      case 'PICKUP_SCHEDULED':
        return 'Return Requested';
      case 'RETURN_FAILED':
      case 'RETURN_REJECTED':
        return 'Return Failed';
      case 'NOT_DELIVERED':
      case 'DELIVERY_FAILED':
        return 'Delivery Failed';
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
        status == 'RETURNED_TO_IAP' ||
        status == 'RETURN_REQUESTED' ||
        status == 'RETURN_PENDING' ||
        status == 'PICKUP_SCHEDULED') {
      return Colors.green;
    }
    if (status == 'RETURN_FAILED' ||
        status == 'RETURN_REJECTED' ||
        status == 'NOT_DELIVERED' ||
        status == 'DELIVERY_FAILED') {
      return const Color(0xFFF87171);
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
    if (order == null || order.isReturnComplete) return const [];

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

  List<_TrackingStepData> get _refundTrackingSteps {
    final order = _order;
    if (order == null || !_hasRefundToTrack(order)) return const [];

    final rawStage = _refundStage(order);
    final rejected = rawStage < 0;
    final progress = rejected ? 1 : (rawStage < 1 ? 1 : rawStage);
    final currentIndex = progress >= 3 ? -1 : progress - 1;
    final requestedAt = _refundStatus?.createdAt;

    const titles = ['REFUND REQUESTED', 'APPROVED', 'REFUNDED'];
    return List.generate(titles.length, (index) {
      final title = index == 1 && rejected ? 'REJECTED' : titles[index];
      final isCompleted = progress >= 3 || index < currentIndex;
      final isCurrent = currentIndex == index;
      final subtitle = index == 0 && requestedAt != null && (isCompleted || isCurrent)
          ? UserOrderMapper.formatTrackingTimestamp(requestedAt)
          : (isCompleted
              ? 'Completed'
              : (isCurrent ? 'In progress' : 'Pending'));
      return _TrackingStepData(
        title: title,
        subtitle: subtitle,
        isCompleted: isCompleted,
        isCurrent: isCurrent,
      );
    });
  }

  bool _hasRefundToTrack(OrderHistoryItem order) {
    if (_refundStatus != null) return true;
    if (PendingRefundStore.instance.hasRefundRequest(order.id)) return true;
    return _refundStage(order) != 0 || _isRejectedRefund(order);
  }

  /// A deposit stays PENDING until a refund actually starts.
  String? _depositRefundStatus(String? raw) {
    final status = raw?.trim().toUpperCase() ?? '';
    if (status.isEmpty ||
        status == 'NONE' ||
        status == 'NOT_APPLICABLE' ||
        status == 'PENDING' ||
        status == 'NOT_REFUNDED') {
      return null;
    }
    return status;
  }

  bool _isRejectedRefund(OrderHistoryItem order) {
    bool rejected(String? raw) {
      final status = raw?.trim().toUpperCase() ?? '';
      return status == 'REJECTED' ||
          status == 'FAILED' ||
          status == 'REFUND_REJECTED';
    }

    return rejected(_refundStatus?.status) ||
        rejected(order.refundStatus) ||
        rejected(_depositRefundStatus(order.securityDepositRefundStatus));
  }

  /// 0 = no refund yet, 1 = requested, 2 = approved, 3 = refunded. -1 = rejected.
  int _refundStage(OrderHistoryItem order) {
    var stage = 0;
    var rejected = false;

    void consider(String? raw) {
      final status = raw?.trim().toUpperCase() ?? '';
      if (status.isEmpty || status == 'NONE' || status == 'NOT_APPLICABLE') {
        return;
      }
      if (status == 'REJECTED' ||
          status == 'FAILED' ||
          status == 'REFUND_REJECTED') {
        rejected = true;
        return;
      }
      if (status == 'REFUNDED' ||
          status == 'COMPLETED' ||
          status == 'SUCCESS' ||
          status == 'REFUND_COMPLETED') {
        stage = 3;
        rejected = false;
        return;
      }
      if (status == 'APPROVED' ||
          status == 'PROCESSING' ||
          status == 'REFUND_APPROVED') {
        if (stage < 2) stage = 2;
        return;
      }
      if (status == 'PENDING' ||
          status == 'REQUESTED' ||
          status == 'INITIATED' ||
          status == 'UNDER_REVIEW' ||
          status == 'REFUND_REQUESTED') {
        if (stage < 1) stage = 1;
      }
    }

    consider(_refundStatus?.status);
    consider(order.refundStatus);
    consider(_depositRefundStatus(order.securityDepositRefundStatus));
    if (stage == 0 &&
        PendingRefundStore.instance.hasRefundRequest(order.id)) {
      stage = 1;
    }
    if (rejected && stage < 3) return -1;
    return stage;
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
    final refundSteps = _refundTrackingSteps;
    final isReturnFlow = order.isInReturnFlow ||
        order.shouldShowReturnTimeline ||
        PendingReturnStore.instance.contains(order.id);

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
          _buildDeliveryCard(order),
          SizedBox(height: 16.h),
          if (order.pickupDetails?.hasDisplayContent == true ||
              order.waitlistPickupDetails?.hasDisplayContent == true ||
              isReturnFlow) ...[
            _buildPickupCard(order),
            SizedBox(height: 16.h),
          ],
          SizedBox(height: 8.h),
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
          if (refundSteps.isNotEmpty) ...[
            SizedBox(height: 24.h),
            Divider(color: AppColours.primary, thickness: 0.2),
            SizedBox(height: 24.h),
            Text(
              'REFUND TRACKING',
              style: CustomTextStyles.montserratBold.copyWith(
                color: AppColours.primary,
                fontSize: 14.fSize,
                letterSpacing: 2.0,
              ),
            ),
            SizedBox(height: 32.h),
            ...refundSteps.asMap().entries.map(
              (entry) => _buildTrackingStep(
                title: entry.value.title,
                subtitle: entry.value.subtitle,
                isCompleted: entry.value.isCompleted,
                isCurrent: entry.value.isCurrent,
                isLast: entry.key == refundSteps.length - 1,
              ),
            ),
            ..._completedRefundFacts(order),
          ],
          SizedBox(height: 40.h),
        ],
      ),
    );
  }

  List<Widget> _completedRefundFacts(OrderHistoryItem order) {
    final completed = order.isRefunded ||
        (order.refundStatus?.trim().toUpperCase() == 'REFUNDED');
    if (!completed) return const [];

    final formatted = order.formattedRefundAmount?.trim() ?? '';
    final amount = formatted.isNotEmpty && formatted.toLowerCase() != 'null'
        ? formatted
        : (order.refundAmount > 0 ? '₹${order.refundAmount}' : null);
    final refundedAt = UserOrderMapper.completedRefundAt(order);
    final time = refundedAt == null
        ? null
        : UserOrderMapper.formatTrackingTimestamp(refundedAt);
    final note = UserOrderMapper.completedRefundNote(order);

    final lines = <(String, String)>[
      if (amount != null) ('REFUND AMOUNT', amount),
      if (time != null && time != 'Pending') ('REFUNDED ON', time),
      if (note != null && note.isNotEmpty) ('NOTE', note),
    ];
    if (lines.isEmpty) return const [];

    return [
      SizedBox(height: 8.h),
      ...lines.map(
        (line) => Padding(
          padding: EdgeInsets.only(left: 46.w, bottom: 14.h),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                line.$1,
                style: TextStyle(
                  color: AppColours.primary,
                  fontSize: 10.fSize,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
              SizedBox(height: 4.h),
              Text(
                line.$2,
                style: CustomTextStyles.openSansRegular.copyWith(
                  color: AppColours.secondary,
                  fontSize: 13.fSize,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ),
    ];
  }

  String? _cleanPartnerValue(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty || text.toLowerCase() == 'null') return null;
    return text;
  }

  String? _partnerLine(String? name, String? phone) {
    final parts = [
      _cleanPartnerValue(name),
      _cleanPartnerValue(phone),
    ].whereType<String>().toList();
    return parts.isEmpty ? null : parts.join('\n');
  }

  static const _detailGold = Color(0xFFD8B26A);

  Widget _detailLine(String label, String value) {
    return Padding(
      padding: EdgeInsets.only(top: 12.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: _detailGold,
              fontSize: 9.fSize,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
          SizedBox(height: 4.h),
          Text(
            value,
            style: TextStyle(
              color: Colors.white,
              fontSize: 13.fSize,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailTile({
    required String label,
    required String value,
    required IconData icon,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: const Color(0xFF16181D),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _detailGold.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: _detailGold, size: 13),
              SizedBox(width: 6.w),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _detailGold,
                    fontSize: 9.fSize,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 6.h),
          Text(
            value,
            style: TextStyle(
              color: Colors.white,
              fontSize: 13.fSize,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailsCard({
    required String title,
    required IconData icon,
    required String dateLabel,
    required String timeLabel,
    String? date,
    String? time,
    required List<Widget> lines,
  }) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: const Color(0xFF0C0D14),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _detailGold.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: _detailGold, size: 18.w),
              SizedBox(width: 8.w),
              Text(
                title,
                style: TextStyle(
                  color: _detailGold,
                  fontSize: 12.fSize,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          if (date != null || time != null) ...[
            SizedBox(height: 14.h),
            Row(
              children: [
                if (date != null)
                  Expanded(
                    child: _detailTile(
                      label: dateLabel,
                      value: _formatDetailDate(date),
                      icon: Icons.calendar_today_outlined,
                    ),
                  ),
                if (date != null && time != null) SizedBox(width: 10.w),
                if (time != null)
                  Expanded(
                    child: _detailTile(
                      label: timeLabel,
                      value: time,
                      icon: Icons.schedule_outlined,
                    ),
                  ),
              ],
            ),
          ],
          ...lines,
        ],
      ),
    );
  }

  Widget _buildDeliveryCard(OrderHistoryItem order) {
    String? clean(String? value) {
      final text = value?.trim() ?? '';
      if (text.isEmpty ||
          text.toLowerCase() == 'null' ||
          UserOrderMapper.isIapAddress(text)) {
        return null;
      }
      return text;
    }

    final date = clean(order.resolvedDeliveryDate);
    final time = clean(order.resolvedDeliveryTime);
    final partner =
        _partnerLine(order.deliveryPartnerName, order.deliveryPartnerPhone);
    final name = clean(_contactName);
    final mobile = clean(_userOrder?.mobileDisplay) ?? clean(_contactMobile);
    final address = clean(_addressLines) ?? clean(_userOrder?.addressLines);
    final note = clean(order.orderNote);

    return _detailsCard(
      title: 'DELIVERY DETAILS',
      icon: Icons.local_shipping_outlined,
      dateLabel: 'DELIVERY DATE',
      timeLabel: 'DELIVERY TIME',
      date: date,
      time: time,
      lines: [
        if (partner != null) _detailLine('DELIVERY PARTNER', partner),
        if (name != null) _detailLine('NAME', name),
        if (mobile != null) _detailLine('MOBILE', mobile),
        _detailLine('LOCATION', address ?? 'Address not available'),
        if (note != null) _detailLine('NOTE', note),
      ],
    );
  }

  String _formatDetailDate(String raw) {
    final parsed = DateTime.tryParse(raw.trim());
    if (parsed == null) return raw.trim();
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final day = parsed.day.toString().padLeft(2, '0');
    return '$day ${months[parsed.month - 1]} ${parsed.year}';
  }

  Widget _buildPickupCard(OrderHistoryItem order) {
    final ticket = order.waitlistPickupDetails;
    final pickup = order.pickupDetails;
    String? clean(String? value) {
      final text = value?.trim() ?? '';
      if (text.isEmpty || text.toLowerCase() == 'null') return null;
      return text;
    }

    final date = clean(ticket?.pickupDate) ?? clean(pickup?.pickupDate);
    final time = clean(ticket?.pickupTime) ?? clean(pickup?.pickupTime);

    // Prefer pickup name if not IAP, else customer contact name
    String? name = clean(ticket?.fullName);
    if (name == null || UserOrderMapper.isIapAddress(name)) {
      name = clean(pickup?.fullName);
    }
    if (name == null || UserOrderMapper.isIapAddress(name)) {
      name = clean(_contactName);
    }
    if (name == null || UserOrderMapper.isIapAddress(name)) {
      name = clean(_userOrder?.pickupFullName);
    }

    // Prefer pickup mobile if not IAP, else customer mobile
    String? mobile = clean(ticket?.mobile);
    if (mobile == null || UserOrderMapper.isIapAddress(mobile)) {
      mobile = clean(pickup?.mobile);
    }
    if (mobile == null || UserOrderMapper.isIapAddress(mobile)) {
      mobile = clean(_contactMobile);
    }
    if (mobile == null || UserOrderMapper.isIapAddress(mobile)) {
      mobile = clean(_userOrder?.mobileDisplay);
    }

    // Resolve address: NEVER use IAP address, always fallback to customer address
    String? address = clean(ticket?.fullAddress);
    if (address == null || UserOrderMapper.isIapAddress(address)) {
      address = clean(pickup?.fullAddress);
    }
    if (address == null || UserOrderMapper.isIapAddress(address)) {
      address = clean(_userOrder?.pickupAddress);
    }
    if (address == null || UserOrderMapper.isIapAddress(address)) {
      address = clean(_addressLines);
    }
    if (address == null || UserOrderMapper.isIapAddress(address)) {
      address = clean(_userOrder?.addressLines);
    }
    if (address == null || UserOrderMapper.isIapAddress(address)) {
      address = clean(_order?.customerAddress);
    }
    if (address != null && UserOrderMapper.isIapAddress(address)) {
      address = null;
    }

    final note = clean(ticket?.note) ?? clean(pickup?.note);
    final partner = _partnerLine(
      order.returnDeliveryPartnerName,
      order.returnDeliveryPartnerPhone,
    );
    if (date == null &&
        time == null &&
        partner == null &&
        name == null &&
        mobile == null &&
        address == null &&
        note == null) {
      return const SizedBox.shrink();
    }

    return _detailsCard(
      title: 'PICKUP DETAILS',
      icon: Icons.assignment_return_outlined,
      dateLabel: 'PICKUP DATE',
      timeLabel: 'PICKUP TIME',
      date: date,
      time: time,
      lines: [
        if (partner != null) _detailLine('PICKUP PARTNER', partner),
        if (name != null) _detailLine('NAME', name),
        if (mobile != null) _detailLine('MOBILE', mobile),
        if (address != null) _detailLine('LOCATION', address),
        if (note != null) _detailLine('NOTE', note),
      ],
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
