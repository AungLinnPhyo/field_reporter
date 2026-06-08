import 'dart:convert';
import 'dart:developer';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/entities/post_entity.dart';
import '../../domain/repositories/post_repository.dart';
import '../data_sources/local_database.dart';
import '../models/post_model.dart';

class PostRepositoryImpl implements PostRepository {
  final AppDatabase _database;
  final SupabaseClient _supabaseClient;
  bool _isSyncing = false;

  DateTime? _lastFetchTime;
  static const _cacheDuration = Duration(minutes: 5);

  PostRepositoryImpl(this._database, this._supabaseClient) {
    // 🚀 Check and sync immediately on startup
    triggerSyncEngine();

    // Watch the connectivity
    Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
      // အင်တာနက် ပြန်ပွင့်လာပြီဆိုလျှင် (none မဟုတ်တော့လျှင်) Sync Engine ကို လှမ်းနှိုးမည်
      if (!results.contains(ConnectivityResult.none)) {
        log("🌐 အင်တာနက် ပြန်ပွင့်လာပြီ - Sync Engine ကို နှိုးနေပါသည်...");
        triggerSyncEngine();
      }
    });

    // 📥 Local DB ရဲ့ Outbox ထဲ သတင်းအသစ် ဝင်လာတိုင်းလည်း လှမ်းနှိုးခြင်း
    _database.select(_database.outboxQueue).watch().listen((items) {
      if (items.isNotEmpty) {
        triggerSyncEngine();
      }
    });
  }

  // Sync Engine
  Future<void> triggerSyncEngine() async {
    if (_isSyncing) return;
    _isSyncing = true;

    try {
      // Continue looping as long as there are items and internet is available
      while (true) {
        final connectivity = await Connectivity().checkConnectivity();
        if (connectivity.contains(ConnectivityResult.none)) {
          log("📡 Sync Engine: No internet connection. Standing by...");
          break;
        }

        final outboxItems = await _database.select(_database.outboxQueue).get();
        if (outboxItems.isEmpty) break;

        log("🔄 Sync Engine: Processing ${outboxItems.length} item(s)");

        for (var item in outboxItems) {
          try {
            final Map<String, dynamic> payload = jsonDecode(item.payload);

            if (item.actionType == 'create_post') {
              final int localId = payload['id'];
              final String content = payload['content'];
              final String idempotencyKey = payload['idempotency_key'];

              await _supabaseClient.from('posts').upsert({'content': content, 'idempotency_key': idempotencyKey}, onConflict: 'idempotency_key').select();

              await (_database.delete(_database.posts)..where((t) => t.id.equals(localId))).go();
            } else if (item.actionType == 'edit_post') {
              final int serverId = payload["post_id"];
              final String newContent = payload['content'];

              await _supabaseClient.from('posts').update({'content': newContent}).eq('id', serverId);

              await (_database.update(_database.serverPosts)..where((t) => t.id.equals(serverId))).write(ServerPostsCompanion(localStatus: const Value(null)));
            } else if (item.actionType == 'delete_post') {
              final int serverId = payload['post_id'];

              await _supabaseClient.from('posts').delete().eq('id', serverId);

              await (_database.delete(_database.serverPosts)..where((t) => t.id.equals(serverId))).go();
            }

            // Remove from outbox ONLY after successful Supabase operation
            await (_database.delete(_database.outboxQueue)..where((t) => t.id.equals(item.id))).go();
            log("✅ Sync Completed: ${item.actionType}");
          } catch (e) {
            log("❌ Item Sync Failed (${item.actionType}): $e");
            return; // Exit the loop on error to prevent out-of-order syncs
          }
        }

        // Force refresh server cache after a batch is done
        try {
          await fetchAndCacheServerPosts(forceRefresh: true);
        } catch (e) {
          log("📡 Auto-refresh of server cache failed: $e");
        }
      }
    } catch (e) {
      log("❌ Sync Engine Fatal Error: $e");
    } finally {
      _isSyncing = false;
    }
  }

  @override
  Future<void> createPost(String content) async {
    await _database.insertPostToOutbox(content);
  }

  @override
  Stream<List<PostEntity>> watchLocalPosts() {
    return (_database.select(_database.posts)..orderBy([(t) => OrderingTerm(expression: t.id, mode: OrderingMode.desc)])).watch().map((driftPosts) {
      return driftPosts.map((post) => PostModel.fromDrift(post)).toList();
    });
  }

  @override
  Future<void> fetchAndCacheServerPosts({bool forceRefresh = false}) async {
    final now = DateTime.now();
    if (!forceRefresh && _lastFetchTime != null && now.difference(_lastFetchTime!) < _cacheDuration) {
      return;
    }

    try {
      // Local မှာ ပြင်ဆင်ဆဲ (သို့) ဖျက်ဆဲဖြစ်နေသော ID များကို ရှာဖွေခြင်း
      final pendingItems = await (_database.select(_database.serverPosts)..where((t) => t.localStatus.isNotNull())).get();
      final pendingIds = pendingItems.map((e) => e.id).toSet();

      final response = await _supabaseClient.from('posts').select().order('created_at', ascending: false);
      final serverPostsData = List<Map<String, dynamic>>.from(response);

      await _database.transaction(() async {
        for (final json in serverPostsData) {
          final serverId = json['id'] as int;

          // 🔥 အကယ်၍ ဤ ID သည် အော့ဖ်လိုင်းတွင် ပြင်ဆင်နေဆဲ ID ဖြစ်ပါက ဆာဗာဒေတာဟောင်းဖြင့် Overwrite မလုပ်ဘဲ ကျော်သွားမည်!
          if (pendingIds.contains(serverId)) continue;

          await _database.into(_database.serverPosts).insertOnConflictUpdate(ServerPostsCompanion(id: Value(serverId), content: Value(json['content'] as String)));
        }
      });
      _lastFetchTime = now;
    } catch (e) {
      log("📡 Offline: Using server cached table data. $e");
      rethrow;
    }
  }

  @override
  Stream<List<PostEntity>> watchCachedServerPosts() {
    return (_database.select(_database.serverPosts)..orderBy([(t) => OrderingTerm(expression: t.id, mode: OrderingMode.desc)])).watch().map((driftServerPosts) {
      return driftServerPosts.map((post) {
        return PostEntity(id: post.id, content: post.content, status: 'synced', localStatus: post.localStatus);
      }).toList();
    });
  }

  @override
  Future<void> deleteServerPost(int id) async {
    await _database.transaction(() async {
      await (_database.update(_database.serverPosts)..where((tbl) => tbl.id.equals(id))).write(ServerPostsCompanion(localStatus: const Value('pending_delete')));

      final payload = jsonEncode({'post_id': id});

      await _database.into(_database.outboxQueue).insert(OutboxQueueCompanion.insert(actionType: 'delete_post', payload: payload));
    });
  }

  @override
  Future<void> updateServerPost(int id, String newContent) async {
    await _database.transaction(() async {
      // Update local cache state immediately
      await (_database.update(_database.serverPosts)..where((t) => t.id.equals(id))).write(ServerPostsCompanion(content: Value(newContent), localStatus: const Value('pending_update')));

      // Add to sync queue
      final payload = jsonEncode({'post_id': id, 'content': newContent});
      await _database.into(_database.outboxQueue).insert(OutboxQueueCompanion.insert(actionType: 'edit_post', payload: payload));
    });
  }
}
