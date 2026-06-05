import '../../data/repositories/post_repository_impl.dart';

class PostUsecase {
  final PostRepositoryImpl _postRepository;

  PostUsecase(this._postRepository);

  Future<void> createPost(String content) async {
    if (content.trim().isEmpty) return; // Prevent creating empty posts
    await _postRepository.createPost(content);
  }
}