import StreamSender "../src/StreamSender";
import Types "../src/types";
import Result "mo:core/Result";
import Array "mo:core/Array";
import Char "mo:core/Char";
import Nat "mo:core/Nat";
import Nat32 "mo:core/Nat32";
import Base "sender.base";

// sequential successful sends, chunk length = 1
do {
  let N = 26;
  let array = Array.tabulate<Text>(N, func(i) = "ab" # Char.toText(Char.fromNat32(Nat32.fromNat(i))));

  var i = 0;
  func send(message : Types.ChunkMessage<?Text>) : async* Types.ControlMessage {
    assert message == (i, #chunk([?array[i]]));
    #ok;
  };

  let sender = StreamSender.StreamSender<Text, ?Text>(
    send,
    Base.create(5),
  );

  for (i in Nat.range(0, N)) {
    Result.assertOk(sender.push(array[i]));
  };

  while (i < N) {
    assert sender.status() == #ready;
    assert sender.sent() == i;
    await* sender.sendChunk();
    i += 1;
  };
};

// sequential successful sends, chunk length = 2
do {
  let N = 26;
  let array = Array.tabulate<Text>(N, func(i) = "ab" # Char.toText(Char.fromNat32(Nat32.fromNat(i))));

  var i = 0;

  func send(message : Types.ChunkMessage<?Text>) : async* Types.ControlMessage {
    assert message == (2 * i, #chunk([?array[2 * i], ?array[2 * i + 1]]));
    #ok;
  };

  let sender = StreamSender.StreamSender<Text, ?Text>(
    send,
    Base.create(6),
  );

  for (i in Nat.range(0, N)) {
    Result.assertOk(sender.push(array[i]));
  };

  while (i < N / 2) {
    assert sender.status() == #ready;
    assert sender.sent() == 2 * i;
    await* sender.sendChunk();
    i += 1;
  };
};

// #stop response
do {
  func send(_ : Types.ChunkMessage<?Text>) : async* Types.ControlMessage {
    #stop 0;
  };

  let sender = StreamSender.StreamSender<Text, ?Text>(
    send,
    Base.create(5),
  );
  Result.assertOk(sender.push("abc"));
  await* sender.sendChunk();
  assert sender.status() == #stopped;
};

// #gap response
do {
  func send(_ : Types.ChunkMessage<?Text>) : async* Types.ControlMessage {
    #gap;
  };

  let sender = StreamSender.StreamSender<Text, ?Text>(
    send,
    Base.create(5),
  );
  Result.assertOk(sender.push("abc"));
  assert sender.status() == #ready;
  assert sender.sent() == 0;
  await* sender.sendChunk();
  assert sender.status() == #shutdown;
  assert sender.sent() == 0;
};
