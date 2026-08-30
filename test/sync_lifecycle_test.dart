import 'package:flutter_test/flutter_test.dart';
import 'package:opto_sync_flutter/src/api/client.dart';
import 'package:opto_sync_flutter/src/api/models.dart';
import 'package:opto_sync_flutter/src/app_lifecycle_controller.dart';
import 'package:opto_sync_flutter/src/state/sync_lifecycle.dart';

void main() {
  group('SyncLifecycleMachine', () {
    test('implements complete happy path and terminal close', () {
      final machine = SyncLifecycleMachine();

      expect(_apply(machine, SyncLifecycleEvent.wake).applied, isTrue);
      final begin = _apply(machine, SyncLifecycleEvent.beginAcquire);
      expect(begin.applied, isTrue);
      expect(begin.after.generation, 1);
      final generation = begin.after.generation;

      expect(
        _apply(
          machine,
          SyncLifecycleEvent.acquireGranted,
          generation: generation,
        ).applied,
        isTrue,
      );
      expect(machine.state.mayRunSyncWork, isTrue);
      expect(
        _apply(
          machine,
          SyncLifecycleEvent.cycleSettled,
          generation: generation,
        ).applied,
        isTrue,
      );
      expect(
        _apply(
          machine,
          SyncLifecycleEvent.releaseSettled,
          generation: generation,
        ).applied,
        isTrue,
      );
      expect(_apply(machine, SyncLifecycleEvent.close).applied, isTrue);
      expect(machine.state.phase, SyncLifecyclePhase.closed);
      expect(machine.state.isValid, isTrue);

      final before = machine.state;
      final rejected = _apply(machine, SyncLifecycleEvent.wake);
      expect(rejected.disposition, TransitionDisposition.rejected);
      expect(machine.state, before);
    });

    test(
      'coalesces a trailing wake without invalidating active generation',
      () {
        final machine = SyncLifecycleMachine();
        _apply(machine, SyncLifecycleEvent.wake);
        final begin = _apply(machine, SyncLifecycleEvent.beginAcquire);
        final generation = begin.after.generation;
        _apply(
          machine,
          SyncLifecycleEvent.acquireGranted,
          generation: generation,
        );

        expect(_apply(machine, SyncLifecycleEvent.wake).applied, isTrue);
        expect(machine.state.wakePending, isTrue);
        expect(machine.state.generation, generation);
        _apply(
          machine,
          SyncLifecycleEvent.cycleSettled,
          generation: generation,
        );
        _apply(
          machine,
          SyncLifecycleEvent.releaseSettled,
          generation: generation,
        );
        expect(machine.state.phase, SyncLifecyclePhase.idle);
        expect(machine.state.wakePending, isTrue);

        final next = _apply(machine, SyncLifecycleEvent.beginAcquire);
        expect(next.after.generation, generation + 1);
      },
    );

    test('stale asynchronous completion stutters without mutation', () {
      final machine = SyncLifecycleMachine();
      _apply(machine, SyncLifecycleEvent.wake);
      final begin = _apply(machine, SyncLifecycleEvent.beginAcquire);
      final before = machine.state;

      final stale = _apply(
        machine,
        SyncLifecycleEvent.acquireGranted,
        generation: begin.after.generation - 1,
      );

      expect(stale.disposition, TransitionDisposition.stale);
      expect(stale.before, before);
      expect(stale.after, before);
      expect(machine.state, before);
    });

    test('close during running requests cancellation and rejects wakes', () {
      final machine = SyncLifecycleMachine();
      _apply(machine, SyncLifecycleEvent.wake);
      final begin = _apply(machine, SyncLifecycleEvent.beginAcquire);
      final generation = begin.after.generation;
      _apply(
        machine,
        SyncLifecycleEvent.acquireGranted,
        generation: generation,
      );

      expect(_apply(machine, SyncLifecycleEvent.close).applied, isTrue);
      expect(machine.state.cancelRequested, isTrue);
      expect(machine.state.closeRequested, isTrue);
      expect(
        _apply(machine, SyncLifecycleEvent.wake).disposition,
        TransitionDisposition.rejected,
      );
      _apply(machine, SyncLifecycleEvent.cycleSettled, generation: generation);
      _apply(
        machine,
        SyncLifecycleEvent.releaseSettled,
        generation: generation,
      );
      expect(machine.state.phase, SyncLifecyclePhase.closed);
    });

    test(
      'reducer is total and preserves invariants over finite input space',
      () {
        var examined = 0;
        for (final phase in SyncLifecyclePhase.values) {
          for (final wakePending in _booleans) {
            for (final closeRequested in _booleans) {
              for (final cancelRequested in _booleans) {
                for (final permitHeld in _booleans) {
                  for (final generation in <int>[0, 1]) {
                    final state = SyncLifecycleSnapshot(
                      phase: phase,
                      wakePending: wakePending,
                      closeRequested: closeRequested,
                      cancelRequested: cancelRequested,
                      permitHeld: permitHeld,
                      generation: generation,
                    );
                    for (final event in SyncLifecycleEvent.values) {
                      for (final commandGeneration in <int?>[
                        null,
                        generation,
                        generation + 1,
                      ]) {
                        final decision = SyncLifecycleMachine.reduce(
                          state,
                          SyncLifecycleCommand(
                            event,
                            generation: commandGeneration,
                          ),
                        );
                        examined += 1;
                        expect(decision.before, state);
                        switch (decision.disposition) {
                          case TransitionDisposition.applied:
                            expect(state.isValid, isTrue);
                            expect(decision.after.isValid, isTrue);
                          case TransitionDisposition.rejected:
                            expect(decision.after, state);
                          case TransitionDisposition.stale:
                            expect(event.requiresGeneration, isTrue);
                            expect(decision.after, state);
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
        expect(examined, 4800);
      },
    );
  });

  group('AppLifecycleController', () {
    test('authorizes the probe only while running', () {
      final client = _RecordingApiClient();
      final controller = AppLifecycleController(client: client);

      final outcome = controller.probe();

      expect(client.calls, 1);
      expect(outcome.error, isNull);
      expect(outcome.status.endpoint, 'recorded');
      expect(outcome.lifecycle.phase, SyncLifecyclePhase.idle);
      expect(outcome.lifecycle.generation, 1);
    });

    test('closed controller fails without probing', () {
      final client = _RecordingApiClient();
      final controller = AppLifecycleController(client: client);
      expect(controller.close().applied, isTrue);

      final outcome = controller.probe();

      expect(client.calls, 0);
      expect(outcome.error, contains('rejected'));
      expect(outcome.lifecycle.phase, SyncLifecyclePhase.closed);
    });
  });
}

const _booleans = <bool>[false, true];

SyncLifecycleTransition _apply(
  SyncLifecycleMachine machine,
  SyncLifecycleEvent event, {
  int? generation,
}) => machine.dispatch(SyncLifecycleCommand(event, generation: generation));

final class _RecordingApiClient extends ApiClient {
  _RecordingApiClient() : super(baseUrl: 'recorded');

  int calls = 0;

  @override
  ConnectionStatus snapshot() {
    calls += 1;
    return const ConnectionStatus(connected: false, endpoint: 'recorded');
  }
}
