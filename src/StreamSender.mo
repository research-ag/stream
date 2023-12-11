import Debug "mo:base/Debug";
import Error "mo:base/Error";
import R "mo:base/Result";
import Time "mo:base/Time";
import Array "mo:base/Array";
import Option "mo:base/Option";
import Nat "mo:base/Nat";
import SWB "mo:swb";
import Vector "mo:vector";
import Types "types";

module {
  /// Usage:
  ///
  /// let sender = StreamSender<Int>(
  ///   123,
  ///   10,
  ///   10,
  ///   func (item) = 1,
  ///   5,
  ///   anotherCanister.appendStream,
  /// );
  /// sender.next(1);
  /// sender.next(2);
  /// .....
  /// sender.next(12);
  /// await* sender.sendChunk(); // will send (123, [1..10], 0) to `anotherCanister`
  /// await* sender.sendChunk(); // will send (123, [11..12], 10) to `anotherCanister`
  /// await* sender.sendChunk(); // will do nothing, stream clean

  // T = queue item type
  // S = stream item type
  public type Status = { #shutdown; #stopped; #paused; #busy; #ready };
  public type ControlMessage = Types.ControlMessage;
  public type ChunkMessage<T> = Types.ChunkMessage<T>;
  public let MAX_CONCURRENT_CHUNKS_DEFAULT = 5;

  public class StreamSender<T, S>(
    counterCreator : () -> { accept(item : T) : ?S },
    sendFunc : (x : Types.ChunkMessage<S>) -> async* Types.ControlMessage,
    settings : {
      maxQueueSize : ?Nat;
      maxConcurrentChunks : ?Nat;
      keepAliveSeconds : ?Nat;
    },
  ) {
    let buffer = SWB.SlidingWindowBuffer<T>();

    let settings_ = {
      var maxQueueSize = settings.maxQueueSize;
      var maxConcurrentChunks = settings.maxConcurrentChunks;
      var keepAliveSeconds = settings.keepAliveSeconds;
    };

    var stopped = false;
    var paused = false;
    var head : Nat = 0;
    var lastChunkSent = Time.now();
    var concurrentChunks = 0;
    var shutdown = false;

    func isQueueFull() : Bool = switch (settings_.maxQueueSize) {
      case (?max) buffer.len() >= max;
      case (null) false;
    };

    func assert_(condition : Bool) {
      if (not condition) shutdown := true;
    };

    /// add item to the stream
    public func push(item : T) : {
      #ok : Nat;
      #err : { #NoSpace };
    } {
      if (isQueueFull())
      #err(#NoSpace) else
      #ok(buffer.add(item));
    };

    /// Get the stream sender's status for inspection.
    ///
    /// The function is sychronous. It can be used (optionally) by the user of
    /// the class before calling the asynchronous function sendChunk.
    ///
    /// sendChunk will attempt to send a chunk if and only if the status is
    /// #ready.  sendChunk will throw if and only if the status is #stopped,
    /// #paused or #busy.
    ///
    /// #stopped means that the stream sender was stopped by the receiver, e.g.
    /// due to a timeout.
    ///
    /// #paused means that at least one chunk could not be delivered and the
    /// stream sender is waiting for outstanding responses to come back before
    /// it can resume sending chunks. When it resumes it will start from the
    /// first item that did not arrive.
    ///
    /// #busy means that there are too many chunk concurrently in flight. The
    /// sender is waiting for outstanding responses to come back before sending
    /// any new chunks.
    ///
    /// #ready n means that the stream sender is ready to send a chunk starting
    /// from position n.

    public func status() : Status {
      if (isShutdown()) return #shutdown;
      if (isStopped()) return #stopped;
      if (isPaused()) return #paused;
      if (isBusy()) return #busy;
      return #ready;
    };

    /// Send chunk to the receiver
    ///
    /// A return value () means that the stream sender was ready to send the
    /// chunk and attempted to send it. It does not mean that the chunk was
    /// delivered to the receiver.
    ///
    /// If the stream sender is not ready (stopped, paused or busy) then the
    /// function throws immediately and does not attempt to send the chunk.

    public func sendChunk() : async* () {
      switch (status()) {
        case (#shutdown) throw Error.reject("Sender shut down");
        case (#stopped) throw Error.reject("Stream stopped by receiver");
        case (#paused) throw Error.reject("Stream is paused");
        case (#busy) throw Error.reject("Stream is busy");
        case (#ready) {};
      };
      let start = head;
      let elements = do {
        var end = head;
        let counter = counterCreator();
        let vec = Vector.new<S>();
        label l loop {
          switch (buffer.getOpt(end)) {
            case (null) break l;
            case (?item) {
              switch (counter.accept(item)) {
                case (?x) Vector.add(vec, x);
                case (null) break l;
              };
              end += 1;
            };
          };
        };
        head := end;
        Vector.toArray(vec);
      };

      func shouldPing() : Bool {
        switch (settings_.keepAliveSeconds) {
          case (?i) lastChunkSent + i * 1_000_000_000 < Time.now();
          case (null) false;
        };
      };

      let ChunkMessage = if (elements.size() == 0) {
        if (not shouldPing()) return;
        (start, #ping);
      } else {
        (start, #chunk elements);
      };

      lastChunkSent := Time.now();
      concurrentChunks += 1;

      let end = start + elements.size();
      func receive() {
        concurrentChunks -= 1;
        if (concurrentChunks == 0) paused := false;
      };

      func assertions(res : { #ok; #gap; #stop; #error }) {
        // start
        switch (res) {
          case (#gap or #stop or #error) assert_(buffer.start() <= start);
          case (_) {};
        };
        // head
        switch (res) {
          case (#ok or #stop) assert_(end <= head);
          case (#gap) if (start < head) assert_(end <= head);
          case (_) {};
        };
        // state
        switch (res) {
          case (#ok) if (stopped) assert_(end <= buffer.start());
          case (#gap or #error) if (not (paused or stopped)) assert_(end <= head);
          case (_) {};
        };
      };

      let res = try {
        await* sendFunc(ChunkMessage);
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
        #error;
      };

      assertions(res);

      // advance the start pointer
      switch (res) {
        case (#ok) buffer.deleteTo(end);
        case (#stop) buffer.deleteTo(start);
        case (_) {};
      };

      // retreat the head pointer
      switch (res) {
        case (#gap or #stop or #error) head := Nat.min(head, start);
        case (_) {};
      };

      // transition state
      switch (res) {
        case (#stop) stopped := true;
        case (#gap or #error) paused := true;
        case (_) {};
      };
      receive();
    };

    /// total amount of items, ever added to the stream sender, also an index, which will be assigned to the next item
    public func length() : Nat = buffer.end();

    /// amount of items, which were sent to receiver
    public func sent() : Nat = head;

    /// amount of items, successfully sent and acknowledged by receiver
    public func received() : Nat = buffer.start();

    /// get item from queue by index
    public func get(index : Nat) : ?T = buffer.getOpt(index);

    /// check busy status of sender
    public func isBusy() : Bool {
      concurrentChunks == Option.get(
        settings_.maxConcurrentChunks,
        MAX_CONCURRENT_CHUNKS_DEFAULT,
      );
    };

    /// check busy level of sender, e.g. current amount of outgoing calls in flight
    public func busyLevel() : Nat = concurrentChunks;

    /// returns flag is sender has shut down
    public func isShutdown() : Bool = shutdown;

    /// returns flag is receiver stopped the stream
    public func isStopped() : Bool = stopped;

    /// check paused status of sender
    public func isPaused() : Bool = paused;

    /// update max queue size
    public func setMaxQueueSize(value : ?Nat) {
      settings_.maxQueueSize := value;
    };

    /// update max amount of concurrent outgoing requests
    public func setMaxConcurrentChunks(value : ?Nat) {
      settings_.maxConcurrentChunks := value;
    };

    /// update max interval between stream calls
    public func setKeepAlive(seconds : ?Nat) {
      settings_.keepAliveSeconds := seconds;
    };
  };
};
