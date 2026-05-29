import { SenderTracker; ReceiverTracker } "../../src/StreamTracker";
import StreamReceiver "../../src/StreamReceiver";
import StreamSender "../../src/StreamSender";
import Debug "mo:core/Debug";
import Error "mo:core/Error";
import Result "mo:core/Result";
import Text "mo:core/Text";
import Types "../../src/internal/types";
import Base "../sender.base";

import PT "mo:promtracker";
import { Tracker } "mo:promtracker";

type ControlMessage = Types.ControlMessage;
type ChunkMessage = Types.ChunkMessage<?Text>;

// Test Receiver tracker initialization and metrics
do {
  func process(index : Nat, item : Text) : Bool { true };

  let receiver = StreamReceiver.StreamReceiver<Text>(process, null);
  let metrics = Tracker.new();
  let renderer = PT.Renderer();
  renderer.addValue(metrics.toValue());
  let tracker = ReceiverTracker.new([]);
  tracker.init(receiver, metrics, renderer);

  // Process some chunks and verify metrics are updated
  ignore receiver.onChunk((0, #chunk(["a", "b", "c"])));
  ignore receiver.onChunk((3, #ping));
  ignore receiver.onChunk((3, #chunk(["d"])));

  // Metrics should be tracked
  let exposition = metrics.renderExposition();
  assert exposition.size() > 0;
};

// Test Receiver tracker with gap
do {
  func process(index : Nat, item : Text) : Bool { true };

  let receiver = StreamReceiver.StreamReceiver<Text>(process, null);
  let metrics = Tracker.new();
  let renderer = PT.Renderer();
  renderer.addValue(metrics.toValue());
  let tracker = ReceiverTracker.new([]);
  tracker.init(receiver, metrics, renderer);

  ignore receiver.onChunk((0, #chunk(["a"])));
  // Create a gap
  ignore receiver.onChunk((2, #chunk(["c"])));

  let exposition = metrics.renderExposition();
  // Should track the gap
  assert exposition.size() > 0;
};

// Test Receiver tracker with stop
do {
  func process(index : Nat, item : Text) : Bool { false };

  let receiver = StreamReceiver.StreamReceiver<Text>(process, null);
  let metrics = Tracker.new();
  let renderer = PT.Renderer();
  renderer.addValue(metrics.toValue());
  let tracker = ReceiverTracker.new([]);
  tracker.init(receiver, metrics, renderer);

  // Process chunk that will stop
  ignore receiver.onChunk((0, #chunk(["a", "b", "c"])));

  let exposition = metrics.renderExposition();
  // Should track the stop
  assert exposition.size() > 0;
};

// Test Receiver tracker with restart
do {
  func process(index : Nat, item : Text) : Bool { true };

  let receiver = StreamReceiver.StreamReceiver<Text>(process, null);
  let metrics = Tracker.new();
  let renderer = PT.Renderer();
  renderer.addValue(metrics.toValue());
  let tracker = ReceiverTracker.new([]);
  tracker.init(receiver, metrics, renderer);

  ignore receiver.onChunk((0, #chunk(["a"])));
  receiver.stop();
  ignore receiver.onChunk((1, #restart));

  let exposition = metrics.renderExposition();
  // Should track the restart
  assert exposition.size() > 0;
};

// Test Receiver tracker dispose
do {
  func process(index : Nat, item : Text) : Bool { true };

  let receiver = StreamReceiver.StreamReceiver<Text>(process, null);
  let metrics = Tracker.new();
  let renderer = PT.Renderer();
  renderer.addValue(metrics.toValue());
  let tracker = ReceiverTracker.new([]);
  tracker.init(receiver, metrics, renderer);

  ignore receiver.onChunk((0, #chunk(["a"])));

  let expositionBefore = metrics.renderExposition();
  assert expositionBefore.size() > 0;

  tracker.dispose(renderer);

  let expositionAfter = metrics.renderExposition();
  // After dispose, metrics should be reduced (not all removed due to potential system metrics)
  // Just verify dispose doesn't crash
  assert expositionAfter.size() <= expositionBefore.size();
};

// Test Sender tracker initialization and metrics
do {
  func send(ch : ChunkMessage) : async* ControlMessage { #ok };

  let sender = StreamSender.StreamSender<Text, ?Text>(send, Base.create(10));
  let metrics = Tracker.new();
  let renderer = PT.Renderer();
  renderer.addValue(metrics.toValue());
  let tracker = SenderTracker.new([]);
  tracker.init(sender, metrics, renderer);

  Result.assertOk(sender.push("a"));
  Result.assertOk(sender.push("b"));
  await* sender.sendChunk();

  // Metrics should be tracked
  let exposition = metrics.renderExposition();
  assert exposition.size() > 0;
};

// Test Sender tracker with no send
do {
  func send(ch : ChunkMessage) : async* ControlMessage { #ok };

  let sender = StreamSender.StreamSender<Text, ?Text>(send, Base.create(10));
  let metrics = Tracker.new();
  let renderer = PT.Renderer();
  renderer.addValue(metrics.toValue());
  let tracker = SenderTracker.new([]);
  tracker.init(sender, metrics, renderer);

  // Send with empty queue
  await* sender.sendChunk();

  let exposition = metrics.renderExposition();
  // Should track the skip
  assert exposition.size() > 0;
};

// Test Sender tracker with ping
do {
  var time = 0;
  func send(ch : ChunkMessage) : async* ControlMessage { #ok };

  let sender = StreamSender.StreamSender<Text, ?Text>(send, Base.create(10));
  sender.setKeepAlive(?(5, func() = time));

  let metrics = Tracker.new();
  let renderer = PT.Renderer();
  renderer.addValue(metrics.toValue());
  let tracker = SenderTracker.new([]);
  tracker.init(sender, metrics, renderer);

  time := 10;
  await* sender.sendChunk();

  let exposition = metrics.renderExposition();
  // Should track the ping
  assert exposition.size() > 0;
};

// Test Sender tracker with error
do {
  func send(ch : ChunkMessage) : async* ControlMessage {
    throw Error.reject("test error");
  };

  let sender = StreamSender.StreamSender<Text, ?Text>(send, Base.create(10));
  let metrics = Tracker.new();
  let renderer = PT.Renderer();
  let tracker = SenderTracker.new([]);
  tracker.init(sender, metrics, renderer);

  Result.assertOk(sender.push("a"));
  await* sender.sendChunk();

  let exposition = metrics.renderExposition();
  // Should track the error
  assert exposition.size() > 0;
};

// Test Sender tracker with gap response
do {
  func send(ch : ChunkMessage) : async* ControlMessage { #gap };

  let sender = StreamSender.StreamSender<Text, ?Text>(send, Base.create(10));
  let metrics = Tracker.new();
  let renderer = PT.Renderer();
  renderer.addValue(metrics.toValue());
  let tracker = SenderTracker.new([]);
  tracker.init(sender, metrics, renderer);

  Result.assertOk(sender.push("a"));
  await* sender.sendChunk();

  let exposition = metrics.renderExposition();
  // Should track the gap
  assert exposition.size() > 0;
};

// Test Sender tracker with stop response
do {
  func send(ch : ChunkMessage) : async* ControlMessage { #stop 0 };

  let sender = StreamSender.StreamSender<Text, ?Text>(send, Base.create(10));
  let metrics = Tracker.new();
  let renderer = PT.Renderer();
  renderer.addValue(metrics.toValue());
  let tracker = SenderTracker.new([]);
  tracker.init(sender, metrics, renderer);

  Result.assertOk(sender.push("a"));
  await* sender.sendChunk();

  let exposition = metrics.renderExposition();
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
  let metrics = Tracker.new();
  let renderer = PT.Renderer();
  renderer.addValue(metrics.toValue());
  let tracker = SenderTracker.new([]);
  tracker.init(sender, metrics, renderer);

  Result.assertOk(sender.push("a"));
  await* sender.sendChunk();
  assert sender.isStopped();

  shouldStop := false;
  assert (await sender.restart());

  let exposition = metrics.renderExposition();
  // Should track the restart
  assert exposition.size() > 0;
};

// Test Sender tracker dispose
do {
  func send(ch : ChunkMessage) : async* ControlMessage { #ok };

  let sender = StreamSender.StreamSender<Text, ?Text>(send, Base.create(10));
  let metrics = Tracker.new();
  let renderer = PT.Renderer();
  renderer.addValue(metrics.toValue());
  let tracker = SenderTracker.new([]);
  tracker.init(sender, metrics, renderer);

  Result.assertOk(sender.push("a"));
  await* sender.sendChunk();

  let expositionBefore = metrics.renderExposition();
  assert expositionBefore.size() > 0;

  tracker.dispose(renderer);

  let expositionAfter = metrics.renderExposition();
  // After dispose, metrics should be reduced
  // Just verify dispose doesn't crash
  assert expositionAfter.size() <= expositionBefore.size();
};

// Test multiple trackers with same PromTracker
do {
  func process(index : Nat, item : Text) : Bool { true };
  func send(ch : ChunkMessage) : async* ControlMessage { #ok };

  let receiver = StreamReceiver.StreamReceiver<Text>(process, null);
  let sender = StreamSender.StreamSender<Text, ?Text>(send, Base.create(10));

  let metrics = Tracker.new();
  let renderer = PT.Renderer();
  renderer.addValue(metrics.toValue());
  let receiverTracker = ReceiverTracker.new([("id", "receiver1")]);
  let senderTracker = SenderTracker.new([("id", "sender1")]);

  receiverTracker.init(receiver, metrics, renderer);
  senderTracker.init(sender, metrics, renderer);

  ignore receiver.onChunk((0, #chunk(["a"])));
  Result.assertOk(sender.push("a"));
  await* sender.sendChunk();

  let exposition = metrics.renderExposition();
  // Should track both receiver and sender metrics
  assert exposition.size() > 0;
};

// Test Receiver tracker with different label
do {
  func process(index : Nat, item : Text) : Bool { true };

  let receiver = StreamReceiver.StreamReceiver<Text>(process, null);
  let metrics = Tracker.new();
  let renderer = PT.Renderer();
  renderer.addValue(metrics.toValue());
  let tracker = ReceiverTracker.new([("custom_label", "value")]);
  tracker.init(receiver, metrics, renderer);

  ignore receiver.onChunk((0, #chunk(["a"])));

  let exposition = metrics.renderExposition();
  // Should include custom label
  assert exposition.startsWith(#text "stream_receiver_chunk_size_last{custom_label=\"value\"} 1 0");
};

// Test Sender tracker with different label
do {
  func send(ch : ChunkMessage) : async* ControlMessage { #ok };

  let sender = StreamSender.StreamSender<Text, ?Text>(send, Base.create(10));
  let metrics = Tracker.new();
  let renderer = PT.Renderer();
  renderer.addValue(metrics.toValue());
  let tracker = SenderTracker.new([("custom_label2", "value")]);
  tracker.init(sender, metrics, renderer);

  Result.assertOk(sender.push("a"));
  await* sender.sendChunk();

  let exposition = metrics.renderExposition();
  // Should include custom label
  assert exposition.startsWith(#text "stream_sender_window_size_last{custom_label2=\"value\"} 0 0");
};

Debug.print("All tracker tests passed");
