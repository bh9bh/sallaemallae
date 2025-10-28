import 'package:flutter/material.dart';
import 'dart:math' as math;

class PhotoViewerScreen extends StatefulWidget {
  const PhotoViewerScreen({super.key});

  @override
  State<PhotoViewerScreen> createState() => _PhotoViewerScreenState();
}

class _PhotoViewerScreenState extends State<PhotoViewerScreen> with SingleTickerProviderStateMixin {
  final TransformationController _transformationController = TransformationController();
  late final AnimationController _animationController;
  Animation<Matrix4>? _animation;

  static const double _minScale = 0.9;
  static const double _maxScale = 5.0;
  static const double _doubleTapScale = 2.5;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(vsync: this, duration: const Duration(milliseconds: 200))
      ..addListener(() {
        final a = _animation;
        if (a != null) _transformationController.value = a.value;
      });
  }

  @override
  void dispose() {
    _animationController.dispose();
    _transformationController.dispose();
    super.dispose();
  }

  void _animateTo(Matrix4 end) {
    final begin = _transformationController.value;
    _animation = Matrix4Tween(begin: begin, end: end).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    ));
    _animationController.forward(from: 0);
  }

  void _onDoubleTapDown(TapDownDetails d, BoxConstraints c) {
    // 확대/원복 토글
    final currentScale = _transformationController.value.getMaxScaleOnAxis();
    if (currentScale > 1.05) {
      _animateTo(Matrix4.identity());
      return;
    }

    // 탭한 지점을 기준으로 확대 (가능한 중앙에 오게)
    final tapPos = d.localPosition;
    final scale = _doubleTapScale.clamp(_minScale, _maxScale);

    // 화면 중심을 기준으로 translate 계산
    final size = c.biggest;
    final dx = -(tapPos.dx - size.width / 2);
    final dy = -(tapPos.dy - size.height / 2);

    final m = Matrix4.identity()
      ..translate(dx, dy)
      ..scale(scale);

    _animateTo(m);
  }

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments;
    final imageUrl = (args is String && args.isNotEmpty) ? args : null;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('사진 보기'),
      ),
      body: imageUrl == null
          ? const Center(
              child: Text(
                '잘못된 접근입니다. (이미지 URL 없음)',
                style: TextStyle(color: Colors.white70),
              ),
            )
          : LayoutBuilder(
              builder: (context, constraints) => GestureDetector(
                onDoubleTapDown: (d) => _onDoubleTapDown(d, constraints),
                onDoubleTap: () {}, // onDoubleTapDown에서 처리
                child: Center(
                  child: Hero(
                    tag: imageUrl,
                    child: InteractiveViewer(
                      transformationController: _transformationController,
                      minScale: _minScale,
                      maxScale: _maxScale,
                      panEnabled: true,
                      clipBehavior: Clip.none,
                      child: Image.network(
                        imageUrl,
                        fit: BoxFit.contain,
                        loadingBuilder: (context, child, progress) {
                          if (progress == null) return child;
                          final v = progress.expectedTotalBytes != null
                              ? progress.cumulativeBytesLoaded /
                                  math.max(1, progress.expectedTotalBytes!)
                              : null;
                          return Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const SizedBox(
                                width: 44,
                                height: 44,
                                child: CircularProgressIndicator(color: Colors.white),
                              ),
                              if (v != null) ...[
                                const SizedBox(height: 8),
                                Text('${(v * 100).clamp(0, 100).toStringAsFixed(0)}%',
                                    style: const TextStyle(color: Colors.white70)),
                              ],
                            ],
                          );
                        },
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.broken_image,
                          color: Colors.white54,
                          size: 64,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}
