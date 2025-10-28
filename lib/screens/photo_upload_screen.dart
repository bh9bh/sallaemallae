import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/api_service.dart';

class PhotoUploadScreen extends StatefulWidget {
  const PhotoUploadScreen({super.key});

  @override
  State<PhotoUploadScreen> createState() => _PhotoUploadScreenState();
}

class _PhotoUploadScreenState extends State<PhotoUploadScreen> {
  final _api = ApiService();

  int? _rentalId;                 // 전달받은 대여 ID
  String _phase = 'BEFORE';       // BEFORE | AFTER
  String? _filePath;              // 선택한 파일 경로

  bool _uploading = false;
  String? _msg;                   // 화면 하단 경고/안내 문구

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;

    // arguments로 int만 오는 현재 라우팅에 맞춤
    if (args is int) {
      _rentalId = args;
    } else {
      _rentalId = null;
    }
  }

  Future<void> _pickFile() async {
    // 이미지 하나만 선택
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: false, // 경로 기반 사용
    );
    if (!mounted) return;

    if (result != null && result.files.isNotEmpty) {
      final path = result.files.single.path;
      setState(() {
        _filePath = path;
        _msg = null;
      });
    }
  }

  void _clearFile() {
    setState(() {
      _filePath = null;
      _msg = null;
    });
  }

  Future<void> _upload() async {
    // 기본 유효성
    if (_rentalId == null) {
      setState(() => _msg = "잘못된 접근입니다. (대여 ID가 없습니다)");
      return;
    }
    if (_filePath == null || _filePath!.isEmpty) {
      setState(() => _msg = "먼저 사진을 선택해주세요.");
      return;
    }
    // 로컬 파일 존재 체크(모바일/데스크톱)
    final f = File(_filePath!);
    if (!await f.exists()) {
      setState(() => _msg = "파일을 찾을 수 없습니다. 다시 선택해주세요.");
      return;
    }

    setState(() {
      _uploading = true;
      _msg = null;
    });

    final ok = await _api.uploadPhoto(_rentalId!, _filePath!, _phase);

    if (!mounted) return;
    setState(() => _uploading = false);

    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("$_phase 사진 업로드 완료")),
      );
      // 이전 화면(MyPage)로 true 반환 → 새로고침 트리거
      Navigator.pop(context, true);
    } else {
      setState(() => _msg = "업로드에 실패했습니다. 네트워크/서버 상태를 확인해주세요.");
    }
  }

  @override
  Widget build(BuildContext context) {
    // rentalId가 없으면 바로 안내
    if (_rentalId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text("사진 업로드")),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("잘못된 접근입니다. (대여 ID가 전달되지 않았습니다.)"),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("뒤로가기"),
              ),
            ],
          ),
        ),
      );
    }

    final preview = _filePath != null ? File(_filePath!) : null;

    return Scaffold(
      appBar: AppBar(title: const Text("사진 업로드")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("대여 ID: $_rentalId", style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),

            // BEFORE / AFTER 선택
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'BEFORE', label: Text('대여 전 (BEFORE)')),
                ButtonSegment(value: 'AFTER', label: Text('반납 후 (AFTER)')),
              ],
              selected: {_phase},
              onSelectionChanged: (s) => setState(() => _phase = s.first),
            ),

            const SizedBox(height: 16),

            // 파일 선택 & 경로 표시 & 초기화
            Row(
              children: [
                FilledButton.icon(
                  onPressed: _uploading ? null : _pickFile,
                  icon: const Icon(Icons.photo_library),
                  label: const Text("사진 선택"),
                ),
                const SizedBox(width: 12),
                if (_filePath != null) ...[
                  Expanded(
                    child: Text(
                      _filePath!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: '선택 초기화',
                    onPressed: _uploading ? null : _clearFile,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ],
            ),

            const SizedBox(height: 16),

            // 미리보기
            Expanded(
              child: Center(
                child: preview == null
                    ? Text(
                        "선택된 이미지가 없습니다.",
                        style: TextStyle(color: Theme.of(context).colorScheme.outline),
                      )
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(
                          preview,
                          fit: BoxFit.cover,
                          height: 280,
                        ),
                      ),
              ),
            ),

            if (_msg != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_msg!, style: const TextStyle(color: Colors.red)),
              ),

            // 업로드 버튼
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: (_uploading || _filePath == null) ? null : _upload,
                child: _uploading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text("업로드"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
