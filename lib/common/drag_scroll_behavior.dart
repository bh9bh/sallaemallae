// FILE: lib/common/drag_scroll_behavior.dart
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

class DesktopDragScrollBehavior extends MaterialScrollBehavior {
  const DesktopDragScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => <PointerDeviceKind>{
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.stylus,
        PointerDeviceKind.trackpad, // 일부 환경
        PointerDeviceKind.unknown,
      };
}
