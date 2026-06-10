import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' show Value;

import '../../../../config/dependency_injections/dependency_injections.dart';
import '../../../../shared/enums/sync_engine_enums.dart';
import '../../data/data_sources/local_database.dart';
import '../../domain/entities/post_entity.dart';
import '../providers/post_providers.dart';
import 'newsfeed.dart';

class ReportNewsScreen extends ConsumerStatefulWidget {
  const ReportNewsScreen({super.key});

  @override
  ConsumerState<ReportNewsScreen> createState() => _ReportNewsScreenState();
}

class _ReportNewsScreenState extends ConsumerState<ReportNewsScreen> {
  final TextEditingController _controller = TextEditingController();
  @override
  Widget build(BuildContext context) {
    // Watch sync status reactively
    final syncStatusAsync = ref.watch(syncStatusProvider);
    // Keep sync engine alive and listening
    ref.watch(syncEngineProvider);

    final postsAsyncValue = ref.watch(postsStreamProvider);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Report News'),
          actions: [_buildSyncStatusIndicator(syncStatusAsync)],
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.edit), text: 'Report'),
              Tab(icon: Icon(Icons.feed), text: 'Feed'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // Report Tab
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 16.0,
                children: [
                  TextField(
                    controller: _controller,
                    decoration: const InputDecoration(
                      hintText: 'သတင်းအချက်အလက်များ ရေးသားရန်...',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 4,
                  ),

                  Center(
                    child: ElevatedButton(
                      onPressed: () async {
                        final text = _controller.text;
                        if (text.trim().isEmpty)
                          return; // Prevent sending empty news

                        // Call the use case through the provider
                        await ref.read(postUsecaseProvider).createPost(text);

                        _controller.clear();

                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('သတင်းပေးပို့ပြီးပါပြီ'),
                            ),
                          );
                        }
                      },
                      child: const Text('သတင်းပေးပို့မည်'),
                    ),
                  ),

                  const Divider(height: 10),

                  const Text(
                    'မကြာသေးမီက ပေးပို့ထားသော သတင်းများ',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),

                  Expanded(
                    child: postsAsyncValue.when(
                      data: (posts) {
                        if (posts.isEmpty) {
                          return const Center(
                            child: Text('ပေးပို့ထားသော သတင်းမရှိသေးပါ။'),
                          );
                        }

                        return ListView.builder(
                          itemCount: posts.length,
                          itemBuilder: (context, index) {
                            final post = posts[index];

                            Color statusColor;
                            IconData statusIcon;
                            String statusText;
                            bool isActionable = false;

                            switch (post.status) {
                              case 'pending':
                                statusColor = Colors.orange;
                                statusIcon = Icons.access_time_rounded;
                                statusText = 'Pending';
                                break;
                              case 'conflict':
                                statusColor = Colors.red;
                                statusIcon = Icons.warning_amber_rounded;
                                statusText = 'Conflict';
                                isActionable = true;
                                break;
                              case 'failed':
                                statusColor = Colors.redAccent;
                                statusIcon = Icons.error_outline_rounded;
                                statusText = 'Sync Failed';
                                isActionable = true;
                                break;
                              case 'synced':
                              default:
                                statusColor = Colors.green;
                                statusIcon = Icons.check_circle_rounded;
                                statusText = 'Synced';
                                break;
                            }

                            return Card(
                              margin: const EdgeInsets.symmetric(vertical: 6),
                              elevation: isActionable ? 3 : 1,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: isActionable
                                    ? BorderSide(
                                        color: statusColor.withOpacity(0.5),
                                        width: 1.5,
                                      )
                                    : BorderSide.none,
                              ),
                              child: ListTile(
                                subtitle: Text(post.content),
                                title: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          statusText,
                                          style: TextStyle(
                                            color: statusColor,
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Icon(
                                          size: 15,
                                          statusIcon,
                                          color: statusColor,
                                        ),
                                      ],
                                    ),
                                    Text(
                                      _formatTime(post.createdAt),
                                      style: TextStyle(
                                        color: Colors.grey.shade500,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                                onTap: isActionable
                                    ? () => _showResolveDialog(context, post)
                                    : null,
                              ),
                            );
                          },
                        );
                      },
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (error, stack) =>
                          Center(child: Text('Error loading posts: $error')),
                    ),
                  ),
                ],
              ),
            ),

            // Newsfeed
            const Newsfeed(),
          ],
        ),
      ),
    );
  }

  Widget _buildSyncStatusIndicator(
    AsyncValue<SyncEngineEnums> syncStatusAsync,
  ) {
    return syncStatusAsync.when(
      data: (status) {
        Color color;
        IconData icon;
        String tooltip;

        switch (status) {
          case SyncEngineEnums.syncing:
            color = Colors.blue;
            icon = Icons.sync;
            tooltip = 'Syncing...';
            break;
          case SyncEngineEnums.offline:
            color = Colors.orange;
            icon = Icons.cloud_off;
            tooltip = 'Offline Mode';
            break;
          case SyncEngineEnums.error:
            color = Colors.red;
            icon = Icons.sync_problem;
            tooltip = 'Sync Paused (Error)';
            break;
          case SyncEngineEnums.idle:
          default:
            color = Colors.green;
            icon = Icons.cloud_done;
            tooltip = 'Connected & Synced';
            break;
        }

        return IconButton(
          icon: Icon(icon, color: color),
          tooltip: tooltip,
          onPressed: () {
            ref.read(syncEngineProvider).triggerSync();
          },
        );
      },
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16.0),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      error: (_, __) => const Icon(Icons.sync_problem, color: Colors.red),
    );
  }

  void _showResolveDialog(BuildContext context, PostEntity post) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(
                post.status == 'conflict'
                    ? Icons.warning_amber_rounded
                    : Icons.error_outline_rounded,
                color: Colors.red,
              ),
              const SizedBox(width: 8),
              const Text('သတင်းပေးပို့မှု ပြဿနာ'),
            ],
          ),
          content: Text(
            post.status == 'conflict'
                ? 'ဆာဗာရှိ အချက်အလက်နှင့် တိုက်ဆိုင်နေပါသည် (ဥပမာ NRC တူနေခြင်း သို့မဟုတ် ဒေတာထပ်နေခြင်း)။ အချက်အလက်ကို ပြင်ဆင်ပြီး ပြန်လည်ပေးပို့ပါရန် သို့မဟုတ် ဖျက်ပစ်ပါရန်။'
                : 'အင်တာနက်ချိတ်ဆက်မှု ပြဿနာကြောင့် ဒေတာမရောက်ရှိပါ။ ပြန်လည်ကြိုးစားရန် သို့မဟုတ် ဖျက်ပစ်ပါရန်။',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                _deletePost(post);
              },
              child: const Text(
                'ဖျက်ပစ်မည်',
                style: TextStyle(color: Colors.red),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                _showEditDialog(context, post);
              },
              child: const Text('ပြင်ဆင်မည်'),
            ),
            if (post.status == 'failed')
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  _retryPost(post);
                },
                child: const Text('ထပ်မံကြိုးစားမည်'),
              ),
          ],
        );
      },
    );
  }

  Future<void> _deletePost(PostEntity post) async {
    final db = ref.read(databaseProvider);
    await (db.delete(db.posts)..where((t) => t.id.equals(post.id))).go();
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('သတင်းကို ဖျက်ပြီးပါပြီ။')));
    }
  }

  Future<void> _retryPost(PostEntity post) async {
    final db = ref.read(databaseProvider);
    await db.transaction(() async {
      await (db.update(db.posts)..where((t) => t.id.equals(post.id))).write(
        const PostsCompanion(status: Value('pending')),
      );
      await db
          .into(db.outboxQueue)
          .insert(
            OutboxQueueCompanion.insert(
              actionType: 'create_post',
              payload: jsonEncode({'id': post.id, 'content': post.content}),
              status: const Value('pending'),
            ),
          );
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('သတင်းပေးပို့ရန် ထပ်မံကြိုးစားနေပါသည်...'),
        ),
      );
    }
  }

  void _showEditDialog(BuildContext context, PostEntity post) {
    final editController = TextEditingController(text: post.content);
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('သတင်းပြင်ဆင်ရန်'),
          content: TextField(
            controller: editController,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'ပြင်ဆင်ထားသော သတင်း ရေးသားရန်...',
            ),
            maxLines: 3,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('မလုပ်တော့ပါ'),
            ),
            ElevatedButton(
              onPressed: () async {
                final newContent = editController.text;
                if (newContent.trim().isEmpty) return;
                Navigator.pop(dialogContext);

                final db = ref.read(databaseProvider);
                await db.transaction(() async {
                  await (db.update(
                    db.posts,
                  )..where((t) => t.id.equals(post.id))).write(
                    PostsCompanion(
                      content: Value(newContent),
                      status: const Value('pending'),
                    ),
                  );
                  await db
                      .into(db.outboxQueue)
                      .insert(
                        OutboxQueueCompanion.insert(
                          actionType: 'create_post',
                          payload: jsonEncode({
                            'id': post.id,
                            'content': newContent,
                          }),
                          status: const Value('pending'),
                        ),
                      );
                });
              },
              child: const Text('သိမ်းဆည်းမည်'),
            ),
          ],
        );
      },
    );
  }

  String _formatTime(DateTime dateTime) {
    return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }
}
