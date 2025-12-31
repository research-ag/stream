import StreamReceiver "../src/StreamReceiver";
import List "mo:core/List";
import Error "mo:core/Error";
import Debug "mo:core/Debug";
import Nat "mo:core/Nat";
import Types "../src/types";

// receiver actor
persistent actor class B() {
  // types for receiver actor
  type ChunkMessage = Types.ChunkMessage<?Text>;
  type ControlMessage = Types.ControlMessage;

  // processor of received items
  transient let received = List.empty<Text>();
  func processItem(i : Nat, item : ?Text) : Bool {
    let prefix = ".   B   item " # Nat.toText(i) # ": ";
    switch (item) {
      case (null) Debug.print(prefix # "null");
      case (?x) {
        Debug.print(prefix # x);
        received.add(x);
      };
    };
    true;
  };

  // StreamReceiver
  transient let receiver = StreamReceiver.StreamReceiver<?Text>(
    processItem,
    null,
  );

  // required top-level boilerplate code,
  // a pass-through to StreamReceiver
  public func receive(m : ChunkMessage) : async ControlMessage {
    let start = m.0;
    var end = m.0;
    var str = ".   B recv: (" # Nat.toText(m.0) # ", ";
    switch (m.1) {
      case (#ping) str #= "ping";
      case (#chunk e) {
        str #= "chunk [" # Nat.toText(e.size()) # "]";
        end := start + e.size();
      };
      case (#restart) str #= "restart";
    };
    Debug.print(str # ")");
    str := ".   B reply: ";
    // The fail mode is used to simulate artifical Errors.
    let res = switch (mode) {
      case (#off) receiver.onChunk(m);
      case (#reject) {
        Debug.print(str # "reject");
        throw Error.reject("failMode");
      };
      case (#stop) #stop 0;
    };
    switch (res) {
      case (#ok) str #= "#ok";
      case (#gap) str #= "#gap";
      case (#stop _) str #= "#stop";
    };
    Debug.print(str);
    res;
  };

  // query the items processor
  public query func listReceived() : async [Text] {
    List.toArray(received);
  };
  public query func nReceived() : async Nat {
    received.size();
  };

  // simulate Errors
  type FailMode = { #off; #reject; #stop };
  transient var mode : FailMode = #off;
  public func setFailMode(m : FailMode, n : Nat) : async () {
    if (n > 0) await setFailMode(m, n - 1) else {
      var str = ".   B failMode: ";
      switch (m) {
        case (#off) str #= "off";
        case (#reject) str #= "reject";
        case (#stop) str #= "stopped";
      };
      Debug.print(str);
      mode := m;
    };
  };
};