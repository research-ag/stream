import Error "mo:core/Error";
import List "mo:core/List";
import Principal "mo:core/Principal";
import Prim "mo:prim";

import Stream "../../../src/StreamReceiver";

persistent actor Receiver {
  // Read sender principal once from an environment variable.
  //
  // Note: We don't allow the sender to change later because that
  // would risk corrupting the stream state. We would create a new
  // stream instead if we have a new sender.
  // Read allowed caller canister principal from environment variable
  let sender = Principal.fromText(
    switch (Prim.envVar<system>("PUBLIC_CANISTER_ID:sender")) {
      case (?id) id;
      case _ Prim.trap("Environment variable 'sender' not set");
    }
  );

  type ControlMessage = Stream.ControlMessage;
  type ChunkMessage = Stream.ChunkMessage<?Text>;

  transient let received = List.empty<?Text>();

  transient let receiver = Stream.StreamReceiver<?Text>(
    func(index : Nat, item : ?Text) : Bool {
      received.add(item);
      received.size() == index + 1;
    },
    null,
  );

  public shared (msg) func receive(message : ChunkMessage) : async ControlMessage {
    // Make sure only Sender can call this method
    if (msg.caller != sender) throw Error.reject("not authorized");
    receiver.onChunk(message);
  };

  public query func lastReceived() : async ??Text {
    if (received.size() == 0) { null } else {
      ?received.at(received.size() - 1 : Nat);
    };
  };
};
