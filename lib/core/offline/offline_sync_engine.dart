import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'sync_config.dart';
import 'outbox_action_processor.dart';
import 'offline_cleanup_handler.dart';
import 'offline_outbox_repository.dart';
import 'offline_outbox_item.dart';

enum SyncEngineStatus {
  idle,
  syncing,
  offline,
  error,
}

class OfflineSyncEngine {
  final OfflineOutboxRepository _outboxRepository;
  final SyncConfig _config;
  final Connectivity _connectivity;

  final Map<String, OutboxActionProcessor> _processors = {};
  final List<OfflineCleanupHandler> _cleanupHandlers = [];

  SyncEngineStatus _status = SyncEngineStatus.idle;
  bool _isProcessing = false;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  StreamSubscription<List<OfflineOutboxItem>>? _outboxSub;

  SyncEngineStatus get status => _status;
  bool get isProcessing => _isProcessing;

  // Multi-cast controller to notify UI of status changes
  final _statusController = StreamController<SyncEngineStatus>.broadcast();
  Stream<SyncEngineStatus> get statusStream => _statusController.stream;

  OfflineSyncEngine({
    required OfflineOutboxRepository outboxRepository,
    SyncConfig config = const SyncConfig(),
    Connectivity? connectivity,
  })  : _outboxRepository = outboxRepository,
        _config = config,
        _connectivity = connectivity ?? Connectivity() {
    _initListeners();
  }

  void registerProcessor(OutboxActionProcessor processor) {
    _processors[processor.actionType] = processor;
    dev.log('🔌 Registered outbox processor for action: ${processor.actionType}', name: 'OfflineSyncEngine');
  }

  void registerCleanupHandler(OfflineCleanupHandler handler) {
    _cleanupHandlers.add(handler);
    dev.log('🧹 Registered database cleanup handler', name: 'OfflineSyncEngine');
  }

  void _initListeners() {
    // 1. Listen for connectivity changes
    _connectivitySub = _connectivity.onConnectivityChanged.listen((results) {
      final hasConnection = !results.contains(ConnectivityResult.none);
      dev.log('🌐 Connectivity changed: hasConnection=$hasConnection (results=$results)', name: 'OfflineSyncEngine');
      if (hasConnection) {
        triggerSync();
      } else {
        _updateStatus(SyncEngineStatus.offline);
      }
    });

    // 2. Listen for outbox additions/updates
    _outboxSub = _outboxRepository.watchOutbox().listen((items) {
      final hasPendingItems = items.any((item) => item.status == 'pending');
      if (hasPendingItems && _status != SyncEngineStatus.offline) {
        dev.log('📥 Pending items detected in outbox. Triggering sync...', name: 'OfflineSyncEngine');
        triggerSync();
      }
    });
  }

  void _updateStatus(SyncEngineStatus newStatus) {
    if (_status != newStatus) {
      _status = newStatus;
      _statusController.add(newStatus);
      dev.log('🔄 Sync engine status changed to: $newStatus', name: 'OfflineSyncEngine');
    }
  }

