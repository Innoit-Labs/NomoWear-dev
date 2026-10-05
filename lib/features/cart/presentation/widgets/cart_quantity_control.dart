import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nomowear/core/app_export.dart';
import 'package:nomowear/features/cart/presentation/bloc/cart_bloc.dart';
import 'package:nomowear/features/cart/presentation/utils/cart_limits.dart';
import 'package:nomowear/features/products/data/product_cache.dart';
import 'package:nomowear/features/products/data/models/product_variant.dart';
import 'package:nomowear/features/cart/presentation/widgets/wardrobe_limit_dialog.dart';

class CartQuantityControl extends StatelessWidget {
  final CartItem item;
  final CartState state;
  final int essentialsMaxQty;
  final ProductVariant? variant;

  const CartQuantityControl({
    Key? key,
    required this.item,
    required this.state,
    this.essentialsMaxQty = 5,
    this.variant,
  }) : super(key: key);

  ProductVariant? _resolveVariant() {
    if (variant != null) return variant;
    if (item.variantId == null) return null;
    final product = ProductCache.instance.findById(item.productId);
    if (product == null) return null;
    for (final v in product.variants) {
      if (v.id == item.variantId) return v;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final resolvedVariant = _resolveVariant();
    final maxLimit = item.isEssential
        ? essentialsMaxQty
        : CartLimits.effectiveMaxWardrobeGarments(state);
    int maxQty = maxLimit;
    if (resolvedVariant != null && resolvedVariant.stockOnHand > 0) {
      maxQty = resolvedVariant.stockOnHand < maxLimit
          ? resolvedVariant.stockOnHand
          : maxLimit;
    }
    final upper = maxQty < 1 ? 1 : maxQty;
    final displayQty = item.quantity > upper ? upper : item.quantity;

    final isPending = state.isLinePending(item.id);
    final canDecrease = displayQty >= 1;
    final canIncrease = displayQty < upper;

    return Container(
      height: 28.h,
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColours.primary.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildQtyButton(
            icon: Icons.remove,
            isActive: canDecrease,
            onTap: () {
              if (canDecrease) {
                if (displayQty > 1) {
                  context.read<CartBloc>().add(
                        UpdateCartItemQuantityEvent(item.id, displayQty - 1),
                      );
                } else {
                  context.read<CartBloc>().add(
                        RemoveFromCartEvent(item.id),
                      );
                }
              }
            },
          ),
          Expanded(
            child: Center(
              child: isPending
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$displayQty',
                          style: CustomTextStyles.montserratSemiBold.copyWith(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                        SizedBox(width: 4.w),
                        SizedBox(
                          width: 10,
                          height: 10,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: AppColours.primary,
                          ),
                        ),
                      ],
                    )
                  : Text(
                      '$displayQty',
                      textAlign: TextAlign.center,
                      style: CustomTextStyles.montserratSemiBold.copyWith(
                        color: Colors.white,
                        fontSize: 12,
                      ),
                    ),
            ),
          ),
          _buildQtyButton(
            icon: Icons.add,
            isActive: canIncrease,
            onTap: () {
              if (canIncrease) {
                if (!item.isEssential && !item.isKids) {
                  if (!checkWardrobeGarmentLimit(context, state, item, delta: 1)) {
                    return;
                  }
                }
                context.read<CartBloc>().add(
                      UpdateCartItemQuantityEvent(item.id, displayQty + 1),
                    );
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildQtyButton({
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: isActive ? onTap : null,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 32.w,
        alignment: Alignment.center,
        child: Icon(
          icon,
          size: 16,
          color: isActive ? AppColours.primary : Colors.grey,
        ),
      ),
    );
  }
}
