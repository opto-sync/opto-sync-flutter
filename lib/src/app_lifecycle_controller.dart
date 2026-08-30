import 'api/client.dart';
import 'api/models.dart';
import 'state/sync_lifecycle.dart';

final class ProbeOutcome {
  const ProbeOutcome({
    required this.status,
    required this.lifecycle,
    this.error,
  });

  final ConnectionStatus status;
  final SyncLifecycleSnapshot lifecycle;
  final String? error;
}

/// Executes app work only while the formal lifecycle grants that capability.
final class AppLifecycleController {
  AppLifecycleController({required ApiClient client}) : _client = client;

  final ApiClient _client;
  final SyncLifecycleMachine lifecycle = SyncLifecycleMachine();

  ProbeOutcome probe() {
    final wake = lifecycle.dispatch(
      const SyncLifecycleCommand(SyncLifecycleEvent.wake),
    );
    if (!wake.applied) return _rejected('wake');

    final begin = lifecycle.dispatch(
      const SyncLifecycleCommand(SyncLifecycleEvent.beginAcquire),
    );
    if (!begin.applied) return _rejected('beginAcquire');
    final generation = begin.after.generation;

    final granted = lifecycle.dispatch(
      SyncLifecycleCommand(
        SyncLifecycleEvent.acquireGranted,
        generation: generation,
      ),
    );
    if (!granted.applied || !lifecycle.state.mayRunSyncWork) {
      return _rejected('acquireGranted');
    }

    try {
      final status = _client.snapshot();
      final settled = lifecycle.dispatch(
        SyncLifecycleCommand(
          SyncLifecycleEvent.cycleSettled,
          generation: generation,
        ),
      );
      if (!settled.applied) return _rejected('cycleSettled');
      final released = lifecycle.dispatch(
        SyncLifecycleCommand(
          SyncLifecycleEvent.releaseSettled,
          generation: generation,
        ),
      );
      if (!released.applied) return _rejected('releaseSettled');
      return ProbeOutcome(status: status, lifecycle: lifecycle.state);
    } on Object catch (error) {
      lifecycle.dispatch(
        SyncLifecycleCommand(
          SyncLifecycleEvent.processAbort,
          generation: generation,
        ),
      );
      return ProbeOutcome(
        status: const ConnectionStatus(connected: false, endpoint: 'unset'),
        lifecycle: lifecycle.state,
        error: 'Probe failed closed: $error',
      );
    }
  }

  SyncLifecycleTransition close() =>
      lifecycle.dispatch(const SyncLifecycleCommand(SyncLifecycleEvent.close));

  ProbeOutcome _rejected(String event) {
    _abortActiveGeneration();
    return ProbeOutcome(
      status: const ConnectionStatus(connected: false, endpoint: 'unset'),
      lifecycle: lifecycle.state,
      error:
          'Lifecycle rejected $event; no further network work was performed.',
    );
  }

  void _abortActiveGeneration() {
    final active = switch (lifecycle.state.phase) {
      SyncLifecyclePhase.idle => false,
      SyncLifecyclePhase.acquiring => true,
      SyncLifecyclePhase.running => true,
      SyncLifecyclePhase.releasing => true,
      SyncLifecyclePhase.closed => false,
    };
    if (active) {
      lifecycle.dispatch(
        SyncLifecycleCommand(
          SyncLifecycleEvent.processAbort,
          generation: lifecycle.state.generation,
        ),
      );
    }
  }
}
