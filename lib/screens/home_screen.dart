// FILE: lib/screens/home_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import '../services/api_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ApiService _api = ApiService.instance;

  bool _loading = true; // 목록/초기 로딩(콘텐츠 영역만 가린다)
  bool _searching = false; // 검색 로딩
  String? _error;

  // 원본 데이터와 화면 표시용 분리
  List<dynamic> _allItems = [];
  List<dynamic> _items = [];

  final Map<int, Map<String, dynamic>> _ratingCache = {};
  final Set<int> _loadingRating = {};

  final TextEditingController _query = TextEditingController();
  String _lastQuery = '';

  /// 카테고리 정의
  static const List<Map<String, dynamic>> cats = [
    {"key": "living", "label": "생활/가전", "icon": Icons.home_filled},
    {"key": "kitchen", "label": "주방/요리", "icon": Icons.restaurant},
    {"key": "electronics", "label": "PC/전자기기", "icon": Icons.computer},
    {"key": "creator", "label": "촬영/크리에이터", "icon": Icons.videocam},
    {"key": "camping", "label": "캠핑/레저", "icon": Icons.park},
    {"key": "fashion", "label": "의류/패션 소품", "icon": Icons.checkroom},
    {"key": "hobby", "label": "취미/게임", "icon": Icons.sports_esports},
    {"key": "kids", "label": "유아/키즈", "icon": Icons.child_friendly},
  ];

  // 카테고리 바/칩 위치 파악용 키들
  final GlobalKey _catListKey = GlobalKey();
  final List<GlobalKey> _catKeys =
      List<GlobalKey>.generate(cats.length, (_) => GlobalKey());

  // 선택 상태: 초기에는 "선택 없음"
  int _selectedCategoryIndex = -1;

  // 카테고리 가로 스크롤 컨트롤러
  final ScrollController _catCtrl = ScrollController();

  // 데스크톱/웹에서도 마우스 드래그로 좌우 스크롤 허용
  final ScrollBehavior _dragEverywhere = const _AnyDeviceScroll();

  // 카테고리 모드(전체 보기)인지 여부
  bool _categoryMode = false;
  String? _categoryKey; // 현재 로드된 카테고리 키(중복탭 판정)

  static const int _fallbackLimit = 20;

  @override
  void initState() {
    super.initState();
    _catCtrl.addListener(_onCatScroll);
    _loadPopular();
  }

  @override
  void dispose() {
    _query.dispose();
    _catCtrl.removeListener(_onCatScroll);
    _catCtrl.dispose();
    super.dispose();
  }

  void _onCatScroll() {
    if (!mounted) return;
    // 경계 버튼 깜빡임 줄이려고 스로틀 없이 가볍게 갱신
    setState(() {});
  }

  // ------------------ 스크롤 유틸: 선택 칩을 바로 중앙 근처로 ------------------

  Future<void> _animateCatToIndex(int index) async {
    if (!_catCtrl.hasClients) return;
    if (index < 0 || index >= _catKeys.length) return;

    final listCtx = _catListKey.currentContext;
    final chipCtx = _catKeys[index].currentContext;
    if (listCtx == null || chipCtx == null) return;

    final listBox = listCtx.findRenderObject() as RenderBox?;
    final chipBox = chipCtx.findRenderObject() as RenderBox?;
    if (listBox == null || chipBox == null) return;

    // 뷰포트와 칩의 전역 좌표
    final listGlobal = listBox.localToGlobal(Offset.zero);
    final chipGlobal = chipBox.localToGlobal(Offset.zero);

    final viewportWidth = listBox.size.width;
    final chipWidth = chipBox.size.width;

    // 칩의 왼쪽이 뷰포트에서 얼마나 떨어져 있는지
    final deltaX = chipGlobal.dx - listGlobal.dx;

    // 칩을 뷰포트 중앙 근처로 이동시키기 위한 타깃 오프셋
    double target = _catCtrl.offset + deltaX - (viewportWidth - chipWidth) / 2;

    // 안전 범위 내 클램프
    final max = _catCtrl.position.maxScrollExtent;
    target = target.clamp(0.0, max);

    // 점프 없이 부드럽게
    await _catCtrl.animateTo(
      target,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
    );
  }

  // ------------------ 데이터 로드(인기/폴백) ------------------

  Future<void> _loadPopular() async {
    setState(() {
      _loading = true;           // 콘텐츠 영역만 로딩으로 가린다 (카테고리 바는 유지)
      _error = null;
      _categoryMode = false;
      _categoryKey = null;
      _selectedCategoryIndex = -1; // 인기 모드 들어오면 선택 해제
    });

    try {
      // 1) 서버 인기 API
      final popular = await _api.getPopularProducts(limit: _fallbackLimit);
      List<dynamic> result = popular;

      // 2) 폴백: 전체에서 상위 N
      if (result.isEmpty) {
        final all = await _api.getProducts();
        result = all.take(_fallbackLimit).toList();
      }

      if (!mounted) return;
      _allItems = result;

      // 인기/검색 화면에서는 카테고리 토큰 필터 적용 (선택 없음이면 전체)
      _applyCategoryFilter(_selectedCategoryIndex, fromCategoryLoad: false);

      setState(() {
        _loading = false;
      });

      // 보여주는 항목만 평점 프리패치
      final ids = _items
          .map((e) => (e is Map ? (e['id'] as int?) : null))
          .whereType<int>()
          .toList();
      _prefetchRatings(ids);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '인기상품을 불러오지 못했습니다.';
        _loading = false;
      });
    }
  }

  Future<void> _loadCategoryAll(String key) async {
    setState(() {
      _loading = true; // 콘텐츠 영역만 로딩
      _error = null;
      _categoryMode = true;
      _categoryKey = key;
    });

    try {
      final result = await _api.searchProducts(category: key, size: 100);

      if (!mounted) return;
      _allItems = result;
      _items = List<dynamic>.from(_allItems); // 재필터링 X

      setState(() {
        _loading = false;
      });

      // 보여주는 항목만 평점 프리패치
      final ids = _items
          .map((e) => (e is Map ? (e['id'] as int?) : null))
          .whereType<int>()
          .toList();
      _prefetchRatings(ids);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '카테고리 목록을 불러오지 못했습니다.';
        _loading = false;
      });
    }
  }

  Future<void> _prefetchRatings(List<int> ids) async {
    for (final id in ids) {
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

  void _openDetail(int productId) {
    Navigator.pushNamed(context, '/product', arguments: productId);
  }

  Future<void> _goAdd() async {
    final result = await Navigator.pushNamed(context, '/add_product');
    if (result == true && mounted) {
      await _loadPopular();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('새 상품이 등록되어 목록을 갱신했어요.')),
      );
    }
  }

  // ------------------ 검색 ------------------

  Future<void> _runSearch(String raw) async {
    final q = raw.trim();
    _lastQuery = q;
    if (q.isEmpty) {
      // 비우면 인기/초기 목록으로 복귀
      _query.clear();
      await _loadPopular();
      return;
    }

    setState(() {
      _searching = true;
      _error = null;
      _categoryMode = false;
      _categoryKey = null;
      // _selectedCategoryIndex = -1; // 원하면 유지/해제 선택
    });

    try {
      List<dynamic> result = [];
      try {
        final serverResult = await _api.searchProducts(query: q, size: 60);
        result = serverResult;
      } catch (_) {
        final all = await _api.getProducts();
        result = _localFilter(all, q);
      }

      if (!mounted) return;

      _allItems = result;
      _applyCategoryFilter(_selectedCategoryIndex, fromCategoryLoad: false);

      // 보여주는 항목만 평점 프리패치
      final ids = _items
          .map((e) => (e is Map ? (e['id'] as int?) : null))
          .whereType<int>()
          .toList();
      _prefetchRatings(ids);
    } catch (e) {
      if (!mounted) return;
      _error = '검색 중 오류가 발생했어요.';
    } finally {
      if (mounted) {
        _searching = false;
        setState(() {});
      }
    }
  }

  List<dynamic> _localFilter(List<dynamic> data, String q) {
    final lower = q.toLowerCase();
    bool match(dynamic it) {
      if (it is! Map) return false;
      String s(Object? v) => (v ?? '').toString().toLowerCase();

      final title = s(it['title']);
      final region = s(it['region'] ?? it['location']);
      final category = s(it['category'] ?? it['cat']);
      final desc = s(it['description'] ?? it['desc']);
      final tags = (it['tags'] is List)
          ? (it['tags'] as List).map((e) => e.toString().toLowerCase()).join(' ')
          : '';

      return title.contains(lower) ||
          region.contains(lower) ||
          category.contains(lower) ||
          desc.contains(lower) ||
          tags.contains(lower);
    }

    return data.where(match).toList();
  }

  void _resetSearch() {
    _query.clear();
    _lastQuery = '';
    _loadPopular();
  }

  // ------------------ 카테고리 필터링 ------------------

  List<String>? _tokensForKey(String? key) {
    switch (key) {
      case 'living':
        return ['living', 'home', 'household', 'appliance', '가전', '생활'];
      case 'kitchen':
        return ['kitchen', 'cook', '주방', '요리'];
      case 'electronics':
        return ['electronics', 'pc', 'computer', '디지털', '전자기기'];
      case 'creator':
        return ['creator', 'camera', 'photo', 'video', '촬영', '크리에이터'];
      case 'camping':
        return ['camp', 'camping', 'leisure', 'outdoor', '캠핑', '레저'];
      case 'fashion':
        return ['fashion', 'apparel', 'clothes', '패션', '의류', '소품'];
      case 'hobby':
        return ['hobby', 'game', 'gaming', '취미', '게임'];
      case 'kids':
        return ['kids', 'child', 'baby', '유아', '키즈'];
      default:
        return null; // 전체
    }
  }

  bool _matchCategory(dynamic item, List<String> tokens) {
    if (item is! Map) return false;
    final raw = (item['category'] ?? item['cat'] ?? '').toString().toLowerCase();
    if (raw.isEmpty) return false;
    for (final t in tokens) {
      if (raw.contains(t.toLowerCase())) return true;
    }
    return false;
  }

  void _applyCategoryFilter(int index, {required bool fromCategoryLoad}) {
    _selectedCategoryIndex = index;

    // 카테고리 API로 전체를 이미 받아온 경우에는 재필터링하지 않고 그대로 사용
    if (fromCategoryLoad || _categoryMode) {
      _items = List<dynamic>.from(_allItems);
      setState(() {});
      return;
    }

    if (index < 0 || index >= cats.length) {
      // 선택 없음 → 전체
      _items = List<dynamic>.from(_allItems);
      setState(() {});
      return;
    }

    final key = (cats[index]['key'] as String?) ?? '';
    final tokens = _tokensForKey(key);

    if (tokens == null) {
      _items = List<dynamic>.from(_allItems);
    } else {
      _items = _allItems.where((e) => _matchCategory(e, tokens)).toList();
    }
    setState(() {});
  }

  Future<void> _onTapCategory(int tappedIndex) async {
    final key = (cats[tappedIndex]['key'] as String?) ?? '';
    final isSame = _categoryKey == key;

    if (_categoryMode && isSame) {
      // 같은 카테고리를 다시 누르면 인기 화면으로 복귀 + 선택 해제
      _selectedCategoryIndex = -1;
      await _loadPopular();
      return;
    }

    // 다른 카테고리: 선택 표시 → 데이터 로드 → (프레임 반영 후) 부드러운 스크롤
    _selectedCategoryIndex = tappedIndex;
    await _loadCategoryAll(key);

    // 프레임 반영 직후 수동 오프셋 계산으로 중앙 근처 정렬 (초기 점프 없음)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _animateCatToIndex(tappedIndex);
    });
  }

  // ------------------ 카테고리 바 스크롤 버튼 ------------------

  Future<void> _scrollCategories(bool forward) async {
    if (!_catCtrl.hasClients) return;
    final distance = 220.0;
    final max = _catCtrl.position.maxScrollExtent;
    final target =
        (forward ? _catCtrl.offset + distance : _catCtrl.offset - distance)
            .clamp(0.0, max);
    await _catCtrl.animateTo(
      target,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  // ------------------ UI ------------------

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFFF5F6F8);
    final cs = Theme.of(context).colorScheme;

    final bool showLeft = _catCtrl.hasClients && _catCtrl.offset > 2.0;
    final bool showRight = _catCtrl.hasClients &&
        _catCtrl.offset < (_catCtrl.position.maxScrollExtent - 2.0);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        titleSpacing: 12,
        centerTitle: true,
        title: const Text('살래말래', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            tooltip: '로그아웃',
            icon: const Icon(Icons.logout_rounded, color: Color(0xFFE53935)),
            onPressed: _logout,
          ),
        ],
      ),
      body: SafeArea(
        // 항상 같은 상단 구조 유지: 검색바 + 카테고리 바는 로딩 중에도 유지
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
          children: [
            _SearchBar(
              controller: _query,
              searching: _searching,
              onSubmitted: _runSearch,
              onSearchPressed: () => _runSearch(_query.text),
              onClear: _resetSearch,
            ),
            const SizedBox(height: 10),

            // ------- 카테고리 바 + 좌우 버튼 -------
            SizedBox(
              height: 48,
              child: Stack(
                children: [
                  ScrollConfiguration(
                    behavior: _dragEverywhere,
                    child: ListView.separated(
                      key: _catListKey, // 뷰포트 기준점
                      controller: _catCtrl,
                      scrollDirection: Axis.horizontal,
                      itemCount: cats.length,
                      padding: const EdgeInsets.only(left: 2, right: 52),
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (_, i) {
                        final m = cats[i];
                        return Container(
                          key: _catKeys[i], // 각 칩 식별
                          child: _CategoryPill(
                            label: m['label'] as String,
                            icon: m['icon'] as IconData,
                            selected: i == _selectedCategoryIndex,
                            onTap: () => _onTapCategory(i),
                          ),
                        );
                      },
                    ),
                  ),
                  // 왼쪽 버튼
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    child: IgnorePointer(
                      ignoring: !showLeft,
                      child: AnimatedOpacity(
                        opacity: showLeft ? 1 : 0,
                        duration: const Duration(milliseconds: 120),
                        child: _EdgeScrollButton(
                          direction: AxisDirection.left,
                          onTap: () => _scrollCategories(false),
                        ),
                      ),
                    ),
                  ),
                  // 오른쪽 버튼
                  Positioned(
                    right: 0,
                    top: 0,
                    bottom: 0,
                    child: IgnorePointer(
                      ignoring: !showRight,
                      child: AnimatedOpacity(
                        opacity: showRight ? 1 : 0,
                        duration: const Duration(milliseconds: 120),
                        child: _EdgeScrollButton(
                          direction: AxisDirection.right,
                          onTap: () => _scrollCategories(true),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            Text(
              _categoryMode ? '카테고리 전체 상품' : '현재 인기상품',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),

            // ------- 콘텐츠 영역(로딩/에러/목록만 바뀜) -------
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 24),
                child: Center(
                  child: Column(
                    children: [
                      Text(_error!, style: const TextStyle(color: Colors.red)),
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        onPressed: () {
                          if (_categoryMode && _categoryKey != null) {
                            _loadCategoryAll(_categoryKey!);
                          } else if (_lastQuery.isEmpty) {
                            _loadPopular();
                          } else {
                            _runSearch(_lastQuery);
                          }
                        },
                        icon: const Icon(Icons.refresh),
                        label: const Text('다시 시도'),
                      ),
                    ],
                  ),
                ),
              )
            else if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 36),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_items.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 48),
                child: Center(
                  child: Text(
                    _lastQuery.isEmpty
                        ? '해당 카테고리의 상품이 없어요.'
                        : '검색 결과가 없어요.',
                    style: TextStyle(color: cs.outline),
                  ),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (_, i) {
                  final p = _items[i];
                  final id = (p is Map ? p['id'] : null) as int?;
                  final title =
                      (p is Map ? p['title'] : null) as String? ?? '제목 없음';

                  // price_per_day, dailyPrice 등 폴백 처리
                  final priceRaw = (p is Map)
                      ? (p['daily_price'] ??
                          p['dailyPrice'] ??
                          p['price_per_day'] ??
                          p['pricePerDay'])
                      : null;
                  final price = (priceRaw is num)
                      ? priceRaw.toDouble()
                      : double.tryParse('${priceRaw ?? ''}') ?? 0.0;

                  // 이미지/지역 폴백
                  final img = (p is Map
                          ? (p['image_url'] ??
                              p['imageUrl'] ??
                              p['thumbnail_url'])
                          : null)
                      as String?;
                  final region =
                      (p is Map ? (p['region'] ?? p['location']) : null)
                          as String?;

                  final summary = (id != null) ? _ratingCache[id] : null;
                  final hasData = summary != null &&
                      summary['avg'] != null &&
                      summary['count'] != null &&
                      (summary['count'] as int) > 0;
                  final avg =
                      hasData ? (summary!['avg'] as num).toDouble() : null;
                  final count = hasData ? (summary!['count'] as int) : null;

                  if (id != null &&
                      summary == null &&
                      !_loadingRating.contains(id)) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) _fetchRating(id);
                    });
                  }

                  return _ProductMiniCard(
                    title: title,
                    region: region,
                    price: price,
                    imageUrl:
                        img != null && img.isNotEmpty ? _api.absolute(img) : null,
                    ratingAvg: avg,
                    ratingCount: count,
                    onTap: () {
                      if (id != null) _openDetail(id);
                    },
                  );
                },
              ),
          ],
        ),
      ),
      // ✅ 하단 네비게이션에서 '채팅' 제거 (3개 탭: 홈 / 상품등록 / 마이페이지)
      bottomNavigationBar: NavigationBar(
        selectedIndex: 0,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: '홈'),
          NavigationDestination(icon: Icon(Icons.add_box_outlined), label: '상품등록'),
          NavigationDestination(icon: Icon(Icons.person_outline), label: '마이페이지'),
        ],
        onDestinationSelected: (i) {
          switch (i) {
            case 0:
              // 홈(현재 화면)
              break;
            case 1:
              _goAdd();
              break;
            case 2:
              Navigator.pushNamed(context, '/mypage');
              break;
          }
        },
      ),
    );
  }

  Future<void> _logout() async {
    await _api.logout();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/login', (r) => false);
  }
}

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final void Function(String) onSubmitted;
  final VoidCallback onSearchPressed;
  final VoidCallback onClear;
  final bool searching;

  const _SearchBar({
    required this.controller,
    required this.onSubmitted,
    required this.onSearchPressed,
    required this.onClear,
    this.searching = false,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onSubmitted: onSubmitted,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: '검색어, 태그검색',
        hintStyle: const TextStyle(color: Color(0xFF9AA0A6)),
        prefixIcon: IconButton(
          icon: const Icon(Icons.search),
          onPressed: onSearchPressed,
          tooltip: '검색',
        ),
        suffixIcon: searching
            ? const Padding(
                padding: EdgeInsets.all(12.0),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : (controller.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: onClear,
                    tooltip: '지우기',
                  )),
        filled: true,
        fillColor: const Color(0xFFF1F2F5),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Colors.black26),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Colors.black26),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Colors.black54, width: 1.4),
        ),
      ),
      style: const TextStyle(color: Colors.black87),
      cursorColor: Colors.black87,
    );
  }
}

