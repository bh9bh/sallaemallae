import 'package:flutter/material.dart';
import '../models/product.dart';
import '../services/api_service.dart';

class ProductDetailScreen extends StatefulWidget {
  const ProductDetailScreen({super.key});

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  final ApiService _api = ApiService.instance;

  Product? _product;
  bool _loading = true;
  String? _error;

  // ⭐ 리뷰 상태
  List<Map<String, dynamic>> _reviews = [];
  double _avgRating = 0.0;

  @override
  void initState() {
    super.initState();
    // arguments는 build 이후 접근이 안전
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final args = ModalRoute.of(context)?.settings.arguments;

    // 인자로 product 객체나 id 둘 다 지원
    int? id;
    if (args is int) {
      id = args;
    } else if (args is Map) {
      if (args['product'] is Product) {
        _product = args['product'] as Product;
        id = _product!.id;
      } else if (args['id'] is int) {
        id = args['id'] as int;
      }
    }

    if (id == null && _product == null) {
      setState(() {
        _loading = false;
        _error = '잘못된 접근입니다. (상품 ID 없음)';
      });
      return;
    }

    try {
      // 1) 상품 정보
      if (_product == null) {
        final p = await _api.getProduct(id!);
        if (!mounted) return;
        if (p == null) {
          setState(() {
            _error = '상품을 불러오지 못했습니다.';
            _loading = false;
          });
          return;
        }
        _product = p;
      }

      // 2) 리뷰 불러오기
      final reviews = await _api.getReviewsByProduct(_product!.id);
      double avg = 0;
      if (reviews.isNotEmpty) {
        final sum = reviews.fold<num>(0, (acc, e) => acc + (e['rating'] as num? ?? 0));
        avg = (sum / reviews.length).toDouble();
      }

      if (!mounted) return;
      setState(() {
        _reviews = reviews;
        _avgRating = avg;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = '상품을 불러오지 못했습니다.';
        _loading = false;
      });
    }
  }

  // ----- UI helpers -----
  String _fmtInt(num n) => n.toStringAsFixed(0);

  Widget _buildStars(double rating, {double size = 18}) {
    // 반올림하여 꽉찬/반쪽/빈 별 계산
    final full = rating.floor();
    final hasHalf = (rating - full) >= 0.5 && (rating - full) < 1.0;
    final empty = 5 - full - (hasHalf ? 1 : 0);

    final stars = <Widget>[];
    for (int i = 0; i < full; i++) {
      stars.add(Icon(Icons.star, size: size, color: Colors.amber));
    }
    if (hasHalf) {
      stars.add(Icon(Icons.star_half, size: size, color: Colors.amber));
    }
    for (int i = 0; i < empty; i++) {
      stars.add(Icon(Icons.star_border, size: size, color: Colors.amber));
    }
    return Row(mainAxisSize: MainAxisSize.min, children: stars);
  }

  void _showAllReviewsBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: _reviews.isEmpty
                ? SizedBox(
                    height: 160,
                    child: Center(
                      child: Text("아직 등록된 후기가 없습니다.", style: TextStyle(color: cs.outline)),
                    ),
                  )
                : SizedBox(
                    height: MediaQuery.of(ctx).size.height * 0.7,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("전체 후기", style: Theme.of(ctx).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        Expanded(
                          child: ListView.separated(
                            itemCount: _reviews.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (_, i) => _ReviewTile(map: _reviews[i]),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        );
      },
    );
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

                              const SizedBox(height: 12),

                              // ⭐ 평균 별점 + 리뷰 수
                              _reviews.isEmpty
                                  ? Text(
                                      "아직 후기가 없습니다.",
                                      style: TextStyle(color: theme.colorScheme.outline),
                                    )
                                  : Row(
                                      children: [
                                        _buildStars(double.parse((_avgRating).toStringAsFixed(1)), size: 20),
                                        const SizedBox(width: 8),
                                        Text(
                                          "${_avgRating.toStringAsFixed(1)} (${_reviews.length})",
                                          style: theme.textTheme.bodyMedium?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const Spacer(),
                                        TextButton(
                                          onPressed: _showAllReviewsBottomSheet,
                                          child: const Text("후기 더보기"),
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

                              // 최근 리뷰 3개 미리보기
                              if (_reviews.isNotEmpty) ...[
                                Row(
                                  children: [
                                    Text('최근 후기', style: theme.textTheme.titleMedium),
                                    const Spacer(),
                                    TextButton(
                                      onPressed: _showAllReviewsBottomSheet,
                                      child: const Text('모두 보기'),
                                    )
                                  ],
                                ),
                                const SizedBox(height: 8),
                                ..._reviews.take(3).map((m) => Padding(
                                      padding: const EdgeInsets.only(bottom: 8.0),
                                      child: _ReviewTile(map: m),
                                    )),
                                const SizedBox(height: 8),
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
                                      onPressed: () => Navigator.pop(context),
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
    final api = ApiService.instance;

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
                tag: 'product:$resolved',
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

  String _fmt(num v) => v.toStringAsFixed(0); // 정수 표기

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

class _ReviewTile extends StatelessWidget {
  final Map<String, dynamic> map;
  const _ReviewTile({required this.map});

  String _ymd(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    return iso.length >= 10 ? iso.substring(0, 10) : iso;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rating = (map['rating'] as num?)?.toInt() ?? 0;
    final comment = (map['comment'] as String?)?.trim();
    final user = (map['user_name'] as String?) ?? (map['user']?.toString() ?? '사용자');
    final created = _ymd(map['created_at']?.toString());

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 상단: 별점 + 사용자 + 날짜
          Row(
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(
                  5,
                  (i) => Icon(
                    i < rating ? Icons.star : Icons.star_border,
                    size: 16,
                    color: Colors.amber,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(user, style: const TextStyle(fontWeight: FontWeight.w600)),
              const Spacer(),
              if (created.isNotEmpty)
                Text(created, style: TextStyle(color: cs.outline, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            (comment == null || comment.isEmpty) ? "내용 없음" : comment,
            style: const TextStyle(fontSize: 14),
          ),
        ],
      ),
    );
  }
}
