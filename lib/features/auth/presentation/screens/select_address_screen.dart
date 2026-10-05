import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:nomowear/core/config/google_maps_config.dart';
import 'package:nomowear/core/services/google_maps_service.dart';
import 'package:nomowear/core/utils/size_utils.dart';
import 'package:nomowear/theme/theme_helper.dart';

/// Map-based address picker. Pops with a `Map<String, dynamic>`:
/// `areaTitle`, `locationDetails`, `latitude`, `longitude`.
class SelectAddressScreen extends StatefulWidget {
  final double? initialLatitude;
  final double? initialLongitude;

  const SelectAddressScreen({
    super.key,
    this.initialLatitude,
    this.initialLongitude,
  });

  @override
  State<SelectAddressScreen> createState() => _SelectAddressScreenState();
}

class _SelectAddressScreenState extends State<SelectAddressScreen> {
  final GoogleMapsService _mapsService = GoogleMapsService();
  final TextEditingController _searchController = TextEditingController();
  final MapController _mapController = MapController();

  static final LatLng _defaultCenter = LatLng(
    GoogleMapsConfig.defaultLatitude,
    GoogleMapsConfig.defaultLongitude,
  );

  late LatLng _mapCenter;
  ResolvedAddress? _resolvedAddress;
  List<PlacePrediction> _predictions = [];
  bool _isResolvingAddress = true;
  bool _showPredictions = false;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    final lat = widget.initialLatitude;
    final lng = widget.initialLongitude;
    if (lat != null && lng != null) {
      _mapCenter = LatLng(lat, lng);
    } else {
      _mapCenter = _defaultCenter;
    }
    _searchController.addListener(_onSearchChanged);
    _resolveAddressAt(_mapCenter);
    if (lat == null || lng == null) {
      _tryMoveToCurrentLocation();
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _tryMoveToCurrentLocation() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }

      final position = await Geolocator.getCurrentPosition();
      final target = LatLng(position.latitude, position.longitude);
      if (!mounted) return;

