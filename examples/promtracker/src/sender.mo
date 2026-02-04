import Stream "../../../src/StreamSender";
import Tracker "../../../src/Tracker";
import Result "mo:core/Result";
import Text "mo:core/Text";
import Time "mo:core/Time";
import Prim "mo:prim";
import PT "mo:promtracker";

persistent actor Sender {
  // Read Receiver's canister ID from environment variable
  transient let receiverId = switch (Prim.envVar<system>("PUBLIC_CANISTER_ID:receiver")) {
      case (?id) id;
      case _ Prim.trap("Environment variable 'PUBLIC_CANISTER_ID:receiver' not set");
    };

  type ControlMessage = Stream.ControlMessage;
  type ChunkMessage = Stream.ChunkMessage<?Text>;

  transient let receiver = actor (receiverId) : actor {
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

  transient let metrics = PT.PromTracker(PT.canisterLabel(Sender), 65);
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
