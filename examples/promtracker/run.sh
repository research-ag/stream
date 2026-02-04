#!/bin/sh
set -e

icp canister call sender add '("abc")'
icp canister call receiver lastReceived '()'
icp canister call sender add '("def")'
icp canister call receiver lastReceived '()'
icp canister call sender add '("ghi")'
icp canister call receiver lastReceived '()'
icp canister call sender add '("jkl")'
icp canister call receiver lastReceived '()'
icp canister call sender add '("mno")'
icp canister call receiver lastReceived '()'
icp canister call sender add '("pqr")'
icp canister call receiver lastReceived '()'

#icp canister call sender http_request '(record { method = "GET"; url = "/metrics"; headers = vec {}; body = blob "" })'
