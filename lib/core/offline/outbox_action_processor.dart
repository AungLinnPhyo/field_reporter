abstract class OutboxActionProcessor {
  /// The unique type of action this processor handles (e.g., 'create_post').
  String get actionType;

  /// Processes the outbox payload (sends data to the server).
  Future<void> process(Map<String, dynamic> payload);

  /// Called when a data conflict is encountered (e.g. unique constraint violation).
  ///
  /// Implementations should mark the local record as conflicted and handle resolution,
  /// e.g. update status to 'conflict' so the user is notified.
  Future<void> onConflict(Object error, Map<String, dynamic> payload);

  /// Called when a general processing failure is encountered.
  ///
  /// [currentRetries] is the number of times this item has failed so far.
  Future<void> onFailure(Object error, Map<String, dynamic> payload, int currentRetries);
}
