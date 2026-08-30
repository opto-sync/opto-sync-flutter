/// Formally modeled background-sync ownership shared by mobile and desktop.
///
/// The phase/event projection refines the canonical
/// `mobile_desktop_lifecycle.qnt` model. Generations are an implementation
/// guard: a settlement from an older asynchronous operation stutters instead
/// of mutating a newer lifecycle.
enum SyncLifecyclePhase { idle, acquiring, running, releasing, closed }

enum SyncLifecycleEvent {
  wake,
  join,
  beginAcquire,
  acquireGranted,
  acquireDeferred,
  cancel,
  cycleSettled,
  releaseSettled,
  close,
  processAbort,
}

enum TransitionDisposition { applied, rejected, stale }

extension SyncLifecycleEventContract on SyncLifecycleEvent {
  bool get requiresGeneration => switch (this) {
        SyncLifecycleEvent.wake => false,
        SyncLifecycleEvent.join => false,
        SyncLifecycleEvent.beginAcquire => false,
        SyncLifecycleEvent.acquireGranted => true,
        SyncLifecycleEvent.acquireDeferred => true,
        SyncLifecycleEvent.cancel => false,
        SyncLifecycleEvent.cycleSettled => true,
        SyncLifecycleEvent.releaseSettled => true,
        SyncLifecycleEvent.close => false,
        SyncLifecycleEvent.processAbort => true,
      };
}

final class SyncLifecycleCommand {
  const SyncLifecycleCommand(this.event, {this.generation});

  final SyncLifecycleEvent event;
  final int? generation;
}

final class SyncLifecycleSnapshot {
  const SyncLifecycleSnapshot({
    required this.phase,
    required this.wakePending,
    required this.closeRequested,
    required this.cancelRequested,
    required this.permitHeld,
    required this.generation,
  });

  const SyncLifecycleSnapshot.initial()
      : phase = SyncLifecyclePhase.idle,
        wakePending = false,
        closeRequested = false,
        cancelRequested = false,
        permitHeld = false,
        generation = 0;

  final SyncLifecyclePhase phase;
  final bool wakePending;
  final bool closeRequested;
  final bool cancelRequested;
  final bool permitHeld;
  final int generation;

  bool get isValid {
    if (generation < 0) return false;
    final activePermit = switch (phase) {
      SyncLifecyclePhase.idle => false,
      SyncLifecyclePhase.acquiring => false,
      SyncLifecyclePhase.running => true,
      SyncLifecyclePhase.releasing => true,
      SyncLifecyclePhase.closed => false,
    };
    if (permitHeld != activePermit) return false;
    if (phase == SyncLifecyclePhase.closed) {
      return closeRequested && !wakePending && !cancelRequested && !permitHeld;
    }
    if (closeRequested && wakePending) return false;
    if (cancelRequested && phase != SyncLifecyclePhase.running) return false;
    return true;
  }

  /// Only this derived capability authorizes network or queue work.
  bool get mayRunSyncWork =>
      phase == SyncLifecyclePhase.running &&
      permitHeld &&
      !cancelRequested &&
      !closeRequested;

  bool get acceptsWake => phase != SyncLifecyclePhase.closed && !closeRequested;

  String get phaseLabel => switch (phase) {
        SyncLifecyclePhase.idle => 'Idle',
        SyncLifecyclePhase.acquiring => 'Acquiring ownership',
        SyncLifecyclePhase.running => 'Synchronizing',
        SyncLifecyclePhase.releasing => 'Releasing ownership',
        SyncLifecyclePhase.closed => 'Closed',
      };

  SyncLifecycleSnapshot copyWith({
    SyncLifecyclePhase? phase,
    bool? wakePending,
    bool? closeRequested,
    bool? cancelRequested,
    bool? permitHeld,
    int? generation,
  }) =>
      SyncLifecycleSnapshot(
        phase: phase ?? this.phase,
        wakePending: wakePending ?? this.wakePending,
        closeRequested: closeRequested ?? this.closeRequested,
        cancelRequested: cancelRequested ?? this.cancelRequested,
        permitHeld: permitHeld ?? this.permitHeld,
        generation: generation ?? this.generation,
      );

  @override
  bool operator ==(Object other) =>
      other is SyncLifecycleSnapshot &&
      other.phase == phase &&
      other.wakePending == wakePending &&
      other.closeRequested == closeRequested &&
      other.cancelRequested == cancelRequested &&
      other.permitHeld == permitHeld &&
      other.generation == generation;

  @override
  int get hashCode => Object.hash(
        phase,
        wakePending,
        closeRequested,
        cancelRequested,
        permitHeld,
        generation,
      );

  @override
  String toString() => 'SyncLifecycleSnapshot(phase: ${phase.name}, '
      'wakePending: $wakePending, closeRequested: $closeRequested, '
      'cancelRequested: $cancelRequested, permitHeld: $permitHeld, '
      'generation: $generation)';
}

final class SyncLifecycleTransition {
  const SyncLifecycleTransition({
    required this.disposition,
    required this.before,
    required this.after,
    required this.command,
  });

  final TransitionDisposition disposition;
  final SyncLifecycleSnapshot before;
  final SyncLifecycleSnapshot after;
  final SyncLifecycleCommand command;

  bool get applied => disposition == TransitionDisposition.applied;
}

