import 'package:nomowear/core/app_export.dart';
import 'package:nomowear/core/utils/kids_size_utils.dart';
import 'package:nomowear/features/products/data/models/product.dart';
import 'package:nomowear/features/products/data/models/product_variant.dart';
import 'package:nomowear/features/products/data/product_catalog.dart';
import 'package:nomowear/features/products/data/product_mapper.dart';

class VariantSelectionSheet extends StatefulWidget {
  final Product product;
  final ProductVariant? initialVariant;

  const VariantSelectionSheet({
    Key? key,
    required this.product,
    this.initialVariant,
  }) : super(key: key);

  static Future<ProductVariant?> show(
    BuildContext context, 
    Product product, {
    ProductVariant? initialVariant,
  }) {
    return showModalBottomSheet<ProductVariant>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0F1012),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: VariantSelectionSheet(
            product: product,
            initialVariant: initialVariant,
          ),
        ),
      ),
    );
  }

  @override
  State<VariantSelectionSheet> createState() => _VariantSelectionSheetState();
}

class _VariantSelectionSheetState extends State<VariantSelectionSheet> {
  final List<String> _availableColors = [];
  final List<String> _allSizes = [];
  String? _selectedColor;
  String? _selectedSize;

  @override
  void initState() {
    super.initState();
    _extractOptions();
    if (widget.initialVariant != null) {
      _selectedColor = ProductMapper.optionValue(widget.initialVariant!, 'Color');
      _selectedSize = ProductMapper.optionValue(widget.initialVariant!, 'Size');
    }
    if ((_selectedColor == null || _selectedColor!.isEmpty) && _availableColors.isNotEmpty) {
      _selectedColor = _availableColors.first;
    }
    final currentSizes = _getSizesForColor(_selectedColor);
    if ((_selectedSize == null || _selectedSize!.isEmpty) && currentSizes.isNotEmpty) {
      _selectedSize = currentSizes.first;
    } else if ((_selectedSize == null || _selectedSize!.isEmpty) && _allSizes.isNotEmpty) {
      _selectedSize = _allSizes.first;
    }
  }

  void _extractOptions() {
    final Set<String> colorSet = {};
    final Set<String> sizeSet = {};

    for (final variant in widget.product.variants) {
      final color = ProductMapper.optionValue(variant, 'Color');
      if (color != null && color.isNotEmpty) {
        colorSet.add(color);
      }
      final size = ProductMapper.optionValue(variant, 'Size');
      if (size != null && size.isNotEmpty) {
        sizeSet.add(size);
      }
    }

    // Fallback to product attributes if variants don't specify size/color
    if (sizeSet.isEmpty) {
      for (final entry in widget.product.attributes.entries) {
        final k = entry.key.toLowerCase();
        if (k == 'size' || k == 'sizes' || k == 'age' || k == 'ages') {
          for (final s in entry.value.split(RegExp(r'[/,]'))) {
            final trimmed = s.trim();
            if (trimmed.isNotEmpty) sizeSet.add(trimmed);
          }
        }
      }
    }
    if (colorSet.isEmpty) {
      for (final entry in widget.product.attributes.entries) {
        final k = entry.key.toLowerCase();
        if (k == 'color' || k == 'colors' || k == 'colour' || k == 'colours') {
          for (final c in entry.value.split(RegExp(r'[/,]'))) {
            final trimmed = c.trim();
            if (trimmed.isNotEmpty) colorSet.add(trimmed);
          }
        }
      }
    }

    _availableColors.addAll(colorSet);
    _allSizes.addAll(_sortSizes(sizeSet.toList()));
  }

  List<String> _getSizesForColor(String? color) {
    if (color == null || color.isEmpty || _availableColors.isEmpty) {
      return _allSizes;
    }
    final Set<String> sizeSet = {};
    for (final variant in widget.product.variants) {
      final vColor = ProductMapper.optionValue(variant, 'Color');
      if (vColor != null && vColor.toLowerCase() == color.toLowerCase()) {
        final size = ProductMapper.optionValue(variant, 'Size');
        if (size != null && size.isNotEmpty) {
          sizeSet.add(size);
        }
      }
    }
    if (sizeSet.isEmpty) {
      return _allSizes;
    }
    return _sortSizes(sizeSet.toList());
  }

