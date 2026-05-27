# Tracker

## Class `Receiver`

```motoko no-repl
class Receiver(metrics : PT.PromTracker, stable_ : Bool)

```

Receiver tracker.

### Function `init`

```motoko no-repl
func init(receiver : ReceiverInterface)

```

### Function `onChunk`

```motoko no-repl
func onChunk(info : Types.ChunkMessageInfo, ret : Types.ControlMessage)

```

## Class `Sender`

```motoko no-repl
class Sender(metrics : PT.PromTracker, stable_ : Bool)

```

Sender tracker.

### Function `init`

```motoko no-repl
func init(sender : SenderInterface)

```

### Function `onSend`

```motoko no-repl
func onSend(c : Types.ChunkInfo)

```

### Function `onNoSend`

```motoko no-repl
func onNoSend()

```

### Function `onError`

```motoko no-repl
func onError(e : Error.Error)

```

### Function `onResponse`

```motoko no-repl
func onResponse(res : { #ok; #gap; #stop; #error })

```

### Function `onRestart`

```motoko no-repl
func onRestart()

```
