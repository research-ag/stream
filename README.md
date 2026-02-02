[![mops](https://oknww-riaaa-aaaam-qaf6a-cai.raw.ic0.app/badge/mops/stream)](https://mops.one/stream)
[![documentation](https://oknww-riaaa-aaaam-qaf6a-cai.raw.ic0.app/badge/documentation/stream)](https://mops.one/stream/docs)

# An ordered stream of messages between two canisters

## Overview

Suppose canister `A` wants to send canister `B` a stream of messages.
The messages in the stream are ordered and should be processed by `B` in that order.
This package provides an implementation of a protocol for this purpose.
The protocol has the following properties:

* efficiency: messages from `A` are sent in batches to `B`
* order: preservation of order is guaranteed
* no gaps: messages are retried if needed to make sure there are no gaps in the stream

The package provides two classes, `StreamSender` for `A` and `StreamReceiver` for `B`.
In `A`, the canister code pushes items one by one to the `StreamSender` class.
In `B`, the `StreamReceiver` class invokes a callback for each arrived item.
The two classes manage everything in between including batching, 
retries if any inter-canister calls fail and 
managing concurrency (pipelining). 

From the outside the protocol provides ordered, reliable messaging similar to TCP.
The implementation is simpler than TCP.
For example, the only state maintained by the receiver is the stream position (a single integer).
In case of a gap, the receiver does not buffer items after the gap.
Instead, the sender will automatically retry those items.

## Links

The package is published on [MOPS](https://mops.one/stream) and [GitHub](https://github.com/research-ag/stream).
Please refer to the README on GitHub where it renders properly with formulas and tables.

The API documentation can be found [here](https://mops.one/stream/docs/lib) on Mops.

For updates, help, questions, feedback and other requests related to this package join us on:

* [OpenChat group](https://oc.app/2zyqk-iqaaa-aaaar-anmra-cai)
* [Twitter](https://twitter.com/mr_research_ag)
* [Dfinity forum](https://forum.dfinity.org/)

## Motivation

Reliable, asynchronous communication between canisters is hard to get right because of the many edge cases that can occur if inter-canister calls fail.
The purpose of this package is to hide that complexity from the developer
by letting this library handle all of it.

## Interface

### `StreamSender` 

Before instantiating the class, the user needs to define a function `sendFunc` that makes an inter-canister call to the receiver and calls a corresponding receiving endpoint. 
This is boilerplate code and is usually a one-line function.
Sender and receiver have to a agree on the name of the endpoint.

The `StreamSender` forms each batch by taking unsent items from its internal queue.
The user has a way to control the batch size beyond simply defining a maximum number of item per batch.
For example, the user may want to count the byte size of the items in a batch
and limit the size of a batch by byte size.
This will allow him to make better use of the total available message size in inter-canister communication. 

To this end, the user provides a `counterCreator` function (typically a class constructor).
The `StreamSender` uses it to create a new counter instance for each batch.
It then feeds the items one-by-one to the counter's `accept` function before adding them to the batch.
When the `accept` function returns `null` then it stops
and considers the batch as "full".

Moreover, as an advanced feature,
the counter can also transform the item from one type to a different type
and the transformed type goes into the batch.
In other words, the type of the items in the queue can differ from the type of the items in the batch.

`sendFunc` and `counterCreator` must be passed to the `StreamSender` constructor.

The `StreamSender` has four more settings that can be set dynamically at runtime via setter functions.
  * `maxQueueSize`: the maximum number of elements that can simultaneously be in `StreamSender`'s queue. Default setting is infinity.
  * `maxWindowSize`: the maximum number of concurrent `sendChunk` calls. Default setting is 5.
  * `keepAliveSeconds`: the period in seconds after which `StreamSender` should send a ping chunk in case there are no items to send. Default setting is not to ping.
  * `maxStreamLength`: the maximum number of items a stream can ever accept. Default setting is infinity.  

Methods:

* `push` is used to add item to the stream.
* `status` to check current status of stream sender.
* `sendChunk` to trigger sending a chunk to the receiver side.
* additional helper functions are provided.

`StreamReceiver` requires the following arguments in its constructor:

* `itemCallback` is the function that will be called on each individual received item.
* `timeoutArg` defines if the stream should be stopped if too much time passes between two consecutive `onChunk` calls. `null` means no timeout. Otherwise a duration and the time retrieval function are supplied.

The method `onChunk` of the `StreamReceiver` must be connected with an endpoint of the receiver canister.
It must be called with each arriving chunk from the sender.

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

This example is taken from `examples/minimal`.

```
import Stream "../../../src/StreamSender";
import Principal "mo:core/Principal";

persistent actor class Alice(bob : Principal) {
  // Substitute your item type here
  type Item = Nat;

  // The endpoint (update method) on Bob's side must have this type:
  type RecvFunc = shared Stream.ChunkMessage<Item> -> async Stream.ControlMessage;
  
  // The endpoint (update method) on Bob's side is called "receive" in this example.
  // Hence, this is the actor supertype for Bob that we use:
  type ReceiverAPI = actor { receive : RecvFunc };

  // This is Bob, the receiving actor whose Principal was supplied in the init argument:
  transient let B : ReceiverAPI = actor (Principal.toText(bob));

  // This is our `sendFunc` which is simply a wrapper around Bob's `receive` method.  
  // It is possible to wrap custom code around calling `B.receive` but we must not tamper  
  // with the response and we must not trap.
  transient let send_ = func(x : Stream.ChunkMessage<Item>) : async* Stream.ControlMessage {
    await B.receive(x)
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
```

### Example of receiver

This example is taken from `examples/minimal`.

```
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
```

### Build & test

Run
```
git clone git@github.com:research-ag/sha2.git
mops install
mops test
```

## Design

## Implementation notes

## Copyright

MR Research AG, 2023 - 2026

## Authors

Main author: Timo Hanke (timohanke).

Contributors: Andrii Stepanov (AStepanov25), Andy Gura (AndyGura).

## License 

Apache-2.0
