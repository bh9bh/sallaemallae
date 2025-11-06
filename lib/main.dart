// FILE: lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter_localizations/flutter_localizations.dart'; // ✅ 로컬라이제이션 import

// screens
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/home_screen.dart';
import 'screens/product_detail_screen.dart';
import 'screens/rental_screen.dart' as rental_screen; // ← 이름 충돌 방지용 별칭
import 'screens/photo_upload_screen.dart';
import 'screens/mypage_screen.dart';
import 'screens/add_product_screen.dart';
import 'screens/photo_viewer_screen.dart';
import 'screens/pre_rental_photos_screen.dart'; // ✅ 대여 전 사진 인증 화면

// etc
import 'services/api_service.dart' as api;
import 'theme/sm_theme.dart';
import 'widgets/mobile_viewport.dart';
import 'common/drag_scroll_behavior.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final apiService = api.ApiService.instance;
  await apiService.initToken();

  // 토큰이 있으면 me 동기화(실패 시 로그아웃)
  if (apiService.isAuthenticated) {
    final ok = await apiService.refreshMe(silent: true);
    if (!ok) {
      await apiService.logout();
    }
  }

  runApp(const SallaeMallaeApp());
}

class SallaeMallaeApp extends StatelessWidget {
  const SallaeMallaeApp({super.key});

  // 데스크톱/웹 미리보기용 모바일 뷰포트 강제
  static const bool kForceMobilePreview = true;

  bool get _isDesktopLike {
    final tp = defaultTargetPlatform;
    return kIsWeb ||
        tp == TargetPlatform.windows ||
        tp == TargetPlatform.linux ||
        tp == TargetPlatform.macOS;
  }

  @override
  Widget build(BuildContext context) {
    final authed = api.ApiService.instance.isAuthenticated;
    final String initialRoute = authed ? '/home' : '/login';

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '살래말래',
      theme: SallaeTheme.light,
      themeMode: ThemeMode.system,
      scrollBehavior: DesktopDragScrollBehavior(),
      initialRoute: initialRoute,

      // ✅ 로컬라이제이션 설정 (DatePicker 등 Material 위젯에 필요)
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('ko', 'KR'),
        Locale('en', 'US'),
      ],
      locale: const Locale('ko', 'KR'), // 기본 한국어

      routes: {
        '/login': (_) => const LoginScreen(),
        '/register': (_) => const RegisterScreen(),
        '/home': (_) => const HomeScreen(),

        // RentalScreen은 별칭으로 import했으니 접두사 없이 직접 호출
        '/rental': (_) => const rental_screen.RentalScreen(),

        // ✅ 대여 전 사진 인증 플로우
        '/pre-photos': (_) => const PreRentalPhotosScreen(),

        // 기존 사진 업로드(렌탈 이후 개별 업로드 화면)
        '/photo-upload': (_) => const PhotoUploadScreen(),
        '/photoUpload': (_) => const PhotoUploadScreen(), // 하위호환

        '/mypage': (_) => const MyPageScreen(),
        '/add_product': (_) => const AddProductScreen(),
        '/photo-viewer': (_) => const PhotoViewerScreen(),
        '/photoViewer': (_) => const PhotoViewerScreen(), // 하위호환
      },

      onGenerateRoute: (settings) {
        // /product 상세로 진입 시 arguments를 그대로 전달
        if (settings.name == '/product') {
          return MaterialPageRoute(
            builder: (_) => const ProductDetailScreen(),
            settings: settings,
          );
        }
        return null;
      },

      onUnknownRoute: (_) => MaterialPageRoute(
        builder: (_) => authed ? const HomeScreen() : const LoginScreen(),
      ),

      builder: (context, child) {
        final content = child ?? const SizedBox.shrink();
        if (!kForceMobilePreview) return content;

        final width = MediaQuery.of(context).size.width;
        final shouldConstrain = _isDesktopLike && width > 480;
        if (!shouldConstrain) return content;

        return MobileViewport(child: content);
      },
    );
  }
}
