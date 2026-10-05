import 'package:flutter_svg/flutter_svg.dart';
import 'package:nomowear/core/app_export.dart';

class DeliveryLocationBottomSheet extends StatefulWidget {
  final void Function(String address) onAddressSelected;

  const DeliveryLocationBottomSheet({
    Key? key,
    required this.onAddressSelected,
  }) : super(key: key);

  @override
  State<DeliveryLocationBottomSheet> createState() =>
      _DeliveryLocationBottomSheetState();
}

class _DeliveryLocationBottomSheetState
    extends State<DeliveryLocationBottomSheet>
    with SingleTickerProviderStateMixin {
  // ── Controllers ────────────────────────────────────────────────────────────
  final _nameController = TextEditingController();
  final _mobileController = TextEditingController();
  final _pincodeController = TextEditingController();
  final _addressController = TextEditingController();

  // ── State ──────────────────────────────────────────────────────────────────
  bool _isMale = true;

  String? _selectedCountry;
  String? _selectedState;
  String? _selectedCity;

  DateTime? _selectedDate;
  String? _selectedTime;

  // ── Time picker state ──────────────────────────────────────────────────────
  bool _showTimePicker = false;
  int _selectedHour = 12;
  int _selectedMinute = 40;
  bool _isAM = false; // false = PM
  late FixedExtentScrollController _hourController;
  late FixedExtentScrollController _minuteController;
  late FixedExtentScrollController _periodController;

  // ── Animation ──────────────────────────────────────────────────────────────
  late AnimationController _animController;
  late Animation<double> _slideAnimation;

  // ── Data ───────────────────────────────────────────────────────────────────
  final List<String> _countries = ['India', 'USA', 'UAE', 'UK', 'Australia'];
  final List<String> _states = [
    'Karnataka',
    'Maharashtra',
    'Tamil Nadu',
    'Delhi',
    'Telangana',
  ];
  final List<String> _cities = [
    'Bengaluru',
    'Mumbai',
    'Chennai',
    'Hyderabad',
    'Delhi',
  ];

  @override
  void initState() {
    super.initState();
    _hourController = FixedExtentScrollController(initialItem: _selectedHour - 1);
    _minuteController = FixedExtentScrollController(initialItem: _selectedMinute);
    _periodController = FixedExtentScrollController(initialItem: _isAM ? 1 : 0);
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    )..forward();
    _slideAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    _hourController.dispose();
    _minuteController.dispose();
    _periodController.dispose();
    _nameController.dispose();
    _mobileController.dispose();
    _pincodeController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  // ── Date picker ────────────────────────────────────────────────────────────
  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 90)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: ColorScheme.dark(
            primary: AppColours.primary,
            surface: const Color(0xFF1A1D21),
            onSurface: Colors.white,
          ),
          dialogBackgroundColor: const Color(0xFF0F1012),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  // ── Date formatter (no intl dependency) ────────────────────────────────────
  String _formatDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day.toString().padLeft(2, '0')} ${months[d.month - 1]} ${d.year}';
  }

  // ── Save & continue ────────────────────────────────────────────────────────
  void _onSave() {
    final name = _nameController.text.trim();
    final mobile = _mobileController.text.trim();
    final pin = _pincodeController.text.trim();
    final addr = _addressController.text.trim();

    if (name.isEmpty ||
        mobile.isEmpty ||
        _selectedCountry == null ||
        _selectedState == null ||
        _selectedCity == null ||
        pin.isEmpty ||
        addr.isEmpty ||
        _selectedDate == null ||
        _selectedTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Please fill in all fields.',
            style: TextStyle(color: Colors.black),
          ),
          backgroundColor: AppColours.primary,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }

    final fullAddress =
        '$addr, $_selectedCity, $_selectedState, $_selectedCountry - $pin';
    widget.onAddressSelected(fullAddress);
  }

  // ══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 1),
        end: Offset.zero,
      ).animate(_slideAnimation),
      child: Container(
        // Let content push up with keyboard
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        decoration: const BoxDecoration(
          color: Color(0xFF131417),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Gender row with X in centre ──────────────────────────────
            _buildGenderRow(),
            // ── Title ────────────────────────────────────────────────────
            Padding(
              padding: EdgeInsets.only(top: 16.h, bottom: 16.h),
              child: Text(
                'Enter Delivery Details',
                style: CustomTextStyles.montserratBold.copyWith(color: AppColours.primary,fontSize: 16),
              ),
            ),
            // ── Scrollable form ──────────────────────────────────────────
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: 16.w),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _fieldLabel('FULL NAME *'),
                    SizedBox(height: 6.h),
                    _textInput(_nameController, 'Divya Sanapala'),
                    SizedBox(height: 14.h),

                    _fieldLabel('MOBILE NUMBER *'),
                    SizedBox(height: 6.h),
                    _textInput(
                      _mobileController,
                      '+91 99999 99999',
                      keyboardType: TextInputType.phone,
                    ),
                    SizedBox(height: 14.h),

                    _fieldLabel('SELECT LOCATION'),
                    SizedBox(height: 6.h),
                    _buildLocationRow(),
                    SizedBox(height: 14.h),

                    _fieldLabel('PINCODE *'),
                    SizedBox(height: 6.h),
                    _textInput(
                      _pincodeController,
                      'Enter Pincode',
                      keyboardType: TextInputType.number,
                    ),
                    SizedBox(height: 14.h),

                    _fieldLabel('ENTER FULL ADDRESS'),
                    SizedBox(height: 6.h),
                    _textInput(
                      _addressController,
                      'Enter your full address',
                      maxLines: 3,
                    ),
                    SizedBox(height: 14.h),

                    _fieldLabel('SELECT DELIVERY DATE'),
                    SizedBox(height: 6.h),
                    _buildDatePicker(),
                    SizedBox(height: 14.h),

                    _fieldLabel('SELECT DELIVERY TIME'),
                    SizedBox(height: 6.h),
                    _buildTimeDropdown(),
                    SizedBox(height: 24.h),
                  ],
                ),
              ),
            ),
            // ── Save & Continue button ────────────────────────────────────
            _buildSaveButton(),
          ],
        ),
      ),
    );
  }

  // ── Gender row ─────────────────────────────────────────────────────────────
  Widget _buildGenderRow() {
    return Container(
      margin: EdgeInsets.only(top: 2.h),
      padding: EdgeInsets.symmetric(horizontal: 2.w, vertical: 2.h),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1D21),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(
          bottom: BorderSide(color: AppColours.primary.withOpacity(0.15)),
        ),
      ),
      child: Row(
        children: [
          // Male tab
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _isMale = true),
              child: Container(
                height: 44.h,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _isMale
                      ? AppColours.primary.withOpacity(0.15)
                      : Colors.transparent,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(22),
                    bottomLeft: Radius.circular(4),
                  ),
                ),
                child: Text(
                  'Male',
                  style: TextStyle(
                    color: _isMale ? AppColours.primary : Colors.white54,
                    fontSize: 14.fSize,
                    fontWeight:
                        _isMale ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
            ),
          ),



          // Centre X close button
          Column(
            children: [
              SizedBox(height: 100), // 👈 top spacing

              
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 36.w,
                  height: 36.h,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColours.primary.withOpacity(0.6),
                      width: 1.5,
                    ),
                  ),
                  child: Icon(
                    Icons.close_rounded,
                    color: AppColours.primary,
                    size: 18,
                  ),
                ),
              ),
            ],
          ),

          // Female tab
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _isMale = false),
              child: Container(
                height: 44.h,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: !_isMale
                      ? AppColours.primary.withOpacity(0.15)
                      : Colors.transparent,
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(22),
                    bottomRight: Radius.circular(4),
                  ),
                ),
                child: Text(
                  'Female',
                  style: TextStyle(
                    color: !_isMale ? AppColours.primary : Colors.white54,
                    fontSize: 14.fSize,
                    fontWeight:
                        !_isMale ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Field label ────────────────────────────────────────────────────────────
  Widget _fieldLabel(String text) {
    return Text(
      text,
      style: CustomTextStyles.montserratBold.copyWith(fontSize: 14,color: AppColours.primary),
    );
  }

  // ── Text input ─────────────────────────────────────────────────────────────
  Widget _textInput(
    TextEditingController controller,
    String hint, {
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      style: CustomTextStyles.openSansBold.copyWith(fontSize: 14),

      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.white38, fontSize: 13.fSize),
        filled: true,
        fillColor: const Color(0xFF1A1D21),
        contentPadding:
            EdgeInsets.symmetric(horizontal: 14.w, vertical: 14.h),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppColours.primary),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppColours.primary),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppColours.primary, width: 1.5),
        ),
      ),
    );
  }

  // ── Location row: Country | State | City ───────────────────────────────────
  Widget _buildLocationRow() {
    return Row(
      children: [
        Expanded(
          child: _buildCompactDropdown(
            value: _selectedCountry,
            hint: 'Country',
            items: _countries,
            onChanged: (v) => setState(() => _selectedCountry = v),
            iconPath: IconConstant.dropdown,
          ),
        ),
        SizedBox(width: 8.w),
        Expanded(
          child: _buildCompactDropdown(
            value: _selectedState,
            hint: 'State',
            items: _states,
            onChanged: (v) => setState(() => _selectedState = v),
            iconPath: IconConstant.dropdown,
          ),
        ),
        SizedBox(width: 8.w),
        Expanded(
          child: _buildCompactDropdown(
            value: _selectedCity,
            hint: 'City',
            items: _cities,
            onChanged: (v) => setState(() => _selectedCity = v),
            iconPath: IconConstant.dropdown,

          ),
        ),
      ],
    );
  }

  Widget _buildCompactDropdown({
    required String? value,
    required String hint,
    required List<String> items,
    required ValueChanged<String?> onChanged,
    required String iconPath
  }) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1D21),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColours.primary),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          hint: Text(
            hint,
            style: TextStyle(color: Colors.white38, fontSize: 11.fSize),
          ),
          dropdownColor: const Color(0xFF1A1D21),
          icon: SvgPicture.asset(iconPath),
          isExpanded: true,
          onChanged: onChanged,
          items: items
              .map(
                (e) => DropdownMenuItem(
                  value: e,
                  child: Text(
                    e,
                    style:
                        TextStyle(color: AppColours.secondary, fontSize: 11.fSize),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  // ── Date picker row ────────────────────────────────────────────────────────
  Widget _buildDatePicker() {
    return GestureDetector(
      onTap: _pickDate,
      child: Container(
        height: 50.h,
        padding: EdgeInsets.symmetric(horizontal: 14.w),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1D21),
          borderRadius: BorderRadius.circular(8),
          border:
              Border.all(color: AppColours.primary),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _selectedDate != null
                    ? _formatDate(_selectedDate!)
                    : 'Select Delivery Date',
                style: TextStyle(
                  color: _selectedDate != null
                      ? Colors.white
                      : Colors.white38,

                  fontSize: 13.fSize,
                ),
              ),
            ),
            Icon(Icons.calendar_today_outlined,
                color: AppColours.primary, size: 18),
          ],
        ),
      ),
    );
  }

  // ── Time picker (scroll wheel) ─────────────────────────────────────────────
  Widget _buildTimeDropdown() {
    return Column(
      children: [
        // Tap bar
        GestureDetector(
          onTap: () => setState(() => _showTimePicker = !_showTimePicker),
          child: Container(
            height: 50.h,
            padding: EdgeInsets.symmetric(horizontal: 14.w),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1D21),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColours.primary),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _selectedTime ?? 'Select Time',
                    style: TextStyle(
                      color: _selectedTime != null
                          ? Colors.white
                          : Colors.white38,
                      fontSize: 13.fSize,
                    ),
                  ),
                ),
                SvgPicture.asset(
                  (_showTimePicker
                      ? IconConstant.dropDown1
                      : IconConstant.dropdown),
                  color: AppColours.primary,
                ),
              ],
            ),
          ),
        ),
        // Expandable scroll-wheel picker
        if (_showTimePicker) ...[  
          SizedBox(height: 8.h),
          Container(
            padding: EdgeInsets.symmetric(vertical: 12.h, horizontal: 12.w),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1D21),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColours.primary.withOpacity(0.4)),
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
                      // Hour wheel
                      _buildWheel(
                        controller: _hourController,
                        itemCount: 12,
                        labelBuilder: (i) => '${i + 1}',
                        selectedIndex: _selectedHour - 1,
                        onChanged: (i) => setState(() => _selectedHour = i + 1),
                        width: 52,
                      ),
                      // Minute wheel
                      _buildWheel(
                        controller: _minuteController,
                        itemCount: 60,
                        labelBuilder: (i) => i.toString().padLeft(2, '0'),
                        selectedIndex: _selectedMinute,
                        onChanged: (i) => setState(() => _selectedMinute = i),
                        width: 52,
                      ),
                      // AM/PM wheel
                      _buildWheel(
                        controller: _periodController,
                        itemCount: 2,
                        labelBuilder: (i) => i == 0 ? 'PM' : 'AM',
                        selectedIndex: _isAM ? 1 : 0,
                        onChanged: (i) => setState(() => _isAM = i == 1),
                        width: 56,
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 8.h),
                // Save button inside picker
                GestureDetector(
                  onTap: () {
                    final period = _isAM ? 'AM' : 'PM';
                    final time =
                        '${_selectedHour.toString().padLeft(2, '0')}:${_selectedMinute.toString().padLeft(2, '0')} $period';
                    setState(() {
                      _selectedTime = time;
                      _showTimePicker = false;
                    });
                  },
                  child: Container(
                    padding: EdgeInsets.symmetric(
                        horizontal: 32.w, vertical: 10.h),
                    decoration: BoxDecoration(
                      color: AppColours.primary,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: AppColours.primary.withOpacity(0.5)),
                    ),
                    child: Text(
                      'Save',
                      style: TextStyle(
                        color: AppColours.black,
                        fontSize: 13.fSize,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
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
                  fontWeight:
                      isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // ── Save & Continue button ─────────────────────────────────────────────────
  Widget _buildSaveButton() {
    return Container(
      width: double.maxFinite,
      padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 28.h),
      child: Container(
        height: 44.h,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          gradient: LinearGradient(
            colors: [
              AppColours.primary.withOpacity(0.85),
              AppColours.primary,
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: AppColours.primary.withOpacity(0.3),
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
                borderRadius: BorderRadius.circular(10)),
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
    );
  }
}
