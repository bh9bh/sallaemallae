import 'package:flutter/material.dart';
import '../services/api_service.dart';

class MyPageScreen extends StatefulWidget {
  const MyPageScreen({super.key});

  @override
  State<MyPageScreen> createState() => _MyPageScreenState();
}

class _MyPageScreenState extends State<MyPageScreen> {
  // ✅ 싱글턴 통일
  final ApiService _api = ApiService.instance;

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rentals = [];

  // 렌탈별 사진 캐시 (지연 로딩)
  final Map<int, List<Map<String, dynamic>>> _photosCache = {};
  final Set<int> _loadingPhotos = {};

  // ✅ 결제 중복 방지용(버튼 비활성화)
  final Set<int> _paying = {};

  // 필터
  bool _showClosed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // ---- Safe nav helper ----
  void _pushReplaceAll(String route) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, route, (r) => false);
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    if (!_api.isAuthenticated) {
      setState(() {
        _loading = false;
        _error = "로그인이 필요합니다. 먼저 로그인해주세요.";
        _rentals = [];
      });
      return;
    }

    try {
      // ✅ ApiService 시그니처에 맞게 includeClosed 사용
      final data = await _api.getMyRentals(includeClosed: _showClosed);
      if (!mounted) return;
      setState(() {
        _rentals = data;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = "내 대여 내역을 불러오지 못했습니다.";
        _loading = false;
      });
    }
  }

  Future<void> _logout() async {
    await _api.logout(); // 토큰/헤더 제거
    if (!mounted) return;
    setState(() {
      _rentals = [];
      _photosCache.clear();
      _loadingPhotos.clear();
      _error = "로그인이 필요합니다. 먼저 로그인해주세요.";
    });
    // ✅ 안전 네비게이션: 스택 제거 후 로그인으로
    _pushReplaceAll('/login');
  }

  // ✅ 결제 시뮬레이터 호출 (중복탭 방지 + 성공 시 목록 갱신)
  Future<void> _actPay(int rentalId, Map<String, dynamic> rental) async {
    if (_paying.contains(rentalId)) return; // 연속 탭 방지
    setState(() => _paying.add(rentalId));

    try {
      // 금액 계산: 대여료 합계 + 보증금
      final totalPrice = (rental['total_price'] ?? 0) as num;
      final deposit = (rental['deposit'] ?? 0) as num;
      final amount = (totalPrice + deposit).toDouble();

      // 결제 시뮬레이터 호출
      final res = await _api.simulatePayment(rentalId: rentalId, amount: amount);
      if (!mounted) return;

      final ok = res != null; // 200 OK면 Map 반환, 실패 시 null
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ok ? "결제가 완료되었습니다." : "결제 실패")),
      );

      // ✅ 성공 시 목록 갱신(상태/버튼 즉시 반영)
      if (ok) await _load();
    } finally {
      if (mounted) setState(() => _paying.remove(rentalId));
    }
  }

  String _fmtDate(dynamic iso) {
    final s = (iso ?? '').toString();
    return s.length >= 10 ? s.substring(0, 10) : s;
  }

  // ✅ 서버 로직과 동일하게 '로컬 날짜' 기준으로 계산하도록 변경
  DateTime? _parseDate(dynamic iso) {
    if (iso == null) return null;
    try {
      // (주의) toUtc() 쓰지 말고, 그대로 파싱 후 로컬로 변환
      return DateTime.parse(iso.toString()).toLocal();
    } catch (_) {
      return null;
    }
  }

  // --- 날짜 비교 헬퍼 (로컬 자정 기준) ---
  DateTime _onlyDate(DateTime d) => DateTime(d.year, d.month, d.day);
  bool isAfterTodayLocal(DateTime? d) {
    if (d == null) return false;
    final today = _onlyDate(DateTime.now().toLocal());
    final x = _onlyDate(d);
    return x.isAfter(today);
  }

  bool isTodayOrBeforeLocal(DateTime? d) {
    if (d == null) return false;
    final today = _onlyDate(DateTime.now().toLocal());
    final x = _onlyDate(d);
    return !x.isAfter(today); // 오늘이거나 과거
  }

  Color _statusColor(String status, BuildContext ctx) {
    final s = status.toUpperCase();
    if (s.contains('RETURN')) return Colors.green;
    if (s.contains('CANCEL') || s.contains('CLOSED')) return Colors.red;
    return Theme.of(ctx).colorScheme.primary; // ACTIVE 등
  }

  Future<void> _ensurePhotosLoaded(int rentalId) async {
    if (_photosCache.containsKey(rentalId) || _loadingPhotos.contains(rentalId)) return;
    _loadingPhotos.add(rentalId);
    final photos = await _api.getPhotosByRental(rentalId);
    _photosCache[rentalId] = photos;
    _loadingPhotos.remove(rentalId);
    if (mounted) setState(() {});
  }

  Future<void> _goUpload(int rentalId) async {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await Navigator.pushNamed(context, '/photo', arguments: rentalId);
      if (!mounted) return;
      _photosCache.remove(rentalId);
      await _ensurePhotosLoaded(rentalId);
    });
  }

  Future<void> _deletePhoto(int rentalId, int photoId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("사진 삭제"),
        content: const Text("정말 이 사진을 삭제하시겠습니까?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("취소")),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("삭제")),
        ],
      ),
    );

    if (ok == true) {
      final success = await _api.deletePhoto(photoId);
      if (success) {
        setState(() {
          _photosCache[rentalId]?.removeWhere((p) => p['id'] == photoId);
        });
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("사진 삭제 실패")),
        );
      }
    }
  }

  Future<void> _actCancel(int rentalId) async {
    final ok = await _api.cancelRental(rentalId);
    if (ok != null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("대여가 취소되었습니다.")));
      _load();
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("대여 취소 실패")));
    }
  }

  Future<void> _actRequestReturn(int rentalId) async {
    final ok = await _api.requestReturn(rentalId);
    if (ok != null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("반납 요청 완료")));
      _load();
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("반납 요청 실패")));
    }
  }

  Future<void> _actConfirmReturn(int rentalId) async {
    final ok = await _api.confirmReturn(rentalId);
    if (ok != null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("반납이 완료되었습니다.")));
      _load();
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("반납 완료 처리 실패")));
    }
  }

  // ⭐ 리뷰: BottomSheet로 작성 UI + 저장 호출
  Future<void> _writeReview(int rentalId) async {
    int rating = 5;
    final controller = TextEditingController();

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return Padding(
          padding: EdgeInsets.only(
            left: 16, right: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
            top: 12,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("후기 작성", style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: 10),

              StatefulBuilder(
                builder: (c, setS) => Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (i) {
                    final filled = i < rating;
                    return IconButton(
                      iconSize: 28,
                      onPressed: () => setS(() => rating = i + 1),
                      icon: Icon(filled ? Icons.star : Icons.star_border),
                      color: filled ? Colors.amber : cs.outline,
                    );
                  }),
                ),
              ),

              const SizedBox(height: 6),
              TextField(
                controller: controller,
                maxLines: 4,
                maxLength: 300,
                decoration: const InputDecoration(
                  hintText: "이용 후기를 적어주세요 (선택)",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),

              SizedBox(
                width: double.infinity,
                height: 46,
                child: FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text("저장"),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );

    if (ok == true) {
      final res = await _api.createReview(
        rentalId: rentalId,
        rating: rating,
        comment: controller.text.trim().isEmpty ? null : controller.text.trim(),
      );
      if (!mounted) return;
      final success = res != null;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(success ? "후기를 등록했습니다." : "후기 등록 실패")));
      // ✅ 저장 성공 시 즉시 목록 갱신 (버튼 숨김 등 반영)
      if (success) await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text("내 대여 내역"),
        actions: [
          if (_api.isAuthenticated)
            IconButton(
              tooltip: '로그아웃',
              icon: const Icon(Icons.logout),
              onPressed: _logout,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _rentals.isEmpty
                  ? ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      children: [
                        _InfoBanner(),
                        const SizedBox(height: 10),
                        _FilterChips(
                          showClosed: _showClosed,
                          onChanged: (v) {
                            setState(() => _showClosed = v);
                            _load();
                          },
                        ),
                        SizedBox(height: MediaQuery.of(context).size.height * .25),
                        _buildEmpty(),
                      ],
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: _rentals.length + 2,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        if (i == 0) return _InfoBanner();
                        if (i == 1) {
                          return _FilterChips(
                            showClosed: _showClosed,
                            onChanged: (v) {
                              setState(() => _showClosed = v);
                              _load();
                            },
                          );
                        }

                        final r = _rentals[i - 2];
                        final id = r['id'] as int;
                        final productId = r['product_id'];
                        final startIso = r['start_date'];
                        final endIso = r['end_date'];
                        final start = _fmtDate(startIso);
                        final end = _fmtDate(endIso);
                        final status = (r['status'] ?? '').toString();
                        final uStatus = status.toUpperCase();
                        final isClosed = uStatus.contains('CLOSED');

                        // ⭐ 이미 후기 작성 여부(백엔드 필드 대응)
                        final hasReview =
                            (r['has_review'] == true) || (r['review_id'] != null);

                        // ✅ 로컬 기준 날짜로 비교
                        final startDT = _parseDate(startIso);

                        // 버튼 노출 조건(백엔드와 동일한 일자 기준)
                        final canCancel =
                            !isClosed && uStatus == 'ACTIVE' && isAfterTodayLocal(startDT);
                        final canRequestReturn =
                            !isClosed && uStatus == 'ACTIVE' && isTodayOrBeforeLocal(startDT);
                        final canConfirmReturn = uStatus == 'RETURN_REQUESTED';

                        _ensurePhotosLoaded(id);
                        final photos = _photosCache[id];

                        return Card(
                          elevation: 0,
                          clipBehavior: Clip.antiAlias,
                          color: cs.surfaceContainerHighest,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // 헤더: 제목 + 상태 Chip
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        "대여 #$id  •  상품 #$productId",
                                        style: Theme.of(context).textTheme.titleMedium,
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: _statusColor(status, context).withOpacity(.12),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        status,
                                        style: TextStyle(
                                          color: _statusColor(status, context),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text("$start  ~  $end"),

                                const SizedBox(height: 12),

                                // 썸네일 영역
                                if (photos == null)
                                  SizedBox(
                                    height: 120,
                                    child: Center(
                                      child: _loadingPhotos.contains(id)
                                          ? const SizedBox(
                                              width: 22,
                                              height: 22,
                                              child: CircularProgressIndicator(strokeWidth: 2),
                                            )
                                          : Text(
                                              "사진 없음",
                                              style: TextStyle(color: cs.outline),
                                            ),
                                    ),
                                  )
                                else if (photos.isEmpty)
                                  SizedBox(
                                    height: 44,
                                    child: Text(
                                      "업로드된 사진이 없습니다.",
                                      style: TextStyle(color: cs.outline),
                                    ),
                                  )
                                else
                                  SizedBox(
                                    height: 120,
                                    child: ListView.separated(
                                      scrollDirection: Axis.horizontal,
                                      itemCount: photos.length,
                                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                                      itemBuilder: (ctx, idx) {
                                        final p = photos[idx];
                                        final url = _api.absolute(p['file_url']?.toString());
                                        final phase = (p['phase'] ?? '').toString().toUpperCase();
                                        final photoId = p['id'] as int;

                                        return SizedBox(
                                          width: 100,
                                          child: _Thumb(
                                            url: url,
                                            phase: phase,
                                            onDelete: () => _deletePhoto(id, photoId),
                                          ),
                                        );
                                      },
                                    ),
                                  ),

                                const SizedBox(height: 12),

                                // ✅ 액션 버튼들
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    FilledButton.tonalIcon(
                                      onPressed: isClosed ? null : () => _goUpload(id),
                                      icon: const Icon(Icons.upload),
                                      label: const Text("사진 업로드"),
                                    ),
                                    OutlinedButton.icon(
                                      onPressed: () => _ensurePhotosLoaded(id),
                                      icon: const Icon(Icons.refresh),
                                      label: const Text("사진 새로고침"),
                                    ),

                                    // ✅ 결제하기 (ACTIVE 상태에서 노출, 결제 중이면 비활성)
                                    if (!isClosed && uStatus == 'ACTIVE')
                                      OutlinedButton.icon(
                                        icon: const Icon(Icons.payment_outlined),
                                        label: const Text("결제하기"),
                                        onPressed: _paying.contains(id) ? null : () => _actPay(id, r),
                                      ),

                                    if (canCancel)
                                      OutlinedButton.icon(
                                        icon: const Icon(Icons.cancel_outlined),
                                        label: const Text("대여 취소"),
                                        onPressed: () => _actCancel(id),
                                      ),

                                    if (canRequestReturn)
                                      OutlinedButton.icon(
                                        icon: const Icon(Icons.assignment_return_outlined),
                                        label: const Text("반납 요청"),
                                        onPressed: () => _actRequestReturn(id),
                                      ),

                                    if (canConfirmReturn)
                                      FilledButton.icon(
                                        icon: const Icon(Icons.check_circle_outline),
                                        label: const Text("반납 완료"),
                                        onPressed: () => _actConfirmReturn(id),
                                      ),

                                    // ⭐ 리뷰: CLOSED일 때만 후기 작성 보이기 + 이미 작성한 경우 숨김
                                    if (isClosed && !hasReview)
                                      FilledButton.tonalIcon(
                                        icon: const Icon(Icons.rate_review_outlined),
                                        label: const Text("후기 작성하기"),
                                        onPressed: () => _writeReview(id),
                                      ),
                                    if (isClosed && hasReview)
                                      OutlinedButton.icon(
                                        onPressed: null,
                                        icon: const Icon(Icons.check_outlined),
                                        label: const Text("후기 작성됨"),
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

  Widget _buildEmpty() {
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  Navigator.pushNamed(context, '/login');
                });
              },
              child: const Text('로그인 하러 가기'),
            ),
          ],
        ),
      );
    }
    return const Center(child: Text("대여 내역이 없습니다."));
  }
}

