import '../entities/post_entity.dart';

abstract class PostRepository {
  Future<void> createPost(String content);
  Future<List<PostEntity>> getServerPosts();
  Stream<List<PostEntity>> watchLocalPosts();
}
