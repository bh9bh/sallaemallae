// lib/screens/admin/admin_reviews_screen.dart
import 'package:flutter/material.dart';
import '../../services/api_service.dart';

class AdminReviewsScreen extends StatefulWidget {
  const AdminReviewsScreen({super.key});

  @override
  State<AdminReviewsScreen> createState() => _AdminReviewsScreenState();
}

class _AdminReviewsScreenState extends State<AdminReviewsScreen> {
  final ApiService _api = ApiService.instance;

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _reviews = [];

  // ── 필터 상태 ────────────────────────────────────────────────────────────────
  final TextEditingController _productIdCtrl = TextEditingController();
  int? _ratingFilter; // 1~5 or null(전체)

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _productIdCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // productId 텍스트 → int? 변환
      int? productIdFilter;
      final pidText = _productIdCtrl.text.trim();
      if (pidText.isNotEmpty) {
        final parsed = int.tryParse(pidText);
        if (parsed != null) productIdFilter = parsed;
      }

      // ✅ 현재 백엔드는 by-product만 지원 → 상품 ID 없으면 안내 후 종료
      if (productIdFilter == null) {
        setState(() {
          _reviews = [];
          _loading = false;
          _error = "상품 ID를 입력하고 조회하세요. (현재 백엔드는 상품별 조회만 지원)";
        });
        return;
      }

      // 백엔드 형태(List/Map) 유연 파싱 (+ adminGetReviews는 404 시 by-product로 폴백)
      final data = await _api.adminGetReviews(
        productId: productIdFilter,
        rating: _ratingFilter, // 서버가 무시해도 됨, 아래에서 클라 후처리
      );

      List<Map<String, dynamic>> rows = [];
      if (data is List) {
        rows = data.cast<Map<String, dynamic>>();
      } else if (data is Map) {
        final maybe = data['items'] ?? data['rows'] ?? data['data'] ?? data['results'];
        if (maybe is List) {
          rows = maybe.cast<Map<String, dynamic>>();
        }
      }

      // ✅ 평점 필터는 클라이언트에서 후처리(서버가 지원 안 할 수 있음)
      if (_ratingFilter != null) {
        rows = rows.where((r) {
          final rt = r['rating'];
          final v = (rt is num) ? rt.toInt() : int.tryParse(rt?.toString() ?? '');
          return v == _ratingFilter;
        }).toList();
      }

      if (!mounted) return;
      setState(() {
        _reviews = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = "리뷰 목록을 불러오지 못했습니다.";
        _loading = false;
      });
    }
  }

  Future<void> _logout() async {
    await _api.logout();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
  }

  Future<void> _deleteReview(int reviewId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('리뷰 삭제'),
        content: const Text('정말 이 리뷰를 삭제하시겠습니까?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('삭제')),
        ],
      ),
    );

    if (ok != true) return;

    final success = await _api.adminDeleteReview(reviewId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(success ? '삭제되었습니다.' : '삭제 실패')),
    );
    if (success) _load();
  }

  String _ymd(dynamic iso) {
    final s = (iso ?? '').toString();
    return s.length >= 10 ? s.substring(0, 10) : s;
  }

  Widget _buildStars(num? rating) {
    final r = (rating ?? 0).toInt().clamp(0, 5);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        return Icon(i < r ? Icons.star : Icons.star_border, size: 16);
      }),
    );
  }

  // ── 상단 필터 바 ────────────────────────────────────────────────────────────
  Widget _buildFilterBar(ColorScheme cs) {
    return Card(
      elevation: 0,
      color: cs.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Column(
          children: [
            Row(
              children: [
                // 상품ID 입력
                Expanded(
                  child: TextField(
                    controller: _productIdCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '상품 ID',
                      hintText: '예) 3',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _load(),
                  ),
                ),
                const SizedBox(width: 8),
                // 평점 선택 (비-const로 타입 충돌 방지)
                DropdownButton<int?>(
                  value: _ratingFilter,
                  underline: const SizedBox(),
                  items: <DropdownMenuItem<int?>>[
                    const DropdownMenuItem<int?>(value: null, child: Text('평점: 전체')),
                    const DropdownMenuItem<int?>(value: 5, child: Text('★ 5')),
                    const DropdownMenuItem<int?>(value: 4, child: Text('★ 4')),
                    const DropdownMenuItem<int?>(value: 3, child: Text('★ 3')),
                    const DropdownMenuItem<int?>(value: 2, child: Text('★ 2')),
                    const DropdownMenuItem<int?>(value: 1, child: Text('★ 1')),
                  ],
                  onChanged: (v) => setState(() => _ratingFilter = v),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _load,
                    icon: const Icon(Icons.search),
                    label: const Text('적용'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      _productIdCtrl.clear();
                      setState(() => _ratingFilter = null);
                      _load();
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('초기화'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('관리자 • 리뷰 관리'),
        actions: [
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
              ? ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    _buildFilterBar(cs),
                    const SizedBox(height: 24),
                    Center(child: Text(_error!)),
                  ],
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _reviews.isEmpty
                      ? ListView(
                          padding: const EdgeInsets.all(12),
                          children: [
                            _buildFilterBar(cs),
                            const SizedBox(height: 140),
                            const Center(child: Text('등록된 리뷰가 없습니다.')),
                          ],
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemCount: _reviews.length + 1, // +1: 필터바
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, i) {
                            if (i == 0) return _buildFilterBar(cs);

                            final r = _reviews[i - 1];
                            // id 키가 review_id일 수도 있어 안전 처리
                            final dynamicId = r['id'] ?? r['review_id'];
                            final id = (dynamicId is int)
                                ? dynamicId
                                : int.tryParse(dynamicId?.toString() ?? '') ?? -1;

                            final productId = r['product_id']?.toString() ?? '?';
                            final userId = r['user_id']?.toString() ?? '?';
                            final rating = r['rating'] as num?;
                            final comment = (r['comment'] ?? '').toString();
                            final createdAt = _ymd(r['created_at']);

                            return Card(
                              elevation: 0,
                              color: cs.surfaceContainerHighest,
                              child: ListTile(
                                contentPadding:
                                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                title: Row(
                                  children: [
                                    _buildStars(rating),
                                    const SizedBox(width: 8),
                                    Text(
                                      '• 상품 #$productId • 사용자 #$userId',
                                      style: TextStyle(color: cs.onSurfaceVariant),
                                    ),
                                  ],
                                ),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 8.0),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      if (comment.isNotEmpty) Text(comment),
                                      const SizedBox(height: 6),
                                      Text(
                                        createdAt,
                                        style: TextStyle(color: cs.outline),
                                      ),
                                    ],
                                  ),
                                ),
                                // 메뉴(삭제)
                                trailing: PopupMenuButton<String>(
                                  onSelected: (v) {
                                    if (v == 'delete') {
                                      _deleteReview(id);
                                    }
                                  },
                                  itemBuilder: (ctx) => const [
                                    PopupMenuItem(
                                      value: 'delete',
                                      child: Row(
                                        children: [
                                          Icon(Icons.delete_outline, size: 18),
                                          SizedBox(width: 8),
                                          Text('삭제'),
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
}
