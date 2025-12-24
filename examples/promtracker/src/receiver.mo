import Stream "../../../src/StreamReceiver";
import Tracker "../../../src/Tracker";
import Text "mo:core/Text";
import Time "mo:core/Time";
import PT "mo:promtracker";
import HTTP "http";

actor class Receiver() = self {
  type ControlMessage = Stream.ControlMessage;
  type ChunkMessage = Stream.ChunkMessage<?Text>;

  var store : ?Text = null;
  public func lastReceived() : async ?Text { store };

  let receiver = Stream.StreamReceiver<?Text>(
    func(_ : Nat, item : ?Text) : Bool { store := item; true },
    ?(10 ** 15, Time.now),
  );

  let metrics = PT.PromTracker("", 65);
  let tracker = Tracker.Receiver(metrics, "", false);
  tracker.init(receiver);

  public shared func receive(c : ChunkMessage) : async ControlMessage {
    receiver.onChunk(c);
  };

  // metrics endpoint
  public query func http_request(req : HTTP.HttpRequest) : async HTTP.HttpResponse {
    let ?path = Text.split(req.url, #char '?').next() else return HTTP.render400();
    let labels = "canister=\"" # PT.shortName(self) # "\"";
    switch (req.method, path) {
      case ("GET", "/metrics") HTTP.renderPlainText(metrics.renderExposition(labels));
      case (_) HTTP.render400();
    };
  };
};
