// FILE: lib/services/api_service.dart
import 'dart:io';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

class ApiService {
  ApiService._() {
    _dio = Dio(
      BaseOptions(
        baseUrl: _baseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 20),
        headers: {'Content-Type': 'application/json'},
        followRedirects: false,
        // 401/409/422를 에러로 던지지 말고 응답으로 돌려 받도록 허용
        validateStatus: (code) =>
            code != null && (code < 400 || code == 401 || code == 409 || code == 422),
      ),
    );

    // ===== Interceptors =====
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final path = options.path;
          final isAuthPath = _isAuthEndpoint(path);
          if (!isAuthPath && _token != null && _token!.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $_token';
          }
          handler.next(options);
        },
        onError: (e, handler) async {
          final status = e.response?.statusCode;
          // 인증 엔드포인트가 아닌데 401이 오면 1회 재시도
          if (status == 401 && !_isAuthEndpoint(e.requestOptions.path)) {
            if (_isRetrying401) return handler.next(e);
            if (!isAuthenticated) return handler.next(e);

            try {
              _isRetrying401 = true;
              final ok = await refreshMe(silent: true);
              if (ok) {
                final retry = await _retryRequest(e.requestOptions);
                _isRetrying401 = false;
                return handler.resolve(retry);
              } else {
                await _saveToken(null);
              }
            } catch (_) {
            } finally {
              _isRetrying401 = false;
            }
          }
          handler.next(e);
        },
      ),
    );

    // 네트워크 로깅
    _dio.interceptors.add(
      LogInterceptor(
        request: true,
        requestHeader: true,
        requestBody: true,
        responseHeader: false,
        responseBody: false,
      ),
    );
  }

  static final ApiService instance = ApiService._();
  factory ApiService() => instance;

  late Dio _dio;

  // ===== Env =====
  static const String _defaultBaseUrl = 'http://127.0.0.1:8000';
  final String _baseUrl =
      const String.fromEnvironment('API_BASE_URL', defaultValue: _defaultBaseUrl);

  String? _token;
  bool _isRetrying401 = false;

  bool get isAuthenticated => (_token ?? '').isNotEmpty;
  Dio get dio => _dio;
  String? get token => _token;

  // ===== WebSocket helpers =====
  String get wsBaseUrl {
    final uri = Uri.parse(_baseUrl);
    final scheme = (uri.scheme == 'https') ? 'wss' : 'ws';
    final host = uri.host;
    final port = uri.hasPort ? ':${uri.port}' : '';
    return '$scheme://$host$port';
  }

  String wsUrl(String path, [Map<String, String>? qs]) {
    final clean = path.startsWith('/') ? path : '/$path';
    final full = Uri.parse('$wsBaseUrl$clean').replace(queryParameters: qs);
    return full.toString();
  }

  // ===== Token =====
  Future<void> initToken() async {
    final sp = await SharedPreferences.getInstance();
    _token = sp.getString('access_token') ?? sp.getString('auth_token');
    if (_token != null && _token!.isNotEmpty) {
      _dio.options.headers['Authorization'] = 'Bearer $_token';
    }
  }

  Future<void> _saveToken(String? t) async {
    final sp = await SharedPreferences.getInstance();
    _token = t;
    if (t == null || t.isEmpty) {
      await sp.remove('access_token');
      await sp.remove('auth_token');
      _dio.options.headers.remove('Authorization');
    } else {
      await sp.setString('access_token', t);
      _dio.options.headers['Authorization'] = 'Bearer $t';
    }
  }

  Map<String, String>? _authHeader() {
    if (_token == null || _token!.isEmpty) return null;
    return {'Authorization': 'Bearer $_token'};
  }

  Future<bool> refreshMe({bool silent = false}) async {
    try {
      final r = await _dio.get(
        '/auth/me',
        options: Options(headers: _authHeader()),
      );
      return (r.statusCode ?? 0) >= 200 && (r.statusCode ?? 0) < 300;
    } catch (_) {
      if (!silent) rethrow;
      return false;
    }
  }

  // ===== Auth =====
  Future<String?> login(String email, String password) async {
    String? _extractToken(dynamic data) {
      if (data is Map) {
        for (final k in [
          'access_token',
          'token',
          'jwt',
          'accessToken',
          'access-token',
        ]) {
          final v = data[k];
          if (v is String && v.isNotEmpty) return v;
        }
      }
      return null;
    }

    // 1) JSON 로그인
    try {
      final r = await _dio.post(
        '/auth/login',
        data: {'email': email, 'password': password},
        options: Options(headers: {'Content-Type': 'application/json'}),
      );
      final token = _extractToken(r.data);
      await _saveToken(token);
      if (token != null && token.isNotEmpty) return token;
    } catch (_) {}

    // 2) FORM 토큰 발급
    try {
      final r = await _dio.post(
        '/auth/token',
        data: {'username': email, 'password': password},
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      final token = _extractToken(r.data);
      await _saveToken(token);
      if (token != null && token.isNotEmpty) return token;
    } catch (_) {}

    return null;
  }

  Future<void> logout() async {
    await _saveToken(null);
  }

  Future<bool> register(String email, String password, String fullName) async {
    try {
      final r = await _dio.post(
        '/auth/register',
        data: {'email': email, 'password': password, 'full_name': fullName},
        options: Options(headers: {'Content-Type': 'application/json'}),
      );
      return r.statusCode == 200 || r.statusCode == 201;
    } catch (_) {
      return false;
    }
  }

  Future<bool> forgotUsername(String email) async {
    for (final path in const [
      '/auth/forgot-username',
      '/auth/forgot_username',
      '/auth/forgot-id',
    ]) {
      try {
        final r = await _dio.post(path, data: {'email': email});
        if (r.statusCode == 200 || r.statusCode == 204) return true;
      } catch (_) {}
    }
    return false;
  }

  Future<bool> forgotPassword(String email) async {
    for (final path in const [
      '/auth/forgot-password',
      '/auth/password/reset',
      '/auth/reset-password',
    ]) {
      try {
        final r = await _dio.post(path, data: {'email': email});
        if (r.statusCode == 200 || r.statusCode == 204) return true;
      } catch (_) {}
    }
    return false;
  }

  // ===== Common helpers =====
  Map<String, dynamic> _normalizeProduct(Map src) {
    final m = Map<String, dynamic>.from(src as Map);

    // 가격 키 통합
    final price = m['price_per_day'] ?? m['daily_price'] ?? m['pricePerDay'] ?? m['dailyPrice'];
    if (price != null) {
      m['price_per_day'] = (price is num) ? price.toInt() : int.tryParse('$price') ?? 0;
      m['daily_price'] = m['price_per_day'];
    }

    // 이미지 키 통합
    final img = m['image_url'] ?? m['thumbnail_url'] ?? m['imageUrl'] ?? m['thumbnailUrl'];
    if (img != null) m['image_url'] = '$img';

    // 제목/이름 키 통합
    final hasTitle = (m['title'] is String) && (m['title'] as String).trim().isNotEmpty;
    final hasName = (m['name'] is String) && (m['name'] as String).trim().isNotEmpty;
    if (hasTitle && !hasName) {
      m['name'] = '${m['title']}';
    } else if (hasName && !hasTitle) {
      m['title'] = '${m['name']}';
    }

    return m;
  }

  List<Map<String, dynamic>> _normalizeList(dynamic data) {
    if (data is List) {
      return data.whereType<Map>().map<Map<String, dynamic>>(_normalizeProduct).toList();
    }
    if (data is Map) {
      final items = data['items'];
      if (items is List) {
        return items.whereType<Map>().map<Map<String, dynamic>>(_normalizeProduct).toList();
      }
    }
    return <Map<String, dynamic>>[];
  }

  // ===== Products =====
  Future<List<Map<String, dynamic>>> getProducts() async {
    try {
      final r = await _dio.get('/products');
      return _normalizeList(r.data);
    } catch (_) {
      return const <Map<String, dynamic>>[];
    }
  }

  Future<Map<String, dynamic>?> getProduct(int id) async {
    try {
      final r = await _dio.get('/products/$id');
      final data = r.data;
      if (data is Map) return _normalizeProduct(data);
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> searchProducts({
    String? query,
    String? category,
    String? region,
    int page = 1,
    int size = 20,
    String? sort,
    double? minPrice,
    double? maxPrice,
  }) async {
    Map<String, dynamic> _buildParams() {
      final qp = <String, dynamic>{
        'page': page,
        'size': size,
        if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
        if (category != null && category.isNotEmpty) 'category': category,
        if (region != null && region.isNotEmpty) 'region': region,
        if (sort != null && sort.isNotEmpty) 'sort': sort,
      };
      if (minPrice != null) qp['min_price'] = minPrice;
      if (maxPrice != null) qp['max_price'] = maxPrice;
      return qp;
    }

    try {
      final r = await _dio.get('/products', queryParameters: _buildParams());
      return _normalizeList(r.data);
    } catch (_) {}

    try {
      final r = await _dio.get('/products/search', queryParameters: _buildParams());
      return _normalizeList(r.data);
    } catch (_) {}

    try {
      final r = await _dio.get('/search/products', queryParameters: _buildParams());
      return _normalizeList(r.data);
    } catch (_) {}

    return <Map<String, dynamic>>[];
  }

  Future<List<Map<String, dynamic>>> getPopularProducts({
    String? category,
    int limit = 20,
    int minReviews = 0,
  }) async {
    try {
      final qp = <String, dynamic>{
        'limit': limit,
        if (category != null && category.isNotEmpty) 'category': category,
        if (minReviews > 0) 'min_reviews': minReviews,
      };
      final r = await _dio.get('/products/popular', queryParameters: qp);
      return _normalizeList(r.data);
    } catch (_) {}

    try {
      final qp = <String, dynamic>{
        'limit': limit,
        'sort': 'popular',
        if (category != null && category.isNotEmpty) 'category': category,
      };
      final r = await _dio.get('/products', queryParameters: qp);
      return _normalizeList(r.data);
    } catch (_) {}

    return const <Map<String, dynamic>>[];
  }

  // ===== URL helper =====
  String? absolute(String? url) {
    if (url == null || url.isEmpty) return null;
    final u = Uri.tryParse(url);
    if (u == null) return null;
    if (u.hasScheme) return url;
    final base = Uri.parse(_baseUrl);
    return Uri(
      scheme: base.scheme,
      host: base.host,
      port: base.hasPort ? base.port : null,
      path: url.startsWith('/') ? url : '/$url',
    ).toString();
  }

  // ===== Reviews =====
  Future<List<Map<String, dynamic>>> getReviewsByProduct(int productId) async {
    try {
      final r = await _dio.get('/reviews/by-product/$productId');
      final list = (r.data as List?) ?? const [];
      return list.cast<Map<String, dynamic>>();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  Future<Map<String, dynamic>?> getProductRatingSummary(int productId) async {
    try {
      final r = await _dio.get('/reviews/summary/$productId');
      if (r.data is Map) return Map<String, dynamic>.from(r.data);
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<bool> createReview({
    required int productId,
    required int rating,
    String? comment,
    int? rentalId,
  }) async {
    try {
      final body = <String, dynamic>{
        'product_id': productId,
        'rating': rating,
        if (comment != null) 'comment': comment,
        if (rentalId != null) 'rental_id': rentalId,
      };
      final r = await _dio.post('/reviews', data: body, options: Options(headers: _authHeader()));
      return r.statusCode == 200 || r.statusCode == 201;
    } catch (_) {
      return false;
    }
  }

  // ===== Rentals =====
  String _d(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  Future<Map<String, dynamic>> createRental({
    required int productId,
    required DateTime startDate,
    required DateTime endDate,
    bool? endExclusive,
  }) async {
    if (!isAuthenticated) {
      return {'ok': false, 'status': 401, 'message': 'Not authenticated (no token on client)'};
    }
    try {
      final payload = {
        'product_id': productId,
        'start_date': _d(startDate),
        'end_date': _d(endDate),
      };

      final res = await _dio.post(
        '/rentals',
        data: jsonEncode(payload),
        options: Options(
          headers: _authHeader(),
          contentType: 'application/json',
          followRedirects: false,
          validateStatus: (code) =>
              code != null && (code < 400 || code == 401 || code == 409 || code == 422),
        ),
      );

      final sc = res.statusCode ?? 0;
      if (sc == 201) return {'ok': true, 'status': sc, 'data': res.data};
      return {'ok': false, 'status': sc, 'data': res.data};
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      final data = e.response?.data;
      // ignore: avoid_print
      print('[createRental] $status ${e.message} body=$data');
      return {'ok': false, 'status': status, 'data': data, 'message': e.message};
    } catch (e) {
      // ignore: avoid_print
      print('[createRental] unknown error: $e');
      return {'ok': false, 'status': null, 'message': e.toString()};
    }
  }

  Future<Set<DateTime>> getBlockedDates(
    int productId, {
    bool includeEnd = false,
  }) async {
    DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

    Future<Response<dynamic>> _tryExpanded() => _dio.get(
          '/rentals/blocked-dates',
          queryParameters: {'product_id': productId, 'expand': true},
          options: Options(headers: _authHeader()),
        );

    Future<Response<dynamic>> _tryRanges1() => _dio.get(
          '/rentals/blocked-dates',
          queryParameters: {'product_id': productId},
          options: Options(headers: _authHeader()),
        );

    Future<Response<dynamic>> _tryRanges2() =>
        _dio.get('/rentals/blocked-dates/$productId', options: Options(headers: _authHeader()));

    try {
      Response r;
      try {
        r = await _tryExpanded();
      } catch (_) {
        try {
          r = await _tryRanges1();
        } catch (_) {
          r = await _tryRanges2();
        }
      }

      final out = <DateTime>{};
      final data = r.data;

      if (data is Iterable) {
        for (final item in data) {
          if (item is String) {
            final dt = DateTime.tryParse(item)?.toLocal();
            if (dt != null) out.add(_day(dt));
            continue;
          }
          if (item is Map) {
            final startStr = item['start']?.toString();
            final endStr = item['end']?.toString();
            if (startStr != null && endStr != null) {
              final start = DateTime.tryParse(startStr)?.toLocal();
              final end = DateTime.tryParse(endStr)?.toLocal();
              if (start != null && end != null) {
                final until = includeEnd ? _day(end).add(const Duration(days: 1)) : _day(end);
                for (DateTime d = _day(start); d.isBefore(until); d = d.add(const Duration(days: 1))) {
                  out.add(_day(d));
                }
                continue;
              }
            }
            final dateStr = item['date']?.toString();
            if (dateStr != null) {
              final dt = DateTime.tryParse(dateStr)?.toLocal();
              if (dt != null) out.add(_day(dt));
              continue;
            }
          }
        }
      }

      return out;
    } catch (_) {
      return <DateTime>{};
    }
  }

  Future<bool> cancelRental(int rentalId) async {
    try {
      Response r;
      try {
        r = await _dio.patch('/rentals/$rentalId/cancel', options: Options(headers: _authHeader()));
      } catch (_) {
        r = await _dio.post('/rentals/$rentalId/cancel', options: Options(headers: _authHeader()));
      }
      return (r.statusCode ?? 0) >= 200 && (r.statusCode ?? 0) < 300;
    } catch (_) {
      return false;
    }
  }

  Future<bool> requestReturn(int rentalId) async {
    try {
      Response r;
      try {
        r = await _dio.patch('/rentals/$rentalId/request-return', options: Options(headers: _authHeader()));
      } catch (_) {
        r = await _dio.post('/rentals/$rentalId/request-return', options: Options(headers: _authHeader()));
      }
      return (r.statusCode ?? 0) >= 200 && (r.statusCode ?? 0) < 300;
    } catch (_) {
      return false;
    }
  }

  Future<bool> confirmReturn(int rentalId) async {
    try {
      Response r;
      try {
        r = await _dio.patch('/rentals/$rentalId/confirm-return', options: Options(headers: _authHeader()));
      } catch (_) {
        r = await _dio.post('/rentals/$rentalId/confirm-return', options: Options(headers: _authHeader()));
      }
      return (r.statusCode ?? 0) >= 200 && (r.statusCode ?? 0) < 300;
    } catch (_) {
      return false;
    }
  }

  // ===== Photos =====
  Map<String, dynamic> _normalizePhoto(Map src) {
    final m = Map<String, dynamic>.from(src);

    // id
    final id = m['id'] ?? m['photo_id'] ?? m['photoId'];
    if (id is num) m['id'] = id.toInt(); else if (id is String) m['id'] = int.tryParse(id);

    // rental_id
    final rid = m['rental_id'] ?? m['rentalId'] ?? m['rental'];
    if (rid is num) {
      m['rental_id'] = rid.toInt();
    } else if (rid is String) {
      m['rental_id'] = int.tryParse(rid);
    }

    // kind/phase
    final kind = (m['kind'] ?? m['phase'] ?? 'BEFORE').toString().toUpperCase();
    m['kind'] = kind;

    // url-ish 필드 수집
    final rawUrl = m['url'] ??
        m['image_url'] ??
        m['imageUrl'] ??
        m['thumbnail_url'] ??
        m['thumbnailUrl'] ??
        m['file_url'] ??
        m['fileUrl'] ??
        m['path'] ??
        m['file'] ??
        m['filepath'] ??
        m['filePath'];
    m['url'] = absolute(rawUrl?.toString());

    // created_at
    final created =
        m['created_at'] ?? m['createdAt'] ?? m['uploaded_at'] ?? m['uploadedAt'];
    if (created != null) m['created_at'] = created.toString();

    return m;
  }

  List _pickList(dynamic raw) {
    if (raw is List) return raw;
    if (raw is Map) {
      final items = raw['items'] ?? raw['data'] ?? raw['results'];
      if (items is List) return items;
    }
    return const [];
  }

  Future<Map<String, dynamic>> uploadRentalPhoto({
    required int rentalId,
    required String filePath,
    String? phase,
    String? kind,
  }) async {
    final fileName = filePath.split(Platform.pathSeparator).last;
    final _kind = (kind ?? phase ?? 'BEFORE');

    try {
      // 여러 서버 구현을 동시에 만족시키기 위해 alias 키 동시 전송
      final form = FormData.fromMap({
        'rental_id': rentalId,
        'rentalId': rentalId,   // alias
        'kind': _kind,
        'phase': _kind,         // alias
        'file': await MultipartFile.fromFile(filePath, filename: fileName),
      });

      try {
        final r = await _dio.post(
          '/photos/upload',
          data: form,
          options: Options(headers: _authHeader()),
        );
        return {'ok': true, 'status': r.statusCode ?? 200, 'data': r.data};
      } catch (_) {
        final r = await _dio.post(
          '/photos/upload/',
          data: form,
          options: Options(headers: _authHeader()),
        );
        return {'ok': true, 'status': r.statusCode ?? 200, 'data': r.data};
      }
    } on DioException catch (e) {
      // ignore: avoid_print
      print('[uploadRentalPhoto] ${e.response?.statusCode} ${e.message} body=${e.response?.data}');
      return {
        'ok': false,
        'status': e.response?.statusCode,
        'data': e.response?.data,
        'message': e.message,
      };
    } catch (e) {
      // ignore: avoid_print
      print('[uploadRentalPhoto] unknown error: $e');
      return {'ok': false, 'status': null, 'message': e.toString()};
    }
  }

  Future<List<Map<String, dynamic>>> getPhotosByRental(int rentalId) async {
    // 다양한 서버 라우트 시도
    final paths = <String>[
      '/photos/by-rental/$rentalId',
      '/photos/by_rental/$rentalId',
      '/rentals/$rentalId/photos',
      '/rental/$rentalId/photos',
      '/photos', // ?rental_id=
    ];

    for (final p in paths) {
      try {
        final Response r = (p == '/photos')
            ? await _dio.get(p,
                queryParameters: {'rental_id': rentalId},
                options: Options(headers: _authHeader()))
            : await _dio.get(p, options: Options(headers: _authHeader()));

        final list = _pickList(r.data);
        if (list.isEmpty) continue;

        return list
            .whereType<Map>()
            .map<Map<String, dynamic>>((e) => _normalizePhoto(e))
            .toList();
      } catch (_) {
        // 다음 경로로 폴백
      }
    }
    return <Map<String, dynamic>>[];
  }

  Future<bool> deletePhoto(int photoId) async {
    try {
      final r =
          await _dio.delete('/photos/$photoId', options: Options(headers: _authHeader()));
      return r.statusCode == 200 || r.statusCode == 204;
    } catch (_) {
      return false;
    }
  }

  // ===== Products (create) =====
  Future<bool> createProduct({
    String? name,
    String? title,
    String? description,
    int? pricePerDay,
    double? dailyPrice,
    String? category,
    String? region,
    String? imageUrl,
    int? ownerId,
    double? deposit,
    double? securityDeposit,
  }) async {
    final resolvedName = (name ?? title ?? '').trim();
    final resolvedPrice = pricePerDay ?? (dailyPrice != null ? dailyPrice.toInt() : null);
    final resolvedDeposit = deposit ?? securityDeposit;

    if (resolvedName.isEmpty || resolvedPrice == null) {
      // ignore: avoid_print
      print('[createProduct] name/price_per_day required');
      return false;
    }

    try {
      final body = <String, dynamic>{
        'name': resolvedName,
        if (description != null) 'description': description,
        'price_per_day': resolvedPrice,
        if (category != null) 'category': category,
        if (region != null) 'region': region,
        if (imageUrl != null) 'image_url': imageUrl,
        if (ownerId != null) 'owner_id': ownerId,
        if (resolvedDeposit != null) 'deposit': resolvedDeposit.toInt(),
      };
      final r =
          await _dio.post('/products', data: body, options: Options(headers: _authHeader()));
      return r.statusCode == 200 || r.statusCode == 201;
    } catch (_) {
      return false;
    }
  }

  Future<bool> createProductWithImage({
    String? name,
    String? title,
    String? description,
    int? pricePerDay,
    double? dailyPrice,
    String? category,
    String? region,
    String? imageUrl,
    required String filePath,
    double? deposit,
    double? securityDeposit,
  }) async {
    final resolvedName = (name ?? title ?? '').trim();
    final resolvedPrice = pricePerDay ?? (dailyPrice != null ? dailyPrice.toInt() : null);
    final resolvedDeposit = deposit ?? securityDeposit;

    if (resolvedName.isEmpty || resolvedPrice == null) {
      // ignore: avoid_print
      print('[createProductWithImage] name/price_per_day required');
      return false;
    }

    try {
      final form = FormData.fromMap({
        'name': resolvedName,
        if (description != null) 'description': description,
        'price_per_day': resolvedPrice,
        if (category != null) 'category': category,
        if (region != null) 'region': region,
        if (imageUrl != null) 'image_url': imageUrl,
        if (resolvedDeposit != null) 'deposit': resolvedDeposit.toInt(),
        'file': await MultipartFile.fromFile(
          filePath,
          filename: filePath.split(Platform.pathSeparator).last,
        ),
      });

      Response r;
      try {
        r = await _dio.post('/products/with-image',
            data: form, options: Options(headers: _authHeader()));
      } catch (_) {
        r = await _dio.post('/products/with-image/',
            data: form, options: Options(headers: _authHeader()));
      }
      return r.statusCode == 200 || r.statusCode == 201;
    } catch (_) {
      return false;
    }
  }

  // ===== My Rentals =====
  Future<List<Map<String, dynamic>>> getMyRentals({bool includeClosed = false}) async {
    try {
      Response r;
      try {
        r = await _dio.get('/rentals/me',
            queryParameters: {'include_inactive': includeClosed},
            options: Options(headers: _authHeader()));
      } catch (_) {
        r = await _dio.get('/rentals/my',
            queryParameters: {'include_closed': includeClosed},
            options: Options(headers: _authHeader()));
      }
      final list = (r.data as List?) ?? const [];
      return list.cast<Map<String, dynamic>>();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  Future<List<Map<String, dynamic>>> listMyRentals({bool includeClosed = false}) {
    return getMyRentals(includeClosed: includeClosed);
  }

  // ===== internals =====
  bool _isAuthEndpoint(String path) {
    return path.startsWith('/auth/login') ||
        path.startsWith('/auth/token') ||
        path.startsWith('/auth/register');
  }

  Future<Response<dynamic>> _retryRequest(RequestOptions req) {
    return _dio.request(
      req.path,
      data: req.data,
      queryParameters: req.queryParameters,
      options: Options(
        method: req.method,
        headers: {
          ...?req.headers,
          ...?_authHeader(),
        },
        contentType: req.contentType,
        responseType: req.responseType,
        followRedirects: req.followRedirects,
        validateStatus: req.validateStatus,
        receiveDataWhenStatusError: req.receiveDataWhenStatusError,
        requestEncoder: req.requestEncoder,
        responseDecoder: req.responseDecoder,
        sendTimeout: req.sendTimeout,
        receiveTimeout: req.receiveTimeout,
      ),
      cancelToken: req.cancelToken,
      onReceiveProgress: req.onReceiveProgress,
      onSendProgress: req.onSendProgress,
    );
  }
}
