// FILE: lib/screens/mypage_screen.dart
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../common/route_observer.dart'; // RouteAware 자동 새로고침

class MyPageScreen extends StatefulWidget {
  const MyPageScreen({super.key});

  @override
  State<MyPageScreen> createState() => _MyPageScreenState();
}

class _MyPageScreenState extends State<MyPageScreen> with RouteAware {
  final ApiService _api = ApiService.instance;

  bool _loading = true;
  String? _error;
  bool _showClosed = false;

  List<Map<String, dynamic>> _rentals = [];
  final Map<int, String> _productTitleCache = {}; // product_id -> title 캐시

  // ⬇️ 업로드 직후 자동으로 사진 시트를 열기 위한 인자 저장 + 재오픈 루프 방지
  int? _focusRentalId;
  bool _justUploaded = false;
  bool _argsConsumed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // ---------- RouteAware: 뒤로 복귀 시 자동 새로고침 ----------
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // arguments는 화면 생애주기 동안 단 1회만 소비해서 무한 오픈 방지
    if (!_argsConsumed) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is Map) {
        final id = args['focusRentalId'];
        if (id is int) _focusRentalId = id;
        if (id is num) _focusRentalId = id.toInt();
        if (id is String) _focusRentalId = int.tryParse(id);
        _justUploaded = args['justUploaded'] == true;
      }
      _argsConsumed = true;
    }

    final route = ModalRoute.of(context);
    if (route != null) routeObserver.subscribe(this, route);
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPopNext() {
    _load();
    super.didPopNext();
  }
  // ----------------------------------------------------------

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
      final List<Map<String, dynamic>> data =
          await _api.getMyRentals(includeClosed: _showClosed);

      // 캐시 채우기 (가능하면 응답에서 바로, 없으면 디테일 호출)
      for (final raw in data) {
        final Map<String, dynamic> r = Map<String, dynamic>.from(raw);
        final int? pid = (r['product_id'] as num?)?.toInt();
        if (pid != null && !_productTitleCache.containsKey(pid)) {
          final String? t =
              (r['product_title'] ?? r['title'] ?? r['name'])?.toString();
          if (t != null && t.isNotEmpty) {
            _productTitleCache[pid] = t;
          } else {
            // 없으면 상세 호출해서 캐시
            _fetchProductTitle(pid);
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _rentals = data.map((e) => Map<String, dynamic>.from(e)).toList();
        _loading = false;
      });

      // ⬇️ 업로드 직후에만 1회 자동으로 해당 대여의 사진 시트를 띄움
      if (_justUploaded && _focusRentalId != null && mounted) {
        _justUploaded = false; // 바로 꺼서 반복 오픈 방지
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _openPhotosSheet(_focusRentalId!);
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = "내 대여 내역을 불러오지 못했습니다.";
        _loading = false;
      });
    }
  }

  Future<void> _fetchProductTitle(int productId) async {
    final dynamic json = await _api.getProduct(productId);
    final String title = (json is Map)
        ? (((json['name'] ?? json['title'])?.toString()) ?? '')
        : '';
    if (title.isNotEmpty && mounted) {
      setState(() {
        _productTitleCache[productId] = title;
      });
    }
  }

  Future<void> _logout() async {
    await _api.logout();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/login', (r) => false);
  }

  // ----------------- Helpers -----------------
  String _fmtDate(dynamic iso) {
    final s = (iso ?? '').toString();
    return s.length >= 10 ? s.substring(0, 10) : s;
  }

  DateTime? _parseDate(dynamic iso) {
    if (iso == null) return null;
    try {
      return DateTime.parse(iso.toString()).toLocal();
    } catch (_) {
      return null;
    }
  }

  DateTime _onlyDate(DateTime d) => DateTime(d.year, d.month, d.day);
  bool _isAfterToday(DateTime? d) {
    if (d == null) return false;
    final today = _onlyDate(DateTime.now().toLocal());
    return _onlyDate(d).isAfter(today);
  }

  bool _isTodayOrBefore(DateTime? d) {
    if (d == null) return false;
    final today = _onlyDate(DateTime.now().toLocal());
    return !_onlyDate(d).isAfter(today);
  }

  Color _statusColor(String s, BuildContext ctx) {
    final u = s.toUpperCase();
    if (u.contains('RETURN')) return Colors.green;
    if (u.contains('CANCEL') || u.contains('CLOSED') || u.contains('EXPIRED')) {
      return Colors.red;
    }
    return Theme.of(ctx).colorScheme.primary;
  }
  // -------------------------------------------

  // ------------- Actions -------------
  Future<void> _actCancel(int rentalId) async {
    final ok = await _api.cancelRental(rentalId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? "대여가 취소되었습니다." : "대여 취소 실패")),
    );
    if (ok) _load();
  }

  Future<void> _actRequestReturn(int rentalId) async {
    final ok = await _api.requestReturn(rentalId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? "반납 요청 완료" : "반납 요청 실패")),
    );
    if (ok) _load();
  }

  Future<void> _actConfirmReturn(int rentalId) async {
    final ok = await _api.confirmReturn(rentalId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? "반납이 완료되었습니다." : "반납 완료 처리 실패")),
    );
    if (ok) _load();
  }
  // ------------------------------------

  void _openProductDetail(int productId) {
    Navigator.pushNamed(context, '/product', arguments: productId);
  }

  // ⬇️ 대여 사진 바텀시트 (전체보기 버튼 제거)
  Future<void> _openPhotosSheet(int rentalId) async {
    final photos = await _api.getPhotosByRental(rentalId);
    if (!mounted) return;

    String? _urlOf(Map<String, dynamic> m) {
      final v = m['url'] ??
          m['image_url'] ??
          m['imageUrl'] ??
          m['thumbnail_url'] ??
          m['thumbnailUrl'] ??
          m['file_url'] ??
          m['fileUrl'] ??
          m['path'] ??
          m['file'] ??
          m['filepath'] ??
          m['filePath'];
      if (v is String && v.isNotEmpty) return _api.absolute(v);
      return null;
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (_) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 헤더: 제목만 (전체보기 제거)
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '대여 사진',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 8),
                if (photos.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text('등록된 사진이 없습니다.'),
                  )
                else
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: photos.length,
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: 1,
                    ),
                    itemBuilder: (_, i) {
                      final u = _urlOf(photos[i]);
                      if (u == null) {
                        return Container(
                          color: const Color(0xFFE5E7EB),
                          child: const Icon(Icons.broken_image_outlined),
                        );
                      }
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(u, fit: BoxFit.cover),
                      );
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.maybePop(context),
          tooltip: '뒤로',
        ),
        centerTitle: true,
        title: const Text('마이페이지'),
        actions: [
          IconButton(
            tooltip: '로그아웃',
            icon: const Icon(Icons.logout),
            onPressed: _logout,
          )
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _rentals.isEmpty
                  ? ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
                      children: [
                        _FilterChips(
                          showClosed: _showClosed,
                          onChanged: (v) {
                            setState(() => _showClosed = v);
                            _load();
                          },
                        ),
                        const SizedBox(height: 80),
                        const Center(child: Text("대여 내역이 없습니다.")),
                      ],
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
                      itemCount: _rentals.length + 1,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        if (i == 0) {
                          return _FilterChips(
                            showClosed: _showClosed,
                            onChanged: (v) {
                              setState(() => _showClosed = v);
                              _load();
                            },
                          );
                        }

                        final Map<String, dynamic> r =
                            Map<String, dynamic>.from(_rentals[i - 1]);

                        final int id = (r['id'] as num).toInt();
                        final int? productId = (r['product_id'] as num?)?.toInt();

                        final String status = (r['status'] ?? '').toString();
                        final String start = _fmtDate(r['start_date']);
                        final String end = _fmtDate(r['end_date']);
                        final DateTime? startDT = _parseDate(r['start_date']);
                        final String uStatus = status.toUpperCase();
                        final bool isClosed =
                            uStatus.contains('CLOSED') || uStatus.contains('EXPIRED');

                        // 제목: 캐시에 name/title 폴백 저장되어 있음
                        final String title = (productId != null)
                            ? (_productTitleCache[productId] ?? '상품 #$productId')
                            : '상품';

                        // 버튼 표시 정책
                        final bool canCancel = !isClosed &&
                            (uStatus == 'PENDING' || uStatus == 'ACTIVE') &&
                            _isAfterToday(startDT);

                        final bool canRequestReturn =
                            !isClosed && uStatus == 'ACTIVE' && _isTodayOrBefore(startDT);

                        final bool canConfirmReturn = uStatus == 'RETURN_REQUESTED';

                        return _RentalCard(
                          title: title,
                          start: start,
                          end: end,
                          status: status,
                          statusColor: _statusColor(status, context),
                          cs: cs,
                          onCancel: canCancel ? () => _actCancel(id) : null,
                          onRequestReturn:
                              canRequestReturn ? () => _actRequestReturn(id) : null,
                          onConfirmReturn:
                              canConfirmReturn ? () => _actConfirmReturn(id) : null,
                          onOpenDetail:
                              (productId != null) ? () => _openProductDetail(productId) : null,
                          // ⬇️ 썸네일 클릭 시 사진 보기
                          onOpenPhotos: () => _openPhotosSheet(id),
                        );
                      },
                    ),
            ),
    );
  }
}

