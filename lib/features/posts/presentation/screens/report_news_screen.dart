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
  int _currentIndex = 2; // Default အနေနဲ့ Outbox (Index 2) ကို ဖွင့်ထားမည်
  final TextEditingController _controller = TextEditingController();

  @override
  Widget build(BuildContext context) {
    // Sync Status နှင့် Sync Engine ကို နားထောင်ထားခြင်း
    final syncStatusAsync = ref.watch(syncStatusProvider);
    ref.watch(syncEngineProvider);

    // Bottom Navigation အလိုက် ပြသမည့် Screen များ စာရင်း
    final List<Widget> screens = [
      _buildReportTab(), // Index 0: Report တင်သည့်နေရာ
      const Newsfeed(), // Index 1: Feed ကြည့်သည့်နေရာ
      _buildOutboxTab(), // Index 2: ထွက်စာ (Outbox) စာရင်း
    ];

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Text(
          _getAppBarTitle(),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 22),
        ),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        actions: [_buildSyncStatusIndicator(syncStatusAsync)],
      ),
      body: IndexedStack(index: _currentIndex, children: screens),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        selectedItemColor: Colors.deepPurple,
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.edit_note_rounded),
            label: 'Report',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.feed_outlined),
            label: 'Feed',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.outbox_rounded),
            label: 'Outbox',
          ),
        ],
      ),
    );
  }

  String _getAppBarTitle() {
    switch (_currentIndex) {
      case 0:
        return 'Report News';
      case 1:
        return 'Newsfeed';
      case 2:
        return 'ထွက်စာ (Outbox)';
      default:
        return 'Report News';
    }
  }

  // ==========================================
  // ၁။ REPORT TAB UI (သတင်းအသစ်တင်ရန်)
  // ==========================================
  Widget _buildReportTab() {
    return Padding(
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
              filled: true,
              fillColor: Colors.white,
            ),
            maxLines: 4,
          ),
          Center(
            child: ElevatedButton.icon(
              onPressed: _submitPost,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
              icon: const Icon(Icons.send_rounded),
              label: const Text('သတင်းပေးပို့မည်'),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // ၂။ OUTBOX LIST TAB UI (ဒီဇိုင်းအသစ်)
  // ==========================================
  Widget _buildOutboxTab() {
    final postsAsyncValue = ref.watch(postsStreamProvider);

    return postsAsyncValue.when(
      data: (posts) {
        if (posts.isEmpty) {
          return const Center(child: Text('ထွက်စာဗန်းထဲတွင် သတင်းမရှိသေးပါ။'));
        }

        // 'synced' မဖြစ်သေးတဲ့ ကောင်တွေကိုပဲ Outbox ထဲမှာ ပြပါမယ်
        final outboxItems = posts.where((p) => p.status != 'synced').toList();

        if (outboxItems.isEmpty) {
          return const Center(
            child: Text('ထွက်စာဗန်း သန့်ရှင်းနေပါသည်။ အားလုံး ပို့ပြီးပါပြီ။'),
          );
        }

        return Column(
          children: [
            // အပေါ်က ကောင်ရေပြတဲ့ Header လေး (ဥပမာ - ၃ ခု ကျန်နေရီ)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 10,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.pending_actions,
                          size: 16,
                          color: Colors.black54,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${outboxItems.length} ခု ကျန်နေသေးသည်',
                          style: TextStyle(fontSize: 12, color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // ကတ်ပြားစာရင်းများ
            Expanded(
              child: ListView.builder(
                itemCount: outboxItems.length,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 4,
                ),
                itemBuilder: (context, index) {
                  final post = outboxItems[index];
                  return _buildOutboxCard(post);
                },
              ),
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('Error: $error')),
    );
  }

  Widget _buildOutboxCard(PostEntity post) {
    Color badgeColor;
    Color textColor;
    String statusText;
    IconData? badgeIcon;
    bool showActionButtons = false;

    // အခြေအနေအလိုက် Design Badge ပြောင်းလဲခြင်း
    switch (post.status) {
      case 'pending':
        badgeColor = Colors.blue.shade50;
        textColor = Colors.blue.shade800;
        statusText = 'ပို့ရန် စောင့်ဆိုင်းဆဲ';
        badgeIcon = Icons.hourglass_empty_rounded;
        showActionButtons = false;
        break;
      case 'conflict':
        badgeColor = Colors.red.shade50;
        textColor = Colors.red.shade800;
        statusText = 'ဒေတာထပ်နေပါသည်';
        badgeIcon = Icons.warning_amber_rounded;
        showActionButtons = true;
        break;
      case 'failed':
        badgeColor = Colors.red.shade50;
        textColor = Colors.red.shade800;
        statusText = 'မအောင်မြင်ပါ';
        badgeIcon = Icons.error_outline_rounded;
        showActionButtons = true;
        break;
      default: // 'syncing' သို့မဟုတ် တခြားအခြေအနေ
        badgeColor = Colors.blue.shade50;
        textColor = Colors.blue.shade800;
        statusText = 'ပို့ဆောင်နေဆဲ';
        badgeIcon = Icons.refresh_rounded;
    }

    return Card(
      color: Colors.white,
      margin: const EdgeInsets.symmetric(vertical: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: Profile Icon + Title + Status Badge
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.deepPurple.shade50,
                  radius: 20,
                  child: const Icon(Icons.person, color: Colors.deepPurple),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Field Reporter',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        'Verified Source',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                // Status Badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: badgeColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(badgeIcon, size: 14, color: textColor),
                      const SizedBox(width: 4),
                      Text(
                        statusText,
                        style: TextStyle(
                          color: textColor,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12.0),
              child: Divider(height: 1),
            ),
            // စာသား
            Text(
              post.content,
              style: TextStyle(
                fontSize: 15,
                color: Colors.black87,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 6),
            // Report ID & Time
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Report ID: #${post.id}',
                  style: const TextStyle(
                    color: Colors.grey,
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                Text(
                  _formatTime(post.createdAt),
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
            // ဖျက်မည်/ပြန်ပို့မည် Action Buttons
            if (showActionButtons) ...[
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                spacing: 12.0,
                children: [
                  OutlinedButton(
                    onPressed: () => _deletePost(post),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.grey.shade700,
                      side: BorderSide(color: Colors.grey.shade300),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    child: const Text('ဖျက်ပစ်မည်'),
                  ),
                  ElevatedButton.icon(
                    onPressed: () => _retryPost(post),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: const Text('ပြန်ပို့မည်'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ==========================================
  // ၃။ HELPERS & LOGIC METHODS
  // ==========================================
  Future<void> _submitPost() async {
    final text = _controller.text;
    if (text.trim().isEmpty) return;

    await ref.read(postUsecaseProvider).createPost(text);
    _controller.clear();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('သတင်းကို အော့ဖ်လိုင်းဗန်းထဲသို့ ထည့်ပြီးပါပြီ။'),
        ),
      );
      setState(() {
        _currentIndex =
            2; // တန်းစီစာရင်း (Outbox) တက်ဘ်သို့ တန်းရွှေ့ပြောင်းပေးမည်
      });
    }
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
    ref.read(syncEngineProvider).triggerSync();
  }

  Widget _buildSyncStatusIndicator(
    AsyncValue<SyncEngineEnums> syncStatusAsync,
  ) {
    return syncStatusAsync.when(
      data: (status) {
        Color color = Colors.green;
        IconData icon = Icons.cloud_done;
        if (status == SyncEngineEnums.syncing) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.only(right: 16.0),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        if (status == SyncEngineEnums.offline) {
          color = Colors.orange;
          icon = Icons.cloud_off;
        }
        if (status == SyncEngineEnums.error) {
          color = Colors.red;
          icon = Icons.sync_problem;
        }

        return IconButton(
          icon: Icon(icon, color: color),
          onPressed: () => ref.read(syncEngineProvider).triggerSync(),
        );
      },
      loading: () => const Icon(Icons.sync, color: Colors.grey),
      error: (_, __) => const Icon(Icons.sync_problem, color: Colors.red),
    );
  }

  String _formatTime(DateTime dateTime) {
    return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }
}
