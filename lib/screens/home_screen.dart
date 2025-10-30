import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../models/product.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // ✅ 싱글턴 통일
  final ApiService _api = ApiService.instance;

  bool _loading = true;
  String? _error;
  List<Product> _items = [];

  // ⭐ 평점 캐시: { productId: {'avg': double, 'count': int} }
  final Map<int, Map<String, dynamic>> _ratingCache = {};
  final Set<int> _loadingRating = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _api.getProducts();
      if (!mounted) return;
      setState(() {
        _items = data;
        _loading = false;
      });
      // ⭐ 평점 미리 가져오기 (가벼운 N개 호출; MVP 기준)
      _prefetchRatings(data.map((e) => e.id).toList());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '상품 목록을 불러오지 못했습니다.';
        _loading = false;
      });
    }
  }

  Future<void> _prefetchRatings(List<int> ids) async {
    for (final id in ids) {
      // 이미 있는 건 스킵
      if (_ratingCache.containsKey(id) || _loadingRating.contains(id)) continue;
      _fetchRating(id);
    }
  }

  Future<void> _fetchRating(int productId) async {
    _loadingRating.add(productId);
    try {
      final summary = await _api.getProductRatingSummary(productId);
      if (!mounted) return;
      _ratingCache[productId] = summary ?? {};
      setState(() {});
    } finally {
      _loadingRating.remove(productId);
    }
  }

  Future<void> _goAdd() async {
    final result = await Navigator.pushNamed(context, '/add_product');
    if (result == true && mounted) {
      await _load();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('새 상품이 등록되어 목록을 갱신했어요.')),
      );
    }
  }

  void _openDetail(Product p) {
    Navigator.pushNamed(context, '/product', arguments: p.id);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sallae Mallae'),
        actions: [
          IconButton(
            tooltip: '내 대여 내역',
            icon: const Icon(Icons.receipt_long_outlined),
            onPressed: () => Navigator.pushNamed(context, '/mypage'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _goAdd,
        icon: const Icon(Icons.add),
        label: const Text('상품 등록'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _error != null
                  ? ListView(
                      children: [
                        SizedBox(height: MediaQuery.of(context).size.height * 0.25),
                        Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(_error!, style: const TextStyle(color: Colors.red)),
                              const SizedBox(height: 12),
                              FilledButton.icon(
                                onPressed: _load,
                                icon: const Icon(Icons.refresh),
                                label: const Text('다시 시도'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    )
                  : _items.isEmpty
                      ? ListView(
                          padding: const EdgeInsets.all(20),
                          children: [
                            SizedBox(height: MediaQuery.of(context).size.height * 0.2),
                            Center(
                              child: Column(
                                children: [
                                  Text(
                                    '등록된 상품이 없어요.',
                                    style: theme.textTheme.titleMedium,
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    '오른쪽 아래 + 버튼으로 상품을 등록해보세요.',
                                    style: TextStyle(color: theme.colorScheme.outline),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        )
                      : GridView.builder(
                          padding: const EdgeInsets.all(12),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            childAspectRatio: 0.78,
                          ),
                          itemCount: _items.length,
                          itemBuilder: (context, i) {
                            final p = _items[i];

                            final img = (p.imageUrl ?? '').isNotEmpty
                                ? _api.absolute(p.imageUrl)
                                : null;

                            // ⭐ 평점 표시 준비
                            final summary = _ratingCache[p.id];
                            final isLoading = _loadingRating.contains(p.id) && summary == null;
                            final hasData = summary != null &&
                                summary['avg'] != null &&
                                summary['count'] != null &&
                                (summary['count'] as int) > 0;
                            final avg = hasData ? (summary!['avg'] as num).toDouble() : 0.0;
                            final count = hasData ? (summary!['count'] as int) : 0;

                            // 첫 진입 시 캐시 없으면 비동기 로드 트리거
                            if (summary == null && !isLoading) {
                              // 프레임 이후 안전 호출
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (mounted) _fetchRating(p.id);
                              });
                            }

                            return InkWell(
                              onTap: () => _openDetail(p),
                              borderRadius: BorderRadius.circular(16),
                              child: Card(
                                clipBehavior: Clip.antiAlias,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  side: BorderSide(color: theme.dividerColor),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    // 이미지 + ⭐평점 배지 오버레이
                                    AspectRatio(
                                      aspectRatio: 1.2,
                                      child: Stack(
                                        children: [
                                          Positioned.fill(
                                            child: img == null
                                                ? Container(
                                                    color: theme.colorScheme.surfaceVariant,
                                                    child: const Icon(Icons.photo_outlined, size: 42),
                                                  )
                                                : Image.network(
                                                    img,
                                                    fit: BoxFit.cover,
                                                    errorBuilder: (_, __, ___) => Container(
                                                      color: theme.colorScheme.surfaceVariant,
                                                      child: const Icon(Icons.broken_image),
                                                    ),
                                                  ),
                                          ),
                                          // ⭐ 배지
                                          Positioned(
                                            left: 8,
                                            top: 8,
                                            child: hasData
                                                ? _RatingBadge(avg: avg, count: count)
                                                : (isLoading
                                                    ? _RatingBadge.loading()
                                                    : const SizedBox.shrink()),
                                          ),
                                        ],
                                      ),
                                    ),

                                    // 정보
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            p.title ?? '제목 없음',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: theme.textTheme.titleMedium?.copyWith(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Row(
                                            children: [
                                              if ((p.region ?? '').isNotEmpty)
                                                Row(
                                                  children: [
                                                    const Icon(Icons.place, size: 14),
                                                    const SizedBox(width: 3),
                                                    Text(
                                                      p.region!,
                                                      style: TextStyle(
                                                        color: theme.colorScheme.outline,
                                                        fontSize: 12,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              const Spacer(),
                                              if (p.dailyPrice != null)
                                                Text(
                                                  '₩ ${_formatNumber(p.dailyPrice!)} /일',
                                                  style: theme.textTheme.labelLarge,
                                                ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
            ),
    );
  }

  String _formatNumber(num n) {
    final s = n.toStringAsFixed(0);
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      final idx = s.length - i;
      buf.write(s[i]);
      final rem = (idx - 1);
      if (rem > 0 && rem % 3 == 0) buf.write(',');
    }
    return buf.toString();
  }
}

class _RatingBadge extends StatelessWidget {
  final double? avg;
  final int? count;
  final bool skeleton;

  const _RatingBadge({super.key, required this.avg, required this.count}) : skeleton = false;

  const _RatingBadge.loading({super.key})
      : avg = null,
        count = null,
        skeleton = true;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (skeleton) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: cs.surface.withOpacity(.85),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Icon(Icons.star_border, size: 16, color: cs.outline),
            const SizedBox(width: 4),
            Container(width: 26, height: 10, color: cs.surfaceContainerHighest,),
          ],
        ),
      );
    }
    if (avg == null || count == null || count == 0) {
      // 후기 없음 → 배지 미표시가 기본이지만, 보여주고 싶다면 여기 커스텀
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: cs.surface.withOpacity(.9),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          const Icon(Icons.star, size: 16, color: Colors.amber),
          const SizedBox(width: 4),
          Text(
            '${avg!.toStringAsFixed(1)} (${count!})',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}