  /// Triggers the FIFO syncing loop.
  Future<void> triggerSync() async {
    if (_isProcessing) {
      dev.log('⚠️ Sync already in progress. Skipping trigger.', name: 'OfflineSyncEngine');
      return;
    }

    // Check internet connection before starting
    final connectivityResult = await _connectivity.checkConnectivity();
    if (connectivityResult.contains(ConnectivityResult.none)) {
      dev.log('🚫 Cannot sync: Offline', name: 'OfflineSyncEngine');
      _updateStatus(SyncEngineStatus.offline);
      return;
    }

    _isProcessing = true;
    _updateStatus(SyncEngineStatus.syncing);

    dev.log('🚀 Starting FIFO outbox sync loop...', name: 'OfflineSyncEngine');

    try {
      while (true) {
        // Fetch next syncable item in FIFO order
        final item = await _outboxRepository.getNextSyncableItem();
        if (item == null) {
          dev.log('🏁 No more syncable items in the outbox.', name: 'OfflineSyncEngine');
          break;
        }

        final processor = _processors[item.actionType];
        if (processor == null) {
          dev.log('❌ Error: No processor registered for action type: ${item.actionType}', name: 'OfflineSyncEngine');
          // Discard/Fail to prevent blocking the FIFO queue permanently
          await _outboxRepository.updateOutboxItem(
            id: item.id,
            status: 'failed',
            retryCount: item.retryCount,
            lastError: 'No processor registered for ${item.actionType}',
          );
          continue;
        }

        // Mark the item as syncing locally
        await _outboxRepository.updateOutboxItem(
          id: item.id,
          status: 'syncing',
          retryCount: item.retryCount,
        );

        Map<String, dynamic> payload;
        try {
          payload = jsonDecode(item.payload) as Map<String, dynamic>;
        } catch (e) {
          dev.log('❌ Error decoding payload for item #${item.id}: $e', name: 'OfflineSyncEngine');
          await _outboxRepository.updateOutboxItem(
            id: item.id,
            status: 'failed',
            retryCount: item.retryCount,
            lastError: 'Invalid JSON payload: $e',
          );
          continue;
        }

        try {
          dev.log('📤 Processing outbox item #${item.id} (Action: ${item.actionType})', name: 'OfflineSyncEngine');
          
          await processor.process(payload);

          // Success: Delete from queue
          await _outboxRepository.deleteOutboxItem(item.id);
          dev.log('✅ Successfully processed and deleted outbox item #${item.id}', name: 'OfflineSyncEngine');
        } catch (error) {
          dev.log('❌ Failed to process outbox item #${item.id}: $error', name: 'OfflineSyncEngine');

          if (_isConflictError(error)) {
            dev.log('⚠️ Conflict detected for item #${item.id}. Invoking conflict handler...', name: 'OfflineSyncEngine');
            
            // Mark item as conflict
            await _outboxRepository.updateOutboxItem(
              id: item.id,
              status: 'conflict',
              retryCount: item.retryCount,
              lastError: error.toString(),
            );

            // Call processor's conflict handler to update local state (e.g. mark post status as conflict)
            await processor.onConflict(error, payload);
            
            dev.log('⚠️ Conflict handled. Queue unblocked.', name: 'OfflineSyncEngine');
          } else {
            // Standard/transient sync failure
            final newRetryCount = item.retryCount + 1;
            final maxRetries = item.maxRetries;

            if (newRetryCount >= maxRetries) {
              dev.log('🚨 Item #${item.id} exceeded max retries ($maxRetries). Marking as failed.', name: 'OfflineSyncEngine');
              
              await _outboxRepository.updateOutboxItem(
                id: item.id,
                status: 'failed',
                retryCount: newRetryCount,
                lastError: error.toString(),
              );

              // Notify processor
              await processor.onFailure(error, payload, newRetryCount);
            } else {
              dev.log('🔄 Item #${item.id} failed. Retry count: $newRetryCount/$maxRetries. Postponing...', name: 'OfflineSyncEngine');
              
              await _outboxRepository.updateOutboxItem(
                id: item.id,
                status: 'failed', // stays failed/retryable
                retryCount: newRetryCount,
                lastError: error.toString(),
              );
            }

            // Since it's a standard/transient error (e.g., network timeout during execution),
            // we pause execution of the queue to prevent spamming retries while connection is unstable.
            _updateStatus(SyncEngineStatus.error);
            break;
          }
        }
      }

      // If we cleared the queue, run database cleaning
      final nextItem = await _outboxRepository.getNextSyncableItem();
      if (nextItem == null) {
        await runDatabaseCleanup();
        _updateStatus(SyncEngineStatus.idle);
      }
    } catch (e) {
      dev.log('🚨 Critical error in sync loop: $e', name: 'OfflineSyncEngine');
      _updateStatus(SyncEngineStatus.error);
    } finally {
      _isProcessing = false;
    }
  }

  /// Runs database cleanup handlers to remove old synced records
  Future<void> runDatabaseCleanup() async {
    dev.log('🧹 Running database cleanup with retention: ${_config.cleanupDuration}', name: 'OfflineSyncEngine');
    for (final handler in _cleanupHandlers) {
      try {
        await handler.cleanup(_config.cleanupDuration);
      } catch (e) {
        dev.log('❌ Error running cleanup handler: $e', name: 'OfflineSyncEngine');
      }
    }
  }

  /// Detects SQLite and PostgreSQL unique constraint conflicts
  bool _isConflictError(Object error) {
    final errorStr = error.toString().toLowerCase();
    // 23505 is PostgreSQL/Supabase code for unique_violation.
    // 'duplicate key' is common Postgres/SQLite error text.
    // 'unique constraint' is standard SQLite constraint failure text.
    return errorStr.contains('23505') ||
        errorStr.contains('duplicate key') ||
        errorStr.contains('unique constraint') ||
        errorStr.contains('already exists');
  }

  void dispose() {
    _connectivitySub?.cancel();
    _outboxSub?.cancel();
    _statusController.close();
  }
}
