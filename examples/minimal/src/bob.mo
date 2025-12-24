import Stream "../../../src/StreamReceiver";
import Error "mo:core/Error";

actor class Main(sender : Principal) {
  // substitute your item type here
  type Item = Nat;

  // define your processing function
  var log_ : Text = "";
  func processItem(index : Nat, item : Item) : Bool {
    // choose function name, keep the signature
    log_ #= debug_show (index, item) # " "; // put your processing code here
    true;
  };

  // begin boilerplate
  let receiver_ = Stream.StreamReceiver<Item>(processItem, null); // substitute your processing function for `processItem`
  public shared (msg) func receive(m : Stream.ChunkMessage<Item>) : async Stream.ControlMessage {
    // choose a name for public endpoint `receive`
    if (msg.caller != sender) throw Error.reject("not authorized"); // use the init argument `sender` here
    receiver_.onChunk(m); // ok to wrap custom code around this
  };
  // end boilerplate

  public func log() : async Text { log_ };
};
