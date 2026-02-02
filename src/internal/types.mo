module {
  /// The payload that can be sent per message.
  /// It is a part of the sequence ("chunk") of messages of type `T` that the sender has to send.
  /// If there are no messages to send then a #ping message is sent to keep the connection alive. 
  public type ChunkPayload<T> = { #chunk : [T]; #ping };
  
  /// Info about the chunk payload.
  /// It does not contain the actual payload, only the length of the chunk or that it was a #ping message.
  public type ChunkInfo = { #chunk : Nat; #ping };
  
  /// Convert a ChunkPayload to ChunkInfo
  public func chunkInfo(m : ChunkPayload<Any>) : ChunkInfo {
    switch m {
      case (#chunk c) #chunk(c.size());
      case (#ping) #ping;
    };
  };

  /// The messages that are sent to the receiver.
  /// This contains not only the chunk payload but also the position (starting index) of the chunk in the whole stream.
  /// #ping messages also contain the stream position.
  /// Additionally, a #restart message can be sent to indicate that the sender wants to restart the stream.
  public type ChunkMessage<T> = (Nat, ChunkPayload<T> or { #restart });
  
  /// The ChunkMessage with its payload converted to ChunkInfo.
  public type ChunkMessageInfo = (Nat, ChunkInfo or { #restart });
  
  /// Convert a ChunkMessage to ChunkMessageInfo.
  public func chunkMessageInfo(m : ChunkMessage<Any>) : ChunkMessageInfo {
    (
      m.0,
      switch (m.1) {
        case (#chunk c) #chunk(c.size());
        case (#ping) #ping;
        case (#restart) #restart;
      },
    );
  };

  /// Return type of the receiver's processing function.
  public type ControlMessage = { #ok; #gap; #stop : Nat };
};
