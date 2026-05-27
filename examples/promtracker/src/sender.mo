import Stream "../../../src/StreamSender";
import Tracker_ "../../../src/Tracker";
import Result "mo:core/Result";
import Text "mo:core/Text";
import Time "mo:core/Time";
import Prim "mo:prim";
import PT "mo:promtracker";
import { Tracker } "mo:promtracker";
import Http "mo:promtracker/mixins/http";

persistent actor Sender {
  // Read receiver canister id once from an environment variable.
  //
  // Note: We don't allow the receiver to change later because that
  // would risk corrupting the stream state. We would create a new
  // stream instead if we have a new receiver.
  let receiverId : Text = switch (Prim.envVar<system>("PUBLIC_CANISTER_ID:receiver")) {
    case (?id) id;
    case _ Prim.trap("Environment variable 'PUBLIC_CANISTER_ID:receiver' not set");
  };

  type ControlMessage = Stream.ControlMessage;
  type ChunkMessage = Stream.ChunkMessage<?Text>;

  let receiver = actor (receiverId) : actor {
    receive : (message : ChunkMessage) -> async ControlMessage;
  };

  let MAX_LENGTH = 30;

  class counter() {
    var sum = 0;
    func wrap(item : Text) : (?Text, Nat) {
      let s = (to_candid (item)).size();
      if (s <= MAX_LENGTH) (?item, s) else (null, 0);
    };
    public func accept(item : Text) : ??Text {
      let (wrapped, size) = wrap(item);
      sum += size;
      if (sum <= MAX_LENGTH) ?wrapped else null;
    };
  };

  transient let sender = Stream.StreamSender<Text, ?Text>(
    func(x : ChunkMessage) : async* ControlMessage { await receiver.receive(x) },
    counter,
  );
  sender.setKeepAlive(?(10 ** 11, Time.now));

  let pt = Tracker.new();
  transient let renderer = PT.Renderer();
  include Http(renderer.renderExposition, "/metrics");

  transient let tracker = Tracker_.Sender(pt, [], true);
  tracker.init(sender);

  renderer.addValue(pt.toValue());
  renderer.addValue(tracker.sentMetric());
  renderer.addValue(tracker.receivedMetric());
  renderer.addValue(tracker.lengthMetric());
  renderer.addValue(tracker.lastChunkSentMetric());
  renderer.addValue(tracker.shutdownMetric());
  renderer.addValue(tracker.windowSizeMetric());
  renderer.addValue(PT.allSystemMetrics);
  renderer.addCanisterLabel(Sender);

  // Persist stream state and metrics across upgrades
  var streamData = sender.share();
  // Tracker is persistent, no need for share/unshare

  system func postupgrade() {
    sender.unshare(streamData);
  };
  system func preupgrade() {
    streamData := sender.share();
  };

  public shared func add(text : Text) : async () {
    Result.assertOk(sender.push(text));
  };

  system func heartbeat() : async () {
    await* sender.sendChunk();
  };

  // Expose the `/metrics` endpoint
  // Using the Http mixin above provides the implementation for http_request.
  // We can remove this manual implementation or keep it if we have other routes.
};