class _Thumb extends StatelessWidget {
  final String url;
  final String phase;
  final VoidCallback? onDelete;

  const _Thumb({required this.url, required this.phase, this.onDelete});

  void _openViewer(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!Navigator.of(context).mounted) return;
      Navigator.pushNamed(context, '/photo_viewer', arguments: url);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => _openViewer(context),
      borderRadius: BorderRadius.circular(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 88,
              height: 88,
              child: Hero(
                tag: url,
                child: Image.network(
                  url,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: cs.surfaceVariant,
                    child: const Icon(Icons.broken_image),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                phase,
                style: TextStyle(
                  fontSize: 12,
                  color: cs.outline,
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                tooltip: '사진 삭제',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                iconSize: 18,
                icon: const Icon(Icons.delete_outline),
                onPressed: onDelete,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              "기간이 지난 대여는 백엔드에서 자동으로 CLOSED 처리됩니다. "
              "아래 토글로 종료 내역 포함 여부를 바꿀 수 있어요.",
              style: TextStyle(color: cs.onSurface.withOpacity(.8)),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChips extends StatelessWidget {
  final bool showClosed;
  final ValueChanged<bool> onChanged;

  const _FilterChips({
    super.key,
    required this.showClosed,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        ChoiceChip(
          label: const Text('진행 중만'),
          selected: !showClosed,
          onSelected: (sel) {
            if (sel) onChanged(false);
          },
          selectedColor: cs.primary.withOpacity(.15),
        ),
        const SizedBox(width: 8),
        ChoiceChip(
          label: const Text('종료 포함'),
          selected: showClosed,
          onSelected: (sel) {
            if (sel) onChanged(true);
          },
          selectedColor: cs.primary.withOpacity(.15),
        ),
      ],
    );
  }
}
