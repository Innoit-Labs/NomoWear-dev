import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:nomowear/core/app_export.dart';
import 'package:nomowear/core/utils/kids_size_utils.dart';
import 'package:nomowear/features/cart/presentation/bloc/cart_bloc.dart';

import 'package:nomowear/features/cart/presentation/widgets/cart_quantity_control.dart';
import 'package:nomowear/features/products/data/models/product_variant.dart';
import 'package:nomowear/features/products/data/product_cache.dart';
import 'package:nomowear/features/products/data/product_catalog.dart';
import 'package:nomowear/features/products/data/product_mapper.dart';
import 'package:nomowear/features/products/data/product_repository.dart';
import 'package:nomowear/features/wardrobe/presentation/screens/product_details_screen.dart';
import 'package:nomowear/features/wardrobe/presentation/widgets/variant_selection_sheet.dart';
import 'package:nomowear/features/checkout/presentation/utils/checkout_pricing.dart';
import 'package:nomowear/features/products/data/models/product.dart';

import 'package:nomowear/features/wardrobe/presentation/screens/wardrobe_screen.dart';

import '../../../products/data/product_catalog.dart';

class ReusableProductCartItem extends StatefulWidget {
  final CartItem item;
  final CartState state;
  final bool showPrice;

  const ReusableProductCartItem({
    Key? key,
    required this.item,
    required this.state,
    this.showPrice = true,
  }) : super(key: key);

  @override
  State<ReusableProductCartItem> createState() => _ReusableProductCartItemState();
}

class _ReusableProductCartItemState extends State<ReusableProductCartItem> {
  Product? _product;
  bool _fetchAttempted = false;

  @override
  void initState() {
    super.initState();
    _resolveProduct();
  }

  @override
  void didUpdateWidget(covariant ReusableProductCartItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.productId != widget.item.productId ||
        oldWidget.item.variantId != widget.item.variantId) {
      _fetchAttempted = false;
      _resolveProduct();
    }
  }

  void _resolveProduct() {
    final cached = ProductCache.instance.findById(widget.item.productId);
    if (cached != null) {
      _product = cached;
      return;
    }
    if (_fetchAttempted) return;
    _fetchAttempted = true;
    _fetchProduct();
  }

  Future<void> _fetchProduct() async {
    try {
      final product = await ProductRepository().getProductById(widget.item.productId);
      if (mounted) {
        setState(() {
          _product = product;
        });
      }
    } catch (_) {
      // Product fetch failed — variant selection will be unavailable
    }
  }

  WardrobeItem _productFromCartItem(CartItem item) {
    final productId = item.productId;

    return WardrobeItem(
      productId: productId.isNotEmpty ? productId : null,
      title: item.title,
      description: '',
      imageUrl: item.imageUrl,
      price: item.price,
      category: item.category,
    );
  }

  void _openProductDetails(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProductDetailsScreen(product: _productFromCartItem(widget.item)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final state = widget.state;
    final product = _product ?? ProductCache.instance.findById(item.productId);
    ProductVariant? variant;
    String? currentColor;
    if (product != null && item.variantId != null) {
      variant = product.variants.where((v) => v.id == item.variantId).firstOrNull;
      if (variant != null) {
        currentColor = ProductMapper.optionValue(variant, 'Color');
      }
    }

    final priceLabel = widget.showPrice 
        ? CheckoutPricing.formatMoney(
            CheckoutPricing.parseItemPrice(
              item.price,
              isEssential: item.isEssential,
            ) * item.quantity,
          )
        : null;

    return Container(
      key: ValueKey(item.id),
      margin: EdgeInsets.only(bottom: 10.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => _openProductDetails(context),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: ProductImage(
                imageUrl: item.imageUrl,
                width: 44.w,
                height: 52.h,
                fit: BoxFit.cover,
              ),
            ),
          ),
          SizedBox(width: 10.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () => _openProductDetails(context),
                  behavior: HitTestBehavior.opaque,
                  child: Text(
                    item.title,
                    style: CustomTextStyles.montserratSemiBold.copyWith(fontSize: 14, color: AppColours.primary),
                  ),
                ),
                if (priceLabel != null) ...[
                  SizedBox(height: 2.h),
                  Text(
                    priceLabel,
                    style: CustomTextStyles.montserratSemiBold.copyWith(fontSize: 12, color: AppColours.primary),
                  ),
                ],
                SizedBox(height: 4.h),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () async {
                          // Re-check cache in case product was fetched by now
                          final resolvedProduct = _product ?? ProductCache.instance.findById(item.productId);
                          if (resolvedProduct != null) {
                            final currentVariant = item.variantId != null
                                ? resolvedProduct.variants.where((v) => v.id == item.variantId).firstOrNull
                                : null;
                            final newVariant = await VariantSelectionSheet.show(
                              context, 
                              resolvedProduct, 
                              initialVariant: currentVariant,
                            );
                            if (newVariant != null && context.mounted) {
                              context.read<CartBloc>().add(UpdateCartItemVariantEvent(item.id, newVariant));
                            }
                          }
                        },
                        behavior: HitTestBehavior.opaque,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Builder(
                                builder: (_) {
                                  final isKids = widget.item.isKids ||
                                      (widget.item.category?.toLowerCase().contains('kids') ?? false) ||
                                      (_product != null && ProductCatalog.isKidsProduct(_product!)) ||
                                      isKidsAgeSize(widget.item.selectedSize);
                                  final displaySize = isKids
                                      ? formatKidsSize(widget.item.selectedSize)
                                      : widget.item.selectedSize;

                                  return Text(
                                    currentColor != null
                                        ? 'Size: $displaySize / Color: $currentColor'
                                        : 'Size: $displaySize',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12.fSize,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  );
                                },
                              ),
                            ),
                            SizedBox(width: 4.w),
                            Icon(Icons.keyboard_arrow_down, color: Colors.white70, size: 16),
                          ],
                        ),
                      ),
                    ),

                    SizedBox(width: 10.w),
                    SizedBox(
                      width: 100.w,
                      child: CartQuantityControl(
                        state: state,
                        item: item,
                        variant: variant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => context
                .read<CartBloc>()
                .add(RemoveFromCartEvent(item.id)),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: EdgeInsets.only(top: 4.h, left: 6.w, right: 2.w, bottom: 6.h),
              child: SvgPicture.asset(IconConstant.delete1),
            ),
          ),
        ],
      ),
    );
  }
}
