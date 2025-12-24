import Stream "../../../src/StreamSender";
import Principal "mo:core/Principal";
import Result "mo:core/Result";

persistent actor class Sender(receiverId : Principal) {
  type ControlMessage = Stream.ControlMessage;
  type ChunkMessage = Stream.ChunkMessage<?Text>;

  transient let receiver = actor (Principal.toText(receiverId)) : actor {
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

  public shared func add(text : Text) : async () {
    Result.assertOk(sender.push(text));
  };

  system func heartbeat() : async() {
    await* sender.sendChunk();
  };
};
