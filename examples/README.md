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
