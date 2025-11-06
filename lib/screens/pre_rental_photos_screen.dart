// FILE: lib/screens/pre_rental_photos_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';

class PreRentalPhotosScreen extends StatefulWidget {
  const PreRentalPhotosScreen({
    super.key,
    this.rentalId,
    this.phase = 'BEFORE',
  });

  final int? rentalId;
  final String phase;

  @override
  State<PreRentalPhotosScreen> createState() => _PreRentalPhotosScreenState();
}

class _PreRentalPhotosScreenState extends State<PreRentalPhotosScreen> {
  final _api = ApiService.instance;

  late int _rentalId;
  late String _phase;

  bool _uploading = false;
  final List<String> _pickedPaths = [];
  final List<String> _uploaded = [];
  String? _notice;

  final _dateFmt = DateFormat('yyyy.MM.dd');

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    _phase = widget.phase; // 기본값 BEFORE

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
      _pickedPaths.addAll(
        res.files.where((f) => f.path != null).map((f) => f.path!),
      );
    });
  }

  (bool ok, String? message) _coerceOk(dynamic resp) {
    try {
      if (resp is bool) return (resp, null);
      if (resp is Map) {
        final ok = (resp['success'] == true) || (resp['ok'] == true);
        final msg = resp['message'] is String ? resp['message'] as String : null;
        return (ok, msg);
      }
      final str = resp?.toString();
      if (str != null && str.contains('success: true')) return (true, null);
      return (false, null);
    } catch (_) {
      return (false, null);
    }
  }

  Future<void> _uploadAll() async {
    if (_pickedPaths.length < 2 || _uploading) return;

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
          phase: _phase, // BEFORE
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

    // ✅ 업로드가 모두 끝나면 '교체' 네비게이션으로 마이페이지로 이동
    if (_uploaded.length == _pickedPaths.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('사진 업로드 완료')),
      );
      // 업로드 화면을 마이페이지로 교체 → 뒤로가면 이전 화면(대여/홈)으로 정상 복귀
      Navigator.pushReplacementNamed(
        context,
        '/mypage',
        arguments: {'focusRentalId': _rentalId, 'justUploaded': true},
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('일부 업로드 실패')),
      );
    }
  }

  // === UI 파트 ===

  Widget _tileAddButton() {
    return InkWell(
      onTap: _uploading ? null : _pickFiles,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 140,
        height: 110,
        decoration: BoxDecoration(
          color: const Color(0xFFF0F1F3),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Center(
          child: Icon(Icons.add, size: 36, color: Color(0xFF6B7280)),
        ),
      ),
    );
  }

  Widget _photoTile(String path) {
    final exists = File(path).existsSync();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 140,
          height: 110,
          decoration: BoxDecoration(
            color: const Color(0xFFF0F1F3),
            borderRadius: BorderRadius.circular(8),
            image: exists
                ? DecorationImage(image: FileImage(File(path)), fit: BoxFit.cover)
                : null,
          ),
          child: !exists
              ? const Center(
                  child: Icon(Icons.photo_camera_outlined, size: 32, color: Color(0xFF9CA3AF)),
                )
              : null,
        ),
        const SizedBox(height: 8),
        Text(
          _phase == 'BEFORE' ? '대여 전' : '반납 전',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Colors.black),
        ),
        const SizedBox(height: 2),
        Text(
          _dateFmt.format(DateTime.now()),
          style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
        ),
      ],
    );
  }

  Widget _placeholderTile() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 140,
          height: 110,
          decoration: BoxDecoration(
            color: const Color(0xFFF0F1F3),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Center(
            child: Icon(Icons.photo_camera_outlined, size: 32, color: Color(0xFF9CA3AF)),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _phase == 'BEFORE' ? '대여 전' : '반납 전',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Colors.black),
        ),
        const SizedBox(height: 2),
        Text(
          _dateFmt.format(DateTime.now()),
          style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final canSubmit = _pickedPaths.length >= 2 && !_uploading;

    final tiles = <Widget>[];
    for (final p in _pickedPaths) {
      tiles.add(_photoTile(p));
    }
    while (tiles.length < 2) {
      tiles.add(_placeholderTile());
    }
    tiles.add(_tileAddButton());

    return Scaffold(
      appBar: AppBar(
        title: const Text('대여인증'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [
                  BoxShadow(color: Color(0x0F000000), blurRadius: 12, offset: Offset(0, 4)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Center(
                    child: Text(
                      '사진 인증(2장이상)',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Wrap(spacing: 16, runSpacing: 16, children: tiles),
                  const SizedBox(height: 24),
                  const Text('대여 전 물건 상태를 여러 각도에서 촬영해 주세요',
                      style: TextStyle(fontSize: 13, color: Colors.black87)),
                  const SizedBox(height: 6),
                  const Text('촬영된 사진은 시간 및 위치 정보가 포함됩니다',
                      style: TextStyle(fontSize: 13, color: Colors.black54)),
                  if (_notice != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
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
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: SizedBox(
            height: 52,
            width: double.infinity,
            child: FilledButton(
              onPressed: canSubmit ? _uploadAll : null,
              child: _uploading
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('등록완료'),
            ),
          ),
        ),
      ),
    );
  }
}
