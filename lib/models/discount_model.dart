class DiscountModel {
  final int id;
  final String subscriberUsername;
  final int subscriberId;
  final double discountAmount;
  final String? packageName;
  final double? packagePrice;
  final String? createdAt;

  const DiscountModel({
    required this.id,
    required this.subscriberUsername,
    required this.subscriberId,
    required this.discountAmount,
    this.packageName,
    this.packagePrice,
    this.createdAt,
  });

  factory DiscountModel.fromJson(Map<String, dynamic> json) {
    return DiscountModel(
      id: json['id'] is int ? json['id'] : int.tryParse(json['id']?.toString() ?? '0') ?? 0,
      subscriberUsername: (json['subscriber_username'] ?? '').toString(),
      subscriberId: json['subscriber_id'] is int ? json['subscriber_id'] : int.tryParse(json['subscriber_id']?.toString() ?? '0') ?? 0,
      discountAmount: json['discount_amount'] is num ? (json['discount_amount'] as num).toDouble() : double.tryParse(json['discount_amount']?.toString() ?? '0') ?? 0,
      packageName: json['package_name']?.toString(),
      packagePrice: json['package_price'] is num ? (json['package_price'] as num).toDouble() : double.tryParse(json['package_price']?.toString() ?? ''),
      createdAt: json['created_at']?.toString(),
    );
  }
}
