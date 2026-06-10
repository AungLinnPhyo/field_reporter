import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import '../../shared/enums/sync_engine_enums.dart';
import 'sync_config.dart';
import 'outbox_action_processor.dart';
import 'offline_cleanup_handler.dart';
import 'offline_outbox_repository.dart';
import 'offline_outbox_item.dart';

class OfflineSyncEngine {
  final OfflineOutboxRepository
  _outboxRepository; // Local Database ထဲရှိ Outbox ဇယားကို စီမံမည့် Repository
  final SyncConfig
  _config; // Sync လုပ်မည့် သတ်မှတ်ချက်များ (ဥပမာ- ဒေတာဟောင်း သိမ်းမည့်သက်တမ်း)
  final Connectivity _connectivity;

  final Map<String, OutboxActionProcessor> _processors =
      {}; // အလုပ်အမျိုးအစားအလိုက် လုပ်ဆောင်ပေးမည့် Processor များကို သိမ်းမည့် Map
  final List<OfflineCleanupHandler> _cleanupHandlers =
      []; // ဒေတာဟောင်း clean လုပ်မည့် Handler များစာရင်း

  SyncEngineEnums _status = SyncEngineEnums.idle;
  bool _isProcessing = false;
  StreamSubscription<List<ConnectivityResult>>?
  _connectivitySub; // အင်တာနက်လိုင်း ရှိ/မရှိ Listen လုပ်ရန်
  StreamSubscription<List<OfflineOutboxItem>>?
  _outboxSub; // Outbox ထဲမှာ ဒေတာအသစ်ဝင်ရင် Listen လုပ်ရန်

  SyncEngineEnums get status => _status;
  bool get isProcessing => _isProcessing;

  // Multi-cast controller to notify UI of status changes
  // UI ဘက်သို့ Engine ၏ အခြေအနေပြောင်းလဲမှုများ လှမ်းအကြောင်းကြားရန် Broadcast Stream Controller
  final _statusController = StreamController<SyncEngineEnums>.broadcast();
  Stream<SyncEngineEnums> get statusStream => _statusController.stream;

  OfflineSyncEngine({
    required OfflineOutboxRepository outboxRepository,
    SyncConfig config = const SyncConfig(),
    Connectivity? connectivity,
  }) : _outboxRepository = outboxRepository,
       _config = config,
       _connectivity = connectivity ?? Connectivity() {
    _initListeners();
  }

  //
  void registerProcessor(OutboxActionProcessor processor) {
    _processors[processor.actionType] = processor;
    dev.log(
      '🔌 Registered outbox processor for action: ${processor.actionType}',
      name: 'OfflineSyncEngine',
    );
  }

  void registerCleanupHandler(OfflineCleanupHandler handler) {
    _cleanupHandlers.add(handler);
    dev.log(
      '🧹 Registered database cleanup handler',
      name: 'OfflineSyncEngine',
    );
  }

  void _initListeners() {
    // 1. အင်တာနက်လိုင်း အပြောင်းအလဲကို စဉ်ဆက်မပြတ် Listen လုပ်
    _connectivitySub = _connectivity.onConnectivityChanged.listen((results) {
      final hasConnection = !results.contains(ConnectivityResult.none);
      dev.log(
        '🌐 Connectivity changed: hasConnection=$hasConnection (results=$results)',
        name: 'OfflineSyncEngine',
      );
      if (hasConnection) {
        triggerSync();
      } else {
        _updateStatus(SyncEngineEnums.offline);
      }
    });

    // 2. Local Database (Outbox) ထဲသို့ ဒေတာအသစ်ရောက်လာခြင်း သို့မဟုတ် Update ဖြစ်ခြင်းကို စောင့်ကြည့်သည်
    _outboxSub = _outboxRepository.watchOutbox().listen((items) {
      final hasPendingItems = items.any(
        (item) => item.status == 'pending',
      ); // ပို့ရန်ကျန်သေးသော 'pending' ဒေတာ ပါ၊ မပါ စစ်ဆေးသည်
      if (hasPendingItems && _status != SyncEngineEnums.offline) {
        // ပို့ရန်ရှိပြီး အော့ဖ်လိုင်းမဟုတ်ပါက
        dev.log(
          '📥 Pending items detected in outbox. Triggering sync...',
          name: 'OfflineSyncEngine',
        );
        triggerSync();
      }
    });
  }

