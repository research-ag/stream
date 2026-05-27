# StreamReceiver

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

## Type `StableData`

```motoko no-repl
type StableData = (Nat, Int, Bool)

```

Type of `StableData` for `share`/`unshare` function.
Stream length, last chunk received timestamp, stopped flag.

## Type `Callbacks`

```motoko no-repl
type Callbacks = {
  var onChunk : (Types.ChunkMessageInfo, ControlMessage) -> ();
};

```

Callbacks called during processing chunk.

## Class `StreamReceiver<T>`

```motoko no-repl
class StreamReceiver<T>(itemCallback : (pos : Nat, item : T) -> (), timeoutArg : ?(Nat, () -> Int));

```

StreamReceiver

- receives chunk by `onChunk` call
- validates `start` position in ChunkMessage (must match internal `length` variable)
- calls `itemCallback` for each item of the chunk.

Constructor arguments:

- `itemCallback` function
- `timeout` is maximum waiting time between onChunk calls (default = infinite)

### Value `callbacks`

```motoko no-repl
let callbacks : Callbacks

```

Callbacks called during processing chunk.

### Function `share`

```motoko no-repl
func share() : StableData

```

Share data in order to store in stable variable. No validation is performed.

### Function `unshare`

```motoko no-repl
func unshare(data : StableData)

```

Unhare data in order to store in stable variable. No validation is performed.

### Function `onChunk`

```motoko no-repl
func onChunk(cm : Types.ChunkMessage<T>) : Types.ControlMessage

```

Returns `#gap` if start position in ChunkMessage does not match internal length.
Returns `#stopped` if the receiver is already stopped or maximum waiting time between chunks is exceeded.
Otherwise processes a chunk and call `itemCallback` on each item.
A #ping message is handled equivalently to a #chunk of length zero.

### Function `stop`

```motoko no-repl
func stop()

```

Manually stop the receiver.

### Function `length`

```motoko no-repl
func length() : Nat

```

Current number of received items.

### Function `lastChunkReceived`

```motoko no-repl
func lastChunkReceived() : Int

```

Timestamp when stream received last chunk

### Function `isStopped`

```motoko no-repl
func isStopped() : Bool

```

Flag if receiver is stopped (manually or by inactivity timeout)
