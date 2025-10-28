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

  factory Product.fromJson(Map<String, dynamic> j) {
    return Product(
      id: j['id'] as int,
      title: j['title'] as String,
      description: j['description'] as String?,
      imageUrl: j['image_url'] as String?,
      category: j['category'] as String?,
      region: j['region'] as String?,
      dailyPrice: (j['daily_price'] as num).toDouble(),
      deposit: (j['deposit'] as num).toDouble(),
      isRentable: j['is_rentable'] as bool? ?? true,
      isPurchasable: j['is_purchasable'] as bool? ?? true,
    );
  }
}
