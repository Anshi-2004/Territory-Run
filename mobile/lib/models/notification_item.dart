class NotificationItem {
  final String id;
  final String title;
  final String message;
  final String? h3Index;
  final String? displacedBy;
  final DateTime createdAt;
  bool isRead;

  NotificationItem({
    required this.id,
    required this.title,
    required this.message,
    this.h3Index,
    this.displacedBy,
    required this.createdAt,
    required this.isRead,
  });

  factory NotificationItem.fromJson(Map<String, dynamic> json) {
    return NotificationItem(
      id: json['id'] ?? '',
      title: json['title'] ?? 'Alert',
      message: json['message'] ?? '',
      h3Index: json['h3_index'],
      displacedBy: json['displaced_by'],
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
      isRead: json['is_read'] ?? false,
    );
  }
}
