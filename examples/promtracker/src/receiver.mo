import Stream "../../../src/StreamReceiver";
import Tracker "../../../src/Tracker";
import Error "mo:core/Error";
import Principal "mo:core/Principal";
import Text "mo:core/Text";
import Time "mo:core/Time";
import Prim "mo:prim";
import PT "mo:promtracker";

persistent actor Receiver {
  // Read allowed caller canister principal from environment variable
  transient let allowedCaller = Principal.fromText(
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

  transient let labels = "canister=\"" # PT.shortName(Receiver) # "\"";
  transient let metrics = PT.PromTracker(labels, 65);
  transient let tracker = Tracker.Receiver(metrics, "", false);
  tracker.init(receiver);

  public shared (msg) func receive(c : ChunkMessage) : async ControlMessage {
    // Make sure only Sender can call this method
    if (msg.caller != allowedCaller) throw Error.reject("not authorized");
    receiver.onChunk(c);
  };

  // Expose the `/metrics` endpoint
  public query func http_request(req : PT.HttpReq) : async PT.HttpResp {
    metrics.http_request(req);
  };
};
