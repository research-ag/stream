import Stream "../../../src/StreamReceiver";
import List "mo:core/List";

actor Receiver {
  type ControlMessage = Stream.ControlMessage;
  type ChunkMessage = Stream.ChunkMessage<?Text>;

  let received = List.List<?Text>(0);

  let receiver = Stream.StreamReceiver<?Text>(
    func(index : Nat, item : ?Text) : Bool {
      received.add(item);
      received.size() == index + 1;
    },
    null,
  );

  public shared func receive(message : ChunkMessage) : async ControlMessage {
    receiver.onChunk(message);
  };

  public query func lastReceived() : async ??Text {
    if (received.size() == 0) { null } else {
      ?received.get(received.size() - 1);
    };
  };
};
