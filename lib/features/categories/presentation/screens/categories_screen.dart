import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:nomowear/core/app_export.dart';

class CategoriesScreen extends StatelessWidget {
  final bool isTab;
  const CategoriesScreen({Key? key, this.isTab = false}) : super(key: key);

  static String garmentForTitle(String title) {
    switch (title.trim().toLowerCase()) {
      case 't-shirts':
        return 't-shirt';
      case 'shirts':
        return 'shirt';
      case 'kurtas':
        return 'kurta';
      case 'jeans':
        return 'jeans';
      case 'trousers':
        return 'trousers';
      case 'sarees':
        return 'saree';
      case 'kurtis':
        return 'kurti';
      case 'girls':
        return 'girls';
      case 'boys':
        return 'boys';
      case 'socks':
        return 'socks';
      case 'innerwear':
        return 'innerwear';
      case 'kerchiefs':
        return 'kerchief';
      case 'boxers':
        return 'boxers';
      default:
        return title.trim().toLowerCase();
    }
  }

  static String? genderForSection(String section, String title) {
    switch (section.trim().toLowerCase()) {
      case 'men':
        return 'men';
      case 'women':
        return 'women';
      case 'kids':
        final t = title.trim().toLowerCase();
        if (t == 'girls') return 'girl';
        if (t == 'boys') return 'boy';
        return null;
      default:
        return null;
    }
  }

  static String? tabForSection(String section) {
    switch (section.trim().toLowerCase()) {
      case 'kids':
        return 'Kids Wardrobe';
      case 'essentials':
        return 'Essentials Wardrobe';
      default:
        return null;
    }
  }

  void _openCategory(
    BuildContext context, {
    required String section,
    required String title,
  }) {
    Navigator.pushNamed(
      context,
      AppRoutes.categoryProductsScreen,
      arguments: {
        'title': title,
        'section': section,
        'garment': garmentForTitle(title),
        'gender': genderForSection(section, title),
        'tab': tabForSection(section),
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1012),

      // ✅ AppBar ALWAYS visible
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F1012),
        elevation: 0,
        centerTitle: true,

        // 🔥 Back button only if NOT tab
        leading: isTab
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),

        title: Text(
          "Categories",
          style: CustomTextStyles.openSansSemiBold.copyWith(color: AppColours.primary,fontSize: 16),
        ),

        // 🔥 Custom Gradient Divider
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: Container(
            height: 2,
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

      body: SafeArea(child: _buildMainContent(context)),
    );
  }

  // ================= MAIN CONTENT =================
  Widget _buildMainContent(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 28.h),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSection(context, "Men", [
                  _item(context, "Men", "T-Shirts", IconConstant.iconTShirts),
                  _item(context, "Men", "Shirts", IconConstant.iconShirts),
                  _item(context, "Men", "Kurtas", IconConstant.iconKurtas),
                  _item(context, "Men", "Jeans", IconConstant.iconJeans),
                  _item(context, "Men", "Trousers", IconConstant.iconTrousers),
                ]),

                _buildSection(context, "Women", [
                  _item(context, "Women", "T-Shirts", IconConstant.iconWTShirts),
                  _item(context, "Women", "Shirts", IconConstant.iconWShirts),
                  _item(context, "Women", "Sarees", IconConstant.iconSarees),
                  _item(context, "Women", "Kurtis", IconConstant.iconWKurtis),
                  _item(context, "Women", "Jeans", IconConstant.iconWJeans),
                ]),

                _buildSection(context, "Kids", [
                  _item(context, "Kids", "Girls", IconConstant.iconKGirls),
                  _item(context, "Kids", "Boys", IconConstant.iconKBoys),
                ]),

                _buildSection(context, "Essentials", [
                  _item(context, "Essentials", "Socks", IconConstant.iconSocks),
                  _item(context, "Essentials", "Innerwear", IconConstant.iconInnerwear),
                  _item(context, "Essentials", "Kerchiefs", IconConstant.iconKerchiefs),
                  _item(context, "Essentials", "Boxers", IconConstant.iconBoxers),
                ]),
              ],
            ),
          ),
        ),

        // ✅ Bottom nav only when NOT tab
        if (!isTab) _buildBottomNav(context),
      ],
    );
  }

  // ================= SECTION =================
  Widget _buildSection(BuildContext context, String title, List<Widget> items) {
    return Padding(
      padding: EdgeInsets.only(bottom: 20.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // 🔥 Title + Gradient Line (Same Row)
          Row(
            children: [
              Text(
                title,
                style: CustomTextStyles.openSansBold.copyWith(fontSize: 16,color: AppColours.primary),
              ),

              SizedBox(width: 10.w),

              // 🔥 Expanded Gradient Line
              Expanded(
                child: Container(
                  height: 2,
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
            ],
          ),

          SizedBox(height: 18.h),

          // 🔥 Grid
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1,
            children: items,
          ),
        ],
      ),
    );
  }
  // ================= ITEM =================
  Widget _item(
    BuildContext context,
    String section,
    String title,
    String iconPath,
  ) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _openCategory(context, section: section, title: title),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColours.primary, width: 1.5),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SvgPicture.asset(
              iconPath,
              height: 28,
              width: 28,
            ),
            SizedBox(height: 8.h),
            Text(
              title,
              style: CustomTextStyles.openSansBold.copyWith(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  // ================= BOTTOM NAV =================
  Widget _buildBottomNav(BuildContext context) {
    return Container(
      height: 80.h,
      decoration: BoxDecoration(
        color: const Color(0xFF16181D),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildNavItem(
            context,
            Icons.home_filled,
            "Home",
            false,
            AppRoutes.homeScreen,
          ),
          _buildNavItem(
            context,
            Icons.grid_view,
            "Categories",
            true,
            AppRoutes.categoriesScreen,
          ),
          _buildNavItem(
            context,
            Icons.shopping_cart_outlined,
            "Cart",
            false,
            "",
          ),
          _buildNavItem(
            context,
            Icons.stars_outlined,
            "Subscription",
            false,
            "",
          ),
          _buildNavItem(context, Icons.person_outline, "Profile", false, ""),
        ],
      ),
    );
  }

  Widget _buildNavItem(
    BuildContext context,
    IconData icon,
    String label,
    bool isActive,
    String route,
  ) {
    return GestureDetector(
      onTap: () {
        if (!isActive && route.isNotEmpty) {
          Navigator.pushReplacementNamed(context, route);
        }
      },
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            color: isActive ? AppColours.primary : Colors.grey,
            size: 24,
          ),
          SizedBox(height: 4.h),
          Text(
            label,
            style: TextStyle(
              color: isActive ? AppColours.primary : Colors.grey,
              fontSize: 10.fSize,
            ),
          ),
        ],
      ),
    );
  }
}
