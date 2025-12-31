import StreamReceiver "../src/StreamReceiver";
import StreamSender "../src/StreamSender";
import { StreamReceiver = Receiver } "../src/StreamReceiver";
import { StreamSender = Sender } "../src/StreamSender";
import List "mo:core/List";
import Debug "mo:core/Debug";
import Nat "mo:core/Nat";
import Result "mo:core/Result";
import Types "../src/types";

type ChunkMessage = Types.ChunkMessage<?Text>;
type ControlMessage = Types.ControlMessage;
type Sender<T, S> = StreamSender.StreamSender<T, S>;
type Receiver<S> = StreamReceiver.StreamReceiver<S>;

func createReceiver() : Receiver<?Text> {
  let received = List.empty<?Text>();

  let receiver = Receiver<?Text>(
    func(pos : Nat, item : ?Text) : Bool {
      received.add(item);
      received.size() == pos + 1;
    },
    null,
  );
  receiver;
};

func createSender(receiver : Receiver<?Text>) : Sender<Text, ?Text> {
  let MAX_LENGTH = 5;

  func counter() : { accept(Text) : ??Text } {
    var sum = 0;
    {
      accept = func(item : Text) : ??Text {
        let (wrapped_item, wrapped_size) = if (item.size() <= MAX_LENGTH) {
          (?item, item.size());
        } else {
          (null, 0);
        };
        sum += wrapped_size;
        if (sum <= MAX_LENGTH) ?wrapped_item else null;
      };
    };
  };

  func send(ch : ChunkMessage) : async* ControlMessage { receiver.onChunk(ch) };

  let sender = Sender<Text, ?Text>(send, counter);
  sender;
};

do {
  let receiver = createReceiver();
  let sender = createSender(receiver);

  ignore sender.push("abc");
  ignore sender.push("abcdef");
  ignore sender.push("abc");
  ignore sender.push("def");
  ignore sender.push("get");
  ignore sender.push("nmb");
  ignore sender.push("abc");
  ignore sender.push("abc");
  ignore sender.push("abc");

  let n = sender.length();

  var i = 0;
  let max = 100;
  while (sender.received() < n and i < max) {
    await* sender.sendChunk();
    i += 1;
  };
  Debug.print("sent " # Nat.toText(i) # " chunks");
  assert i != max;
};

do {
  let receiver = createReceiver();
  let sender = createSender(receiver);

  let MAX_LENGTH = 3;
  receiver.setMaxLength(?MAX_LENGTH);
  sender.setMaxStreamLength(?(MAX_LENGTH + MAX_LENGTH));

  Result.assertOk(sender.push("abc"));
  Result.assertOk(sender.push("abcde"));
  Result.assertOk(sender.push("ac"));
  Result.assertOk(sender.push("abc"));
  Result.assertOk(sender.push("abcde"));
  Result.assertOk(sender.push("ac"));
  Result.assertErr(sender.push("d"));

  var i = 0;
  let max = 100;
  while (sender.status() == #ready and i < max) {
    await* sender.sendChunk();
    i += 1;
  };

  assert receiver.length() == MAX_LENGTH;
};