class _RentalCard extends StatelessWidget {
  const _RentalCard({
    required this.title,
    required this.start,
    required this.end,
    required this.status,
    required this.statusColor,
    required this.cs,
    this.onCancel,
    this.onRequestReturn,
    this.onConfirmReturn,
    this.onOpenDetail,
    this.onOpenPhotos,
  });

  final String title;
  final String start;
  final String end;
  final String status;
  final Color statusColor;
  final ColorScheme cs;

  final VoidCallback? onCancel;
  final VoidCallback? onRequestReturn;
  final VoidCallback? onConfirmReturn;
  final VoidCallback? onOpenDetail;
  final VoidCallback? onOpenPhotos;

  @override
  Widget build(BuildContext context) {
    final card = Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      color: cs.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 좌측 썸네일(카메라) → 사진 바텀시트 열기
            InkWell(
              onTap: onOpenPhotos,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: cs.surfaceVariant,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.photo_camera_outlined, size: 28),
              ),
            ),
            const SizedBox(width: 12),

            // 본문
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 제목 + 상태배지
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: onOpenDetail,
                          child: Text(
                            title,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      Container(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          status,
                          style: TextStyle(
                              color: statusColor,
                              fontWeight: FontWeight.w600,
                              fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text("$start  ~  $end", style: const TextStyle(fontSize: 13)),
                  const SizedBox(height: 6),

                  // 액션 버튼들
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (onOpenDetail != null)
                        _PillButton.icon(
                          icon: Icons.open_in_new,
                          label: '상세 보기',
                          onPressed: onOpenDetail,
                        ),
                      if (onRequestReturn != null)
                        _PillButton.icon(
                          icon: Icons.assignment_return_outlined,
                          label: '반납 요청',
                          onPressed: onRequestReturn,
                        ),
                      if (onConfirmReturn != null)
                        _PillButton.icon(
                          icon: Icons.check_circle_outline,
                          label: '반납 완료',
                          onPressed: onConfirmReturn,
                          filled: true,
                        ),
                      if (onCancel != null)
                        _PillButton.icon(
                          icon: Icons.cancel_outlined,
                          label: '대여 취소',
                          onPressed: onCancel,
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

    // 카드 전체 탭으로도 상세 이동 허용 (버튼/제스처 우선순위 유지)
    return onOpenDetail != null ? InkWell(onTap: onOpenDetail, child: card) : card;
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton.icon({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.filled = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final shape = StadiumBorder(side: BorderSide(color: cs.outlineVariant));
    final style = filled
        ? FilledButton.styleFrom(
            shape: shape,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          )
        : OutlinedButton.styleFrom(
            shape: shape,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          );

    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    );

    return filled
        ? FilledButton(onPressed: onPressed, style: style, child: child)
        : OutlinedButton(onPressed: onPressed, style: style, child: child);
  }
}

class _FilterChips extends StatelessWidget {
  final bool showClosed;
  final ValueChanged<bool> onChanged;

  const _FilterChips({super.key, required this.showClosed, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
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
      ),
    );
  }
}
