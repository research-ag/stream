# Executable examples to run locally

Install `icp` executable:
```sh
curl --proto '=https' --tlsv1.2 -LsSf https://github.com/dfinity/icp-cli/releases/download/v0.1.0-beta.6/icp-cli-installer.sh | sh
```

Install [node](https://nodejs.org/) (LTS recommended) including `npm`.
Required for `mops`.

Install `mops`:
```sh
npm install -g ic-mops
mops toolchain init
```

Change in the respective example's subdirectory, for example:
```sh
cd examples/minimal
```

Then do:
```sh
icp network start -d
icp deploy
sh run.sh
icp network stop
```

## Minimal

Minimal code required to get a sender and a receiver talking to each other.

## Main

Compared to the example above this demonstrates:

* how a more sophisticated counter for batch preparation can look like
* how queue type can differ from sending type
* how to send chunks from heartbeat
* how to persist the stream across canister upgrades

## Promtracker

Compared to the main example this demonstrates:

* how to use a Tracker connected to a stream
* how to persist the metrics across canister upgrades

You can watch the metrics from a browser at a URL like this:
http://txyno-ch777-77776-aaaaq-cai.raw.localhost:8000/metrics
where `txyno-ch777-77776-aaaaq-cai` is replaced by the canister id
that is shown during `icp deploy`.
