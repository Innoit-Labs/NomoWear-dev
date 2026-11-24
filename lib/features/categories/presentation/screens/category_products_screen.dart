import 'package:flutter/material.dart';
import 'package:nomowear/core/app_export.dart';
import 'package:nomowear/core/network/api_exception.dart';
import 'package:nomowear/core/widgets/product_image.dart';
import 'package:nomowear/features/products/data/models/product.dart';
import 'package:nomowear/features/products/data/product_repository.dart';
import 'package:nomowear/features/profile/domain/saved_address.dart';

/// Browse-only product grid for a categories-screen tile.
/// No add-to-cart or favorites — just products for the selected garment.
class CategoryProductsScreen extends StatefulWidget {
  const CategoryProductsScreen({
    super.key,
    required this.title,
    required this.section,
    required this.garment,
    this.gender,
    this.tab,
  });

  final String title;
  final String section;
  final String garment;
  final String? gender;
  final String? tab;

  @override
  State<CategoryProductsScreen> createState() => _CategoryProductsScreenState();
}

class _CategoryProductsScreenState extends State<CategoryProductsScreen> {
  final ProductRepository _productRepository = ProductRepository();

  bool _isLoading = true;
  String? _errorMessage;
  List<Product> _products = const [];

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Men/Women nearby needs saved-address coords when kit session is empty.
      final isKidsOrEssentials = widget.tab != null &&
          (widget.tab!.toLowerCase().contains('kids') ||
              widget.tab!.toLowerCase().contains('essentials'));
      if (!isKidsOrEssentials) {
        await loadSavedAddressesFromProfile();
      }

      final products = await _productRepository.getProducts(
        forceRefresh: true,
        useNearbyLocation: true,
        garment: widget.garment,
        gender: widget.gender,
        tab: widget.tab,
        page: 1,
        limit: 50,
      );
      final visible = products
          .where((p) => !p.isWardrobeKit)
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _products = visible;
        _isLoading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.message;
        _isLoading = false;
        _products = const [];
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Unable to load products. Please try again.';
        _isLoading = false;
        _products = const [];
      });
    }
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
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.title,
          style: CustomTextStyles.openSansSemiBold.copyWith(
            color: AppColours.primary,
            fontSize: 16,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: Container(
            height: 2,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
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
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColours.primary),
      );
    }

    if (_errorMessage != null) {
      return RefreshIndicator(
        color: AppColours.primary,
        backgroundColor: const Color(0xFF16181D),
        onRefresh: _loadProducts,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(height: MediaQuery.sizeOf(context).height * 0.28),
            _buildEmptyMessage(
              icon: Icons.cloud_off_outlined,
              title: 'Unable to load products',
              subtitle: _errorMessage!,
              showRetry: true,
            ),
          ],
        ),
      );
    }

    if (_products.isEmpty) {
      return RefreshIndicator(
        color: AppColours.primary,
        backgroundColor: const Color(0xFF16181D),
        onRefresh: _loadProducts,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(height: MediaQuery.sizeOf(context).height * 0.28),
            _buildEmptyMessage(
              icon: Icons.inventory_2_outlined,
              title: 'No products available',
              subtitle:
                  'Nothing to show in ${widget.title} right now.\nPull down to refresh.',
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: AppColours.primary,
      backgroundColor: const Color(0xFF16181D),
      onRefresh: _loadProducts,
      child: GridView.builder(
        padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 24.h),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 16.h,
          crossAxisSpacing: 12.w,
          childAspectRatio: 0.68,
        ),
        itemCount: _products.length,
        itemBuilder: (context, index) => _buildProductCard(_products[index]),
      ),
    );
  }

  Widget _buildEmptyMessage({
    required IconData icon,
    required String title,
    required String subtitle,
    bool showRetry = false,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 28.w),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: AppColours.primary.withOpacity(0.45),
            size: 64,
          ),
          SizedBox(height: 16.h),
          Text(
            title,
            textAlign: TextAlign.center,
            style: CustomTextStyles.openSansSemiBold.copyWith(
              color: Colors.white70,
              fontSize: 16,
            ),
          ),
          SizedBox(height: 8.h),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: CustomTextStyles.openSansRegular.copyWith(
              color: Colors.white38,
              fontSize: 13,
            ),
          ),
          if (showRetry) ...[
            SizedBox(height: 18.h),
            TextButton(
              onPressed: _loadProducts,
              style: TextButton.styleFrom(foregroundColor: AppColours.primary),
              child: const Text('Retry'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildProductCard(Product product) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF16181D),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColours.primary.withOpacity(0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
              child: ProductImage(
                imageUrl: product.displayImageUrl,
                width: double.infinity,
                height: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(10.w, 10.h, 10.w, 12.h),
            child: Text(
              product.productName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: CustomTextStyles.openSansSemiBold.copyWith(
                color: Colors.white,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
