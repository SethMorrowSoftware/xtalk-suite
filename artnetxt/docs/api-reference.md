# artnetxt API reference

The 5 public handlers of the `artnet` library, from the doc blocks in `src/artnet.lcb` (the IDE
dictionary reads the same blocks; `tools/build-api-reference.py` writes this file from them,
and its `--check` is a gate). Read [getting-started.md](getting-started.md) first.

## Output: ArtDmx

### `artnetBuildDmx`

`artnetBuildDmx(in pUniverse as Integer, in pChannels as Data) returns Data`

Builds one ArtDmx packet: the levels of one DMX universe, ready to send.

- pUniverse: The universe (the 15-bit Port-Address), 0 to 32767.
- pChannels: The levels as binary data, one byte (0 to 255) per DMX channel, channel 1 first, up to 512 of them.

Returns: The packet as binary data, or empty when the universe is out of range.

The packet carries an even number of channels from 2 to 512, as the Art-Net specification asks: fewer than 2 levels, or an odd number, are padded with level 0, and anything past 512 is left out. A universe outside 0 to 32767 builds nothing: the result is empty and `artnetLastError` says why. A fractional universe is cut toward zero.

```livecodescript
local tLevels
put numToByte(255) & numToByte(128) & numToByte(0) into tLevels
open datagram socket to "192.168.1.50:6454"
write artnetBuildDmx(0, tLevels) to socket "192.168.1.50:6454"
```

## Input: ArtDmx

### `artnetParseDmx`

`artnetParseDmx(in pData as Data) returns Array`

Reads an ArtDmx packet: the levels of one universe that arrived as bytes.

- pData: The bytes of one datagram.

Returns: An array: "opcode" ("ArtDmx"), "universe" (0 to 32767 for a well-formed packet), "net" and "subuni" (the two bytes the universe is made of), "sequence", "physical", "length" (the number of channels) and "channels" (the levels as binary data, channel 1 first). For bytes that are not an ArtDmx packet, "opcode" is empty and `artnetLastError` says why.

A packet whose Length field claims more channels than arrived, or more than 512, is read as far as its bytes go and no further: "length" is the number of levels in "channels".

```livecodescript
put artnetParseDmx(pData) into tFrame
if tFrame["opcode"] is "ArtDmx" and tFrame["universe"] is 0 then
   put byteToNum(byte 1 of tFrame["channels"]) into tLevelOfChannel1
end if
```

## Discovery: ArtPoll / ArtPollReply

### `artnetBuildPoll`

`artnetBuildPoll() returns Data`

Builds an ArtPoll packet, which asks every Art-Net node to say who it is.

Returns: The packet as binary data.

Broadcast it to port 6454 (the engine sends a broadcast only after `set the allowDatagramBroadcasts to true`), or send it to one node's address. Each node answers with an ArtPollReply, which `artnetParseReply` reads. Nodes answer to port 6454 of the computer that asked, so listen there: `accept datagram connections on port 6454 with message ...`.

```livecodescript
set the allowDatagramBroadcasts to true
open datagram socket to "255.255.255.255:6454"
write artnetBuildPoll() to socket "255.255.255.255:6454"
```

### `artnetParseReply`

`artnetParseReply(in pData as Data) returns Array`

Reads an ArtPollReply packet: one node's answer to an ArtPoll.

- pData: The bytes of one datagram.

Returns: An array: "opcode" ("ArtPollReply"), "ip" (the node's address, such as "2.0.0.10"), "port" (6454), "shortName", "longName", "nodeReport" (the node's status text), "net" and "subuni" (its Net and Sub-Net switches), "outputUniverses" and "inputUniverses" (lists of the universes its DMX output and input ports use), "mac" (such as "00:1a:2b:3c:4d:5e"), "style" (0 for a node, 1 for a controller, 2 for a media server), "bindIndex" and "version" (its firmware version). For bytes that are not an ArtPollReply, "opcode" is empty and `artnetLastError` says why.

Send DMX for a node's output port to one of its "outputUniverses". A node with more than four ports answers once per group of four; "bindIndex" tells the answers apart.

```livecodescript
put artnetParseReply(pData) into tNode
if tNode["opcode"] is "ArtPollReply" then
   put tNode["shortName"] && "at" && tNode["ip"] into line (the number of lines of field "Nodes" + 1) of field "Nodes"
end if
```

## Shared

### `artnetLastError`

`artnetLastError() returns String`

Says why the last call of this library built or read nothing.

Returns: The reason, or empty when the last call succeeded.

Every other handler of this library clears it when it starts, so it always describes the most recent call.

```livecodescript
put artnetBuildDmx(tUniverse, tLevels) into tPacket
if tPacket is empty then answer artnetLastError()
```
