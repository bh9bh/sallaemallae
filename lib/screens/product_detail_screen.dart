import 'package:flutter/material.dart';
import '../models/product.dart';
import '../services/api_service.dart';

class ProductDetailScreen extends StatefulWidget {
  const ProductDetailScreen({super.key});

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  final _api = ApiService();

  Product? _product;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    // arguments는 build 이후 접근하는 게 안전
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final args = ModalRoute.of(context)?.settings.arguments;

    // 인자로 product 객체나 id를 둘 다 지원
    int? id;
    if (args is int) {
      id = args;
    } else if (args is Map) {
      if (args['product'] is Product) {
        _product = args['product'] as Product;
        setState(() => _loading = false);
        return;
      }
      if (args['id'] is int) id = args['id'] as int;
    }

    if (id == null) {
      setState(() {
        _loading = false;
        _error = '잘못된 접근입니다. (상품 ID 없음)';
      });
      return;
    }

    try {
      final p = await _api.getProduct(id);
      if (!mounted) return;
      if (p == null) {
        setState(() {
          _error = '상품을 불러오지 못했습니다.';
          _loading = false;
        });
      } else {
        setState(() {
          _product = p;
          _loading = false;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = '상품을 불러오지 못했습니다.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('상품 상세')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Text(
                    _error!,
                    style: TextStyle(color: theme.colorScheme.outline),
                  ),
                )
              : _product == null
                  ? Center(
                      child: Text(
                        '잘못된 접근입니다. (상품 정보 없음)',
                        style: TextStyle(color: theme.colorScheme.outline),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // 이미지
                              _ProductImage(url: _product!.imageUrl),

                              const SizedBox(height: 16),

                              // 타이틀
                              Text(
                                _product!.title,
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),

                              const SizedBox(height: 8),

                              // 카테고리/지역 Chip
                              Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                children: [
                                  if ((_product!.category ?? '').isNotEmpty)
                                    Chip(
                                      label: Text(_product!.category!),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                  if ((_product!.region ?? '').isNotEmpty)
                                    Chip(
                                      label: Text(_product!.region!),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                ],
                              ),

                              const SizedBox(height: 16),

                              // 가격 섹션
                              _PriceRow(
                                daily: _product!.dailyPrice,
                                deposit: _product!.deposit,
                              ),

                              const SizedBox(height: 16),

                              // 설명
                              if ((_product!.description ?? '').isNotEmpty) ...[
                                Text('설명', style: theme.textTheme.titleMedium),
                                const SizedBox(height: 6),
                                Text(
                                  _product!.description!,
                                  style: theme.textTheme.bodyMedium,
                                ),
                                const SizedBox(height: 16),
                              ],

                              // 액션 버튼들
                              Row(
                                children: [
                                  Expanded(
                                    child: FilledButton.icon(
                                      onPressed: () {
                                        // 대여 화면으로 이동 (productId 전달)
                                        Navigator.pushNamed(
                                          context,
                                          '/rental',
                                          arguments: _product!.id,
                                        );
                                      },
                                      icon: const Icon(Icons.event_available_outlined),
                                      label: const Text('대여하기'),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () {
                                        Navigator.pop(context);
                                      },
                                      icon: const Icon(Icons.arrow_back),
                                      label: const Text('뒤로'),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
    );
  }
}

class _ProductImage extends StatelessWidget {
  final String? url;
  const _ProductImage({required this.url});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final api = ApiService();

    final resolved = api.absolute(url ?? '');

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: AspectRatio(
        aspectRatio: 1.6, // 가로형 배너 비율
        child: resolved.isEmpty
            ? Container(
                color: theme.colorScheme.surfaceVariant,
                child: Icon(
                  Icons.image_not_supported_outlined,
                  size: 48,
                  color: theme.colorScheme.outline,
                ),
              )
            : Hero(
                tag: 'product:${resolved}',
                child: Image.network(
                  resolved,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: theme.colorScheme.surfaceVariant,
                    child: Icon(
                      Icons.broken_image,
                      size: 48,
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

class _PriceRow extends StatelessWidget {
  final double daily;
  final double deposit;
  const _PriceRow({required this.daily, required this.deposit});

  String _fmt(num v) => v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 0); // 정수 표기

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: theme.colorScheme.surfaceContainerHighest,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('일일 대여료', style: theme.textTheme.labelMedium),
                const SizedBox(height: 4),
                Text('₩ ${_fmt(daily)}',
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: theme.colorScheme.surfaceContainerHighest,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('보증금', style: theme.textTheme.labelMedium),
                const SizedBox(height: 4),
                Text('₩ ${_fmt(deposit)}',
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
