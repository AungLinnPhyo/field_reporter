class SyncConfig {
  final int maxRetries;
  final Duration cleanupDuration;

  const SyncConfig({
    this.maxRetries = 3,
    this.cleanupDuration = const Duration(days: 7),
  });
}
