import StreamReceiver "../src/StreamReceiver";
import StreamSender "../src/StreamSender";
import { StreamReceiver = Receiver } "../src/StreamReceiver";
import { StreamSender = Sender } "../src/StreamSender";
import List "mo:core/List";
import Debug "mo:core/Debug";
import Nat "mo:core/Nat";
import VarArray "mo:core/VarArray";
import Types "../src/types";
import Base "sender.base";

type ChunkMessage = Types.ChunkMessage<?Text>;
type ControlMessage = Types.ControlMessage;
type Sender<T, S> = StreamSender.StreamSender<T, S>;
type Receiver<S> = StreamReceiver.StreamReceiver<S>;

func createReceiver() : Receiver<?Text> {
  let received = List.empty<?Text>();

  let receiver = Receiver<?Text>(
    func(pos : Nat, item : ?Text) {
      received.add(item);
      received.size() == pos + 1;
    },
    null,
  );
  receiver;
};

func createSender(receiver : Receiver<?Text>) : Sender<Text, ?Text> {
  func send(ch : ChunkMessage) : async* ControlMessage { receiver.onChunk(ch) };

  let sender = Sender<Text, ?Text>(send, Base.create(1));
  sender;
};

let receiver = createReceiver();
let sender = createSender(receiver);

func send() : async () {
  await* sender.sendChunk();
};

let n = 2;
for (i in Nat.range(0, n + 1)) {
  ignore sender.push("a");
};

let result = VarArray.repeat<async ()>(async (), n);

result[0] := send();
await async {};

receiver.stop();

result[1] := send();
await async {};

assert sender.status() == #stopped;
Debug.print(debug_show sender.status());

assert (await sender.restart());
assert not receiver.isStopped();
await async {};

await send();
assert receiver.length() == n;
