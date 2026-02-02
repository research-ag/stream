import Stream "../../../src/StreamSender";
import Tracker "../../../src/Tracker";
import Principal "mo:core/Principal";
import Result "mo:core/Result";
import Text "mo:core/Text";
import Time "mo:core/Time";
import PT "mo:promtracker";

persistent actor class Sender(receiverId : Principal) = self {
  type ControlMessage = Stream.ControlMessage;
  type ChunkMessage = Stream.ChunkMessage<?Text>;

  transient let receiver = actor (Principal.toText(receiverId)) : actor {
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

  transient let labels = "canister=\"" # PT.shortName(self) # "\"";
  transient let metrics = PT.PromTracker(labels, 65);
  transient let tracker = Tracker.Sender(metrics, "", true);

  transient let sender = Stream.StreamSender<Text, ?Text>(
    func(x : ChunkMessage) : async* ControlMessage { await receiver.receive(x) },
    counter,
  );

  sender.setKeepAlive(?(10 ** 15, Time.now));

  tracker.init(sender);

  public shared func add(text : Text) : async () {
    Result.assertOk(sender.push(text));
  };

  system func heartbeat() : async () {
    await* sender.sendChunk();
  };

  // Expose the `/metrics` endpoint
  public query func http_request(req : PT.HttpReq) : async PT.HttpResp {
    metrics.http_request(req);
  };
};
