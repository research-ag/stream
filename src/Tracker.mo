import Array "mo:core/Array";
import List "mo:core/List";
import Error "mo:core/Error";
import Int "mo:core/Int";
import Prim "mo:prim";
import PT "mo:promtracker";

import StreamReceiver "StreamReceiver";
import StreamSender "StreamSender";
import Types "types";

/// See use example in examples/promtracker.
module {
  public type ReceiverInterface = {
    length : () -> Nat;
    callbacks : StreamReceiver.Callbacks;
  };

  /// Receiver tracker.
  public class Receiver(metrics : PT.PromTracker, labels : Text, stable_ : Bool) {
    var receiver_ : ?ReceiverInterface = null;
    var previousTime : Nat = 0;

    // gauges
    public let chunkSize = metrics.addGauge("stream_receiver_chunk_size", labels, #both, Array.tabulate<Nat>(8, func(i) = 8 ** i), stable_);
    public let stopFlag = metrics.addGauge("stream_receiver_stop_flag", labels, #both, [], stable_);

    // pulls
    public let lastChunkReceived = metrics.addPullValue("stream_receiver_last_chunk_received", labels, func() = previousTime);

    // counters
    public let chunksOk = metrics.addCounter("stream_receiver_total_chunks_ok", labels, stable_);
    public let pingsOk = metrics.addCounter("stream_receiver_total_pings_ok", labels, stable_);
    public let gaps = metrics.addCounter("stream_receiver_total_gaps", labels, stable_);
    public let stops = metrics.addCounter("stream_receiver_total_stops", labels, stable_);
    public let restarts = metrics.addCounter("stream_receiver_total_restarts", labels, stable_);
    public let lastStopPos = metrics.addCounter("stream_receiver_last_stop_pos", labels, stable_);
    public let lastRestartPos = metrics.addCounter("stream_receiver_last_restart_pos", labels, stable_);
    public let timeSinceLastChunk = metrics.addGauge("stream_receiver_time_since_last_chunk", labels, #both, [], stable_);

    var pullValues = List.empty<{ remove : () -> () }>();

    public func init(receiver : ReceiverInterface) {
      receiver_ := ?receiver;
      receiver.callbacks.onChunk := onChunk;
      pullValues.add(metrics.addPullValue("stream_receiver_length", labels, receiver.length));
    };

    public func dispose() {
      chunkSize.remove();
      stopFlag.remove();
      lastChunkReceived.remove();
      chunksOk.remove();
      pingsOk.remove();
      gaps.remove();
      stops.remove();
      restarts.remove();
      lastStopPos.remove();
      lastRestartPos.remove();
      timeSinceLastChunk.remove();
      for (v in pullValues.values()) {
        v.remove();
      };
      pullValues.clear();
    };

    public func onChunk(info : Types.ChunkMessageInfo, ret : Types.ControlMessage) {
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
  public class Sender(metrics : PT.PromTracker, labels : Text, stable_ : Bool) {
    var sender_ : ?SenderInterface = null;

    // on send
    public let busyLevel = metrics.addGauge("stream_sender_window_size", labels, #both, [], stable_);
    public let queueSizePreBatch = metrics.addGauge("stream_sender_queue_size_pre_batch", labels, #both, [], stable_);
    public let queueSizePostBatch = metrics.addGauge("stream_sender_queue_size_post_batch", labels, #both, [], stable_);
    public let chunkSize = metrics.addGauge("stream_sender_chunk_size", labels, #both, Array.tabulate<Nat>(8, func(i) = 8 ** i), stable_);
    public let pings = metrics.addCounter("stream_sender_total_pings", labels, stable_);
    public let skips = metrics.addCounter("stream_sender_total_skips", labels, stable_);

    // on response
    public let oks = metrics.addCounter("stream_sender_total_oks", labels, stable_);
    public let gaps = metrics.addCounter("stream_sender_total_gaps", labels, stable_);
    public let stops = metrics.addCounter("stream_sender_total_stops", labels, stable_);
    public let errors = metrics.addCounter("stream_sender_total_errors", labels, stable_);
    public let stopFlag = metrics.addGauge("stream_sender_stop_flag", labels, #both, [], stable_);
    public let pausedFlag = metrics.addGauge("stream_sender_paused_flag", labels, #both, [], stable_);
    public let lastStopPos = metrics.addCounter("stream_sender_last_stop_pos", labels, stable_);
    public let lastRestartPos = metrics.addCounter("stream_sender_last_restart_pos", labels, stable_);

    // on error
    public let chunkErrorType = metrics.addGauge("stream_sender_chunk_error_type", labels, #none, [0, 1, 2, 3, 4, 5, 6], stable_);

    var pullValues = List.empty<{ remove : () -> () }>();

    public func init(sender : SenderInterface) {
      sender_ := ?sender;
      sender.callbacks.onSend := onSend;
      sender.callbacks.onNoSend := onNoSend;
      sender.callbacks.onError := onError;
      sender.callbacks.onResponse := onResponse;
      sender.callbacks.onRestart := onRestart;

      pullValues.add(metrics.addPullValue("stream_sender_sent", labels, sender.sent));
      pullValues.add(metrics.addPullValue("stream_sender_received", labels, sender.received));
      pullValues.add(metrics.addPullValue("stream_sender_length", labels, sender.length));
      pullValues.add(metrics.addPullValue("stream_sender_last_chunk_sent", labels, func() : Nat { Int.abs(sender.lastChunkSent()) / 10 ** 9 }));
      pullValues.add(metrics.addPullValue("stream_sender_shutdown", labels, func() = if (sender.isShutdown()) 1 else 0));
      pullValues.add(metrics.addPullValue("stream_sender_setting_window_size", labels, sender.windowSize));
    };

    public func dispose() {
      busyLevel.remove();
      queueSizePreBatch.remove();
      queueSizePostBatch.remove();
      chunkSize.remove();
      pings.remove();
      skips.remove();
      oks.remove();
      gaps.remove();
      stops.remove();
      errors.remove();
      stopFlag.remove();
      pausedFlag.remove();
      lastStopPos.remove();
      lastRestartPos.remove();
      chunkErrorType.remove();
      for (v in pullValues.values()) {
        v.remove();
      };
      pullValues.clear();
    };

    public func onSend(c : Types.ChunkInfo) {
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

    public func onNoSend() {
      skips.add(1);
    };

    public func onError(e : Error.Error) {
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

    public func onResponse(res : Types.ControlMessage or { #error }) {
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

    public func onRestart() {
      let ?s = sender_ else return;
      lastRestartPos.set(s.sent());
    };
  };
};
