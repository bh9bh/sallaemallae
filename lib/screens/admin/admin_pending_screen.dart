import 'package:flutter/material.dart';
import '../../services/api_service.dart';

class AdminPendingScreen extends StatefulWidget {
  const AdminPendingScreen({super.key});

  @override
  State<AdminPendingScreen> createState() => _AdminPendingScreenState();
}

class _AdminPendingScreenState extends State<AdminPendingScreen> {
  final ApiService _api = ApiService.instance;

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];

  // 승인/거절 중복 방지
  final Set<int> _acting = {};

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
      final rows = await _api.adminListPendingRentals();
      if (!mounted) return;
      setState(() {
        _items = rows;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = "승인 대기 목록을 불러오지 못했습니다.";
        _loading = false;
      });
    }
  }

  Future<void> _logout() async {
    await _api.logout();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
  }

  // ✅ (NEW) 리뷰 관리 화면으로 이동
  void _goReviews() {
    Navigator.pushNamed(context, '/admin/reviews');
  }

  String _money(num n) =>
      n.toStringAsFixed(0).replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');

  String _ymd(dynamic iso) {
    final s = (iso ?? '').toString();
    return s.length >= 10 ? s.substring(0, 10) : s;
  }

  Future<void> _approve(int id) async {
    if (_acting.contains(id)) return;
    setState(() => _acting.add(id));

    try {
      final ok = await _api.adminApproveRental(id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ok ? "승인 완료" : "승인 실패")),
      );
      if (ok) _load();
    } finally {
      if (mounted) setState(() => _acting.remove(id));
    }
  }

  Future<void> _reject(int id) async {
    if (_acting.contains(id)) return;
    setState(() => _acting.add(id));

    try {
      final ok = await _api.adminRejectRental(id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ok ? "거절 완료" : "거절 실패")),
      );
      if (ok) _load();
    } finally {
      if (mounted) setState(() => _acting.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text("관리자 • 승인 대기"),
        actions: [
          // ✅ (NEW) 리뷰 관리 이동 아이콘
          IconButton(
            tooltip: '리뷰 관리',
            icon: const Icon(Icons.reviews_outlined),
            onPressed: _goReviews,
          ),
          IconButton(
            tooltip: '로그아웃',
            icon: const Icon(Icons.logout),
            onPressed: _logout,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _items.isEmpty
                      ? ListView(
                          children: const [
                            SizedBox(height: 140),
                            Center(child: Text("승인 대기 중인 대여가 없습니다.")),
                          ],
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemCount: _items.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, i) {
                            final r = _items[i];
                            final id = r['id'] as int;
                            final productId = r['product_id'];
                            final userId = r['user_id'];
                            final start = _ymd(r['start_date']);
                            final end = _ymd(r['end_date']);
                            final price = (r['total_price'] ?? 0) as num;
                            final deposit = (r['deposit'] ?? 0) as num;
                            final acting = _acting.contains(id);

                            return Card(
                              elevation: 0,
                              color: cs.surfaceContainerHighest,
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      "대여 #$id • 상품 #$productId • 사용자 #$userId",
                                      style: Theme.of(context).textTheme.titleMedium,
                                    ),
                                    const SizedBox(height: 6),
                                    Text("$start ~ $end"),
                                    const SizedBox(height: 6),
                                    Text(
                                      "대여료 ₩${_money(price)}   /   보증금 ₩${_money(deposit)}",
                                      style: TextStyle(color: cs.outline),
                                    ),
                                    const SizedBox(height: 12),
                                    Row(
                                      children: [
                                        FilledButton.icon(
                                          onPressed: acting ? null : () => _approve(id),
                                          icon: const Icon(Icons.check),
                                          label: const Text("승인"),
                                        ),
                                        const SizedBox(width: 8),
                                        OutlinedButton.icon(
                                          onPressed: acting ? null : () => _reject(id),
                                          icon: const Icon(Icons.close),
                                          label: const Text("거절"),
                                        ),
                                      ],
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
}
