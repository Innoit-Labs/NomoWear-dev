import 'dart:math' show pi;

import 'package:flutter/foundation.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:nomowear/core/app_export.dart';
import 'package:nomowear/core/network/api_exception.dart';
import 'package:nomowear/features/cart/presentation/bloc/cart_bloc.dart';
import 'package:nomowear/features/checkout/data/checkout_session.dart';
import 'package:nomowear/features/checkout/data/wardrobe_booking_session.dart';
import 'package:nomowear/features/checkout/data/subscription_kit_preferences.dart';
import 'package:nomowear/features/products/data/product_cache.dart';
import 'package:nomowear/features/products/data/product_catalog.dart';
import 'package:nomowear/features/products/data/product_repository.dart';
import 'package:nomowear/features/profile/domain/saved_address.dart';
import 'package:nomowear/features/subscriptions/data/subscription_garment_balance.dart';
import 'package:nomowear/features/subscriptions/data/models/active_subscription.dart';
import 'package:nomowear/features/subscriptions/data/subscription_repository.dart';
import 'package:nomowear/features/wardrobe/data/models/wardrobe_kit.dart';
import 'package:nomowear/features/wardrobe/data/wardrobe_kit_repository.dart';
import 'package:nomowear/core/services/google_maps_service.dart';

class ChooseYourWardrobeKitScreen extends StatefulWidget {
  final String wardrobeCategory;

  const ChooseYourWardrobeKitScreen({
    Key? key,
    required this.wardrobeCategory,
  }) : super(key: key);

  @override
  State<ChooseYourWardrobeKitScreen> createState() =>
      _ChooseYourWardrobeKitScreenState();
}

/// Backward compatibility alias
typedef ScreenshotScreen = ChooseYourWardrobeKitScreen;

