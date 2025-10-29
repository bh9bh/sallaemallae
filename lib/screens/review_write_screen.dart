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
  String? _productTitle;

  @override
  void initState() {
    super.initState();
    // arguments 안전 접근
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is Map) {
        _rentalId = args['rentalId'] as int?;
        _productTitle = args['productTitle']?.toString();
      } else if (args is int) {
        _rentalId = args;
      }
      if (_rentalId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('잘못된 접근입니다. (rentalId 없음)')),
        );
        Navigator.pop(context, false);
      } else {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_rentalId == null) return;
    if (_rating < 1 || _rating > 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('별점을 1~5 사이로 선택해주세요.')),
      );
      return;
    }

    setState(() => _submitting = true);
    final ok = await _api.createReview(
      rentalId: _rentalId!,
      rating: _rating,
      comment: _comment.text.trim().isEmpty ? null : _comment.text.trim(),
    );
    setState(() => _submitting = false);

    if (!mounted) return;

    if (ok != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('후기가 저장되었습니다.')),
      );
      Navigator.pop(context, true); // 성공 → true 반환
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('후기 저장에 실패했습니다.')),
      );
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('후기 작성'),
      ),
      body: _rentalId == null
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
