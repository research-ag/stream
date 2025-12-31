import StreamSender "../src/StreamSender";
import Error "mo:core/Error";
import Debug "mo:core/Debug";
import Nat "mo:core/Nat";
import Types "../src/types";

// sender actor
// argument r is the receiver's shared receive function
persistent actor class A(
  b : actor {
    receive(m : Types.ChunkMessage<?Text>) : async Types.ControlMessage;
  }
) {
  // types for receiver actor
  type ChunkMessage = Types.ChunkMessage<?Text>;
  type ControlMessage = Types.ControlMessage;

  transient let MAX_LENGTH = 5;

  class counter() {
    var sum = 0;
    // Any individual item larger than MAX_LENGTH is wrapped to null
    // and its size is not counted.
    func wrap(item : Text) : (?Text, Nat) {
      let s = item.size();
      if (s <= MAX_LENGTH) (?item, s) else (null, 0);
    };
    public func accept(item : Text) : ??Text {
      let (wrapped, size) = wrap(item);
      sum += size;
      if (sum <= MAX_LENGTH) ?wrapped else null;
    };
  };

  // Wrap the receiver's shared function.
  // This must always be done because we need to turn the receiver's shared
  // function into an async* return type.
  // We can place additional code here, for example, for logging.
  // However, we must not catch and convert any Errors. The Errors from
  // `await r` must be passed through unaltered or the StreamSender may break.
  func sendToReceiver(m : ChunkMessage) : async* ControlMessage {
    let start = m.0;
    var end = m.0;
    var str = "A send: (" # Nat.toText(m.0) # ", ";
    switch (m.1) {
      case (#ping) str #= "ping";
      case (#chunk e) {
        str #= "chunk [" # Nat.toText(e.size()) # "]";
        end := start + e.size();
      };
      case (#restart) str #= "restart";
    };
    Debug.print(str # ")");
    str := "A recv: [" # Nat.toText(start) # "-" # Nat.toText(end) # ") ";
    try {
      let ret = await b.receive(m);
      switch (ret) {
        case (#ok) str #= "ok";
        case (#gap) str #= "gap";
        case (#stop _) str #= "stop";
      };
      Debug.print(str);
      return ret;
    } catch (e) {
      switch (Error.code(e)) {
        case (#canister_reject) str #= "reject(";
        case (#canister_error) str #= "trap(";
        case (_) str #= "other(";
      };
      str #= "\"" # Error.message(e) # "\")";
      Debug.print(str);
      throw e;
    };
  };

  transient let sender = StreamSender.StreamSender<Text, ?Text>(sendToReceiver, counter);

  public func submit(item : Text) : async {
    #err : { #NoSpace; #LimitExceeded };
    #ok : Nat;
  } {
    let res = sender.push(item);
    var str = "A submit: ";
    switch (res) {
      case (#ok i) str #= Nat.toText(i);
      case (#err _) str #= "Error";
    };
    Debug.print(str);
    res;
  };

  transient var t = 0;
  public func trigger() : async () {
    let t_ = t;
    t += 1;
    Debug.print("A trigger: " # Nat.toText(t_) # " ");
    await* sender.sendChunk();
    // Debug.print("A trigger: " # Nat.toText(t_) # " <-");
  };

  public query func isState(l : [Nat]) : async Bool {
    Debug.print("A isState: " # debug_show (l));
    sender.length() == l[0] and sender.sent() == l[1] and sender.received() == l[2] and sender.busyLevel() == l[3];
  };

  public query func isShutdown() : async Bool {
    sender.isShutdown();
  };
};