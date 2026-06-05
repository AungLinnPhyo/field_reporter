import 'package:riverpod/riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/data_sources/local_database.dart';
import '../../data/repositories/post_repository_impl.dart';
import '../../domain/usecases/post_usecase.dart';

///Local Database Provider
final databaseProvider = Provider<AppDatabase>((ref) {
  return AppDatabase();
});

/// Post Stream Provider
final postsStreamProvider = StreamProvider<List<Post>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.posts)).watch();
},);

/// Supabase Client Provider
final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

/// Post Repository Provider
final postRepositoryProvider = Provider<PostRepositoryImpl>((ref) {
  final database = ref.watch(databaseProvider);
  final supabaseClient = ref.watch(supabaseClientProvider);
  return PostRepositoryImpl(database, supabaseClient);
});

/// Post Usecase Provider
final postUsecaseProvider = Provider<PostUsecase>((ref) {
  final postRepository = ref.watch(postRepositoryProvider);
  return PostUsecase(postRepository);
});
