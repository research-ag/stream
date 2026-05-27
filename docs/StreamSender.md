# StreamSender

## Type `Status`

```motoko no-repl
type Status = { #shutdown; #stopped; #paused; #busy; #ready }

```

Status of `StreamSender`.

## Type `ControlMessage`

```motoko no-repl
type ControlMessage = Types.ControlMessage

```

Return type of processing function.

## Type `ChunkMessage`

```motoko no-repl
type ChunkMessage<T> = Types.ChunkMessage<T>

```

Argument of processing function.

## Value `MAX_CONCURRENT_CHUNKS_DEFAULT`

```motoko no-repl
let MAX_CONCURRENT_CHUNKS_DEFAULT

```

Maximum concurrent chunks number.

## Type `Settings`

```motoko no-repl
type Settings = {
  var maxQueueSize : ?Nat;
  var windowSize : Nat;
  var keepAlive : ?(Nat, () -> Int);
};

```

Settings of `StreamSender`.

## Type `StableData`

```motoko no-repl
type StableData<T> = {
  buffer : SWB.StableData<T>;
  stopped : Bool;
  head : Nat;
  lastChunkSent : Int;
  shutdown : Bool;
};

```

Type of `StableData` for `share`/`unshare` function.

## Type `Callbacks`

```motoko no-repl
type Callbacks = {
  var onNoSend : () -> ();
  var onSend : Types.ChunkInfo -> ();
  var onError : Error.Error -> ();
  var onResponse : (Types.ControlMessage or { #error }) -> ();
  var onRestart : () -> ();
};

```

Callbacks called in different places of sending chunk.

## Class `StreamSender<Q, S>`

```motoko no-repl
class StreamSender<Q, S>(sendFunc : (x : Types.ChunkMessage<S>) -> async* Types.ControlMessage, counterCreator : () -> { accept : (item : Q) -> ?S });

```

Stream sender receiving items of type `Q` with `push` function and sending them with `sendFunc` callback when calling `sendChunk`.

Arguments:

- `sendFunc` typically should implement sending chunk to the receiver canister.
- `counterCreator` is used to create a chunk out of pushed items.
  `accept` function is called sequentially on items which are added to the chunk, until receiving `null`.
  If the item is accepted it should be converted to type `S`.
  Typical implementation of `counter` is to accept items while their total size is less then given maximum chunk size.

### Value `callbacks`

```motoko no-repl
let callbacks : Callbacks

```

Callbacks called during sending chunk.

### Function `share`

```motoko no-repl
func share() : StableData<Q>

```

Share data in order to store in stable varible. No validation is performed.

### Function `unshare`

```motoko no-repl
func unshare(data : StableData<Q>)

```

Unhare data in order to store in stable varible. No validation is performed.

### Function `push`

```motoko no-repl
func push(item : Q) : Result.Result<Nat, { #NoSpace }>

```

Add item to the `StreamSender`'s queue. Return number of succesfull `push` call, or error in case of lack of space.

### Function `status`

```motoko no-repl
func status() : Status

```

Get the stream sender's status for inspection.

The function is sychronous. It can be used (optionally) by the user of
the class before calling the asynchronous function sendChunk.

sendChunk will attempt to send a chunk if and only if the status is
`#ready`. sendChunk will throw if and only if the status is `#shutdown`, `#stopped`,
`#paused` or `#busy`.

`#shutdown` means irrecoverable error ocurred during the work process of `StreamSender`.

`#stopped` means that the stream sender was stopped by the receiver, e.g.
due to a timeout.

`#paused` means that at least one chunk could not be delivered and the
stream sender is waiting for outstanding responses to come back before
it can resume sending chunks. When it resumes it will start from the
first item that did not arrive.

`#busy` means that there are too many chunk concurrently in flight. The
sender is waiting for outstanding responses to come back before sending
any new chunks.

`#ready` means that the stream sender is ready to send a chunk.

### Function `sendChunk`

```motoko no-repl
func sendChunk() : async* ()

```

Send chunk to the receiver.

A return value `()` means that the stream sender was ready to send the
chunk and attempted to send it. It does not mean that the chunk was
delivered to the receiver.

If the stream sender is not ready (shutdown, stopped, paused or busy) then the
function throws immediately and does not attempt to send the chunk.

### Function `restart`

```motoko no-repl
func restart() : async Bool

```

Restart the sender in case it's stopped after receiving `#stop` from `sendFunc`.

### Function `maxQueueSize`

```motoko no-repl
func maxQueueSize() : ?Nat

```

Get `maxQueueSize` setting.
`maxQueueSize` is maximum number of elements, which can simultaneously be in `StreamSender`'s queue. Default value is infinity.

### Function `windowSize`

```motoko no-repl
func windowSize() : Nat

```

Get `windowSize` setting.
`windowSize` is maximum number of concurrent `sendChunk` calls. Default value is `MAX_CONCURRENT_CHUNKS_DEFAULT`.

### Function `keepAliveTime`

```motoko no-repl
func keepAliveTime() : ?Nat

```

Get `keepAlive` setting.
`keepAlive` is pair of period in seconds after which `StreamSender` should send ping chunk in case if there is no items to send and current time function.
Default value means not to ping.

### Function `setMaxQueueSize`

```motoko no-repl
func setMaxQueueSize(n : ?Nat)

```

Update max queue size.
`maxQueueSize` is maximum number of elements, which can simultaneously be in `StreamSender`'s queue. Default value is infinity.

### Function `setWindowSize`

```motoko no-repl
func setWindowSize(n : Nat)

```

Update max amount of concurrent outgoing requests.
`windowSize` is maximum number of concurrent `sendChunk` calls. Default value is `MAX_CONCURRENT_CHUNKS_DEFAULT`.

### Function `setKeepAlive`

```motoko no-repl
func setKeepAlive(seconds : ?(Nat, () -> Int))

```

Update max interval between stream calls.
`keepAlive` is pair of period in seconds after which `StreamSender` should send ping chunk in case if there is no items to send and current time function.
Default value means not to ping.

### Function `lastChunkSent`

```motoko no-repl
func lastChunkSent() : Int

```

Last chunk sent time

### Function `length`

```motoko no-repl
func length() : Nat

```

Total amount of items, ever added to the stream sender.
Equals the index which will be assigned to the next item.

### Function `queueSize`

```motoko no-repl
func queueSize() : Nat

```

Internal queue size

### Function `sent`

```motoko no-repl
func sent() : Nat

```

Amount of items, which were sent to receiver.

### Function `received`

```motoko no-repl
func received() : Nat

```

Amount of items, successfully sent and acknowledged by receiver.

### Function `get`

```motoko no-repl
func get(index : Nat) : ?Q

```

Get item from queue by index.

### Function `isReady`

```motoko no-repl
func isReady() : Bool

```

Returns flag is sender is ready.

### Function `isShutdown`

```motoko no-repl
func isShutdown() : Bool

```

Returns flag is sender has shut down.

### Function `isStopped`

```motoko no-repl
func isStopped() : Bool

```

Returns flag is receiver stopped the stream.

### Function `isBusy`

```motoko no-repl
func isBusy() : Bool

```

Check busy status of sender.

### Function `busyLevel`

```motoko no-repl
func busyLevel() : Nat

```

Check busy level of sender, e.g. current amount of outgoing calls in flight.

### Function `isPaused`

```motoko no-repl
func isPaused() : Bool

```

Check paused status of sender.
