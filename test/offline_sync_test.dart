import 'dart:async';
import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import 'package:field_reporter/core/offline/offline_sync_engine.dart';
import 'package:field_reporter/core/offline/sync_config.dart';
import 'package:field_reporter/core/offline/outbox_action_processor.dart';
import 'package:field_reporter/core/offline/offline_cleanup_handler.dart';
import 'package:field_reporter/features/posts/data/data_sources/local_database.dart';
import 'package:drift/drift.dart' show Value;

/// Fake Connectivity that simulates online status
class FakeConnectivity implements Connectivity {
  final List<ConnectivityResult> _status;
  FakeConnectivity(this._status);

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => _status;

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => Stream.value(_status);
}

/// Fake processor that registers execution events to verify sync actions
class FakePostProcessor implements OutboxActionProcessor {
  final AppDatabase database;
  final List<String> processedLogs = [];
  
  // Controls behavior of the process call for testing
  Future<void> Function(Map<String, dynamic> payload)? onProcessOverride;
  
  Object? lastConflictError;
  Object? lastFailureError;

  FakePostProcessor(this.database);

  @override
  String get actionType => 'create_post';

  @override
  Future<void> process(Map<String, dynamic> payload) async {
    processedLogs.add(payload['content'] as String);
    if (onProcessOverride != null) {
      await onProcessOverride!(payload);
    } else {
      // Default: set status to synced
      final int localId = payload['id'];
      await (database.update(database.posts)..where((t) => t.id.equals(localId))).write(
        const PostsCompanion(status: Value('synced')),
      );
    }
  }

  @override
  Future<void> onConflict(Object error, Map<String, dynamic> payload) async {
    lastConflictError = error;
    final int localId = payload['id'];
    await (database.update(database.posts)..where((t) => t.id.equals(localId))).write(
      const PostsCompanion(status: Value('conflict')),
    );
  }

  @override
  Future<void> onFailure(Object error, Map<String, dynamic> payload, int currentRetries) async {
    lastFailureError = error;
    final int localId = payload['id'];
    await (database.update(database.posts)..where((t) => t.id.equals(localId))).write(
      const PostsCompanion(status: Value('failed')),
    );
  }
}

/// Post cleanup handler to purge old synced data
class TestPostCleanupHandler implements OfflineCleanupHandler {
  final AppDatabase database;
  TestPostCleanupHandler(this.database);

  @override
  Future<void> cleanup(Duration retentionDuration) async {
    final thresholdDate = DateTime.now().subtract(retentionDuration);
    await (database.delete(database.posts)
          ..where((t) => t.status.equals('synced') & t.createdAt.isBefore(thresholdDate)))
        .go();
  }
}

