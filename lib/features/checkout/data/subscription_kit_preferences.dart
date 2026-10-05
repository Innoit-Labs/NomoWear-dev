import 'package:shared_preferences/shared_preferences.dart';

/// Persists wardrobe kit / delivery choices across subscription bookings so
/// subsequent CHOOSE flows can skip the kit setup screen.
class SubscriptionKitPreferences {
  SubscriptionKitPreferences._();

  static final SubscriptionKitPreferences instance =
      SubscriptionKitPreferences._();

  String? wardrobeKitId;
  String? wardrobeKitProductId;
  String? wardrobeKitVariantId;
  int wardrobeKitDays = 0;
  String wardrobeKitName = '';
  int wardrobeKitMaxGarments = 0;
  String? wardrobeKitPrice;
  String? wardrobeCategory;

  String? addressId;
  String? addressTitle;
  String? addressLines;
  int? deliveryDateEpochMs;
  String? deliveryTime;
  String? gender;
  String? kitType;

  bool hasCompletedFirstSubscriptionBooking = false;

  bool get isKitConfigured {
    if (wardrobeKitId == null || wardrobeKitId!.trim().isEmpty) return false;
    if (addressId == null || addressId!.trim().isEmpty) return false;
    if (gender == null || gender!.trim().isEmpty) return false;
    if (kitType == null || kitType!.trim().isEmpty) return false;
    if (deliveryDateEpochMs == null || deliveryDateEpochMs! <= 0) return false;
    return true;
  }

  Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    wardrobeKitId = prefs.getString(_kWardrobeKitId);
    wardrobeKitProductId = prefs.getString(_kWardrobeKitProductId);
    wardrobeKitVariantId = prefs.getString(_kWardrobeKitVariantId);
    wardrobeKitDays = prefs.getInt(_kWardrobeKitDays) ?? 0;
    wardrobeKitName = prefs.getString(_kWardrobeKitName) ?? '';
    wardrobeKitMaxGarments = prefs.getInt(_kWardrobeKitMaxGarments) ?? 0;
    wardrobeKitPrice = prefs.getString(_kWardrobeKitPrice);
    wardrobeCategory = prefs.getString(_kWardrobeCategory);
    addressId = prefs.getString(_kAddressId);
    addressTitle = prefs.getString(_kAddressTitle);
    addressLines = prefs.getString(_kAddressLines);
    deliveryDateEpochMs = prefs.getInt(_kDeliveryDateEpochMs);
    deliveryTime = prefs.getString(_kDeliveryTime);
    gender = prefs.getString(_kGender);
    kitType = prefs.getString(_kKitType);
    hasCompletedFirstSubscriptionBooking =
        prefs.getBool(_kHasCompletedFirstBooking) ?? false;
  }

  Future<void> saveFromKitSetup({
    required String kitId,
    String? wardrobeKitProductId,
    String? wardrobeKitVariantId,
    required int kitDays,
    required String kitName,
    required int maxGarments,
    required String kitPrice,
    required String wardrobeCategory,
    required String addressId,
    required String addressTitle,
    required String addressLines,
    required DateTime deliveryDate,
    required String deliveryTime,
    required String gender,
    required String kitType,
  }) async {
    wardrobeKitId = kitId;
    this.wardrobeKitProductId = wardrobeKitProductId;
    this.wardrobeKitVariantId = wardrobeKitVariantId;
    wardrobeKitDays = kitDays;
    wardrobeKitName = kitName;
    wardrobeKitMaxGarments = maxGarments;
    wardrobeKitPrice = kitPrice;
    this.wardrobeCategory = wardrobeCategory;
    this.addressId = addressId;
    this.addressTitle = addressTitle;
    this.addressLines = addressLines;
    deliveryDateEpochMs = deliveryDate.millisecondsSinceEpoch;
    this.deliveryTime = deliveryTime;
    this.gender = gender;
    this.kitType = kitType;
    await _persist();
  }

  Future<void> markFirstSubscriptionBookingCompleted() async {
    hasCompletedFirstSubscriptionBooking = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kHasCompletedFirstBooking, true);
  }

  Future<void> clear() async {
    wardrobeKitId = null;
    wardrobeKitProductId = null;
    wardrobeKitVariantId = null;
    wardrobeKitDays = 0;
    wardrobeKitName = '';
    wardrobeKitMaxGarments = 0;
    wardrobeKitPrice = null;
    wardrobeCategory = null;
    addressId = null;
    addressTitle = null;
    addressLines = null;
    deliveryDateEpochMs = null;
    deliveryTime = null;
    gender = null;
    kitType = null;
    hasCompletedFirstSubscriptionBooking = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kWardrobeKitId);
    await prefs.remove(_kWardrobeKitProductId);
    await prefs.remove(_kWardrobeKitVariantId);
    await prefs.remove(_kWardrobeKitDays);
    await prefs.remove(_kWardrobeKitName);
    await prefs.remove(_kWardrobeKitMaxGarments);
    await prefs.remove(_kWardrobeKitPrice);
    await prefs.remove(_kWardrobeCategory);
    await prefs.remove(_kAddressId);
    await prefs.remove(_kAddressTitle);
    await prefs.remove(_kAddressLines);
    await prefs.remove(_kDeliveryDateEpochMs);
    await prefs.remove(_kDeliveryTime);
    await prefs.remove(_kGender);
    await prefs.remove(_kKitType);
    await prefs.remove(_kHasCompletedFirstBooking);
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await _setString(prefs, _kWardrobeKitId, wardrobeKitId);
    await _setString(prefs, _kWardrobeKitProductId, wardrobeKitProductId);
    await _setString(prefs, _kWardrobeKitVariantId, wardrobeKitVariantId);
    await prefs.setInt(_kWardrobeKitDays, wardrobeKitDays);
    await _setString(prefs, _kWardrobeKitName, wardrobeKitName);
    await prefs.setInt(_kWardrobeKitMaxGarments, wardrobeKitMaxGarments);
    await _setString(prefs, _kWardrobeKitPrice, wardrobeKitPrice);
    await _setString(prefs, _kWardrobeCategory, wardrobeCategory);
    await _setString(prefs, _kAddressId, addressId);
    await _setString(prefs, _kAddressTitle, addressTitle);
    await _setString(prefs, _kAddressLines, addressLines);
    if (deliveryDateEpochMs != null && deliveryDateEpochMs! > 0) {
      await prefs.setInt(_kDeliveryDateEpochMs, deliveryDateEpochMs!);
    } else {
      await prefs.remove(_kDeliveryDateEpochMs);
    }
    await _setString(prefs, _kDeliveryTime, deliveryTime);
    await _setString(prefs, _kGender, gender);
    await _setString(prefs, _kKitType, kitType);
    await prefs.setBool(
      _kHasCompletedFirstBooking,
      hasCompletedFirstSubscriptionBooking,
    );
  }

  Future<void> _setString(
    SharedPreferences prefs,
    String key,
    String? value,
  ) async {
    final trimmed = value?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      await prefs.setString(key, trimmed);
    } else {
      await prefs.remove(key);
    }
  }
}

const String _kWardrobeKitId = 'sub_kit_wardrobe_kit_id';
const String _kWardrobeKitProductId = 'sub_kit_wardrobe_kit_product_id';
const String _kWardrobeKitVariantId = 'sub_kit_wardrobe_kit_variant_id';
const String _kWardrobeKitDays = 'sub_kit_wardrobe_kit_days';
const String _kWardrobeKitName = 'sub_kit_wardrobe_kit_name';
const String _kWardrobeKitMaxGarments = 'sub_kit_wardrobe_kit_max_garments';
const String _kWardrobeKitPrice = 'sub_kit_wardrobe_kit_price';
const String _kWardrobeCategory = 'sub_kit_wardrobe_category';
const String _kAddressId = 'sub_kit_address_id';
const String _kAddressTitle = 'sub_kit_address_title';
const String _kAddressLines = 'sub_kit_address_lines';
const String _kDeliveryDateEpochMs = 'sub_kit_delivery_date_epoch_ms';
const String _kDeliveryTime = 'sub_kit_delivery_time';
const String _kGender = 'sub_kit_gender';
const String _kKitType = 'sub_kit_kit_type';
const String _kHasCompletedFirstBooking = 'sub_kit_has_completed_first_booking';
