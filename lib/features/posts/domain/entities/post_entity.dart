class PostEntity {
  final int id;
  final String content;
  final String status; // 'pending', 'synced', 'conflict', 'failed'
  final DateTime createdAt;

  PostEntity({
    required this.id,
    required this.content,
    required this.status,
    required this.createdAt,
  });
}