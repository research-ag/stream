import Stream "../../../src/StreamSender";
import Principal "mo:core/Principal";

actor class Main(receiver : Principal) {
  // substitute your item type here
  type Item = Nat;

  // begin boilerplate
  type RecvFunc = shared Stream.ChunkMessage<Item> -> async Stream.ControlMessage;
  type ReceiverAPI = actor { receive : RecvFunc }; // substitute your receiver's endpoint for `receive`
  let A : ReceiverAPI = actor (Principal.toText(receiver)); // use the init argument `receiver` here
  let send_ = func(x : Stream.ChunkMessage<Item>) : async* Stream.ControlMessage {
    await A.receive(x) // ok to wrap custom code around this but not tamper with response or trap
  };
  // end boilerplate

  // define your sender by defining counter
  class counter_() {
    var sum = 0;
    let maxLength = 3;
    public func accept(item : Item) : ?Item {
      if (sum == maxLength) return null;
      sum += 1;
      return ?item;
    };
  };
  let sender = Stream.StreamSender<Item, Item>(send_, counter_);

  // example use of sender `push` and `sendChunk`
  public shared func enqueue(n : Nat) : async () {
    var i = 0;
    while (i < n) {
      ignore sender.push((i + 1) ** 2);
      i += 1;
    };
  };
  
  public shared func batch() : async () {
    await* sender.sendChunk();
  };
};
