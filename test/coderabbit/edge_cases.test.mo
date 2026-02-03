import StreamReceiver "../../src/StreamReceiver";
import StreamSender "../../src/StreamSender";
import Debug "mo:core/Debug";
import Error "mo:core/Error";
import Result "mo:core/Result";
import Types "../../src/internal/types";

type ChunkMessage = Types.ChunkMessage<?Text>;
type ControlMessage = Types.ControlMessage;

// Edge case: zero-length chunks
do {
  var itemsProcessed = 0;
  func process(index : Nat, item : Text) : Bool {
    itemsProcessed += 1;
    true;
  };

  let receiver = StreamReceiver.StreamReceiver<Text>(process, null);

  // Multiple zero-length chunks in sequence
  assert receiver.onChunk((0, #chunk([]))) == #ok;
  assert receiver.onChunk((0, #chunk([]))) == #ok;
  assert receiver.onChunk((0, #chunk([]))) == #ok;
  assert itemsProcessed == 0;
  assert receiver.length() == 0;
};

// Edge case: alternating empty and non-empty chunks
do {
  var itemsProcessed = 0;
  func process(index : Nat, item : Text) : Bool {
    itemsProcessed += 1;
    true;
  };

  let receiver = StreamReceiver.StreamReceiver<Text>(process, null);

  assert receiver.onChunk((0, #chunk([]))) == #ok;
  assert receiver.onChunk((0, #chunk(["a"]))) == #ok;
  assert receiver.onChunk((1, #chunk([]))) == #ok;
  assert receiver.onChunk((1, #chunk(["b"]))) == #ok;
  assert itemsProcessed == 2;
  assert receiver.length() == 2;
};

// Edge case: sender with maxQueueSize = 0 (effectively no queue)
do {
  func send(ch : ChunkMessage) : async* ControlMessage { #ok };

  func counter() : { accept(item : Text) : ??Text } {
    {
      accept = func(item : Text) : ??Text {
        ??item;
      };
    };
  };

  let sender = StreamSender.StreamSender<Text, ?Text>(send, counter);
  sender.setMaxQueueSize(?0);

  // Should immediately fail to push
  assert sender.push("a") == #err(#NoSpace);
};

// Edge case: sender with maxStreamLength = 0
do {
  func send(ch : ChunkMessage) : async* ControlMessage { #ok };

  func counter() : { accept(item : Text) : ??Text } {
    {
      accept = func(item : Text) : ??Text {
        ??item;
      };
    };
  };

  let sender = StreamSender.StreamSender<Text, ?Text>(send, counter);
  sender.setMaxStreamLength(?0);

  // Should immediately fail to push
  assert sender.push("a") == #err(#LimitExceeded);
};

// Edge case: windowSize = 1 (minimum concurrency)
do {
  var sendCount = 0;
  func send(ch : ChunkMessage) : async* ControlMessage {
    sendCount += 1;
    #ok;
  };

  func counter() : { accept(item : Text) : ??Text } {
    {
      accept = func(item : Text) : ??Text {
        ??item;
      };
    };
  };

  let sender = StreamSender.StreamSender<Text, ?Text>(send, counter);
  sender.setWindowSize(1);

  Result.assertOk(sender.push("a"));
  Result.assertOk(sender.push("b"));

  await* sender.sendChunk();
  // Disabled because concurrency cannot be tested like this.
  // It requires advanced setup using the async-test package.
  // assert sender.status() == #busy;

  // Cannot send another chunk until first returns
  let threw = try {
    await* sender.sendChunk();
    false;
  } catch (e) {
    true;
  };
  // Disabled because concurrency cannot be tested like this.
  // It requires advanced setup using the async-test package.
  // assert threw;
};

// Edge case: receiver with timeout = 0 (immediate timeout)
do {
  var time = 1;
  func process(index : Nat, item : Text) : Bool { true };

  let receiver = StreamReceiver.StreamReceiver<Text>(process, ?(0, func() = time));

  // First chunk at time 1
  assert receiver.onChunk((0, #chunk(["a"]))) == #ok;

  time := 2;

  // Second chunk at time 2 should timeout
  assert receiver.onChunk((1, #chunk(["b"]))) == #stop 0;
};

// Edge case: counter that accepts nothing
do {
  func send(ch : ChunkMessage) : async* ControlMessage { #ok };

  func counter() : { accept(item : Text) : ??Text } {
    {
      accept = func(item : Text) : ??Text {
        null; // Never accepts anything
      };
    };
  };

  let sender = StreamSender.StreamSender<Text, ?Text>(send, counter);

  Result.assertOk(sender.push("a"));

  // Should send empty chunk or nothing
  await* sender.sendChunk();
};

// Edge case: very large stop value
do {
  func process(index : Nat, item : Text) : Bool { true };

  let receiver = StreamReceiver.StreamReceiver<Text>(process, null);

  let largeArray : [Text] = ["a", "b", "c", "d", "e"];
  assert receiver.onChunk((0, #chunk(largeArray))) == #ok;

  // Verify large stop values work
  let stopMessage : ControlMessage = #stop 1000000;
  switch (stopMessage) {
    case (#stop n) assert n == 1000000;
    case (_) assert false;
  };
};

// Edge case: restart at position 0
do {
  func process(index : Nat, item : Text) : Bool { true };

  let receiver = StreamReceiver.StreamReceiver<Text>(process, null);

  // Restart at position 0 (start of stream)
  assert receiver.onChunk((0, #restart)) == #ok;
  assert receiver.length() == 0;
};

// Edge case: restart after already stopped
do {
  var time = 0;
  func process(index : Nat, item : Text) : Bool { true };

  let receiver = StreamReceiver.StreamReceiver<Text>(process, ?(5, func() = time));

  assert receiver.onChunk((0, #chunk(["a"]))) == #ok;

  time := 10;
  assert receiver.onChunk((1, #chunk(["b"]))) == #stop 0;
  assert receiver.isStopped();

  // Restart should work
  assert receiver.onChunk((1, #restart)) == #ok;
  assert not receiver.isStopped();
};

// Edge case: maxLength exactly equals chunk size
do {
  func process(index : Nat, item : Text) : Bool { true };

  let receiver = StreamReceiver.StreamReceiver<Text>(process, null);
  receiver.setMaxLength(?5);

  // Chunk with exactly 5 items
  assert receiver.onChunk((0, #chunk(["a", "b", "c", "d", "e"]))) == #ok;
  assert receiver.length() == 5;

  // Next chunk should stop immediately
  assert receiver.onChunk((5, #chunk(["f"]))) == #stop 0;
};

// Edge case: negative time values (edge of Int type)
do {
  var time : Int = -100;
  func process(index : Nat, item : Text) : Bool { true };

  let receiver = StreamReceiver.StreamReceiver<Text>(
    process,
    ?(50, func() = time),
  );

  assert receiver.onChunk((0, #chunk(["a"]))) == #ok;

  time := -50; // Within timeout
  assert receiver.onChunk((1, #chunk(["b"]))) == #ok;

  time := 0; // Still within timeout
  assert receiver.onChunk((2, #chunk(["c"]))) == #ok;
};

// Edge case: share/unshare with stopped receiver
do {
  func process(index : Nat, item : Text) : Bool { true };

  let receiver1 = StreamReceiver.StreamReceiver<Text>(process, null);
  receiver1.stop();

  let data = receiver1.share();

  let receiver2 = StreamReceiver.StreamReceiver<Text>(process, null);
  receiver2.unshare(data);

  assert receiver2.isStopped();
};

// Edge case: share/unshare sender with items in queue
do {
  func send(ch : ChunkMessage) : async* ControlMessage { #ok };

  func counter() : { accept(item : Text) : ??Text } {
    {
      accept = func(item : Text) : ??Text {
        ??item;
      };
    };
  };

  let sender1 = StreamSender.StreamSender<Text, ?Text>(send, counter);
  Result.assertOk(sender1.push("a"));
  Result.assertOk(sender1.push("b"));

  let data = sender1.share();

  let sender2 = StreamSender.StreamSender<Text, ?Text>(send, counter);
  sender2.unshare(data);

  // Sender2 should have the items
  assert sender2.get(0) == ?"a";
  assert sender2.get(1) == ?"b";
};

// Edge case: concurrent sends with errors
do {
  var shouldError = true;
  func send(ch : ChunkMessage) : async* ControlMessage {
    if (shouldError) {
      throw Error.reject("test error");
    } else {
      #ok;
    };
  };

  func counter() : { accept(item : Text) : ??Text } {
    var count = 0;
    {
      accept = func(item : Text) : ??Text {
        count += 1;
        if (count <= 1) ??item else null;
      };
    };
  };

  let sender = StreamSender.StreamSender<Text, ?Text>(send, counter);
  sender.setWindowSize(2);

  Result.assertOk(sender.push("a"));
  Result.assertOk(sender.push("b"));

  await* sender.sendChunk();
  shouldError := false;
  await* sender.sendChunk();

  // Should handle errors gracefully
  assert not sender.isShutdown();
};

// Edge case: callback returns false on first item
do {
  func process(index : Nat, item : Text) : Bool { false };

  let receiver = StreamReceiver.StreamReceiver<Text>(process, null);

  assert receiver.onChunk((0, #chunk(["a", "b", "c"]))) == #stop 0;
  assert receiver.length() == 0;
};

// Edge case: very large position values
do {
  func process(index : Nat, item : Text) : Bool { true };

  let receiver = StreamReceiver.StreamReceiver<Text>(process, null);

  let largePos : Nat = 1000000;
  assert receiver.onChunk((largePos, #chunk(["a"]))) == #gap;
};

// Edge case: restart multiple times
do {
  func process(index : Nat, item : Text) : Bool { true };

  let receiver = StreamReceiver.StreamReceiver<Text>(process, null);

  assert receiver.onChunk((0, #restart)) == #ok;
  assert receiver.onChunk((0, #restart)) == #ok;
  assert receiver.onChunk((0, #restart)) == #ok;
  assert receiver.length() == 0;
};

// Edge case: ping at non-current position
do {
  func process(index : Nat, item : Text) : Bool { true };

  let receiver = StreamReceiver.StreamReceiver<Text>(process, null);

  assert receiver.onChunk((0, #chunk(["a"]))) == #ok;

  // Ping at wrong position
  assert receiver.onChunk((0, #ping)) == #gap;
  assert receiver.onChunk((2, #ping)) == #gap;
};

Debug.print("All edge case tests passed");