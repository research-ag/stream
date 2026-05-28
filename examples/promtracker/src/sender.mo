import Result "mo:core/Result";
import Text "mo:core/Text";
import Time "mo:core/Time";
import Prim "mo:prim";

import { Tracker; Renderer; allSystemMetrics } "mo:promtracker";
import Http "mo:promtracker/mixins/http";
import Metrics "mo:promtracker/Metrics";

import Stream "mo:stream/StreamSender";
import Tracker_ "mo:stream/Tracker";

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
  transient let renderer = Renderer();
  renderer.addCanisterLabel(Sender);
  // Expose the `/metrics` endpoint
  include Http(renderer.renderExposition, "/metrics");

  transient let tracker = Tracker_.Sender(pt, renderer, []);
  tracker.init(sender);

  // Persist stream state and metrics across upgrades
  var streamData = sender.share();

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

};
