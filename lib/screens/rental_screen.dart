// FILE: lib/screens/rental_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';

class RentalScreen extends StatefulWidget {
  const RentalScreen({super.key});

  @override
  State<RentalScreen> createState() => _RentalScreenState();
}

class _RentalScreenState extends State<RentalScreen> {
  final _api = ApiService.instance;

  Map<String, dynamic>? _product; // 서버 응답 Map (정규화 전제)
  bool _loading = true;
  bool _creating = false;

  late DateTime _start;
  late DateTime _end;

  /// 차단일(자정 기준)
  Set<DateTime> _blocked = <DateTime>{};

  String? _notice;
  String? _error;
  bool _autoFixToNext = true;
  bool _autoOpenEndPicker = true;

  int? _routeProductId;
  bool _routeInited = false;

  @override
  void initState() {
    super.initState();
    final today = _day(DateTime.now());
    _start = today.add(const Duration(days: 1));
    _end = _start.add(const Duration(days: 1));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_routeInited) return;
    _routeInited = true;
    _routeProductId = _readProductIdFromRoute();
    _load();
  }

  // ===== Navigation helpers =====
  void _goHome() {
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/home', (r) => false);
  }

  Future<void> _goLogin({String? reason}) async {
    if (!mounted) return;
    final msg = reason ?? '로그인이 필요합니다.';
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('인증 필요'),
        content: Text(msg),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pushNamed(context, '/login');
            },
            child: const Text('로그인으로 가기'),
          ),
        ],
      ),
    );
  }

  // ===== Utils =====
  DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);
  String _fmtDate(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  String _formatNumber(num n) {
    final s = n.toStringAsFixed(0);
    final reg = RegExp(r'\B(?=(\d{3})+(?!\d))');
    return s.replaceAllMapped(reg, (m) => ',');
  }

  int? _readProductIdFromRoute() {
    final args = ModalRoute.of(context)?.settings.arguments;

    if (args == null) return null;
    if (args is int) return args;
    if (args is num) return args.toInt();
    if (args is String) return int.tryParse(args);
    if (args is Map) {
      final v = args['id'] ?? args['product_id'] ?? args['productId'];
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v);
    }
    return null;
  }

  // ===== Load =====
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _notice = null;
    });

    try {
      final id = _routeProductId;
      if (id == null) {
        throw Exception('라우팅 arguments에 product id가 없습니다.');
      }

      // 상품 정보
      final p = await _api.getProduct(id);
      if (p == null) throw Exception('getProduct($id) 응답이 비어 있습니다.');

      // 차단일
      Set<DateTime> blocked = <DateTime>{};
      try {
        blocked = await _api.getBlockedDates(id);
      } catch (_) {
        // 차단일 실패는致命적이지 않으므로 무시하고 진행
      }

      setState(() {
        _product = p;
        _blocked = blocked.map(_day).toSet(); // 일자 정규화
        _loading = false;
      });

      // 진입 즉시 한 방에 자동 보정
      _forceAdjust(from: _start, silent: true);
    } catch (e) {
      setState(() {
        _loading = false;
        _product = null;
        _error = e.toString();
        _notice = '상품 정보를 불러오지 못했습니다.';
      });
      // ignore: avoid_print
      print('[RentalScreen] load error: $e');
    }
  }

  // ===== Block & Range helpers =====
  bool _isBlocked(DateTime d) => _blocked.contains(_day(d));

  /// 서버가 종료일을 포함(inclusive)으로 볼 가능성까지 고려
  bool _rangeOverlapsBlocked(DateTime s, DateTime e) {
    for (DateTime d = _day(s); d.isBefore(e); d = d.add(const Duration(days: 1))) {
      if (_isBlocked(d)) return true;
    }
    // 종료일 당일까지 보수적으로 확인
    if (_isBlocked(_day(e))) return true;
    return false;
  }

  /// 내부 계산용: `from` 이후로 [nights]일 연속 비차단 구간 반환 (UI 갱신 안 함)
  (DateTime, DateTime)? _computeNextAvailableRange(int nights, DateTime from) {
    final want = nights.clamp(1, 365);
    DateTime base = _day(from);
    int run = 0;

    for (int i = 0; i < 366; i++) {
      final day = _day(base.add(Duration(days: i)));

      if (_isBlocked(day)) {
        run = 0;
        continue;
      }

      run += 1;
      if (run == want) {
        final end = day.add(const Duration(days: 1));
        final start = end.subtract(Duration(days: want));
        return (start, end);
      }
    }
    return null;
  }

  /// 현재 `_days` 유지하며 겹치면만 보정(최종 한 번만 setState)
  void _autoAdjustIfOverlap({required DateTime from}) {
    if (!_rangeOverlapsBlocked(_start, _end)) {
      if (_notice != null) {
        setState(() => _notice = null);
      }
      return;
    }
    _forceAdjust(from: from);
  }

  /// 강제 보정(최종 한 번만 setState). silent=true면 알림 없이 처리
  bool _forceAdjust({required DateTime from, bool silent = false}) {
    if (!_autoFixToNext) return false;

    final nights = _days;
    DateTime cursor = _day(from);
    const int MAX_ATTEMPTS = 365; // 1년 한도

    DateTime? pickS;
    DateTime? pickE;

    for (int attempt = 0; attempt < MAX_ATTEMPTS; attempt++) {
      final res = _computeNextAvailableRange(nights, cursor);
      if (res == null) break;

      final foundStart = res.$1;
      final foundEnd = res.$2;

      // 같은 기간을 또 찾으면 커서를 한 칸 더 뒤로 밀고 재시도
      final sameAsCurrent = (foundStart == _start && foundEnd == _end);
      if (sameAsCurrent) {
        cursor = foundEnd;
        continue;
      }

      pickS = foundStart;
      pickE = foundEnd;
      break;
    }

    if (pickS != null && pickE != null) {
      setState(() {
        _start = pickS!;
        _end = pickE!;
        _notice = silent ? null : '가능한 날짜로 자동 조정했어요. (${_fmtDate(_start)} ~ ${_fmtDate(_end)})';
      });
      return true;
    }

    if (!silent) {
      setState(() {
        _notice = '겹치는 예약으로 인접 가능한 날짜를 찾지 못했어요.';
      });
    }
    return false;
  }

  // ===== Pickers =====
  Future<void> _pickStart() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _start,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: '시작일 선택',
      fieldLabelText: '시작일',
      cancelText: '취소',
      confirmText: '확인',
      selectableDayPredicate: (d) => !_isBlocked(d),
      locale: const Locale('ko', 'KR'),
    );
    if (picked == null) return;

    setState(() {
      _start = _day(picked);
      if (!_end.isAfter(_start)) {
        _end = _start.add(const Duration(days: 1));
      }
    });

    _autoAdjustIfOverlap(from: _start);

    if (_autoOpenEndPicker) await _pickEnd();
  }

  Future<void> _pickEnd() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _end.isAfter(_start) ? _end : _start.add(const Duration(days: 1)),
      firstDate: _start.add(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: '종료일 선택',
      fieldLabelText: '종료일',
      cancelText: '취소',
      confirmText: '확인',
      selectableDayPredicate: (d) => !_isBlocked(d),
      locale: const Locale('ko', 'KR'),
    );
    if (picked == null) return;

    setState(() {
      _end = _day(picked);
      if (!_end.isAfter(_start)) {
        _end = _start.add(const Duration(days: 1));
      }
    });

    _autoAdjustIfOverlap(from: _start);
  }

  // ===== Submit =====
  Future<void> _submit() async {
    if (_product == null || _creating) return;

    // ✅ 토큰 가드
    if (!_api.isAuthenticated) {
      await _goLogin(reason: '대여 신청은 로그인 후 이용할 수 있어요.');
      return;
    }

    setState(() {
      _creating = true;
      _notice = null;
    });

    final productId =
        (_product!['id'] as int?) ??
        (_product!['product_id'] as int?) ??
        (_product!['productId'] as int?) ??
        0;

    const int MAX_TRIES = 12;
    DateTime s = _start;
    DateTime e = _end;
    DateTime retryCursor = s;
    dynamic successData;

    for (int attempt = 0; attempt < MAX_TRIES; attempt++) {
      final res = await _api.createRental(
        productId: productId,
        startDate: s,
        endDate: e,
        endExclusive: true,
      );

      if (res['ok'] == true) {
        successData = res['data'];
        break;
      }

      final status = res['status'] as int?;
      final body = res['data'];

      if (status == 401) {
        setState(() => _creating = false);
        await _goLogin(reason: '세션이 만료되었어요. 다시 로그인 후 대여를 진행해주세요.');
        return;
      }

      if (status == 409) {
        try {
          final latestBlocked = await _api.getBlockedDates(productId);
          _blocked = latestBlocked.map(_day).toSet();
        } catch (_) {}

        final next = _computeNextAvailableRange(
          e.difference(s).inDays.clamp(1, 365),
          retryCursor,
        );
        if (next == null) break;

        final foundStart = next.$1;
        final foundEnd = next.$2;

        final sameAsCurrent = (foundStart == s && foundEnd == e);
        if (sameAsCurrent) {
          retryCursor = foundEnd.add(const Duration(days: 1));
          continue;
        }

        s = foundStart;
        e = foundEnd;
        retryCursor = e.add(const Duration(days: 1));
        continue;
      }

      final msg = () {
        if (body is Map && body['detail'] != null) return '${body['detail']}';
        if (body is String && body.isNotEmpty) return body;
        return '대여 신청에 실패했습니다.';
      }();

      setState(() {
        _creating = false;
        _notice = '$msg (status: ${status ?? '-'})';
      });
      return;
    }

    // ✅ 성공 처리: 곧바로 사진 업로드 화면으로 전환
    final rentalId = _extractId(successData);
    setState(() => _creating = false);

    if (!mounted) return;
    if (rentalId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('대여는 생성됐지만 예약 ID를 확인하지 못했어요.')),
      );
      return;
    }

    Navigator.pushReplacementNamed(
      context,
      '/pre-photos',
      arguments: {
        'rentalId': rentalId,
        'productId': productId,
        'flow': 'pre', // BEFORE 업로드 플로우
      },
    );
  }

  int? _extractId(dynamic data) {
    if (data is Map) {
      final v = data['id'] ?? data['rental_id'] ?? data['rentalId'];
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v);
    }
    return null;
  }

  // ===== Derived =====
  int get _days => _end.difference(_start).inDays.clamp(1, 365);
  double get _daily => (_product?['daily_price'] as num?)?.toDouble() ?? 0;
  double get _deposit => (_product?['deposit'] as num?)?.toDouble() ?? 0;
  double get _rentTotal => _days * _daily;
  double get _fee => 0;
  double get _grand => _rentTotal + _deposit + _fee;

  // ===== UI =====
  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final p = _product;
    if (p == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('대여하기'),
          centerTitle: true,
          actions: [
            IconButton(
              tooltip: '홈으로',
              icon: const Icon(Icons.home_outlined),
              onPressed: _goHome,
            ),
          ],
        ),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('상품 정보를 불러오지 못했습니다.'),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.black54, fontSize: 12),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              FilledButton(onPressed: _load, child: const Text('다시 시도')),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('대여하기'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: '홈으로',
            icon: const Icon(Icons.home_outlined),
            onPressed: _goHome,
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF2C2F36),
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: 64,
                      height: 64,
                      color: const Color(0xFF3D414A),
                      child: const Icon(Icons.image, color: Colors.white70),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DefaultTextStyle(
                      style: const TextStyle(color: Colors.white),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (p['title'] ?? '').toString(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Text('일일 대여료 ₩${_formatNumber(_daily)}'),
                              const SizedBox(width: 12),
                              Text('보증금 ₩${_formatNumber(_deposit)}'),
                            ],
                          ),
                          if ((p['category'] ?? '').toString().isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text('카테고리 ${p['category']}',
                                  style: const TextStyle(color: Colors.white70)),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            Row(
              children: [
                Expanded(child: _DateChip(label: '시작일', value: _fmtDate(_start), onTap: _pickStart)),
                const SizedBox(width: 12),
                Expanded(child: _DateChip(label: '종료일', value: _fmtDate(_end), onTap: _pickEnd)),
              ],
            ),
            const SizedBox(height: 14),

            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF2C2F36),
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: DefaultTextStyle(
                style: const TextStyle(color: Colors.white),
                child: Column(
                  children: [
                    _row('대여 기간', '${_days}일'),
                    _row('일일 대여료', '₩${_formatNumber(_daily)}'),
                    _row('대여료 합계', '₩${_formatNumber(_rentTotal)}'),
                    _row('보증금', '₩${_formatNumber(_deposit)}'),
                    const Divider(color: Colors.white24),
                    _row('총 결제 예상', '₩${_formatNumber(_grand)}', bold: true),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            SwitchListTile.adaptive(
              title: const Text('종료일 피커 자동 열기'),
              value: _autoOpenEndPicker,
              onChanged: (v) => setState(() => _autoOpenEndPicker = v),
            ),
            SwitchListTile.adaptive(
              title: const Text('겹칠 때 다음 가능한 날짜로 자동 보정'),
              value: _autoFixToNext,
              onChanged: (v) => setState(() => _autoFixToNext = v),
            ),

            if (_notice != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF2FF),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_notice!, style: const TextStyle(color: Colors.black87)),
              )
            ],
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: _creating ? null : _submit,
              icon: _creating
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.calendar_month),
              label: Text(_creating ? '신청 중...' : '대여 신청'),
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(String k, String v, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          const SizedBox(width: 4),
          Text(k, style: const TextStyle(color: Colors.white70)),
          const Spacer(),
          Text(
            v,
            style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _DateChip extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;
  const _DateChip({required this.label, required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF2C2F36),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              const Icon(Icons.event, color: Colors.white70),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    const SizedBox(height: 2),
                    Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
