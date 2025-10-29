import 'package:flutter/material.dart';

// Screens
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
import 'screens/admin/admin_reviews_screen.dart'; // ✅ 관리자 리뷰 화면

// Services
import 'services/api_service.dart' as api; // ✅ prefix 유지

// Theme
import 'theme/sm_theme.dart'; // ✅ 피그마 느낌 테마

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ✅ 토큰 복구 + /auth/me 동기화
  final apiService = api.ApiService.instance;
  await apiService.initToken();     // 내부에서 silent refreshMe 시도
  if (apiService.isAuthenticated) {
    await apiService.refreshMe();   // 한번 더 확정 동기화 (is_admin 포함)
  }

  // ✅ 시작 라우트 결정
  final String startRoute = apiService.isAuthenticated
      ? (apiService.isAdmin ? '/admin/pending' : '/home')
      : '/login';

  runApp(SallaeMallaeApp(initialRoute: startRoute));
}

class SallaeMallaeApp extends StatelessWidget {
  const SallaeMallaeApp({super.key, required this.initialRoute});
  final String initialRoute;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sallae Mallae',

      // ✅ 피그마 기반 테마 적용 (Style B)
      theme: SallaeTheme.light,
      darkTheme: SallaeTheme.dark,
      themeMode: ThemeMode.system,

      // ✅ 시작 라우트
      initialRoute: initialRoute,

      // ✅ 정적 라우트 맵
      routes: {
        '/login': (_) => const LoginScreen(),
        '/register': (_) => const RegisterScreen(),

        // 일반 화면들 → 공통 가드
        '/home': (_) => _RouteGuard(
              routeName: '/home',
              child: const HomeScreen(),
            ),
        '/product': (_) => _RouteGuard(
              routeName: '/product',
              child: const ProductDetailScreen(),
            ),
        '/rental': (_) => _RouteGuard(
              routeName: '/rental',
              child: const RentalScreen(),
            ),
        '/photo': (_) => _RouteGuard(
              routeName: '/photo',
              child: const PhotoUploadScreen(),
            ),
        '/mypage': (_) => _RouteGuard(
              routeName: '/mypage',
              child: const MyPageScreen(),
            ),
        '/add_product': (_) => _RouteGuard(
              routeName: '/add_product',
              child: const AddProductScreen(),
            ),
        '/photo_viewer': (_) => _RouteGuard(
              routeName: '/photo_viewer',
              child: const PhotoViewerScreen(),
            ),

        // ✅ 관리자 전용
        '/admin/pending': (_) => _AdminGuard(
              child: const AdminPendingScreen(),
            ),
        '/admin/reviews': (_) => _AdminGuard(
              child: const AdminReviewsScreen(),
            ),
      },

      // 404 처리
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

/// ---------------- Guards ----------------

/// ✅ 일반 화면 공통 가드:
/// - 미인증이면 /login
/// - 관리자 계정이 일반 화면(/home 등)에 접근하면 /admin/pending 으로 이동
class _RouteGuard extends StatefulWidget {
  const _RouteGuard({required this.child, required this.routeName, super.key});

  final Widget child;
  final String routeName;

  @override
  State<_RouteGuard> createState() => _RouteGuardState();
}

class _RouteGuardState extends State<_RouteGuard> {
  bool _checked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_checked) return;
    _checked = true;

    final svc = api.ApiService.instance;

    Future.microtask(() {
      if (!mounted) return;

      // 1) 미인증 → 로그인으로
      if (!svc.isAuthenticated) {
        Navigator.pushNamedAndRemoveUntil(context, '/login', (r) => false);
        return;
      }

      // 2) 관리자면 일반 화면 접근 차단 → 관리자 첫 화면으로
      if (svc.isAdmin && widget.routeName != '/admin/pending') {
        Navigator.pushNamedAndRemoveUntil(context, '/admin/pending', (r) => false);
        return;
      }
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// ✅ 관리자 전용 가드:
/// - 미인증이면 /login
/// - 일반 계정이면 /home
class _AdminGuard extends StatefulWidget {
  const _AdminGuard({required this.child, super.key});
  final Widget child;

  @override
  State<_AdminGuard> createState() => _AdminGuardState();
}

class _AdminGuardState extends State<_AdminGuard> {
  bool _checked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_checked) return;
    _checked = true;

    final svc = api.ApiService.instance;

    Future.microtask(() {
      if (!mounted) return;

      if (!svc.isAuthenticated) {
        Navigator.pushNamedAndRemoveUntil(context, '/login', (r) => false);
        return;
      }
      if (!svc.isAdmin) {
        Navigator.pushNamedAndRemoveUntil(context, '/home', (r) => false);
        return;
      }
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
