import 'dart:io';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

part 'local_database.g.dart';

/// Define the tables
/// Post table
class Posts extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get content => text()();
  // TextColumn get status => text().clientDefault(() => 'pending')(); // Deafult value (Client-side)
  TextColumn get status => text().withDefault(const Constant('pending'))(); // Deafult value (Server-side)
}

/// Server Post Table
class ServerPosts extends Table {
  IntColumn get id => integer()(); // Server Post ID
  TextColumn get content => text()();
  TextColumn get status => text().withDefault(const Constant('synced'))();

  @override
  Set<Column> get primaryKey => {id}; // Primary Key
}

/// OutboxQueue table
class OutboxQueue extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get actionType => text()();
  TextColumn get payload => text()();
  // DateTimeColumn get createdAt => dateTime().clientDefault(() => DateTime.now())(); // Deafult value (Client-side)
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)(); // Deafult value (Server-side)
}

/// Database class
@DriftDatabase(tables: [Posts, OutboxQueue, ServerPosts])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  // Database Schema Version
  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (m) => m.createAll(),
      onUpgrade: (m, from, to) async {
        if (from < 2) {
          await m.createTable(serverPosts);
        }
      },
    );
  }

  Future<void> insertPostToOutbox(String postContent) async {
    await transaction(() async {
      final postId = await into(posts).insert(PostsCompanion.insert(content: postContent, status: const Value('pending')));

      final payload = jsonEncode({'id': postId, 'content': postContent});

      await into(outboxQueue).insert(OutboxQueueCompanion.insert(actionType: 'create_post', payload: payload));
    });
  }
}

// Define a path to store the database
LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(path.join(dbFolder.path, 'app_database.sqlite'));
    return NativeDatabase.createBackgroundConnection(file);
  });
}