      setState(() => _mapCenter = target);
      _mapController.move(target, 16);
      await _resolveAddressAt(target);
    } catch (_) {
      // Keep default center when location is unavailable.
    }
  }

  void _onSearchChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () async {
      final query = _searchController.text.trim();
      if (!mounted) return;
      if (query.length < 2) {
        setState(() {
          _predictions = [];
          _showPredictions = false;
        });
        return;
      }

      final results = await _mapsService.searchPlaces(query);
      if (!mounted) return;
      setState(() {
        _predictions = results;
        _showPredictions = results.isNotEmpty;
      });
    });
  }

  Future<void> _resolveAddressAt(LatLng position) async {
    setState(() => _isResolvingAddress = true);
    final resolved = await _mapsService.reverseGeocode(
      latitude: position.latitude,
      longitude: position.longitude,
    );
    if (!mounted) return;
    setState(() {
      _mapCenter = position;
      _resolvedAddress = resolved;
      _isResolvingAddress = false;
    });
  }

  Future<void> _onPredictionTap(PlacePrediction prediction) async {
    FocusScope.of(context).unfocus();
    setState(() {
      _showPredictions = false;
      _predictions = [];
      _searchController.text = prediction.description;
      _isResolvingAddress = true;
    });

    final resolved = await _mapsService.resolvePlace(prediction.placeId);
    if (!mounted || resolved == null) {
      setState(() => _isResolvingAddress = false);
      return;
    }

    final target = LatLng(resolved.latitude, resolved.longitude);
    
    // Update state before moving the map to prevent _onMapMoved from overriding the resolved address
    if (!mounted) return;
    setState(() {
      _mapCenter = target;
      _resolvedAddress = resolved;
      _isResolvingAddress = false;
    });

    _mapController.move(target, 16);
  }

  void _onConfirm() {
    final address = _resolvedAddress;
    if (address == null) return;

    String finalAddress = address.fullAddress;
    if (address.areaTitle.isNotEmpty && !address.fullAddress.toLowerCase().contains(address.areaTitle.toLowerCase())) {
      finalAddress = '${address.areaTitle}, ${address.fullAddress}';
    }

    debugPrint('SELECTED PLACE NAME = ${address.areaTitle}');
    debugPrint('SELECTED PLACE ADDRESS = ${address.fullAddress}');
    debugPrint('FINAL PROFILE ADDRESS = $finalAddress');

    Navigator.pop(context, {
      'areaTitle': address.areaTitle,
      'locationDetails': finalAddress,
      'latitude': address.latitude,
      'longitude': address.longitude,
      'buildingNumber': address.buildingNumber,
      'streetName': address.streetName,
      'country': address.country,
      'state': address.state,
      'city': address.city,
      'pincode': address.pincode,
    });
  }

  void _onMapMoved() {
    final center = _mapController.camera.center;
    if (center.latitude == _mapCenter.latitude &&
        center.longitude == _mapCenter.longitude) {
      return;
    }
    _resolveAddressAt(center);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1012),
      body: SafeArea(
        child: Column(
          children: [
            _buildAppBar(),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: FlutterMap(
                      mapController: _mapController,
                      options: MapOptions(
                        initialCenter: _mapCenter,
                        initialZoom: 15,
                        onMapEvent: (event) {
                          if (event is MapEventMoveEnd) {
                            _onMapMoved();
                          }
                        },
                      ),
                      children: [
                        TileLayer(
                          urlTemplate:
                              'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.example.nomowear',
                          tileBuilder: darkModeTileBuilder,
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    top: 12.h,
                    left: 16.w,
                    right: 16.w,
                    child: _buildSearchBar(),
                  ),
                  if (_showPredictions)
                    Positioned(
                      top: 68.h,
                      left: 16.w,
                      right: 16.w,
                      child: _buildPredictionsList(),
                    ),
                  Center(
                    child: Padding(
                      padding: EdgeInsets.only(bottom: 36.h),
                      child: Icon(
                        Icons.location_on,
                        size: 44,
                        color: AppColours.primary,
                        shadows: [
                          Shadow(
                            color: Colors.black.withValues(alpha: 0.45),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _buildBottomCard(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 10.h),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Icon(Icons.arrow_back, color: AppColours.primary),
          ),
          Expanded(
            child: Text(
              'Select Address',
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
    );
  }

  Widget _buildSearchBar() {
    return Material(
      color: Colors.transparent,
      child: TextField(
        controller: _searchController,
        style: TextStyle(color: Colors.white, fontSize: 14.fSize),
        decoration: InputDecoration(
          hintText: 'Search for an area or address street',
          hintStyle: TextStyle(
            color: Colors.white38,
            fontSize: 13.fSize,
          ),
          prefixIcon: Icon(Icons.search, color: AppColours.primary),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.close, color: AppColours.primary, size: 20),
                  onPressed: () {
                    _searchController.clear();
                    setState(() {
                      _predictions = [];
                      _showPredictions = false;
                    });
                  },
                )
              : null,
          filled: true,
          fillColor: const Color(0xFF16181D),
          contentPadding: EdgeInsets.symmetric(vertical: 14.h),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppColours.primary.withValues(alpha: 0.7)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColours.primary, width: 1.2),
          ),
        ),
        onChanged: (_) => setState(() {}),
        onTap: () {
          if (_predictions.isNotEmpty) {
            setState(() => _showPredictions = true);
          }
        },
      ),
    );
  }

  Widget _buildPredictionsList() {
    return Material(
      elevation: 6,
      color: const Color(0xFF16181D),
      borderRadius: BorderRadius.circular(12),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: 220.h),
        child: ListView.separated(
          shrinkWrap: true,
          padding: EdgeInsets.symmetric(vertical: 8.h),
          itemCount: _predictions.length,
          separatorBuilder: (_, __) => Divider(
            height: 1,
            color: Colors.white.withValues(alpha: 0.08),
          ),
          itemBuilder: (context, index) {
            final item = _predictions[index];
            return ListTile(
              dense: true,
              leading: Icon(Icons.location_on_outlined, color: AppColours.primary),
              title: Text(
                item.mainText,
                style: TextStyle(color: Colors.white, fontSize: 13.fSize),
              ),
              subtitle: item.secondaryText.isEmpty
                  ? null
                  : Text(
                      item.secondaryText,
                      style: TextStyle(color: Colors.white54, fontSize: 11.fSize),
                    ),
              onTap: () => _onPredictionTap(item),
            );
          },
        ),
      ),
    );
  }

  Widget _buildBottomCard() {
    final areaTitle = _resolvedAddress?.areaTitle ?? 'Locating...';
    final fullAddress = _resolvedAddress?.fullAddress ?? 'Move the map to pick a location';

    return Container(
      margin: EdgeInsets.all(16.w),
      padding: EdgeInsets.fromLTRB(16.w, 18.h, 16.w, 16.h),
      decoration: BoxDecoration(
        color: const Color(0xFF16181D),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColours.primary.withValues(alpha: 0.45)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.location_on, color: AppColours.primary, size: 22),
              SizedBox(width: 10.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      areaTitle,
                      style: TextStyle(
                        color: AppColours.primary,
                        fontSize: 16.fSize,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 6.h),
                    Text(
                      _isResolvingAddress ? 'Fetching address...' : fullAddress,
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12.fSize,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 18.h),
          SizedBox(
            width: double.infinity,
            height: 44.h,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: LinearGradient(
                  colors: [
                    AppColours.primary.withValues(alpha: 0.85),
                    AppColours.primary,
                  ],
                ),
              ),
              child: ElevatedButton(
                onPressed: _resolvedAddress == null || _isResolvingAddress
                    ? null
                    : _onConfirm,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  disabledBackgroundColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  'Confirm & Proceed',
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 15.fSize,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
