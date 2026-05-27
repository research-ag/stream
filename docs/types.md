# types

## Type `ChunkMessage`

```motoko no-repl
type ChunkMessage<T> = (pos : Nat, { #chunk : [T]; #ping; #restart })

```

Type of messages sent to the receiver

## Type `ChunkMessageInfo`

```motoko no-repl
type ChunkMessageInfo = (pos : Nat, { #chunk : Nat; #ping; #restart })

```

## Function `chunkMessageInfo`

```motoko no-repl
func chunkMessageInfo(m : ChunkMessage<Any>) : ChunkMessageInfo

```

## Type `ChunkPayload`

```motoko no-repl
type ChunkPayload<T> = { #chunk : [T]; #ping }

```

## Type `ChunkInfo`

```motoko no-repl
type ChunkInfo = { #chunk : Nat; #ping }

```

Information passed to callback

## Function `info`

```motoko no-repl
func info(m : ChunkPayload<Any>) : ChunkInfo

```

## Type `ControlMessage`

```motoko no-repl
type ControlMessage = { #ok; #gap; #stop }

```

Return type of processing function.
