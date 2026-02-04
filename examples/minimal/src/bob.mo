import Error "mo:core/Error";
import Principal "mo:core/Principal";
import Stream "../../../src/StreamReceiver";
import Prim "mo:prim";

persistent actor Bob {
  // Read sender principal once from an environment variable.
  //
  // Note: We don't allow the sender to change later because that
  // would risk corrupting the stream state. We would create a new
  // stream instead if we have a new sender.
  let sender = Principal.fromText(
    switch (Prim.envVar<system>("PUBLIC_CANISTER_ID:alice")) {
      case (?id) id;
      case _ Prim.trap("Environment variable 'alice' not set");
    }
  );

  // Substitute your item type here
  type Item = Nat;

  // We define a function to process each item.
  // It accepts the item index (position) in the stream and the item itself.
  // In this example the processing function simply logs the item.
  // The function name can be freely chosen.
  transient var log_ : Text = "";
  func processItem(index : Nat, item : Item) : Bool {
    // put your processing code here
    log_ #= debug_show (index, item) # " ";
    true;
  };

  // Now we can define our `StreamReceiver` by passing it the processing function defined above:
  transient let receiver_ = Stream.StreamReceiver<Item>(processItem, null);

  // We have to create the endpoint (update method) that Alice will call to send chunks.
  // Here, both sides have agreed on the name "receive" for this endpoint.
  // The type must be: `shared Stream.ChunkMessage<Item> -> async Stream.ControlMessage`
  // It is possible to wrap custom code around calling `onChunk` but we must not tamper
  // with the response and we must not trap.
  public shared (msg) func receive(m : Stream.ChunkMessage<Item>) : async Stream.ControlMessage {
    // Make sure only Alice can call this method
    if (msg.caller != sender) throw Error.reject("not authorized");
    receiver_.onChunk(m);
  };

  // A getter for the log to monitor the receiver in action
  public func log() : async Text { log_ };
};
