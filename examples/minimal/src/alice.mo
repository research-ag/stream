import Stream "../../../src/StreamSender";
import Prim "mo:prim";

persistent actor Alice {
  // Read Bob's canister id once from an environment variable.
  //
  // Note: We don't allow the receiver to change later because that
  // would risk corrupting the stream state. We would create a new
  // stream instead if we have a new receiver.
  let bob : Text = switch (Prim.envVar<system>("PUBLIC_CANISTER_ID:bob")) {
    case (?id) id;
    case _ Prim.trap("Environment variable 'PUBLIC_CANISTER_ID:bob' not set");
  };

  // Substitute your item type here
  type Item = Nat;

  // The endpoint (update method) on Bob's side must have this type:
  type RecvFunc = shared Stream.ChunkMessage<Item> -> async Stream.ControlMessage;

  // The endpoint (update method) on Bob's side is called "receive" in this example.
  // Hence, this is the actor supertype for Bob that we use:
  type ReceiverAPI = actor { receive : RecvFunc };

  // This is Bob, the receiving actor whose Principal was supplied in the init argument:
  transient let B : ReceiverAPI = actor (bob);

  // This is our `sendFunc` which is simply a wrapper around Bob's `receive` method.
  // It is possible to wrap custom code around calling `B.receive` but we must not tamper
  // with the response and we must not trap.
  transient let send_ = func(x : Stream.ChunkMessage<Item>) : async* Stream.ControlMessage {
    await B.receive(x);
  };

  // This is our `counterCreator`.

  // A class with a single `accept` method which returns `null` when a batch is full.
  // In this example we simply count the number of items and allow at most 3 items in a batch.
  // We also do not transform the items, i.e. the type of items in the queue is identical to
  // the type of items in the batch.

  class counter_() {
    var sum = 0;
    let maxLength = 3;
    public func accept(item : Item) : ?Item {
      if (sum == maxLength) return null;
      sum += 1;
      return ?item;
    };
  };

  // We can now define our `StreamSender` class, initialized with our `sendFunc` and `counterCreator`.
  transient let sender = Stream.StreamSender<Item, Item>(send_, counter_);

  // This function shows how we push to the `StreamSender`'s queue with `push`.
  public shared func enqueue(n : Nat) : async () {
    var i = 0;
    while (i < n) {
      ignore sender.push((i + 1) ** 2);
      i += 1;
    };
  };

  // This function shows how we trigger a chunk to formed and sent with `sendChunk`.
  public shared func batch() : async () {
    await* sender.sendChunk();
  };
};
