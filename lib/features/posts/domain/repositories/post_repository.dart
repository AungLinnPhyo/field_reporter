import '../entities/post_entity.dart';

abstract class PostRepository {
  // Future<void> createPost(String content);
  // Future<List<PostEntity>> getServerPosts();
  // Stream<List<PostEntity>> watchLocalPosts();
  Future<void> createPost(String content);
  Stream<List<PostEntity>> watchLocalPosts();       // TAB 1 အတွက် (Pending & local)
  Stream<List<PostEntity>> watchCachedServerPosts(); // TAB 2 အတွက် (Server Cache စစ်စစ်)
  Future<void> fetchAndCacheServerPosts({bool forceRefresh = false});
}
