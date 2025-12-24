[![mops](https://oknww-riaaa-aaaam-qaf6a-cai.raw.ic0.app/badge/mops/stream)](https://mops.one/stream)
[![documentation](https://oknww-riaaa-aaaam-qaf6a-cai.raw.ic0.app/badge/documentation/stream)](https://mops.one/stream/docs)

# An ordered stream of messages between two canisters

## Overview

Suppose canister A wants to send canister B a stream of messages.
The messages in the stream are ordered and should be processed by B in that order.
This package provides an implementation of a protocol for this purpose.
The protocol has the following properties:

* efficiency: messages from A are sent in batches to B
* order: preservation of order is guaranteed
* no gaps: messages are retried if needed to make sure there are no gaps in the stream

The package provides two classes, `StreamSender` for A and `StreamReceiver` for B.
In A, the canister code pushes items one by one to the StreamSender class.
In B, the StreamReceiver class invokes a callback for each arrived item.
The two classes manage everything in between including batching, 
retries if any inter-canister calls fail and 
managing concurrency (pipelining). 

From the outside the protocol provides ordered, reliable messaging similar to TCP.
The implementation is simler than TCP.
For example, the only state maintained by the receiver is the stream position (a single integer).
The receiver does not buffer later items that have arrived out of order.

## Links

The package is published on [MOPS](https://mops.one/stream) and [GitHub](https://github.com/research-ag/stream).
Please refer to the README on GitHub where it renders properly with formulas and tables.

The API documentation can be found [here](https://mops.one/stream/docs/lib) on Mops.

For updates, help, questions, feedback and other requests related to this package join us on:

* [OpenChat group](https://oc.app/2zyqk-iqaaa-aaaar-anmra-cai)
* [Twitter](https://twitter.com/mr_research_ag)
* [Dfinity forum](https://forum.dfinity.org/)

## Motivation

Reliable, asynchronous communication between canisters is hard to get right because of the many edge cases that can occur if inter-canisters calls fail.
The purpose of this package is to hide that complexity from the developer
by letting this library handle all of it.

## Interface

`StreamSender` requires such argements as:

* `sendFunc` typically should implement sending chunk to the receiver canister.
* `counterCreator` is used to create a chunk out of pushed items.
`accept` function is called sequentially on items which are added to the chunk, until receiving `null`.
If the item is accepted it should be converted to type `S`.
Typical implementation of `counter` is to accept items while their total size is less then given maximum chunk size.
* `settings` consists of:
    * `maxQueueSize` is maximum number of elements, which can simultaneously be in `StreamSender`'s queue. Default value is infinity.
    * `maxConcurrentChunks` is maximum number of concurrent `sendChunk` calls. Default value is `MAX_CONCURRENT_CHUNKS_DEFAULT`.
    * `keepAliveSeconds` is period in seconds after which `StreamSender` should send ping chunk in case if there is no items to send. Default value means not to ping.

Methods:

* `push` is used to add item to the stream.
* `status` to check current status of stream sender.
* `sendChunk` to send chunk to the receiver side.
* additional helper functions are provided.

`StreamReceiver` requires such argements as:

* `startPos` is starting length.
* `timeout` is maximum time between onChunk calls. Default time period is infinite.
* `itemCallback` function to be called on each received item.

Method `onChunk` should be called when receiving chunk from another canister.

## Usage

### Install with mops

You need `mops` installed. In your project directory run:
```
mops add stream
```

In the Motoko source file import the package as:
```
import StreamSender "mo:stream/StreamSender";
import StreamReceiver "mo:stream/StreamReceiver";
```

### Example of sender

```
import Stream "mo:stream/StreamSender";
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
  let sender = Stream.StreamSender<Item, Item>(counter_, send_, null);

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
```

### Example of receiver

```
import Stream "mo:stream/StreamReceiver";
import Error "mo:core/Error";

actor class Main(sender : Principal) {
  // substitute your item type here
  type Item = Nat;

  // define your processing function
  var log_ : Text = "";
  func processItem(index : Nat, item : Item) : () {
    // choose function name, keep the signature
    log_ #= debug_show (index, item) # " "; // put your processing code here
  };

  // begin boilerplate
  let receiver_ = Stream.StreamReceiver<Item>(0, null, processItem); // substitute your processing function for `processItem` 
  public shared (msg) func receive(m : Stream.ChunkMessage<Item>) : async Stream.ControlMessage {
    // choose a name for public endpoint `receive`
    if (msg.caller != sender) throw Error.reject("not authorized"); // use the init argument `sender` here
    receiver_.onChunk(m); // ok to wrap custom code around this
  };
  // end boilerplate

  public func log() : async Text { log_ };
};
```

### Build & test

We need up-to-date versions of `node`, `moc` and `mops` installed.
Suppose `<path-to-moc>` is the path of the `moc` binary of the appropriate version.

Then run:
```
git clone git@github.com:research-ag/stream.git
mops install
DFX_MOC_PATH=<path-to-moc> mops test
```

## Design

## Implementation notes

## Copyright

MR Research AG, 2023 - 2025

## Authors

Main author: Timo Hanke (timohanke).

Contributors: Andrii Stepanov (AStepanov25), Andy Gura (AndyGura).

## License 

Apache-2.0
