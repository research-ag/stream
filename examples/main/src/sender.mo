import Stream "../../../src/StreamSender";
import Result "mo:core/Result";
import Prim "mo:prim";

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

  transient let MAX_LENGTH = 30;

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

  func send(message : ChunkMessage) : async* ControlMessage {
    await receiver.receive(message);
  };

  transient let sender = Stream.StreamSender<Text, ?Text>(send, counter);

  // Persist stream state across upgrades
  var streamData = sender.share();
  system func preupgrade() = streamData := sender.share();
  system func postupgrade() = sender.unshare(streamData);

  public shared func add(text : Text) : async () {
    Result.assertOk(sender.push(text));
  };

  system func heartbeat() : async () {
    await* sender.sendChunk();
  };

};
