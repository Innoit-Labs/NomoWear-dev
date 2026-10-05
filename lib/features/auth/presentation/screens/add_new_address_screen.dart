import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nomowear/core/utils/size_utils.dart';
import 'package:nomowear/routes/app_routes.dart';
import 'package:nomowear/theme/theme_helper.dart';
import 'package:nomowear/features/profile/domain/saved_address.dart';

/// Full-screen add address form. Pops with `Map<String,String>` keys:
/// `title`, `addressLines`, `phone`, `contactName` — or `null` if user goes back without saving.
///
/// Pass [initialAddress] (e.g. via route `arguments`) to pre-fill for edit.
class AddNewAddressScreen extends StatefulWidget {
  final SavedAddress? initialAddress;
  final String? initialLocationDetails;
  final String? initialAreaTitle;
  final double? initialLatitude;
  final double? initialLongitude;
  final String? initialBuildingNumber;
  final String? initialStreetName;

  const AddNewAddressScreen({
    super.key,
    this.initialAddress,
    this.initialLocationDetails,
    this.initialAreaTitle,
    this.initialLatitude,
    this.initialLongitude,
    this.initialBuildingNumber,
    this.initialStreetName,
  });

  @override
  State<AddNewAddressScreen> createState() => _AddNewAddressScreenState();
}

class _AddNewAddressScreenState extends State<AddNewAddressScreen> {
  final _nameController = TextEditingController(text: '');
  final _mobileController = TextEditingController(text: '');
  final _buildingController = TextEditingController();
  final _streetController = TextEditingController();
  final _saveAsController = TextEditingController();

  String _locationDetails = '';
  String _areaTitle = '';
  double? _latitude;
  double? _longitude;

  static const _bg = Color(0xFF0F1012);
  static const _fieldFill = Color(0xFF16181D);

  @override
  void initState() {
    super.initState();
    _applyPickedLocation(
      locationDetails: widget.initialLocationDetails,
      areaTitle: widget.initialAreaTitle,
      latitude: widget.initialLatitude,
      longitude: widget.initialLongitude,
      buildingNumber: widget.initialBuildingNumber,
      streetName: widget.initialStreetName,
    );

    final i = widget.initialAddress;
    if (i == null) {
      if (_locationDetails.isEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _onChangeLocation());
      }
      return;
    }

    _nameController.text = i.contactName;
    _saveAsController.text = i.title;
    _mobileController.text = i.mobileDisplay;

    if (i.locationDetails.trim().isNotEmpty) {
      _locationDetails = i.locationDetails.trim();
    } else if (_locationDetails.isEmpty && i.addressLines.trim().isNotEmpty) {
      _locationDetails = i.addressLines.trim();
    }

    if (i.buildingNumber.trim().isNotEmpty) {
      _buildingController.text = i.buildingNumber.trim();
    }
    if (i.streetName.trim().isNotEmpty) {
      _streetController.text = i.streetName.trim();
    }

    if (i.latitude != null) _latitude = i.latitude;
    if (i.longitude != null) _longitude = i.longitude;