  // Engine ၏ (Status) ပြောင်းလဲမှုကို UI ဘက်သို့ လှမ်းပို့
  void _updateStatus(SyncEngineEnums newStatus) {
    if (_status != newStatus) {
      _status = newStatus;
      _statusController.add(newStatus);
      dev.log(
        '🔄 Sync engine status changed to: $newStatus',
        name: 'OfflineSyncEngine',
      );
    }
  }

  /// Triggers the FIFO syncing loop.
  Future<void> triggerSync() async {
    if (_isProcessing) {
      dev.log(
        '⚠️ Sync already in progress. Skipping trigger.',
        name: 'OfflineSyncEngine',
      );
      return;
    }

    // Check internet connection before starting
    final connectivityResult = await _connectivity.checkConnectivity();
    if (connectivityResult.contains(ConnectivityResult.none)) {
      dev.log('🚫 Cannot sync: Offline', name: 'OfflineSyncEngine');
      _updateStatus(SyncEngineEnums.offline);
      return;
    }

    _isProcessing = true;
    _updateStatus(SyncEngineEnums.syncing);

    dev.log('🚀 Starting FIFO outbox sync loop...', name: 'OfflineSyncEngine');

    try {
      while (true) {
        // Fetch next syncable item in FIFO order
        final item = await _outboxRepository.getNextSyncableItem();
        if (item == null) {
          dev.log(
            '🏁 No more syncable items in the outbox.',
            name: 'OfflineSyncEngine',
          );
          break;
        }

        final processor = _processors[item.actionType];
        if (processor == null) {
          dev.log(
            '❌ Error: No processor registered for action type: ${item.actionType}',
            name: 'OfflineSyncEngine',
          );
          // ကျန်ရှိနေသော တန်းစီဇယား Block ဖြစ်မသွားစေရန် 'failed' သတ်မှတ်ပြီး ကျော်သည်
          await _outboxRepository.updateOutboxItem(
            id: item.id,
            status: 'failed',
            retryCount: item.retryCount,
            lastError: 'No processor registered for ${item.actionType}',
          );
          continue;
        }

        // ပို့တော့မည့် Item ကို Local Database တွင် 'syncing' အခြေအနေသို့ ပြောင်းလဲသည်
        await _outboxRepository.updateOutboxItem(
          id: item.id,
          status: 'syncing',
          retryCount: item.retryCount,
        );

        // String ဖြင့် သိမ်းထားသော ပို့မည့်ဒေတာ (Payload) ကို JSON Map အဖြစ် ပြန်လည်ပြောင်းလဲ
        Map<String, dynamic> payload;
        try {
          payload = jsonDecode(item.payload) as Map<String, dynamic>;
        } catch (e) {
          // JSON format မှားခဲ့လျှင်
          dev.log(
            '❌ Error decoding payload for item #${item.id}: $e',
            name: 'OfflineSyncEngine',
          );
          await _outboxRepository.updateOutboxItem(
            id: item.id,
            status: 'failed',
            retryCount: item.retryCount,
            lastError: 'Invalid JSON payload: $e',
          );
          continue;
        }

        try {
          dev.log(
            '📤 Processing outbox item #${item.id} (Action: ${item.actionType})',
            name: 'OfflineSyncEngine',
          );

          // 🛑 ဤနေရာသည် သက်ဆိုင်ရာ Processor ကိုသုံး၍ ဆာဗာသို့ အင်တာနက်မှတစ်ဆင့် အချက်အလက် အမှန်တကယ် ပို့ဆောင်သည့်နေရာဖြစ်သည်
          await processor.process(payload);

          // အောင်မြင်လျှင် Outbox မှ ဖျက်
          await _outboxRepository.deleteOutboxItem(item.id);
          dev.log(
            '✅ Successfully processed and deleted outbox item #${item.id}',
            name: 'OfflineSyncEngine',
          );
        } catch (error) {
          dev.log(
            '❌ Failed to process outbox item #${item.id}: $error',
            name: 'OfflineSyncEngine',
          );

          if (_isConflictError(error)) {
            // တက်လာသော error သည် ဒေတာချင်း ထပ်နေသည့် Conflict Error ဖြစ်ပါက
            dev.log(
              '⚠️ Conflict detected for item #${item.id}. Invoking conflict handler...',
              name: 'OfflineSyncEngine',
            );

            // Database တွင် 'conflict' ဟု ပြောင်းလဲမှတ်သား
            await _outboxRepository.updateOutboxItem(
              id: item.id,
              status: 'conflict',
              retryCount: item.retryCount,
              lastError: error.toString(),
            );

            // သက်ဆိုင်ရာ Processor ၏ Conflict Handler ကို ခေါ်ကာ Local Database တွင် ပြောင်းလဲမှုများ ပြုလုပ်သည်
            await processor.onConflict(error, payload);

            dev.log(
              '⚠️ Conflict handled. Queue unblocked.',
              name: 'OfflineSyncEngine',
            );
          } else {
            // Conflict မဟုတ်ဘဲ သာမန် လိုင်းပြတ်တောက်ခြင်း စသည့် error ဆိုလျှင်
            final newRetryCount = item.retryCount + 1;
            final maxRetries = item.maxRetries;

            if (newRetryCount >= maxRetries) {
              // သတ်မှတ်ထားသော အကြိမ်ရေထက် ကျော်လွန်သွားပါက
              dev.log(
                '🚨 Item #${item.id} exceeded max retries ($maxRetries). Marking as failed.',
                name: 'OfflineSyncEngine',
              );

              await _outboxRepository.updateOutboxItem(
                id: item.id,
                status: 'failed',
                retryCount: newRetryCount,
                lastError: error.toString(),
              );

              // Notify processor
              await processor.onFailure(error, payload, newRetryCount);
            } else {
              dev.log(
                '🔄 Item #${item.id} failed. Retry count: $newRetryCount/$maxRetries. Postponing...',
                name: 'OfflineSyncEngine',
              );

              await _outboxRepository.updateOutboxItem(
                id: item.id,
                status: 'failed', // stays failed/retryable
                retryCount: newRetryCount,
                lastError: error.toString(),
              );
            }

            // Since it's a standard/transient error (e.g., network timeout during execution),
            // we pause execution of the queue to prevent spamming retries while connection is unstable.
            _updateStatus(SyncEngineEnums.error);
            break;
          }
        }
      }

      // If we cleared the queue, run database cleaning
      final nextItem = await _outboxRepository.getNextSyncableItem();
      if (nextItem == null) {
        await runDatabaseCleanup();
        _updateStatus(SyncEngineEnums.idle);
      }
    } catch (e) {
      dev.log('🚨 Critical error in sync loop: $e', name: 'OfflineSyncEngine');
      _updateStatus(SyncEngineEnums.error);
    } finally {
      _isProcessing = false;
    }
  }

