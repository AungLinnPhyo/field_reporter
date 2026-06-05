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

/// OutboxQueue table
class OutboxQueue extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get actionType => text()();
  TextColumn get payload => text()();
  // DateTimeColumn get createdAt => dateTime().clientDefault(() => DateTime.now())(); // Deafult value (Client-side)
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)(); // Deafult value (Server-side)
}

/// Database class
@DriftDatabase(tables: [Posts, OutboxQueue])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1; // These version should be incremented when change the database schema

  Future<void> insertPostToOutbox(String postContent) async {
    await transaction(() async {
      final postId = await into(posts).insert(
        PostsCompanion.insert(
          content: postContent,
          status: const Value('pending'),
        )
      );

      final payload = jsonEncode({
        'id': postId,
        'content': postContent,
      });

      await into(outboxQueue).insert(
        OutboxQueueCompanion.insert(
          actionType: 'create_post',
          payload: payload,
        )
      );
    },);
  }
}

// Define a function to open the database connection
LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(path.join(dbFolder.path, 'app_database.sqlite'));
    return NativeDatabase.createBackgroundConnection(file);
  });
}
