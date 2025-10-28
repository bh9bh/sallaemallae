import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../models/product.dart';

class RentalScreen extends StatefulWidget {
  const RentalScreen({super.key});

  @override
  State<RentalScreen> createState() => _RentalScreenState();
}

class _RentalScreenState extends State<RentalScreen> {
  final _api = ApiService();

  Product? _product;
  bool _loading = true;
  String? _error;

  DateTime _start = DateTime.now();
  DateTime _end = DateTime.now().add(const Duration(days: 1));

  // 예약 불가 날짜(자정 기준으로 정규화해서 보관)
  final Set<DateTime> _blockedDates = {};
  bool _loadingBlocked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;
    int? productId;
    if (args is int) productId = args;
    if (args is Map && args['productId'] is int) productId = args['productId'] as int?;

    if (productId == null) {
      setState(() {
        _loading = false;
        _error = "잘못된 접근입니다. (상품 ID 없음)";
      });
      return;
    }
    _fetch(productId);
  }

  Future<void> _fetch(int productId) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final p = await _api.getProduct(productId);
      if (!mounted) return;
      if (p == null) {
        setState(() {
          _loading = false;
          _error = "상품 정보를 불러오지 못했습니다.";
        });
      } else {
        setState(() {
          _product = p;
          _loading = false;
        });
        await _loadBlockedDates(p.id);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = "상품 정보를 불러오지 못했습니다.";
      });
    }
  }

  // === Blocked Dates ===

  DateTime _d(DateTime d) => DateTime(d.year, d.month, d.day);

  bool _isBlockedDay(DateTime d) => _blockedDates.contains(_d(d));

  bool _isRangeBlocked(DateTime a, DateTime b) {
    var cur = _d(a);
    final end = _d(b);
    while (!cur.isAfter(end)) {
      if (_isBlockedDay(cur)) return true;
      cur = cur.add(const Duration(days: 1));
    }
    return false;
  }

  DateTime _nextAvailableDay(DateTime from) {
    var d = _d(from);
    // 무한루프 방지용 한도
    for (int i = 0; i < 730; i++) {
      if (!_isBlockedDay(d)) return d;
      d = d.add(const Duration(days: 1));
    }
    return _d(from);
  }

  Future<void> _loadBlockedDates(int productId) async {
    setState(() => _loadingBlocked = true);
    try {
      final ranges = await _api.getBlockedDates(productId);
      _blockedDates.clear();

      // ranges: [{"start":"..."|"start_date":"..." , "end":"..."|"end_date":"..."}]
      for (final r in ranges) {
        final rawStart = (r['start'] ?? r['start_date'])?.toString();
        final rawEnd = (r['end'] ?? r['end_date'])?.toString();
        if (rawStart == null || rawEnd == null) continue;

        final s = DateTime.parse(rawStart).toLocal();
        final e = DateTime.parse(rawEnd).toLocal();
        var d = _d(s);
        final last = _d(e);
        while (!d.isAfter(last)) {
          _blockedDates.add(d);
          d = d.add(const Duration(days: 1));
        }
      }

      // 현재 선택한 구간이 막힌 날과 겹치면 자동 보정
      if (_isRangeBlocked(_start, _end)) {
        final today = _d(DateTime.now());
        // 시작 보정: 오늘과 현재 시작일 중 더 큰 날부터 다음 가능한 날 찾기
        final base = _start.isAfter(today) ? _start : today;
        final newStart = _nextAvailableDay(base);
        final newEnd = newStart.add(const Duration(days: 1));
        setState(() {
          _start = newStart;
          _end = newEnd;
        });
      }
    } catch (_) {
      // 실패해도 submit에서 가용성 체크로 2차 방어
    } finally {
      if (mounted) setState(() => _loadingBlocked = false);
    }
  }

  // ---------- Helpers (intl 대체) ----------
  String _fmtDate(DateTime d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return "${d.year}-${two(d.month)}-${two(d.day)}";
  }

  String _fmtMoney(num v) {
    final s = v.toStringAsFixed(0);
    final reg = RegExp(r'\B(?=(\d{3})+(?!\d))');
    return s.replaceAllMapped(reg, (m) => ',');
  }

  // inclusive-day count (요금 표시용)
  int get _days {
    final d = _end.difference(_start).inDays + 1;
    return d < 1 ? 1 : d;
  }

  Future<void> _pickStart() async {
    final now = DateTime.now();
    final today = _d(now);

    final picked = await showDatePicker(
      context: context,
      initialDate: _start.isBefore(today) ? today : _start,
      firstDate: today,
      lastDate: DateTime(today.year + 2),
      selectableDayPredicate: (d) => !_isBlockedDay(d),
    );
    if (picked == null) return;

    final pickedD = _d(picked);
    if (_isBlockedDay(pickedD)) return; // 안전 가드

    setState(() {
      _start = pickedD;
      // 종료일이 시작일보다 크도록 최소 1일 보장 + 구간에 막힌 날 없도록 보정
      var candidateEnd = _d(_end.isAfter(_start) ? _end : _start.add(const Duration(days: 1)));
      // 시작~종료 사이에 막힌 날이 있다면 종료일을 늘리거나 시작일을 뒤로 이동
      if (_isRangeBlocked(_start, candidateEnd)) {
        // 종료를 뒤로 미는 전략
        var e = candidateEnd;
        for (int i = 0; i < 60 && _isRangeBlocked(_start, e); i++) {
          e = e.add(const Duration(days: 1));
        }
        candidateEnd = e;
      }
      _end = candidateEnd;
    });
  }

  Future<void> _pickEnd() async {
    final first = _d(_start);
    final firstDate = first.add(const Duration(days: 1));
    final init = _end.isAfter(firstDate) ? _end : firstDate;

    final picked = await showDatePicker(
      context: context,
      initialDate: _d(init),
      firstDate: firstDate,
      lastDate: DateTime(first.year + 2),
      selectableDayPredicate: (d) {
        if (_isBlockedDay(d)) return false;
        // 시작~후보 종료 구간 중 하나라도 막힌 날 있으면 선택 불가
        var cur = first;
        final end = _d(d);
        while (!cur.isAfter(end)) {
          if (_isBlockedDay(cur)) return false;
          cur = cur.add(const Duration(days: 1));
        }
        return true;
      },
    );
    if (picked == null) return;

    final pickedD = _d(picked);
    if (pickedD.isBefore(firstDate)) return; // 안전 가드
    if (_isRangeBlocked(first, pickedD)) return;

    setState(() {
      _end = pickedD;
    });
  }

  Future<void> _submit() async {
    if (_product == null) return;

    if (!_api.isAuthenticated) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("로그인이 필요합니다.")),
      );
      if (!mounted) return;
      Navigator.pushNamed(context, '/login');
      return;
    }

    // 백엔드 정책: 종료일은 시작일 '다음날부터' 가능 (strict)
    if (!_end.isAfter(_start)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("종료일은 시작일 다음날부터 선택 가능합니다.")),
      );
      return;
    }

    // 로컬 검증: 구간에 막힌 날이 있으면 프런트에서 즉시 차단
    if (_isRangeBlocked(_start, _end)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("선택하신 기간에 이미 예약이 있습니다. 다른 날짜를 선택해주세요.")),
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    // 1) 서버 가용성 확인(2차 방어)
    final available = await _api.checkAvailability(_product!.id, _start, _end);
    if (!mounted) return;
    if (!available) {
      Navigator.pop(context); // progress
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('이미 해당 기간에 예약이 있습니다. 다른 날짜를 선택해주세요.')),
      );
      return;
    }

    // 2) 생성
    final res = await _api.createRental(_product!.id, _start, _end);

    if (!mounted) return;
    Navigator.pop(context); // progress

    if (res != null) {
      final rentalId = (res['id'] as num?)?.toInt();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("대여가 생성되었습니다.")),
      );

      // ✅ 생성 직후 결제 유도
      if (rentalId != null) {
        _promptCheckout(rentalId);
      } else {
        // id가 없으면 이전 화면으로만 복귀
        Navigator.pop(context, true);
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("대여 생성에 실패했습니다.")),
      );
    }
  }

  // ================== 결제 유도 바텀시트 ==================
  void _promptCheckout(int rentalId) {
    final days = _days;
    final rent = (_product?.dailyPrice ?? 0) * days;
    final deposit = _product?.deposit ?? 0;
    final total = rent + deposit;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            bottom: 16 + MediaQuery.of(ctx).viewInsets.bottom,
            top: 8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("결제하기", style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 6),
              Text(
                "대여가 생성되었습니다. 바로 결제하시겠어요?",
                style: TextStyle(color: cs.outline),
              ),
              const SizedBox(height: 12),
              _kv("대여 기간", "$days일"),
              _kv("대여료 합계", "₩ ${_fmtMoney(rent)}"),
              _kv("보증금", "₩ ${_fmtMoney(deposit)}"),
              const Divider(height: 18),
              _kv("총 결제 금액", "₩ ${_fmtMoney(total)}", bold: true),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.pop(ctx); // bottom sheet 닫기
                        Navigator.pop(context, true); // 이전 화면으로
                      },
                      child: const Text("나중에 하기"),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      icon: const Icon(Icons.payment_outlined),
                      label: const Text("지금 결제"),
                      onPressed: () async {
                        // 로딩 표시
                        showDialog(
                          context: context,
                          barrierDismissible: false,
                          builder: (_) => const Center(child: CircularProgressIndicator()),
                        );
                        final ok = await _api.mockCheckout(rentalId);
                        if (!mounted) return;
                        Navigator.pop(context); // progress
                        Navigator.pop(ctx); // bottom sheet

                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(ok ? "결제가 완료되었습니다." : "결제 실패"),
                          ),
                        );

                        // 결제 성공 시 마이페이지로 이동해 확인
                        if (ok && mounted) {
                          Navigator.pushNamedAndRemoveUntil(context, '/mypage', (r) => false);
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Widget _kv(String k, String v, {bool bold = false}) {
    final style = bold
        ? const TextStyle(fontWeight: FontWeight.w700)
        : const TextStyle(fontWeight: FontWeight.w500);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(k, style: style)),
          Text(v, style: style),
        ],
      ),
    );
  }
  // ======================================================

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text("대여하기")),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _product == null
                  ? const Center(child: Text("상품 정보가 없습니다."))
                  : SafeArea(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 720),
                          child: ListView(
                            padding: const EdgeInsets.all(16),
                            children: [
                              // 상품 카드
                              Card(
                                elevation: 0,
                                color: theme.colorScheme.surfaceContainerHighest,
                                clipBehavior: Clip.antiAlias,
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      _ProductThumb(imageUrl: _product!.imageUrl),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(_product!.title, style: theme.textTheme.titleLarge),
                                            const SizedBox(height: 6),
                                            Text(
                                              _product!.description ?? "",
                                              maxLines: 3,
                                              overflow: TextOverflow.ellipsis,
                                              style: theme.textTheme.bodyMedium?.copyWith(
                                                color: theme.colorScheme.outline,
                                              ),
                                            ),
                                            const SizedBox(height: 10),
                                            Wrap(
                                              spacing: 12,
                                              runSpacing: 8,
                                              children: [
                                                _ChipText("일일 대여료 ₩ ${_fmtMoney(_product!.dailyPrice)}"),
                                                _ChipText("보증금 ₩ ${_fmtMoney(_product!.deposit)}"),
                                                if (_product!.category != null && _product!.category!.isNotEmpty)
                                                  _ChipText("카테고리 ${_product!.category}"),
                                                if (_product!.region != null && _product!.region!.isNotEmpty)
                                                  _ChipText("지역 ${_product!.region}"),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                              const SizedBox(height: 16),

                              // 날짜 선택
                              Row(
                                children: [
                                  Expanded(
                                    child: _DateTile(
                                      label: "시작일",
                                      dateText: _fmtDate(_start),
                                      onTap: _loadingBlocked ? null : _pickStart,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _DateTile(
                                      label: "종료일",
                                      dateText: _fmtDate(_end),
                                      onTap: _loadingBlocked ? null : _pickEnd,
                                    ),
                                  ),
                                ],
                              ),
                              if (_loadingBlocked) ...[
                                const SizedBox(height: 8),
                                Text(
                                  "예약 가능 날짜를 불러오는 중...",
                                  style: TextStyle(color: theme.colorScheme.outline),
                                ),
                              ],

                              const SizedBox(height: 16),

                              // 금액 요약
                              _SummaryBox(
                                days: _days,
                                dailyPrice: _product!.dailyPrice,
                                deposit: _product!.deposit,
                                formatter: _fmtMoney,
                              ),

                              const SizedBox(height: 20),

                              SizedBox(
                                height: 48,
                                child: FilledButton.icon(
                                  onPressed: _submit,
                                  icon: const Icon(Icons.assignment_turned_in_outlined),
                                  label: const Text("대여 신청"),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
    );
  }
}

class _ProductThumb extends StatelessWidget {
  final String? imageUrl;
  const _ProductThumb({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 110,
        height: 110,
        child: imageUrl == null || imageUrl!.isEmpty
            ? Container(
                color: theme.colorScheme.surfaceVariant,
                child: const Icon(Icons.image_not_supported_outlined),
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
    );
  }
}

class _ChipText extends StatelessWidget {
  final String text;
  const _ChipText(this.text);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(.6),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _DateTile extends StatelessWidget {
  final String label;
  final String dateText;
  final VoidCallback? onTap;

  const _DateTile({
    required this.label,
    required this.dateText,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.dividerColor),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            Icon(Icons.event, color: theme.colorScheme.primary),
            const SizedBox(width: 10),
            Text(label, style: theme.textTheme.bodyMedium),
            const Spacer(),
            Text(dateText, style: theme.textTheme.titleMedium),
          ],
        ),
      ),
    );
  }
}

class _SummaryBox extends StatelessWidget {
  final int days;
  final double dailyPrice;
  final double deposit;
  final String Function(num) formatter;

  const _SummaryBox({
    required this.days,
    required this.dailyPrice,
    required this.deposit,
    required this.formatter,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rent = dailyPrice * days;
    final total = rent + deposit;

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            _line("대여 기간", "$days일"),
            _line("일일 대여료", "₩ ${formatter(dailyPrice)}"),
            _line("대여료 합계", "₩ ${formatter(rent)}"),
            _line("보증금", "₩ ${formatter(deposit)}"),
            const Divider(height: 16),
            _line("총 결제 예상", "₩ ${formatter(total)}", bold: true),
          ],
        ),
      ),
    );
  }

  Widget _line(String left, String right, {bool bold = false}) {
    final style = bold
        ? const TextStyle(fontWeight: FontWeight.w700)
        : const TextStyle(fontWeight: FontWeight.w500);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(left, style: style)),
          Text(right, style: style),
        ],
      ),
    );
  }
}