void main() {
  late AppDatabase database;
  late FakeConnectivity connectivity;
  late OfflineSyncEngine syncEngine;
  late FakePostProcessor postProcessor;
  late TestPostCleanupHandler cleanupHandler;

  setUp(() {
    // Use in-memory SQLite database for testing
    database = AppDatabase(NativeDatabase.memory());
    connectivity = FakeConnectivity([ConnectivityResult.wifi]);
    
    syncEngine = OfflineSyncEngine(
      outboxRepository: database,
      connectivity: connectivity,
      config: const SyncConfig(
        maxRetries: 3,
        cleanupDuration: Duration(days: 7),
      ),
    );

    postProcessor = FakePostProcessor(database);
    cleanupHandler = TestPostCleanupHandler(database);

    syncEngine.registerProcessor(postProcessor);
    syncEngine.registerCleanupHandler(cleanupHandler);
  });

  tearDown(() async {
    syncEngine.dispose();
    await database.close();
  });

  test('FIFO queue processes items in the correct order', () async {
    // Disable autostart during setup by going offline in connectivity
    // or just let it process. Since we want to test FIFO specifically,
    // let's insert multiple items offline, then trigger sync
    final offlineConnectivity = FakeConnectivity([ConnectivityResult.none]);
    final offlineEngine = OfflineSyncEngine(
      outboxRepository: database,
      connectivity: offlineConnectivity,
    );
    offlineEngine.registerProcessor(postProcessor);

    // Insert 3 posts offline
    await database.insertPostToOutbox('First Post');
    await database.insertPostToOutbox('Second Post');
    await database.insertPostToOutbox('Third Post');

    // Verify outbox has 3 items
    final outboxItems = await database.select(database.outboxQueue).get();
    expect(outboxItems.length, 3);
    
    // Switch sync engine to online connectivity and trigger
    final onlineEngine = OfflineSyncEngine(
      outboxRepository: database,
      connectivity: FakeConnectivity([ConnectivityResult.wifi]),
    );
    onlineEngine.registerProcessor(postProcessor);

    await onlineEngine.triggerSync();

    // Verify processor processed items in exact FIFO order
    expect(postProcessor.processedLogs, [
      'First Post',
      'Second Post',
      'Third Post',
    ]);

    // Verify outbox queue is now empty
    final finalOutbox = await database.select(database.outboxQueue).get();
    expect(finalOutbox.isEmpty, true);

    // Verify all posts are marked as synced
    final posts = await database.select(database.posts).get();
    expect(posts.every((p) => p.status == 'synced'), true);

    onlineEngine.dispose();
    offlineEngine.dispose();
  });

  test('Retry mechanism retries up to maxRetries on standard errors', () async {
    int attempts = 0;
    postProcessor.onProcessOverride = (payload) async {
      attempts++;
      throw Exception('Transient connection issue');
    };

    // Insert 1 post
    await database.insertPostToOutbox('Retry Post');

    // Trigger sync engine
    await syncEngine.triggerSync();

    // Expect engine status is error due to retry delay/pause on failure
    expect(syncEngine.status, SyncEngineStatus.error);

    // Verify outbox item has failed status and retryCount has incremented
    final outboxItems = await database.select(database.outboxQueue).get();
    expect(outboxItems.length, 1);
    expect(outboxItems.first.retryCount, 1);
    expect(outboxItems.first.status, 'failed');

    // Reset attempt handler to succeed now
    postProcessor.onProcessOverride = null;

    // Trigger sync again
    await syncEngine.triggerSync();

    // Outbox should now be clear as it succeeded on the retry
    final finalOutbox = await database.select(database.outboxQueue).get();
    expect(finalOutbox.isEmpty, true);

    final posts = await database.select(database.posts).get();
    expect(posts.first.status, 'synced');
  });

  test('Persistent error exhausts maxRetries and marks item as failed', () async {
    postProcessor.onProcessOverride = (payload) async {
      throw Exception('Persistent network timeout');
    };

    await database.insertPostToOutbox('Broken Post');

    // Trigger sync (Retry 1)
    await syncEngine.triggerSync();
    // Trigger sync (Retry 2)
    await syncEngine.triggerSync();
    // Trigger sync (Retry 3 - hits maxRetries = 3)
    await syncEngine.triggerSync();

    // Item should stop being syncable and remain in outbox as 'failed' (unblocking FIFO)
    final outboxItems = await database.select(database.outboxQueue).get();
    expect(outboxItems.length, 1);
    expect(outboxItems.first.status, 'failed');
    expect(outboxItems.first.retryCount, 3);

    // Verify the post record status was set to failed by onFailure
    final posts = await database.select(database.posts).get();
    expect(posts.first.status, 'failed');
  });

  test('Data conflict (unique constraint) flags item and unblocks queue', () async {
    bool nrcConflictTriggered = false;
    postProcessor.onProcessOverride = (payload) async {
      if (!nrcConflictTriggered) {
        nrcConflictTriggered = true;
        // Simulating Supabase postgrest duplicate key error: PostgreSQL 23505
        throw Exception('PostgrestException: { message: Duplicate key, code: 23505 }');
      }
    };

    // Insert duplicate NRC post and then a valid post
    await database.insertPostToOutbox('Duplicate NRC Post');
    await database.insertPostToOutbox('Valid Post');

    // Sync
    await syncEngine.triggerSync();

    // The duplicate post should be marked as 'conflict' in the DB (unblocking queue),
    // and the valid post should successfully sync.
    final outboxItems = await database.select(database.outboxQueue).get();
    // outboxItems should be empty since the duplicate post is marked as 'conflict' and deleted/skipped from active queue processing
    expect(outboxItems.length, 1); // Only conflict remains in the outbox but has status='conflict' which is skipped by getNextSyncableItem
    expect(outboxItems.first.status, 'conflict');

    final posts = await database.select(database.posts).get();
    expect(posts.first.status, 'conflict');
    expect(posts.last.status, 'synced'); // The valid post has successfully synced!
  });

  test('Synced items older than retention period are auto-cleaned', () async {
    // Force sync completion to trigger cleanups
    await database.insertPostToOutbox('New Post');
    await syncEngine.triggerSync();

    // Manually insert an old synced post and an old pending post into DB
    final sevenDaysAgo = DateTime.now().subtract(const Duration(days: 8));
    
    // Add old synced post
    await database.into(database.posts).insert(
      PostsCompanion.insert(
        content: 'Old Synced Post',
        status: const Value('synced'),
        createdAt: Value(sevenDaysAgo),
      ),
    );

    // Add old pending post
    await database.into(database.posts).insert(
      PostsCompanion.insert(
        content: 'Old Pending Post',
        status: const Value('pending'),
        createdAt: Value(sevenDaysAgo),
      ),
    );

    // Verify all 3 posts are in DB
    var posts = await database.select(database.posts).get();
    expect(posts.length, 3);

    // Run database cleanup via engine
    await syncEngine.runDatabaseCleanup();

    // Verify 'Old Synced Post' is deleted, but 'Old Pending Post' and 'New Post' remain
    posts = await database.select(database.posts).get();
    expect(posts.length, 2);
    expect(posts.any((p) => p.content == 'Old Synced Post'), false);
    expect(posts.any((p) => p.content == 'Old Pending Post'), true);
    expect(posts.any((p) => p.content == 'New Post'), true);
  });
}
