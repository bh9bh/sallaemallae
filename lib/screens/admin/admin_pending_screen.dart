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

  /// 승인/거절 중복 방지
  final Set<int> _acting = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // (선택) 관리자 권한 가드가 필요하면 주석 해제
      // if (!_api.isAdmin) {
      //   setState(() {
      //     _items = [];
      //     _error = "관리자 권한이 필요합니다.";
      //     _loading = false;
      //   });
      //   return;
      // }

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

  void _goReviews() {
    Navigator.pushNamed(context, '/admin/reviews');
  }

  String _money(num? n) {
    if (n == null) return "-";
    return n
        .toStringAsFixed(0)
        .replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ",");
  }

  String _ymd(dynamic iso) {
    final s = (iso ?? "").toString();
    return s.length >= 10 ? s.substring(0, 10) : s;
  }

  Future<void> _approve(int id) async {
    if (_acting.contains(id)) return;
    setState(() => _acting.add(id));
    try {
      final ok = await _api.adminApproveRental(id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ok ? "✅ 승인 완료" : "❌ 승인 실패")),
      );
      if (ok) await _load();
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
        SnackBar(content: Text(ok ? "🚫 거절 완료" : "❌ 거절 실패")),
      );
      if (ok) await _load();
    } finally {
      if (mounted) setState(() => _acting.remove(id));
    }
  }

  Widget _buildRentalCard(Map<String, dynamic> r) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final id = r['id'] is int ? r['id'] as int : int.tryParse("${r['id']}") ?? -1;
    final productTitle = r['product_title'] ?? r['product']?['title'] ?? "상품명 미상";
    final userName = r['user_name'] ?? r['user']?['name'] ?? "사용자 미상";
    final start = _ymd(r['start_date'] ?? r['start']);
    final end = _ymd(r['end_date'] ?? r['end']);
    final price = _money(r['total_price']);
    final deposit = _money(r['deposit']);
    final acting = _acting.contains(id);

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720), // ✅ 폭 제한(웹/데스크탑 무한폭 방지)
        child: Card(
          elevation: 0,
          color: theme.cardColor,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 상단 제목 + 보조 정보
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        productTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text("#$id", style: TextStyle(color: cs.outline)),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text("신청자: $userName", style: TextStyle(color: cs.onSurfaceVariant)),
                    Text("기간: $start ~ $end"),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  "대여료 ₩$price   /   보증금 ₩$deposit",
                  style: TextStyle(color: cs.outline),
                ),
                const SizedBox(height: 12),
                // 버튼은 Wrap으로 줄바꿈 가능하게 → 오버플로우 방지
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: acting ? null : () => _approve(id),
                      icon: const Icon(Icons.check),
                      label: const Text("승인"),
                    ),
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
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text("관리자 • 승인 대기"),
        actions: [
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
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(12),
                    children: [
                      Align(
                        alignment: Alignment.topCenter,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 720),
                          child: Card(
                            elevation: 0,
                            color: Theme.of(context).cardColor,
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                children: [
                                  Text(_error!, style: TextStyle(color: cs.error)),
                                  const SizedBox(height: 12),
                                  FilledButton.icon(
                                    onPressed: _load,
                                    icon: const Icon(Icons.refresh),
                                    label: const Text("다시 시도"),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    child: LayoutBuilder(
                      builder: (context, _) {
                        if (_items.isEmpty) {
                          return ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
                            children: const [
                              SizedBox(height: 120),
                              Center(child: Text("승인 대기 중인 대여가 없습니다.")),
                            ],
                          );
                        }
                        return ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                          itemCount: _items.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, i) => _buildRentalCard(_items[i]),
                        );
                      },
                    ),
                  ),
      ),
    );
  }
}
