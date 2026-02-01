import StreamSender "../src/StreamSender";
import StreamReceiver "../src/StreamReceiver";
import Result "mo:core/Result";
import Debug "mo:core/Debug";
import Nat "mo:core/Nat";
import Error "mo:core/Error";
import Types "../src/internal/types";
import Base "sender.base";

type ControlMessage = Types.ControlMessage;
type ChunkMessage = Types.ChunkMessage<?Text>;

// Test maxQueueSize setting
do {
  func send(ch : ChunkMessage) : async* ControlMessage { #ok };

  let sender = StreamSender.StreamSender<Text, ?Text>(send, Base.create(10));

  sender.setMaxQueueSize(?3);
  assert sender.maxQueueSize() == ?3;

  Result.assertOk(sender.push("a"));
  Result.assertOk(sender.push("b"));
  Result.assertOk(sender.push("c"));

  // Should fail due to queue size limit
  let result = sender.push("d");
  assert result == #err(#NoSpace);
  assert sender.queueSize() == 3;
};

// Test maxStreamLength setting
do {
  func send(ch : ChunkMessage) : async* ControlMessage { #ok };

  let sender = StreamSender.StreamSender<Text, ?Text>(send, Base.create(10));

  sender.setMaxStreamLength(?5);
  assert sender.maxStreamLength() == ?5;

  Result.assertOk(sender.push("a"));
  Result.assertOk(sender.push("b"));
  Result.assertOk(sender.push("c"));
  Result.assertOk(sender.push("d"));
  Result.assertOk(sender.push("e"));

  // Should fail due to stream length limit
  let result = sender.push("f");
  assert result == #err(#LimitExceeded);
  assert sender.length() == 5;
};

// Test windowSize setting
do {
  var callCount = 0;
  func send(ch : ChunkMessage) : async* ControlMessage {
    callCount += 1;
    #ok;
  };

  let sender = StreamSender.StreamSender<Text, ?Text>(send, Base.create(1));
  sender.setWindowSize(2);
  assert sender.windowSize() == 2;

  Result.assertOk(sender.push("a"));
  Result.assertOk(sender.push("b"));
  Result.assertOk(sender.push("c"));

  await* sender.sendChunk();
  await* sender.sendChunk();

  // Should be busy with 2 concurrent chunks
  assert sender.status() == #busy;
  assert sender.busyLevel() == 2;
};

// Test keepAlive setting
do {
  var time = 0;
  var pingSent = false;
  func send(ch : ChunkMessage) : async* ControlMessage {
    switch (ch.1) {
      case (#ping) pingSent := true;
      case (_) {};
    };
    #ok;
  };

  let sender = StreamSender.StreamSender<Text, ?Text>(send, Base.create(10));
  sender.setKeepAlive(?(5, func() = time));
  assert sender.keepAliveTime() == ?5;

  Result.assertOk(sender.push("a"));
  await* sender.sendChunk();
  assert not pingSent;

  time := 6;
  // Should send ping due to keepAlive timeout
  await* sender.sendChunk();
  assert pingSent;
};

// Test share/unshare functionality
do {
  func send(ch : ChunkMessage) : async* ControlMessage { #ok };

  let sender1 = StreamSender.StreamSender<Text, ?Text>(send, Base.create(10));
  Result.assertOk(sender1.push("a"));
  Result.assertOk(sender1.push("b"));
  await* sender1.sendChunk();

  let data = sender1.share();

  let sender2 = StreamSender.StreamSender<Text, ?Text>(send, Base.create(10));
  sender2.unshare(data);

  assert sender2.length() == 2;
  assert sender2.queueSize() == 1;
};

// Test status transitions
do {
  func send(ch : ChunkMessage) : async* ControlMessage { #ok };

  let sender = StreamSender.StreamSender<Text, ?Text>(send, Base.create(1));

  // Initially ready
  assert sender.status() == #ready;
  assert sender.isReady();
  assert not sender.isStopped();
  assert not sender.isShutdown();
  assert not sender.isPaused();
};

// Test shutdown on #gap response
do {
  func send(ch : ChunkMessage) : async* ControlMessage { #gap };

  let sender = StreamSender.StreamSender<Text, ?Text>(send, Base.create(10));
  Result.assertOk(sender.push("a"));

  await* sender.sendChunk();

  assert sender.status() == #shutdown;
  assert sender.isShutdown();
};

// Test stopped status
do {
  func send(ch : ChunkMessage) : async* ControlMessage { #stop 0 };

  let sender = StreamSender.StreamSender<Text, ?Text>(send, Base.create(10));
  Result.assertOk(sender.push("a"));

  await* sender.sendChunk();

  assert sender.status() == #stopped;
  assert sender.isStopped();
};

// Test partial stop
do {
  func send(ch : ChunkMessage) : async* ControlMessage { #stop 1 };

  let sender = StreamSender.StreamSender<Text, ?Text>(send, Base.create(10));
  Result.assertOk(sender.push("a"));
  Result.assertOk(sender.push("b"));

  await* sender.sendChunk();

  assert sender.status() == #stopped;
  assert sender.received() == 1;
  assert sender.length() == 2;
};

// Test callbacks: onSend
do {
  var sendCallbackCalled = false;
  var chunkSizeReceived = 0;

  func send(ch : ChunkMessage) : async* ControlMessage { #ok };

  let sender = StreamSender.StreamSender<Text, ?Text>(send, Base.create(10));

  sender.callbacks.onSend := func(info) {
    sendCallbackCalled := true;
    switch (info) {
      case (#chunk size) chunkSizeReceived := size;
      case (#ping) {};
    };
  };

  Result.assertOk(sender.push("a"));
  Result.assertOk(sender.push("b"));
  await* sender.sendChunk();

  assert sendCallbackCalled;
  assert chunkSizeReceived == 2;
};

// Test callbacks: onNoSend
do {
  var noSendCalled = false;

  func send(ch : ChunkMessage) : async* ControlMessage { #ok };

  let sender = StreamSender.StreamSender<Text, ?Text>(send, Base.create(10));

  sender.callbacks.onNoSend := func() {
    noSendCalled := true;
  };

  // No items to send
  await* sender.sendChunk();

  assert noSendCalled;
};

// Test callbacks: onResponse
do {
  var responseCalled = false;
  var lastResponse : ?(ControlMessage or { #error }) = null;

  func send(ch : ChunkMessage) : async* ControlMessage { #ok };

  let sender = StreamSender.StreamSender<Text, ?Text>(send, Base.create(10));

  sender.callbacks.onResponse := func(res) {
    responseCalled := true;
    lastResponse := ?res;
  };

  Result.assertOk(sender.push("a"));
  await* sender.sendChunk();

  assert responseCalled;
  assert lastResponse == ? #ok;
};

// Test callbacks: onRestart
do {
  var restartCalled = false;
  var stopFirst = true;

  func send(ch : ChunkMessage) : async* ControlMessage {
    if (stopFirst) {
      switch (ch.1) {
        case (#restart) #ok;
        case (_) #stop 0;
      };
    } else #ok;
  };

  let sender = StreamSender.StreamSender<Text, ?Text>(send, Base.create(10));

  sender.callbacks.onRestart := func() {
    restartCalled := true;
  };

  Result.assertOk(sender.push("a"));
  await* sender.sendChunk();
  assert sender.isStopped();

  stopFirst := false;
  assert (await sender.restart());
  assert restartCalled;
};

// Test callbacks: onError
do {
  var errorCalled = false;
  var errorCode : ?Error.ErrorCode = null;

  func send(ch : ChunkMessage) : async* ControlMessage {
    throw Error.reject("test error");
  };

  let sender = StreamSender.StreamSender<Text, ?Text>(send, Base.create(10));

  sender.callbacks.onError := func(err) {
    errorCalled := true;
    errorCode := ?Error.code(err);
  };

  Result.assertOk(sender.push("a"));
  await* sender.sendChunk();

  assert errorCalled;
};

// Test get() function
do {
  func send(ch : ChunkMessage) : async* ControlMessage { #ok };

  let sender = StreamSender.StreamSender<Text, ?Text>(send, Base.create(10));

  Result.assertOk(sender.push("first"));
  Result.assertOk(sender.push("second"));
  Result.assertOk(sender.push("third"));

  assert sender.get(0) == ?"first";
  assert sender.get(1) == ?"second";
  assert sender.get(2) == ?"third";
  assert sender.get(3) == null;
};

// Test sent() vs received() vs length()
do {
  func send(ch : ChunkMessage) : async* ControlMessage { #ok };

  let sender = StreamSender.StreamSender<Text, ?Text>(send, Base.create(10));

  Result.assertOk(sender.push("a"));
  Result.assertOk(sender.push("b"));
  Result.assertOk(sender.push("c"));

  assert sender.length() == 3;
  assert sender.sent() == 0;
  assert sender.received() == 0;

  await* sender.sendChunk();

  assert sender.length() == 3;
  assert sender.sent() == 2;
  assert sender.received() == 2;

  await* sender.sendChunk();

  assert sender.length() == 3;
  assert sender.sent() == 3;
  assert sender.received() == 3;
};

// Test throw behavior on different states
do {
  func send(ch : ChunkMessage) : async* ControlMessage { #stop 0 };

  let sender = StreamSender.StreamSender<Text, ?Text>(send, Base.create(10));
  Result.assertOk(sender.push("a"));

  await* sender.sendChunk();
  assert sender.status() == #stopped;

  // Should throw when trying to send while stopped
  let threw = try {
    await* sender.sendChunk();
    false;
  } catch (e) {
    true;
  };
  assert threw;
};

// Test busyLevel() function
do {
  func send(ch : ChunkMessage) : async* ControlMessage { #ok };

  let sender = StreamSender.StreamSender<Text, ?Text>(send, Base.create(1));
  sender.setWindowSize(3);

  Result.assertOk(sender.push("a"));
  Result.assertOk(sender.push("b"));

  assert sender.busyLevel() == 0;

  await* sender.sendChunk();
  assert sender.busyLevel() == 0;
};

// Test queue rotation after receiving acknowledgment
do {
  func send(ch : ChunkMessage) : async* ControlMessage { #ok };

  let sender = StreamSender.StreamSender<Text, ?Text>(send, Base.create(10));

  Result.assertOk(sender.push("a"));
  Result.assertOk(sender.push("b"));
  Result.assertOk(sender.push("c"));

  assert sender.queueSize() == 3;
  await* sender.sendChunk();
  assert sender.queueSize() == 1; // First 2 items removed from queue

  await* sender.sendChunk();
  assert sender.queueSize() == 0; // Last item removed
};

// Test restart() function returns false on shutdown
do {
  func send(ch : ChunkMessage) : async* ControlMessage { #gap };

  let sender = StreamSender.StreamSender<Text, ?Text>(send, Base.create(10));
  Result.assertOk(sender.push("a"));

  await* sender.sendChunk();
  assert sender.isShutdown();

  assert not (await sender.restart());
};

// Test counter that wraps items
do {
  func send(ch : ChunkMessage) : async* ControlMessage {
    let (_, payload) = ch;
    switch (payload) {
      case (#chunk items) {
        // Verify wrapped items
        assert items[0] == ?"short";
        assert items[1] == null; // Too long, wrapped to null
      };
      case (_) {};
    };
    #ok;
  };

  let sender = StreamSender.StreamSender<Text, ?Text>(send, Base.create(10));

  Result.assertOk(sender.push("short"));
  Result.assertOk(sender.push("this is a very long string"));

  await* sender.sendChunk();
};

// Test empty queue behavior
do {
  var sendCalled = false;
  func send(ch : ChunkMessage) : async* ControlMessage {
    sendCalled := true;
    #ok;
  };

  let sender = StreamSender.StreamSender<Text, ?Text>(send, Base.create(10));

  // No items in queue, no keepAlive set
  await* sender.sendChunk();
  assert not sendCalled; // Should not send anything
};

// Test ping message due to keepAlive
do {
  var time = 0;
  var pingReceived = false;

  func send(ch : ChunkMessage) : async* ControlMessage {
    switch (ch.1) {
      case (#ping) pingReceived := true;
      case (_) {};
    };
    #ok;
  };

  let sender = StreamSender.StreamSender<Text, ?Text>(send, Base.create(10));
  sender.setKeepAlive(?(5, func() = time));

  Result.assertOk(sender.push("a"));
  await* sender.sendChunk(); // Sends "a"
  assert not pingReceived;

  time := 10;
  // Empty queue but keepAlive timeout exceeded
  await* sender.sendChunk(); // Should send ping
  assert pingReceived;
};

// Test lastChunkSent() function
do {
  var time = 0;
  func send(ch : ChunkMessage) : async* ControlMessage { #ok };

  let sender = StreamSender.StreamSender<Text, ?Text>(send, Base.create(10));
  sender.setKeepAlive(?(5, func() = time));

  assert sender.lastChunkSent() == 0;

  time := 10;
  Result.assertOk(sender.push("a"));
  await* sender.sendChunk();

  assert sender.lastChunkSent() == 10;
};

Debug.print("All advanced sender tests passed");