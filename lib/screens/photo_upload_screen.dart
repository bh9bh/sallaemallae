// FILE: lib/screens/photo_upload_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/api_service.dart';

class PhotoUploadScreen extends StatefulWidget {
  const PhotoUploadScreen({
    super.key,
    this.rentalId,          // ← optional
    this.phase = 'BEFORE',  // 기본값
  });

  final int? rentalId;
  final String phase;

  @override
  State<PhotoUploadScreen> createState() => _PhotoUploadScreenState();
}

class _PhotoUploadScreenState extends State<PhotoUploadScreen> {
  final _api = ApiService.instance;

  late int _rentalId;
  late String _phase;

  bool _uploading = false;
  final List<String> _pickedPaths = [];
  final List<String> _uploaded = [];
  String? _notice;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    _phase = widget.phase;

    int fromArgs() {
      final a = ModalRoute.of(context)?.settings.arguments;
      if (a is Map) {
        final v = a['rentalId'] ?? a['id'];
        if (v is int) return v;
        if (v is num) return v.toInt();
        if (v is String) return int.tryParse(v) ?? 0;
      } else if (a is int) {
        return a;
      }
      return 0;
    }

    _rentalId = widget.rentalId ?? fromArgs();
  }

  Future<void> _pickFiles() async {
    final res = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: false,
      type: FileType.image,
    );
    if (res == null) return;
    setState(() {
      _pickedPaths
        ..clear()
        ..addAll(res.files.where((f) => f.path != null).map((f) => f.path!));
    });
  }

  /// 서버 응답(dynamic) → (ok, message)로 안전 변환
  (bool ok, String? message) _coerceOk(dynamic resp) {
    try {
      if (resp is bool) return (resp, null);
      if (resp is Map) {
        final ok = (resp['success'] == true) || (resp['ok'] == true);
        final msg = resp['message'] is String ? resp['message'] as String : null;
        return (ok, msg);
      }
      // dio Response같은 케이스를 넓게 커버
      final str = resp?.toString();
      if (str != null && str.contains('success: true')) return (true, null);
      return (false, null);
    } catch (_) {
      return (false, null);
    }
  }

  Future<void> _uploadAll() async {
    if (_pickedPaths.isEmpty || _uploading) return;

    if (_rentalId <= 0) {
      setState(() => _notice = '유효하지 않은 대여 번호입니다. 이전 화면에서 다시 시도해주세요.');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('대여 ID가 없습니다.')),
      );
      return;
    }

    setState(() {
      _uploading = true;
      _notice = null;
      _uploaded.clear();
    });

    for (final p in _pickedPaths) {
      try {
        final resp = await _api.uploadRentalPhoto(
          rentalId: _rentalId,
          phase: _phase,
          filePath: p,
        );

        final (ok, msg) = _coerceOk(resp);
        if (ok) {
          _uploaded.add(p);
        } else {
          setState(() {
            _notice = msg ?? '일부 사진 업로드에 실패했습니다.';
          });
        }
      } catch (e) {
        setState(() {
          _notice = '업로드 중 오류: $e';
        });
      }
    }

    setState(() => _uploading = false);

    if (!mounted) return;

    if (_uploaded.length == _pickedPaths.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('사진 업로드 완료')),
      );
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('일부 업로드 실패')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final canUpload = _pickedPaths.isNotEmpty && !_uploading;

    return Scaffold(
      appBar: AppBar(
        title: Text(_phase == 'BEFORE' ? '대여 전 상태 사진' : '반납 전 상태 사진'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF2C2F36),
                borderRadius: BorderRadius.circular(12),
              ),
              child: DefaultTextStyle(
                style: const TextStyle(color: Colors.white),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text('가이드', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    SizedBox(height: 8),
                    Text('• 전체 샷 1장 (제품 전면/측면 식별 가능)'),
                    Text('• 손상/오염 의심 부위 클로즈업'),
                    Text('• 일련번호/식별표시가 있으면 함께 촬영'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            FilledButton.icon(
              onPressed: _uploading ? null : _pickFiles,
              icon: const Icon(Icons.photo_library),
              label: const Text('사진 선택'),
            ),
            const SizedBox(height: 12),

            if (_pickedPaths.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _pickedPaths.map((p) {
                  return Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2C2F36),
                      borderRadius: BorderRadius.circular(8),
                      image: File(p).existsSync()
                          ? DecorationImage(image: FileImage(File(p)), fit: BoxFit.cover)
                          : null,
                    ),
                    child: File(p).existsSync()
                        ? null
                        : const Icon(Icons.image_not_supported, color: Colors.white70),
                  );
                }).toList(),
              ),

            if (_notice != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF2FF),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_notice!, style: const TextStyle(color: Colors.black87)),
              ),
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
              onPressed: canUpload ? _uploadAll : null,
              icon: _uploading
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.cloud_upload),
              label: Text(_uploading ? '업로드 중...' : '업로드'),
            ),
          ),
        ),
      ),
    );
  }
}
