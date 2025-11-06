// FILE: lib/widgets/product_card.dart
import 'package:flutter/material.dart';
import '../models/product.dart';

class ProductCard extends StatelessWidget {
  const ProductCard({
    super.key,
    required this.product,
    this.onTap,
  });

  final Product product;
  final VoidCallback? onTap;

  // 안전하게 가격 문자열 만들기
  String _formatPricePerDay(Product p) {
    // 가장 흔한 필드 이름들에 대한 폴백 체인
    try {
      // 1) dailyPrice(double?)
      final v = (p as dynamic).dailyPrice;
      if (v is num) return '${v.toInt()}원/일';
      if (v is String && v.trim().isNotEmpty) return '${v}원/일';
    } catch (_) {}

    try {
      // 2) pricePerDay(double?) — 과거 코드 호환
      final v = (p as dynamic).pricePerDay;
      if (v is num) return '${v.toInt()}원/일';
      if (v is String && v.trim().isNotEmpty) return '${v}원/일';
    } catch (_) {}

    try {
      // 3) daily_price(Map에서 넘어온 경우 모델이 그대로 노출했을 수도)
      final v = (p as dynamic).daily_price;
      if (v is num) return '${v.toInt()}원/일';
      if (v is String && v.trim().isNotEmpty) return '${v}원/일';
    } catch (_) {}

    return '가격 정보 없음';
  }

  // 안전하게 대여 가능 여부 가져오기
  (bool available, String label) _rentable(Product p) {
    try {
      final v = (p as dynamic).isRentable;
      if (v is bool) return (v, v ? '대여 가능' : '대여 불가');
    } catch (_) {}

    try {
      final v = (p as dynamic).rentable;
      if (v is bool) return (v, v ? '대여 가능' : '대여 불가');
    } catch (_) {}

    try {
      final v = (p as dynamic).available;
      if (v is bool) return (v, v ? '대여 가능' : '대여 불가');
    } catch (_) {}

    // 정보가 없으면 '불명' 처리
    return (false, '대여 정보 없음');
  }

  @override
  Widget build(BuildContext context) {
    final (ok, rentLabel) = _rentable(product);

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F2F5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.image, size: 28),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(product.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 6),
                    Text(_formatPricePerDay(product),
                        style: Theme.of(context).textTheme.bodyMedium),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          ok ? Icons.check_circle : Icons.cancel,
                          size: 16,
                          color: ok
                              ? const Color(0xFF2B8CEC)
                              : const Color(0xFF99A1A8),
                        ),
                        const SizedBox(width: 4),
                        Text(rentLabel,
                            style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}
