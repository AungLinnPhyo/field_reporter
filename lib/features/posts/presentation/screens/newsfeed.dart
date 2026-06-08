import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/post_providers.dart';

class Newsfeed extends ConsumerWidget {
  const Newsfeed({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final serverPostsAsync = ref.watch(cachedPostsProvider);

    return RefreshIndicator(
      onRefresh: () => ref.refresh(cachedPostsProvider.future),
      child: serverPostsAsync.when(
        skipLoadingOnRefresh: false,
        skipLoadingOnReload: false,
        loading: () => _buildLoadingSkeleton(),
        error: (error, stackTrace) => _buildErrorState(error.toString(), ref),
        data: (posts) {
          if (posts.isEmpty) {
            return _buildEmptyState();
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: posts.length,
            itemBuilder: (context, index) {
              final post = posts[index];

              return Container(
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
                          // Cloud Synced Badge လေး
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(20)),
                            child: const Row(
                              children: [
                                Icon(Icons.cloud_done, color: Colors.green, size: 14),
                                SizedBox(width: 4),
                                Text(
                                  'Synced',
                                  style: TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Divider(height: 1, color: Colors.black12),
                      ),
                      // Body
                      Text(post.content, style: const TextStyle(fontSize: 15, height: 1.5, color: Colors.black87)),
                      const SizedBox(height: 12),
                      // Footer: Post ID
                      Text(
                        'Report ID: #${post.id}',
                        style: TextStyle(color: Colors.grey.shade500, fontSize: 11, fontStyle: FontStyle.italic),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
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