    if (_buildingController.text.isEmpty && _streetController.text.isEmpty) {
      final parts = i.addressLines
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      if (parts.length >= 2) {
        _buildingController.text = parts.first;
        _streetController.text = parts.sublist(1).join(', ');
      } else if (i.addressLines.trim().isNotEmpty) {
        _buildingController.text = i.addressLines.trim();
      }
    }
  }

  void _applyPickedLocation({
    String? locationDetails,
    String? areaTitle,
    double? latitude,
    double? longitude,
    String? buildingNumber,
    String? streetName,
  }) {
    final details = locationDetails?.trim();
    if (details != null && details.isNotEmpty) {
      _locationDetails = details;
    }

    final area = areaTitle?.trim();
    if (area != null && area.isNotEmpty) {
      _areaTitle = area;
    }

    if (latitude != null) _latitude = latitude;
    if (longitude != null) _longitude = longitude;

    if (buildingNumber != null && buildingNumber.trim().isNotEmpty) {
      _buildingController.text = buildingNumber.trim();
    }
    
    if (streetName != null && streetName.trim().isNotEmpty) {
      _streetController.text = streetName.trim();
    }
  }

  double? _readCoordinate(dynamic value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  InputBorder _goldOutline() {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: AppColours.primary, width: 0.8),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _mobileController.dispose();
    _buildingController.dispose();
    _streetController.dispose();
    _saveAsController.dispose();
    super.dispose();
  }

  Future<void> _onChangeLocation() async {
    final picked = await Navigator.pushNamed(
      context,
      AppRoutes.selectAddressScreen,
    );
    if (!mounted || picked is! Map) return;

    setState(() {
      _applyPickedLocation(
        locationDetails: picked['locationDetails']?.toString(),
        areaTitle: picked['areaTitle']?.toString(),
        latitude: _readCoordinate(picked['latitude']),
        longitude: _readCoordinate(picked['longitude']),
        buildingNumber: picked['buildingNumber']?.toString(),
        streetName: picked['streetName']?.toString(),
      );
    });
  }

  String _composedAddressLines() {
    final b = _buildingController.text.trim();
    final s = _streetController.text.trim();
    final parts = <String>[];
    
    final lowerLoc = _locationDetails.toLowerCase();
    
    if (b.isNotEmpty && s.isNotEmpty && b == s) {
      if (!lowerLoc.contains(b.toLowerCase())) {
        parts.add(b);
      }
    } else {
      if (b.isNotEmpty && !lowerLoc.contains(b.toLowerCase())) {
        parts.add(b);
      }
      if (s.isNotEmpty && !lowerLoc.contains(s.toLowerCase())) {
        parts.add(s);
      }
    }
    
    if (_locationDetails.isNotEmpty) parts.add(_locationDetails);
    
    if (parts.isEmpty) return _locationDetails;
    if (parts.length == 1) return parts.first;
    final head = parts.sublist(0, parts.length - 1).join(', ');
    return '$head\n${parts.last}';
  }

  void _onSave() {
    final name = _nameController.text.trim();
    final mobile = _mobileController.text.trim();
    final building = _buildingController.text.trim();
    final street = _streetController.text.trim();
    final saveAs = _saveAsController.text.trim();

    if (name.isEmpty ||
        mobile.isEmpty ||
        building.isEmpty ||
        street.isEmpty ||
        saveAs.isEmpty ||
        _locationDetails.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _locationDetails.trim().isEmpty
                ? 'Please select a location on the map.'
                : 'Please fill in all fields.',
            style: const TextStyle(color: Colors.black),
          ),
          backgroundColor: AppColours.primary,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }

    final digitsOnly = mobile.replaceAll(RegExp(r'\D'), '');
    if (digitsOnly.length != 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Please enter a valid 10-digit mobile number.',
            style: TextStyle(color: Colors.black),
          ),
          backgroundColor: AppColours.primary,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }

    Navigator.pop(context, {
      'title': saveAs,
      'addressLines': _composedAddressLines(),
      'phone': mobile,
      'contactName': name,
      'buildingNumber': building,
      'streetName': street,
      if (_areaTitle.isNotEmpty) 'areaTitle': _areaTitle,
      if (_latitude != null) 'latitude': _latitude.toString(),
      if (_longitude != null) 'longitude': _longitude.toString(),
      'locationDetails': _locationDetails,
    });
  }

  Widget _label(String text) {
    return Padding(
      padding: EdgeInsets.only(bottom: 8.h),
      child: Text(
        text,
        style: TextStyle(
          color: AppColours.primary,
          fontSize: 11.fSize,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _goldBorderField({
    required TextEditingController controller,
    required String hint,
    TextInputType keyboardType = TextInputType.text,
    int? maxLength,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLength: maxLength,
      inputFormatters: inputFormatters,
      style: CustomTextStyles.openSansBold.copyWith(
        fontSize: 14,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.white38, fontSize: 14.fSize),
        filled: true,
        fillColor: _fieldFill,
        counterText: '',
        contentPadding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 16.h),
        enabledBorder: _goldOutline(),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColours.primary, width: 1.2),
        ),
      ),
    );
  }

  Widget _locationRow() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 14.h),
      decoration: BoxDecoration(
        color: _fieldFill,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColours.primary, width: 0.8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.location_on, color: AppColours.primary, size: 22),
          SizedBox(width: 8.w),
          Expanded(
            child: Text(
              _locationDetails.isEmpty
                  ? 'Select location on map'
                  : _locationDetails,
              style: CustomTextStyles.openSansBold.copyWith(
                fontSize: 13,
                height: 1.35,
                color: _locationDetails.isEmpty ? Colors.white38 : Colors.white,
              ),
            ),
          ),
          GestureDetector(
            onTap: _onChangeLocation,
            child: Padding(
              padding: EdgeInsets.only(left: 8.w, top: 2.h),
              child: Text(
                _locationDetails.isEmpty ? 'SELECT' : 'CHANGE',
                style: TextStyle(
                  color: AppColours.primary,
                  fontSize: 12.fSize,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.6,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _saveAsField() {
    return Container(
      padding: EdgeInsets.only(left: 14.w, right: 14.w, top: 4.h),
      decoration: const BoxDecoration(
        color: _fieldFill,
        border: Border(
          bottom: BorderSide(color: AppColours.primary, width: 1.2),
        ),
      ),
      child: TextField(
        controller: _saveAsController,
        style: CustomTextStyles.openSansBold.copyWith(
          fontSize: 14,
          color: Colors.white,
        ),
        decoration: InputDecoration(
          hintText: 'Example: Work , Home',
          hintStyle: TextStyle(color: Colors.white38, fontSize: 14.fSize),
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(vertical: 14.h),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.symmetric(vertical: 14.h, horizontal: 8.w),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.arrow_back, color: AppColours.primary),
                  ),
                  Expanded(
                    child: Text(
                      widget.initialAddress == null
                          ? 'Add New Address'
                          : 'Edit Address',
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
                padding: EdgeInsets.fromLTRB(20.w, 24.h, 20.w, 24.h),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label('FULL NAME *'),
                    _goldBorderField(
                      controller: _nameController,
                      hint: 'Enter full name',
                    ),
                    SizedBox(height: 20.h),
                    _label('MOBILE NUMBER *'),
                    _goldBorderField(
                      controller: _mobileController,
                      hint: 'Enter MOBILE NUMBER',
                      keyboardType: TextInputType.phone,
                      maxLength: 10,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                    ),
                    SizedBox(height: 20.h),
                    _label('LOCATION DETAILS *'),
                    _locationRow(),
                    SizedBox(height: 20.h),
                    _label('BUILDING/ FLOOR NO *'),
                    _goldBorderField(
                      controller: _buildingController,
                      hint: 'Enter building/floor no',
                    ),
                    SizedBox(height: 20.h),
                    _label('STREET NAME *'),
                    _goldBorderField(
                      controller: _streetController,
                      hint: 'Enter street name',
                    ),
                    SizedBox(height: 20.h),
                    _label('SAVE ADDRESS AS *'),
                    _saveAsField(),
                  ],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 20.h),
              child: SizedBox(
                width: double.infinity,
                height: 44.h,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: LinearGradient(
                      colors: [
                        AppColours.primary.withOpacity(0.85),
                        AppColours.primary,
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColours.primary.withOpacity(0.25),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ElevatedButton(
                    onPressed: _onSave,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'Save & Continue',
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 15.fSize,
                        fontWeight: FontWeight.bold,
                      ),
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
}
