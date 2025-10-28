import 'package:flutter/material.dart';
import '../../services/api_service.dart';

class AdminPendingScreen extends StatefulWidget {
  const AdminPendingScreen({super.key});

  @override
  State<AdminPendingScreen> createState() => _AdminPendingScreenState();
}

class _AdminPendingScreenState extends State<AdminPendingScreen> {
  final _api = ApiService();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];

  // ✅ 승인/거절 중복탭 방지
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
      // NOTE: ApiService에 adminListPendingRentals()가 있어야 합니다.
      final rows = await _api.adminListPendingRentals();
      if (!mounted) return;
      setState(() {
        _items = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = "불러오기 실패";
        _loading = false;
      });
    }
  }

  String _money(num n) {
    final s = n.toStringAsFixed(0);
    return s.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
  }

  Future<void> _approve(int id) async {
    if (_acting.contains(id)) return;
    setState(() => _acting.add(id));
    try {
      final res = await _api.adminApproveRental(id); // Map<String,dynamic>? or null
      if (!mounted) return;
      final ok = res != null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ok ? "승인 완료" : "승인 실패")),
      );
      if (ok) await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("승인 중 오류가 발생했습니다.")),
      );
    } finally {
      if (mounted) setState(() => _acting.remove(id));
    }
  }

  Future<void> _reject(int id) async {
    if (_acting.contains(id)) return;
    setState(() => _acting.add(id));
    try {
      final res = await _api.adminRejectRental(id); // Map<String,dynamic>? or null
      if (!mounted) return;
      final ok = res != null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ok ? "거절 완료" : "거절 실패")),
      );
      if (ok) await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("거절 중 오류가 발생했습니다.")),
      );
    } finally {
      if (mounted) setState(() => _acting.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text("관리자 • 승인 대기")),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _items.isEmpty
                      ? ListView(
                          children: [
                            SizedBox(height: 120),
                            Center(child: Text("승인 대기 항목이 없습니다.")),
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
                            final start = (r['start_date'] ?? '').toString();
                            final end = (r['end_date'] ?? '').toString();
                            final period =
                                "${start.length >= 10 ? start.substring(0, 10) : start} ~ ${end.length >= 10 ? end.substring(0, 10) : end}";
                            final price = (r['total_price'] ?? 0) as num;
                            final deposit = (r['deposit'] ?? 0) as num;

                            final acting = _acting.contains(id);

                            return Card(
                              color: cs.surfaceContainerHighest,
                              elevation: 0,
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
                                    Text(period),
                                    const SizedBox(height: 6),
                                    Text(
                                      "대여료: ₩${_money(price)} / 보증금: ₩${_money(deposit)}",
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