/// 아이콘 + 라벨 칩
class _CategoryPill extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback? onTap;

  const _CategoryPill({
    required this.label,
    required this.icon,
    this.selected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = selected ? const Color(0xFF111827) : const Color(0xFFEDEEF1);
    final fg = selected ? Colors.white : Colors.black87;
    final border = selected ? Colors.black : Colors.black12;

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: border),
        ),
        alignment: Alignment.center,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: fg),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700, color: fg),
            ),
          ],
        ),
      ),
    );
  }
}

class _EdgeScrollButton extends StatelessWidget {
  final AxisDirection direction;
  final VoidCallback onTap;

  const _EdgeScrollButton({
    super.key,
    required this.direction,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bool isRight = direction == AxisDirection.right;
    return Container(
      width: 46,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: isRight ? Alignment.centerLeft : Alignment.centerRight,
          end: isRight ? Alignment.centerRight : Alignment.centerLeft,
          colors: const [Color(0x00FFFFFF), Color(0xFFFFFFFF)],
        ),
      ),
      alignment: isRight ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.only(right: isRight ? 4 : 0, left: isRight ? 0 : 4),
        child: Material(
          color: Colors.black87,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 32,
              height: 32,
              child: Transform.rotate(
                angle: isRight ? 0 : 3.14159, // 좌/우 방향 아이콘 회전
                child: const Icon(
                  Icons.chevron_right,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProductMiniCard extends StatelessWidget {
  final String title;
  final String? region;
  final double price;
  final String? imageUrl;
  final double? ratingAvg;
  final int? ratingCount;
  final VoidCallback onTap;

  const _ProductMiniCard({
    super.key,
    required this.title,
    required this.region,
    required this.price,
    required this.imageUrl,
    required this.onTap,
    this.ratingAvg,
    this.ratingCount,
  });

  String _formatNumber(num n) {
    final s = n.toStringAsFixed(0);
    final reg = RegExp(r'\B(?=(\d{3})+(?!\d))');
    return s.replaceAllMapped(reg, (m) => ',');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.black12),
        ),
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 64,
                height: 64,
                child: (imageUrl == null || imageUrl!.isEmpty)
                    ? Container(
                        color: theme.colorScheme.surfaceVariant,
                        child: const Icon(Icons.image_outlined),
                      )
                    : Image.network(
                        imageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: theme.colorScheme.surfaceVariant,
                          child: const Icon(Icons.broken_image),
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Colors.black87)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text('₩ ${_formatNumber(price)} /일',
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Colors.black87)),
                      const Spacer(),
                      if ((region ?? '').isNotEmpty)
                        Row(
                          children: [
                            const Icon(Icons.place, size: 14),
                            const SizedBox(width: 3),
                            Text(region!, style: TextStyle(fontSize: 12, color: cs.outline)),
                          ],
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (ratingAvg != null && ratingCount != null && ratingCount! > 0)
                    Row(
                      children: [
                        const Icon(Icons.star, size: 16, color: Colors.amber),
                        const SizedBox(width: 4),
                        Text('${ratingAvg!.toStringAsFixed(1)} ($ratingCount)',
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w600)),
                      ],
                    )
                  else
                    const SizedBox(height: 10),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 모든 입력 장치에서 드래그 스크롤 가능하도록 하는 ScrollBehavior
class _AnyDeviceScroll extends ScrollBehavior {
  const _AnyDeviceScroll();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
        PointerDeviceKind.unknown,
      };
}
