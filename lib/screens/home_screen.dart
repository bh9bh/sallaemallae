import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../models/product.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _api = ApiService();

  bool _loading = true;
  String? _error;
  List<Product> _items = [];

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
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '상품 목록을 불러오지 못했습니다.';
        _loading = false;
      });
    }
  }

  Future<void> _goAdd() async {
    // 등록 화면으로 이동 → true 반환 시 자동 새로고침
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
                                    // 이미지
                                    AspectRatio(
                                      aspectRatio: 1.2,
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
    // 간단한 천단위 구분
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
