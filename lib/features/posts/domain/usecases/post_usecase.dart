import '../entities/post_entity.dart';
import '../repositories/post_repository.dart';

class PostUsecase {
  final PostRepository _postRepository;

  PostUsecase(this._postRepository);

  Future<void> createPost(String content) async => await _postRepository.createPost(content);

  // Future<List<PostEntity>> getServerPosts() async => await _postRepository.getServerPosts();

  Stream<List<PostEntity>> watchLocalPosts() => _postRepository.watchLocalPosts();

  Stream<List<PostEntity>> watchCachedServerPosts() => _postRepository.watchCachedServerPosts();

  Future<void> fetchAndCacheServerPosts({bool forceRefresh = false}) async => await _postRepository.fetchAndCacheServerPosts(forceRefresh: forceRefresh);
}
