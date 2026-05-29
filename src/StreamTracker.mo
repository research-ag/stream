/// Prometheus tracking for stream receivers and senders.
///
/// This module provides helpers to track metrics for `StreamReceiver` and `StreamSender`
/// using the `promtracker` library.
///
/// For a usage example, see `examples/promtracker`.
///
/// ```motoko name=import
/// import { ReceiverTracker; SenderTracker; } "mo:stream/StreamTracker";
/// ```

import Array "mo:core/Array";
import Error "mo:core/Error";
import Int "mo:core/Int";
import Prim "mo:prim";

import PT "mo:promtracker";
import Label "mo:promtracker/Label";
import { Counter; Gauge; Tracker } "mo:promtracker";

import StreamReceiver "StreamReceiver";
import StreamSender "StreamSender";
import Types "internal/types";

module {
  /// Interface for a stream receiver that can be tracked.
  ///
  /// `length`: Returns the total number of bytes received.
  /// `callbacks`: The callbacks object of the receiver.
  public type ReceiverInterface = {
    length : () -> Nat;
    callbacks : StreamReceiver.Callbacks;
  };

  /// Prometheus tracker for a stream receiver.
  ///
  /// This module provides a helper to connect a `StreamReceiver` instance
  /// to a `PromTracker` instance.
  ///
  /// ```motoko include=import
  /// // Example usage
  /// let tracker = ReceiverTracker.new([("role", "alice")]);
  /// ReceiverTracker.init(tracker, receiver, promTracker, renderer);
  /// ```
  public module ReceiverTracker {
    /// The state of a receiver tracker.
    ///
    /// `previousTime`: The time when the last chunk was received (in milliseconds).
    /// `metrics`: The Prometheus metrics objects, or `null` if not yet initialized.
    /// `pullValuesRef`: A reference to the pull-based values in the renderer.
    /// `labels`: Additional labels applied to all metrics.
    public type ReceiverTracker = {
      var previousTime : Nat;

      var metrics : ?{
        // gauges
        chunkSize : Gauge.Gauge;
        stopFlag : Gauge.Gauge;

        // counters
        chunksOk : Counter.Counter;
        pingsOk : Counter.Counter;
        gaps : Counter.Counter;
        stops : Counter.Counter;
        restarts : Counter.Counter;
        lastStopPos : Counter.Counter;
        lastRestartPos : Counter.Counter;
        timeSinceLastChunk : Gauge.Gauge;
      };

      var pullValuesRef : ?Nat;
      labels : [Label.Label];
    };

    /// Creates a new `ReceiverTracker` instance.
    ///
    /// `labels`: Additional labels to be added to all metrics.
    ///
    /// Never traps.
    public func new(labels : [Label.Label]) : ReceiverTracker = {
      var previousTime = 0;
      var metrics = null;
      var pullValuesRef = null;
      labels;
    };

    /// Initializes the tracker by connecting it to a receiver and a PromTracker.
    ///
    /// This method sets up the callbacks on the `receiver` and registers
    /// metrics in the `tracker`.
    ///
    /// `self`: The tracker instance to initialize.
    /// `receiver`: The stream receiver to track.
    /// `tracker`: The PromTracker instance where metrics will be registered.
    /// `renderer`: The Renderer instance for pull-based metrics.
    ///
    /// Never traps.
    public func init(self : ReceiverTracker, receiver : ReceiverInterface, tracker : Tracker.Tracker, renderer : PT.Renderer) {
      receiver.callbacks.onChunk := func(info, ret) { onChunk(self, info, ret) };
      switch (self.metrics) {
        case (null) {
          self.metrics := ?{
            chunkSize = tracker.newGauge("stream_receiver_chunk_size", self.labels, Array.tabulate<Nat>(8, func(i) = 8 ** i));
            stopFlag = tracker.newGauge("stream_receiver_stop_flag", self.labels, []);
            chunksOk = tracker.newCounter("stream_receiver_total_chunks_ok", self.labels);
            pingsOk = tracker.newCounter("stream_receiver_total_pings_ok", self.labels);
            gaps = tracker.newCounter("stream_receiver_total_gaps", self.labels);
            stops = tracker.newCounter("stream_receiver_total_stops", self.labels);
            restarts = tracker.newCounter("stream_receiver_total_restarts", self.labels);
            lastStopPos = tracker.newCounter("stream_receiver_last_stop_pos", self.labels);
            lastRestartPos = tracker.newCounter("stream_receiver_last_restart_pos", self.labels);
            timeSinceLastChunk = tracker.newGauge("stream_receiver_time_since_last_chunk", self.labels, []);
          };
        };
        case _ {};
      };
      self.pullValuesRef := ?renderer.addValueRef(
        PT.bundle(
          [
            PT.newValue("stream_receiver_last_chunk_received", self.labels, func() = self.previousTime),
            PT.newValue("stream_receiver_length", self.labels, receiver.length),
          ],
          [],
        )
      );
    };

    /// Disposes of the tracker, unregistering all metrics.
    ///
    /// `self`: The tracker instance to dispose.
    /// `renderer`: The Renderer instance to remove pull-based values from.
    ///
    /// Never traps.
    public func dispose(self : ReceiverTracker, renderer : PT.Renderer) {
      switch (self.metrics) {
        case (?m) {
          m.chunkSize.unregister();
          m.stopFlag.unregister();
          m.chunksOk.unregister();
          m.pingsOk.unregister();
          m.gaps.unregister();
          m.stops.unregister();
          m.restarts.unregister();
          m.lastStopPos.unregister();
          m.lastRestartPos.unregister();
          m.timeSinceLastChunk.unregister();
        };
        case _ {};
      };
      switch (self.pullValuesRef) {
        case (?v) renderer.removeValue(v);
        case _ {};
      };
      // TODO: clear receiver callbacks?
      self.metrics := null;
      self.pullValuesRef := null;
    };

    func onChunk(self : ReceiverTracker, info : Types.ChunkMessageInfo, ret : Types.ControlMessage) {
      let (pos, msg) = info;
      let now = Prim.nat64ToNat(Prim.time() / 10 ** 6);

      switch (self.metrics) {
        case (?m) {
          switch (msg, ret) {
            case (#chunk size, #ok) {
              m.chunksOk.add(1);
              m.chunkSize.update(size);
            };
            case (#ping, #ok) m.pingsOk.add(1);
            case (#restart, #ok) {
              m.restarts.add(1);
              m.stopFlag.update(0);
              m.lastRestartPos.set(pos);
            };
            case (_, #gap) m.gaps.add(1);
            case (_, #stop i) {
              m.stops.add(1);
              m.stopFlag.update(1);
              m.lastStopPos.set(pos + i);
            };
          };
          if (ret != #gap and msg != #restart and self.previousTime != 0) {
            m.timeSinceLastChunk.update(now - self.previousTime);
          };
        };
        case null {};
      };

      self.previousTime := now;
    };
  };

  /// Interface for a stream sender that can be tracked.
  ///
  /// `busyLevel`: Returns the current busy level (number of in-flight chunks).
  /// `isPaused`: Returns `true` if the sender is paused.
  /// `isStopped`: Returns `true` if the sender is stopped.
  /// `isShutdown`: Returns `true` if the sender is shutdown.
  /// `queueSize`: Returns the current number of bytes in the queue.
  /// `sent`: Returns the total number of bytes sent.
  /// `received`: Returns the total number of bytes received (acknowledged).
  /// `length`: Returns the total length of the stream.
  /// `lastChunkSent`: Returns the timestamp of the last chunk sent.
  /// `windowSize`: Returns the current window size.
  /// `callbacks`: The callbacks object of the sender.
  public type SenderInterface = {
    busyLevel : () -> Nat;
    isPaused : () -> Bool;
    isStopped : () -> Bool;
    isShutdown : () -> Bool;
    queueSize : () -> Nat;
    sent : () -> Nat;
    received : () -> Nat;
    length : () -> Nat;
    lastChunkSent : () -> Int;
    windowSize : () -> Nat;
    callbacks : StreamSender.Callbacks;
  };

  /// Prometheus tracker for a stream sender.
  ///
  /// This module provides a helper to connect a `StreamSender` instance
  /// to a `PromTracker` instance.
  ///
  /// ```motoko include=import
  /// // Example usage
  /// let tracker = SenderTracker.new([("role", "bob")]);
  /// SenderTracker.init(tracker, sender, promTracker, renderer);
  /// ```
  public module SenderTracker {
    /// The state of a sender tracker.
    ///
    /// `metrics`: The Prometheus metrics objects, or `null` if not yet initialized.
    /// `pullValuesRef`: A reference to the pull-based values in the renderer.
    /// `labels`: Additional labels applied to all metrics.
    public type SenderTracker = {

      var metrics : ?{
        // on send
        busyLevel : Gauge.Gauge;
        queueSizePreBatch : Gauge.Gauge;
        queueSizePostBatch : Gauge.Gauge;
        chunkSize : Gauge.Gauge;
        pings : Counter.Counter;
        skips : Counter.Counter;

        // on response
        oks : Counter.Counter;
        gaps : Counter.Counter;
        stops : Counter.Counter;
        errors : Counter.Counter;
        stopFlag : Gauge.Gauge;
        pausedFlag : Gauge.Gauge;
        lastStopPos : Counter.Counter;
        lastRestartPos : Counter.Counter;

        // on error
        chunkErrorType : Gauge.Gauge;
      };

      var pullValuesRef : ?Nat;
      labels : [Label.Label];
    };

    /// Creates a new `SenderTracker` instance.
    ///
    /// `labels`: Additional labels to be added to all metrics.
    ///
    /// Never traps.
    public func new(labels : [Label.Label]) : SenderTracker = {
      var metrics = null;
      var pullValuesRef = null;
      labels;
    };

    /// Initializes the tracker by connecting it to a sender and a PromTracker.
    ///
    /// This method sets up the callbacks on the `sender` and registers
    /// metrics in the `tracker`.
    ///
    /// `self`: The tracker instance to initialize.
    /// `sender`: The stream sender to track.
    /// `tracker`: The PromTracker instance where metrics will be registered.
    /// `renderer`: The Renderer instance for pull-based metrics.
    ///
    /// Never traps.
    public func init(self : SenderTracker, sender : SenderInterface, tracker : Tracker.Tracker, renderer : PT.Renderer) {
      sender.callbacks.onSend := func(c) { onSend(self, sender, c) };
      sender.callbacks.onNoSend := func() { onNoSend(self) };
      sender.callbacks.onError := func(e) { onError(self, e) };
      sender.callbacks.onResponse := func(res) { onResponse(self, sender, res) };
      sender.callbacks.onRestart := func() { onRestart(self, sender) };

      switch (self.metrics) {
        case (null) {
          self.metrics := ?{
            // on send
            busyLevel = tracker.newGauge("stream_sender_window_size", self.labels, []);
            queueSizePreBatch = tracker.newGauge("stream_sender_queue_size_pre_batch", self.labels, []);
            queueSizePostBatch = tracker.newGauge("stream_sender_queue_size_post_batch", self.labels, []);
            chunkSize = tracker.newGauge("stream_sender_chunk_size", self.labels, Array.tabulate<Nat>(8, func(i) = 8 ** i));
            pings = tracker.newCounter("stream_sender_total_pings", self.labels);
            skips = tracker.newCounter("stream_sender_total_skips", self.labels);

            // on response
            oks = tracker.newCounter("stream_sender_total_oks", self.labels);
            gaps = tracker.newCounter("stream_sender_total_gaps", self.labels);
            stops = tracker.newCounter("stream_sender_total_stops", self.labels);
            errors = tracker.newCounter("stream_sender_total_errors", self.labels);
            stopFlag = tracker.newGauge("stream_sender_stop_flag", self.labels, []);
            pausedFlag = tracker.newGauge("stream_sender_paused_flag", self.labels, []);
            lastStopPos = tracker.newCounter("stream_sender_last_stop_pos", self.labels);
            lastRestartPos = tracker.newCounter("stream_sender_last_restart_pos", self.labels);

            // on error
            chunkErrorType = tracker.newGauge("stream_sender_chunk_error_type", self.labels, [0, 1, 2, 3, 4, 5, 6]);
          };
        };
        case _ {};
      };

      self.pullValuesRef := ?renderer.addValueRef(
        PT.bundle(
          [
            PT.newValue("stream_sender_sent", self.labels, sender.sent),
            PT.newValue("stream_sender_received", self.labels, sender.received),
            PT.newValue("stream_sender_length", self.labels, sender.length),
            PT.newValue("stream_sender_last_chunk_sent", self.labels, func() : Nat = Int.abs(sender.lastChunkSent()) / 10 ** 9),
            PT.newValue("stream_sender_shutdown", self.labels, func() = if (sender.isShutdown()) 1 else 0),
            PT.newValue("stream_sender_setting_window_size", self.labels, sender.windowSize),
          ],
          [],
        )
      );
    };

    /// Disposes of the tracker, unregistering all metrics.
    ///
    /// `self`: The tracker instance to dispose.
    /// `renderer`: The Renderer instance to remove pull-based values from.
    ///
    /// Never traps.
    public func dispose(self : SenderTracker, renderer : PT.Renderer) {
      switch (self.metrics) {
        case (?m) {
          m.busyLevel.unregister();
          m.queueSizePreBatch.unregister();
          m.queueSizePostBatch.unregister();
          m.chunkSize.unregister();
          m.pings.unregister();
          m.skips.unregister();
          m.oks.unregister();
          m.gaps.unregister();
          m.stops.unregister();
          m.errors.unregister();
          m.stopFlag.unregister();
          m.pausedFlag.unregister();
          m.lastStopPos.unregister();
          m.lastRestartPos.unregister();
          m.chunkErrorType.unregister();
        };
        case _ {};
      };
      switch (self.pullValuesRef) {
        case (?v) renderer.removeValue(v);
        case _ {};
      };
      // TODO: clear receiver callbacks?
      self.metrics := null;
      self.pullValuesRef := null;
    };

    func onSend(self : SenderTracker, sender : SenderInterface, c : Types.ChunkInfo) {
      switch (self.metrics) {
        case (?m) {
          m.busyLevel.update(sender.busyLevel());
          m.queueSizePostBatch.update(sender.queueSize());
          switch (c) {
            case (#ping) {
              m.pings.add(1);
              m.queueSizePreBatch.update(sender.queueSize());
            };
            case (#chunk size) {
              m.chunkSize.update(size);
              m.queueSizePreBatch.update(sender.queueSize() + size);
            };
          };
        };
        case _ {};
      };
    };

    func onNoSend(self : SenderTracker) {
      let ?m = self.metrics else return;
      m.skips.add(1);
    };

    func onError(self : SenderTracker, e : Error.Error) {
      let ?m = self.metrics else return;
      let rejectCode = switch (Error.code(e)) {
        case (#call_error _) 0;
        case (#system_fatal) 1;
        case (#system_transient) 2;
        case (#destination_invalid) 3;
        case (#canister_reject) 4;
        case (#canister_error) 5;
        case (#future _) 7;
        case (#system_unknown) 8;
      };
      m.chunkErrorType.update(rejectCode);
    };

    func onResponse(self : SenderTracker, sender : SenderInterface, res : Types.ControlMessage or { #error }) {
      let ?m = self.metrics else return;
      switch (res) {
        case (#ok) m.oks.add(1);
        case (#gap) m.gaps.add(1);
        case (#stop _) m.stops.add(1);
        case (#error) m.errors.add(1);
      };
      m.busyLevel.update(sender.busyLevel());
      m.stopFlag.update(if (sender.isStopped()) 1 else 0);
      m.pausedFlag.update(if (sender.isPaused()) 1 else 0);
      if (sender.isStopped()) {
        m.lastStopPos.set(sender.sent());
      };
    };

    func onRestart(self : SenderTracker, sender : SenderInterface) {
      let ?m = self.metrics else return;
      m.lastRestartPos.set(sender.sent());
    };
  };
};
