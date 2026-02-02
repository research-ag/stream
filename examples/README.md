# How to run the examples locally

Have a local replica running with `dfx start --background --clean`.

Inside the example's directory (`main` or `minimal` or `promtracker`) run:

```sh
dfx build --check
./run.sh
```

# Examples

## Minimal

Minimal code required to get a sender and a receiver talking to each other.

## Main

Compared to the example above this demonstrates:
* how a more sophisticated counter for batch preparation can look like
* how queue type can differ from sending type
* how to send chunks from heartbeat

## Promtracker

Example to show using trackers along with streams.
