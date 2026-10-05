class CustomerNotification {
  final String notificationId;
  final String title;
  final String message;
  final int recipients;
  final bool isRead;
  final DateTime? createdAt;

  const CustomerNotification({
    required this.notificationId,
    required this.title,
    required this.message,
    this.recipients = 1,
    this.isRead = false,
    this.createdAt,
  });

  CustomerNotification copyWith({
    String? notificationId,
    String? title,
    String? message,
    int? recipients,
    bool? isRead,
    DateTime? createdAt,
  }) {
    return CustomerNotification(
      notificationId: notificationId ?? this.notificationId,
      title: title ?? this.title,
      message: message ?? this.message,
      recipients: recipients ?? this.recipients,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  factory CustomerNotification.fromJson(Map<String, dynamic> json) {
    bool parseIsRead(dynamic value) {
      if (value is bool) return value;
      if (value is num) return value != 0;
      if (value is String) {
        final lower = value.toLowerCase().trim();
        return lower == '1' || lower == 'true';
      }
      return false;
    }

    DateTime? parseDate(dynamic value) {
      if (value == null) return null;
      if (value is DateTime) return value;
      if (value is String && value.isNotEmpty) {
        try {
          return DateTime.parse(value).toLocal();
        } catch (_) {
          return null;
        }
      }
      return null;
    }

    return CustomerNotification(
      notificationId: (json['notification_id'] ?? json['id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      message: (json['message'] ?? json['body'] ?? '').toString(),
      recipients: json['recipients'] is num
          ? (json['recipients'] as num).toInt()
          : int.tryParse(json['recipients']?.toString() ?? '1') ?? 1,
      isRead: parseIsRead(json['is_read']),
      createdAt: parseDate(json['created_at']),
    );
  }

  String get formattedTime {
    if (createdAt == null) return '';
    final now = DateTime.now();
    final diff = now.difference(createdAt!);

    if (diff.isNegative) {
      return 'Just now';
    }
    if (diff.inSeconds < 60) {
      return 'Just now';
    }
    if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    }
    if (diff.inHours < 24) {
      return '${diff.inHours} hr ago';
    }
    if (diff.inDays == 1) {
      return 'Yesterday';
    }
    if (diff.inDays < 7) {
      return '${diff.inDays} days ago';
    }

    final d = createdAt!.day.toString().padLeft(2, '0');
    final m = createdAt!.month.toString().padLeft(2, '0');
    final y = createdAt!.year;
    return '$d/$m/$y';
  }
}
