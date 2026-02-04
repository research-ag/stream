import Stream "../../../src/StreamReceiver";
import Tracker "../../../src/Tracker";
import Error "mo:core/Error";
import Principal "mo:core/Principal";
import Text "mo:core/Text";
import Time "mo:core/Time";
import Prim "mo:prim";
import PT "mo:promtracker";

persistent actor Receiver {
  // Read sender principal once from an environment variable.
  //
  // Note: We don't allow the sender to change later because that
  // would risk corrupting the stream state. We would create a new
  // stream instead if we have a new sender.
  // Read allowed caller canister principal from environment variable
  // Read allowed caller canister principal from environment variable
  let sender = Principal.fromText(
    switch (Prim.envVar<system>("PUBLIC_CANISTER_ID:sender")) {
      case (?id) id;
      case _ Prim.trap("Environment variable 'sender' not set");
    }
  );

  type ControlMessage = Stream.ControlMessage;
  type ChunkMessage = Stream.ChunkMessage<?Text>;

  transient var store : ?Text = null;
  public func lastReceived() : async ?Text { store };

  transient let receiver = Stream.StreamReceiver<?Text>(
    func(_ : Nat, item : ?Text) : Bool { store := item; true },
    ?(10 ** 15, Time.now),
  );

  transient let metrics = PT.PromTracker(PT.canisterLabel(Receiver), 65);
  transient let tracker = Tracker.Receiver(metrics, "", false);
  tracker.init(receiver);

  public shared (msg) func receive(c : ChunkMessage) : async ControlMessage {
    // Make sure only Sender can call this method
    if (msg.caller != sender) throw Error.reject("not authorized");
    receiver.onChunk(c);
  };

  // Expose the `/metrics` endpoint
  public query func http_request(req : PT.HttpReq) : async PT.HttpResp {
    metrics.http_request(req);
  };

  // Persist metrics across upgrades (optional)
  var ptData : PT.StableData = null;
  system func postupgrade() = metrics.unshare(ptData);
  system func preupgrade() = ptData := metrics.share();
};