class _ChooseYourWardrobeKitScreenState
    extends State<ChooseYourWardrobeKitScreen> {
  final WardrobeKitRepository _wardrobeKitRepository = WardrobeKitRepository();

  bool isMale = true;
  String? _selectedKitId;
  String? _prefilledKitId;
  int? _prefilledKitDays;
  String? _prefilledKitName;
  List<WardrobeKit> _kits = [];
  bool _loadingKits = true;
  String? _kitsError;
  int? _subscriptionRemaining;
  ActiveSubscription? _activeSubscription;

  final Map<String, bool> _kitEligibility = {};

  int? get _effectiveRemainingGarments {
    if (_subscriptionRemaining != null) return _subscriptionRemaining;
    final sub = _activeSubscription;
    if (sub == null) return null;
    if (sub.remainingGarments != null) return sub.remainingGarments;
    if (sub.usedGarments != null) {
      final rem = sub.maxGarments - sub.usedGarments!;
      return rem < 0 ? 0 : rem;
    }
    return sub.apiRemainingGarments ?? sub.maxGarments;
  }

  bool _computeKitEligibility(WardrobeKit kit, int remainingGarments) {
    if (remainingGarments <= 0) return false;

    final days = kit.durationDays;
    if (days <= 1 || kit.maxItems <= 4) {
      return remainingGarments >= 1;
    } else if (days <= 3 || (kit.maxItems >= 5 && kit.maxItems <= 8)) {
      return remainingGarments >= 5;
    } else if (days <= 5 || (kit.maxItems >= 9 && kit.maxItems <= 11)) {
      return remainingGarments >= 9;
    } else if (days >= 7 || kit.maxItems >= 12) {
      return remainingGarments >= 12;
    }
    return remainingGarments >= 1;
  }

  DateTime? _selectedDeliveryDate;
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
  String? _selectedTimeLabel;
  late FixedExtentScrollController _hourController;
  late FixedExtentScrollController _minuteController;
  late FixedExtentScrollController _periodController;

  bool _loadingAddresses = true;
  String? _addressesError;
  int _selectedAddressIndex = 0;
  bool _isSubmittingNext = false;

  @override
  void initState() {
    super.initState();
    _applySyncPrefills();
    _hourController = FixedExtentScrollController(initialItem: _selectedHour - 1);
    _minuteController = FixedExtentScrollController(initialItem: _selectedMinute);
    _periodController = FixedExtentScrollController(initialItem: _isAM ? 1 : 0);
    _initData();
  }

  void _applySyncPrefills() {
    // 1. Gender
    final sessionGender = CheckoutSession.instance.gender?.trim();
    final prefGender = SubscriptionKitPreferences.instance.gender?.trim();
    final savedGender = (sessionGender != null && sessionGender.isNotEmpty)
        ? sessionGender
        : prefGender;
    if (savedGender != null && savedGender.isNotEmpty) {
      isMale = savedGender.toLowerCase() != 'female';
    }

    // 2. Delivery Date
    if (_selectedDeliveryDate == null) {
      if (CheckoutSession.instance.deliveryDate != null) {
        _selectedDeliveryDate = CheckoutSession.instance.deliveryDate;
      } else if (SubscriptionKitPreferences.instance.deliveryDateEpochMs != null &&
          SubscriptionKitPreferences.instance.deliveryDateEpochMs! > 0) {
        _selectedDeliveryDate = DateTime.fromMillisecondsSinceEpoch(
          SubscriptionKitPreferences.instance.deliveryDateEpochMs!,
        );
      }
      if (_selectedDeliveryDate != null) {
        _calendarMonth = DateTime(
          _selectedDeliveryDate!.year,
          _selectedDeliveryDate!.month,
          1,
        );
      }
    }

    // 3. Delivery Time
    final sessionTime = CheckoutSession.instance.deliveryTime?.trim();
    final prefTime = SubscriptionKitPreferences.instance.deliveryTime?.trim();
    final savedTime = (sessionTime != null && sessionTime.isNotEmpty)
        ? sessionTime
        : prefTime;
    if (savedTime != null && savedTime.isNotEmpty && _selectedTimeLabel == null) {
      _selectedTimeLabel = savedTime;
      final match = RegExp(r'(\d{1,2}):(\d{2})\s*(AM|PM)', caseSensitive: false)
          .firstMatch(savedTime);
      if (match != null) {
        final h = int.tryParse(match.group(1)!);
        final m = int.tryParse(match.group(2)!);
        final isAm = (match.group(3)?.toUpperCase() ?? '') == 'AM';
        if (h != null && h >= 1 && h <= 12) _selectedHour = h;
        if (m != null && m >= 0 && m <= 59) _selectedMinute = m;
        _isAM = isAm;
      }
    }

    // 4. Kit Selection
    final prefKitId = SubscriptionKitPreferences.instance.wardrobeKitId?.trim();
    final sessionKitId = WardrobeBookingSession.instance.selectedKitId?.trim();
    _prefilledKitId = (prefKitId != null && prefKitId.isNotEmpty)
        ? prefKitId
        : ((sessionKitId != null && sessionKitId.isNotEmpty) ? sessionKitId : null);

    final prefDays = SubscriptionKitPreferences.instance.wardrobeKitDays;
    int cartDays = 0;
    try {
      cartDays = context.read<CartBloc>().state.wardrobeKitDays;
    } catch (_) {}
    _prefilledKitDays = prefDays > 0 ? prefDays : (cartDays > 0 ? cartDays : null);

    final prefName = SubscriptionKitPreferences.instance.wardrobeKitName.trim();
    final sessionKitType = CheckoutSession.instance.kitType?.trim();
    _prefilledKitName = prefName.isNotEmpty
        ? prefName
        : ((sessionKitType != null && sessionKitType.isNotEmpty) ? sessionKitType : null);

    // 5. Address
    _syncSelectedAddress();
  }

  Future<void> _initData() async {
    await Future.wait([
      CheckoutSession.instance.restore(),
      SubscriptionKitPreferences.instance.restore(),
    ]);
    if (!mounted) return;
    setState(() {
      _applySyncPrefills();
      if (_hourController.hasClients) {
        _hourController.jumpToItem(_selectedHour - 1);
      }
      if (_minuteController.hasClients) {
        _minuteController.jumpToItem(_selectedMinute);
      }
      if (_periodController.hasClients) {
        _periodController.jumpToItem(_isAM ? 1 : 0);
      }
    });

    await Future.wait([
      _loadWardrobeKits(),
      _loadSavedAddresses(),
    ]);
  }

  List<SavedAddress> get _savedAddresses =>
      List<SavedAddress>.from(userSavedAddresses);

  Future<void> _loadSavedAddresses() async {
    setState(() {
      _loadingAddresses = true;
      _addressesError = null;
    });

    try {
      await loadSavedAddressesFromProfile();
      if (!mounted) return;
      setState(() {
        _loadingAddresses = false;
        _syncSelectedAddress();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingAddresses = false;
        _addressesError = 'Unable to load saved addresses.';
        _syncSelectedAddress();
      });
    }
  }

  void _syncSelectedAddress() {
    if (userSavedAddresses.isEmpty) {
      _selectedAddressIndex = 0;
      return;
    }

    final targetAddressId = CheckoutSession.instance.addressId?.trim() ??
        SubscriptionKitPreferences.instance.addressId?.trim();
    if (targetAddressId != null && targetAddressId.isNotEmpty) {
      final index = userSavedAddresses.indexWhere(
        (a) => a.id.trim() == targetAddressId,
      );
      if (index != -1) {
        _selectedAddressIndex = index;
        return;
      }
    }

    final targetTitle = CheckoutSession.instance.addressTitle?.trim() ??
        SubscriptionKitPreferences.instance.addressTitle?.trim();
    if (targetTitle != null && targetTitle.isNotEmpty) {
      final index = userSavedAddresses.indexWhere(
        (a) => a.title.trim().toLowerCase() == targetTitle.toLowerCase(),
      );
      if (index != -1) {
        _selectedAddressIndex = index;
        return;
      }
    }

    if (_selectedAddressIndex >= userSavedAddresses.length) {
      _selectedAddressIndex = 0;
    }
  }

  bool get _isAddressLocked {
    CartState cartState = const CartState();
    try {
      cartState = context.read<CartBloc>().state;
    } catch (_) {}

    final hasItemsInCart =
        cartState.items.isNotEmpty || cartState.wardrobeItems.isNotEmpty;
    final savedAddressId = CheckoutSession.instance.addressId?.trim() ??
        SubscriptionKitPreferences.instance.addressId?.trim();
    final hasSavedAddress = savedAddressId != null && savedAddressId.isNotEmpty;

    return hasItemsInCart && hasSavedAddress;
  }

  bool get _isSubscriptionKitFlow =>
      CheckoutSession.instance.useSubscriptionBooking &&
      !CheckoutSession.instance.continueWithoutMembership;

  List<WardrobeKit> get _filteredKits {
    final gender = isMale ? 'male' : 'female';
    return _kits
        .where((kit) => kit.isActive && kit.matchesGender(gender))
        .toList()
      ..sort((a, b) => a.durationDays.compareTo(b.durationDays));
  }

  WardrobeKit? get _selectedKit {
    final kits = _filteredKits;
    if (kits.isEmpty) return null;
    if (_selectedKitId == null) return kits.first;
    for (final kit in kits) {
      if (kit.id == _selectedKitId) return kit;
    }
    return kits.first;
  }

  Future<void> _loadWardrobeKits() async {
    setState(() {
      _loadingKits = true;
      _kitsError = null;
    });

    try {
      final kits = await _wardrobeKitRepository.getWardrobeKits();
      int? remaining;
      ActiveSubscription? activeSub;

      if (_isSubscriptionKitFlow) {
        remaining = await SubscriptionGarmentBalance.resolveAndCache(
          forceRefresh: true,
        );
        final subRepo = SubscriptionRepository();
        activeSub = await subRepo.getActiveSubscription(forceRefresh: true);
      }

      final Map<String, bool> eligibilityMap = {};
      final effRemaining = remaining ??
          activeSub?.remainingGarments ??
          (activeSub != null && activeSub.usedGarments != null
              ? (activeSub.maxGarments - activeSub.usedGarments!)
                  .clamp(0, activeSub.maxGarments)
              : activeSub?.apiRemainingGarments ?? activeSub?.maxGarments);

      for (final kit in kits) {
        if (!_isSubscriptionKitFlow || effRemaining == null) {
          eligibilityMap[kit.id] = true;
        } else {
          eligibilityMap[kit.id] =
              _computeKitEligibility(kit, effRemaining);
        }
      }

      // Check per-kit eligibility from API concurrently if available
      if (_isSubscriptionKitFlow) {
        await Future.wait(
          kits.map((kit) async {
            try {
              final response =
                  await _wardrobeKitRepository.checkEligibility(kit.id);
              if (response.containsKey('isEligible') ||
                  response.containsKey('is_eligible') ||
                  response.containsKey('eligible')) {
                final isEligible = response['isEligible'] == true ||
                    response['is_eligible'] == true ||
                    response['eligible'] == true;
                eligibilityMap[kit.id] = isEligible;
              }
            } catch (_) {
              // Retain computed entitlement eligibility on error
            }
          }),
        );
      }

      if (!mounted) return;
      setState(() {
        _kits = kits;
        _subscriptionRemaining = remaining;
        _activeSubscription = activeSub;
        _kitEligibility
          ..clear()
          ..addAll(eligibilityMap);
        _loadingKits = false;
        _syncSelectedKit();
      });
      _logWardrobeKitAvailability();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _kits = [];
        _loadingKits = false;
        _kitsError = e.message;
        _selectedKitId = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _kits = [];
        _loadingKits = false;
        _kitsError = 'Unable to load wardrobe kits. Please try again.';
        _selectedKitId = null;
      });
    }
  }

  void _syncSelectedKit() {
    final kits = _filteredKits;
    if (kits.isEmpty) {
      _selectedKitId = null;
      return;
    }
    final enabledKits = kits.where((k) => _isKitEnabled(k)).toList();
    if (enabledKits.isEmpty) {
      _selectedKitId = null;
      return;
    }

    if (_selectedKitId != null &&
        enabledKits.any((kit) => kit.id == _selectedKitId)) {
      return;
    }

    // 1. Match by prefilled kit ID
    if (_prefilledKitId != null && _prefilledKitId!.isNotEmpty) {
      final match =
          enabledKits.where((k) => k.id == _prefilledKitId).firstOrNull;
      if (match != null) {
        _selectedKitId = match.id;
        return;
      }
    }

    // 2. Match by prefilled duration days (e.g. 1-day kit)
    if (_prefilledKitDays != null && _prefilledKitDays! > 0) {
      final match = enabledKits
          .where((k) => k.durationDays == _prefilledKitDays)
          .firstOrNull;
      if (match != null) {
        _selectedKitId = match.id;
        return;
      }
    }

    // 3. Match by prefilled kit name/title
    if (_prefilledKitName != null && _prefilledKitName!.isNotEmpty) {
      final target = _prefilledKitName!.toLowerCase();
      final match = enabledKits.where((k) {
        final title = k.displayTitle.toLowerCase();
        return title.contains(target) || target.contains(title);
      }).firstOrNull;
      if (match != null) {
        _selectedKitId = match.id;
        return;
      }
    }

    _selectedKitId = enabledKits.first.id;
  }

  bool _isKitEnabled(WardrobeKit kit) {
    if (!_isSubscriptionKitFlow) return true;
    if (_kitEligibility.containsKey(kit.id)) {
      return _kitEligibility[kit.id]!;
    }
    final remaining = _effectiveRemainingGarments;
    if (remaining != null) {
      return _computeKitEligibility(kit, remaining);
    }
    return true;
  }

  void _logWardrobeKitAvailability() {
    if (!kDebugMode) return;
    final remaining = _subscriptionRemaining;
    debugPrint('[WARDROBE_KIT] subscriptionRemaining=$remaining');
    for (final kit in _filteredKits) {
      debugPrint(
        '[WARDROBE_KIT] ${kit.durationDays}Day required=${kit.maxItems}',
      );
    }
  }

  @override
  void dispose() {
    _hourController.dispose();
    _minuteController.dispose();
    _periodController.dispose();
    super.dispose();
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

  Future<void> _openAddAddressScreen() async {
    if (_isAddressLocked) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Delivery address is locked for items currently in your cart.',
          ),
          backgroundColor: AppColours.primary,
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

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
    if (!mounted || result == null) return;
    if (result is Map) {
      final payload = <String, String>{};
      result.forEach((key, value) {
        payload[key.toString()] = value?.toString() ?? '';
      });

      final title = payload['title']?.trim();
      final lines = payload['addressLines']?.trim();
      if (title == null || title.isEmpty || lines == null || lines.isEmpty) {
        return;
      }

      try {
        await createAndAppendSavedAddress(payload);
        if (!mounted) return;
        setState(() {
          _selectedAddressIndex = userSavedAddresses.length - 1;
        });
      } on ApiException catch (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error.message,
              style: const TextStyle(color: Colors.black),
            ),
            backgroundColor: AppColours.primary,
            behavior: SnackBarBehavior.floating,
          ),
        );
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Unable to save address. Please try again.',
              style: TextStyle(color: Colors.black),
            ),
            backgroundColor: AppColours.primary,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _confirmDeleteAddress(int index) async {
    if (_isAddressLocked) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Cannot remove delivery address while items are in your cart.',
          ),
          backgroundColor: AppColours.primary,
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final addresses = _savedAddresses;
    if (index < 0 || index >= addresses.length) return;

    final address = addresses[index];
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16181D),
        title: Text(
          'Remove address?',
          style: TextStyle(
            color: AppColours.primary,
            fontSize: 16.fSize,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          '"${address.title}" will be removed from saved addresses.',
          style: TextStyle(color: Colors.white70, fontSize: 14.fSize),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete', style: TextStyle(color: AppColours.primary)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    try {
      await deleteSavedAddressById(address.id);
      if (!mounted) return;
      setState(() {
        if (userSavedAddresses.isEmpty) {
          _selectedAddressIndex = 0;
        } else if (index < _selectedAddressIndex) {
          _selectedAddressIndex--;
        } else if (index == _selectedAddressIndex) {
          _selectedAddressIndex = 0;
        }
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message),
          backgroundColor: AppColours.primary,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Unable to delete address. Please try again.'),
          backgroundColor: AppColours.primary,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1012),
      body: Stack(
        children: [
          SafeArea(
            child: AbsorbPointer(
              absorbing: _isSubmittingNext,
              child: Column(
                children: [
                  _buildAppBar(),
                  Container(
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
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: 20.w),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(height: 24.h),
                    _buildGenderSelection(),
                    SizedBox(height: 24.h),
                    _buildKitSelection(),
                    SizedBox(height: 24.h),
                    _buildDeliveryScheduleSection(),
                    SizedBox(height: 24.h),
                    _buildSavedAddressesSection(),
                    SizedBox(height: 24.h),
                  ],
                ),
              ),
            ),
            Container(
              padding: EdgeInsets.fromLTRB(20.w, 12.h, 20.w, 16.h),
              decoration: BoxDecoration(
                color: const Color(0xFF0F1012),
                border: Border(
                  top: BorderSide(
                    color: AppColours.primary.withOpacity(0.15),
                    width: 1,
                  ),
                ),
              ),
              child: _buildNextButton(),
            ),
          ],
        ),
      ),
    ),
    if (_isSubmittingNext)
      Positioned.fill(
        child: Container(
                color: Colors.black.withOpacity(0.6),
                child: const Center(
                  child: CircularProgressIndicator(
                    color: AppColours.primary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAppBar() {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 16.h, horizontal: 20.w),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColours.primary.withOpacity(0.1)),
        ),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Icon(Icons.arrow_back, color: AppColours.primary),
          ),
          Expanded(
            child: Center(
              child: Text(
                "Choose Your Wardrobe Kit",
                style: TextStyle(
                  color: AppColours.primary,
                  fontSize: 18.fSize,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          SizedBox(width: 24.w),
        ],
      ),
    );
  }

  Widget _buildGenderSelection() {
    return Row(
      children: [
        Expanded(
          child: _buildGenderButton("Male", isMale),
        ),
        SizedBox(width: 16.w),
        Expanded(
          child: _buildGenderButton("Female", !isMale),
        ),
      ],
    );
  }

  Widget _buildGenderButton(String label, bool isActive) {
    return GestureDetector(
      onTap: () {
        setState(() {
          isMale = label == "Male";
          _syncSelectedKit();
        });
      },
      child: Container(
        height: 52.h,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: isActive
              ? LinearGradient(
                  colors: [AppColours.primary.withOpacity(0.8), AppColours.primary],
                )
              : null,
          color: isActive ? null : const Color(0xFF16181D),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive ? AppColours.primary : AppColours.primary,
            width: 0.6,
          ),
        ),
        child: Text(
          label,
          style: CustomTextStyles.openSansSemiBold.copyWith(
            fontSize: 14,
            color: isActive ? Colors.black : AppColours.secondary,
          ),
        ),
      ),
    );
  }

  Widget _buildKitSelection() {
    if (_loadingKits) {
      return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          _sectionHeader('SELECT WARDROBE KIT'),
          SizedBox(height: 12.h),
          Row(
            children: [
              Expanded(child: _buildKitShimmerCard()),
              SizedBox(width: 12.w),
              Expanded(child: _buildKitShimmerCard()),
            ],
        ),
      ],
    );
  }

    if (_kitsError != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader('SELECT WARDROBE KIT'),
          SizedBox(height: 12.h),
          Container(
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
                  _kitsError!,
                  textAlign: TextAlign.center,
                  style: CustomTextStyles.openSansRegular.copyWith(
                    fontSize: 12,
                    color: Colors.white70,
                  ),
                ),
                SizedBox(height: 12.h),
                TextButton(
                  onPressed: _loadWardrobeKits,
              child: Text(
                    'Retry',
                    style: CustomTextStyles.openSansSemiBold.copyWith(
                      color: AppColours.primary,
              ),
        ),
      ),
              ],
            ),
          ),
        ],
    );
  }

    final kits = _filteredKits;
    if (kits.isEmpty) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
          _sectionHeader('SELECT WARDROBE KIT'),
          SizedBox(height: 12.h),
        Text(
            'No wardrobe kits available for ${isMale ? 'Male' : 'Female'}.',
            style: CustomTextStyles.openSansRegular.copyWith(
              fontSize: 12,
              color: Colors.white54,
            ),
        ),
      ],
    );
  }

    final rows = <Widget>[];
    for (var i = 0; i < kits.length; i += 2) {
      final left = kits[i];
      final right = i + 1 < kits.length ? kits[i + 1] : null;
      rows.add(_buildKitGridRow(left, right));
      if (i + 2 < kits.length) {
        rows.add(SizedBox(height: 12.h));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
            children: [
        _sectionHeader('SELECT WARDROBE KIT'),
        SizedBox(height: 12.h),
        ...rows,
      ],
    );
  }

  Widget _buildKitShimmerCard() {
    return AppShimmer(
      child: Container(
        height: 84.h,
        decoration: BoxDecoration(
          color: AppShimmer.baseColor,
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  Widget _buildKitGridRow(WardrobeKit left, WardrobeKit? right) {
    return Column(
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _buildKitOption(left)),
              if (right != null) ...[
                SizedBox(width: 12.w),
                Expanded(child: _buildKitOption(right)),
              ] else
                const Spacer(),
            ],
          ),
        ),
        SizedBox(height: 8.h),
        Row(
          children: [
            Expanded(child: _buildKitGarmentLabel(left)),
            if (right != null) ...[
              SizedBox(width: 12.w),
              Expanded(child: _buildKitGarmentLabel(right)),
            ] else
              const Spacer(),
          ],
        ),
      ],
    );
  }

  Widget _buildKitGarmentLabel(WardrobeKit kit) {
    if (kit.maxItems <= 0) {
      return SizedBox(height: 14.h);
    }

    return Text(
      '${kit.maxItems} garments',
      textAlign: TextAlign.center,
      style: CustomTextStyles.openSansBold.copyWith(
        fontSize: 10,
        color: AppColours.primary,
      ),
    );
  }

  void _onKitSelected(WardrobeKit kit) {
    setState(() {
      _selectedKitId = kit.id;
    });
  }

  Widget _buildKitOption(WardrobeKit kit) {
    final isActive = _selectedKitId == kit.id;
    final isEnabled = _isKitEnabled(kit);
    return GestureDetector(
      onTap: isEnabled ? () => _onKitSelected(kit) : null,
      child: Opacity(
        opacity: isEnabled ? 1.0 : 0.4,
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 12.h),
          decoration: BoxDecoration(
            color: isActive
                ? AppColours.primary.withOpacity(0.35)
                : const Color(0xFF16181D),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isActive
                  ? AppColours.primary
                  : AppColours.primary.withOpacity(0.45),
              width: isActive ? 1.5 : 1,
            ),
          ),
          child: Stack(
            children: [
              Padding(
                padding: EdgeInsets.only(right: isActive ? 24.w : 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        kit.displayTitle,
                        maxLines: 1,
                        softWrap: false,
                        style: CustomTextStyles.openSansSemiBold.copyWith(
                          fontSize: 12.fSize,
                          color: AppColours.secondary,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: 4.h),
                  Text(
                    kit.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: CustomTextStyles.openSansRegular.copyWith(
                      fontSize: 9,
                      color: const Color(0xFFF5E6C8).withAlpha((0.45 * 255).round()),
                    ),
                  ),
                ],
              ),
            ),
            if (isActive)
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                child: Center(child: _kitSelectionCheck()),
              ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _kitSelectionCheck() {
    const double size = 20;
    return Container(
      width: size.w,
      height: size.w,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: AppColours.primary,
        shape: BoxShape.circle,
      ),
      child: Icon(Icons.check, color: Colors.black, size: 14, weight: 900),
    );
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

  Widget _buildDeliveryScheduleSection() {
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
        _sectionHeader('SELECT DELIVERY DATE'),
        SizedBox(height: 12.h),
                  _buildDeliveryDateField(),
                ],
              ),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionHeader('SELECT DELIVERY TIME'),
                  SizedBox(height: 12.h),
                  _buildDeliveryTimeField(),
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

  Widget _buildDeliveryDateField() {
    return GestureDetector(
      onTap: () => setState(() {
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
                    _selectedDeliveryDate != null
                        ? _formatDate(_selectedDeliveryDate!)
                        : 'Select Delivery Date',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                  color: _selectedDeliveryDate != null
                      ? Colors.white
                      : AppColours.hintcolor,
                  fontSize: 12.fSize,
                    ),
                  ),
                ),
            Icon(Icons.calendar_today_outlined, color: AppColours.primary, size: 16),
              ],
            ),
          ),
    );
  }

  Widget _buildDeliveryTimeField() {
    return GestureDetector(
      onTap: () => setState(() {
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
                _selectedTimeLabel ?? 'Select Delivery Time',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _selectedTimeLabel != null
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
                  colorFilter: ColorFilter.mode(AppColours.primary, BlendMode.srcIn),
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
                _selectedTimeLabel =
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
                    _calendarMonth = DateTime(_calendarMonth.year, _calendarMonth.month + 1);
                  });
                },
                icon: Icon(Icons.chevron_right, color: AppColours.primary, size: 26),
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
        final isSelected = _selectedDeliveryDate != null &&
            _selectedDeliveryDate!.year == date.year &&
            _selectedDeliveryDate!.month == date.month &&
            _selectedDeliveryDate!.day == date.day;
        cells.add(
          GestureDetector(
            onTap: isPastDate ? null : () => setState(() => _selectedDeliveryDate = date),
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
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
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

  Widget _buildSavedAddressesSection() {
    if (_isAddressLocked) {
      _syncSelectedAddress();
    }
    final locked = _isAddressLocked;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Saved Addresses',
              style: TextStyle(
                color: AppColours.primary,
                fontSize: 14.fSize,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Spacer(),
            GestureDetector(
              onTap: locked
                  ? () {
                      ScaffoldMessenger.of(context).hideCurrentSnackBar();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Delivery address is locked for items currently in your cart.',
                          ),
                          backgroundColor: AppColours.primary,
                          behavior: SnackBarBehavior.floating,
                          duration: Duration(seconds: 2),
                        ),
                      );
                    }
                  : _openAddAddressScreen,
              child: Opacity(
                opacity: locked ? 0.4 : 1.0,
                child: Text(
                  '+ Add New Address',
                  style: TextStyle(
                    color: AppColours.primary,
                    fontSize: 12.fSize,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: 14.h),
        if (_loadingAddresses)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 16.h),
            child: Center(
              child: CircularProgressIndicator(color: AppColours.primary),
            ),
          )
        else if (_addressesError != null)
          Padding(
            padding: EdgeInsets.only(bottom: 12.h),
            child: Column(
              children: [
                Text(
                  _addressesError!,
                  style: TextStyle(color: Colors.white70, fontSize: 12.fSize),
                ),
                TextButton(
                  onPressed: _loadSavedAddresses,
                  child: Text(
                    'Retry',
                    style: TextStyle(color: AppColours.primary),
                  ),
                ),
              ],
            ),
          )
        else if (_savedAddresses.isEmpty)
          Padding(
            padding: EdgeInsets.only(bottom: 12.h),
            child: Text(
              'No saved addresses yet. Tap + Add New Address to add one.',
              style: TextStyle(color: Colors.white54, fontSize: 12.fSize),
            ),
          )
        else
          ...List.generate(_savedAddresses.length, (index) {
            final a = _savedAddresses[index];
            final selected = _selectedAddressIndex == index;
            return Padding(
              padding: EdgeInsets.only(bottom: 12.h),
              child: Opacity(
                opacity: (locked && !selected) ? 0.45 : 1.0,
                child: Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(14.w),
                  decoration: BoxDecoration(
                    color: const Color(0xFF16181D),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: selected
                          ? AppColours.primary
                          : const Color(0xFF3A3D45),
                      width: selected ? 1.2 : 1,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: locked
                              ? (selected
                                  ? null
                                  : () {
                                      ScaffoldMessenger.of(context)
                                          .hideCurrentSnackBar();
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Delivery address is locked for items currently in your cart.',
                                          ),
                                          backgroundColor: AppColours.primary,
                                          behavior: SnackBarBehavior.floating,
                                          duration: Duration(seconds: 2),
                                        ),
                                      );
                                    })
                              : () => setState(
                                  () => _selectedAddressIndex = index),
                          behavior: HitTestBehavior.opaque,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    a.title,
                                    style: TextStyle(
                                      color: AppColours.primary,
                                      fontSize: 14.fSize,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  if (locked && selected) ...[
                                    SizedBox(width: 8.w),
                                    Container(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 6.w,
                                        vertical: 2.h,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppColours.primary.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                          color: AppColours.primary
                                              .withOpacity(0.4),
                                          width: 0.8,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.lock_outline,
                                            size: 11.w,
                                            color: AppColours.primary,
                                          ),
                                          SizedBox(width: 3.w),
                                          Text(
                                            'Locked',
                                            style: TextStyle(
                                              color: AppColours.primary,
                                              fontSize: 10.fSize,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              if (a.contactName.isNotEmpty) ...[
                                SizedBox(height: 6.h),
                                Text(
                                  a.contactName,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 13.fSize,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                              SizedBox(height: 6.h),
                              Text(
                                a.addressLines,
                                style: CustomTextStyles.montserratRegular
                                    .copyWith(fontSize: 12),
                              ),
                              if (a.mobileDisplay.isNotEmpty) ...[
                                SizedBox(height: 6.h),
                                Text(
                                  'Mobile Number: ${a.mobileDisplay}',
                                  style: CustomTextStyles.montserratMedium
                                      .copyWith(fontSize: 14),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: locked
                            ? () {
                                ScaffoldMessenger.of(context)
                                    .hideCurrentSnackBar();
                                ScaffoldMessenger.of(context)
                                    .showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Cannot remove delivery address while items are in your cart.',
                                    ),
                                    backgroundColor: AppColours.primary,
                                    behavior: SnackBarBehavior.floating,
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              }
                            : () => _confirmDeleteAddress(index),
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8.w),
                          child: SvgPicture.asset(
                            IconConstant.delete2,
                            width: 28.w,
                            height: 28.w,
                            colorFilter: ColorFilter.mode(
                              locked
                                  ? AppColours.primary.withOpacity(0.3)
                                  : AppColours.primary,
                              BlendMode.srcIn,
                            ),
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: locked
                            ? (selected
                                ? null
                                : () {
                                    ScaffoldMessenger.of(context)
                                        .hideCurrentSnackBar();
                                    ScaffoldMessenger.of(context)
                                        .showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Delivery address is locked for items currently in your cart.',
                                        ),
                                        backgroundColor: AppColours.primary,
                                        behavior: SnackBarBehavior.floating,
                                        duration: Duration(seconds: 2),
                                      ),
                                    );
                                  })
                            : () => setState(
                                () => _selectedAddressIndex = index),
                        child: _addressSelectionRadio(selected),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
      ],
    );
  }

  /// Selected: gold fill + black check. Other addresses: grey fill + black check.
  Widget _addressSelectionRadio(bool selected) {
    const double size = 26;
    const Color indicatorGrey = Color(0xFF8A8A8A);

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected ? AppColours.primary : indicatorGrey,
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.check, color: Colors.black, size: 16, weight: 900),
    );
  }

  Widget _buildNextButton() {
    return Container(
      width: double.maxFinite,
      height: 44.h,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          colors: [AppColours.primary.withOpacity(0.8), AppColours.primary],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColours.primary.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: _selectedKit == null || _isSubmittingNext
            ? null
            : () async {
                setState(() => _isSubmittingNext = true);
                try {
                  if (_selectedDeliveryDate == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text('Please select a delivery date.'),
                        backgroundColor: AppColours.primary,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                    return;
                  }
                  if (_selectedTimeLabel == null || _selectedTimeLabel!.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text('Please select a delivery time.'),
                        backgroundColor: AppColours.primary,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                    return;
                  }
                  if (_savedAddresses.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text('Please add a delivery address.'),
                        backgroundColor: AppColours.primary,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                    return;
                  }

                  final selectedAddress = _savedAddresses[_selectedAddressIndex];
                  final kit = _selectedKit!;
                  var wardrobeKitProduct = ProductCache.instance.products == null
                      ? null
                      : ProductCatalog.findWardrobeKit(
                          ProductCache.instance.products!,
                          widget.wardrobeCategory,
                        );

                  if (wardrobeKitProduct == null) {
                    try {
                      final products = await ProductRepository().getProducts(
                        useNearbyLocation: true,
                        forceRefresh: false,
                      );
                      wardrobeKitProduct = ProductCatalog.findWardrobeKit(
                        products,
                        widget.wardrobeCategory,
                      );
                    } catch (e) {
                      if (kDebugMode) {
                        debugPrint('[KIT_SCREEN] Failed to fetch products for wardrobe kit: $e');
                      }
                    }
                  }

                  final kitVariantId = wardrobeKitProduct?.variants.firstOrNull?.id;

                  // ── Resolve address coordinates ──────────────────────────
                  // The backend customer-addresses API does not return lat/lng.
                  // Geocode the address text now (before opening Products) so
                  // product_repository.dart can call the nearby-products API
                  // without showing "Address Required".
                  double? resolvedLat = selectedAddress.latitude;
                  double? resolvedLng = selectedAddress.longitude;

                  if (resolvedLat == null || resolvedLng == null) {
                    final addressText = selectedAddress.addressLines.trim().isNotEmpty
                        ? selectedAddress.addressLines
                        : selectedAddress.title;
                    if (addressText.isNotEmpty) {
                      try {
                        final mapsService = GoogleMapsService();
                        final predictions = await mapsService.searchPlaces(addressText);
                        if (predictions.isNotEmpty) {
                          final resolved = await mapsService.resolvePlace(predictions.first.placeId);
                          if (resolved != null) {
                            resolvedLat = resolved.latitude;
                            resolvedLng = resolved.longitude;
                            if (kDebugMode) {
                              debugPrint('[KIT_SCREEN] Geocoded address "${selectedAddress.title}" → $resolvedLat,$resolvedLng');
                            }
                          }
                        }
                      } catch (e) {
                        if (kDebugMode) {
                          debugPrint('[KIT_SCREEN] Geocode failed: $e');
                        }
                      }
                    }
                  }

                  CheckoutSession.instance.setDelivery(
                    addressId: selectedAddress.id,
                    addressTitle: selectedAddress.title,
                    addressLines: selectedAddress.addressLines,
                    addressLatitude: resolvedLat,
                    addressLongitude: resolvedLng,
                    deliveryDate: _selectedDeliveryDate,
                    deliveryTime: _selectedTimeLabel,
                    gender: isMale ? 'male' : 'female',
                    kitType: kit.displayTitle,
                    wardrobeCategory: widget.wardrobeCategory,
                  );

                  ProductCache.instance.clear();
                  if (wardrobeKitProduct != null) {
                    ProductCache.instance.upsert(wardrobeKitProduct);
                  }

                  if (CheckoutSession.instance.useSubscriptionBooking) {
                    await SubscriptionGarmentBalance.resolveAndCache(
                      forceRefresh: true,
                    );
                  }

                  await SubscriptionKitPreferences.instance.saveFromKitSetup(
                    kitId: kit.id,
                    wardrobeKitProductId: wardrobeKitProduct?.id,
                    wardrobeKitVariantId: kitVariantId,
                    kitDays: kit.durationDays,
                    kitName: kit.displayTitle,
                    maxGarments: kit.maxItems,
                    kitPrice: kit.price,
                    wardrobeCategory: widget.wardrobeCategory,
                    addressId: selectedAddress.id,
                    addressTitle: selectedAddress.title,
                    addressLines: selectedAddress.addressLines,
                    deliveryDate: _selectedDeliveryDate!,
                    deliveryTime: _selectedTimeLabel!,
                    gender: isMale ? 'male' : 'female',
                    kitType: kit.displayTitle,
                  );

                  // Always store the kit's own max. Subscription remaining is
                  // applied at validation time so a refreshed balance can raise
                  // the cap without re-picking the kit.
                  final maxGarments = kit.maxItems;

                  if (!context.mounted) return;
                  await WardrobeBookingSession.instance.markKitSelected(
                    kitId: kit.id,
                    kitGarmentLimit: maxGarments,
                  );
                  context.read<CartBloc>().add(
                        SetWardrobeKitEvent(
                          kitId: kit.id,
                          wardrobeKitProductId: wardrobeKitProduct?.id,
                          wardrobeKitVariantId: kitVariantId,
                          kitDays: kit.durationDays,
                          kitName: kit.displayTitle,
                          maxGarments: maxGarments,
                          kitPrice: kit.price,
                          wardrobeCategory: widget.wardrobeCategory,
                          wardrobeCategoryId: WardrobeBookingSession
                              .instance.wardrobeCategoryId,
                        ),
                      );

                  if (kDebugMode) {
                    debugPrint('[WARDROBE_KIT_NEXT_CLICKED]');
                  }

                  try {
                    await ProductRepository().getProducts(
                      forceRefresh: true,
                      useNearbyLocation: true,
                      tab: widget.wardrobeCategory,
                      limit: 50,
                      page: 1,
                    );
                  } catch (e) {
                    if (kDebugMode) {
                      debugPrint('[NEARBY_API_CALL_FAILED] error=$e');
                    }
                  }

                  if (!context.mounted) return;
                  Navigator.pushNamed(
                    context,
                    AppRoutes.wardrobeScreen,
                    arguments: widget.wardrobeCategory,
                  );
                } finally {
                  if (mounted) {
                    setState(() => _isSubmittingNext = false);
                  }
                }
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Text(
          'NEXT',
          style: TextStyle(
            color: Colors.black,
            fontSize: 16.fSize,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
