import 'dart:developer';

import 'package:drift/drift.dart';
import 'package:field_reporter/core/offline/offline_cleanup_handler.dart';
import 'package:field_reporter/core/offline/outbox_action_processor.dart';
import 'package:field_reporter/features/posts/domain/entities/post_entity.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/repositories/post_repository.dart';
import '../data_sources/local_database.dart';
import '../models/post_model.dart';

class PostRepositoryImpl implements PostRepository {
  final AppDatabase _database;
  final SupabaseClient _supabaseClient;

  PostRepositoryImpl(this._database, this._supabaseClient);

  @override
  Future<void> createPost(String content) async {
    await _database.insertPostToOutbox(content);
  }

  @override
  Future<List<PostEntity>> getServerPosts() async {
    try {
      final response = await _supabaseClient
          .from('posts')
          .select()
          .order('created_at', ascending: false);

      return List<Map<String, dynamic>>.from(
        response,
      ).map((json) => PostModel.fromJson(json)).toList();
    } catch (e) {
      throw Exception("ဆာဗာမှ ဒေတာဆွဲယူ၍ မရပါ - $e");
    }
  }

  @override
  Stream<List<PostEntity>> watchLocalPosts() {
    return _database.select(_database.posts).watch().map((driftPosts) {
      return driftPosts.map((post) => PostModel.fromDrift(post)).toList();
    });
  }
}

/// Processor to sync posts added to the outbox queue
class PostSyncProcessor implements OutboxActionProcessor {
  final AppDatabase _database;
  final SupabaseClient _supabaseClient;

  PostSyncProcessor(this._database, this._supabaseClient);

  @override
  String get actionType => 'create_post';

  @override
  Future<void> process(Map<String, dynamic> payload) async {
    final String content = payload['content'];
    final int localId = payload['id'];

    log(
      "📤 [PostSyncProcessor] Syncing Post ID: $localId (content: $content)",
      name: 'PostSyncProcessor',
    );

    // Sync to Supabase. This can throw network exceptions or DB unique constraint violations
    await _supabaseClient.from('posts').insert({'content': content});

    log(
      "✅ [PostSyncProcessor] Synced to Supabase for local ID: $localId",
      name: 'PostSyncProcessor',
    );

    // Update local post status to synced
    await (_database.update(_database.posts)
          ..where((t) => t.id.equals(localId)))
        .write(const PostsCompanion(status: Value('synced')));
  }

  @override
  Future<void> onConflict(Object error, Map<String, dynamic> payload) async {
    final int localId = payload['id'];
    log(
      "⚠️ [PostSyncProcessor] Conflict encountered for local ID $localId: $error",
      name: 'PostSyncProcessor',
    );

    // Update local post status to conflict
    await (_database.update(_database.posts)
          ..where((t) => t.id.equals(localId)))
        .write(const PostsCompanion(status: Value('conflict')));
  }

  @override
  Future<void> onFailure(
    Object error,
    Map<String, dynamic> payload,
    int currentRetries,
  ) async {
    final int localId = payload['id'];
    log(
      "❌ [PostSyncProcessor] Permanent failure for local ID $localId (Retries: $currentRetries): $error",
      name: 'PostSyncProcessor',
    );

    // Update local post status to failed
    await (_database.update(_database.posts)
          ..where((t) => t.id.equals(localId)))
        .write(const PostsCompanion(status: Value('failed')));
  }
}

/// Database cleaner for synced posts older than the retention duration
class PostCleanupHandler implements OfflineCleanupHandler {
  final AppDatabase _database;

  PostCleanupHandler(this._database);

  @override
  Future<void> cleanup(Duration retentionDuration) async {
    final cutoffDate = DateTime.now().subtract(retentionDuration);

    // Delete synced posts older than retention period
    final count =
        await (_database.delete(_database.posts)..where(
              (t) =>
                  t.status.equals('synced') &
                  t.createdAt.isSmallerThanValue(cutoffDate),
            ))
            .go();

    log(
      "🧹 [PostCleanupHandler] Deleted $count synced posts older than threshold",
      name: 'PostCleanupHandler',
    );
  }
}
