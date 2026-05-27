import Array "mo:core/Array";
import Error "mo:core/Error";
import Int "mo:core/Int";
import Prim "mo:prim";
import PT "mo:promtracker";
import Metrics "mo:promtracker/Metrics";
import Label "mo:promtracker/Label";
// Import only the modules you actually use to enable dot-notation
import { Counter; Gauge } "mo:promtracker";

import StreamReceiver "StreamReceiver";
import StreamSender "StreamSender";
import Types "internal/types";

/// See use example in examples/promtracker.
module {
  /// A subtype of the Receiver class.
  public type ReceiverInterface = {
    length : () -> Nat;
    callbacks : StreamReceiver.Callbacks;
  };

  /// Receiver tracker.
  ///
  /// This class is a convenient helper used to connect one specific Receiver instance
  /// to one specific PromTracker instance.
  ///
  /// The PromTracker instance is passed in to the constructor.
  /// The constructor code will then add all relevant metrics to the PromTracker.
  ///
  /// The Receiver instance is passed in to the init() method.
  /// The init() method will then connect all relevant events in the Receiver to update
  /// the metrics in the PromTracker.
  ///
  /// Further constructor arguments are:
  ///
  /// * `labels` : additional labels given to all metrics that are added to the PromTracker.
  /// * `stable_` : whether PromTracker persists the metrics across canister upgrades or not.
  ///
  /// If you want to connect more than one Receiver to the same PromTracker then
  /// create multiple Receiver tracker instances, one for each Receiver instance.
  /// Make sure to pass different labels to each Receiver tracker instance because that is
  /// the only way the single PromTracker instance can distinguish between them.
  public class Receiver(pt : PT.Tracker, labels : [Label.Label], _stable_ : Bool) {
    var receiver_ : ?ReceiverInterface = null;
    var previousTime : Nat = 0;

    // gauges
    let chunkSize = PT.Tracker.newGauge(pt, "stream_receiver_chunk_size", labels, Array.tabulate<Nat>(8, func(i) = 8 ** i));
    let stopFlag = PT.Tracker.newGauge(pt, "stream_receiver_stop_flag", labels, []);

    // counters
    let chunksOk = PT.Tracker.newCounter(pt, "stream_receiver_total_chunks_ok", labels);
    let pingsOk = PT.Tracker.newCounter(pt, "stream_receiver_total_pings_ok", labels);
    let gaps = PT.Tracker.newCounter(pt, "stream_receiver_total_gaps", labels);
    let stops = PT.Tracker.newCounter(pt, "stream_receiver_total_stops", labels);
    let restarts = PT.Tracker.newCounter(pt, "stream_receiver_total_restarts", labels);
    let lastStopPos = PT.Tracker.newCounter(pt, "stream_receiver_last_stop_pos", labels);
    let lastRestartPos = PT.Tracker.newCounter(pt, "stream_receiver_last_restart_pos", labels);
    let timeSinceLastChunk = PT.Tracker.newGauge(pt, "stream_receiver_time_since_last_chunk", labels, []);

    /// Initialize the tracker once by passing the Sender class to track.
    public func init(receiver : ReceiverInterface) {
      receiver_ := ?receiver;
      receiver.callbacks.onChunk := onChunk;
    };

    /// Returns a pull-based metric for the stream length.
    public func lengthMetric() : Metrics.Value {
      let ?r = receiver_ else return PT.newValue("stream_receiver_length", labels, func() = 0);
      PT.newValue("stream_receiver_length", labels, r.length);
    };

    /// Returns a pull-based metric for the last chunk received time.
    public func lastChunkReceivedMetric() : Metrics.Value {
      PT.newValue("stream_receiver_last_chunk_received", labels, func() = previousTime);
    };

    /// Remove all metrics created by this tracker from the PromTracker.
    public func dispose() {
      Counter.unregister(chunksOk);
      Counter.unregister(pingsOk);
      Counter.unregister(gaps);
      Counter.unregister(stops);
      Counter.unregister(restarts);
      Counter.unregister(lastStopPos);
      Counter.unregister(lastRestartPos);
      Gauge.unregister(chunkSize);
      Gauge.unregister(stopFlag);
      Gauge.unregister(timeSinceLastChunk);
      // TODO: clear receiver callbacks?
    };

    func onChunk(info : Types.ChunkMessageInfo, ret : Types.ControlMessage) {
      let (pos, msg) = info;
      switch (msg, ret) {
        case (#chunk size, #ok) {
          chunksOk.add(1);
          chunkSize.update(size);
        };
        case (#ping, #ok) pingsOk.add(1);
        case (#restart, #ok) {
          restarts.add(1);
          stopFlag.update(0);
          lastRestartPos.set(pos);
        };
        case (_, #gap) gaps.add(1);
        case (_, #stop i) {
          stops.add(1);
          stopFlag.update(1);
          lastStopPos.set(pos + i);
        };
      };
      let now = Prim.nat64ToNat(Prim.time() / 10 ** 6);
      if (ret != #gap and msg != #restart and previousTime != 0) {
        timeSinceLastChunk.update(now - previousTime);
      };
      previousTime := now;
    };
  };

  /// A subtype of the Sender class.
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

  /// Sender tracker.
  ///
  /// This class is a convenient helper used to connect one specific Sender instance
  /// to one specific PromTracker instance.
  ///
  /// The PromTracker instance is passed in to the constructor.
  /// The constructor code will then add all relevant metrics to the PromTracker.
  ///
  /// The Sender instance is passed in to the init() method.
  /// The init() method will then connect all relevant events in the Sender to update
  /// the metrics in the PromTracker.
  ///
  /// Further constructor arguments are:
  ///   labels : additional labels given to all metrics that are added to the PromTracker.
  ///   stable_ : whether PromTracker persists the metrics across canister upgrades or not.
  ///
  /// If you want to connect more than one Sender to the same PromTracker then
  /// create multiple Sender tracker instances, one for each Sender instance.
  /// Make sure to pass different labels to each Sender tracker instance because that is
  /// the only way the single PromTracker instance can distinguish between them.
  public class Sender(pt : PT.Tracker, labels : [Label.Label], _stable_ : Bool) {
    var sender_ : ?SenderInterface = null;

    // on send
    let busyLevel = PT.Tracker.newGauge(pt, "stream_sender_window_size", labels, []);
    let queueSizePreBatch = PT.Tracker.newGauge(pt, "stream_sender_queue_size_pre_batch", labels, []);
    let queueSizePostBatch = PT.Tracker.newGauge(pt, "stream_sender_queue_size_post_batch", labels, []);
    let chunkSize = PT.Tracker.newGauge(pt, "stream_sender_chunk_size", labels, Array.tabulate<Nat>(8, func(i) = 8 ** i));
    let pings = PT.Tracker.newCounter(pt, "stream_sender_total_pings", labels);
    let skips = PT.Tracker.newCounter(pt, "stream_sender_total_skips", labels);

    // on response
    let oks = PT.Tracker.newCounter(pt, "stream_sender_total_oks", labels);
    let gaps = PT.Tracker.newCounter(pt, "stream_sender_total_gaps", labels);
    let stops = PT.Tracker.newCounter(pt, "stream_sender_total_stops", labels);
    let errors = PT.Tracker.newCounter(pt, "stream_sender_total_errors", labels);
    let stopFlag = PT.Tracker.newGauge(pt, "stream_sender_stop_flag", labels, []);
    let pausedFlag = PT.Tracker.newGauge(pt, "stream_sender_paused_flag", labels, []);
    let lastStopPos = PT.Tracker.newCounter(pt, "stream_sender_last_stop_pos", labels);
    let lastRestartPos = PT.Tracker.newCounter(pt, "stream_sender_last_restart_pos", labels);

    // on error
    let chunkErrorType = PT.Tracker.newGauge(pt, "stream_sender_chunk_error_type", labels, [0, 1, 2, 3, 4, 5, 6]);

    /// Initialize the tracker once by passing the Sender class to track.
    public func init(sender : SenderInterface) {
      sender_ := ?sender;
      sender.callbacks.onSend := onSend;
      sender.callbacks.onNoSend := onNoSend;
      sender.callbacks.onError := onError;
      sender.callbacks.onResponse := onResponse;
      sender.callbacks.onRestart := onRestart;
    };

    public func sentMetric() : Metrics.Value {
      let ?s = sender_ else return PT.newValue("stream_sender_sent", labels, func() = 0);
      PT.newValue("stream_sender_sent", labels, s.sent);
    };

    public func receivedMetric() : Metrics.Value {
      let ?s = sender_ else return PT.newValue("stream_sender_received", labels, func() = 0);
      PT.newValue("stream_sender_received", labels, s.received);
    };

    public func lengthMetric() : Metrics.Value {
      let ?s = sender_ else return PT.newValue("stream_sender_length", labels, func() = 0);
      PT.newValue("stream_sender_length", labels, s.length);
    };

    public func lastChunkSentMetric() : Metrics.Value {
      let ?s = sender_ else return PT.newValue("stream_sender_last_chunk_sent", labels, func() = 0);
      PT.newValue("stream_sender_last_chunk_sent", labels, func() : Nat = Int.abs(s.lastChunkSent()) / 10 ** 9);
    };

    public func shutdownMetric() : Metrics.Value {
      let ?s = sender_ else return PT.newValue("stream_sender_shutdown", labels, func() = 0);
      PT.newValue("stream_sender_shutdown", labels, func() = if (s.isShutdown()) 1 else 0);
    };

    public func windowSizeMetric() : Metrics.Value {
      let ?s = sender_ else return PT.newValue("stream_sender_setting_window_size", labels, func() = 0);
      PT.newValue("stream_sender_setting_window_size", labels, s.windowSize);
    };

    /// Remove all metrics created by this tracker from the PromTracker.
    public func dispose() {
      Gauge.unregister(busyLevel);
      Gauge.unregister(queueSizePreBatch);
      Gauge.unregister(queueSizePostBatch);
      Gauge.unregister(chunkSize);
      Counter.unregister(pings);
      Counter.unregister(skips);
      Counter.unregister(oks);
      Counter.unregister(gaps);
      Counter.unregister(stops);
      Counter.unregister(errors);
      Gauge.unregister(stopFlag);
      Gauge.unregister(pausedFlag);
      Counter.unregister(lastStopPos);
      Counter.unregister(lastRestartPos);
      Gauge.unregister(chunkErrorType);
      // TODO: clear sender callbacks?
    };

    func onSend(c : Types.ChunkInfo) {
      let ?s = sender_ else return;
      busyLevel.update(s.busyLevel());
      queueSizePostBatch.update(s.queueSize());
      switch (c) {
        case (#ping) {
          pings.add(1);
          queueSizePreBatch.update(s.queueSize());
        };
        case (#chunk size) {
          chunkSize.update(size);
          queueSizePreBatch.update(s.queueSize() + size);
        };
      };
    };

    func onNoSend() {
      skips.add(1);
    };

    func onError(e : Error.Error) {
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
      chunkErrorType.update(rejectCode);
    };

    func onResponse(res : Types.ControlMessage or { #error }) {
      switch (res) {
        case (#ok) oks.add(1);
        case (#gap) gaps.add(1);
        case (#stop _) stops.add(1);
        case (#error) errors.add(1);
      };
      let ?s = sender_ else return;
      busyLevel.update(s.busyLevel());
      stopFlag.update(if (s.isStopped()) 1 else 0);
      pausedFlag.update(if (s.isPaused()) 1 else 0);
      if (s.isStopped()) {
        lastStopPos.set(s.sent());
      };
    };

    func onRestart() {
      let ?s = sender_ else return;
      lastRestartPos.set(s.sent());
    };
  };
};
