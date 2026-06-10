
import '../../domain/entities/post_entity.dart';
import '../data_sources/local_database.dart';

class PostModel extends PostEntity {
  PostModel({
    required super.id,
    required super.content,
    required super.status,
    required super.createdAt,
  });

  factory PostModel.fromJson(Map<String, dynamic> json) => PostModel(
    id: json['id'] as int,
    content: json['content'] as String,
    status: 'synced', // Synced by default
    createdAt: json['created_at'] != null 
        ? DateTime.parse(json['created_at'] as String) 
        : DateTime.now(),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'content': content,
    'status': status,
    'created_at': createdAt.toIso8601String(),
  };

  factory PostModel.fromDrift(Post driftPost) {
    return PostModel(
      id: driftPost.id,
      content: driftPost.content,
      status: driftPost.status,
      createdAt: driftPost.createdAt,
    );
  }
}