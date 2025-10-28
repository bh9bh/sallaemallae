import 'package:flutter/material.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/home_screen.dart';
import 'screens/product_detail_screen.dart';
import 'screens/rental_screen.dart';
import 'screens/photo_upload_screen.dart';
import 'screens/mypage_screen.dart';
import 'screens/add_product_screen.dart';
import 'screens/photo_viewer_screen.dart';
import 'screens/admin/admin_pending_screen.dart';
import 'services/api_service.dart' as api;  // ✅ prefix 추가!


Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ✅ 토큰 복구 + /auth/me 동기화
  final apiService = api.ApiService.instance; // ← prefix 추가됨
  await apiService.initToken();
  if (apiService.isAuthenticated) {
    await apiService.refreshMe();
  }

  final startRoute = apiService.isAuthenticated ? '/home' : '/login';
  runApp(SallaeMallaeApp(initialRoute: startRoute));
}

class SallaeMallaeApp extends StatelessWidget {
  const SallaeMallaeApp({super.key, required this.initialRoute});

  final String initialRoute;

  @override
  Widget build(BuildContext context) {
    final seed = Colors.indigo;

    final light = ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.light);
    final dark  = ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark);

    return MaterialApp(
      title: 'Sallae Mallae',
      // ✅ 테마/다크모드 통일
      theme: ThemeData(
        colorScheme: light,
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: dark,
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system, // 시스템 설정 자동 추종

      // ✅ 시작 라우트
      initialRoute: initialRoute,

      // ✅ 정적 라우트 맵
      routes: {
        '/login': (_) => const LoginScreen(),
        '/register': (_) => const RegisterScreen(),
        '/home': (_) => const HomeScreen(),
        '/product': (_) => const ProductDetailScreen(),
        '/rental': (_) => const RentalScreen(),          // 대여 신청
        '/photo': (_) => const PhotoUploadScreen(),
        '/mypage': (_) => const MyPageScreen(),          // 내 대여 목록
        '/add_product': (_) => const AddProductScreen(),
        '/photo_viewer': (_) => const PhotoViewerScreen(),
        '/admin/pending': (_) => const AdminPendingScreen(), // 관리자 승인 대기
      },

      // (선택) 잘못된 경로로 들어왔을 때 404 처리
      onUnknownRoute: (settings) => MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('페이지를 찾을 수 없습니다')),
          body: const Center(child: Text('404 Not Found')),
        ),
      ),

      debugShowCheckedModeBanner: false,
    );
  }
}
