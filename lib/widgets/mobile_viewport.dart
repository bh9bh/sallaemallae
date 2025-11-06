import 'package:flutter/material.dart';

/// 데스크톱/태블릿에서도 모바일처럼 390~420폭으로 미리보기하는 래퍼
class MobileViewport extends StatelessWidget {
  const MobileViewport({
    super.key,
    required this.child,
    this.minWidth = 360,
    this.maxWidth = 420, // iPhone 13/14는 390, 15 Pro는 393
    this.bgColor = const Color(0xFFF5F6F8),
  });

  final Widget child;
  final double minWidth;
  final double maxWidth;
  final Color bgColor;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: bgColor,
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: minWidth,
              maxWidth: maxWidth,
            ),
            child: Material(
              color: Colors.transparent,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
