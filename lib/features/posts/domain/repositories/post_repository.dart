import '../entities/post_entity.dart';

abstract class PostRepository {
  // Future<void> createPost(String content);
  // Future<List<PostEntity>> getServerPosts();
  // Stream<List<PostEntity>> watchLocalPosts();
  Future<void> createPost(String content);
  Stream<List<PostEntity>> watchLocalPosts(); // Local 
  Stream<List<PostEntity>> watchCachedServerPosts(); // Server Cache
  Future<void> fetchAndCacheServerPosts({bool forceRefresh = false});
  Future<void> updateServerPost(int id, String newContent);
  Future<void> deleteServerPost(int id);
}
