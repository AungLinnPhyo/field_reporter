import 'dart:io';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:field_reporter/core/offline/offline_outbox_repository.dart';
import 'package:field_reporter/core/offline/offline_outbox_item.dart';

part 'local_database.g.dart';

/// Define the tables
/// Post table
class Posts extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get content => text()();
  TextColumn get status => text().withDefault(const Constant('pending'))(); // Default value (Server-side)
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)(); // Tracking for cleanup
  DateTimeColumn get nextRetryAt => dateTime().nullable()();
}

/// OutboxQueue table
class OutboxQueue extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get actionType => text()();
  TextColumn get payload => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
  IntColumn get maxRetries => integer().withDefault(const Constant(3))();
  TextColumn get status => text().withDefault(const Constant('pending'))();
  TextColumn get lastError => text().nullable()();
  DateTimeColumn get nextRetryAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime().nullable()();
}

/// Database class
@DriftDatabase(tables: [Posts, OutboxQueue])
class AppDatabase extends _$AppDatabase implements OfflineOutboxRepository {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openConnection());

  // Database Schema Version
  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        // Drop and recreate tables to apply schema modifications
        await m.deleteTable('posts');
        await m.deleteTable('outbox_queue');
        await m.createAll();
      } else if (from < 3) {
        await m.addColumn(posts, posts.nextRetryAt);
        await m.addColumn(outboxQueue, outboxQueue.nextRetryAt);
      }
    },
  );

  // OutboxQueue Table ထဲမှာ ဒေတာအပြောင်းအလဲ ရှိ၊ မရှိကိုအမြဲ စောင့်ကြည့်
  @override
  Stream<List<OfflineOutboxItem>> watchOutbox() {
    return select(outboxQueue).watch().map((rows) {
      return rows
          .map(
            (row) => OfflineOutboxItem(
              id: row.id,
              actionType: row.actionType,
              payload: row.payload,
              retryCount: row.retryCount,
              maxRetries: row.maxRetries,
              status: row.status,
              lastError: row.lastError,
              createdAt: row.createdAt,
              nextRetryAt: row.nextRetryAt,
              updatedAt: row.updatedAt,
            ),
          )
          .toList();
    });
  }

  // ဆာဗာကို ပို့ဖို့ နောက်ထပ် အလှည့်ကျမယ့် Item တစ်ခုတည်း (limit(1)) ကို ရှာဖွေပေးတာ ဖြစ်ပါတယ်။
  @override
  Future<OfflineOutboxItem?> getNextSyncableItem() async {
    final now = DateTime.now();
    final query = select(outboxQueue)
      ..where((t) => (t.status.equals('pending') | (t.status.equals('failed') & t.retryCount.isSmallerThan(t.maxRetries))) & (t.nextRetryAt.isNull() | t.nextRetryAt.isSmallerThanValue(now)))
      ..orderBy([(t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.asc)])
      ..limit(1);

    final row = await query.getSingleOrNull();
    if (row == null) return null;

    return OfflineOutboxItem(
      id: row.id,
      actionType: row.actionType,
      payload: row.payload,
      retryCount: row.retryCount,
      maxRetries: row.maxRetries,
      status: row.status,
      lastError: row.lastError,
      createdAt: row.createdAt,
      nextRetryAt: row.nextRetryAt,
      updatedAt: row.updatedAt,
    );
  }

  // OutboxQueue ထဲက Item တစ်ခုရဲ့ အခြေအနေ (Status, Retry Count စသည်) ကို ပြင်ဆင်သတ်မှတ်ပေးခြင်း
  @override
  Future<void> updateOutboxItem({required int id, required String status, required int retryCount, String? lastError, DateTime? nextRetryAt}) async {
    await (update(outboxQueue)..where((t) => t.id.equals(id))).write(
      OutboxQueueCompanion(status: Value(status), retryCount: Value(retryCount), lastError: Value(lastError), nextRetryAt: Value(nextRetryAt), updatedAt: Value(DateTime.now())),
    );
  }

  // OutboxQueue ထဲက Item ကို အပြီးအပိုင် ဖျက်ထုတ်ပေးခြင်း
  @override
  Future<void> deleteOutboxItem(int id) async {
    await (delete(outboxQueue)..where((t) => t.id.equals(id))).go();
  }

  // Post တစ်ခုကို Outbox ထဲထည့်ဖို့ စီစဉ်ပေးခြင်း
  Future<void> insertPostToOutbox(String postContent) async {
    await transaction(() async {
      final postId = await into(posts).insert(PostsCompanion.insert(content: postContent, status: const Value('pending')));

      final payload = jsonEncode({'id': postId, 'content': postContent});

      await into(outboxQueue).insert(OutboxQueueCompanion.insert(actionType: 'create_post', payload: payload, status: const Value('pending')));
    });
  }
}

// SQLite ဒေတာဘေ့စ် သိမ်းဆည်းမယ့်နေရာ (Path) ကို define ပေးခြင်း
LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(path.join(dbFolder.path, 'app_database.sqlite'));
    return NativeDatabase.createBackgroundConnection(file);
  });
}
