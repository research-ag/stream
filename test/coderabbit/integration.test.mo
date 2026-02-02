import StreamReceiver "../../src/StreamReceiver";
import StreamSender "../../src/StreamSender";
import List "mo:core/List";
import Debug "mo:core/Debug";
import Nat "mo:core/Nat";
import Result "mo:core/Result";
import Types "../../src/internal/types";

type ChunkMessage = Types.ChunkMessage<?Text>;
type ControlMessage = Types.ControlMessage;

// Integration test: sender and receiver working together with wrapping
do {
  let MAX_LENGTH = 10;

  // Receiver setup
  let received = List.empty<?Text>();
  func processItem(i : Nat, item : ?Text) : Bool {
    received.add(item);
    true;
  };

  let receiver = StreamReceiver.StreamReceiver<?Text>(processItem, null);

  // Counter for sender
  func counter() : { accept(item : Text) : ??Text } {
    var sum = 0;
    {
      accept = func(item : Text) : ??Text {
        let (wrapped_item, wrapped_size) = if (item.size() <= MAX_LENGTH) {
          (?item, item.size());
        } else {
          (null, 0);
        };
        sum += wrapped_size;
        if (sum <= MAX_LENGTH) ?wrapped_item else null;
      };
    };
  };

  // Sender setup
  func send(ch : ChunkMessage) : async* ControlMessage { receiver.onChunk(ch) };
  let sender = StreamSender.StreamSender<Text, ?Text>(send, counter);

  // Push various items
  Result.assertOk(sender.push("short"));
  Result.assertOk(sender.push("this is a very very long text"));
  Result.assertOk(sender.push("mid"));
  Result.assertOk(sender.push("text"));

  // Send all chunks
  var iterations = 0;
  let maxIterations = 100;
  while (sender.received() < sender.length() and iterations < maxIterations) {
    await* sender.sendChunk();
    iterations += 1;
  };

  assert iterations < maxIterations;
  assert receiver.length() == 4;

  let receivedArr = List.toArray(received);
  assert receivedArr[0] == ?"short";
  assert receivedArr[1] == null; // Long text wrapped to null
  assert receivedArr[2] == ?"mid";
  assert receivedArr[3] == ?"text";
};

// Integration test: receiver timeout causes sender to stop
do {
  var time = 0;
  let TIMEOUT = 100;

  let received = List.empty<?Text>();
  func processItem(i : Nat, item : ?Text) : Bool {
    received.add(item);
    true;
  };

  let receiver = StreamReceiver.StreamReceiver<?Text>(
    processItem,
    ?(TIMEOUT, func() = time),
  );

  func counter() : { accept(item : Text) : ??Text } {
    var sum = 0;
    {
      accept = func(item : Text) : ??Text {
        if (item.size() <= 5) {
          sum += item.size();
          if (sum <= 5) ??item else null;
        } else ?null;
      };
    };
  };

  func send(ch : ChunkMessage) : async* ControlMessage { receiver.onChunk(ch) };
  let sender = StreamSender.StreamSender<Text, ?Text>(send, counter);

  Result.assertOk(sender.push("a"));
  Result.assertOk(sender.push("b"));

  await* sender.sendChunk();
  assert sender.received() == 2;
  assert not sender.isStopped();

  // Exceed timeout
  time := TIMEOUT + 1;

  Result.assertOk(sender.push("c"));
  await* sender.sendChunk();

  // Receiver should stop sender
  assert sender.isStopped();
  assert sender.received() == 2; // Only first 2 received
};