/// The only mutable lifecycle authority in the app shell.
///
/// [reduce] is total over all representable snapshots and commands. Invalid
/// transitions are rejected without mutation; stale generated settlements are
/// classified separately and also leave state unchanged.
final class SyncLifecycleMachine {
  SyncLifecycleMachine({
    SyncLifecycleSnapshot initial = const SyncLifecycleSnapshot.initial(),
  }) : _state = initial {
    if (!initial.isValid) {
      throw ArgumentError.value(initial, 'initial', 'must be valid');
    }
  }

  SyncLifecycleSnapshot _state;

  SyncLifecycleSnapshot get state => _state;

  SyncLifecycleTransition dispatch(SyncLifecycleCommand command) {
    final decision = reduce(_state, command);
    if (decision.applied) _state = decision.after;
    return decision;
  }

  static SyncLifecycleTransition reduce(
    SyncLifecycleSnapshot state,
    SyncLifecycleCommand command,
  ) {
    SyncLifecycleTransition unchanged(TransitionDisposition disposition) =>
        SyncLifecycleTransition(
          disposition: disposition,
          before: state,
          after: state,
          command: command,
        );

    if (!state.isValid) return unchanged(TransitionDisposition.rejected);
    if (command.event.requiresGeneration) {
      if (command.generation == null) {
        return unchanged(TransitionDisposition.rejected);
      }
      if (command.generation != state.generation) {
        return unchanged(TransitionDisposition.stale);
      }
    }

    final next = _next(state, command.event);
    if (next == null || !next.isValid) {
      return unchanged(TransitionDisposition.rejected);
    }
    return SyncLifecycleTransition(
      disposition: TransitionDisposition.applied,
      before: state,
      after: next,
      command: command,
    );
  }

  static SyncLifecycleSnapshot? _next(
    SyncLifecycleSnapshot state,
    SyncLifecycleEvent event,
  ) {
    switch (event) {
      case SyncLifecycleEvent.wake:
        if (!state.acceptsWake) return null;
        return state.copyWith(wakePending: true);
      case SyncLifecycleEvent.join:
        final canJoin = switch (state.phase) {
          SyncLifecyclePhase.idle => false,
          SyncLifecyclePhase.acquiring => true,
          SyncLifecyclePhase.running => true,
          SyncLifecyclePhase.releasing => true,
          SyncLifecyclePhase.closed => false,
        };
        return canJoin ? state : null;
      case SyncLifecycleEvent.beginAcquire:
        if (state.phase != SyncLifecyclePhase.idle ||
            !state.wakePending ||
            state.closeRequested) {
          return null;
        }
        return state.copyWith(
          phase: SyncLifecyclePhase.acquiring,
          wakePending: false,
          generation: state.generation + 1,
        );
      case SyncLifecycleEvent.acquireGranted:
        if (state.phase != SyncLifecyclePhase.acquiring) return null;
        return state.copyWith(
          phase: state.closeRequested
              ? SyncLifecyclePhase.releasing
              : SyncLifecyclePhase.running,
          permitHeld: true,
          cancelRequested: false,
        );
      case SyncLifecycleEvent.acquireDeferred:
        if (state.phase != SyncLifecyclePhase.acquiring) return null;
        return state.copyWith(
          phase: state.closeRequested
              ? SyncLifecyclePhase.closed
              : SyncLifecyclePhase.idle,
          wakePending: state.closeRequested ? false : state.wakePending,
          cancelRequested: false,
          permitHeld: false,
        );
      case SyncLifecycleEvent.cancel:
        if (state.phase != SyncLifecyclePhase.running) return null;
        return state.copyWith(cancelRequested: true);
      case SyncLifecycleEvent.cycleSettled:
        if (state.phase != SyncLifecyclePhase.running || !state.permitHeld) {
          return null;
        }
        return state.copyWith(
          phase: SyncLifecyclePhase.releasing,
          cancelRequested: false,
        );
      case SyncLifecycleEvent.releaseSettled:
        if (state.phase != SyncLifecyclePhase.releasing || !state.permitHeld) {
          return null;
        }
        return state.copyWith(
          phase: state.closeRequested
              ? SyncLifecyclePhase.closed
              : SyncLifecyclePhase.idle,
          wakePending: state.closeRequested ? false : state.wakePending,
          cancelRequested: false,
          permitHeld: false,
        );
      case SyncLifecycleEvent.close:
        if (state.phase == SyncLifecyclePhase.closed) return null;
        if (state.phase == SyncLifecyclePhase.idle) {
          return state.copyWith(
            phase: SyncLifecyclePhase.closed,
            wakePending: false,
            closeRequested: true,
            cancelRequested: false,
          );
        }
        return state.copyWith(
          wakePending: false,
          closeRequested: true,
          cancelRequested: state.phase == SyncLifecyclePhase.running,
        );
      case SyncLifecycleEvent.processAbort:
        final canAbort = switch (state.phase) {
          SyncLifecyclePhase.idle => false,
          SyncLifecyclePhase.acquiring => true,
          SyncLifecyclePhase.running => true,
          SyncLifecyclePhase.releasing => true,
          SyncLifecyclePhase.closed => false,
        };
        if (!canAbort) return null;
        return state.copyWith(
          phase: state.closeRequested
              ? SyncLifecyclePhase.closed
              : SyncLifecyclePhase.idle,
          wakePending: false,
          cancelRequested: false,
          permitHeld: false,
        );
    }
  }
}
