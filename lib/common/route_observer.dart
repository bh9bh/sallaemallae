import 'package:flutter/material.dart';

/// 전역 RouteObserver: RouteAware(예: MyPageScreen)에서 subscribe 해 사용
final RouteObserver<ModalRoute<void>> routeObserver =
    RouteObserver<ModalRoute<void>>();
