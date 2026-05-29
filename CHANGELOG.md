# Streams changelog

## 0.0.7

### Changed

- Updated `core` from `2.0.0` to `2.5.0`.
- Updated `swb` from `1.2.2` to `1.2.3`.
- Updated `promtracker` to `1.0.1` and adapted to its new API.
- Renamed `Tracker` to `StreamTracker` to not confuse with promtracker's `Tracker`
- Converted `StreamTracker` API from class-based to static module (record type). `SenderTracker` and `ReceiverTracker` are now directly stable.

### Fixed

- Fixed compiler warnings in `src/StreamTracker.mo`.

## 0.0.6

- Demo persistence in promtracker example

## 0.0.5

- Use environment variables in examples
- Replaced dfx with icp-cli
- Update documentation

## 0.0.4

- Bump promtracker dependency
- Simplify promtracker example
- Update README
- Improve documentation in examples

## 0.0.3

- Add documentation
- Update dependencies
- Make internals private

## 0.0.2

- Switch from base to core 2.0.0

## 0.0.1

- Initial version
