import { min } "mo:core/Nat";
import Types "internal/types";

module {
  /// Return type of processing function.
  public type ControlMessage = Types.ControlMessage;

  /// Argument of processing function.
  public type ChunkMessage<T> = Types.ChunkMessage<T>;

  /// Type of `StableData` for `share`/`unshare` function.
  /// Stream length, last chunk received timestamp, stopped flag.
  public type StableData = (Nat, Int, Bool);

  /// Callbacks called during processing chunk.
  public type Callbacks = {
    var onChunk : (Types.ChunkMessageInfo, ControlMessage) -> ();
  };

  /// StreamReceiver
  /// * receives chunk by `onChunk` call
  /// * validates `start` position in ChunkMessage (must match internal `length` variable)
  /// * calls `itemCallback` for each item of the chunk.
  ///
  /// Constructor arguments:
  /// * `itemCallback` function
  /// * `timeout` is maximum waiting time between onChunk calls (default = infinite)
  public class StreamReceiver<T>(
    itemCallback : (pos : Nat, item : T) -> Bool,
    timeoutArg : ?(Nat, () -> Int),
  ) {
    /// Callbacks called during processing chunk.
    public let callbacks : Callbacks = {
      var onChunk = func(_) {};
    };

    var maxLength : ?Nat = null;

    /// Set max stream length
    public func setMaxLength(length : ?Nat) {
      maxLength := length;
    };

    var stopped_ = false;
    var length_ = 0;
    var lastChunkReceived_ : Int = 0;

    func checkTimeAndStop() {
      let ?arg = timeoutArg else return;
      let now = arg.1 ();
      if ((now - lastChunkReceived_) <= arg.0) {
        lastChunkReceived_ := now;
      } else stop();
    };

    func resetTimeout() {
      let ?arg = timeoutArg else return;
      lastChunkReceived_ := arg.1 ();
    };

    resetTimeout();

    /// Share data in order to store in stable variable. No validation is performed.
    public func share() : StableData = (
      length_,
      lastChunkReceived_,
      stopped_,
    );

    /// Unhare data in order to store in stable variable. No validation is performed.
    public func unshare(data : StableData) {
      length_ := data.0;
      lastChunkReceived_ := data.1;
      stopped_ := data.2;
    };

    /// Returns `#gap` if start position in ChunkMessage does not match internal length.
    /// Returns `#stopped` if the receiver is already stopped or maximum waiting time between chunks is exceeded.
    /// Otherwise processes a chunk and call `itemCallback` on each item.
    /// A #ping message is handled equivalently to a #chunk of length zero.
    public func onChunk(cm : Types.ChunkMessage<T>) : Types.ControlMessage {
      let ret = processChunk(cm);
      callbacks.onChunk |> _(Types.chunkMessageInfo(cm), ret);
      ret;
    };

    func processChunk(cm : Types.ChunkMessage<T>) : Types.ControlMessage {
      let (start, msg) = cm;
      if (start != length_) return #gap;
      switch (msg) {
        case (#ping or #chunk _) {
          checkTimeAndStop();
          if (stopped_) return #stop 0;
        };
        case (#restart) {
          resetTimeout();
          stopped_ := false;
        };
      };
      let #chunk ch = msg else return #ok;
      let n = switch (maxLength) {
        case (?max) min(max - length_, ch.size());
        case (null) ch.size();
      };
      var i = 0;
      label w while (i < n) {
        if (not itemCallback(start + i, ch[i])) break w;
        i += 1;
      };
      length_ += i;
      if (i == ch.size()) #ok else #stop i;
    };

    /// Manually stop the receiver.
    public func stop() = stopped_ := true;

    /// Current number of received items.
    public func length() : Nat = length_;

    /// Timestamp when stream received last chunk
    public func lastChunkReceived() : Int = lastChunkReceived_;

    /// Flag if receiver is stopped (manually or by inactivity timeout)
    public func isStopped() : Bool {
      checkTimeAndStop();
      stopped_;
    };
  };
};
