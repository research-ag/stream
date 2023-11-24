import Debug "mo:base/Debug";
import Error "mo:base/Error";
import R "mo:base/Result";
import Time "mo:base/Time";
import Array "mo:base/Array";
import SWB "mo:swb";

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
  public class StreamSender<T, S>(
    // Do we need it?
    maxQueueSize : ?Nat,
    counter : { accept(item : T) : Bool; reset() : () },
    wrapItem : T -> S,
    maxConcurrentChunks : Nat,
    keepAliveSeconds : Nat,
    sendFunc : (items : [S], firstIndex : Nat) -> async* Bool,
    // TODO Did we already change this to async* in deployment?
  ) {
    var closed : Bool = false;
    let queue = object {
      public let buf = SWB.SlidingWindowBuffer<T>();
      var head_ : Nat = 0;
      public func head() : Nat = head_;

      func pop() : T {
        let ?x = buf.getOpt(head_) else Debug.trap("queue empty in pop()");
        head_ += 1;
        x;
      };

      public func rewind() { head_ := buf.start() };
      public func size() : Nat { buf.end() - head_ : Nat };
      public func chunk() : (Nat, Nat, [S]) {
        var start = head_;
        var end = start;
        counter.reset();
        label peekLoop while (true) {
          switch (buf.getOpt(end)) {
            case (null) break peekLoop;
            case (?item) {
              if (not counter.accept(item)) break peekLoop;
              end += 1;
            };
          };
        };
        let elements = Array.tabulate<S>(end - start, func(n) = wrapItem(pop()));
        (start, end, elements);
      };
    };

    /// total amount of items, ever added to the stream sender, also an index, which will be assigned to the next item
    public func length() : Nat = queue.buf.end();
    /// amount of items, which were sent to receiver
    public func sent() : Nat = queue.head();
    /// amount of items, successfully sent and acknowledged by receiver
    public func received() : Nat = queue.buf.start();

    /// get item from queue by index
    public func get(index : Nat) : ?T = queue.buf.getOpt(index);

    /// check busy status of sender
    public func isBusy() : Bool = window.isBusy();

    /// check busy level of sender, e.g. current amount of outgoing calls in flight
    public func busyLevel() : Nat = window.size();

    /// returns flag is receiver closed the stream
    public func isClosed() : Bool = closed;

    /// check paused status of sender
    public func isPaused() : Bool = window.hasError();

    /// update max amount of concurrent outgoing requests
    public func setMaxConcurrentChunks(value : Nat) = window.maxSize := value;

    var keepAliveInterval : Nat = keepAliveSeconds * 1_000_000_000;
    /// update max interval between stream calls
    public func setKeepAlive(seconds : Nat) {
      keepAliveInterval := seconds * 1_000_000_000;
    };

    /// add item to the stream
    public func add(item : T) : { #ok : Nat; #err : { #NoSpace } } {
      switch (maxQueueSize) {
        case (?max) if (queue.buf.len() >= max) {
          return #err(#NoSpace);
        };
        case (_) {};
      };
      #ok(queue.buf.add(item));
    };

    // The receive window of the sliding window protocol
    let window = object {
      public var maxSize = maxConcurrentChunks;
      public var lastChunkSent = Time.now();
      var size_ = 0;
      var error_ = false;

      func isClosed() : Bool { size_ == 0 }; // if window is closed (not stream)
      public func hasError() : Bool { error_ };
      public func isBusy() : Bool { size_ == maxSize };
      public func size() : Nat = size_;
      public func send() {
        lastChunkSent := Time.now();
        size_ += 1;
      };
      public func receive(msg : { #ok : Nat; #err }) {
        switch (msg) {
          case (#ok(pos)) queue.buf.deleteTo(pos);
          case (#err) error_ := true;
        };
        size_ -= 1;
        if (isClosed() and error_) {
          queue.rewind();
          error_ := false;
        };
      };
    };

    func nothingToSend(start : Nat, end : Nat) : Bool {
      // skip sending empty chunk unless keep-alive is due
      start == end and Time.now() < window.lastChunkSent + keepAliveInterval
    };

    /// send chunk to the receiver
    public func sendChunk() : async* () {
      if (closed) Debug.trap("Stream closed");
      if (window.isBusy()) Debug.trap("Stream sender is busy");
      if (window.hasError()) Debug.trap("Stream sender is paused");
      let (start, end, elements) = queue.chunk();
      if (nothingToSend(start, end)) return;
      window.send();
      try {
        switch (await* sendFunc(elements, start)) {
          case (true) window.receive(#ok(end));
          case (false) {
            // This response came from the first batch after the stream's
            // closing position, hence `start` is exactly the final length of
            // the stream.
            window.receive(#ok(start));
            closed := true;
          };
        };
      } catch (e) {
        window.receive(#err);
        throw e;
      };
    };
  };
};
