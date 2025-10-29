import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/product.dart';

class ApiService {
  // ---------- Singleton ----------
  ApiService._internal() {
    _dio = Dio(
      BaseOptions(
        baseUrl: _base,
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
        headers: {
          // 전역 Content-Type 고정 금지 (멀티파트 위해 비워둠)
        },
      ),
    );

    // 요청/에러 로깅 + 401 처리
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        final auth = options.headers['Authorization'];
        print("[DIO] => ${options.method} ${options.baseUrl}${options.path}  Authorization=$auth");
        handler.next(options);
      },
      onError: (e, handler) async {
        final msg = _extractMessage(e);
        print("[DIO:ERROR] ${e.response?.statusCode} ${e.response?.data}  <- $msg");
        if (e.response?.statusCode == 401) {
          await clearToken(); // 토큰 만료/무효 ⇒ 정리
        }
        handler.next(e);
      },
    ));
  }

  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  static ApiService get instance => _instance;

  // ---------- Base URL ----------
  String _base = "http://127.0.0.1:8000";
  late Dio _dio;

  void setBaseUrl(String url) {
    _base = url;
    _dio.options.baseUrl = url;
    print("🔧 [ApiService] baseUrl set to $_base");
  }

  String absolute(String? path) {
    if (path == null || path.isEmpty) return '';
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    return '$_base$path';
  }

  // ---------- Auth state ----------
  String? _token;
  String? get token => _token;
  bool get isAuthenticated => _token != null && _token!.isNotEmpty;

  Map<String, dynamic>? _me; // /auth/me 캐시
  Map<String, dynamic>? get me => _me;
  bool get isAdmin => (_me?['is_admin'] == true);

  // ---------- common error extractor ----------
  String _extractMessage(Object err) {
    if (err is DioException) {
      final data = err.response?.data;
      if (data is Map) {
        final d = data['detail'];
        if (d is String && d.trim().isNotEmpty) return d;
        if (d is List && d.isNotEmpty) {
          final first = d.first;
          if (first is Map && first['msg'] is String) return first['msg'];
        }
        if (data['message'] is String) return data['message'];
        if (data['error'] is String) return data['error'];
      } else if (data is String && data.trim().isNotEmpty) {
        return data;
      }
      return err.message ?? "Network error";
    }
    return err.toString();
  }

  // ---------- Token ----------
  Future<void> initToken() async {
    final sp = await SharedPreferences.getInstance();
    final t = sp.getString("token");
    if (t != null && t.isNotEmpty) {
      _token = t;
      _dio.options.headers["Authorization"] = "Bearer $t";
      print("✅ [ApiService] token restored");
      // 토큰 복구 시 사용자 정보 갱신 시도
      await refreshMe(silent: true);
    } else {
      _token = null;
      _dio.options.headers.remove("Authorization");
      print("ℹ️ [ApiService] no saved token");
      _me = null;
    }
  }

  Future<void> saveToken(String token) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString("token", token);
    _token = token;
    _dio.options.headers["Authorization"] = "Bearer $token";
    print("✅ [ApiService] token saved");
  }

  Future<void> clearToken() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove("token");
    _token = null;
    _me = null;
    _dio.options.headers.remove("Authorization");
    print("✅ [ApiService] token cleared");
  }

  /// ---------- 현재 사용자 정보 갱신 (/auth/me) ----------
  Future<bool> refreshMe({bool silent = false}) async {
    if (!isAuthenticated) {
      if (!silent) print("ℹ️ [me] no token");
      _me = null;
      return false;
    }
    try {
      final res = await _dio.get("/auth/me");
      final body = (res.data as Map).cast<String, dynamic>();
      _me = body;
      print("✅ [/auth/me] $_me");
      return true;
    } on DioException catch (e) {
      if (!silent) {
        print("❌ [/auth/me] ${_extractMessage(e)} status:${e.response?.statusCode} data:${e.response?.data}");
      }
      if (e.response?.statusCode == 401) {
        await clearToken();
      }
      return false;
    } catch (e) {
      if (!silent) print("❌ [/auth/me] Unknown error: $e");
      return false;
    }
  }

  /// ---------- 로그아웃 ----------
  Future<void> logout() async {
    await clearToken();
    print("[AUTH] 로그아웃 완료");
  }

  // ---------------- Auth ----------------
  Future<String?> login(String email, String password) async {
    try {
      // OAuth2PasswordRequestForm 규격 (x-www-form-urlencoded)
      final res = await _dio.post(
        "/auth/login",
        data: {
          "username": email,
          "password": password,
        },
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          headers: {"Content-Type": Headers.formUrlEncodedContentType},
        ),
      );
      final token = res.data["access_token"] as String?;
      if (token != null && token.isNotEmpty) {
        await saveToken(token);
        // 토큰 저장 직후 프로필 동기화 (is_admin 포함)
        await refreshMe(silent: true);
      }
      return token;
    } on DioException catch (e) {
      print("❌ [login] ${_extractMessage(e)} status:${e.response?.statusCode} data:${e.response?.data}");
      return null;
    } catch (e) {
      print("❌ [login] Unknown error: $e");
      return null;
    }
  }

  Future<bool> register(String email, String password, String name) async {
    try {
      await _dio.post(
        "/auth/register",
        data: {"email": email, "password": password, "name": name},
        options: Options(headers: {"Content-Type": "application/json"}),
      );
      return true;
    } on DioException catch (e) {
      print("❌ [register] ${_extractMessage(e)} status:${e.response?.statusCode} data:${e.response?.data}");
      return false;
    } catch (e) {
      print("❌ [register] Unknown error: $e");
      return false;
    }
  }

  // ---------------- Products ----------------
  Future<List<Product>> getProducts() async {
    try {
      final res = await _dio.get("/products");
      final list = (res.data as List<dynamic>)
          .map((e) => Product.fromJson(e as Map<String, dynamic>))
          .toList();
      return list;
    } on DioException catch (e) {
      print("❌ [getProducts] ${_extractMessage(e)} status:${e.response?.statusCode} data:${e.response?.data}");
      return [];
    } catch (e) {
      print("❌ [getProducts] Unknown error: $e");
      return [];
    }
  }

  Future<Product?> getProduct(int id) async {
    try {
      final res = await _dio.get("/products/$id");
      return Product.fromJson(res.data as Map<String, dynamic>);
    } on DioException catch (e) {
      print("❌ [getProduct] ${_extractMessage(e)} status:${e.response?.statusCode} data:${e.response?.data}");
      return null;
    } catch (e) {
      print("❌ [getProduct] Unknown error: $e");
      return null;
    }
  }

  Future<bool> createProduct({
    required String title,
    String? description,
    String? imageUrl,
    String? category,
    String? region,
    required double dailyPrice,
    required double deposit,
  }) async {
    try {
      await _dio.post(
        "/products",
        data: {
          "title": title,
          "description": description,
          "image_url": imageUrl,
          "category": category,
          "region": region,
          "daily_price": dailyPrice,
          "deposit": deposit,
          "is_rentable": true,
          "is_purchasable": true,
        },
        options: Options(headers: {"Content-Type": "application/json"}),
      );
      return true;
    } on DioException catch (e) {
      print("❌ [createProduct] ${_extractMessage(e)} status:${e.response?.statusCode} data:${e.response?.data}");
      return false;
    } catch (e) {
      print("❌ [createProduct] Unknown error: $e");
      return false;
    }
  }

  // 이미지 포함 생성
  Future<bool> createProductWithImage({
    required String title,
    String? description,
    String? category,
    String? region,
    required double dailyPrice,
    required double deposit,
    required String filePath,
    bool isRentable = true,
    bool isPurchasable = true,
  }) async {
    try {
      final form = FormData.fromMap({
        "title": title,
        if (description != null) "description": description,
        if (category != null) "category": category,
        if (region != null) "region": region,
        "daily_price": dailyPrice,
        "deposit": deposit,
        "is_rentable": isRentable,
        "is_purchasable": isPurchasable,
        "file": await MultipartFile.fromFile(filePath),
      });

      final res = await _dio.post(
        "/products/with-image",
        data: form,
        options: Options(contentType: 'multipart/form-data'),
      );

      return res.statusCode != null && res.statusCode! >= 200 && res.statusCode! < 300;
    } on DioException catch (e) {
      print("❌ [createProductWithImage] ${_extractMessage(e)} status:${e.response?.statusCode} data:${e.response?.data}");
      return false;
    } catch (e) {
      print("❌ [createProductWithImage] Unknown error: $e");
      return false;
    }
  }

  // ---------------- Rentals ----------------
  Future<Map<String, dynamic>?> createRental(
    int productId,
    DateTime start,
    DateTime end,
  ) async {
    try {
      final res = await _dio.post(
        "/rentals",
        data: {
          "product_id": productId,
          "start_date": start.toIso8601String(),
          "end_date": end.toIso8601String(),
        },
        options: Options(headers: {"Content-Type": "application/json"}),
      );
      return (res.data as Map).cast<String, dynamic>();
    } on DioException catch (e) {
      print("❌ [createRental] ${_extractMessage(e)} status:${e.response?.statusCode} data:${e.response?.data}");
      return null;
    } catch (e) {
      print("❌ [createRental] Unknown error: $e");
      return null;
    }
  }

  /// ✅ 날짜 가용성 체크
  Future<bool> checkAvailability(int productId, DateTime start, DateTime end) async {
    try {
      final res = await _dio.get(
        "/rentals/availability",
        queryParameters: {
          "product_id": productId,
          "start": start.toIso8601String(),
          "end": end.toIso8601String(),
        },
      );
      final data = res.data;
      if (data is Map && data["available"] is bool) {
        return data["available"] as bool;
      }
      return false;
    } on DioException catch (e) {
      print("❌ [checkAvailability] ${_extractMessage(e)} status:${e.response?.statusCode} data:${e.response?.data}");
      return false;
    } catch (e) {
      print("❌ [checkAvailability] Unknown error: $e");
      return false;
    }
  }

  /// 🔒 예약 불가 구간 조회
  Future<List<Map<String, DateTime>>> getBlockedDates(int productId) async {
    try {
      final res = await _dio.get(
        "/rentals/blocked-dates",
        queryParameters: {"product_id": productId},
      );

      final raw = res.data;
      if (raw is! List) return [];

      return raw.map<Map<String, DateTime>>((e) {
        final s = e is Map ? e['start']?.toString() : null;
        final t = e is Map ? e['end']?.toString() : null;
        final start = s != null ? DateTime.parse(s).toLocal() : DateTime.now();
        final end = t != null ? DateTime.parse(t).toLocal() : start;
        return {"start": start, "end": end};
      }).toList();
    } on DioException catch (e) {
      print("❌ [getBlockedDates] ${_extractMessage(e)} status:${e.response?.statusCode} data:${e.response?.data}");
      return [];
    } catch (e) {
      print("❌ [getBlockedDates] Unknown error: $e");
      return [];
    }
  }

  /// ✅ 단건 대여 조회
  Future<Map<String, dynamic>?> getRental(int rentalId) async {
    try {
      final res = await _dio.get("/rentals/$rentalId");
      return (res.data as Map).cast<String, dynamic>();
    } on DioException catch (e) {
      print("❌ [getRental] ${_extractMessage(e)} status:${e.response?.statusCode} data:${e.response?.data}");
      return null;
    } catch (e) {
      print("❌ [getRental] Unknown error: $e");
      return null;
    }
  }

  /// 내 대여 내역 조회
  Future<List<Map<String, dynamic>>> getMyRentals({
    bool? includeInactive,
    bool? includeClosed,
  }) async {
    try {
      final bool? _include = includeInactive ?? includeClosed;

      final qp = <String, dynamic>{};
      if (_include != null) {
        qp['include_inactive'] = _include;
      }

      final res = await _dio.get(
        "/rentals/me",
        queryParameters: qp.isEmpty ? null : qp,
      );
      return (res.data as List).cast<Map<String, dynamic>>();
    } on DioException catch (e) {
      print("❌ [getMyRentals] ${_extractMessage(e)} status:${e.response?.statusCode} data:${e.response?.data}");
      return [];
    } catch (e) {
      print("❌ [getMyRentals] Unknown error: $e");
      return [];
    }
  }

  /// 커서 페이지네이션
  Future<Map<String, dynamic>?> getMyRentalsPaged({
    int limit = 20,
    String? cursor,
    String? status,
    bool? includeInactive,
    bool? includeClosed,
  }) async {
    try {
      final bool? _include = includeInactive ?? includeClosed;

      final qp = <String, dynamic>{
        "limit": limit,
        if (cursor != null) "cursor": cursor,
        if (status != null) "status": status,
        if (_include != null) "include_inactive": _include,
      };

      final res = await _dio.get("/rentals/me/page", queryParameters: qp);
      return (res.data as Map).cast<String, dynamic>();
    } on DioException catch (e) {
      print("❌ [getMyRentalsPaged] ${_extractMessage(e)} status:${e.response?.statusCode} data:${e.response?.data}");
      return null;
    } catch (e) {
      print("❌ [getMyRentalsPaged] Unknown error: $e");
      return null;
    }
  }

  // 액션: 대여 취소
  Future<Map<String, dynamic>?> cancelRental(int rentalId) async {
    try {
      final res = await _dio.patch("/rentals/$rentalId/cancel");
      return (res.data as Map).cast<String, dynamic>();
    } on DioException catch (e) {
      print("❌ [cancelRental] ${_extractMessage(e)} status:${e.response?.statusCode} data:${e.response?.data}");
      return null;
    } catch (e) {
      print("❌ [cancelRental] Unknown error: $e");
      return null;
    }
  }

  // 액션: 반납 요청
  Future<Map<String, dynamic>?> requestReturn(int rentalId) async {
    try {
      final res = await _dio.patch("/rentals/$rentalId/request-return");
      return (res.data as Map).cast<String, dynamic>();
    } on DioException catch (e) {
      print("❌ [requestReturn] ${_extractMessage(e)} status:${e.response?.statusCode} data:${e.response?.data}");
      return null;
    } catch (e) {
      print("❌ [requestReturn] Unknown error: $e");
      return null;
    }
  }

  // 액션: 반납 완료
  Future<Map<String, dynamic>?> confirmReturn(int rentalId) async {
    try {
      final res = await _dio.patch("/rentals/$rentalId/confirm-return");
      return (res.data as Map).cast<String, dynamic>();
    } on DioException catch (e) {
      print("❌ [confirmReturn] ${_extractMessage(e)} status:${e.response?.statusCode} data:${e.response?.data}");
      return null;
    } catch (e) {
      print("❌ [confirmReturn] Unknown error: $e");
      return null;
    }
  }

  // ---------------- Photos ----------------
  Future<bool> uploadPhoto(int rentalId, String filePath, String phase) async {
    try {
      final form = FormData.fromMap({
        "rental_id": rentalId,
        "phase": phase, // "BEFORE" | "AFTER"
        "file": await MultipartFile.fromFile(filePath),
      });
      await _dio.post(
        "/photos/upload",
        data: form,
        options: Options(contentType: 'multipart/form-data'),
      );
      return true;
    } on DioException catch (e) {
      print("❌ [uploadPhoto] ${_extractMessage(e)} status:${e.response?.statusCode} data:${e.response?.data}");
      return false;
    } catch (e) {
      print("❌ [uploadPhoto] Unknown error: $e");
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> getPhotosByRental(int rentalId) async {
    try {
      final res = await _dio.get("/photos/by-rental/$rentalId");
      return (res.data as List).cast<Map<String, dynamic>>();
    } on DioException catch (e) {
      print("❌ [getPhotosByRental] ${_extractMessage(e)} status:${e.response?.statusCode} data:${e.response?.data}");
      return [];
    } catch (e) {
      print("❌ [getPhotosByRental] Unknown error: $e");
      return [];
    }
  }

  Future<bool> deletePhoto(int photoId) async {
    try {
      final res = await _dio.delete("/photos/$photoId");
      return (res.statusCode == 204) || (res.statusCode == 200);
    } on DioException catch (e) {
      print("❌ [deletePhoto] ${_extractMessage(e)} status:${e.response?.statusCode} data:${e.response?.data}");
      return false;
    } catch (e) {
      print("❌ [deletePhoto] Unknown error: $e");
      return false;
    }
  }

  // ---------------- Payments (결제 시뮬레이터) ----------------
  Future<Map<String, dynamic>?> simulatePayment({
    required int rentalId,
    required double amount,
  }) async {
    try {
      final res = await _dio.post(
        "/payments/checkout",
        data: {
          "rental_id": rentalId,
          "method": "mock",
        },
        options: Options(headers: {"Content-Type": "application/json"}),
      );
      return (res.data as Map).cast<String, dynamic>();
    } on DioException catch (e) {
      print("❌ [simulatePayment] ${_extractMessage(e)} status:${e.response?.statusCode} data:${e.response?.data}");
      return null;
    } catch (e) {
      print("❌ [simulatePayment] Unknown error: $e");
      return null;
    }
  }

  /// ✅ 대여료+보증금 합계 계산 후 시뮬레이터 호출
  Future<bool> mockCheckout(int rentalId) async {
    final rental = await getRental(rentalId);
    if (rental == null) return false;

    final totalPrice = (rental['total_price'] as num?)?.toDouble() ?? 0.0;
    final deposit = (rental['deposit'] as num?)?.toDouble() ?? 0.0;
    final amount = totalPrice + deposit;

    final paid = await simulatePayment(rentalId: rentalId, amount: amount);
    if (paid == null) return false;
    return paid['ok'] == true;
  }

  // ---------------- Reviews (후기) ----------------
  Future<Map<String, dynamic>?> createReview({
    required int rentalId,
    required int rating, // 1~5
    String? comment,
  }) async {
    try {
      final res = await _dio.post(
        "/reviews",
        data: {
          "rental_id": rentalId,
          "rating": rating,
          if (comment != null) "comment": comment,
        },
        options: Options(headers: {"Content-Type": "application/json"}),
      );
      return (res.data as Map).cast<String, dynamic>();
    } on DioException catch (e) {
      print("❌ [createReview] ${_extractMessage(e)} status:${e.response?.statusCode} data:${e.response?.data}");
      return null;
    } catch (e) {
      print("❌ [createReview] Unknown error: $e");
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> getReviewsByProduct(int productId) async {
    try {
      final res = await _dio.get("/reviews/by-product/$productId");
      return (res.data as List).cast<Map<String, dynamic>>();
    } on DioException catch (e) {
      print("❌ [getReviewsByProduct] ${_extractMessage(e)} status:${e.response?.statusCode} data:${e.response?.data}");
      return [];
    } catch (e) {
      print("❌ [getReviewsByProduct] Unknown error: $e");
      return [];
    }
  }

  // ⭐ Added alias: UI 코드에서 getReviews()를 기대하는 경우 지원
  Future<List<Map<String, dynamic>>> getReviews(int productId) async {
    return await getReviewsByProduct(productId);
  }

  /// ⭐ 상품별 평점 요약 조회 (avg, count)
  /// 1) 백엔드 summary 엔드포인트가 있으면 사용
  /// 2) 없으면 전체 리뷰를 불러와 로컬에서 계산
  Future<Map<String, dynamic>?> getProductRatingSummary(int productId) async {
    try {
      final res = await _dio.get("/reviews/summary/$productId");
      final data = (res.data as Map).cast<String, dynamic>();

      final avg = (data['avg'] as num?)?.toDouble() ?? 0.0;
      final count = (data['count'] as num?)?.toInt() ?? 0;
      return {"avg": avg, "count": count};
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        // ✅ summary API 없으면 폴백
        return await _calcRatingSummaryFallback(productId);
      }
      print("❌ [getProductRatingSummary] ${_extractMessage(e)} status:${e.response?.statusCode} data:${e.response?.data}");
      return null;
    } catch (e) {
      print("❌ [getProductRatingSummary] Unknown error: $e");
      return null;
    }
  }

  /// 🔁 summary 엔드포인트가 없을 때 fallback 계산
  Future<Map<String, dynamic>?> _calcRatingSummaryFallback(int productId) async {
    try {
      final list = await getReviewsByProduct(productId);
      if (list.isEmpty) return {"avg": 0.0, "count": 0};

      int count = 0;
      double sum = 0.0;

      for (final r in list) {
        final rt = r['rating'];
        if (rt is num) {
          sum += rt.toDouble();
          count++;
        }
      }

      if (count == 0) return {"avg": 0.0, "count": 0};
      return {"avg": sum / count, "count": count};
    } catch (e) {
      print("❌ [_calcRatingSummaryFallback] $e");
      return null;
    }
  }

  // ---------------- Admin (관리자) ----------------
  Future<List<Map<String, dynamic>>> adminListPendingRentals() async {
    try {
      final res = await _dio.get("/admin/rentals/pending");
      return (res.data as List).cast<Map<String, dynamic>>();
    } on DioException catch (e) {
      if (e.response?.statusCode == 403) {
        throw ApiForbiddenError();
      }
      print("❌ [adminListPendingRentals] ${_extractMessage(e)} status:${e.response?.statusCode} data:${e.response?.data}");
      return [];
    } catch (e) {
      print("❌ [adminListPendingRentals] Unknown error: $e");
      return [];
    }
  }

  Future<Map<String, dynamic>?> adminUpdateRentalStatus({
    required int rentalId,
    required String status,
  }) async {
    try {
      final res = await _dio.patch(
        "/admin/rentals/$rentalId/status",
        data: {"status": status},
        options: Options(headers: {"Content-Type": "application/json"}),
      );
      return (res.data as Map).cast<String, dynamic>();
    } on DioException catch (e) {
      print("❌ [adminUpdateRentalStatus] ${_extractMessage(e)} status:${e.response?.statusCode} data:${e.response?.data}");
      return null;
    } catch (e) {
      print("❌ [adminUpdateRentalStatus] Unknown error: $e");
      return null;
    }
  }

  Future<bool> adminApproveRental(int rentalId) async {
    try {
      final res = await _dio.patch("/admin/rentals/$rentalId/approve");
      return res.statusCode != null && res.statusCode! >= 200 && res.statusCode! < 300;
    } on DioException catch (e) {
      if (e.response?.statusCode == 403) {
        throw ApiForbiddenError();
      }
      print("❌ [adminApproveRental] ${_extractMessage(e)} status:${e.response?.statusCode} data:${e.response?.data}");
      return false;
    } catch (e) {
      print("❌ [adminApproveRental] Unknown error: $e");
      return false;
    }
  }

  Future<bool> adminRejectRental(int rentalId) async {
    try {
      final res = await _dio.patch("/admin/rentals/$rentalId/reject");
      return res.statusCode != null && res.statusCode! >= 200 && res.statusCode! < 300;
    } on DioException catch (e) {
      if (e.response?.statusCode == 403) {
        throw ApiForbiddenError();
      }
      print("❌ [adminRejectRental] ${_extractMessage(e)} status:${e.response?.statusCode} data:${e.response?.data}");
      return false;
    } catch (e) {
      print("❌ [adminRejectRental] Unknown error: $e");
      return false;
    }
  }

  Future<bool> adminDeleteProduct(int productId) async {
    try {
      final res = await _dio.delete("/admin/products/$productId");
      return res.statusCode != null && res.statusCode! >= 200 && res.statusCode! < 300;
    } on DioException catch (e) {
      print("❌ [adminDeleteProduct] ${_extractMessage(e)} status:${e.response?.statusCode} data:${e.response?.data}");
      return false;
    } catch (e) {
      print("❌ [adminDeleteProduct] Unknown error: $e");
      return false;
    }
  }
  // ---------------- Admin: Reviews (리뷰 관리) ----------------

  /// 관리자: 리뷰 목록 조회
  /// 현재 백엔드에 /admin/reviews 없음 → 404이면 /reviews/by-product/{product_id}로 폴백
  Future<dynamic> adminGetReviews({int? productId, int? rating}) async {
    try {
      final qp = <String, dynamic>{};
      if (productId != null) qp['product_id'] = productId;
      if (rating != null) qp['rating'] = rating;

      final res = await _dio.get(
        "/admin/reviews",
        queryParameters: qp.isEmpty ? null : qp,
      );
      return res.data; // (미래에 엔드포인트가 생기면 그대로 사용)
    } on DioException catch (e) {
      // ✅ 404: 현재 엔드포인트가 없으므로 폴백
      if (e.response?.statusCode == 404) {
        if (productId != null) {
          try {
            final alt = await _dio.get("/reviews/by-product/$productId");
            return alt.data; // List 형태
          } on DioException catch (e2) {
            print("❌ [fallback by-product] ${_extractMessage(e2)} "
                  "status:${e2.response?.statusCode} data:${e2.response?.data}");
            return null;
          }
        }
        // productId가 없으면 폴백 불가
        return [];
      }
      if (e.response?.statusCode == 403) {
        throw ApiForbiddenError();
      }
      print("❌ [adminGetReviews] ${_extractMessage(e)}  "
            "status:${e.response?.statusCode} data:${e.response?.data}");
      return null;
    } catch (e) {
      print("❌ [adminGetReviews] Unknown error: $e");
      return null;
    }
  }


  /// 관리자: 리뷰 삭제
  Future<bool> adminDeleteReview(int reviewId) async {
    try {
      final res = await _dio.delete("/admin/reviews/$reviewId");
      return res.statusCode != null && res.statusCode! >= 200 && res.statusCode! < 300;
    } on DioException catch (e) {
      if (e.response?.statusCode == 403) {
        throw ApiForbiddenError();
      }
      print("❌ [adminDeleteReview] ${_extractMessage(e)} status:${e.response?.statusCode} data:${e.response?.data}");
      return false;
    } catch (e) {
      print("❌ [adminDeleteReview] Unknown error: $e");
      return false;
    }
  }

    /// 관리자: 리뷰 목록 조회 (화면에서 List<Map<String,dynamic>> 기대)
  /// - 백엔드가 배열로 주면 그대로 반환
  /// - {"items":[...], "next":"..."} 형태면 items만 꺼내 반환
  Future<List<Map<String, dynamic>>> adminListReviews({
    int? productId,
    int? rating,
    int? limit,
    String? cursor,
  }) async {
    try {
      final qp = <String, dynamic>{};
      if (productId != null) qp['product_id'] = productId;
      if (rating != null) qp['rating'] = rating;
      if (limit != null) qp['limit'] = limit;
      if (cursor != null && cursor.isNotEmpty) qp['cursor'] = cursor;

      final res = await _dio.get(
        "/admin/reviews",
        queryParameters: qp.isEmpty ? null : qp,
      );

      final data = res.data;
      if (data is List) {
        return data.cast<Map<String, dynamic>>();
      }
      if (data is Map && data['items'] is List) {
        return (data['items'] as List).cast<Map<String, dynamic>>();
      }
      return [];
    } on DioException catch (e) {
      if (e.response?.statusCode == 403) {
        throw ApiForbiddenError();
      }
      print("❌ [adminListReviews] ${_extractMessage(e)} status:${e.response?.statusCode} data:${e.response?.data}");
      return [];
    } catch (e) {
      print("❌ [adminListReviews] Unknown error: $e");
      return [];
    }
  }

}

// ✅ 403 구분용 커스텀 에러
class ApiForbiddenError implements Exception {}
