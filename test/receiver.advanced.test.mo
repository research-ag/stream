import StreamReceiver "../src/StreamReceiver";
import Debug "mo:core/Debug";
import Nat "mo:core/Nat";

// Test receiver with maxLength set
do {
  var size = 0;
  var itemsProcessed = 0;
  func process(index : Nat, item : Text) : Bool {
    itemsProcessed += 1;
    size += 1;
    size == index + 1;
  };

  let receiver = StreamReceiver.StreamReceiver<Text>(process, null);
  receiver.setMaxLength(?5);

  // Should accept items up to maxLength
  assert receiver.onChunk((0, #chunk(["a", "b", "c"]))) == #ok;
  assert itemsProcessed == 3;
  assert receiver.length() == 3;

  // Should stop when maxLength is reached
  assert receiver.onChunk((3, #chunk(["d", "e", "f"]))) == #stop 2;
  assert itemsProcessed == 5;
  assert receiver.length() == 5;

  // Further chunks should be rejected with #stop
  assert receiver.onChunk((5, #chunk(["g"]))) == #stop 0;
  assert itemsProcessed == 5;
  assert receiver.length() == 5;
};

// Test receiver that rejects items via itemCallback
do {
  var acceptCount = 3;
  func process(index : Nat, item : Text) : Bool {
    if (acceptCount > 0) {
      acceptCount -= 1;
      true;
    } else {
      false;
    };
  };

  let receiver = StreamReceiver.StreamReceiver<Text>(process, null);

  // Should stop when callback returns false
  assert receiver.onChunk((0, #chunk(["a", "b", "c", "d", "e"]))) == #stop 3;
  assert receiver.length() == 3;
};

// Test share/unshare functionality
do {
  var size = 0;
  func process(index : Nat, item : Text) : Bool {
    size += 1;
    true;
  };

  let receiver1 = StreamReceiver.StreamReceiver<Text>(process, null);
  assert receiver1.onChunk((0, #chunk(["a", "b"]))) == #ok;
  assert receiver1.length() == 2;

  let data = receiver1.share();

  let receiver2 = StreamReceiver.StreamReceiver<Text>(process, null);
  receiver2.unshare(data);

  // Receiver2 should continue from where receiver1 left off
  assert receiver2.length() == 2;
  assert receiver2.onChunk((2, #chunk(["c"]))) == #ok;
  assert receiver2.length() == 3;

  // Wrong position should cause gap
  assert receiver2.onChunk((0, #chunk(["x"]))) == #gap;
};

// Test stop() function
do {
  func process(index : Nat, item : Text) : Bool { true };

  let receiver = StreamReceiver.StreamReceiver<Text>(process, null);
  assert not receiver.isStopped();

  receiver.stop();
  assert receiver.isStopped();

  // Should return #stop when already stopped
  assert receiver.onChunk((0, #chunk(["a"]))) == #stop 0;
};

// Test ping handling
do {
  var itemsProcessed = 0;
  func process(index : Nat, item : Text) : Bool {
    itemsProcessed += 1;
    true;
  };

  let receiver = StreamReceiver.StreamReceiver<Text>(process, null);

  // Ping should not process any items
  assert receiver.onChunk((0, #ping)) == #ok;
  assert itemsProcessed == 0;
  assert receiver.length() == 0;

  // Normal chunk
  assert receiver.onChunk((0, #chunk(["a"]))) == #ok;
  assert itemsProcessed == 1;

  // Ping at current position
  assert receiver.onChunk((1, #ping)) == #ok;
  assert itemsProcessed == 1;
  assert receiver.length() == 1;
};

// Test restart message
do {
  var time = 0;
  func process(index : Nat, item : Text) : Bool { true };

  let receiver = StreamReceiver.StreamReceiver<Text>(process, ?(10, func() = time));

  assert receiver.onChunk((0, #chunk(["a"]))) == #ok;
  assert receiver.lastChunkReceived() == 0;

  time := 11;
  // Should stop due to timeout
  assert receiver.onChunk((1, #chunk(["b"]))) == #stop 0;
  assert receiver.isStopped();

  // Restart should reset stopped flag
  assert receiver.onChunk((1, #restart)) == #ok;
  assert not receiver.isStopped();

  // Should accept chunks again
  assert receiver.onChunk((1, #chunk(["b"]))) == #ok;
};

// Test timeout with multiple chunks and pings
do {
  var time = 0;
  func process(index : Nat, item : Text) : Bool { true };

  let receiver = StreamReceiver.StreamReceiver<Text>(process, ?(5, func() = time));

  assert receiver.onChunk((0, #chunk(["a"]))) == #ok;
  assert receiver.lastChunkReceived() == 0;

  time := 3;
  assert receiver.onChunk((1, #ping)) == #ok;
  assert receiver.lastChunkReceived() == 3;

  time := 7;
  assert receiver.onChunk((1, #chunk(["b"]))) == #ok;
  assert receiver.lastChunkReceived() == 7;

  time := 13;
  // Timeout exceeded
  assert receiver.onChunk((2, #ping)) == #stop 0;
};

// Test gap with wrong start position (too high)
do {
  func process(index : Nat, item : Text) : Bool { true };

  let receiver = StreamReceiver.StreamReceiver<Text>(process, null);

  assert receiver.onChunk((0, #chunk(["a"]))) == #ok;
  // Skip position 1, try position 2
  assert receiver.onChunk((2, #chunk(["c"]))) == #gap;
  assert receiver.length() == 1;
};

// Test gap with wrong start position (too low)
do {
  func process(index : Nat, item : Text) : Bool { true };

  let receiver = StreamReceiver.StreamReceiver<Text>(process, null);

  assert receiver.onChunk((0, #chunk(["a", "b"]))) == #ok;
  assert receiver.length() == 2;

  // Try to send from position 0 again
  assert receiver.onChunk((0, #chunk(["x"]))) == #gap;
  assert receiver.length() == 2;
};

// Test callback functionality
do {
  var callbackCalled = false;
  var lastInfo : ?(Nat, { #chunk : Nat; #ping; #restart }) = null;
  var lastResponse : ?StreamReceiver.ControlMessage = null;

  func process(index : Nat, item : Text) : Bool { true };

  let receiver = StreamReceiver.StreamReceiver<Text>(process, null);

  receiver.callbacks.onChunk := func(info, response) {
    callbackCalled := true;
    lastInfo := ?(info.0, info.1);
    lastResponse := ?response;
  };

  assert receiver.onChunk((0, #chunk(["a", "b"]))) == #ok;
  assert callbackCalled;
  assert lastInfo == ?(0, #chunk 2);
  assert lastResponse == ? #ok;

  callbackCalled := false;
  assert receiver.onChunk((2, #ping)) == #ok;
  assert callbackCalled;
  assert lastInfo == ?(2, #ping);
  assert lastResponse == ? #ok;

  callbackCalled := false;
  assert receiver.onChunk((3, #chunk(["c"]))) == #gap;
  assert callbackCalled;
  assert lastInfo == ?(3, #chunk 1);
  assert lastResponse == ? #gap;
};

// Test edge case: empty chunk
do {
  var itemsProcessed = 0;
  func process(index : Nat, item : Text) : Bool {
    itemsProcessed += 1;
    true;
  };

  let receiver = StreamReceiver.StreamReceiver<Text>(process, null);

  // Empty chunk should be processed successfully
  assert receiver.onChunk((0, #chunk([]))) == #ok;
  assert itemsProcessed == 0;
  assert receiver.length() == 0;

  // Next chunk should work normally
  assert receiver.onChunk((0, #chunk(["a"]))) == #ok;
  assert itemsProcessed == 1;
};

// Test maxLength with exact boundary
do {
  func process(index : Nat, item : Text) : Bool { true };

  let receiver = StreamReceiver.StreamReceiver<Text>(process, null);
  receiver.setMaxLength(?3);

  // Exactly at maxLength
  assert receiver.onChunk((0, #chunk(["a", "b", "c"]))) == #ok;
  assert receiver.length() == 3;

  // One more should be rejected
  assert receiver.onChunk((3, #chunk(["d"]))) == #stop 0;
};

// Test timeout at exact boundary
do {
  var time = 0;
  func process(index : Nat, item : Text) : Bool { true };

  let receiver = StreamReceiver.StreamReceiver<Text>(process, ?(10, func() = time));

  assert receiver.onChunk((0, #chunk(["a"]))) == #ok;
  time := 10; // Exactly at timeout boundary
  assert receiver.onChunk((1, #chunk(["b"]))) == #ok; // Should still work

  time := 11; // Now exceeded
  assert receiver.onChunk((2, #chunk(["c"]))) == #stop 0;
};

Debug.print("All advanced receiver tests passed");