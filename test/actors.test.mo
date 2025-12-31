import Debug "mo:core/Debug";
import A "A";
import B "B";

let b = await B.B();
let a = await A.A(b);

// Part 1: messages arrive and return one by one
Debug.print("=== Part 1 ===");
assert ((await a.submit("m0")) == #ok 0);
assert ((await a.submit("m1")) == #ok 1);
assert ((await a.submit("m2xxx")) == #ok 2);
assert ((await a.submit("m3-long")) == #ok 3);
assert ((await a.submit("m4-long")) == #ok 4);
assert ((await a.submit("m5")) == #ok 5);
assert await a.isState([6, 0, 0, 0]);
assert ((await b.nReceived()) == 0);
ignore a.trigger(); // chunk m0, m1
assert await a.isState([6, 2, 0, 1]); // chunk was sent
assert await a.isState([6, 2, 2, 0]); // chunk has returned ok
assert ((await b.nReceived()) == 2);
await b.setFailMode(#reject, 0);
ignore a.trigger(); // chunk m2,null,null will fail
assert await a.isState([6, 5, 2, 1]); // chunk was sent
assert await a.isState([6, 2, 2, 0]); // chunk has returned rejected
ignore a.trigger(); // chunk m2,null,null will fail
assert await a.isState([6, 5, 2, 1]); // chunk was sent
assert await a.isState([6, 2, 2, 0]); // chunk has returned rejected
assert ((await b.nReceived()) == 2);
await b.setFailMode(#off, 0);
ignore a.trigger(); // chunk m2,null,null will succeed
assert await a.isState([6, 5, 2, 1]); // chunk was sent
assert await a.isState([6, 5, 5, 0]); // chunk has returned ok
assert ((await b.nReceived()) == 3);
ignore a.trigger(); // chunk m5
assert await a.isState([6, 6, 5, 1]); // chunk was sent
assert await a.isState([6, 6, 6, 0]); // chunk has returned ok
assert ((await b.nReceived()) == 4);
await a.trigger(); // no items left
assert ((await b.nReceived()) == 4);
let list : [Text] = await b.listReceived();
assert (list[0] == "m0");
assert (list[1] == "m1");
assert (list[2] == "m2xxx");
assert (list[3] == "m5");

// Part 2: second message sent out before first one returns
Debug.print("=== Part 2 ===");
assert ((await a.submit("m6xxx")) == #ok 6);
assert ((await a.submit("m7xxx")) == #ok 7);
assert await a.isState([8, 6, 6, 0]);
ignore a.trigger();
let a1 = a.isState([8, 7, 6, 1]);
ignore a.trigger();
let a2 = a.isState([8, 8, 6, 2]);
await async {};
// here the two chunks have returned with ok
let a3 = a.isState([8, 8, 8, 0]);
await async {};
assert await a1;
assert await a2;
assert await a3;

// Part 3: test broken pipe behaviour
Debug.print("=== Part 3 ===");
assert ((await a.submit("m8")) == #ok 8);
assert ((await a.submit("m9")) == #ok 9);
assert ((await a.submit("mA")) == #ok 10);
assert ((await a.submit("mB")) == #ok 11);
assert await a.isState([12, 8, 8, 0]);
ignore b.setFailMode(#reject, 0);
ignore a.trigger();
let b1 = a.isState([12, 10, 8, 1]);
ignore b.setFailMode(#off, 1);
ignore a.trigger();
let b2 = a.isState([12, 12, 8, 2]);
await async {};
// here the two chunks have returned with rejects
let b3 = a.isState([12, 8, 8, 0]);
assert await b1;
assert await b2;
assert await b3;
ignore a.trigger();
ignore a.trigger();
await async {};
assert await a.isState([12, 12, 12, 0]);

assert not (await a.isShutdown());
