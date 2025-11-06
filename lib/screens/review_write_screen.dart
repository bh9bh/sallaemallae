// FILE: lib/screens/review_write_screen.dart
import 'package:flutter/material.dart';
import '../services/api_service.dart';

class ReviewWriteScreen extends StatefulWidget {
  const ReviewWriteScreen({super.key});

  @override
  State<ReviewWriteScreen> createState() => _ReviewWriteScreenState();
}

class _ReviewWriteScreenState extends State<ReviewWriteScreen> {
  final _api = ApiService.instance;

  int _rating = 5;
  final _comment = TextEditingController();
  bool _submitting = false;

  int? _rentalId;
  int? _productId;
  String? _productTitle;

  @override
  void initState() {
    super.initState();
    // 라우트 인자 안전 접근
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final args = ModalRoute.of(context)?.settings.arguments;

      // rentalId / productId 파싱 (int/string/map 전부 허용)
      if (args is int) {
        _rentalId = args;
      } else if (args is String) {
        _rentalId = int.tryParse(args);
      } else if (args is Map) {
        final rid = args['rentalId'];
        final pid = args['productId'];
        _rentalId = rid is int ? rid : (rid is String ? int.tryParse(rid) : _rentalId);
        _productId = pid is int ? pid : (pid is String ? int.tryParse(pid) : _productId);
        _productTitle = args['productTitle']?.toString();
      }

      // 필수값 체크
      if (_rentalId == null || _productId == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('잘못된 접근입니다. (rentalId / productId 확인)')),
          );
          Navigator.pop(context, false);
        }
        return;
      }

      // productTitle 없으면 한 번만 조회해서 UX 개선
      if ((_productTitle == null || _productTitle!.isEmpty) && _productId != null) {
        try {
          final p = await _api.getProduct(_productId!);
          final t = (p is Map) ? (p['title']?.toString() ?? '') : '';
          if (mounted && t.isNotEmpty) {
            setState(() => _productTitle = t);
          }
        } catch (_) {
          // 제목 조회 실패는 무시 가능 (필수 정보가 아님)
        }
      }

      if (mounted) setState(() {}); // 초기 렌더링
    });
  }

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (_rentalId == null || _productId == null) return;

    if (_rating < 1 || _rating > 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('별점을 1~5 사이로 선택해주세요.')),
      );
      return;
    }

    setState(() => _submitting = true);

    final content = _comment.text.trim();
    try {
      // ApiService의 반환 타입이 bool 또는 Map({ok:true} 등)이어도 안전 처리
      final res = await _api.createReview(
        productId: _productId!,
        rentalId: _rentalId!,
        rating: _rating,
        content: content.isEmpty ? null : content,
      );

      final bool ok = switch (res) {
        bool b => b,
        Map m => (m['ok'] == true) || (m['success'] == true),
        _ => res != null, // 널이 아니면 성공으로 보는 느슨한 계약
      };

      if (!mounted) return;

      if (ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('후기가 저장되었습니다.')),
        );
        Navigator.pop(context, true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('후기 저장에 실패했습니다.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('후기 저장 중 오류가 발생했습니다: $e')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _buildStars(ColorScheme cs) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(5, (i) {
        final idx = i + 1;
        final filled = idx <= _rating;
        return IconButton(
          onPressed: _submitting ? null : () => setState(() => _rating = idx),
          iconSize: 34,
          icon: Icon(
            filled ? Icons.star : Icons.star_border,
            color: filled ? cs.primary : cs.outline,
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ready = (_rentalId != null && _productId != null);

    return Scaffold(
      appBar: AppBar(
        title: const Text('후기 작성'),
      ),
      body: !ready
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.all(16),
              child: ListView(
                children: [
                  if ((_productTitle ?? '').isNotEmpty) ...[
                    Text(
                      _productTitle!,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Center(child: _buildStars(cs)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _comment,
                    maxLines: 6,
                    maxLength: 500,
                    decoration: const InputDecoration(
                      labelText: '코멘트 (선택)',
                      hintText: '제품 상태, 사용 경험 등을 적어주세요.',
                      border: OutlineInputBorder(),
                    ),
                    enabled: !_submitting,
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 48,
                    child: FilledButton.icon(
                      onPressed: _submitting ? null : _submit,
                      icon: _submitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_outlined),
                      label: const Text('후기 저장'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
