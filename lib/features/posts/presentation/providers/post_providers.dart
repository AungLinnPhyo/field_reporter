import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:field_reporter/core/offline/offline_sync_engine.dart';
import 'package:field_reporter/core/offline/sync_config.dart';

import '../../data/data_sources/local_database.dart';
import '../../data/repositories/post_repository_impl.dart';
import '../../domain/entities/post_entity.dart';
import '../../domain/repositories/post_repository.dart';
import '../../domain/usecases/post_usecase.dart';

///Local Database Provider
final databaseProvider = Provider<AppDatabase>((ref) {
  return AppDatabase();
});

/// Supabase Client Provider
final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

/// Offline Sync Engine Provider
final syncEngineProvider = Provider<OfflineSyncEngine>((ref) {
  final database = ref.watch(databaseProvider);
  final supabaseClient = ref.watch(supabaseClientProvider);

  final engine = OfflineSyncEngine(
    outboxRepository: database,
    config: const SyncConfig(
      maxRetries: 3,
      cleanupDuration: Duration(days: 7), // Synced data retention period
    ),
  );

  // Register feature processors and cleanup handlers
  engine.registerProcessor(PostSyncProcessor(database, supabaseClient));
  engine.registerCleanupHandler(PostCleanupHandler(database));

  // Trigger initial sync run
  engine.triggerSync();

  return engine;
});

/// Post Repository Provider
final postRepositoryProvider = Provider<PostRepository>((ref) {
  final database = ref.watch(databaseProvider);
  final supabaseClient = ref.watch(supabaseClientProvider);
  return PostRepositoryImpl(database, supabaseClient);
});

/// Post Usecase Provider
final postUsecaseProvider = Provider<PostUsecase>((ref) {
  final postRepository = ref.watch(postRepositoryProvider);
  return PostUsecase(postRepository);
});

/// Posts Stream Provider
final postsStreamProvider = StreamProvider<List<PostEntity>>((ref) {
  final repository = ref.watch(postRepositoryProvider);
  return repository.watchLocalPosts();
});

/// Posts Stream Provider
final serverPostsFutureProvider = FutureProvider<List<PostEntity>>((ref) async {
  final useCase = ref.watch(postUsecaseProvider);
  return await useCase.getServerPosts();
});

/// Sync Status Stream Provider
final syncStatusProvider = StreamProvider<SyncEngineStatus>((ref) async* {
  final engine = ref.watch(syncEngineProvider);
  yield engine.status; // Initial value
  await for (final status in engine.statusStream) {
    yield status;
  }
});


