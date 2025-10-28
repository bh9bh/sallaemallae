import 'dart:typed_data';
import 'dart:io' as io; // ✅ File 미리보기/업로드용 (웹 빌드 시에는 조건부 임포트로 전환 필요)
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/api_service.dart';

class AddProductScreen extends StatefulWidget {
  const AddProductScreen({super.key});

  @override
  State<AddProductScreen> createState() => _AddProductScreenState();
}

class _AddProductScreenState extends State<AddProductScreen> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _desc = TextEditingController();
  final _category = TextEditingController();
  final _region = TextEditingController();
  final _daily = TextEditingController();
  final _deposit = TextEditingController();

  bool _loading = false;

  String? _pickedPath;      // 데스크톱/모바일 경로
  Uint8List? _pickedBytes;  // 웹(또는 일부 플랫폼)에서의 바이트
  String? _pickedName;

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    _category.dispose();
    _region.dispose();
    _daily.dispose();
    _deposit.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: kIsWeb,
    );
    if (res == null || res.files.isEmpty) return;

    final f = res.files.first;
    setState(() {
      _pickedName = f.name;
      if (kIsWeb) {
        _pickedBytes = f.bytes;
        _pickedPath = null;
      } else {
        _pickedPath = f.path;
        _pickedBytes = f.bytes; // 일부 플랫폼은 bytes도 같이 제공
      }
    });
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    if (_pickedPath == null && _pickedBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('상품 이미지를 선택해주세요.')),
      );
      return;
    }

    final daily = double.tryParse(_daily.text.replaceAll(',', '').trim());
    final deposit = double.tryParse(_deposit.text.replaceAll(',', '').trim());
    if (daily == null || deposit == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('가격/보증금은 숫자만 입력해주세요.')),
      );
      return;
    }

    setState(() => _loading = true);

    bool ok = false;
    try {
      if (kIsWeb) {
        // 현재 ApiService는 파일 경로 기반 업로드만 지원
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('현재 웹 빌드는 이미지 업로드를 지원하지 않습니다. 모바일/데스크톱에서 시도해주세요.')),
        );
      } else {
        ok = await ApiService().createProductWithImage(
          title: _title.text.trim(),
          description: _desc.text.trim().isEmpty ? null : _desc.text.trim(),
          category: _category.text.trim().isEmpty ? null : _category.text.trim(),
          region: _region.text.trim().isEmpty ? null : _region.text.trim(),
          dailyPrice: daily,
          deposit: deposit,
          filePath: _pickedPath!, // 경로 필수
        );
      }
    } finally {
      setState(() => _loading = false);
    }

    if (!mounted) return;

    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('상품이 등록되었습니다.')),
      );
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('상품 등록에 실패했습니다. 다시 시도해주세요.')),
      );
    }
  }

  Widget _buildImagePreview() {
    // 1) 메모리 바이트가 있으면 우선 사용 (웹/일부 플랫폼)
    if (_pickedBytes != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: AspectRatio(
          aspectRatio: 1,
          child: Image.memory(_pickedBytes!, fit: BoxFit.cover),
        ),
      );
    }

    // 2) 경로가 있고 웹이 아니면 File 기반 미리보기
    if (_pickedPath != null && !kIsWeb) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: AspectRatio(
          aspectRatio: 1,
          child: Image.file(
            io.File(_pickedPath!),
            fit: BoxFit.cover,
          ),
        ),
      );
    }

    // 3) 아직 선택 안 함 (또는 웹에서 경로만 있고 bytes 없음)
    return Container(
      height: 120,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.grey[200],
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Center(
        child: Text(
          _pickedName == null ? '이미지 미리보기' : '($_pickedName) 미리보기 불가',
          style: const TextStyle(color: Colors.black54),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('상품 등록')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: ListView(
                  children: [
                    // 이미지 선택 & 미리보기
                    Text('대표 이미지', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    SizedBox(height: 120, child: _buildImagePreview()),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: _loading ? null : _pickImage,
                        icon: const Icon(Icons.image),
                        label: Text(_pickedName == null ? '이미지 선택' : '다른 이미지 선택'),
                      ),
                    ),

                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _title,
                      decoration: const InputDecoration(
                        labelText: '상품명 *',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) => (v ?? '').trim().isEmpty ? '상품명을 입력해주세요.' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _desc,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: '설명',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _category,
                            decoration: const InputDecoration(
                              labelText: '카테고리',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _region,
                            decoration: const InputDecoration(
                              labelText: '지역',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _daily,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: '일일 대여료(숫자) *',
                              border: OutlineInputBorder(),
                              prefixText: '₩ ',
                            ),
                            validator: (v) {
                              final t = (v ?? '').trim();
                              if (t.isEmpty) return '대여료를 입력해주세요.';
                              if (double.tryParse(t.replaceAll(',', '')) == null) {
                                return '숫자만 입력해주세요.';
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _deposit,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: '보증금(숫자) *',
                              border: OutlineInputBorder(),
                              prefixText: '₩ ',
                            ),
                            validator: (v) {
                              final t = (v ?? '').trim();
                              if (t.isEmpty) return '보증금을 입력해주세요.';
                              if (double.tryParse(t.replaceAll(',', '')) == null) {
                                return '숫자만 입력해주세요.';
                              }
                              return null;
                            },
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),
                    SizedBox(
                      height: 48,
                      child: FilledButton.icon(
                        onPressed: _loading ? null : _submit,
                        icon: _loading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.cloud_upload_outlined),
                        label: Text(_loading ? '업로드 중…' : '상품 등록'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
