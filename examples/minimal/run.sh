#!/bin/sh

icp canister call alice enqueue '(7)'

for i in 1 2 3 4
do
  icp canister call alice batch '()'
  icp canister call bob log '()'
done
