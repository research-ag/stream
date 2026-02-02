import Stream "../../../src/StreamReceiver";
import Error "mo:core/Error";

persistent actor class Bob(alice : Principal) {
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
    if (msg.caller != alice) throw Error.reject("not authorized");
    receiver_.onChunk(m);
  };

  // A getter for the log to monitor the receiver in action
  public func log() : async Text { log_ };
};
