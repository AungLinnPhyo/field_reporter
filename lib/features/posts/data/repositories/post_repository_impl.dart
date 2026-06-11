import 'dart:convert';
import 'dart:developer';

import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/offline/offline_cleanup_handler.dart';
import '../../../../core/offline/outbox_action_processor.dart';
import '../../domain/entities/post_entity.dart';
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
  Stream<List<PostEntity>> getServerPosts() {
    try {
      final response = _supabaseClient.from('posts').stream(primaryKey: ['id']).order('created_at', ascending: false);

      return response.map((json) {
        // 1. Raw JSON List မှ List<Map<String, dynamic>> ကို သေချာယူသည်
        final List rawList = json as List;

        // 2. Map<String, dynamic> စာရင်းတစ်ခုအဖြစ် ပြောင်းပေးသည်
        final List<Map<String, dynamic>> jsonList = rawList.map((e) => e as Map<String, dynamic>).toList();

        // 3. အစအဆုံး စီထားသောစာရင်းအဖြစ် ပြောင်းသည်
        return jsonList.map((json) => PostModel.fromJson(json)).toList();
      });
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

  @override
  Future<void> deletePost(int id) async {
    await _database.transaction(() async {
      await (_database.delete(_database.posts)..where((t) => t.id.equals(id))).go();
      await (_database.delete(_database.outboxQueue)..where((t) => t.payload.like('%"id":$id%') | t.payload.like('%"id":"$id"%'))).go();
    });
  }

  @override
  Future<void> retryPost(PostEntity post) async {
    await _database.transaction(() async {
      await (_database.update(_database.posts)..where((t) => t.id.equals(post.id))).write(const PostsCompanion(status: Value('pending'), nextRetryAt: Value(null)));
      await _database
          .into(_database.outboxQueue)
          .insert(OutboxQueueCompanion.insert(actionType: 'create_post', payload: jsonEncode({'id': post.id, 'content': post.content}), status: const Value('pending')));
    });
  }
}

/// Outbox queue ထဲက ပို့စ်တွေကို နောက်ကွယ်ကနေ ဆာဗာပေါ် လိုက်တင်ပေးမည့် Processor
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

    log("📤 [PostSyncProcessor] Syncing Post ID: $localId (content: $content)", name: 'PostSyncProcessor');

    // Sync to Supabase. This can throw network exceptions or DB unique constraint violations
    await _supabaseClient.from('posts').insert({'content': content});

    log("✅ [PostSyncProcessor] Synced to Supabase for local ID: $localId", name: 'PostSyncProcessor');

    // Update local post status to synced
    await (_database.update(_database.posts)..where((t) => t.id.equals(localId))).write(const PostsCompanion(status: Value('synced'), nextRetryAt: Value(null)));
  }

  @override
  Future<void> onConflict(Object error, Map<String, dynamic> payload) async {
    final int localId = payload['id'];
    log("⚠️ [PostSyncProcessor] Conflict encountered for local ID $localId: $error", name: 'PostSyncProcessor');

    // Update local post status to conflict
    await (_database.update(_database.posts)..where((t) => t.id.equals(localId))).write(const PostsCompanion(status: Value('conflict'), nextRetryAt: Value(null)));
  }

  @override
  Future<void> onFailure(Object error, Map<String, dynamic> payload, int currentRetries) async {
    final int localId = payload['id'];
    log("❌ [PostSyncProcessor] Permanent failure for local ID $localId (Retries: $currentRetries): $error", name: 'PostSyncProcessor');

    // Update local post status to failed
    await (_database.update(_database.posts)..where((t) => t.id.equals(localId))).write(const PostsCompanion(status: Value('failed'), nextRetryAt: Value(null)));
  }
}

/// Database cleaner for synced posts older than the retention duration
class PostCleanupHandler implements OfflineCleanupHandler {
  final AppDatabase _database;

  PostCleanupHandler(this._database);

  @override
  Future<void> cleanup(Duration retentionDuration) async {
    // လက်ရှိအချိန်ကနေ သတ်မှတ်ထားတဲ့ သက်တမ်း (ဥပမာ ရက်ပေါင်း ၃၀) ကို နှုတ်ပြီး သတ်မှတ်ရက် တစ်ခုတွက်ထုတ်သည်
    final cutoffDate = DateTime.now().subtract(retentionDuration);

    // သက်တမ်းကျော်နေတဲ့ Data တွေကို ဖျက်ထုတ်သည်
    final count = await (_database.delete(_database.posts)..where((t) => t.status.equals('synced') & t.createdAt.isSmallerThanValue(cutoffDate))).go();

    log("🧹 [PostCleanupHandler] Deleted $count synced posts older than threshold", name: 'PostCleanupHandler');
  }
}
