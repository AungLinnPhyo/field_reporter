import 'dart:convert';
import 'dart:developer';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data_sources/local_database.dart';

class PostRepositoryImpl {
  final AppDatabase _database;
  final SupabaseClient _supabaseClient;
  bool _isSyncing = false;

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

  Future<void> createPost(String content) async {
    await _database.insertPostToOutbox(content);
  }

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

        log("📤 Syncing Local ID: $localId with content: $content");

        await _supabaseClient.from('posts').insert({'content': content});

        log("📤 Inserted into Supabase for Local ID: $localId");

        await (_database.update(_database.posts)..where((t) => t.id.equals(localId))).write(PostsCompanion(status: const Value('synced')));

        await (_database.delete(_database.outboxQueue)..where((t) => t.id.equals(item.id))).go();

        log("✅ Synced Completed for Local ID: $localId");
      } catch (e) {
        log("❌ Sync Engine Paused: $e");
        break;
      }
    }

    _isSyncing = false;
  }
}