  /// Runs database cleanup handlers to remove old synced records
  Future<void> runDatabaseCleanup() async {
    dev.log(
      '🧹 Running database cleanup with retention: ${_config.cleanupDuration}',
      name: 'OfflineSyncEngine',
    );
    for (final handler in _cleanupHandlers) {
      try {
        await handler.cleanup(_config.cleanupDuration);
      } catch (e) {
        dev.log(
          '❌ Error running cleanup handler: $e',
          name: 'OfflineSyncEngine',
        );
      }
    }
  }

  /// Detects SQLite and PostgreSQL unique constraint conflicts
  // bool _isConflictError(Object error) {
  //   final errorStr = error.toString().toLowerCase();
  //   // 23505 is PostgreSQL/Supabase code for unique_violation.
  //   // 'duplicate key' is common Postgres/SQLite error text.
  //   // 'unique constraint' is standard SQLite constraint failure text.
  //   return errorStr.contains('23505') ||
  //       errorStr.contains('duplicate key') ||
  //       errorStr.contains('unique constraint') ||
  //       errorStr.contains('already exists');
  // }

  bool _isConflictError(Object error) {
    // ၁။ တက်လာတဲ့ error က DioException ဟုတ်မဟုတ် အရင်စစ်တယ်
    if (error is DioException) {
      // ၂။ Server က ပြန်ပေးတဲ့ HTTP Status Code က 409 Conflict ဟုတ်မဟုတ် စစ်တယ်
      if (error.response?.statusCode == 409) {
        return true;
      }

      // ၃။ သို့မဟုတ် Custom Error Code ပါလာရင် ၎င်းကို စစ်တယ်
      final data = error.response?.data;
      if (data is Map<String, dynamic> &&
          data['error_code'] == 'DUPLICATE_USERNAME') {
        return true;
      }
    }

    return false;
  }

  void dispose() {
    _connectivitySub?.cancel();
    _outboxSub?.cancel();
    _statusController.close();
  }
}
