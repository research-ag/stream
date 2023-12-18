import Debug "mo:base/Debug";
import Error "mo:base/Error";
import R "mo:base/Result";
import Array "mo:base/Array";
import Time "mo:base/Time";
import SWB "mo:swb";
import Types "types";

module {
  /// Return type of processing function.
  public type ControlMessage = Types.ControlMessage;

  /// Argument of processing function.
  public type ChunkMessage<T> = Types.ChunkMessage<T>;

  /// Type of `StableData` for `share`/`unshare` function.
  public type StableData = (Nat, Int);

  /// Stream recevier receiving chunks on `onChunk` call,
  /// validating whether `length` in chunk message corresponds to `length` inside `StreamRecevier`,
  /// calling `itemCallback` on each items of the chunk.
  ///
  /// Arguments:
  /// * `startPos` is starting length.
  /// * `timeout` is maximum time between onChunk calls. Default time period is infinite.
  /// * `itemCallback` function to be called on each received item.
  public class StreamReceiver<T>(
    startPos : Nat,
    timeout : ?Nat,
    itemCallback : (pos : Nat, item : T) -> (),
    // itemCallback is custom made per-stream and contains the streamId
  ) {
    var stopped_ = false;
    var length_ : Nat = startPos;

    var lastChunkReceived_ : Int = switch (timeout) {
      case (?to) Time.now();
      case (_) 0;
    };

    /// Share data in order to store in stable varible. No validation is performed.
    public func share() : StableData = (length_, lastChunkReceived_);

    /// Unhare data in order to store in stable varible. No validation is performed.
    public func unshare(data : StableData) {
      length_ := data.0;
      lastChunkReceived_ := data.1;
    };

    /// Returns `#gap` if length in chunk don't correspond to length in `StreamReceiver`.
    /// Returns `#stopped` if the receiver is already stopped or maximum time out between chunks exceeded.
    /// Otherwise processes a chunk and call `itemCallback` on each item.
    public func onChunk(cm : Types.ChunkMessage<T>) : Types.ControlMessage {
      let (start, msg) = cm;
      if (start != length_) return #gap;
      updateTimeout();
      if (stopped_) return #stop;
      switch (msg) {
        case (#chunk ch) {
          for (i in ch.keys()) {
            itemCallback(start + i, ch[i]);
            length_ += 1;
          };
        };
        case (#ping) {};
      };
      return #ok;
    };

    /// Manually stop the receiver.
    public func stop() { stopped_ := true };

    /// Current number of received items.
    public func length() : Nat = length_;

    /// Returns timestamp when stream received last chunk
    public func lastChunkReceived() : Int = lastChunkReceived_;

    /// Returns flag if receiver timed out because of non-activity or stopped.
    public func isStopped() : Bool = stopped_;

    func updateTimeout() {
      switch (timeout) {
        case (?to) {
          let now = Time.now();
          if ((now - lastChunkReceived_) > to) {
            stopped_ := true;
          } else {
            lastChunkReceived_ := now;
          };
        };
        case (_) {};
      };
    };
  };
};
