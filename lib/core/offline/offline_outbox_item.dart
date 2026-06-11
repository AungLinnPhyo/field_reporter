class OfflineOutboxItem {
  final int id;
  final String actionType;
  final String payload;
  final int retryCount;
  final int maxRetries;
  final String status;
  final String? lastError;
  final DateTime createdAt;
  final DateTime? nextRetryAt;
  final DateTime? updatedAt;

  const OfflineOutboxItem({
    required this.id,
    required this.actionType,
    required this.payload,
    required this.retryCount,
    required this.maxRetries,
    required this.status,
    this.lastError,
    required this.createdAt,
    this.nextRetryAt,
    this.updatedAt,
  });
}
