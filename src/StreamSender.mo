import Error "mo:base/Error";
import Nat "mo:base/Nat";
import Option "mo:base/Option";
import Result "mo:base/Result";
import SWB "mo:swb";
import Vector "mo:vector";
import Types "types";

module {
  /// Status of `StreamSender`.
  public type Status = { #shutdown; #stopped; #paused; #busy; #ready };

  /// Return type of processing function.
  public type ControlMessage = Types.ControlMessage;

  /// Argument of processing function.
  public type ChunkMessage<T> = Types.ChunkMessage<T>;

  /// Maximum concurrent chunks number.
  public let MAX_CONCURRENT_CHUNKS_DEFAULT = 5;

  /// Settings of `StreamSender`.
  public type SettingsArg = {
    maxQueueSize : ?Nat;
    maxConcurrentChunks : ?Nat;
    keepAlive : ?(Nat, () -> Int);
  };

  /// Type of `StableData` for `share`/`unshare` function.
  public type StableData<T> = {
    buffer : SWB.StableData<T>;
    stopped : Bool;
    head : Nat;
    lastChunkSent : Int;
    shutdown : Bool;
  };
  public type Callbacks = {
    onNoSend : () -> ();
    onSend : { #ping; #chunk : [Any] } -> ();
    onError : Error.Error -> ();
    onResponse : { #ok; #gap; #stop; #error } -> ();
    onRestart : () -> ();
  };

  /// Stream sender receiving items of type `Q` with `push` function and sending them with `sendFunc` callback when calling `sendChunk`.
  ///
  /// Arguments:
  /// * `sendFunc` typically should implement sending chunk to the receiver canister.
  /// * `counterCreator` is used to create a chunk out of pushed items.
  /// `accept` function is called sequentially on items which are added to the chunk, until receiving `null`.
  /// If the item is accepted it should be converted to type `S`.
  /// Typical implementation of `counter` is to accept items while their total size is less then given maximum chunk size.
  /// * `settings` consists of:
  ///   * `maxQueueSize` is maximum number of elements, which can simultaneously be in `StreamSender`'s queue. Default value is infinity.
  ///   * `maxConcurrentChunks` is maximum number of concurrent `sendChunk` calls. Default value is `MAX_CONCURRENT_CHUNKS_DEFAULT`.
  ///   * `keepAlive` is pair of period in seconds after which `StreamSender` should send ping chunk in case if there is no items to send and current time function.
  ///     Default value means not to ping.
  public class StreamSender<Q, S>(
    sendFunc : (x : Types.ChunkMessage<S>) -> async* Types.ControlMessage,
    counterCreator : () -> { accept(item : Q) : ?S },
    settings : ?SettingsArg,
  ) {
    public var callbacks : Callbacks = {
      onNoSend = func(_) {};
      onSend = func(_) {};
      onError = func(_) {};
      onResponse = func(_) {};
      onRestart = func(_) {};
    };

    let buffer = SWB.SlidingWindowBuffer<Q>();

    let settings_ = {
      var maxQueueSize = Option.chain<SettingsArg, Nat>(settings, func(s) = s.maxQueueSize);
      var keepAlive = Option.chain<SettingsArg, (Nat, () -> Int)> (settings, func(s) = s.keepAlive);
      var maxConcurrentChunks : Nat = Option.get(
        Option.chain<SettingsArg, Nat>(settings, func(s) = s.maxConcurrentChunks),
        MAX_CONCURRENT_CHUNKS_DEFAULT,
      );
    };

    var stopped = false;
    var paused = false;
    var head : Nat = 0;
    var lastChunkSent_ : Int = 0;
    var concurrentChunks = 0;
    var shutdown = false;

    func updateTime() {
      let ?arg = settings_.keepAlive else return;
      lastChunkSent_ := arg.1 ();
    };

    /// Share data in order to store in stable varible. No validation is performed.
    public func share() : StableData<Q> = {
      buffer = buffer.share();
      stopped = stopped;
      head = head;
      lastChunkSent = lastChunkSent_;
      shutdown = shutdown or paused or concurrentChunks > 0;
    };

    /// Unhare data in order to store in stable varible. No validation is performed.
    public func unshare(data : StableData<Q>) {
      buffer.unshare(data.buffer);
      stopped := data.stopped;
      head := data.head;
      lastChunkSent_ := data.lastChunkSent;
      shutdown := data.shutdown;
    };

    func queueFull() : Bool {
      let ?maxQueueSize = settings_.maxQueueSize else return false;
      buffer.len() >= maxQueueSize;
    };

    /// Add item to the `StreamSender`'s queue. Return number of succesfull `push` call, or error in case of lack of space.
    public func push(item : Q) : Result.Result<Nat, { #NoSpace }> {
      if (queueFull()) return #err(#NoSpace);
      return #ok(buffer.add item);
    };

    /// Get the stream sender's status for inspection.
    ///
    /// The function is sychronous. It can be used (optionally) by the user of
    /// the class before calling the asynchronous function sendChunk.
    ///
    /// sendChunk will attempt to send a chunk if and only if the status is
    /// `#ready`.  sendChunk will throw if and only if the status is `#shutdown`, `#stopped`,
    /// `#paused` or `#busy`.
    ///
    /// `#shutdown` means irrecoverable error ocurred during the work process of `StreamSender`.
    ///
    /// `#stopped` means that the stream sender was stopped by the receiver, e.g.
    /// due to a timeout.
    ///
    /// `#paused` means that at least one chunk could not be delivered and the
    /// stream sender is waiting for outstanding responses to come back before
    /// it can resume sending chunks. When it resumes it will start from the
    /// first item that did not arrive.
    ///
    /// `#busy` means that there are too many chunk concurrently in flight. The
    /// sender is waiting for outstanding responses to come back before sending
    /// any new chunks.
    ///
    /// `#ready` means that the stream sender is ready to send a chunk.

    public func status() : Status {
      if (shutdown) return #shutdown;
      if (stopped) return #stopped;
      if (paused) return #paused;
      if (concurrentChunks == settings_.maxConcurrentChunks) return #busy;
      return #ready;
    };

    /// Send chunk to the receiver.
    ///
    /// A return value `()` means that the stream sender was ready to send the
    /// chunk and attempted to send it. It does not mean that the chunk was
    /// delivered to the receiver.
    ///
    /// If the stream sender is not ready (shutdown, stopped, paused or busy) then the
    /// function throws immediately and does not attempt to send the chunk.
    public func sendChunk() : async* () {
      if (shutdown) throw Error.reject("Sender shut down");
      if (stopped) throw Error.reject("Stream stopped by receiver");
      if (paused) throw Error.reject("Stream is paused");
      if (concurrentChunks == settings_.maxConcurrentChunks) throw Error.reject("Stream is busy");

      let start = head;
      let elements = do {
        var end = head;
        let counter = counterCreator();
        let vec = Vector.new<S>();
        label fill loop {
          let ?item = buffer.getOpt(end) else break fill;
          let ?wrappedItem = counter.accept(item) else break fill;
          Vector.add(vec, wrappedItem);
          end += 1;
        };
        head := end;
        Vector.toArray(vec);
      };

      let size = elements.size();

      func shouldPing() : Bool {
        let ?arg = settings_.keepAlive else return false;
        (arg.1 () - lastChunkSent_) > arg.0;
      };

      if (size == 0 and not shouldPing()) {
        callbacks.onNoSend();
        return;
      };

      let chunkMessage = if (size > 0) #chunk elements else #ping;

      updateTime();
      concurrentChunks += 1;

      callbacks.onSend(chunkMessage);

      let res = try {
        await* sendFunc((start, chunkMessage));
      } catch (e) {
        // shutdown on permanent system errors
        switch (Error.code(e)) {
          case (#system_fatal or #destination_invalid or #future _) shutdown := true;
          case (_) {};
          // TODO: revisit #canister_reject after an IC protocol bug is fixed.
          // Currently, a stopped receiver responds with #canister_reject.
          // In the future it should be #canister_error.
          //
          // However, there is an advantage of handling #canister_reject and
          // #canister_error equally. It becomes easier to test because in the
          // moc interpreter we can simulate #canister_reject but not
          // #canister_error.
        };
        callbacks.onError(e);
        #error;
      };

      // plan changes
      var okTo = buffer.start();
      var retraceTo = head;
      var retraceMoreLater = false;
      var pausingNow = false;

      let end = start + size;

      switch (res) {
        case (#ok) okTo := end;
        case (#gap) { retraceTo := start; retraceMoreLater := true };
        case (#stop) { okTo := start; retraceTo := start };
        case (#error) if (start != end) retraceTo := start;
      };

      if (res != #ok) pausingNow := true;

      // protocol-level assertions (are covered in tests)
      func assert_(condition : Bool) = if (not condition) shutdown := true;
      assert_(okTo <= head);
      assert_(buffer.start() <= retraceTo);
      if (retraceMoreLater) assert_(buffer.start() < retraceTo);

      // internal assertions (not covered in tests, would represent an internal bugs if triggered)
      if (retraceTo < head) assert_(end <= head);
      if (not paused and pausingNow) assert_(retraceTo <= head);

      // apply changes
      buffer.deleteTo(okTo);
      head := Nat.min(head, retraceTo);
      if (pausingNow) paused := true;

      // unpause stream
      concurrentChunks -= 1;
      if (concurrentChunks == 0) paused := false;

      // stop stream
      if (res == #stop) stopped := true;
      
      callbacks.onResponse(res);
    };

    /// Restart the sender in case it's stopped after receiving `#stop` from `sendFunc`.
    public func restart() : async Bool {
      if (shutdown or paused) return false;
      let res = try {
        await* sendFunc((head, #restart));
      } catch (_) #error;
      if (res == #ok) {
        stopped := false;
        callbacks.onRestart();
      };
      return res == #ok;
    };

    /// Update max queue size.
    public func setMaxQueueSize(n : ?Nat) = settings_.maxQueueSize := n;

    /// Update max amount of concurrent outgoing requests.
    public func setMaxConcurrentChunks(n : Nat) = settings_.maxConcurrentChunks := n;

    /// Update max interval between stream calls.
    public func setKeepAlive(seconds : ?(Nat, () -> Int)) {
      settings_.keepAlive := seconds;
    };

    // Query functions for internal state
    // Should not be needed by normal users of the class

    // Last chunk sent time
    public func lastChunkSent() : Int = lastChunkSent_;
    
    /// Total amount of items, ever added to the stream sender.
    /// Equals the index which will be assigned to the next item.
    public func length() : Nat = buffer.end();

    // Internal queue size
    public func queueSize() : Nat = buffer.len();

    /// Amount of items, which were sent to receiver.
    public func sent() : Nat = head;

    /// Amount of items, successfully sent and acknowledged by receiver.
    public func received() : Nat = buffer.start();

    /// Get item from queue by index.
    public func get(index : Nat) : ?Q = buffer.getOpt(index);

    /// Returns flag is sender is ready.
    public func isReady() : Bool = status() == #ready;

    /// Returns flag is sender has shut down.
    public func isShutdown() : Bool = shutdown;

    /// Returns flag is receiver stopped the stream.
    public func isStopped() : Bool = stopped;

    /// Check busy status of sender.
    public func isBusy() : Bool = concurrentChunks == settings_.maxConcurrentChunks;

    /// Check busy level of sender, e.g. current amount of outgoing calls in flight.
    public func busyLevel() : Nat = concurrentChunks;

    /// Check paused status of sender.
    public func isPaused() : Bool = paused;
  };
};
