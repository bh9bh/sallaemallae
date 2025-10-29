import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../models/product.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // ✅ 싱글턴 사용: new 대신 instance
  final ApiService _api = ApiService.instance;

  bool _loading = true;
  String? _error;
  List<Product> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  // ---- Safe nav helpers ----
  void _push(String route, {Object? args}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.pushNamed(context, route, arguments: args);
    });
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
    // ✅ 관리자만 접근
    if (!_api.isAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('관리자만 상품을 등록할 수 있어요.')),
      );
      return;
    }
    final result = await Navigator.pushNamed(context, '/add_product');
    if (result == true && mounted) {
      await _load();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('새 상품이 등록되어 목록을 갱신했어요.')),
      );
    }
  }

  void _openDetail(Product p) {
    _push('/product', args: p.id);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isAdmin = _api.isAdmin;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sallae Mallae'),
        actions: [
          IconButton(
            tooltip: '내 대여 내역',
            icon: const Icon(Icons.receipt_long_outlined),
            onPressed: () => _push('/mypage'),
          ),
          // ✅ 관리자 빠른 이동(선택): 보이면 편함
          if (isAdmin)
            IconButton(
              tooltip: '관리자: 승인 대기',
              icon: const Icon(Icons.admin_panel_settings_outlined),
              onPressed: () => _push('/admin/pending'),
            ),
        ],
      ),

      // ✅ 관리자에게만 등록 FAB 노출
      floatingActionButton: isAdmin
          ? FloatingActionButton.extended(
              onPressed: _goAdd,
              icon: const Icon(Icons.add),
              label: const Text('상품 등록'),
            )
          : null,

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
                                    isAdmin
                                        ? '오른쪽 아래 + 버튼으로 상품을 등록해보세요.'
                                        : '관리자가 상품을 등록하면 여기에서 볼 수 있어요.',
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

  // ✅ 천단위 콤마 버그 수정: 오른쪽부터 3자리마다 콤마
  String _formatNumber(num n) {
    final negative = n < 0;
    final s = n.abs().toStringAsFixed(0);
    final chars = s.split('').reversed.toList();
    final buf = StringBuffer();
    for (int i = 0; i < chars.length; i++) {
      if (i != 0 && i % 3 == 0) buf.write(',');
      buf.write(chars[i]);
    }
    final withCommas = buf.toString().split('').reversed.join();
    return negative ? '-$withCommas' : withCommas;
  }
}
