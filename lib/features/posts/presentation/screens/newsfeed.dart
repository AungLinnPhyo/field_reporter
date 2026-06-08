import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/post_providers.dart';

class Newsfeed extends ConsumerWidget {
  const Newsfeed({super.key});

  Future<void> _showEditDialog(BuildContext context, WidgetRef ref, int id, String initialContent) async {
    final controller = TextEditingController(text: initialContent);
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Post'),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                ref.read(postUsecaseProvider).updateServerPost(id, controller.text);
                Navigator.pop(context);
              }
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final serverPostsAsync = ref.watch(cachedPostsProvider);
    final useCase = ref.read(postUsecaseProvider);

    return RefreshIndicator(
      onRefresh: () => ref.refresh(cachedPostsProvider.future),
      child: serverPostsAsync.when(
        skipLoadingOnRefresh: false,
        skipLoadingOnReload: false,
        loading: () => _buildLoadingSkeleton(),
        error: (error, stackTrace) => _buildErrorState(error.toString(), ref),
        data: (posts) {
          if (posts.isEmpty) {
            return _buildEmptyState(ref);
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: posts.length,
            itemBuilder: (context, index) {
              final post = posts[index];

              final isDeleting = post.localStatus == 'pending_delete';
              final isUpdating = post.localStatus == 'pending_update';

              return Opacity(
                opacity: isDeleting ? 0.4 : 1.0,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.08), spreadRadius: 2, blurRadius: 8, offset: const Offset(0, 4))],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header
                        Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: Colors.blue.shade50,
                              radius: 18,
                              child: const Icon(Icons.person, color: Colors.blueAccent, size: 20),
                            ),
                            const SizedBox(width: 10),
                            const Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Field Reporter', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                Text('Verified Source', style: TextStyle(color: Colors.grey, fontSize: 11)),
                              ],
                            ),
                            const Spacer(),
                            if (!isDeleting && !isUpdating)
                              PopupMenuButton<String>(
                                padding: EdgeInsets.zero,
                                icon: const Icon(Icons.more_vert, size: 20, color: Colors.grey),
                                onSelected: (value) {
                                  if (value == 'edit') {
                                    _showEditDialog(context, ref, post.id, post.content);
                                  } else if (value == 'delete') {
                                    useCase.deleteServerPost(post.id);
                                  }
                                },
                                itemBuilder: (context) => [
                                  const PopupMenuItem(
                                    value: 'edit',
                                    child: ListTile(
                                      leading: Icon(Icons.edit, size: 18),
                                      title: Text('Edit', style: TextStyle(fontSize: 14)),
                                      contentPadding: EdgeInsets.zero,
                                      visualDensity: VisualDensity.compact,
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: ListTile(
                                      leading: Icon(Icons.delete, size: 18, color: Colors.red),
                                      title: Text('Delete', style: TextStyle(color: Colors.red, fontSize: 14)),
                                      contentPadding: EdgeInsets.zero,
                                      visualDensity: VisualDensity.compact,
                                    ),
                                  ),
                                ],
                              ),
                            _buildStatusBadge(isUpdating, isDeleting),
                          ],
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Divider(height: 1, color: Colors.black12),
                        ),
                        // Body
                        Text(
                          post.content,
                          style: TextStyle(fontSize: 15, height: 1.5, color: Colors.black87, decoration: isDeleting ? TextDecoration.lineThrough : null),
                        ),
                        const SizedBox(height: 12),
                        // Footer: Post ID
                        Text(
                          'Report ID: #${post.id}',
                          style: TextStyle(color: Colors.grey.shade500, fontSize: 11, fontStyle: FontStyle.italic),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildStatusBadge(bool isUpdating, bool isDeleting) {
    final color = isDeleting ? Colors.red : (isUpdating ? Colors.orange : Colors.green);
    final icon = isDeleting ? Icons.delete_sweep : (isUpdating ? Icons.sync_problem : Icons.cloud_done);
    final label = isDeleting ? 'Deleting...' : (isUpdating ? 'Updating...' : 'Synced');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(WidgetRef ref) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.layers_clear_outlined, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            'ဆာဗာပေါ်တွင် သတင်းများ မရှိသေးပါ',
            style: TextStyle(fontSize: 16, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          ElevatedButton(onPressed: () => ref.refresh(cachedPostsProvider.future), child: Text("Refresh")),
        ],
      ),
    );
  }

  Widget _buildErrorState(String message, WidgetRef ref) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.wifi_off_rounded, size: 64, color: Colors.redAccent),
            const SizedBox(height: 16),
            const Text('ချိတ်ဆက်မှု မအောင်မြင်ပါ', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              'အင်တာနက်လိုင်းကို စစ်ဆေးပြီး အောက်ကခလုတ်ကို နှိပ်၍ ပြန်လည်ကြိုးစားကြည့်ပါ။',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () => ref.refresh(cachedPostsProvider),
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, foregroundColor: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingSkeleton() {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: 3,
      itemBuilder: (context, index) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        height: 140,
        decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}
