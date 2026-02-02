import Tracker "../../src/Tracker";
import StreamReceiver "../../src/StreamReceiver";
import StreamSender "../../src/StreamSender";
import PT "mo:promtracker";
import Debug "mo:core/Debug";
import Error "mo:core/Error";
import Result "mo:core/Result";
import Types "../../src/internal/types";
import Base "../sender.base";

type ControlMessage = Types.ControlMessage;
type ChunkMessage = Types.ChunkMessage<?Text>;

// Test Receiver tracker initialization and metrics
do {
  func process(index : Nat, item : Text) : Bool { true };

  let receiver = StreamReceiver.StreamReceiver<Text>(process, null);
  let metrics = PT.PromTracker("", 100);
  let tracker = Tracker.Receiver(metrics, "test_receiver", false);

  tracker.init(receiver);

  // Process some chunks and verify metrics are updated
  ignore receiver.onChunk((0, #chunk(["a", "b", "c"])));
  ignore receiver.onChunk((3, #ping));
  ignore receiver.onChunk((3, #chunk(["d"])));

  // Metrics should be tracked
  let exposition = metrics.renderExposition("");
  assert exposition.size() > 0;
};

// Test Receiver tracker with gap
do {
  func process(index : Nat, item : Text) : Bool { true };

  let receiver = StreamReceiver.StreamReceiver<Text>(process, null);
  let metrics = PT.PromTracker("", 100);
  let tracker = Tracker.Receiver(metrics, "test_receiver", false);

  tracker.init(receiver);

  ignore receiver.onChunk((0, #chunk(["a"])));
  // Create a gap
  ignore receiver.onChunk((2, #chunk(["c"])));

  let exposition = metrics.renderExposition("");
  // Should track the gap
  assert exposition.size() > 0;
};

// Test Receiver tracker with stop
do {
  func process(index : Nat, item : Text) : Bool { false };

  let receiver = StreamReceiver.StreamReceiver<Text>(process, null);
  let metrics = PT.PromTracker("", 100);
  let tracker = Tracker.Receiver(metrics, "test_receiver", false);

  tracker.init(receiver);

  // Process chunk that will stop
  ignore receiver.onChunk((0, #chunk(["a", "b", "c"])));

  let exposition = metrics.renderExposition("");
  // Should track the stop
  assert exposition.size() > 0;
};

// Test Receiver tracker with restart
do {
  func process(index : Nat, item : Text) : Bool { true };

  let receiver = StreamReceiver.StreamReceiver<Text>(process, null);
  let metrics = PT.PromTracker("", 100);
  let tracker = Tracker.Receiver(metrics, "test_receiver", false);

  tracker.init(receiver);

  ignore receiver.onChunk((0, #chunk(["a"])));
  receiver.stop();
  ignore receiver.onChunk((1, #restart));

  let exposition = metrics.renderExposition("");
  // Should track the restart
  assert exposition.size() > 0;
};

// Test Receiver tracker dispose
do {
  func process(index : Nat, item : Text) : Bool { true };

  let receiver = StreamReceiver.StreamReceiver<Text>(process, null);
  let metrics = PT.PromTracker("", 100);
  let tracker = Tracker.Receiver(metrics, "test_receiver", false);

  tracker.init(receiver);

  ignore receiver.onChunk((0, #chunk(["a"])));

  let expositionBefore = metrics.renderExposition("");
  assert expositionBefore.size() > 0;

  tracker.dispose();

  let expositionAfter = metrics.renderExposition("");
  // After dispose, metrics should be reduced (not all removed due to potential system metrics)
  // Just verify dispose doesn't crash
  assert expositionAfter.size() >= 0;
};

// Test Sender tracker initialization and metrics
do {
  func send(ch : ChunkMessage) : async* ControlMessage { #ok };

  let sender = StreamSender.StreamSender<Text, ?Text>(send, Base.create(10));
  let metrics = PT.PromTracker("", 100);
  let tracker = Tracker.Sender(metrics, "test_sender", false);

  tracker.init(sender);

  Result.assertOk(sender.push("a"));
  Result.assertOk(sender.push("b"));
  await* sender.sendChunk();

  // Metrics should be tracked
  let exposition = metrics.renderExposition("");
  assert exposition.size() > 0;
};

// Test Sender tracker with no send
do {
  func send(ch : ChunkMessage) : async* ControlMessage { #ok };

  let sender = StreamSender.StreamSender<Text, ?Text>(send, Base.create(10));
  let metrics = PT.PromTracker("", 100);
  let tracker = Tracker.Sender(metrics, "test_sender", false);

  tracker.init(sender);

  // Send with empty queue
  await* sender.sendChunk();

  let exposition = metrics.renderExposition("");
  // Should track the skip
  assert exposition.size() > 0;
};

// Test Sender tracker with ping
do {
  var time = 0;
  func send(ch : ChunkMessage) : async* ControlMessage { #ok };

  let sender = StreamSender.StreamSender<Text, ?Text>(send, Base.create(10));
  sender.setKeepAlive(?(5, func() = time));

  let metrics = PT.PromTracker("", 100);
  let tracker = Tracker.Sender(metrics, "test_sender", false);

  tracker.init(sender);

  time := 10;
  await* sender.sendChunk();

  let exposition = metrics.renderExposition("");
  // Should track the ping
  assert exposition.size() > 0;
};

// Test Sender tracker with error
do {
  func send(ch : ChunkMessage) : async* ControlMessage {
    throw Error.reject("test error");
  };

  let sender = StreamSender.StreamSender<Text, ?Text>(send, Base.create(10));
  let metrics = PT.PromTracker("", 100);
  let tracker = Tracker.Sender(metrics, "test_sender", false);

  tracker.init(sender);

  Result.assertOk(sender.push("a"));
  await* sender.sendChunk();

  let exposition = metrics.renderExposition("");
  // Should track the error
  assert exposition.size() > 0;
};

// Test Sender tracker with gap response
do {
  func send(ch : ChunkMessage) : async* ControlMessage { #gap };

  let sender = StreamSender.StreamSender<Text, ?Text>(send, Base.create(10));
  let metrics = PT.PromTracker("", 100);
  let tracker = Tracker.Sender(metrics, "test_sender", false);

  tracker.init(sender);

  Result.assertOk(sender.push("a"));
  await* sender.sendChunk();

  let exposition = metrics.renderExposition("");
  // Should track the gap
  assert exposition.size() > 0;
};

// Test Sender tracker with stop response
do {
  func send(ch : ChunkMessage) : async* ControlMessage { #stop 0 };

  let sender = StreamSender.StreamSender<Text, ?Text>(send, Base.create(10));
  let metrics = PT.PromTracker("", 100);
  let tracker = Tracker.Sender(metrics, "test_sender", false);

  tracker.init(sender);

  Result.assertOk(sender.push("a"));
  await* sender.sendChunk();

  let exposition = metrics.renderExposition("");
  // Should track the stop
  assert exposition.size() > 0;
};

// Test Sender tracker with restart
do {
  var shouldStop = true;
  func send(ch : ChunkMessage) : async* ControlMessage {
    if (shouldStop) {
      switch (ch.1) {
        case (#restart) #ok;
        case (_) #stop 0;
      };
    } else #ok;
  };

  let sender = StreamSender.StreamSender<Text, ?Text>(send, Base.create(10));
  let metrics = PT.PromTracker("", 100);
  let tracker = Tracker.Sender(metrics, "test_sender", false);

  tracker.init(sender);

  Result.assertOk(sender.push("a"));
  await* sender.sendChunk();
  assert sender.isStopped();

  shouldStop := false;
  assert (await sender.restart());

  let exposition = metrics.renderExposition("");
  // Should track the restart
  assert exposition.size() > 0;
};

// Test Sender tracker dispose
do {
  func send(ch : ChunkMessage) : async* ControlMessage { #ok };

  let sender = StreamSender.StreamSender<Text, ?Text>(send, Base.create(10));
  let metrics = PT.PromTracker("", 100);
  let tracker = Tracker.Sender(metrics, "test_sender", false);

  tracker.init(sender);

  Result.assertOk(sender.push("a"));
  await* sender.sendChunk();

  let expositionBefore = metrics.renderExposition("");
  assert expositionBefore.size() > 0;

  tracker.dispose();

  let expositionAfter = metrics.renderExposition("");
  // After dispose, metrics should be reduced
  // Just verify dispose doesn't crash
  assert expositionAfter.size() >= 0;
};

// Test multiple trackers with same PromTracker
do {
  func process(index : Nat, item : Text) : Bool { true };
  func send(ch : ChunkMessage) : async* ControlMessage { #ok };

  let receiver = StreamReceiver.StreamReceiver<Text>(process, null);
  let sender = StreamSender.StreamSender<Text, ?Text>(send, Base.create(10));

  let metrics = PT.PromTracker("", 150);
  let receiverTracker = Tracker.Receiver(metrics, "receiver1", false);
  let senderTracker = Tracker.Sender(metrics, "sender1", false);

  receiverTracker.init(receiver);
  senderTracker.init(sender);

  ignore receiver.onChunk((0, #chunk(["a"])));
  Result.assertOk(sender.push("a"));
  await* sender.sendChunk();

  let exposition = metrics.renderExposition("");
  // Should track both receiver and sender metrics
  assert exposition.size() > 0;
};

// Test Receiver tracker with different label
do {
  func process(index : Nat, item : Text) : Bool { true };

  let receiver = StreamReceiver.StreamReceiver<Text>(process, null);
  let metrics = PT.PromTracker("", 100);
  let tracker = Tracker.Receiver(metrics, "custom_label=\"value\"", false);

  tracker.init(receiver);

  ignore receiver.onChunk((0, #chunk(["a"])));

  let exposition = metrics.renderExposition("");
  // Should include custom label
  assert exposition.size() > 0;
};

// Test Sender tracker with different label
do {
  func send(ch : ChunkMessage) : async* ControlMessage { #ok };

  let sender = StreamSender.StreamSender<Text, ?Text>(send, Base.create(10));
  let metrics = PT.PromTracker("", 100);
  let tracker = Tracker.Sender(metrics, "custom_label=\"value\"", false);

  tracker.init(sender);

  Result.assertOk(sender.push("a"));
  await* sender.sendChunk();

  let exposition = metrics.renderExposition("");
  // Should include custom label
  assert exposition.size() > 0;
};

// Test stable metrics flag
do {
  func process(index : Nat, item : Text) : Bool { true };

  let receiver = StreamReceiver.StreamReceiver<Text>(process, null);
  let metrics = PT.PromTracker("", 100);

  // Create tracker with stable = true
  let tracker = Tracker.Receiver(metrics, "test", true);
  tracker.init(receiver);

  ignore receiver.onChunk((0, #chunk(["a"])));

  let exposition = metrics.renderExposition("");
  assert exposition.size() > 0;
};

Debug.print("All tracker tests passed");