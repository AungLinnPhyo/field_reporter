import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    final postsAsyncValue = ref.watch(postsStreamProvider);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Report News'),
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
                    decoration: const InputDecoration(hintText: 'သတင်းအချက်အလက်များ ရေးသားရန်...', border: OutlineInputBorder()),
                    maxLines: 4,
                  ),

                  Center(
                    child: ElevatedButton(
                      onPressed: () async {
                        final text = _controller.text;
                        if (text.trim().isEmpty) return; // Prevent sending empty news

                        // Call the use case through the provider
                        await ref.read(postUsecaseProvider).createPost(text);

                        _controller.clear();

                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('သတင်းပေးပို့ပြီးပါပြီ')));
                        }
                      },
                      child: const Text('သတင်းပေးပို့မည်'),
                    ),
                  ),

                  const Divider(height: 10),

                  const Text('မကြာသေးမီက ပေးပို့ထားသော သတင်းများ', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),

                  Expanded(
                    child: postsAsyncValue.when(
                      data: (posts) {
                        if (posts.isEmpty) {
                          return const Center(child: Text('ပေးပို့ထားသော သတင်းမရှိသေးပါ။'));
                        }

                        return ListView.builder(
                          itemCount: posts.length,
                          itemBuilder: (context, index) {
                            final post = posts[index];

                            final isPending = post.status == 'pending';

                            return Card(
                              margin: const EdgeInsets.symmetric(vertical: 6),
                              child: ListTile(
                                subtitle: Text(post.content),
                                title: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(isPending ? 'Pending ' : 'Synced ', style: TextStyle(color: isPending ? Colors.orange : Colors.green, fontSize: 12)),
                                    Icon(size: 15, isPending ? Icons.access_time_rounded : Icons.check_circle_rounded, color: isPending ? Colors.orange : Colors.green),
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                      },
                      loading: () => const Center(child: CircularProgressIndicator()),
                      error: (error, stack) => Center(child: Text('Error loading posts: $error')),
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
}