  List<String> _sortSizes(List<String> sizes) {
    if (ProductCatalog.isKidsProduct(widget.product)) {
      final result = List<String>.from(sizes);
      result.sort(compareKidsSizes);
      return result;
    }
    final ordered = ['XS', 'S', 'M', 'L', 'XL', 'XXL', 'XXXL'];
    final result = List<String>.from(sizes);
    result.sort((a, b) {
      final iA = ordered.indexOf(a.toUpperCase());
      final iB = ordered.indexOf(b.toUpperCase());
      if (iA != -1 && iB != -1) return iA.compareTo(iB);
      if (iA != -1) return -1;
      if (iB != -1) return 1;
      return a.compareTo(b);
    });
    return result;
  }

  ProductVariant? _resolveVariant() {
    if (widget.product.variants.isEmpty) return null;
    if (widget.product.variants.length == 1) return widget.product.variants.first;

    // 1. If both color and size are selected:
    if (_selectedColor != null && _selectedSize != null) {
      final exact = ProductMapper.matchingVariant(
        variants: widget.product.variants,
        selectedColor: _selectedColor,
        selectedSize: _selectedSize!,
      );
      if (exact != null) return exact;
    }

    // 2. If only size is selected:
    if (_selectedSize != null) {
      for (final v in widget.product.variants) {
        final s = ProductMapper.optionValue(v, 'Size');
        if (s != null &&
            (s.toUpperCase() == _selectedSize!.toUpperCase() ||
                areKidsSizesEquivalent(s, _selectedSize))) {
          return v;
        }
      }
    }

    // 3. If only color is selected:
    if (_selectedColor != null) {
      for (final v in widget.product.variants) {
        final c = ProductMapper.optionValue(v, 'Color');
        if (c != null && c.toUpperCase() == _selectedColor!.toUpperCase()) {
          return v;
        }
      }
    }

    return widget.product.variants.first;
  }

  @override
  Widget build(BuildContext context) {
    final sizes = _getSizesForColor(_selectedColor);
    if (_selectedSize != null && !sizes.contains(_selectedSize)) {
      _selectedSize = sizes.isNotEmpty ? sizes.first : null;
    }
    if (_selectedSize == null && sizes.isNotEmpty) {
      _selectedSize = sizes.first;
    }
    
    final isKids = ProductCatalog.isKidsProduct(widget.product);
    final variant = _resolveVariant();
    final isOutOfStock = variant != null &&
        variant.stockStatus.toUpperCase() == 'OUT_OF_STOCK' &&
        variant.stockOnHand <= 0;
    final canSubmit = (variant != null && !isOutOfStock) ||
        (widget.product.variants.isEmpty && (sizes.isNotEmpty || _availableColors.isNotEmpty));

    final displaySelectedSize =
        isKids ? formatKidsSize(_selectedSize) : _selectedSize;

    final summaryParts = <String>[
      if (displaySelectedSize != null && displaySelectedSize.isNotEmpty)
        'Size: $displaySelectedSize',
      if (_selectedColor != null && _selectedColor!.isNotEmpty) 'Color: $_selectedColor',
    ];

    return Padding(
      padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 16.h),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40.w,
              height: 4.h,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          SizedBox(height: 16.h),
          Text(
            'SELECT SIZE & VARIANT',
            textAlign: TextAlign.center,
            style: CustomTextStyles.montserratBold.copyWith(
              fontSize: 14,
              color: AppColours.primary,
              letterSpacing: 0.8,
            ),
          ),
          SizedBox(height: 4.h),
          Text(
            widget.product.productName,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white70,
              fontSize: 12.fSize,
            ),
          ),
          SizedBox(height: 24.h),

          // Size Selection (shown whenever sizes exist)
          if (sizes.isNotEmpty) ...[
            Text(
              'SIZE${displaySelectedSize != null ? ': $displaySelectedSize' : ''}',
              style: CustomTextStyles.montserratBold.copyWith(
                fontSize: 12,
                color: Colors.white54,
                letterSpacing: 1.2,
              ),
            ),
            SizedBox(height: 12.h),
            Wrap(
              spacing: 10.w,
              runSpacing: 10.h,
              children: sizes.map((s) => _buildChoiceChip(
                text: isKids ? formatKidsSize(s) : s,
                isSelected: s == _selectedSize ||
                    (isKids && areKidsSizesEquivalent(s, _selectedSize)),
                onTap: () {
                  setState(() => _selectedSize = s);
                },
              )).toList(),
            ),
            SizedBox(height: 24.h),
          ],

