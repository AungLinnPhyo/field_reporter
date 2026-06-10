import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/offline/offline_sync_engine.dart';
import '../../core/offline/sync_config.dart';
import '../../features/posts/data/data_sources/local_database.dart';
import '../../features/posts/data/repositories/post_repository_impl.dart';
import '../../features/posts/domain/repositories/post_repository.dart';
import '../../features/posts/domain/usecases/post_usecase.dart';

// ==========================================
// 🏗️ INFRASTRUCTURE & ENGINES DI
// ==========================================

/// Local Database Instance
final databaseProvider = Provider<AppDatabase>((ref) {
  return AppDatabase();
});

/// Supabase Client Instance
final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

/// Offline Sync Engine Setup
final syncEngineProvider = Provider<OfflineSyncEngine>((ref) {
  final database = ref.watch(databaseProvider);
  final supabaseClient = ref.watch(supabaseClientProvider);

  final engine = OfflineSyncEngine(
    outboxRepository: database,
    config: const SyncConfig(maxRetries: 5, cleanupDuration: Duration(days: 7)),
  );

  // Register Handlers
  engine.registerProcessor(PostSyncProcessor(database, supabaseClient));
  engine.registerCleanupHandler(PostCleanupHandler(database));

  // Init Sync
  engine.triggerSync();

  return engine;
});

// ==========================================
// 🎯 REPOSITORIES & USECASES DI
// ==========================================

/// Post Repository DI
final postRepositoryProvider = Provider<PostRepository>((ref) {
  final database = ref.watch(databaseProvider);
  final supabaseClient = ref.watch(supabaseClientProvider);
  return PostRepositoryImpl(database, supabaseClient);
});

/// Post Usecase DI
final postUsecaseProvider = Provider<PostUsecase>((ref) {
  final postRepository = ref.watch(postRepositoryProvider);
  return PostUsecase(postRepository);
});
