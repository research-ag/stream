import Types "../../src/internal/types";
import Debug "mo:core/Debug";

// Test ChunkPayload types
do {
  let chunkPayload : Types.ChunkPayload<Text> = #chunk(["a", "b", "c"]);
  let pingPayload : Types.ChunkPayload<Text> = #ping;

  // Verify types are properly defined
  switch (chunkPayload) {
    case (#chunk arr) assert arr.size() == 3;
    case (#ping) assert false;
  };

  switch (pingPayload) {
    case (#chunk _) assert false;
    case (#ping) {};
  };
};

// Test ChunkInfo conversion
do {
  let chunkPayload : Types.ChunkPayload<Text> = #chunk(["a", "b", "c"]);
  let chunkInfo = Types.chunkInfo(chunkPayload);

  switch (chunkInfo) {
    case (#chunk size) assert size == 3;
    case (#ping) assert false;
  };

  let pingPayload : Types.ChunkPayload<Text> = #ping;
  let pingInfo = Types.chunkInfo(pingPayload);

  switch (pingInfo) {
    case (#chunk _) assert false;
    case (#ping) {};
  };
};

// Test ChunkMessage types
do {
  let chunkMessage : Types.ChunkMessage<Text> = (5, #chunk(["a", "b"]));
  let pingMessage : Types.ChunkMessage<Text> = (10, #ping);
  let restartMessage : Types.ChunkMessage<Text> = (0, #restart);

  // Verify position and payload
  assert chunkMessage.0 == 5;
  assert pingMessage.0 == 10;
  assert restartMessage.0 == 0;

  switch (chunkMessage.1) {
    case (#chunk arr) assert arr.size() == 2;
    case (#ping or #restart) assert false;
  };

  switch (pingMessage.1) {
    case (#chunk _ or #restart) assert false;
    case (#ping) {};
  };

  switch (restartMessage.1) {
    case (#chunk _ or #ping) assert false;
    case (#restart) {};
  };
};

// Test ChunkMessageInfo conversion
do {
  let chunkMessage : Types.ChunkMessage<Text> = (5, #chunk(["a", "b", "c"]));
  let chunkMessageInfo = Types.chunkMessageInfo(chunkMessage);

  assert chunkMessageInfo.0 == 5;
  switch (chunkMessageInfo.1) {
    case (#chunk size) assert size == 3;
    case (#ping or #restart) assert false;
  };

  let pingMessage : Types.ChunkMessage<Text> = (10, #ping);
  let pingMessageInfo = Types.chunkMessageInfo(pingMessage);

  assert pingMessageInfo.0 == 10;
  switch (pingMessageInfo.1) {
    case (#chunk _) assert false;
    case (#ping) {};
    case (#restart) assert false;
  };

  let restartMessage : Types.ChunkMessage<Text> = (0, #restart);
  let restartMessageInfo = Types.chunkMessageInfo(restartMessage);

  assert restartMessageInfo.0 == 0;
  switch (restartMessageInfo.1) {
    case (#chunk _ or #ping) assert false;
    case (#restart) {};
  };
};

// Test ControlMessage types
do {
  let okMessage : Types.ControlMessage = #ok;
  let gapMessage : Types.ControlMessage = #gap;
  let stopMessage : Types.ControlMessage = #stop 5;

  switch (okMessage) {
    case (#ok) {};
    case (#gap or #stop _) assert false;
  };

  switch (gapMessage) {
    case (#gap) {};
    case (#ok or #stop _) assert false;
  };

  switch (stopMessage) {
    case (#stop n) assert n == 5;
    case (#ok or #gap) assert false;
  };
};

// Test ChunkInfo with empty chunk
do {
  let emptyChunk : Types.ChunkPayload<Text> = #chunk([]);
  let emptyInfo = Types.chunkInfo(emptyChunk);

  switch (emptyInfo) {
    case (#chunk size) assert size == 0;
    case (#ping) assert false;
  };
};

// Test ChunkMessageInfo with empty chunk
do {
  let emptyMessage : Types.ChunkMessage<Text> = (0, #chunk([]));
  let emptyMessageInfo = Types.chunkMessageInfo(emptyMessage);

  assert emptyMessageInfo.0 == 0;
  switch (emptyMessageInfo.1) {
    case (#chunk size) assert size == 0;
    case (#ping or #restart) assert false;
  };
};

// Test ChunkInfo with large chunk
do {
  let largeArray = ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j"];
  let largeChunk : Types.ChunkPayload<Text> = #chunk(largeArray);
  let largeInfo = Types.chunkInfo(largeChunk);

  switch (largeInfo) {
    case (#chunk size) assert size == 10;
    case (#ping) assert false;
  };
};

// Test ChunkMessage with different positions
do {
  let message0 : Types.ChunkMessage<Text> = (0, #chunk(["a"]));
  let message100 : Types.ChunkMessage<Text> = (100, #chunk(["b"]));
  let message1000 : Types.ChunkMessage<Text> = (1000, #ping);

  assert message0.0 == 0;
  assert message100.0 == 100;
  assert message1000.0 == 1000;
};

// Test ControlMessage with different stop values
do {
  let stop0 : Types.ControlMessage = #stop 0;
  let stop1 : Types.ControlMessage = #stop 1;
  let stop100 : Types.ControlMessage = #stop 100;

  switch (stop0) {
    case (#stop n) assert n == 0;
    case (_) assert false;
  };

  switch (stop1) {
    case (#stop n) assert n == 1;
    case (_) assert false;
  };

  switch (stop100) {
    case (#stop n) assert n == 100;
    case (_) assert false;
  };
};

// Test type compatibility with nullable items
do {
  let nullableChunk : Types.ChunkMessage<?Text> = (0, #chunk([?"a", null, ?"c"]));
  let info = Types.chunkMessageInfo(nullableChunk);

  assert info.0 == 0;
  switch (info.1) {
    case (#chunk size) assert size == 3;
    case (_) assert false;
  };
};

// Test ChunkPayload with different generic types
do {
  let natChunk : Types.ChunkPayload<Nat> = #chunk([1, 2, 3]);
  let natInfo = Types.chunkInfo(natChunk);

  switch (natInfo) {
    case (#chunk size) assert size == 3;
    case (#ping) assert false;
  };

  let boolChunk : Types.ChunkPayload<Bool> = #chunk([true, false, true]);
  let boolInfo = Types.chunkInfo(boolChunk);

  switch (boolInfo) {
    case (#chunk size) assert size == 3;
    case (#ping) assert false;
  };
};

// Test equality of ChunkInfo
do {
  let chunk1 : Types.ChunkPayload<Text> = #chunk(["a", "b"]);
  let chunk2 : Types.ChunkPayload<Text> = #chunk(["x", "y"]);
  let info1 = Types.chunkInfo(chunk1);
  let info2 = Types.chunkInfo(chunk2);

  // Both should have size 2
  assert info1 == info2;

  let ping1 : Types.ChunkPayload<Text> = #ping;
  let ping2 : Types.ChunkPayload<Text> = #ping;
  let pingInfo1 = Types.chunkInfo(ping1);
  let pingInfo2 = Types.chunkInfo(ping2);

  assert pingInfo1 == pingInfo2;
};

// Test ChunkMessageInfo preserves position
do {
  let messages = [
    (0, #chunk(["a"])),
    (1, #ping),
    (10, #chunk(["b", "c"])),
    (100, #restart),
  ];

  for (msg in messages.vals()) {
    let info = Types.chunkMessageInfo(msg);
    assert info.0 == msg.0;
  };
};

// Test ControlMessage equality
do {
  let ok1 : Types.ControlMessage = #ok;
  let ok2 : Types.ControlMessage = #ok;
  assert ok1 == ok2;

  let gap1 : Types.ControlMessage = #gap;
  let gap2 : Types.ControlMessage = #gap;
  assert gap1 == gap2;

  let stop1 : Types.ControlMessage = #stop 5;
  let stop2 : Types.ControlMessage = #stop 5;
  assert stop1 == stop2;

  // Different values should not be equal
  assert ok1 != gap1;
  assert ok1 != stop1;
  assert gap1 != stop1;
};

Debug.print("All types tests passed");