          // Color Selection (shown whenever colors exist)
          if (_availableColors.isNotEmpty) ...[
            Text(
              'COLOR${_selectedColor != null ? ': $_selectedColor' : ''}',
              style: CustomTextStyles.montserratBold.copyWith(
                fontSize: 12,
                color: Colors.white54,
                letterSpacing: 1.2,
              ),
            ),
            SizedBox(height: 12.h),
            Wrap(
              spacing: 10.w,
              runSpacing: 10.h,
              children: _availableColors.map((c) => _buildChoiceChip(
                text: c,
                isSelected: c == _selectedColor,
                onTap: () {
                  setState(() {
                    _selectedColor = c;
                    final nextSizes = _getSizesForColor(c);
                    if (_selectedSize != null && !nextSizes.contains(_selectedSize)) {
                      _selectedSize = nextSizes.isNotEmpty ? nextSizes.first : null;
                    }
                  });
                },
              )).toList(),
            ),
            SizedBox(height: 32.h),
          ],

          // Summary
          if (variant != null || summaryParts.isNotEmpty) ...[
            Container(
              padding: EdgeInsets.all(16.w),
              decoration: BoxDecoration(
                color: const Color(0xFF16181D),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColours.primary.withOpacity(0.2)),
              ),
              child: Row(
                mainAxisAlignment:
                    ProductCatalog.shouldShowPrice(product: widget.product)
                        ? MainAxisAlignment.spaceBetween
                        : MainAxisAlignment.center,
                children: [
                  if (ProductCatalog.shouldShowPrice(product: widget.product))
                    Text(
                      variant != null
                          ? ProductMapper.resolveVariantPrice(variant).discountedPrice
                          : ProductMapper.resolveProductPrice(widget.product).discountedPrice,
                      style: CustomTextStyles.montserratBold.copyWith(
                        fontSize: 16,
                        color: AppColours.primary,
                      ),
                    ),
                  Text(
                    summaryParts.isNotEmpty ? summaryParts.join(' / ') : 'Standard',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 13.fSize,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 24.h),
          ],

          // Action Buttons
          SizedBox(
            height: 48.h,
            child: ElevatedButton(
              onPressed: canSubmit ? () {
                final resolved = variant ?? (widget.product.variants.isNotEmpty ? widget.product.variants.first : null);
                debugPrint('===== ADD TO CART VARIANT SELECTION =====');
                debugPrint('PRODUCT ID = ${widget.product.id}');
                debugPrint('SELECTED COLOR = $_selectedColor');
                debugPrint('SELECTED SIZE = $_selectedSize');
                debugPrint('SELECTED VARIANT ID = ${resolved?.id}');
                debugPrint('SELECTED VARIANT NAME = ${resolved?.variantName}');
                debugPrint('SELECTED STOCK = ${resolved?.stockOnHand}');
                debugPrint('==========================================');
                Navigator.pop(context, resolved);
              } : null,
              style: ElevatedButton.styleFrom(
                elevation: 0,
                backgroundColor: AppColours.primary,
                disabledBackgroundColor: AppColours.primary.withOpacity(0.2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                'ADD TO CART',
                style: CustomTextStyles.montserratBold.copyWith(
                  fontSize: 13,
                  color: canSubmit ? Colors.black : Colors.white24,
                  letterSpacing: 1,
                ),
              ),
            ),
          ),
          SizedBox(height: 12.h),
          SizedBox(
            height: 48.h,
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              style: TextButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: AppColours.primary.withOpacity(0.4)),
                ),
              ),
              child: Text(
                'DONE',
                style: CustomTextStyles.montserratBold.copyWith(
                  fontSize: 13,
                  color: AppColours.primary,
                  letterSpacing: 1,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChoiceChip({
    required String text,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 12.h),
        decoration: BoxDecoration(
          color: isSelected ? AppColours.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? AppColours.primary : Colors.white24,
          ),
        ),
        child: Text(
          text,
          style: CustomTextStyles.montserratSemiBold.copyWith(
            fontSize: 13,
            color: isSelected ? Colors.black : Colors.white70,
          ),
        ),
      ),
    );
  }
}
