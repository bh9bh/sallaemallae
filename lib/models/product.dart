// FILE: lib/models/product.dart
class Product {
  final int id;
  final String title;
  final String? description;
  final String? imageUrl;
  final String? category;
  final String? region;
  final double dailyPrice;
  final double deposit;
  final bool isRentable;
  final bool isPurchasable;

  Product({
    required this.id,
    required this.title,
    this.description,
    this.imageUrl,
    this.category,
    this.region,
    required this.dailyPrice,
    required this.deposit,
    required this.isRentable,
    required this.isPurchasable,
  });

  /// 숫자/문자 혼합 응답 대비 안전 파서
  static int _asInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }

  static double _asDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is double) return v;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  static bool _asBool(dynamic v, {bool fallback = true}) {
    if (v == null) return fallback;
    if (v is bool) return v;
    final s = v.toString().toLowerCase();
    if (s == 'true' || s == '1') return true;
    if (s == 'false' || s == '0') return false;
    return fallback;
  }

  static String? _asStringOrNull(dynamic v) {
    if (v == null) return null;
    final s = v.toString();
    return s.isEmpty ? null : s;
  }

  /// 백엔드가 snake_case / camelCase 를 섞어 보내도 수용
  factory Product.fromJson(Map<String, dynamic> j) {
    final map = j;

    String? _pick(List<String> keys) {
      for (final k in keys) {
        if (map.containsKey(k) && map[k] != null) {
          final v = map[k];
          if (v is String && v.isEmpty) continue;
          return v.toString();
        }
      }
      return null;
    }

    dynamic _pickRaw(List<String> keys) {
      for (final k in keys) {
        if (map.containsKey(k)) return map[k];
      }
      return null;
    }

    return Product(
      id: _asInt(_pickRaw(['id', 'product_id'])),
      title: _pick(['title', 'name']) ?? '제목 없음',
      description: _pick(['description', 'desc']),
      imageUrl: _pick(['image_url', 'imageUrl', 'image', 'thumb']),
      category: _pick(['category']),
      region: _pick(['region', 'location']),
      dailyPrice: _asDouble(_pickRaw(['daily_price', 'dailyPrice', 'price_per_day', 'pricePerDay'])),
      deposit: _asDouble(_pickRaw(['deposit', 'security_deposit'])),
      isRentable: _asBool(_pickRaw(['is_rentable', 'isRentable']), fallback: true),
      isPurchasable: _asBool(_pickRaw(['is_purchasable', 'isPurchasable']), fallback: true),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'image_url': imageUrl,
        'category': category,
        'region': region,
        'daily_price': dailyPrice,
        'deposit': deposit,
        'is_rentable': isRentable,
        'is_purchasable': isPurchasable,
      };
}
