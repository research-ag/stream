import Stream "../../../src/StreamReceiver";
import Tracker "../../../src/Tracker";
import Text "mo:core/Text";
import Time "mo:core/Time";
import PT "mo:promtracker";

persistent actor Receiver {
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

  public shared func receive(c : ChunkMessage) : async ControlMessage {
    receiver.onChunk(c);
  };

  // Expose the `/metrics` endpoint
  public query func http_request(req : PT.HttpReq) : async PT.HttpResp {
    metrics.http_request(req);
  };
};
