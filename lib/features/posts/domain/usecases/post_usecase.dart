import '../entities/post_entity.dart';
import '../repositories/post_repository.dart';

class PostUsecase {
  final PostRepository _postRepository;

  PostUsecase(this._postRepository);

  Future<void> createPost(String content) async => await _postRepository.createPost(content);

  Stream<List<PostEntity>> getServerPosts() => _postRepository.getServerPosts();

  // Stream<List<PostEntity>> watchLocalPosts() async => await _postRepository.watchLocalPosts();
}