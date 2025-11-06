// FILE: lib/screens/product_detail_screen.dart
import 'package:flutter/material.dart';
import '../services/api_service.dart';

class ProductDetailScreen extends StatefulWidget {
  const ProductDetailScreen({super.key});

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  final api = ApiService.instance;

  Map<String, dynamic>? product;
  bool loading = true;
  String? error;

  int? _productId;               // 라우트 인자에서 꺼낸 실제 id
  DateTimeRange? _initialRange;  // (옵션) 라우트에서 넘어올 수 있는 기간

  @override
  void initState() {
    super.initState();
    // 첫 프레임 이후 arguments 접근
    WidgetsBinding.instance.addPostFrameCallback((_) => _initAndLoad());
  }

  void _readRouteArgs() {
    final Object? args = ModalRoute.of(context)?.settings.arguments;

    // 1) int id 만 넘어오는 경우
    if (args is int) {
      _productId = args;
      _initialRange = null;
      return;
    }

    // 2) 문자열 id 방어
    if (args is String) {
      final maybe = int.tryParse(args);
      if (maybe != null) {
        _productId = maybe;
        _initialRange = null;
        return;
      }
    }

    // 3) 맵으로 넘어오는 경우 (productId / range)
    if (args is Map) {
      final Map<dynamic, dynamic> raw = args as Map<dynamic, dynamic>;
      final dynamic pidAny = raw['productId'];
      if (pidAny is int) {
        _productId = pidAny;
      } else if (pidAny is String) {
        _productId = int.tryParse(pidAny);
      }

      final dynamic r = raw['range'];
      _initialRange = (r is DateTimeRange) ? r : null;
      return;
    }

    // 그 외는 지원 안 함
    _productId = null;
    _initialRange = null;
  }

  Future<void> _initAndLoad() async {
    _readRouteArgs();
    await _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });

    try {
      final id = _productId;
      if (id == null) {
        throw Exception('product id is null');
      }

      final dynamic data = await api.getProduct(id);
      final Map<String, dynamic>? parsed =
          (data is Map) ? Map<String, dynamic>.from(data as Map) : null;

      if (!mounted) return;
      setState(() {
        product = parsed;
        loading = false;
        if (product == null) error = '상품 정보를 불러오지 못했습니다.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = '상품 정보를 불러오지 못했습니다.';
      });
    }
  }

  String _fmtIntComma(num? v) {
    final n = (v ?? 0).toInt();
    final s = n.toString();
    return s.replaceAll(RegExp(r'\B(?=(\d{3})+(?!\d))'), ',');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('상품 상세')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (product == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('상품 상세')),
        body: const Center(child: Text('상품 정보를 불러오지 못했습니다.')),
      );
    }

    // ✅ 이 시점에서 product는 non-null
    final Map<String, dynamic> p = Map<String, dynamic>.from(product!);

    // 제목: name → title 폴백
    final String title = (p['name'] ?? p['title'] ?? '').toString();

    final String desc = (p['description'] ?? '').toString();
    final String category = (p['category'] ?? '').toString();

    // 가격: price_per_day → daily_price 폴백 (숫자/문자 모두 처리)
    final dynamic priceRaw =
        p['price_per_day'] ?? p['daily_price'] ?? p['pricePerDay'] ?? p['dailyPrice'];
    final int price = (priceRaw is num)
        ? priceRaw.toInt()
        : (int.tryParse('${priceRaw ?? ''}') ?? 0);

    // 보증금
    final dynamic depositRaw = p['deposit'];
    final int deposit = (depositRaw is num)
        ? depositRaw.toInt()
        : (int.tryParse('${depositRaw ?? ''}') ?? 0);

    // id
    final int? id = (p['id'] as num?)?.toInt();

    // 이미지
    final String? imageUrl = api.absolute(
      (p['image_url'] ?? p['file_url'] ?? '').toString(),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('상품 상세')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          children: [
            Container(
              height: 220,
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(16),
              ),
              clipBehavior: Clip.antiAlias,
              child: (imageUrl == null || imageUrl.isEmpty)
                  ? const Center(child: Icon(Icons.image, size: 48, color: Colors.black26))
                  : Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          const Center(child: Icon(Icons.broken_image, size: 48, color: Colors.black26)),
                    ),
            ),
            const SizedBox(height: 16),

            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    title.isEmpty ? '제목 없음' : title,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(onPressed: () {}, icon: const Icon(Icons.favorite_border)),
                IconButton(onPressed: () {}, icon: const Icon(Icons.share)),
              ],
            ),
            const SizedBox(height: 6),
            Text('0회 조회', style: TextStyle(color: cs.outline)),

            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  '₩ ${_fmtIntComma(price)} /일',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.circle, size: 10, color: Color(0xFF2A69FF)),
                const SizedBox(width: 6),
                const Text('대여 가능', style: TextStyle(color: Color(0xFF2A69FF))),
              ],
            ),
            const SizedBox(height: 10),

            Row(
              children: const [
                Icon(Icons.check, size: 18),
                SizedBox(width: 6),
                Expanded(child: Text('1600W 고속 건조, 정품 케이스 포함')),
              ],
            ),
            const SizedBox(height: 14),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  children: [
                    _kv('보증금', '${0}원'), // 값은 아래에서 다시 씀
                  ],
                ),
              ),
            ),
            // 카드 내용 대체 (위에서 한 줄 먼저 넣은 이유는 레이아웃 유지용)
            Padding(
              padding: const EdgeInsets.only(top: 0),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    children: [
                      _kv('보증금', '${_fmtIntComma(deposit)}원'),
                      const SizedBox(height: 10),
                      _kv('카테고리', category.isEmpty ? '-' : category),
                      const SizedBox(height: 10),
                      _kv('상품 ID', id == null ? '-' : '#$id'),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),

            if (desc.isNotEmpty) ...[
              const Text('상세 설명', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(desc),
              const SizedBox(height: 16),
            ],
          ],
        ),
      ),

      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: SizedBox(
            height: 52,
            child: FilledButton(
              // id를 그대로 넘김 (RentalScreen에서 ModalRoute로 받도록)
              onPressed: (id == null)
                  ? null
                  : () => Navigator.pushNamed(context, '/rental', arguments: id),
              child: const Text('대여 신청하기'),
            ),
          ),
        ),
      ),
    );
  }

  static Widget _kv(String k, String v) {
    return Row(
      children: [
        Expanded(child: Text(k, style: const TextStyle(color: Colors.black54))),
        Text(v, style: const TextStyle(fontWeight: FontWeight.w700)),
      ],
    );
  }
}
