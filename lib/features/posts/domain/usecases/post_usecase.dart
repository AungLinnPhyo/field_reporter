import '../entities/post_entity.dart';
import '../repositories/post_repository.dart';

class PostUsecase {
  final PostRepository _postRepository;

  PostUsecase(this._postRepository);

  Future<void> createPost(String content) async => await _postRepository.createPost(content);

  Stream<List<PostEntity>> getServerPosts() => _postRepository.getServerPosts();

  // Stream<List<PostEntity>> watchLocalPosts() async => await _postRepository.watchLocalPosts();

  Future<void> deletePost(int id) async => await _postRepository.deletePost(id);
  Future<void> retryPost(PostEntity post) async => await _postRepository.retryPost(post);
}
