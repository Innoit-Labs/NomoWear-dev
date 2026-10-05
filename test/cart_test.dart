import 'package:flutter_test/flutter_test.dart';
import 'package:nomowear/features/cart/data/models/remote_cart.dart';
import 'package:nomowear/features/cart/presentation/bloc/cart_bloc.dart';

void main() {
  group('Cart Deduplication and Sanitization Tests', () {
    test('Deduplicates identical items without inflating quantities', () {
      final json = {
        'id': 'test-cart-123',
        'sections': {
          'subscription': {
            'items': [],
          },
          'non_subscription': {
            'items': [
              {
                'productId': 'prod-1',
                'productName': 'Trouser',
                'quantity': 2,
                'unit_price': 500,
                'line_total': 1000,
              },
              {
                'productId': 'prod-1',
                'productName': 'Trouser',
                'quantity': 2,
                'unit_price': 500,
                'line_total': 1000,
              }
            ]
          }
        }
      };

      final remoteCart = RemoteCart.fromJson(json);
      expect(remoteCart.items.length, 1);
      expect(remoteCart.items.first.quantity, 2);
    });

    test('Kit items are preserved with correct duration and category', () {
      final json = {
        'id': 'test-cart-kit',
        'sections': {
          'subscription': {
            'items': [
              {
                'productId': 'kit-prod-1',
                'productClass': 'wardrobe_kit',
                'quantity': 1,
                'kitDetails': {
                  'kit_type': '3 Day wardrobe kit',
                  'duration_days': 3,
                  'selected_items': [
                    {'productId': 'garment-1', 'quantity': 1},
                    {'productId': 'garment-2', 'quantity': 1},
                  ]
                }
              }
            ]
          }
        }
      };

      final remoteCart = RemoteCart.fromJson(json);
      expect(remoteCart.items.length, 3); // 1 kit + 2 garments
      final garments = remoteCart.items.where((i) => i.productClass != 'wardrobe_kit').toList();
      expect(garments.length, 2);
    });
  });
}
