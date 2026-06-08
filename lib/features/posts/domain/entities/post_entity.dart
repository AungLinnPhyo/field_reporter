class PostEntity {
  final int id;
  final String content;
  final String status;
  final String? localStatus;

  PostEntity({
    required this.id,
    required this.content,
    required this.status,
    this.localStatus,
  });
}