// Integration test: multiple concurrent chunks
do {
  let received = List.empty<?Text>();
  func processItem(i : Nat, item : ?Text) : Bool {
    received.add(item);
    true;
  };

  let receiver = StreamReceiver.StreamReceiver<?Text>(processItem, null);

  func counter() : { accept(item : Text) : ??Text } {
    var count = 0;
    {
      accept = func(item : Text) : ??Text {
        count += 1;
        if (count <= 1) ??item else null;
      };
    };
  };

  func send(ch : ChunkMessage) : async* ControlMessage { receiver.onChunk(ch) };
  let sender = StreamSender.StreamSender<Text, ?Text>(send, counter);
  sender.setWindowSize(3);

  // Push items
  for (i in Nat.range(0, 5)) {
    Result.assertOk(sender.push("item" # Nat.toText(i)));
  };

  // Send multiple chunks concurrently
  await* sender.sendChunk();
  await* sender.sendChunk();
  await* sender.sendChunk();

  assert sender.busyLevel() == 0; // All should have returned
  assert receiver.length() == 3;
};

// Integration test: receiver rejects items mid-chunk
do {
  var acceptCount = 2;

  func processItem(i : Nat, item : ?Text) : Bool {
    if (acceptCount > 0) {
      acceptCount -= 1;
      true;
    } else {
      false;
    };
  };

  let receiver = StreamReceiver.StreamReceiver<?Text>(processItem, null);

  func counter() : { accept(item : Text) : ??Text } {
    {
      accept = func(item : Text) : ??Text {
        ??item;
      };
    };
  };

  func send(ch : ChunkMessage) : async* ControlMessage { receiver.onChunk(ch) };
  let sender = StreamSender.StreamSender<Text, ?Text>(send, counter);

  Result.assertOk(sender.push("a"));
  Result.assertOk(sender.push("b"));
  Result.assertOk(sender.push("c"));
  Result.assertOk(sender.push("d"));

  await* sender.sendChunk();

  // Sender should be stopped because receiver rejected items
  assert sender.isStopped();
  assert receiver.length() == 2;
};

// Integration test: sender restart after stop
do {
  var shouldStop = true;

  let received = List.empty<?Text>();
  func processItem(i : Nat, item : ?Text) : Bool {
    received.add(item);
    true;
  };

  let receiver = StreamReceiver.StreamReceiver<?Text>(processItem, null);

  func counter() : { accept(item : Text) : ??Text } {
    {
      accept = func(item : Text) : ??Text {
        ??item;
      };
    };
  };

  func send(ch : ChunkMessage) : async* ControlMessage {
    if (shouldStop) {
      switch (ch.1) {
        case (#restart) receiver.onChunk(ch);
        case (_) #stop 0;
      };
    } else {
      receiver.onChunk(ch);
    };
  };

  let sender = StreamSender.StreamSender<Text, ?Text>(send, counter);

  Result.assertOk(sender.push("a"));
  Result.assertOk(sender.push("b"));

  await* sender.sendChunk();
  assert sender.isStopped();
  assert receiver.length() == 0;

  // Restart
  shouldStop := false;
  assert (await sender.restart());
  assert not sender.isStopped();
  assert not receiver.isStopped();

  await* sender.sendChunk();
  assert receiver.length() == 2;
};

// Integration test: maxStreamLength and maxQueueSize interaction
do {
  let received = List.empty<?Text>();
  func processItem(i : Nat, item : ?Text) : Bool {
    received.add(item);
    true;
  };

  let receiver = StreamReceiver.StreamReceiver<?Text>(processItem, null);

  func counter() : { accept(item : Text) : ??Text } {
    {
      accept = func(item : Text) : ??Text {
        ??item;
      };
    };
  };

  func send(ch : ChunkMessage) : async* ControlMessage { receiver.onChunk(ch) };
  let sender = StreamSender.StreamSender<Text, ?Text>(send, counter);

  sender.setMaxQueueSize(?2);
  sender.setMaxStreamLength(?5);

  Result.assertOk(sender.push("a"));
  Result.assertOk(sender.push("b"));
  assert sender.push("c") == #err(#NoSpace);

  await* sender.sendChunk();

  Result.assertOk(sender.push("c"));
  Result.assertOk(sender.push("d"));

  await* sender.sendChunk();

  Result.assertOk(sender.push("e"));
  assert sender.push("f") == #err(#LimitExceeded);

  await* sender.sendChunk();

  assert sender.received() == 5;
  assert receiver.length() == 5;
};

// Integration test: receiver maxLength stops sender
do {
  let MAX_RECEIVER_LENGTH = 3;

  let received = List.empty<?Text>();
  func processItem(i : Nat, item : ?Text) : Bool {
    received.add(item);
    true;
  };

  let receiver = StreamReceiver.StreamReceiver<?Text>(processItem, null);
  receiver.setMaxLength(?MAX_RECEIVER_LENGTH);

  func counter() : { accept(item : Text) : ??Text } {
    {
      accept = func(item : Text) : ??Text {
        ??item;
      };
    };
  };

  func send(ch : ChunkMessage) : async* ControlMessage { receiver.onChunk(ch) };
  let sender = StreamSender.StreamSender<Text, ?Text>(send, counter);

  Result.assertOk(sender.push("a"));
  Result.assertOk(sender.push("b"));
  Result.assertOk(sender.push("c"));
  Result.assertOk(sender.push("d"));

  await* sender.sendChunk();
  assert sender.isStopped();
  assert receiver.length() == MAX_RECEIVER_LENGTH;
  assert sender.received() == MAX_RECEIVER_LENGTH;
};

// Integration test: keepAlive ping mechanism
do {
  var time = 0;
  var pingReceived = false;

  let received = List.empty<?Text>();
  func processItem(i : Nat, item : ?Text) : Bool {
    received.add(item);
    true;
  };

  let receiver = StreamReceiver.StreamReceiver<?Text>(processItem, null);

  func counter() : { accept(item : Text) : ??Text } {
    {
      accept = func(item : Text) : ??Text {
        ??item;
      };
    };
  };

  func send(ch : ChunkMessage) : async* ControlMessage {
    switch (ch.1) {
      case (#ping) pingReceived := true;
      case (_) {};
    };
    receiver.onChunk(ch);
  };

  let sender = StreamSender.StreamSender<Text, ?Text>(send, counter);
  sender.setKeepAlive(?(10, func() = time));

  Result.assertOk(sender.push("a"));
  await* sender.sendChunk();
  assert not pingReceived;

  time := 20;
  await* sender.sendChunk(); // Should send ping
  assert pingReceived;
};

Debug.print("All integration tests passed");