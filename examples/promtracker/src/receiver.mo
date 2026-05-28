import Error "mo:core/Error";
import Principal "mo:core/Principal";
import Text "mo:core/Text";
import Time "mo:core/Time";
import Prim "mo:prim";

import { Tracker; Renderer } "mo:promtracker";
import Http "mo:promtracker/mixins/http";

import Stream "mo:stream/StreamReceiver";
import StreamTracker "mo:stream/StreamTracker";

persistent actor Receiver {
  // Read sender principal once from an environment variable.
  //
  // Note: We don't allow the sender to change later because that
  // would risk corrupting the stream state. We would create a new
  // stream instead if we have a new sender.
  let sender = Principal.fromText(
    switch (Prim.envVar<system>("PUBLIC_CANISTER_ID:sender")) {
      case (?id) id;
      case _ Prim.trap("Environment variable 'PUBLIC_CANISTER_ID:sender' not set");
    }
  );

  type ControlMessage = Stream.ControlMessage;
  type ChunkMessage = Stream.ChunkMessage<?Text>;

  var store : ?Text = null;
  public func lastReceived() : async ?Text { store };

  transient let receiver = Stream.StreamReceiver<?Text>(
    func(_ : Nat, item : ?Text) : Bool { store := item; true },
    ?(10 ** 12, Time.now),
  );

  let pt = Tracker.new();

  transient let renderer = Renderer();
  renderer.addCanisterLabel(Receiver);
  renderer.addValue(pt.toValue());
  include Http(renderer.renderExposition, "/metrics");

  transient let tracker = StreamTracker.Receiver(pt, renderer, []);
  tracker.init(receiver);

  // Persist stream state and metrics across upgrades
  var streamData = receiver.share();
  system func preupgrade() {
    streamData := receiver.share();
  };
  system func postupgrade() {
    receiver.unshare(streamData);
  };

  public shared (msg) func receive(c : ChunkMessage) : async ControlMessage {
    // Make sure only Sender can call this method
    if (msg.caller != sender) throw Error.reject("not authorized");
    receiver.onChunk(c);
  };

};
