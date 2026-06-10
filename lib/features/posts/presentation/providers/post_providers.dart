import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../config/dependency_injections/dependency_injections.dart';
import '../../../../shared/enums/sync_engine_enums.dart';
import '../../domain/entities/post_entity.dart';

/// Local Posts များကို UI တွင် စောင့်ကြည့်ရန် Stream
final postsStreamProvider = StreamProvider<List<PostEntity>>((ref) {
  final repository = ref.watch(
    postRepositoryProvider,
  ); // DI မှ Repository ကို ယူသည်
  return repository.watchLocalPosts();
});

/// Server Posts များကို ဆွဲယူရန် Future
// final serverPostsFutureProvider = FutureProvider<List<PostEntity>>((ref) async {
//   final useCase = ref.watch(postUsecaseProvider); // DI မှ Usecase ကို ယူသည်
//   return await useCase.getServerPosts();
// });
final serverPostsStreamProvider = StreamProvider<List<PostEntity>>((ref) {
  // သင့်ရဲ့ UseCase သို့မဟုတ် Repository ထံမှ Supabase Stream ကို လှမ်းယူခြင်း
  // (ဥပမာ - supabase.from('posts').stream(primaryKey: ['id']).order('created_at').map(...))
  final useCase = ref.watch(postUsecaseProvider); 
  return useCase.getServerPosts(); 
});

/// Sync Engine ၏ အခြေအနေ စောင့်ကြည့်ရန် Stream
final syncStatusProvider = StreamProvider<SyncEngineEnums>((ref) async* {
  final engine = ref.watch(syncEngineProvider); // DI မှ Engine ကို ယူသည်

  yield engine.status;
  await for (final status in engine.statusStream) {
    yield status;
  }
});
