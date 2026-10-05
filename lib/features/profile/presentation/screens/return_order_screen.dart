import 'dart:math' show pi;

import 'package:flutter_svg/flutter_svg.dart';
import 'package:nomowear/core/app_export.dart';
import 'package:nomowear/core/network/api_exception.dart';
import 'package:nomowear/features/orders/data/order_repository.dart';
import 'package:nomowear/features/orders/data/pending_return_store.dart';
import 'package:nomowear/features/orders/data/models/order_return_result.dart';
import 'package:nomowear/features/profile/domain/saved_address.dart';
import 'package:nomowear/features/profile/domain/user_order.dart';

class ReturnOrderScreen extends StatefulWidget {
  const ReturnOrderScreen({
    super.key,
    required this.orderId,
    this.orderNumber,
    this.isReattempt = false,
    this.failureReason,
  });

  final String orderId;
  final String? orderNumber;
  final bool isReattempt;
  final String? failureReason;

  @override
  State<ReturnOrderScreen> createState() => _ReturnOrderScreenState();
}

class _ReturnOrderScreenState extends State<ReturnOrderScreen> {
  final OrderRepository _orderRepository = OrderRepository();
  final TextEditingController _noteController = TextEditingController();

  List<SavedAddress> _addresses = [];
  bool _loadingAddresses = true;
  bool _submitting = false;
  String? _addressesError;
  String? _selectedAddressId;
  DateTime? _pickupDate;
  String? _pickupTime;
  DateTime _calendarMonth = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    1,
  );
  bool _showCalendar = false;
  bool _showTimePicker = false;
  int _selectedHour = 12;
  int _selectedMinute = 40;
  bool _isAM = false;
  late FixedExtentScrollController _hourController;
  late FixedExtentScrollController _minuteController;
  late FixedExtentScrollController _periodController;

  @override
  void initState() {
    super.initState();
    _hourController = FixedExtentScrollController(initialItem: _selectedHour - 1);
    _minuteController = FixedExtentScrollController(initialItem: _selectedMinute);
    _periodController = FixedExtentScrollController(initialItem: _isAM ? 1 : 0);
    _loadAddresses();
  }

  @override
  void dispose() {
    _noteController.dispose();
    _hourController.dispose();
    _minuteController.dispose();
    _periodController.dispose();
    super.dispose();
  }

  Future<void> _loadAddresses() async {
    setState(() {
      _loadingAddresses = true;
      _addressesError = null;
    });

    try {
      await loadSavedAddressesFromProfile(forceRefresh: true);
      if (!mounted) return;
      final orderAddressId = await _resolveOrderAddressId();
      if (!mounted) return;
      setState(() {
        _addresses = List<SavedAddress>.from(userSavedAddresses);
        _loadingAddresses = false;
        _selectedAddressId = _matchingAddressId(orderAddressId);
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      final orderAddressId = await _resolveOrderAddressId();
      if (!mounted) return;
      setState(() {
        _addresses = List<SavedAddress>.from(userSavedAddresses);
        _loadingAddresses = false;
        _addressesError = e.message;
        _selectedAddressId = _matchingAddressId(orderAddressId);
      });
    } catch (_) {
      if (!mounted) return;
      final orderAddressId = await _resolveOrderAddressId();
      if (!mounted) return;
      setState(() {
        _addresses = List<SavedAddress>.from(userSavedAddresses);
        _loadingAddresses = false;
        _addressesError = 'Unable to load addresses.';
        _selectedAddressId = _matchingAddressId(orderAddressId);
      });
    }
  }

  Future<String?> _resolveOrderAddressId() async {
    final cached = findUserOrderById(widget.orderId)?.customerAddressId?.trim();
    if (cached != null && cached.isNotEmpty) return cached;
    try {
      final detail = await _orderRepository.getOrderDetail(widget.orderId);
      return detail.resolvedCustomerAddressId;
    } catch (_) {
      return null;
    }
  }

  String? _matchingAddressId(String? orderAddressId) {
    final wanted = orderAddressId?.trim() ?? '';
    if (wanted.isNotEmpty && _addresses.any((address) => address.id == wanted)) {
      return wanted;
    }
    if (_addresses.isEmpty) return null;
    return _addresses.first.id;
  }

  String get _apiPickupDate {
    final date = _pickupDate;
    if (date == null) return '';
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  String _formatDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day.toString().padLeft(2, '0')} ${months[d.month - 1]} ${d.year}';
  }

  String _monthYearLabel(DateTime m) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return '${months[m.month - 1]} ${m.year}';
  }

  DateTime get _todayDateOnly {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  Future<void> _submit() async {
    if (_submitting) return;

    final addressId = _selectedAddressId?.trim() ?? '';
    if (addressId.isEmpty) {
      CustomAppSnackBar.showError(context, 'Please select a pickup address.');
      return;
    }
    if (_pickupDate == null) {
      CustomAppSnackBar.showError(context, 'Please select a pickup date.');
      return;
    }
    if (_pickupTime == null || _pickupTime!.isEmpty) {
      CustomAppSnackBar.showError(context, 'Please select a pickup time.');
      return;
    }

    setState(() => _submitting = true);

    try {
      final OrderReturnResult result;
      if (widget.isReattempt) {
        result = await _orderRepository.reattemptReturn(
          orderId: widget.orderId,
          addressId: addressId,
          pickupDate: _apiPickupDate,
          pickupTime: _pickupTime!,
          note: _noteController.text,
        );
      } else {
        result = await _orderRepository.requestReturn(
          orderId: widget.orderId,
          addressId: addressId,
          pickupDate: _apiPickupDate,
          pickupTime: _pickupTime!,
          note: _noteController.text,
        );
      }

      await PendingReturnStore.instance.mark(widget.orderId);
      markUserOrderReturnSubmitted(widget.orderId);

      if (!mounted) return;
      setState(() => _submitting = false);

      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF16181D),
          title: Text(
            widget.isReattempt
                ? 'Return Pickup Rescheduled'
                : (result.waitlisted ? 'Return Waitlisted' : 'Return Requested'),
            style: TextStyle(
              color: AppColours.primary,
              fontSize: 16.fSize,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Text(
            result.message,
            style: TextStyle(color: Colors.white70, fontSize: 14.fSize),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                'OK',
                style: TextStyle(color: AppColours.primary),
              ),
            ),
          ],
        ),
      );

      if (!mounted) return;
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      final isAlreadySubmitted =
          e.message.toLowerCase().contains('already submitted') ||
          e.message.toLowerCase().contains('pending super admin approval');
      if (isAlreadySubmitted) {
        await PendingReturnStore.instance.mark(widget.orderId);
        markUserOrderReturnSubmitted(widget.orderId);
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF16181D),
            title: Text(
              'Return Already Submitted',
              style: TextStyle(
                color: AppColours.primary,
                fontSize: 16.fSize,
                fontWeight: FontWeight.bold,
              ),
            ),
            content: Text(
              e.message,
              style: TextStyle(color: Colors.white70, fontSize: 14.fSize),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(
                  'OK',
                  style: TextStyle(color: AppColours.primary),
                ),
              ),
            ],
          ),
        );
        if (!mounted) return;
        Navigator.pop(context, true);
        return;
      }
      CustomAppSnackBar.showError(context, e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      CustomAppSnackBar.showError(
        context,
        'Unable to submit return request. Please try again.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final orderLabel = widget.orderNumber?.trim().isNotEmpty == true
        ? widget.orderNumber!
        : widget.orderId;

    return Scaffold(
      backgroundColor: const Color(0xFF0F1012),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F1012),
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppColours.primary),
          onPressed: _submitting ? null : () => Navigator.pop(context),
        ),
        title: Text(
          widget.isReattempt ? 'Reschedule Return Pickup' : 'Return Order',
          style: TextStyle(
            color: AppColours.primary,
            fontSize: 18.fSize,
            fontWeight: FontWeight.bold,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
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
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(20.w, 20.h, 20.w, 16.h),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ORDER: $orderLabel',
                      style: CustomTextStyles.openSansSemiBold.copyWith(
                        fontSize: 12,
                        color: AppColours.primary,
                        letterSpacing: 1.1,
                      ),
                    ),
                    if (widget.failureReason != null &&
                        widget.failureReason!.trim().isNotEmpty) ...[
                      SizedBox(height: 14.h),
                      Container(
                        padding: EdgeInsets.all(12.w),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2B1215),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: const Color(0xFFEF4444).withValues(alpha: 0.5),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.error_outline_rounded,
                              color: Color(0xFFEF4444),
                              size: 20,
                            ),
                            SizedBox(width: 10.w),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Previous Pickup Failed',
                                    style: TextStyle(
                                      color: const Color(0xFFEF4444),
                                      fontSize: 12.5.fSize,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  SizedBox(height: 3.h),
                                  Text(
                                    widget.failureReason!,
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 11.5.fSize,
                                      height: 1.3,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    SizedBox(height: 24.h),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          'PICKUP ADDRESS',
                          style: CustomTextStyles.montserratBold.copyWith(
                            fontSize: 12,
                            color: AppColours.primary,
                            letterSpacing: 1.2,
                          ),
                        ),
                        if (!_loadingAddresses && _addresses.isNotEmpty)
                          InkWell(
                            onTap: _submitting ? null : _openChangeLocation,
                            borderRadius: BorderRadius.circular(6),
                            child: Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: 6.w,
                                vertical: 2.h,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.edit_location_alt_outlined,
                                    color: AppColours.primary,
                                    size: 14.w,
                                  ),
                                  SizedBox(width: 4.w),
                                  Text(
                                    'Change Location',
                                    style: TextStyle(
                                      color: AppColours.primary,
                                      fontSize: 12.fSize,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.4,
                                      decoration: TextDecoration.underline,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                    SizedBox(height: 12.h),
                    _buildAddressSection(),
                    SizedBox(height: 24.h),
                    _buildPickupScheduleSection(),
                    SizedBox(height: 24.h),
                    Text(
                      'NOTE (OPTIONAL)',
                      style: CustomTextStyles.montserratBold.copyWith(
                        fontSize: 12,
                        color: AppColours.primary,
                        letterSpacing: 1.2,
                      ),
                    ),
                    SizedBox(height: 12.h),
                    TextField(
                      controller: _noteController,
                      enabled: !_submitting,
                      maxLines: 4,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14.fSize,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Add a note for pickup',
                        hintStyle: TextStyle(
                          color: Colors.white38,
                          fontSize: 13.fSize,
                        ),
                        filled: true,
                        fillColor: const Color(0xFF16181D),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: AppColours.primary.withOpacity(0.35),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: AppColours.primary),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 20.h),
              child: SizedBox(
                width: double.infinity,
                height: 52.h,
                child: ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColours.primary,
                    disabledBackgroundColor:
                        AppColours.primary.withOpacity(0.5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _submitting
                      ? SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.black.withOpacity(0.7),
                          ),
                        )
                      : Text(
                          widget.isReattempt
                              ? 'RESCHEDULE RETURN PICKUP'
                              : 'SUBMIT RETURN REQUEST',
                          style: CustomTextStyles.montserratBold.copyWith(
                            fontSize: 14,
                            color: Colors.black,
                            letterSpacing: 1.2,
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddressSection() {
    if (_loadingAddresses) {
      return Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 24.h),
          child: CircularProgressIndicator(color: AppColours.primary),
        ),
      );
    }

    if (_addresses.isEmpty) {
      return Container(
        width: double.infinity,
        padding: EdgeInsets.all(16.w),
        decoration: BoxDecoration(
          color: const Color(0xFF16181D),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColours.primary.withOpacity(0.35)),
        ),
        child: Column(
          children: [
            Text(
              _addressesError ?? 'No saved addresses found.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 13.fSize),
            ),
            SizedBox(height: 12.h),
            TextButton.icon(
              onPressed: _addNewLocation,
              icon: Icon(
                Icons.add_location_alt_outlined,
                color: AppColours.primary,
                size: 18,
              ),
              label: Text(
                'Add Pickup Location',
                style: TextStyle(
                  color: AppColours.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final selectedAddress = _addresses.firstWhere(
      (a) => a.id == _selectedAddressId,
      orElse: () => _addresses.first,
    );

    return InkWell(
      onTap: _submitting ? null : _openChangeLocation,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(14.w),
        decoration: BoxDecoration(
          color: const Color(0xFF16181D),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppColours.primary,
            width: 1.3,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.radio_button_checked,
              color: AppColours.primary,
              size: 20,
            ),
            SizedBox(width: 10.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    selectedAddress.title,
                    style: CustomTextStyles.openSansSemiBold.copyWith(
                      fontSize: 14,
                      color: AppColours.primary,
                    ),
                  ),
                  SizedBox(height: 4.h),
                  Text(
                    selectedAddress.addressLines,
                    style: CustomTextStyles.openSansRegular.copyWith(
                      fontSize: 12,
                      color: Colors.white70,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openChangeLocation() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF16181D),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (bottomSheetContext) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 16.h),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40.w,
                        height: 4.h,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    SizedBox(height: 16.h),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Select Pickup Location',
                          style: TextStyle(
                            color: AppColours.primary,
                            fontSize: 16.fSize,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: const Icon(Icons.close, color: Colors.white70),
                          onPressed: () => Navigator.pop(bottomSheetContext),
                        ),
                      ],
                    ),
                    SizedBox(height: 14.h),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(context).size.height * 0.45,
                      ),
                      child: SingleChildScrollView(
                        child: Column(
                          children: _addresses.map((address) {
                            final selected = address.id == _selectedAddressId;
                            return Padding(
                              padding: EdgeInsets.only(bottom: 10.h),
                              child: InkWell(
                                onTap: () {
                                  setState(() => _selectedAddressId = address.id);
                                  Navigator.pop(bottomSheetContext);
                                },
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  width: double.infinity,
                                  padding: EdgeInsets.all(14.w),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0F1012),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: selected
                                          ? AppColours.primary
                                          : Colors.white12,
                                      width: selected ? 1.4 : 1,
                                    ),
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        selected
                                            ? Icons.radio_button_checked
                                            : Icons.radio_button_off,
                                        color: AppColours.primary,
                                        size: 20,
                                      ),
                                      SizedBox(width: 10.w),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              address.title,
                                              style: CustomTextStyles.openSansSemiBold.copyWith(
                                                fontSize: 14,
                                                color: AppColours.primary,
                                              ),
                                            ),
                                            SizedBox(height: 4.h),
                                            Text(
                                              address.addressLines,
                                              style: CustomTextStyles.openSansRegular.copyWith(
                                                fontSize: 12,
                                                color: Colors.white70,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                    SizedBox(height: 14.h),
                    SizedBox(
                      width: double.infinity,
                      height: 46.h,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(bottomSheetContext);
                          _addNewLocation();
                        },
                        icon: Icon(
                          Icons.add_location_alt_outlined,
                          color: AppColours.primary,
                          size: 18.w,
                        ),
                        label: Text(
                          'Add New Location',
                          style: TextStyle(
                            color: AppColours.primary,
                            fontSize: 13.fSize,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                            color: AppColours.primary.withOpacity(0.6),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _addNewLocation() async {
    final location = await Navigator.pushNamed(
      context,
      AppRoutes.selectAddressScreen,
    );
    if (!mounted || location == null) return;

    final result = await Navigator.pushNamed(
      context,
      AppRoutes.addNewAddressScreen,
      arguments: location is Map ? location : null,
    );
    if (!mounted) return;
    if (result is Map) {
      try {
        final payload = result.map(
          (key, value) => MapEntry(key.toString(), value?.toString() ?? ''),
        );
        final saved = await createAndAppendSavedAddress(payload);
        if (!mounted) return;
        setState(() {
          _addresses = List<SavedAddress>.from(userSavedAddresses);
          _selectedAddressId = saved.id;
        });
        CustomAppSnackBar.showSuccess(
          context,
          'Pickup location updated',
        );
      } on ApiException catch (error) {
        if (!mounted) return;
        CustomAppSnackBar.showError(context, error.message);
      } catch (_) {
        if (!mounted) return;
        CustomAppSnackBar.showError(
          context,
          'Unable to save location. Please try again.',
        );
      }
    }
  }

  Widget _sectionHeader(String text) {
    return Text(
      text,
      style: TextStyle(
        color: AppColours.primary,
        fontSize: 10.fSize,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.1,
      ),
    );
  }

  Widget _buildPickupScheduleSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionHeader('SELECT PICKUP DATE'),
                  SizedBox(height: 12.h),
                  _buildPickupDateField(),
                ],
              ),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionHeader('SELECT PICKUP TIME'),
                  SizedBox(height: 12.h),
                  _buildPickupTimeField(),
                ],
              ),
            ),
          ],
        ),
        if (_showCalendar) ...[
          SizedBox(height: 10.h),
          _buildInlineCalendar(),
        ],
        if (_showTimePicker) ...[
          SizedBox(height: 8.h),
          _buildInlineTimePicker(),
        ],
      ],
    );
  }

  Widget _buildPickupDateField() {
    return GestureDetector(
      onTap: _submitting
          ? null
          : () => setState(() {
                _showCalendar = !_showCalendar;
                if (_showCalendar) _showTimePicker = false;
              }),
      child: Container(
        height: 50.h,
        padding: EdgeInsets.symmetric(horizontal: 12.w),
        decoration: BoxDecoration(
          color: const Color(0xFF16181D),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColours.primary, width: 0.6),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _pickupDate != null
                    ? _formatDate(_pickupDate!)
                    : 'Select Pickup Date',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _pickupDate != null
                      ? Colors.white
                      : AppColours.hintcolor,
                  fontSize: 12.fSize,
                ),
              ),
            ),
            Icon(
              Icons.calendar_today_outlined,
              color: AppColours.primary,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPickupTimeField() {
    return GestureDetector(
      onTap: _submitting
          ? null
          : () => setState(() {
                _showTimePicker = !_showTimePicker;
                if (_showTimePicker) _showCalendar = false;
              }),
      child: Container(
        height: 50.h,
        padding: EdgeInsets.symmetric(horizontal: 12.w),
        decoration: BoxDecoration(
          color: const Color(0xFF16181D),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColours.primary, width: 0.6),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _pickupTime ?? 'Select Pickup Time',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _pickupTime != null
                      ? Colors.white
                      : AppColours.hintcolor,
                  fontSize: 12.fSize,
                ),
              ),
            ),
            SizedBox(
              width: 16.w,
              height: 16.w,
              child: Transform.rotate(
                angle: _showTimePicker ? 0 : pi,
                child: SvgPicture.asset(
                  IconConstant.dropDown1,
                  width: 16.w,
                  height: 16.w,
                  fit: BoxFit.contain,
                  colorFilter: ColorFilter.mode(
                    AppColours.primary,
                    BlendMode.srcIn,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInlineTimePicker() {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 12.h, horizontal: 12.w),
      decoration: BoxDecoration(
        color: const Color(0xFF16181D),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColours.primary.withOpacity(0.5)),
      ),
      child: Column(
        children: [
          Text(
            'Select Time',
            style: TextStyle(
              color: AppColours.primary,
              fontSize: 14.fSize,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 8.h),
          SizedBox(
            height: 160.h,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildWheel(
                  controller: _hourController,
                  itemCount: 12,
                  labelBuilder: (i) => '${i + 1}'.padLeft(2, '0'),
                  selectedIndex: _selectedHour - 1,
                  onChanged: (i) => setState(() => _selectedHour = i + 1),
                ),
                Text(
                  ':',
                  style: TextStyle(
                    color: AppColours.primary,
                    fontSize: 20.fSize,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                _buildWheel(
                  controller: _minuteController,
                  itemCount: 60,
                  labelBuilder: (i) => i.toString().padLeft(2, '0'),
                  selectedIndex: _selectedMinute,
                  onChanged: (i) => setState(() => _selectedMinute = i),
                ),
                _buildWheel(
                  controller: _periodController,
                  itemCount: 2,
                  labelBuilder: (i) => i == 0 ? 'PM' : 'AM',
                  selectedIndex: _isAM ? 1 : 0,
                  onChanged: (i) => setState(() => _isAM = i == 1),
                  width: 48,
                ),
              ],
            ),
          ),
          SizedBox(height: 8.h),
          GestureDetector(
            onTap: () {
              setState(() {
                final period = _isAM ? 'AM' : 'PM';
                _pickupTime =
                    '${_selectedHour.toString().padLeft(2, '0')}:${_selectedMinute.toString().padLeft(2, '0')} $period';
                _showTimePicker = false;
              });
            },
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(vertical: 10.h),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColours.primary,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Save',
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 13.fSize,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInlineCalendar() {
    final nowMonthStart = DateTime(_todayDateOnly.year, _todayDateOnly.month, 1);
    final isCurrentMonth = _calendarMonth.year == nowMonthStart.year &&
        _calendarMonth.month == nowMonthStart.month;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 14.h),
      decoration: BoxDecoration(
        color: const Color(0xFF16181D),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColours.primary.withOpacity(0.6)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                onPressed: isCurrentMonth
                    ? null
                    : () {
                        setState(() {
                          _calendarMonth = DateTime(
                            _calendarMonth.year,
                            _calendarMonth.month - 1,
                          );
                        });
                      },
                icon: Icon(
                  Icons.chevron_left,
                  color: isCurrentMonth ? Colors.white24 : AppColours.primary,
                  size: 26,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
              Text(
                _monthYearLabel(_calendarMonth),
                style: TextStyle(
                  color: AppColours.primary,
                  fontSize: 15.fSize,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                onPressed: () {
                  setState(() {
                    _calendarMonth = DateTime(
                      _calendarMonth.year,
                      _calendarMonth.month + 1,
                    );
                  });
                },
                icon: Icon(
                  Icons.chevron_right,
                  color: AppColours.primary,
                  size: 26,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
            ],
          ),
          SizedBox(height: 8.h),
          Row(
            children: ['S', 'M', 'T', 'W', 'T', 'F', 'S']
                .map(
                  (d) => Expanded(
                    child: Center(
                      child: Text(
                        d,
                        style: TextStyle(
                          color: AppColours.primary,
                          fontSize: 11.fSize,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          SizedBox(height: 8.h),
          _buildCalendarGrid(),
        ],
      ),
    );
  }

  Widget _buildCalendarGrid() {
    final y = _calendarMonth.year;
    final m = _calendarMonth.month;
    final first = DateTime(y, m, 1);
    final daysInMonth = DateTime(y, m + 1, 0).day;
    final leading = first.weekday % 7;
    final totalCells = ((leading + daysInMonth + 6) ~/ 7) * 7;
    final cells = <Widget>[];

    for (int i = 0; i < totalCells; i++) {
      final dayNum = i - leading + 1;
      if (dayNum < 1 || dayNum > daysInMonth) {
        cells.add(const SizedBox(height: 40));
      } else {
        final date = DateTime(y, m, dayNum);
        final isPastDate = date.isBefore(_todayDateOnly);
        final isSelected = _pickupDate != null &&
            _pickupDate!.year == date.year &&
            _pickupDate!.month == date.month &&
            _pickupDate!.day == date.day;
        cells.add(
          GestureDetector(
            onTap: isPastDate ? null : () => setState(() => _pickupDate = date),
            child: SizedBox(
              height: 40,
              child: Center(
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected ? AppColours.primary : Colors.transparent,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '$dayNum',
                    style: TextStyle(
                      color: isSelected
                          ? Colors.black
                          : (isPastDate ? Colors.white24 : Colors.white70),
                      fontSize: 14.fSize,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }
    }

    return GridView.count(
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 4,
      children: cells,
    );
  }

  Widget _buildWheel({
    required FixedExtentScrollController controller,
    required int itemCount,
    required String Function(int) labelBuilder,
    required int selectedIndex,
    required ValueChanged<int> onChanged,
    double width = 52,
  }) {
    return SizedBox(
      width: width.w,
      child: ListWheelScrollView.useDelegate(
        controller: controller,
        itemExtent: 36.h,
        perspective: 0.003,
        diameterRatio: 1.6,
        physics: const FixedExtentScrollPhysics(),
        onSelectedItemChanged: onChanged,
        childDelegate: ListWheelChildBuilderDelegate(
          childCount: itemCount,
          builder: (context, index) {
            final isSelected = index == selectedIndex;
            return Center(
              child: Text(
                labelBuilder(index),
                style: TextStyle(
                  color: isSelected ? AppColours.primary : AppColours.secondary,
                  fontSize: isSelected ? 18.fSize : 14.fSize,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
