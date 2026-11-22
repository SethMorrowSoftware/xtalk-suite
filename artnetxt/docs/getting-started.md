# Getting started with artnetxt

artnetxt sends and receives Art-Net from OpenXTalk (OXT), and from LiveCode 9.6.3 or later.
Art-Net carries DMX512 lighting levels over an ordinary network: a lighting desk, a media
server or your stack sends the levels, and an Art-Net node (a box with DMX sockets on it, or
a fixture with Art-Net built in) turns them into light. artnetxt is a codec: it turns levels
into Art-Net packets and packets back into levels. The network is the engine's own UDP
sockets, so nothing here opens a socket, starts a thread or calls you back.

- [1. Install](#1-install)
- [2. Check that it loaded](#2-check-that-it-loaded)
- [3. Words you will meet](#3-words-you-will-meet)
- [4. Sending levels](#4-sending-levels)
- [5. Levels are bytes: round and clamp](#5-levels-are-bytes-round-and-clamp)
- [6. Receiving levels](#6-receiving-levels)
- [7. Finding the nodes on the network](#7-finding-the-nodes-on-the-network)
- [8. Trying it without a node](#8-trying-it-without-a-node)
- [9. The self-test](#9-the-self-test)
- [Troubleshooting](#troubleshooting)

## 1. Install

artnetxt is pure LiveCode Builder: there is no native library, so there is nothing to build
and nothing that differs between Windows, macOS and Linux. In OXT open **Tools > Extension
Builder**, open `src/artnet.lcb` and press **Package**; **Tools > Extension Manager**
installs the `.lce` it makes. While developing, **Test** in the Extension Builder loads the
`.lcb` in place.

Most stacks also want the helpers: paste `examples/artnet-helpers.livecodescript` into the
stack script (or a library stack you `start using`). Every example below that calls an
`sc...` handler assumes they are there.

## 2. Check that it loaded

```livecodescript
put the number of bytes in artnetBuildPoll()   -- 14: the extension is loaded
```

"handler not found" means the extension is not loaded.

## 3. Words you will meet

- **Channel**: one DMX level, 0 (off) to 255 (full). A dimmer uses one channel; a colour
  LED fixture uses one per colour, and a moving light many more. Channels are numbered from
  1.
- **Universe**: up to 512 channels, the most one DMX cable carries. A node has one or more
  outputs, each set to a universe number.
- **Universe number (Port-Address)**: Art-Net numbers universes 0 to 32767. Desks often
  write them as Net, Sub-Net and Universe ("0:0:1"), and some count from 1, so the desk's
  "universe 1" is often Art-Net's 0. If a node shows nothing, try the universe one lower.

## 4. Sending levels

Keep the universe's levels in a variable, change a channel with `scArtnetSetChannel`, and
send the whole universe with `scArtnetSend`, which builds the packet, opens the datagram
socket the first time and writes it:

```livecodescript
-- in the stack script, with the helpers pasted above it
local sLevels   -- channel 1 is byte 1: the universe's levels, kept between sends

on mouseUp
   scArtnetSetChannel sLevels, 1, 255      -- channel 1 (a dimmer) at full
   scArtnetSetChannel sLevels, 2, 128      -- channel 2 at half
   scArtnetSend "192.168.1.50", 0, sLevels -- universe 0 of the node at that address
end mouseUp
```

`scArtnetSend` sends to port 6454, Art-Net's port; give `"host:port"` for anything else. It
returns empty when the packet went, and the reason when it did not: a universe outside 0 to
32767 builds nothing, and nothing is sent.

**Send on a steady timer, not only when something changes.** DMX refreshes at most about 44
times a second, and a node may treat a universe that stops arriving as lost. A show sends
each universe 30 to 40 times a second:

```livecodescript
local sLevels, sSending

on openCard
   put true into sSending
   sendLights
end openCard

on closeCard
   put false into sSending
end closeCard

on sendLights
   if not sSending then exit sendLights
   scArtnetSend "192.168.1.50", 0, sLevels
   send "sendLights" to me in 25 milliseconds   -- 40 frames a second
end sendLights

on scrollbarDrag pNewPosition
   -- a fader from 0 to 100 drives channel 1; the timer sends it
   scArtnetSetChannel sLevels, 1, pNewPosition * 2.55
end scrollbarDrag
```

By hand, without the helpers, it is `artnetBuildDmx` and the engine's sockets. The engine
only writes to a socket that is OPEN: `write ... to socket "host:port"` on a name never
opened sends nothing and sets the result to "socket is not open".

```livecodescript
local tLevels
put numToByte(255) & numToByte(128) into tLevels
open datagram socket to "192.168.1.50:6454"
write artnetBuildDmx(0, tLevels) to socket "192.168.1.50:6454"
```

## 5. Levels are bytes: round and clamp

A level travels as one byte, and LiveCode Script's `numToByte` does not keep a number in a
byte's range: it WRAPS, so 256 becomes 0, and a light at full goes dark. It also rounds a
fraction or cuts it, depending on where the number came from (a computed 255.6 becomes 0,
the same number held in a variable 255). The helpers round and clamp every level for you
(`scArtnetSetChannel`, `scArtnetOneChannel`); if you build levels yourself, do the same:

```livecodescript
put numToByte(max(0, min(255, round(tLevel)))) after tLevels
```

A channel number outside 1 to 512 is an error the helpers throw, with the reason; a level
that is not a number is too. To read a level back, `scArtnetChannel(sLevels, 4)` answers
channel 4's level, and 0 for a channel past the end.

## 6. Receiving levels

Listen on port 6454 and let `scArtnetReceived` sort what arrives. It calls your handlers in
the object that set up the listening:

```livecodescript
on openCard
   accept datagram connections on port 6454 with message "scArtnetReceived"
   if the result is not empty then answer "Could not listen on 6454:" && the result
end openCard

on closeCard
   close socket "6454"
end closeCard

on scArtnetDmx pUniverse, pChannels, pSender
   if pUniverse is 0 then
      set the thumbPosition of scrollbar "Channel 1" to byteToNum(byte 1 of pChannels)
   end if
end scArtnetDmx
```

`pChannels` holds the levels as bytes, channel 1 first; `pSender` is the sender's
`"address:port"`. Anything that is not Art-Net, an ArtPoll (your own broadcast coming back,
say) and the Art-Net packets artnetxt does not read are ignored.

By hand it is `artnetParseDmx`. The engine calls a datagram message with the sender first
and the data second:

```livecodescript
on dmxArrived pSender, pData
   local tFrame
   put artnetParseDmx(pData) into tFrame
   if tFrame["opcode"] is "ArtDmx" then
      put tFrame["universe"] && tFrame["length"] into field "Last frame"
   end if
end dmxArrived
```

For bytes that are not an ArtDmx, "opcode" is empty and `artnetLastError()` says why.

Only one program on a computer can listen on 6454: with a lighting desk program running on
the same machine, the `accept` fails, and only `the result` says so.

## 7. Finding the nodes on the network

An ArtPoll asks every node to say who it is, and each answers with an ArtPollReply. The
answers come to port 6454 of the computer that asked, so listen there first:

```livecodescript
on mouseUp
   accept datagram connections on port 6454 with message "scArtnetReceived"
   scArtnetPoll    -- broadcast to every node on the network
end mouseUp

on scArtnetNodeFound pNode, pSender
   put pNode["shortName"] && pNode["ip"] && "outputs:" && \
         pNode["outputUniverses"][1] & return after field "Nodes"
end scArtnetNodeFound
```

`scArtnetPoll` with no host broadcasts to 255.255.255.255, and sets
`the allowDatagramBroadcasts` to true, which the engine needs before it sends a broadcast;
give it a subnet's broadcast address ("192.168.1.255", "2.255.255.255") or one node's
address instead. `pNode` is `artnetParseReply`'s array:

| Key | What it is |
|---|---|
| `ip`, `port` | the node's address, and the port it listens on (6454) |
| `shortName`, `longName` | the names the node's owner gave it |
| `nodeReport` | the node's status line, such as "#0001 [0042] Power On Tests successful" |
| `version` | the node's firmware version |
| `outputUniverses`, `inputUniverses` | the universe of each output and input port, numbered from 1 (`the number of elements of pNode["outputUniverses"]` counts them) |
| `net`, `subuni` | the node's switch bytes, as the packet carries them |
| `style` | 0 for a node; other values for desks, media servers and the like |
| `mac`, `bindIndex` | the node's hardware address ("00:1a:2b:3c:4d:5e"), and which of a multi-port device's replies this is |

## 8. Trying it without a node

`tools/sim/artnet_node.py` (Python 3, nothing to install) is a virtual node: it answers
ArtPoll like hardware, and can echo every ArtDmx back on another universe.

```sh
python3 tools/sim/artnet_node.py --port 6455 --name "Desk node" --echo 100
```

The node answers to the address and port a packet came from: the socket the helpers opened
to it. Ask that socket for its datagrams, and the answers arrive through `scArtnetReceived`
like any others:

```livecodescript
local sLevels

on openCard
   scArtnetEnsureSocket "127.0.0.1:6455"
   read from socket "127.0.0.1:6455" with message "scArtnetReceived"
end openCard

on mouseUp
   scArtnetPoll "127.0.0.1:6455"                  -- answered as scArtnetNodeFound
   scArtnetSetChannel sLevels, 1, 200
   scArtnetSend "127.0.0.1:6455", 0, sLevels      -- echoed as scArtnetDmx, universe 100
end mouseUp
```

(Hardware answers ArtPoll to port 6454 instead, which is why section 7 listens there;
`--reply-port 6454` makes the virtual node do the same.)

## 9. The self-test

`examples/artnet-selftest.livecodescript` checks the extension with no lighting gear. Paste
it into a stack or card script and run `put runArtnetSelfTest()` in the Message Box. Tier 1
builds and reads packets back and checks their exact bytes; Tier 2 sends an ArtDmx to the
computer itself over UDP (port 9996) and checks the levels that arrive, a moment after the
tally. An "ArtnetResults" field shows the log when a card is open.

## Troubleshooting

| What you see | Why, and what to do |
|---|---|
| "handler not found" on any `artnet...` call | The extension is not loaded: install the packaged `.lce`, or **Test** `src/artnet.lcb` in the Extension Builder. |
| "handler not found" on an `sc...` call | The helpers are not in the message path: paste `examples/artnet-helpers.livecodescript` into the stack script. |
| A send returns "socket is not open" | Something wrote to a socket it never opened. `scArtnetSend` opens it for you. |
| The node ignores the packets | Check the universe (one lower, if your desk counts from 1), the node's address, and that the node is set to Art-Net, not sACN. Wireshark with the filter `udp.port == 6454` shows what went out. |
| A full light goes dark | A level of 256 or more, or a computed 255.6, went through a bare `numToByte` (section 5). |
| No node answers a poll | Listen on 6454 BEFORE polling; check `the result` of the `accept`; a firewall may block inbound UDP 6454. |
| `artnetBuildDmx` throws a type error | An EMPTY universe: the extension's parameter is a number, and empty is not one. |
