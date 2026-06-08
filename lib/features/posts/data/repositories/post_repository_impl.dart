import 'dart:convert';
import 'dart:developer';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart';
import 'package:field_reporter/features/posts/domain/entities/post_entity.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
    // _initSyncEngine();
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

    // Outbox Queue ထဲမှာ ပို့ဖို့ကျန်တာတွေ အကုန်လှမ်းယူမယ်
    final outboxItems = await _database.select(_database.outboxQueue).get();

    log("🔄 Sync Engine Triggered - ${outboxItems.length} item(s) to sync");

    for (var item in outboxItems) {
      try {
        final Map<String, dynamic> payload = jsonDecode(item.payload);
        final int localId = payload['id'];
        final String content = payload['content'];
        final String idempotencyKey = payload['idempotency_key'];

        log("📤 Syncing Local ID: $localId with content: $content");

        await _supabaseClient.from('posts').upsert({'content': content, 'idempotency_key': idempotencyKey}, onConflict: 'idempotency_key').select();

        log("📤 Upserted into Supabase for Local ID: $localId");

        // Update Local DB with synced status
        // await (_database.update(_database.posts)..where((t) => t.id.equals(localId))).write(PostsCompanion(status: const Value('synced')));

        // Delete synced item from Local DB
        await (_database.delete(_database.posts)..where((t) => t.id.equals(localId))).go();
        
        // Delete synced item from Outbox
        await (_database.delete(_database.outboxQueue)..where((t) => t.id.equals(item.id))).go();

        log("✅ Synced Completed for Local ID: $localId");
      } catch (e) {
        log("❌ Sync Engine Paused: $e");
        break;
      }
    }

    // After successfully syncing items, force a refresh of the server cache.
    // This ensures the "Feed" tab (which watches serverPosts table) reflects the new data.
    if (outboxItems.isNotEmpty) {
      try {
        await fetchAndCacheServerPosts(forceRefresh: true);
      } catch (e) {
        log("📡 Auto-refresh of server cache failed: $e");
      }
    }

    _isSyncing = false;
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
      final response = await _supabaseClient.from('posts').select().order('created_at', ascending: false);
      final serverPostsData = List<Map<String, dynamic>>.from(response);

      await _database.transaction(() async {
        for (final json in serverPostsData) {
          await _database.into(_database.serverPosts).insertOnConflictUpdate(ServerPostsCompanion(id: Value(json['id'] as int), content: Value(json['content'] as String), status: Value('synced')));
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
        return PostEntity(id: post.id, content: post.content, status: 'synced');
      }).toList();
    });
  }
}
