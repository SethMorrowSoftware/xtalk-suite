script "audioxtDemo"

-- audioxt-demo.livecodescript - Sound Stage, the audioxt showcase.
--
-- A dark stage that opens playing. Five scenes, each a short show of one
-- thing the library does at its best, and each made in script while it
-- runs (nothing here is a recording):
--   1. Beat machine: drums mixed into memory by an offline engine, every
--      hit a clone started on the engine's own clock, the drums one group.
--   2. Round your head: a sound with a place. It circles you, flies past
--      (Doppler), then holds still while you turn round.
--   3. Synth and fades: the four tone shapes gliding through an arpeggio,
--      then a chord that swells and dies away over pink noise.
--   4. A tape made here: two seconds mixed in script into a WAV file,
--      streamed back from disk, played as three clones at once, looped.
--   5. Your microphone: five seconds heard, kept in memory and written to
--      a file at the same time, then played back.
-- Under every scene: what the device is playing (an oscilloscope, from
-- auEngineWaveform) and how loud (auEnginePeak). "Run the checks" runs
-- every check of this window, a few at a time, so the window never stops.
--
-- HOW TO USE (requires the audioxt extension, org.openxtalk.library.audioxt):
-- open audioxt-demo.oxtstack, which examples/build-demo-stack.livecodescript
-- makes from this file, or paste this into a stack's script, then close and
-- reopen that stack (or `send "preOpenStack" to <that stack>`). Opening this
-- file itself loads the script and builds no window: that is the engine
-- (suite engine note 5.5). It plays through the default sound device at
-- once. In a web browser the sound starts with your first click or key
-- press, which is the browser's rule, and the stage says so. With no sound
-- device it says so and plays on the silent device, so every scene still
-- runs; without the extension it says so plainly and waits.
--
-- Conventions (the library's): handles are integers and 0 is "none"; times
-- are seconds on the engine's own clock; a refused call does nothing,
-- returns 0 or empty, never throws, and auLastError() says why. The library
-- never calls a script, so ONE timer (adTick, about 30 times a second, the
-- screen locked for each frame) asks it what happened, schedules what comes
-- next and draws. Nothing waits: work that takes a while (the drums, the
-- tape, the checks) is done a piece a frame, with its progress shown.
--
-- THE LOOK is OXT-Beyond's showcase look, the Render3D Tour's palette: a
-- dark stage and controls this script draws itself (no system tick box,
-- list or slider). Every field and button gets its text colour where it
-- gets its background, because a system in dark mode gives a control with
-- no colour of its own white text (seen on Windows, 2026-11-21).
--
-- HONESTY (the suite convention): the footer line this stack paints is kept
-- true to what has run.

-- Bump when the generated window changes, so a saved stack rebuilds it.
constant kAdUiVersion = "audioxt-stage-2"
constant kAdWidth = 960
constant kAdHeight = 600

-- The look: the Render3D Tour's palette, then the stage's own colours.
constant kAdPage = "#12151F"
constant kAdPanel = "#1C2130"
constant kAdInk = "#EEF1F7"
constant kAdSoft = "#A9B2C7"
constant kAdAccent = "#FF8A3D"
constant kAdButton = "#2A3146"
constant kAdEdge = "#3A4360"
constant kAdDeep = "#0B0E16"
constant kAdWell = "#151A27"
constant kAdLine = "#2A3146"
constant kAdScopeInk = "#5CE1E6"
constant kAdGood = "#3DDC97"
constant kAdWarm = "#FFC857"
constant kAdHot = "#FF5A5F"
constant kAdKeyWhite = "#C9D1E3"
constant kAdKeyBlack = "#1A1F2C"

-- The scenes, in the order of their buttons, and what each one shows.
constant kAdSceneNames = "Beat machine,Round your head,Synth and fades,A tape made here,Your microphone"

-- The beat: the rows of the grid and each row's colour; 120 beats a
-- minute, so a step (a sixteenth) is 0.125 s and a bar 2 s. The show is
-- five bars and one last hit (81 steps).
constant kAdRows = "Kick,Snare,Hat,Bell"
constant kAdRowInk = "#FF8A3D,#4FC3F7,#B39DDB,#81E6A5"
constant kAdStepSeconds = 0.125
constant kAdLastStep = 80
-- The bell's note on each step, in semitones above its own pitch: a
-- pentatonic line, so any pattern of bells is a tune.
constant kAdBellNotes = "0,3,5,7,10,12,10,7,5,3,0,-2,0,3,7,12"

-- Round your head: pixels to a unit of the room, and where you stand.
constant kAdFlyScale = 22
constant kAdFlyX = 336
constant kAdFlyY = 250

-- Synth and fades: the arpeggio (C3, E3, G3, C4: low notes, so the
-- oscilloscope shows a few whole waves) and its MIDI numbers for the keys.
constant kAdArpHertz = "130.81,164.81,196,261.63"
constant kAdArpMidi = "48,52,55,60"
constant kAdShapes = "sine,square,triangle,sawtooth"
-- each shape's amplitude: a square or a sawtooth is louder to the ear
constant kAdShapeAmp = "0.3,0.11,0.3,0.15"
constant kAdNoteSeconds = 0.55
-- the chord at the end: C3, G3, C4, E4, spread from left to right
constant kAdChordHertz = "130.81,196,261.63,329.63"
constant kAdChordMidi = "48,55,60,64"
constant kAdChordPan = "-0.6,-0.2,0.2,0.6"

-- The tape: four notes then the same four as a chord, two seconds at
-- 44,100 Hz stereo, 16-bit (C5, E5, G5, C6).
constant kAdTuneNotes = "261.63,329.63,392,523.25"
constant kAdTuneFrames = 88200
constant kAdTuneChunk = 4410
constant kAdTuneColumns = 156
-- the three clones' pitches: a major chord of the whole tape
constant kAdClonePitches = "1,1.2599,1.4983"
constant kAdHeadInk = "#EEF1F7,#FF8A3D,#3DDC97"

-- The sound devices panel: rows of devices in each of its two columns.
constant kAdDeviceRows = 8

-- Your microphone: what is asked for, and how long it listens.
constant kAdMicRate = 16000
constant kAdMicSeconds = 5

-- The checks, in the order they run, a step a frame; the live ones wait
-- for the silent device's own thread between them (milliseconds).
constant kAdCheckSteps = "facts,mixing,wav,fourways,timing,own,refusals,liveA,liveB,liveC,done"
constant kAdCheckWaits = "0,0,0,0,0,0,0,0,350,450,0"

-- the engine and its device
local sEngine        -- the engine every scene plays through; 0 until the first
local sDevice        -- the playback device asked for: 0 the default, -1 the silent one
local sManual        -- true when the engine is offline and this script moves its clock
local sManualMs      -- the milliseconds when it was last moved
local sEngineNote    -- what to say about the engine when it is not the device asked for
local sMicDevice     -- the capture device the microphone scene opens
local sPaused        -- true while the engine is paused (auEngineStop)
local sVolume        -- the engine's volume, 0 to 1
local sVolDrag       -- true while the volume knob is dragged
local sMenuMap       -- the devices panel: what each of its buttons picks
local sBuildGroup    -- the group the window's builders create into, or empty
-- the timer
local sTickMsg       -- the pending adTick, empty when none is pending
local sTicks         -- frames so far
local sMeterL        -- the meters as drawn, falling back slowly after a peak
local sMeterR
local sScopeGain     -- the oscilloscope's zoom, eased from frame to frame
local sLastClock     -- the engine's clock at the last frame, and since when it
local sHeldMs        -- has stood still (a web page holds sound until a click)
local sBegun         -- true once the opening show has been started
-- the scene
local sScene         -- 0 none, 1 to 5 a scene, 6 the checks
local sSceneT0       -- the engine time the scene's clock counts from
local sScenePhase    -- where the scene's own story has got to
local sPlayAll       -- true: each scene runs into the next, 1 to 4
local sOwned         -- the sounds the scene made, freed when it ends
local sEnded         -- sounds whose end the last poll reported
-- Beat machine
local sKit           -- kick, snare, hat, bell, crash: sounds, comma-separated
local sDrums         -- the group the drums play in (the bell is not in it)
local sBeatStart     -- the engine time of step 0
local sBeatIndex     -- the next step to schedule, 0 to kAdLastStep
local sNotes         -- notes started (each a clone, freed at its end)
local sGridBar       -- the bar the grid shows
local sGridStep      -- the step drawn lit
-- Round your head
local sBee           -- the flying sound
local sBeeX          -- where it is: x to the right, z down the screen (behind you)
local sBeeZ
local sFacing        -- your heading in degrees: 0 faces up the screen
local sTrail         -- its last places, as points
local sWaveAt        -- when its last ring of sound set out
-- Synth and fades
local sVoices        -- the four shapes' tones, in kAdShapes order
local sVoiceNow      -- the shape sounding, 1 to 4, or 0
local sHertzNow      -- the frequency it glides from
local sChordTones    -- the chord's four tones
local sNoise         -- the pink noise under it
local sLitKeys       -- the keys drawn lit
-- A tape made here
local sTapeOff       -- the offline engine that makes the tape
local sTapeFrames    -- frames of it made so far
local sTapeData      -- its samples so far (s16, stereo)
local sTapeTop       -- the picture so far: the left channel's points and the right's
local sTapeBottom
local sTapeMs        -- the milliseconds when it was begun, then how long it took
local sTapeWav       -- the WAV file's bytes
local sTapePath      -- where the file was written
local sTape          -- the tape loaded from its bytes (it can be cloned)
local sTapeStream    -- the same tape streamed from its file
local sTapeClones    -- the three clones
-- Your microphone
local sMic           -- the capture
local sMicData       -- what it heard, kept in memory (s16 mono)
local sMicFile       -- the WAV file it is written to, or empty
local sMicMs         -- the milliseconds when it began to listen
local sMicSound      -- what it heard, as a sound to play back
local sMicFacts      -- what is known about it, in words
local sMicTop        -- its picture so far
local sMicBottom
-- the checks
local sCkPass
local sCkFail
local sCkLog
local sCkStep        -- the next step, 1 to the number of items of kAdCheckSteps
local sCkMs          -- the milliseconds when the last step ran
local sCkDone        -- true when the last step has run
local sCkLive        -- the silent device's engine, its tone, its microphone and file
local sCkTone
local sCkMic
local sCkPath
local sCkFolder
local sCkSeconds

-- ==========================================================================
-- Opening and closing.
-- ==========================================================================

on preOpenStack
   adInitState
   adBuildUI
   adPlaceWindow
   adShowScene sScene
   adPaintVolume
   adSyncButtons
   adPaintEngineStatus
   -- Straight into the show, a moment after the window is up. Armed here
   -- and not in openStack so the paste path (send "preOpenStack") gets it.
   if not sBegun then
      send "adBegin" to me in 80 milliseconds
   end if
end preOpenStack

on closeStack
   adCloseAll
end closeStack

on adBegin
   set the defaultStack to the short name of this stack
   adInitState
   if sBegun then
      exit adBegin
   end if
   put true into sBegun
   if not adLoaded() then
      adShowMissing
      exit adBegin
   end if
   put true into sPlayAll
   adStartScene 1
end adBegin

-- ==========================================================================
-- State. Every handle starts as 0 ("none") and never as empty: a library
-- parameter typed Integer refuses empty before the library sees it (suite
-- engine note 6.4). Idempotent, so every entry point calls it first.
-- ==========================================================================

command adInitState
   if sEngine is not an integer then put 0 into sEngine
   if sDevice is not an integer then put 0 into sDevice
   if sMicDevice is not an integer then put 0 into sMicDevice
   if sDrums is not an integer then put 0 into sDrums
   if sBee is not an integer then put 0 into sBee
   if sNoise is not an integer then put 0 into sNoise
   if sTapeOff is not an integer then put 0 into sTapeOff
   if sTape is not an integer then put 0 into sTape
   if sTapeStream is not an integer then put 0 into sTapeStream
   if sMic is not an integer then put 0 into sMic
   if sMicSound is not an integer then put 0 into sMicSound
   if sCkLive is not an integer then put 0 into sCkLive
   if sCkTone is not an integer then put 0 into sCkTone
   if sCkMic is not an integer then put 0 into sCkMic
   if sScene is not an integer then put 0 into sScene
   if sTicks is not an integer then put 0 into sTicks
   if sNotes is not an integer then put 0 into sNotes
   if sBeatIndex is not an integer then put 0 into sBeatIndex
   if sVoiceNow is not an integer then put 0 into sVoiceNow
   if sTapeFrames is not an integer then put 0 into sTapeFrames
   if sCkPass is not an integer then put 0 into sCkPass
   if sCkFail is not an integer then put 0 into sCkFail
   if sCkStep is not an integer then put 1 into sCkStep
   if sGridBar is not an integer then put 0 into sGridBar
   if sGridStep is not an integer then put 0 into sGridStep
   if sVolume is not a number then put 0.7 into sVolume
   if sSceneT0 is not a number then put 0 into sSceneT0
   if sBeatStart is not a number then put 0 into sBeatStart
   if sFacing is not a number then put 0 into sFacing
   if sBeeX is not a number then put 0 into sBeeX
   if sBeeZ is not a number then put -4 into sBeeZ
   if sHertzNow is not a number then put 0 into sHertzNow
   if sMeterL is not a number then put 0 into sMeterL
   if sMeterR is not a number then put 0 into sMeterR
   if sScopeGain is not a number then put 1 into sScopeGain
   if sLastClock is not a number then put -1 into sLastClock
   if sHeldMs is not a number then put the milliseconds into sHeldMs
   if sManualMs is not a number then put the milliseconds into sManualMs
   if sWaveAt is not a number then put 0 into sWaveAt
   if sTapeMs is not a number then put 0 into sTapeMs
   if sMicMs is not a number then put 0 into sMicMs
   if sCkMs is not a number then put 0 into sCkMs
   if sManual is not true then put false into sManual
   if sPaused is not true then put false into sPaused
   if sVolDrag is not true then put false into sVolDrag
   if sPlayAll is not true then put false into sPlayAll
   if sBegun is not true then put false into sBegun
   if sCkDone is not true then put false into sCkDone
   if the number of items of sVoices is not 4 then put "0,0,0,0" into sVoices
   if the number of items of sChordTones is not 4 then put "0,0,0,0" into sChordTones
end adInitState

-- The library's handles die with their engine (auEngineFree, auShutDown),
-- so the window forgets them all at once and makes them again when needed.
command adForgetSounds
   put empty into sKit
   put 0 into sDrums
   put 0 into sBee
   put "0,0,0,0" into sVoices
   put "0,0,0,0" into sChordTones
   put 0 into sNoise
   put 0 into sTape
   put 0 into sTapeStream
   put empty into sTapeClones
   put 0 into sMicSound
   put empty into sOwned
   put false into sPaused
end adForgetSounds

-- Everything closed: the timer cancelled, every device and handle gone.
command adCloseAll
   local tError
   if sTickMsg is not empty then
      cancel sTickMsg
      put empty into sTickMsg
   end if
   put 0 into sScene
   try
      auShutDown
   catch tError
   end try
   put 0 into sEngine
   put 0 into sMic
   put 0 into sTapeOff
   put 0 into sCkLive
   put 0 into sCkMic
   put false into sManual
   put false into sBegun
   adForgetSounds
end adCloseAll

-- Is the extension there at all? (Its first call throws when it is not, or
-- when its native library is from another release.)
function adLoaded
   local tError
   try
      get auABIVersion()
   catch tError
      return false
   end try
   return true
end adLoaded

-- What the drive (tests/demo-drive.livecodescript) and a curious reader can
-- ask for, by name.
function adProbe pWhat
   local tCopy
   adInitState
   switch pWhat
      case "engine"
         return sEngine
      case "device"
         return sDevice
      case "manual"
         return sManual
      case "enginenote"
         return sEngineNote
      case "paused"
         return sPaused
      case "volume"
         return sVolume
      case "scene"
         return sScene
      case "phase"
         return sScenePhase
      case "scenetime"
         return adSceneTime()
      case "playall"
         return sPlayAll
      case "kit"
         return sKit
      case "drums"
         return sDrums
      case "notes"
         return sNotes
      case "gridbar"
         return sGridBar
      case "gridstep"
         return sGridStep
      case "bee"
         return sBee
      case "beexz"
         return sBeeX & comma & sBeeZ
      case "facing"
         return sFacing
      case "voices"
         return sVoices
      case "voicenow"
         return sVoiceNow
      case "chord"
         return sChordTones
      case "noise"
         return sNoise
      case "tape"
         return sTape
      case "tapestream"
         return sTapeStream
      case "tapebytes"
         return the number of bytes in sTapeWav
      case "tapepath"
         return sTapePath
      case "clones"
         return sTapeClones
      case "mic"
         return sMic
      case "micdevice"
         return sMicDevice
      case "micbytes"
         return the number of bytes in sMicData
      case "micsound"
         return sMicSound
      case "micfacts"
         return sMicFacts
      case "ckpass"
         return sCkPass
      case "ckfail"
         return sCkFail
      case "ckdone"
         return sCkDone
      case "cklog"
         return sCkLog
      case "menu"
         put sMenuMap into tCopy
         combine tCopy using return and "="
         return tCopy
      case "ticks"
         return sTicks
   end switch
   return 0
end adProbe

-- ==========================================================================
-- The window. Built once and kept: a saved stack keeps its controls, so it
-- is built again only when kAdUiVersion changes. Each scene's pieces are in
-- one group, shown while that scene plays.
-- ==========================================================================

on adBuildUI
   local tI, tName, tLeft, tTop, tX, tRow, tStep, tWasLocked
   set the defaultStack to the short name of this stack
   if the uAdUiVersion of this stack is kAdUiVersion and there is a field "Heading" then
      exit adBuildUI
   end if
   lock screen
   -- Messages stay locked for the whole build. Each control made sends a
   -- new-object message, and an IDE answers every one: built with messages
   -- on, the window took 59 s to open in OXT-Beyond 0.2.8-dp.1's IDE on
   -- Windows (2026-11-21), where the engine alone builds it in about 30 ms.
   -- Restored, not unlocked: the stack file's builder calls this with
   -- messages locked already.
   put the lockMessages into tWasLocked
   lock messages
   repeat while the number of controls of this card > 0
      delete control 1 of this card
   end repeat
   set the width of this stack to kAdWidth
   set the height of this stack to kAdHeight
   set the resizable of this stack to false
   set the title of this stack to "Sound Stage - audioxt"
   set the backgroundColor of this stack to kAdPage
   set the foregroundColor of this stack to kAdInk
   set the textSize of this stack to 13
   set the backgroundColor of this card to kAdPage
   set the foregroundColor of this card to kAdInk
   put empty into sBuildGroup

   -- the header: the family's name, the stage's, what it is, and whose
   adLabel "Brand", "OXT-BEYOND", "16,8,400,26", 11, kAdAccent, "bold"
   adLabel "Credit", "by Seth Morrow", "560,8,944,26", 12, kAdSoft, "plain"
   set the textAlign of field "Credit" to "right"
   adLabel "Heading", "Sound Stage", "12,22,250,58", 22, kAdInk, "bold"
   adLabel "Sub", "Sound made in script and mixed live by audioxt: a beat, a sound that flies round you, a synth, a tape and your microphone.", \
         "176,33,944,53", 12, kAdSoft, "plain"

   -- the stage, its progress line and its caption
   adShape "Frame", "rectangle", "10,56,662,548", kAdPanel
   adShape "StageBg", "rectangle", "16,62,656,542", kAdDeep
   adShape "SceneBar", "rectangle", "16,62,17,65", kAdAccent
   adLabel "Caption", empty, "24,72,648,98", 13, kAdInk, "bold"
   set the opaque of field "Caption" to true
   set the backgroundColor of field "Caption" to kAdPage
   set the blendLevel of field "Caption" to 20
   set the margins of field "Caption" to 5

   -- what the device plays, under every scene
   adShape "ScopeBg", "roundrect", "26,404,598,532", kAdWell
   adShape "ScopeMid", "line", "34,468,590,468", empty
   set the foregroundColor of graphic "ScopeMid" to kAdLine
   adShape "Scope", "polygon", "34,468,590,468", empty
   set the opaque of graphic "Scope" to false
   set the foregroundColor of graphic "Scope" to kAdScopeInk
   set the lineSize of graphic "Scope" to 2
   set the points of graphic "Scope" to "34,468" & return & "590,468"
   adLabel "ScopeCap", "WHAT THE DEVICE PLAYS", "34,407,330,422", 10, kAdSoft, "bold"
   adLabel "ScopeGain", empty, "450,407,590,422", 10, kAdSoft, "bold"
   set the textAlign of field "ScopeGain" to "right"
   adLabel "MeterLCap", "L", "606,404,628,422", 10, kAdSoft, "bold"
   adLabel "MeterRCap", "R", "628,404,650,422", 10, kAdSoft, "bold"
   set the textAlign of field "MeterLCap" to "center"
   set the textAlign of field "MeterRCap" to "center"
   adShape "MeterLBg", "roundrect", "610,424,624,532", kAdWell
   adShape "MeterRBg", "roundrect", "632,424,646,532", kAdWell
   adShape "MeterL", "roundrect", "610,530,624,532", kAdGood
   adShape "MeterR", "roundrect", "632,530,646,532", kAdGood

   -- the scenes
   adBuildBeat
   adBuildFly
   adBuildSynth
   adBuildTape
   adBuildMic
   adBuildChecks
   put empty into sBuildGroup

   -- what is said over the stage: no library, a held web page, the end
   adText "Missing", empty, "96,170,576,320", 15, kAdInk
   set the textAlign of field "Missing" to "center"
   set the visible of field "Missing" to false
   adButton "Held", "Click anywhere to hear it", "196,200,476,244"
   set the textSize of button "Held" to 15
   set the textStyle of button "Held" to "bold"
   set the backgroundColor of button "Held" to kAdAccent
   set the borderColor of button "Held" to kAdAccent
   set the visible of button "Held" to false
   adBuildEnd
   put empty into sBuildGroup

   -- the side: the scenes, the sound, what this shows
   adLabel "ScenesCap", "SCENES", "672,56,944,74", 11, kAdAccent, "bold"
   repeat with tI = 1 to 5
      put 78 + (tI - 1) * 34 into tTop
      adButton "Sc" & tI, tI & ". " & item tI of kAdSceneNames, "672," & tTop & ",944," & (tTop + 30)
   end repeat
   adLabel "SoundCap", "THE SOUND", "672,252,944,270", 11, kAdAccent, "bold"
   adButton "PlayAll", "Play all", "672,274,805,300"
   adButton "Pause", "Pause", "811,274,944,300"
   adButton "Device", "Sound device...", "672,306,805,332"
   adButton "Checks", "Run the checks", "811,306,944,332"
   adLabel "VolCap", "Volume", "672,338,734,358", 12, kAdSoft, "plain"
   adShape "VolTrack", "roundrect", "740,345,896,351", kAdButton
   adShape "VolFill", "roundrect", "740,345,850,351", kAdAccent
   adShape "VolKnob", "oval", "843,341,857,355", kAdInk
   adLabel "VolText", "70%", "900,338,944,358", 12, kAdSoft, "plain"
   set the textAlign of field "VolText" to "right"
   adLabel "AboutCap", "WHAT THIS SHOWS", "672,368,944,386", 11, kAdAccent, "bold"
   adText "About", empty, "672,388,944,520", 12, kAdInk
   adLabel "Stats", empty, "672,524,944,542", 11, kAdSoft, "plain"

   -- the foot of the window
   adLabel "Status", empty, "16,552,944,570", 12, kAdSoft, "plain"
   adLabel "Footer", "Made in script with audioxt (miniaudio inside). Played through the silent device on Linux and a sound card " \
         & "on Windows (2026-11-21); not yet heard: needs an OXT pass.", "16,572,944,590", 11, kAdSoft, "italic"

   -- the sound devices, a panel over the stage (last, so it is on top)
   adBuildDevices
   put empty into sBuildGroup

   set the uAdUiVersion of this stack to kAdUiVersion
   set the lockMessages to tWasLocked
   unlock screen
end adBuildUI

-- Where the window goes when it opens: empty to leave it where it is (all
-- of it, and the title bar above it, inside one working screen), or the loc
-- that centres it on the first screen, never with its title bar above the
-- top. A window whose title bar is above the screen cannot be dragged: the
-- stack file once opened at -320,-140 on Windows (2026-11-21), its size set
-- around the engine's default centre. pScreens is the working screenRects,
-- one rectangle a line; a screen of no size (an engine with no display)
-- asks for nothing. A function of its own, so the drive can try it with
-- screens it has not got.
function adPlacedLoc pWindow, pScreens
   local tTitle, tScreen, tX, tY
   -- about a title bar, which sits above a stack's own top
   put 32 into tTitle
   put line 1 of pScreens into tScreen
   if the number of items of tScreen is not 4 then
      return empty
   end if
   if item 3 of tScreen - item 1 of tScreen < 1 or item 4 of tScreen - item 2 of tScreen < 1 then
      return empty
   end if
   repeat for each line tScreen in pScreens
      if item 1 of pWindow >= item 1 of tScreen and item 2 of pWindow - tTitle >= item 2 of tScreen \
            and item 3 of pWindow <= item 3 of tScreen and item 4 of pWindow <= item 4 of tScreen then
         return empty
      end if
   end repeat
   put line 1 of pScreens into tScreen
   put (item 1 of tScreen + item 3 of tScreen) div 2 into tX
   put (item 2 of tScreen + item 4 of tScreen + tTitle) div 2 into tY
   put max(tY, item 2 of tScreen + tTitle + (item 4 of pWindow - item 2 of pWindow) div 2) into tY
   return tX & comma & tY
end adPlacedLoc

private command adPlaceWindow
   local tLoc
   -- the desktop's windows only: in a browser the Stack Player gives the
   -- stack its own window and lays the page out, and a phone's window is
   -- its screen
   if the platform is "HTML5" or the environment is "mobile" then
      exit adPlaceWindow
   end if
   put adPlacedLoc(the rect of this stack, the working screenRects) into tLoc
   if tLoc is not empty then
      set the loc of this stack to tLoc
   end if
end adPlaceWindow

-- Beat machine: four rows of sixteen steps, a playhead, the drums' group.
private command adBuildBeat
   local tRow, tStep, tName, tLeft, tTop, tI
   adGroup "gBeat"
   adShape "bHead", "rectangle", "93,118,128,302", kAdInk
   set the blendLevel of graphic "bHead" to 90
   repeat with tI = 1 to 4
      put adCellLeft(tI * 4 - 3) into tLeft
      adLabel "bNum" & tI, tI, tLeft & ",102," & (tLeft + 40) & ",120", 10, kAdSoft, "bold"
   end repeat
   repeat with tRow = 1 to 4
      put 124 + (tRow - 1) * 44 into tTop
      adLabel "bRow" & tRow, item tRow of kAdRows, "24," & (tTop + 8) & ",92," & (tTop + 28), 12, item tRow of kAdRowInk, "bold"
      repeat with tStep = 1 to 16
         put "bC" & tRow & "-" & tStep into tName
         put adCellLeft(tStep) into tLeft
         adShape tName, "roundrect", tLeft & "," & tTop & "," & (tLeft + 29) & "," & (tTop + 36), kAdLine
         set the roundRadius of graphic tName to 10
      end repeat
   end repeat
   adLabel "bGrpCap", "THE DRUMS' GROUP", "24,316,240,332", 10, kAdAccent, "bold"
   adLabel "bPanL", "left", "52,340,92,358", 10, kAdSoft, "plain"
   adShape "bPanTrack", "line", "100,350,400,350", empty
   set the foregroundColor of graphic "bPanTrack" to kAdLine
   set the lineSize of graphic "bPanTrack" to 2
   adShape "bPanMid", "line", "250,343,250,357", empty
   set the foregroundColor of graphic "bPanMid" to kAdEdge
   adLabel "bPanR", "right", "406,340,446,358", 10, kAdSoft, "plain"
   adShape "bPanDot", "oval", "244,344,256,356", kAdAccent
   adLabel "bGrpText", empty, "452,340,648,358", 12, kAdSoft, "plain"
   adLabel "bNotes", empty, "24,366,648,384", 12, kAdSoft, "plain"
end adBuildBeat

-- The left edge of step pStep of the grid: steps in fours, a gap between.
function adCellLeft pStep
   return 96 + (pStep - 1) * 32 + ((pStep - 1) div 4) * 8
end adCellLeft

-- Round your head: you from above, in rings of 2, 4 and 6 units.
private command adBuildFly
   local tR, tI
   adGroup "gFly"
   repeat for each item tR in "2,4,6"
      adShape "fRing" & tR, "oval", (kAdFlyX - tR * kAdFlyScale) & "," & (kAdFlyY - tR * kAdFlyScale) & "," \
            & (kAdFlyX + tR * kAdFlyScale) & "," & (kAdFlyY + tR * kAdFlyScale), empty
      set the opaque of graphic ("fRing" & tR) to false
      set the foregroundColor of graphic ("fRing" & tR) to kAdEdge
      set the dashes of graphic ("fRing" & tR) to "3,6"
   end repeat
   adLabel "fAhead", "ahead", (kAdFlyX - 40) & ",102," & (kAdFlyX + 40) & ",118", 10, kAdSoft, "bold"
   adLabel "fBehind", "behind", (kAdFlyX - 40) & ",383," & (kAdFlyX + 40) & ",399", 10, kAdSoft, "bold"
   adLabel "fLeft", "left", "140,242,198,258", 10, kAdSoft, "bold"
   adLabel "fRight", "right", "474,242,532,258", 10, kAdSoft, "bold"
   set the textAlign of field "fAhead" to "center"
   set the textAlign of field "fBehind" to "center"
   set the textAlign of field "fLeft" to "right"
   adShape "fTrail", "polygon", "0,0,1,1", empty
   set the opaque of graphic "fTrail" to false
   set the foregroundColor of graphic "fTrail" to kAdWarm
   set the lineSize of graphic "fTrail" to 3
   set the blendLevel of graphic "fTrail" to 55
   repeat with tI = 1 to 2
      adShape "fWave" & tI, "oval", "0,0,10,10", empty
      set the opaque of graphic ("fWave" & tI) to false
      set the foregroundColor of graphic ("fWave" & tI) to kAdWarm
      set the lineSize of graphic ("fWave" & tI) to 2
      set the visible of graphic ("fWave" & tI) to false
   end repeat
   adShape "fEarL", "oval", "0,0,8,8", kAdAccent
   adShape "fEarR", "oval", "0,0,8,8", kAdAccent
   adShape "fHead", "oval", (kAdFlyX - 13) & "," & (kAdFlyY - 13) & "," & (kAdFlyX + 13) & "," & (kAdFlyY + 13), kAdButton
   set the foregroundColor of graphic "fHead" to kAdInk
   set the lineSize of graphic "fHead" to 2
   adShape "fNose", "polygon", "0,0,1,1", kAdInk
   adShape "fGlow", "oval", "0,0,40,40", kAdWarm
   set the blendLevel of graphic "fGlow" to 78
   adShape "fBee", "oval", "0,0,16,16", kAdWarm
   adText "fReadout", empty, "508,286,650,398", 12, kAdSoft
end adBuildFly

-- Synth and fades: the shape's name and outline, two octaves of keys, and
-- the chord's four voices from left to right.
private command adBuildSynth
   local tI, tLeft, tPlace, tN
   adGroup "gSynth"
   adLabel "yName", empty, "24,104,316,150", 30, kAdInk, "bold"
   adShape "yIcon", "polygon", "0,0,1,1", empty
   set the opaque of graphic "yIcon" to false
   set the foregroundColor of graphic "yIcon" to kAdAccent
   set the lineSize of graphic "yIcon" to 3
   adLabel "yNote", empty, "24,152,648,170", 12, kAdSoft, "plain"
   repeat with tI = 1 to 15
      put 96 + (tI - 1) * 32 into tLeft
      adShape "yW" & tI, "rectangle", tLeft & ",184," & (tLeft + 30) & ",288", kAdKeyWhite
   end repeat
   put 0 into tN
   repeat with tI = 1 to 14
      -- a black key after C, D, F, G and A
      put (tI - 1) mod 7 into tPlace
      if tPlace is among the items of "0,1,3,4,5" then
         add 1 to tN
         put 96 + tI * 32 - 10 into tLeft
         adShape "yB" & tN, "rectangle", tLeft & ",184," & (tLeft + 18) & ",248", kAdKeyBlack
      end if
   end repeat
   -- the shapes in turn, the one sounding lit (shown until the chord)
   repeat with tI = 1 to 4
      adButton "ySh" & tI, item tI of "Sine,Square,Triangle,Sawtooth", (24 + (tI - 1) * 128) & ",318," & (24 + (tI - 1) * 128 + 118) & ",342"
   end repeat
   adLabel "yC3", "C3", "96,290,126,306", 10, kAdSoft, "bold"
   adLabel "yC4", "C4", "320,290,350,306", 10, kAdSoft, "bold"
   adLabel "yC5", "C5", "544,290,574,306", 10, kAdSoft, "bold"
   adLabel "yPanCap", "THE CHORD, FROM LEFT TO RIGHT", "24,316,330,332", 10, kAdAccent, "bold"
   adShape "yPanTrack", "line", "96,352,576,352", empty
   set the foregroundColor of graphic "yPanTrack" to kAdLine
   set the lineSize of graphic "yPanTrack" to 2
   repeat with tI = 1 to 4
      adShape "yPan" & tI, "oval", "0,0,14,14", kAdAccent
      adLabel "yPanN" & tI, item tI of "C3,G3,C4,E4", "0,0,40,16", 10, kAdSoft, "bold"
      set the textAlign of field ("yPanN" & tI) to "center"
   end repeat
   adLabel "yFacts", empty, "24,374,648,392", 12, kAdSoft, "plain"
end adBuildSynth

-- A tape made here: its picture (the left channel above the line, the
-- right below), a playhead for each sound playing it, the loop.
private command adBuildTape
   local tI
   adGroup "gTape"
   adShape "tWaveBg", "roundrect", "24,160,648,300", kAdWell
   adShape "tRange", "rectangle", "100,162,200,298", kAdAccent
   set the blendLevel of graphic "tRange" to 80
   set the visible of graphic "tRange" to false
   adShape "tWaveMid", "line", "28,230,644,230", empty
   set the foregroundColor of graphic "tWaveMid" to kAdLine
   adShape "tWave", "polygon", "0,0,1,1", kAdScopeInk
   set the foregroundColor of graphic "tWave" to kAdScopeInk
   set the blendLevel of graphic "tWave" to 30
   set the visible of graphic "tWave" to false
   adLabel "tLeftCap", "LEFT", "30,164,100,180", 10, kAdSoft, "bold"
   adLabel "tRightCap", "RIGHT", "30,280,100,296", 10, kAdSoft, "bold"
   repeat with tI = 1 to 3
      adShape "tHead" & tI, "line", "30,156,30,304", empty
      set the foregroundColor of graphic ("tHead" & tI) to item tI of kAdHeadInk
      set the lineSize of graphic ("tHead" & tI) to 2
      set the visible of graphic ("tHead" & tI) to false
      adLabel "tLab" & tI, empty, "0,136,56,154", 11, item tI of kAdHeadInk, "bold"
      set the textAlign of field ("tLab" & tI) to "center"
      set the visible of field ("tLab" & tI) to false
   end repeat
   adShape "tProgBg", "roundrect", "24,306,648,312", kAdWell
   adShape "tProg", "roundrect", "24,306,25,312", kAdAccent
   adText "tFacts", empty, "24,318,648,398", 12, kAdSoft
   adLabel "tName", empty, "24,102,380,136", 24, kAdInk, "bold"
   adLabel "tStat", empty, "380,112,648,130", 12, kAdSoft, "plain"
   set the textAlign of field "tStat" to "right"
end adBuildTape

-- Your microphone: a level, its picture as it arrives, what is known.
private command adBuildMic
   adGroup "gMic"
   adShape "mRec", "oval", "26,110,40,124", kAdHot
   adLabel "mRecText", empty, "46,106,648,126", 13, kAdInk, "bold"
   adShape "mLevelBg", "roundrect", "24,134,648,152", kAdWell
   adShape "mLevel", "roundrect", "24,134,25,152", kAdGood
   adShape "mWaveBg", "roundrect", "24,162,648,296", kAdWell
   adShape "mWaveMid", "line", "28,229,644,229", empty
   set the foregroundColor of graphic "mWaveMid" to kAdLine
   adShape "mWave", "polygon", "0,0,1,1", kAdGood
   set the foregroundColor of graphic "mWave" to kAdGood
   set the blendLevel of graphic "mWave" to 30
   set the visible of graphic "mWave" to false
   adShape "mHead", "line", "30,158,30,300", empty
   set the foregroundColor of graphic "mHead" to kAdInk
   set the lineSize of graphic "mHead" to 2
   set the visible of graphic "mHead" to false
   adText "mFacts", empty, "24,304,648,398", 12, kAdSoft
end adBuildMic

-- The checks: the newest lines, the progress, the count.
private command adBuildChecks
   adGroup "gChecks"
   adText "cLog", empty, "24,104,648,318", 12, kAdInk
   set the dontWrap of field "cLog" to true
   adShape "cProgBg", "roundrect", "24,324,648,332", kAdWell
   adShape "cProg", "roundrect", "24,324,25,332", kAdAccent
   adLabel "cSum", empty, "24,338,476,364", 16, kAdInk, "bold"
   adButton "cCopy", "Copy the results", "488,338,648,364"
   set the visible of button "cCopy" to false
   adText "cNote", empty, "24,368,648,398", 12, kAdSoft
end adBuildChecks

-- What the stage shows when a scene has ended: what it was, and what next.
private command adBuildEnd
   adGroup "gEnd"
   adShape "EndPanel", "roundrect", "146,184,526,292", kAdPanel
   set the foregroundColor of graphic "EndPanel" to kAdEdge
   set the roundRadius of graphic "EndPanel" to 10
   adLabel "EndKicker", "THAT WAS", "166,198,506,216", 11, kAdAccent, "bold"
   adLabel "EndName", empty, "166,218,506,250", 20, kAdInk, "bold"
   adLabel "EndHint", "Pick another scene on the right, or Play all.", "166,254,506,274", 13, kAdSoft, "plain"
   set the textAlign of field "EndKicker" to "center"
   set the textAlign of field "EndName" to "center"
   set the textAlign of field "EndHint" to "center"
end adBuildEnd

-- The sound devices: a panel of buttons drawn here, not a system menu,
-- whose colours would be the system's. Two columns, play through and listen
-- with, each kAdDeviceRows buttons, labelled when the panel opens.
private command adBuildDevices
   local tI, tTop
   adGroup "gDevices"
   adShape "dvPanel", "roundrect", "32,96,640,398", kAdPanel
   set the foregroundColor of graphic "dvPanel" to kAdEdge
   set the roundRadius of graphic "dvPanel" to 10
   adLabel "dvTitle", "SOUND DEVICES", "48,104,300,122", 11, kAdAccent, "bold"
   adButton "dvClose", "Close", "556,102,628,126"
   adLabel "dvPlayCap", "PLAY THROUGH", "48,130,330,146", 10, kAdSoft, "bold"
   adLabel "dvListenCap", "LISTEN WITH", "344,130,628,146", 10, kAdSoft, "bold"
   repeat with tI = 1 to kAdDeviceRows
      put 150 + (tI - 1) * 27 into tTop
      adButton "dvP" & tI, empty, "48," & tTop & ",330," & (tTop + 24)
      adButton "dvL" & tI, empty, "344," & tTop & ",628," & (tTop + 24)
      set the textAlign of button ("dvP" & tI) to "left"
      set the textAlign of button ("dvL" & tI) to "left"
      set the margins of button ("dvP" & tI) to 8
      set the margins of button ("dvL" & tI) to 8
   end repeat
   adLabel "dvNote", empty, "48,368,628,390", 11, kAdSoft, "plain"
end adBuildDevices

-- A group the builders below then create into. Its own box draws nothing
-- and catches no click: only its controls do.
private command adGroup pName
   put empty into sBuildGroup
   create group pName
   set the showBorder of group pName to false
   set the opaque of group pName to false
   set the threeD of group pName to false
   set the margins of group pName to 0
   set the visible of group pName to false
   put pName into sBuildGroup
end adGroup

private command adMake pType, pName
   if sBuildGroup is empty then
      switch pType
         case "field"
            create field pName
            break
         case "button"
            create button pName
            break
         case "graphic"
            create graphic pName
            break
      end switch
   else
      switch pType
         case "field"
            create field pName in group sBuildGroup
            break
         case "button"
            create button pName in group sBuildGroup
            break
         case "graphic"
            create graphic pName in group sBuildGroup
            break
      end switch
   end if
end adMake

-- One line of words nobody types into.
private command adLabel pName, pText, pRect, pSize, pColor, pStyle
   adMake "field", pName
   adQuiet pName
   set the dontWrap of field pName to true
   set the textSize of field pName to pSize
   adRoomy pName, pSize
   set the textStyle of field pName to pStyle
   set the foregroundColor of field pName to pColor
   set the rect of field pName to pRect
   put pText into field pName
end adLabel

-- Words that wrap.
private command adText pName, pText, pRect, pSize, pColor
   adMake "field", pName
   adQuiet pName
   set the dontWrap of field pName to false
   set the textSize of field pName to pSize
   adRoomy pName, pSize
   set the foregroundColor of field pName to pColor
   set the rect of field pName to pRect
   put pText into field pName
end adText

-- Lines tall enough for any system's font: left alone, a line is as tall as
-- the font the stack was BUILT with wants, and on Windows the tops of the
-- capitals were cut off (the Render3D Tour, 2026-11-21). So the height is
-- said: half as much again as the size.
private command adRoomy pName, pSize
   set the fixedLineHeight of field pName to true
   set the textHeight of field pName to round(pSize * 1.5)
end adRoomy

-- A field that is only words: no border, no box, no focus, and its own
-- colours (a system in dark mode would give it white text on its default
-- white; here every colour is set).
private command adQuiet pName
   set the lockText of field pName to true
   set the traversalOn of field pName to false
   set the opaque of field pName to false
   set the backgroundColor of field pName to kAdDeep
   set the showBorder of field pName to false
   set the threeD of field pName to false
   set the borderWidth of field pName to 0
   set the margins of field pName to 2
   set the vScrollbar of field pName to false
   set the hScrollbar of field pName to false
   set the autoHilite of field pName to false
   set the listBehavior of field pName to false
   set the hiliteColor of field pName to kAdButton
end adQuiet

-- A button drawn here: a rounded box, lit (orange) while its hilite is
-- true. Not a system button: those draw in the system's own colours.
private command adButton pName, pLabel, pRect
   adMake "button", pName
   set the style of button pName to "roundrect"
   set the label of button pName to pLabel
   set the opaque of button pName to true
   set the showBorder of button pName to true
   set the threeD of button pName to false
   set the shadow of button pName to false
   set the traversalOn of button pName to false
   set the showFocusBorder of button pName to false
   set the autoHilite of button pName to false
   set the textSize of button pName to 12
   set the backgroundColor of button pName to kAdButton
   set the foregroundColor of button pName to kAdInk
   set the borderColor of button pName to kAdEdge
   set the hiliteColor of button pName to kAdAccent
   set the hilite of button pName to false
   set the rect of button pName to pRect
end adButton

-- A graphic: a rectangle, a rounded one, an oval, a line or a polygon,
-- filled with pFill when one is given.
private command adShape pName, pStyle, pRect, pFill
   adMake "graphic", pName
   set the style of graphic pName to pStyle
   set the antialiased of graphic pName to true
   set the lineSize of graphic pName to 1
   if pStyle is "line" then
      set the points of graphic pName to item 1 to 2 of pRect & return & item 3 to 4 of pRect
      set the opaque of graphic pName to false
   else
      set the rect of graphic pName to pRect
      if pFill is empty then
         set the opaque of graphic pName to false
      else
         set the opaque of graphic pName to true
         set the backgroundColor of graphic pName to pFill
         set the foregroundColor of graphic pName to pFill
      end if
   end if
   if pStyle is "roundrect" then
      set the roundRadius of graphic pName to 6
   end if
end adShape

-- ==========================================================================
-- The engine. One engine plays every scene. Asked for the default device;
-- with none, the silent device (a real device thread on a real clock that
-- plays to nowhere), and with no device at all (a web page with no Web
-- Audio) an offline engine whose clock this window moves itself, so the
-- scenes still run and say so.
-- ==========================================================================

function adEnsureEngine
   local tWhy
   adInitState
   if auEngineIsValid(sEngine) then
      return true
   end if
   adForgetSounds
   put false into sManual
   put empty into sEngineNote
   put auEngineCreate(sDevice, 0, 0) into sEngine
   if sEngine is 0 then
      put adShortWhy(auLastError()) into tWhy
      if the platform is not "HTML5" and sDevice is not -1 then
         put auEngineCreate(-1, 0, 0) into sEngine
         if sEngine is not 0 then
            put "No sound device answered (" & tWhy & "), so the scenes play on the silent device: all of it runs, and nothing " \
                  & "is heard." into sEngineNote
         end if
      end if
   end if
   if sEngine is 0 then
      put auEngineCreateOffline(44100, 2) into sEngine
      if sEngine is not 0 then
         put true into sManual
         put the milliseconds into sManualMs
         put "No sound device answered (" & tWhy & "), so the scenes run on an offline engine this window drives: all of it runs, " \
               & "and nothing is heard." into sEngineNote
      end if
   end if
   if sEngine is 0 then
      adStatus "No sound at all: " & auLastError(), "bad"
      return false
   end if
   -- You stand at the middle, up is +y, and you face up the screen (-z).
   auEngineSetListenerPosition sEngine, 0, 0, 0
   auEngineSetListenerUp sEngine, 0, 1, 0
   auEngineSetListenerVelocity sEngine, 0, 0, 0
   adFace 0
   auEngineSetVolume sEngine, sVolume
   put -1 into sLastClock
   put the milliseconds into sHeldMs
   adSyncButtons
   adPaintEngineStatus
   adArmTick
   return true
end adEnsureEngine

-- The clock every scene keeps: the engine's own, which stands still while
-- it is paused (and, on a web page, until the first click).
function adClock
   if auEngineIsValid(sEngine) then
      return auEngineTime(sEngine)
   end if
   return the milliseconds / 1000
end adClock

function adSceneTime
   return adClock() - sSceneT0
end adSceneTime

-- An offline engine mixes only when asked: on each frame, as many frames as
-- the time since the last one (the sound itself is thrown away).
command adAdvanceManual
   local tNow, tFrames
   if not sManual or not auEngineIsValid(sEngine) then
      exit adAdvanceManual
   end if
   put the milliseconds into tNow
   if not sPaused then
      put round(min(250, max(0, tNow - sManualMs)) * auEngineSampleRate(sEngine) / 1000) into tFrames
      if tFrames > 0 then
         get auEngineRender(sEngine, tFrames, "s16")
      end if
   end if
   put tNow into sManualMs
end adAdvanceManual

command adTogglePause
   if not auEngineIsValid(sEngine) then
      exit adTogglePause
   end if
   if sPaused then
      if not sManual then
         auEngineStart sEngine
      end if
      put false into sPaused
      put the milliseconds into sManualMs
      put the milliseconds into sHeldMs
   else
      -- the device stops and the clock with it: every sound and every
      -- scene keeps its place
      if not sManual then
         auEngineStop sEngine
      end if
      put true into sPaused
   end if
   adSyncButtons
end adTogglePause

command adVolumeTo pFraction
   if pFraction is not a number then
      exit adVolumeTo
   end if
   put round(max(0, min(1, pFraction)), 2) into sVolume
   if adLoaded() then
      if auEngineIsValid(sEngine) then
         auEngineSetVolume sEngine, sVolume
      end if
   end if
   adPaintVolume
end adVolumeTo

command adPaintVolume
   local tX
   set the defaultStack to the short name of this stack
   if there is no graphic "VolKnob" then
      exit adPaintVolume
   end if
   put 740 + round(156 * sVolume) into tX
   set the rect of graphic "VolFill" to 740, 345, max(741, tX), 351
   set the rect of graphic "VolKnob" to tX - 7, 341, tX + 7, 355
   put round(100 * sVolume) & "%" into field "VolText"
end adPaintVolume

-- A new engine on another device: the old one is freed with every sound of
-- it, and the scene that was playing starts again on the new one.
command adUseDevice pDevice
   local tScene
   if pDevice is not an integer then
      exit adUseDevice
   end if
   put sScene into tScene
   adEndScene
   if auEngineIsValid(sEngine) then
      auEngineFree sEngine
   end if
   put 0 into sEngine
   adForgetSounds
   put pDevice into sDevice
   if adEnsureEngine() and tScene > 0 then
      adStartScene tScene
   end if
end adUseDevice

-- ==========================================================================
-- The timer: one frame, about 30 times a second.
-- ==========================================================================

command adArmTick
   if sTickMsg is empty then
      send "adTick" to me in 33 milliseconds
      put the result into sTickMsg
   end if
end adArmTick

-- The library never calls a script, so this asks it: which sounds ended
-- (freeing the ones marked to free themselves), what the scene does next,
-- what the device plays and how loud. The screen is locked for the frame,
-- so it changes once. A frame that throws says so on the status line and
-- the next one comes anyway: the window never stops.
on adTick
   local tError
   set the defaultStack to the short name of this stack
   put empty into sTickMsg
   adInitState
   if not adLoaded() then
      exit adTick
   end if
   if not auEngineIsValid(sEngine) and not auCaptureIsValid(sMic) and sScene is not 6 then
      exit adTick
   end if
   add 1 to sTicks
   lock screen
   try
      adAdvanceManual
      adPollEnded
      adSceneFrame
      adLiveFrame
      adHeldFrame
      if sTicks mod 8 is 0 then
         adPaintStats
      end if
   catch tError
      adStatus "A frame went wrong: " & line 1 of tError, "bad"
   end try
   unlock screen
   adArmTick
end adTick

-- The sounds that ended since the last frame. The ones marked auto-free are
-- already freed by this poll; the scenes ask sEnded about the others.
command adPollEnded
   local tCount, tI
   put empty into sEnded
   put auPollEnded() into tCount
   repeat with tI = 1 to tCount
      put auEndedSound(tI) & comma after sEnded
   end repeat
end adPollEnded

-- What the device plays (an oscilloscope over the newest 2048 frames the
-- engine mixed) and how loud each side is (the loudest sample since the
-- last frame: reading it resets it).
command adLiveFrame
   local tPeak
   if not auEngineIsValid(sEngine) then
      exit adLiveFrame
   end if
   put auEnginePeak(sEngine) into tPeak
   put max(item 1 of tPeak, sMeterL * 0.86) into sMeterL
   put max(item 2 of tPeak, sMeterR * 0.86) into sMeterR
   adMeter "MeterL", sMeterL
   adMeter "MeterR", sMeterR
   set the points of graphic "Scope" to adScopePoints(auEngineWaveform(sEngine, 600))
   if sScopeGain >= 1.2 then
      put "ZOOMED x" & format("%.1f", sScopeGain) into field "ScopeGain"
   else
      put empty into field "ScopeGain"
   end if
end adLiveFrame

-- A meter: a bar that rises from the bottom of its well; amber near the
-- top, red when the output clips.
command adMeter pName, pLevel
   local tTop, tLeft, tRight
   if pLevel is not a number then
      put 0 into pLevel
   end if
   put the left of graphic (pName & "Bg") into tLeft
   put the right of graphic (pName & "Bg") into tRight
   put 532 - round(108 * min(1, max(0, pLevel))) into tTop
   set the rect of graphic pName to tLeft, min(530, tTop), tRight, 532
   if pLevel > 1 then
      set the backgroundColor of graphic pName to kAdHot
   else if pLevel > 0.7 then
      set the backgroundColor of graphic pName to kAdWarm
   else
      set the backgroundColor of graphic pName to kAdGood
   end if
end adMeter

-- The oscilloscope's line: 400 of the 600 points, starting where the wave
-- first rises through the middle, so a steady tone stands still instead of
-- running across the screen (what a real oscilloscope's trigger does). A
-- quiet sound is zoomed, up to four times, so its shape still shows: the
-- zoom rises slowly (the gaps of a beat do not move it) and falls at once
-- (a loud sound never runs off the screen), and is written beside the
-- line. The meters always show the true level.
function adScopePoints pWave
   local tSamples, tCount, tStart, tI, tV, tPts, tShow, tMost, tWant
   put pWave into tSamples
   split tSamples by comma
   put the number of lines of the keys of tSamples into tCount
   put 400 into tShow
   if tCount < tShow + 2 then
      put 1 into sScopeGain
      return "34,468" & return & "590,468"
   end if
   put 1 into tStart
   repeat with tI = 2 to tCount - tShow
      if tSamples[tI - 1] <= 0 and tSamples[tI] > 0 then
         put tI into tStart
         exit repeat
      end if
   end repeat
   put 0 into tMost
   repeat with tI = 0 to tShow - 1
      if tSamples[tStart + tI] is a number then
         put max(tMost, abs(tSamples[tStart + tI])) into tMost
      end if
   end repeat
   put max(1, min(4, 0.8 / max(0.001, tMost))) into tWant
   if tMost < 0.002 then
      put 1 into tWant
   end if
   if tWant < sScopeGain then
      put tWant into sScopeGain
   else
      put sScopeGain + 0.06 * (tWant - sScopeGain) into sScopeGain
   end if
   repeat with tI = 0 to tShow - 1
      put tSamples[tStart + tI] into tV
      if tV is not a number then
         put 0 into tV
      end if
      put round(34 + 556 * tI / (tShow - 1)) & "," & round(468 - max(-50, min(50, tV * 48 * sScopeGain))) & return after tPts
   end repeat
   delete the last char of tPts
   return tPts
end adScopePoints

-- A web page holds sound until the visitor's first click or key press (the
-- browser's rule), and the engine's clock stands still till then: after a
-- moment of that, the stage asks for the click.
command adHeldFrame
   local tNow
   if the platform is not "HTML5" or sManual or sPaused or not auEngineIsValid(sEngine) then
      set the visible of button "Held" to false
      exit adHeldFrame
   end if
   put auEngineTime(sEngine) into tNow
   if tNow is not sLastClock then
      put tNow into sLastClock
      put the milliseconds into sHeldMs
      set the visible of button "Held" to false
   else if the milliseconds - sHeldMs > 600 then
      set the visible of button "Held" to true
      set the blendLevel of button "Held" to round(20 * (1 + sin(the milliseconds / 220)))
   end if
end adHeldFrame

command adPaintStats
   local tOut
   if not auEngineIsValid(sEngine) then
      put empty into field "Stats"
      exit adPaintStats
   end if
   put adThousands(auEngineSampleRate(sEngine)) & " Hz, " & auEngineChannels(sEngine) & " channels | clock " \
         & format("%.1f", auEngineTime(sEngine)) & " s | " & auEngineSoundCount(sEngine) & " sounds" into tOut
   if sPaused then
      put " | paused" after tOut
   end if
   put tOut into field "Stats"
end adPaintStats

command adPaintEngineStatus
   set the defaultStack to the short name of this stack
   if there is no field "Status" then
      exit adPaintEngineStatus
   end if
   if not adLoaded() then
      adStatus "audioxt is not loaded, so there is no sound here yet.", "bad"
   else if not auEngineIsValid(sEngine) then
      adStatus auLibraryVersion() & ". No sound device is open: the first scene opens the default one.", empty
   else if sEngineNote is not empty then
      adStatus sEngineNote, "warn"
   else
      adStatus auLibraryVersion() & " | playing through " & auEngineDeviceName(sEngine) & ", " \
            & adThousands(auEngineSampleRate(sEngine)) & " Hz, " & auEngineChannels(sEngine) & " channels", empty
   end if
end adPaintEngineStatus

-- The status line, in the stage's colours: soft, amber or red.
command adStatus pText, pKind
   set the defaultStack to the short name of this stack
   if there is no field "Status" then
      exit adStatus
   end if
   put pText into field "Status"
   if pKind is "bad" then
      set the foregroundColor of field "Status" to kAdHot
   else if pKind is "warn" then
      set the foregroundColor of field "Status" to kAdWarm
   else
      set the foregroundColor of field "Status" to kAdSoft
   end if
end adStatus

-- ==========================================================================
-- Scenes: one plays at a time; its pieces are its group's.
-- ==========================================================================

command adStartScene pScene
   adInitState
   adEndScene
   if pScene is not an integer or pScene < 1 or pScene > 6 then
      exit adStartScene
   end if
   set the visible of group "gEnd" to false
   adCloseDevices
   if not adLoaded() then
      adShowMissing
      exit adStartScene
   end if
   if pScene < 6 and not adEnsureEngine() then
      exit adStartScene
   end if
   put pScene into sScene
   put adClock() into sSceneT0
   put empty into sScenePhase
   put empty into sOwned
   adShowScene pScene
   put adAboutScene(pScene) into field "About"
   switch pScene
      case 1
         adBeatBegin
         break
      case 2
         adFlyBegin
         break
      case 3
         adSynthBegin
         break
      case 4
         adTapeBegin
         break
      case 5
         adMicBegin
         break
      case 6
         adChecksBegin
         break
   end switch
   adSyncButtons
   adArmTick
end adStartScene

-- The scene that was playing stops: its own sounds are freed, the group's
-- pan and pitch put back, the microphone closed.
command adEndScene
   local tSound
   switch sScene
      case 1
         adBeatEnd
         break
      case 2
         adFlyEnd
         break
      case 3
         adSynthEnd
         break
      case 4
         adTapeEnd
         break
      case 5
         adMicEnd
         break
      case 6
         adChecksEnd
         break
   end switch
   repeat for each item tSound in sOwned
      if tSound is an integer then
         auSoundFree tSound
      end if
   end repeat
   put empty into sOwned
   put 0 into sScene
   adSyncButtons
end adEndScene

-- A scene came to its end: the next one, when playing them all, or the
-- card that says what to do next.
command adSceneDone
   local tWas
   put sScene into tWas
   adEndScene
   if sPlayAll and tWas < 4 then
      adStartScene tWas + 1
      exit adSceneDone
   end if
   put false into sPlayAll
   adSyncButtons
   -- the stage clears, and says what that was and what comes next
   adShowScene 0
   put item tWas of kAdSceneNames into field "EndName"
   set the visible of group "gEnd" to true
   put "Pick a scene on the right" into field "Caption"
   adSceneBar 1
end adSceneDone

command adSceneFrame
   switch sScene
      case 1
         adBeatFrame
         break
      case 2
         adFlyFrame
         break
      case 3
         adSynthFrame
         break
      case 4
         adTapeFrame
         break
      case 5
         adMicFrame
         break
      case 6
         adChecksFrame
         break
   end switch
end adSceneFrame

-- Shows one scene's group (0: none) and lights its button.
command adShowScene pScene
   local tI, tGroups
   set the defaultStack to the short name of this stack
   put "gBeat,gFly,gSynth,gTape,gMic,gChecks" into tGroups
   repeat with tI = 1 to 6
      if there is a group (item tI of tGroups) then
         set the visible of group (item tI of tGroups) to (tI is pScene)
      end if
   end repeat
   if pScene > 0 then
      set the visible of field "Missing" to false
   end if
end adShowScene

-- The thin line along the top of the stage: how far through its show the
-- scene is, 0 to 1.
command adSceneBar pFraction
   if pFraction is not a number then
      put 0 into pFraction
   end if
   set the rect of graphic "SceneBar" to 16, 62, 16 + max(1, round(640 * max(0, min(1, pFraction)))), 65
end adSceneBar

-- A scene's own sound, freed when the scene ends.
command adOwn pSound
   if pSound is an integer and pSound > 0 then
      put pSound & comma after sOwned
   end if
end adOwn

command adSyncButtons
   local tI
   set the defaultStack to the short name of this stack
   if there is no button "Sc1" then
      exit adSyncButtons
   end if
   repeat with tI = 1 to 5
      adLight "Sc" & tI, (sScene is tI)
   end repeat
   adLight "PlayAll", sPlayAll
   adLight "Pause", sPaused
   adLight "Checks", (sScene is 6)
   if sPaused then
      set the label of button "Pause" to "Paused: resume"
   else
      set the label of button "Pause" to "Pause"
   end if
end adSyncButtons

command adLight pButton, pOn
   set the hilite of button pButton to (pOn is true)
   if pOn is true then
      set the borderColor of button pButton to kAdAccent
   else
      set the borderColor of button pButton to kAdEdge
   end if
end adLight

command adShowMissing
   set the defaultStack to the short name of this stack
   adShowScene 0
   put "This stage needs audioxt, the xTalk Suite's sound library (org.openxtalk.library.audioxt), and this engine " \
         & "does not have it. Every scene waits for it; nothing else needs setting up." into field "Missing"
   set the visible of field "Missing" to true
   put "audioxt is not here" into field "Caption"
   adStatus "audioxt is not loaded, so there is no sound here yet.", "bad"
end adShowMissing

-- What each scene shows, in plain words, with the calls that do it.
function adAboutScene pScene
   switch pScene
      case 1
         return "Drums and a bell made in script: an offline engine mixes each into memory (auEngineRender) and it becomes a " \
               & "sound (auSoundFromPCM). Every hit is a clone (auSoundClone) started on the engine's clock (auSoundStartAt); " \
               & "the drums share one group (auGroupSetPan)."
      case 2
         return "One buzzing sound with a place in the room (auSoundSetPosition). It circles you, flies past with its speed " \
               & "told to the library so its pitch falls (auSoundSetDoppler), then holds still while you turn " \
               & "(auEngineSetListenerDirection). Best on headphones."
      case 3
         return "Tones the library makes itself, in four shapes (auSoundTone), gliding note to note (auSoundSetFrequency); " \
               & "then a chord spread left to right (auSoundSetPan) that swells and dies away (auSoundFade, " \
               & "auSoundStopWithFade) over pink noise (auSoundNoise)."
      case 4
         return "Two seconds of music mixed in script into a WAV file (auEngineRender, auWAVEncode), streamed back from " \
               & "disk (auSoundLoad), played as three clones at once (auSoundClone, auSoundSetPitch), then looped over its " \
               & "middle (auSoundSetLoopRange)."
      case 5
         return "Five seconds from your microphone (auCaptureOpen), read as it arrives (auCaptureRead) and written to a " \
               & "WAV file at once (auCaptureRecordStart), then played back (auSoundFromPCM), and again faster. A browser " \
               & "asks you first."
      case 6
         return "Every check of this window, on engines of its own: the mixer measured, WAV files made and read back bit " \
               & "for bit, ends, groups, 3D, refusals in words, and the silent test device in real time. The headless test " \
               & "runs the same code."
   end switch
   return empty
end adAboutScene

-- ==========================================================================
-- Clicks, the volume knob and the sound devices.
-- ==========================================================================

on mouseUp
   local tName
   set the defaultStack to the short name of this stack
   put the short name of the target into tName
   put false into sVolDrag
   adInitState
   if not adLoaded() then
      adShowMissing
      exit mouseUp
   end if
   if char 1 to 2 of tName is "Sc" and char 3 to -1 of tName is an integer then
      put false into sPlayAll
      adStartScene char 3 to -1 of tName
      exit mouseUp
   end if
   if char 1 to 3 of tName is among the items of "dvP,dvL" and char 4 to -1 of tName is an integer then
      if sMenuMap[tName] is not empty then
         adPickDevice sMenuMap[tName], the label of button tName
      end if
      exit mouseUp
   end if
   switch tName
      case "PlayAll"
         if sPlayAll then
            put false into sPlayAll
            adSyncButtons
         else
            put true into sPlayAll
            adStartScene 1
         end if
         break
      case "Pause"
         adTogglePause
         break
      case "Device"
         if the visible of group "gDevices" then
            adCloseDevices
         else
            adOpenDevices
         end if
         break
      case "dvClose"
         adCloseDevices
         break
      case "Checks"
         put false into sPlayAll
         adStartScene 6
         break
      case "Held"
         -- the click itself is what the browser waited for
         set the visible of button "Held" to false
         break
      case "cCopy"
         if sCkLog is not empty then
            set the clipboardData["text"] to sCkLog
            adStatus "The checks' " & the number of lines of sCkLog & " lines are on the clipboard.", empty
         end if
         break
   end switch
end mouseUp

on mouseDown
   local tName
   put the short name of the target into tName
   if tName is among the items of "VolTrack,VolFill,VolKnob" then
      put true into sVolDrag
      adVolumeFromX the mouseH
   end if
end mouseDown

on mouseMove pX, pY
   if sVolDrag is true then
      adVolumeFromX pX
   end if
end mouseMove

on mouseRelease
   put false into sVolDrag
end mouseRelease

command adVolumeFromX pX
   if pX is a number then
      adVolumeTo (pX - 740) / 156
   end if
end adVolumeFromX

-- The sound devices panel opens over the stage: what this machine can play
-- through and listen with, as the library's scan finds them. The scene
-- plays on underneath; a pick takes effect at once and closes the panel.
command adOpenDevices
   local tFound, tPlay, tListen, tI
   set the defaultStack to the short name of this stack
   if not adLoaded() then
      adShowMissing
      exit adOpenDevices
   end if
   put empty into sMenuMap
   put auDeviceScan() into tFound
   put adDeviceLine("The system's default", "play,0", sDevice is 0) into tPlay
   if the platform is not "HTML5" then
      put adDeviceLine("The silent device (nothing is heard)", "play,-1", sDevice is -1) after tPlay
   end if
   repeat with tI = 1 to auPlaybackDeviceCount()
      put adDeviceLine(adDeviceName(auPlaybackDeviceName(tI), auPlaybackDeviceIsDefault(tI)), "play," & tI, sDevice is tI) \
            after tPlay
   end repeat
   put adDeviceLine("The system's default microphone", "listen,0", sMicDevice is 0) into tListen
   if the platform is not "HTML5" then
      put adDeviceLine("The silent microphone (it hears silence)", "listen,-1", sMicDevice is -1) after tListen
   end if
   repeat with tI = 1 to auCaptureDeviceCount()
      put adDeviceLine(adDeviceName(auCaptureDeviceName(tI), auCaptureDeviceIsDefault(tI)), "listen," & tI, sMicDevice is tI) \
            after tListen
   end repeat
   adDeviceColumn "P", tPlay
   adDeviceColumn "L", tListen
   if tFound < 0 then
      put "No list of devices here (" & auLastError() & "); the defaults still work." into field "dvNote"
   else
      put "Found through " & adOr(auBackendName(), "the system") & ". The lit ones are in use; a pick takes effect at once." \
            into field "dvNote"
   end if
   set the visible of group "gDevices" to true
   adLight "Device", true
end adOpenDevices

command adCloseDevices
   set the defaultStack to the short name of this stack
   if there is a group "gDevices" then
      set the visible of group "gDevices" to false
   end if
   if there is a button "Device" then
      adLight "Device", false
   end if
end adCloseDevices

-- One row: what it says, what it picks ("play,N" or "listen,N"), and
-- whether it is the one in use, tab-separated.
function adDeviceLine pLabel, pPick, pInUse
   return pLabel & tab & pPick & tab & (pInUse is true) & return
end adDeviceLine

function adDeviceName pName, pDefault
   replace tab with space in pName
   replace return with space in pName
   if pName is empty then
      put "A device with no name" into pName
   end if
   if pDefault is true then
      put " (the default)" after pName
   end if
   return pName
end adDeviceName

-- Fills one column's buttons from its rows; more devices than buttons, and
-- the last button says how many more there are (the default reaches them).
private command adDeviceColumn pSide, pRows
   local tCount, tI, tName, tRow
   set the itemDelimiter to tab
   put the number of lines of pRows into tCount
   repeat with tI = 1 to kAdDeviceRows
      put "dv" & pSide & tI into tName
      put line tI of pRows into tRow
      if tI is kAdDeviceRows and tCount > kAdDeviceRows then
         put "and" && (tCount - kAdDeviceRows + 1) && "more: the default reaches them" & tab & tab & "false" into tRow
      end if
      set the visible of button tName to (tRow is not empty)
      set the label of button tName to item 1 of tRow
      adFitLabel tName
      put item 2 of tRow into sMenuMap[tName]
      adLight tName, (item 3 of tRow is "true")
   end repeat
end adDeviceColumn

-- A device's name can be longer than its button: cut, with an ellipsis,
-- to what fits in this system's font.
private command adFitLabel pButton
   local tFull
   put the label of button pButton into tFull
   repeat while the formattedWidth of button pButton > the width of button pButton and the number of chars of tFull > 8
      delete the last char of tFull
      set the label of button pButton to tFull & "..."
   end repeat
end adFitLabel

-- The button that picks pPick ("play,-1" ...), for the drive: it clicks it.
function adDeviceButton pPick
   local tKey
   repeat for each key tKey in sMenuMap
      if sMenuMap[tKey] is pPick then
         return tKey
      end if
   end repeat
   return empty
end adDeviceButton

command adPickDevice pPick, pLabel
   adCloseDevices
   if item 1 of pPick is "play" then
      adUseDevice item 2 of pPick
   else if item 1 of pPick is "listen" then
      put item 2 of pPick into sMicDevice
      if sScene is 5 then
         adStartScene 5
      end if
      adStatus "Listening with: " & pLabel & ". The microphone scene uses it from now on.", empty
   end if
end adPickDevice

-- ==========================================================================
-- Small helpers.
-- ==========================================================================

-- A whole number with commas: 352844 -> 352,844.
function adThousands pNumber
   local tText, tOut
   put round(pNumber) into tText
   repeat while the number of chars of tText > 3
      put comma & char -3 to -1 of tText before tOut
      delete char -3 to -1 of tText
   end repeat
   return tText & tOut
end adThousands

-- Where the window writes: the engine's temporary folder, which a browser
-- page has too (its own file system in memory).
function adTempFile pName
   local tFolder
   put specialFolderPath("temporary") into tFolder
   if tFolder is empty then
      put "/tmp" into tFolder
   end if
   return tFolder & "/" & pName
end adTempFile

-- A library's reason, without the words that only repeat what failed:
-- "could not open the playback device: Failed to open backend device"
-- becomes "Failed to open backend device".
function adShortWhy pWhy
   local tAt
   put the number of chars of pWhy into tAt
   repeat while tAt > 1
      if char tAt - 1 to tAt of pWhy is ": " then
         return char tAt + 1 to -1 of pWhy
      end if
      subtract 1 from tAt
   end repeat
   return pWhy
end adShortWhy

function adFileName pPath
   set the itemDelimiter to "/"
   return the last item of pPath
end adFileName

function adOr pText, pElse
   if pText is empty then
      return pElse
   end if
   return pText
end adOr

function adNear pA, pB, pTolerance
   if pA is not a number or pB is not a number then
      return false
   end if
   return abs(pA - pB) <= pTolerance
end adNear

-- ==========================================================================
-- 1. Beat machine. Five drums made in memory, then five bars and a last hit
-- at 120 beats a minute, scheduled a fifth of a second ahead on the
-- engine's clock: the script only has to be on time to within that.
-- ==========================================================================

command adBeatBegin
   put 0 into sBeatIndex
   put 0 into sGridBar
   put 0 into sGridStep
   put 0 into sNotes
   if not auGroupIsValid(sDrums) then
      put auGroupCreate(sEngine) into sDrums
   end if
   auGroupSetVolume sDrums, 0.9
   auGroupSetPan sDrums, 0
   auGroupSetPitch sDrums, 1
   auGroupStart sDrums
   adPaintGrid 1, 0
   adPaintGroup
   put empty into field "bNotes"
   if adKitReady() then
      adBeatGo
   else
      put "making" into sScenePhase
      put empty into sKit
      put "Making the drums in script..." into field "Caption"
   end if
end adBeatBegin

command adBeatEnd
   if auGroupIsValid(sDrums) then
      auGroupSetPan sDrums, 0
      auGroupSetPitch sDrums, 1
   end if
end adBeatEnd

command adBeatGo
   put "playing" into sScenePhase
   put adClock() into sSceneT0
   put sSceneT0 + 0.15 into sBeatStart
   put 0 into sBeatIndex
end adBeatGo

function adKitReady
   local tSound
   if the number of items of sKit is not 5 then
      return false
   end if
   repeat for each item tSound in sKit
      if not auSoundIsValid(tSound) then
         return false
      end if
   end repeat
   return true
end adKitReady

-- One instrument a frame: each is mixed by an offline engine into memory
-- (22,050 Hz mono floats) and becomes a sound of the real engine.
command adMakeKitStep
   local tMade, tVoice, tSound
   put the number of items of sKit into tMade
   if tMade >= 5 then
      exit adMakeKitStep
   end if
   put item tMade + 1 of "kick,snare,hat,bell,crash" into tVoice
   put auSoundFromPCM(sEngine, adRenderVoice(tVoice), "f32", 22050, 1) into tSound
   if tSound is 0 then
      adStatus "The " & tVoice & " was refused: " & auLastError(), "bad"
   end if
   if sKit is empty then
      put tSound into sKit
   else
      put comma & tSound after sKit
   end if
   put "Making the drums in script: " & item 1 to tMade + 1 of "kick,snare,hat,bell,crash" into field "Caption"
   replace comma with ", " in field "Caption"
   adSceneBar (tMade + 1) / 5
end adMakeKitStep

-- One instrument's samples. A kick is a sine that falls from 150 to 45 Hz
-- as it fades (its frequency changed between short renders); a snare is
-- noise over a triangle; a hat a short hiss; a bell two sines, the brighter
-- dying first; a crash white noise over a longer pink one.
function adRenderVoice pVoice
   local tOff, tA, tB, tData, tI
   put auEngineCreateOffline(22050, 1) into tOff
   if tOff is 0 then
      return empty
   end if
   switch pVoice
      case "kick"
         put auSoundTone(tOff, "sine", 150, 1) into tA
         auSoundFade tA, 1, 0, 0.4
         auSoundStart tA
         repeat with tI = 0 to 33
            auSoundSetFrequency tA, 150 * (0.3 ^ (tI / 33))
            put auEngineRender(tOff, 256, "f32") after tData
         end repeat
         break
      case "snare"
         put auSoundNoise(tOff, "white", 0.6) into tA
         put auSoundTone(tOff, "triangle", 185, 0.6) into tB
         auSoundFade tA, 1, 0, 0.2
         auSoundFade tB, 1, 0, 0.08
         auSoundStart tA
         auSoundStart tB
         put auEngineRender(tOff, 4851, "f32") into tData
         break
      case "hat"
         put auSoundNoise(tOff, "white", 0.35) into tA
         auSoundFade tA, 1, 0, 0.05
         auSoundStart tA
         put auEngineRender(tOff, 1323, "f32") into tData
         break
      case "bell"
         put auSoundTone(tOff, "sine", 660, 0.45) into tA
         put auSoundTone(tOff, "sine", 1650, 0.15) into tB
         auSoundFade tA, 1, 0, 0.7
         auSoundFade tB, 1, 0, 0.25
         auSoundStart tA
         auSoundStart tB
         put auEngineRender(tOff, 16538, "f32") into tData
         break
      case "crash"
         put auSoundNoise(tOff, "white", 0.3) into tA
         put auSoundNoise(tOff, "pink", 0.35) into tB
         auSoundFade tA, 1, 0, 0.5
         auSoundFade tB, 1, 0, 1.3
         auSoundStart tA
         auSoundStart tB
         put auEngineRender(tOff, 28665, "f32") into tData
         break
   end switch
   auEngineFree tOff
   return tData
end adRenderVoice

command adBeatFrame
   local tNow, tAt, tHeard, tBar, tStep, tInBar
   if sScenePhase is "making" then
      adMakeKitStep
      if the number of items of sKit >= 5 then
         adBeatGo
      end if
      exit adBeatFrame
   end if
   put adClock() into tNow
   -- every step that falls within the next fifth of a second
   repeat while sBeatIndex <= kAdLastStep and sBeatStart + sBeatIndex * kAdStepSeconds < tNow + 0.2
      adBeatNotes sBeatIndex, sBeatStart + sBeatIndex * kAdStepSeconds
      add 1 to sBeatIndex
   end repeat
   -- what is being heard now
   put (tNow - sBeatStart) / kAdStepSeconds into tAt
   if tAt < 0 then
      exit adBeatFrame
   end if
   put min(kAdLastStep, trunc(tAt)) into tHeard
   put tHeard div 16 + 1 into tBar
   put tHeard mod 16 + 1 into tStep
   put min(1, (tAt - (tBar - 1) * 16) / 16) into tInBar
   adBeatGroupMoves tBar, tInBar
   adPaintGrid tBar, tStep
   put adBarWords(tBar) into field "Caption"
   put "Notes so far: " & sNotes & ". Sounds on the engine now: " & auEngineSoundCount(sEngine) \
         & " (each note is freed by the poll that reports its end)." into field "bNotes"
   adSceneBar tAt / (kAdLastStep + 12)
   if tAt >= kAdLastStep + 12 then
      adSceneDone
   end if
end adBeatFrame

-- Each row of each bar of the show: x is a note.
function adBarRow pBar, pRow
   switch pRow
      case 1
         if pBar <= 4 then
            return "x.....x.x......."
         else if pBar is 5 then
            return "x.....x.x.x.x.x."
         end if
         return "x..............."
      case 2
         if pBar <= 4 then
            return "....x.......x..."
         else if pBar is 5 then
            return "....x.......xxxx"
         end if
         return "................"
      case 3
         -- the last bar's first hat is the crash
         if pBar <= 4 then
            return "x.x.x.x.x.x.x.x."
         else if pBar is 5 then
            return "xxxxxxxxxxxxxxxx"
         end if
         return "x..............."
      case 4
         if pBar is 1 then
            return "................"
         else if pBar <= 5 then
            return "x..x..x...x..x.."
         end if
         return "x..............."
   end switch
   return "................"
end adBarRow

function adBarWords pBar
   switch pBar
      case 1
         return "Bar 1: kick, snare and hat, every hit a clone started on the engine's clock"
      case 2
         return "Bar 2: the bell joins; every note is the same sound at another pitch"
      case 3
         return "Bar 3: one call to the drums' group pans them all from left to right"
      case 4
         return "Bar 4: one call raises the drums' pitch; the bell is not in the group"
      case 5
         return "Bar 5: a fill, sixteen hats to the bar"
   end switch
   return "The last hit: four bells at once and a crash"
end adBarWords

-- One step: a clone of each instrument whose square is on, started at
-- pWhen and freed by the poll that reports its end. A clone does not
-- inherit a group, so each drum is put in the drums' group; the bell is
-- not, and plays its step's note by its pitch.
command adBeatNotes pIndex, pWhen
   local tBar, tStep, tRow, tShot, tVoice, tShift
   put pIndex div 16 + 1 into tBar
   put pIndex mod 16 + 1 into tStep
   repeat with tRow = 1 to 4
      if char tStep of adBarRow(tBar, tRow) is "x" then
         if tRow is 4 then
            if tBar is 6 then
               repeat for each item tShift in "0,4,7,12"
                  adBellAt pWhen, tShift, 0.5
               end repeat
            else
               put item tStep of kAdBellNotes into tShift
               if tBar is 4 then
                  add 5 to tShift
               end if
               adBellAt pWhen, tShift, 0.8
            end if
         else
            put item tRow of sKit into tVoice
            if tRow is 3 and tBar is 6 then
               put item 5 of sKit into tVoice
            end if
            put auSoundClone(tVoice) into tShot
            if tShot > 0 then
               auSoundSetGroup tShot, sDrums
               auSoundSetAutoFree tShot, true
               auSoundStartAt tShot, pWhen
               add 1 to sNotes
            end if
         end if
      end if
   end repeat
end adBeatNotes

command adBellAt pWhen, pSemitones, pVolume
   local tShot
   put auSoundClone(item 4 of sKit) into tShot
   if tShot > 0 then
      auSoundSetPitch tShot, 2 ^ (pSemitones / 12)
      auSoundSetVolume tShot, pVolume
      auSoundSetAutoFree tShot, true
      auSoundStartAt tShot, pWhen
      add 1 to sNotes
   end if
end adBellAt

-- Bar 3 pans the drums' group across, bar 4 raises its pitch; one call each
-- frame moves every drum in it, the ones already playing too.
command adBeatGroupMoves pBar, pInBar
   if not auGroupIsValid(sDrums) then
      exit adBeatGroupMoves
   end if
   if pBar is 3 then
      auGroupSetPan sDrums, round(-0.8 + 1.6 * pInBar, 2)
      auGroupSetPitch sDrums, 1
   else if pBar is 4 then
      auGroupSetPan sDrums, 0
      auGroupSetPitch sDrums, round(1 + 0.4 * pInBar, 3)
   else
      auGroupSetPan sDrums, 0
      auGroupSetPitch sDrums, 1
   end if
   adPaintGroup
end adBeatGroupMoves

-- The group's pan and pitch, as the library reads them back.
command adPaintGroup
   local tPan, tPitch, tX
   if not auGroupIsValid(sDrums) then
      put 0 into tPan
      put 1 into tPitch
   else
      put auGroupPan(sDrums) into tPan
      put auGroupPitch(sDrums) into tPitch
   end if
   put 250 + round(150 * tPan) into tX
   set the rect of graphic "bPanDot" to tX - 6, 344, tX + 6, 356
   put "pan " & format("%.2f", tPan) & "   pitch " & format("%.2f", tPitch) into field "bGrpText"
end adPaintGroup

-- The grid shows the bar being heard; the step being heard is lit.
command adPaintGrid pBar, pStep
   local tRow, tStep, tLine
   if pBar is not sGridBar then
      put pBar into sGridBar
      put 0 into sGridStep
      repeat with tRow = 1 to 4
         put adBarRow(pBar, tRow) into tLine
         repeat with tStep = 1 to 16
            adCell tRow, tStep, (char tStep of tLine is "x"), false
         end repeat
      end repeat
   end if
   if pStep is sGridStep then
      exit adPaintGrid
   end if
   if sGridStep > 0 then
      repeat with tRow = 1 to 4
         adCell tRow, sGridStep, (char sGridStep of adBarRow(pBar, tRow) is "x"), false
      end repeat
   end if
   if pStep > 0 then
      repeat with tRow = 1 to 4
         adCell tRow, pStep, (char pStep of adBarRow(pBar, tRow) is "x"), true
      end repeat
      set the left of graphic "bHead" to adCellLeft(pStep) - 3
      set the visible of graphic "bHead" to true
   else
      set the visible of graphic "bHead" to false
   end if
   put pStep into sGridStep
end adPaintGrid

-- A square: its row's colour when it has a note (bright while heard), the
-- stage's line colour when it has none.
command adCell pRow, pStep, pOn, pNow
   local tName, tInk
   put "bC" & pRow & "-" & pStep into tName
   if pOn then
      put item pRow of kAdRowInk into tInk
   else if pNow then
      put kAdEdge into tInk
   else
      put kAdLine into tInk
   end if
   set the backgroundColor of graphic tName to tInk
   set the foregroundColor of graphic tName to tInk
   if pOn and not pNow then
      set the blendLevel of graphic tName to 45
   else
      set the blendLevel of graphic tName to 0
   end if
end adCell

-- ==========================================================================
-- 2. Round your head. You are in the middle, seen from above; the sound
-- circles you, flies past, comes back and holds still while you turn.
-- ==========================================================================

command adFlyBegin
   put 0 into sBeeX
   put -4 into sBeeZ
   put empty into sTrail
   put 0 into sWaveAt
   adFace 0
   -- a buzz: a sawtooth is rich in high notes, and those are what an ear
   -- uses to tell where a sound is
   put auSoundTone(sEngine, "sawtooth", 196, 0.35) into sBee
   if sBee is 0 then
      adStatus "No sound to fly: " & auLastError(), "bad"
      put "none" into sScenePhase
      exit adFlyBegin
   end if
   adOwn sBee
   auSoundSetSpatial sBee, true
   -- full strength within 2 units, half at the circle's 4
   auSoundSetDistanceRange sBee, 2, 40
   auSoundSetRolloff sBee, 1
   auSoundSetDoppler sBee, 1
   auSoundSetPosition sBee, sBeeX, 0, sBeeZ
   auSoundFade sBee, 0, 1, 0.4
   auSoundStart sBee
   put "orbit" into sScenePhase
   adPaintFly 0
end adFlyBegin

command adFlyEnd
   adFace 0
   put 0 into sBee
end adFlyEnd

command adFlyFrame
   local tT, tA, tW, tR, tX, tZ, tVX, tVZ, tF
   put adSceneTime() into tT
   if sScenePhase is "none" then
      if tT >= 3 then
         adSceneDone
      end if
      exit adFlyFrame
   end if
   put 4 into tR
   put 2.2 into tW
   put 0 into tVX
   put 0 into tVZ
   put sBeeX into tX
   put sBeeZ into tZ
   if tT < 5 then
      -- round you, clockwise seen from above: ahead, right, behind, left
      put -pi / 2 + tW * tT into tA
      put tR * cos(tA) into tX
      put tR * sin(tA) into tZ
      put -tR * tW * sin(tA) into tVX
      put tR * tW * cos(tA) into tVZ
      put "It circles you: ahead, to your right, behind you, to your left" into field "Caption"
   else if tT < 5.3 then
      -- a cut: it fades out where it is...
      if sScenePhase is "orbit" then
         auSoundFade sBee, -1, 0, 0.25
         put "cut" into sScenePhase
         put empty into sTrail
      end if
   else if tT < 8.6 then
      -- ...and flies past you, far left to far right, its speed told to the
      -- library and the Doppler effect made six times as strong
      if sScenePhase is "cut" then
         auSoundSetDoppler sBee, 6
         auSoundFade sBee, 0, 1, 0.3
         put "past" into sScenePhase
      end if
      put -14 + 28 * (tT - 5.3) / 3.3 into tX
      put -1.5 into tZ
      put 28 / 3.3 into tVX
      put "Now it flies past you: hear its pitch fall as it goes by (Doppler)" into field "Caption"
   else if tT < 9.6 then
      -- back, to wait ahead of you and to the right
      if sScenePhase is "past" then
         auSoundSetDoppler sBee, 1
         put "back" into sScenePhase
      end if
      put tT - 8.6 into tF
      put 14 - 11 * tF into tX
      put -1.5 - 1.5 * tF into tZ
      put -11 into tVX
      put -1.5 into tVZ
      put "It comes back, and waits ahead of you and to the right" into field "Caption"
   else
      -- it holds still; you turn round once, and it moves through your ears
      put 3 into tX
      put -3 into tZ
      adFace 360 * min(1, (tT - 9.6) / 3.4)
      put "Now you turn round once: it stays where it is, and passes from ear to ear" into field "Caption"
      if tT >= 13.1 and sScenePhase is not "fading" then
         auSoundStopWithFade sBee, 0.8
         put "fading" into sScenePhase
      end if
      if tT >= 14 then
         adSceneDone
         exit adFlyFrame
      end if
   end if
   put round(tX, 3) into sBeeX
   put round(tZ, 3) into sBeeZ
   auSoundSetPosition sBee, sBeeX, 0, sBeeZ
   auSoundSetVelocity sBee, round(tVX, 3), 0, round(tVZ, 3)
   adPaintFly tT
   adSceneBar tT / 14
end adFlyFrame

-- Turns you: 0 degrees faces up the screen (-z), 90 faces right (+x).
command adFace pDegrees
   local tRad
   put pDegrees into sFacing
   repeat while sFacing < 0
      add 360 to sFacing
   end repeat
   repeat while sFacing >= 360
      subtract 360 from sFacing
   end repeat
   put sFacing * pi / 180 into tRad
   if auEngineIsValid(sEngine) then
      auEngineSetListenerDirection sEngine, round(sin(tRad), 4), 0, round(-cos(tRad), 4)
   end if
end adFace

command adPaintFly pT
   local tX, tY, tRad, tFade, tI, tAge, tSize, tDistance, tBearing, tOut
   set the defaultStack to the short name of this stack
   put kAdFlyX + round(sBeeX * kAdFlyScale) into tX
   put kAdFlyY + round(sBeeZ * kAdFlyScale) into tY
   -- the orb, its glow and its trail; it fades out and in across the cut
   put 0 into tFade
   if pT >= 5 and pT < 5.3 then
      put round(100 * (pT - 5) / 0.3) into tFade
   else if pT >= 5.3 and pT < 5.6 then
      put round(100 * (5.6 - pT) / 0.3) into tFade
   end if
   set the rect of graphic "fBee" to tX - 8, tY - 8, tX + 8, tY + 8
   set the rect of graphic "fGlow" to tX - 20, tY - 20, tX + 20, tY + 20
   set the blendLevel of graphic "fBee" to tFade
   set the blendLevel of graphic "fGlow" to 78 + round(22 * tFade / 100)
   if tFade is 0 then
      put tX & comma & tY & return after sTrail
      if the number of lines of sTrail > 14 then
         delete line 1 of sTrail
      end if
   end if
   if the number of lines of sTrail >= 2 then
      set the points of graphic "fTrail" to sTrail
      set the visible of graphic "fTrail" to true
   else
      set the visible of graphic "fTrail" to false
   end if
   -- two rings of sound going out from it, half a period apart
   repeat with tI = 1 to 2
      put (pT + (tI - 1) * 0.6) mod 1.2 into tAge
      put round(10 + 50 * tAge / 1.2) into tSize
      set the rect of graphic ("fWave" & tI) to tX - tSize, tY - tSize, tX + tSize, tY + tSize
      set the blendLevel of graphic ("fWave" & tI) to min(100, 35 + round(65 * tAge / 1.2) + tFade)
      set the visible of graphic ("fWave" & tI) to true
   end repeat
   -- you: a head with a nose the way you face, and an ear each side
   put sFacing * pi / 180 into tRad
   set the points of graphic "fNose" to round(kAdFlyX + 22 * sin(tRad)) & "," & round(kAdFlyY - 22 * cos(tRad)) & return \
         & round(kAdFlyX + 9 * sin(tRad + 1.1)) & "," & round(kAdFlyY - 9 * cos(tRad + 1.1)) & return \
         & round(kAdFlyX + 9 * sin(tRad - 1.1)) & "," & round(kAdFlyY - 9 * cos(tRad - 1.1))
   adPlaceDot "fEarR", kAdFlyX + round(14 * cos(tRad)), kAdFlyY + round(14 * sin(tRad)), 4
   adPlaceDot "fEarL", kAdFlyX - round(14 * cos(tRad)), kAdFlyY - round(14 * sin(tRad)), 4
   -- where it is, in words
   put sqrt(sBeeX * sBeeX + sBeeZ * sBeeZ) into tDistance
   put atan2(sBeeX, -sBeeZ) * 180 / pi - sFacing into tBearing
   repeat while tBearing > 180
      subtract 360 from tBearing
   end repeat
   repeat while tBearing <= -180
      add 360 to tBearing
   end repeat
   put format("%.1f", tDistance) & " units away," & return & adBearingWords(tBearing) & return into tOut
   put adXYZ(auSoundPositionXYZ(sBee)) & return after tOut
   put "you face " & round(sFacing) & " degrees" after tOut
   put tOut into field "fReadout"
end adPaintFly

-- "3.53200006,0,-1.8769999" (the library's floats) as "x 3.5  y 0.0  z -1.9".
function adXYZ pXYZ
   local tOut, tI
   if the number of items of pXYZ is not 3 then
      return empty
   end if
   repeat with tI = 1 to 3
      put (item tI of "x,y,z") & " " & format("%.1f", round(item tI of pXYZ, 1) + 0) & "  " after tOut
   end repeat
   return char 1 to -3 of tOut
end adXYZ

command adPlaceDot pName, pX, pY, pRadius
   set the rect of graphic pName to pX - pRadius, pY - pRadius, pX + pRadius, pY + pRadius
end adPlaceDot

function adBearingWords pDegrees
   if abs(pDegrees) <= 30 then
      return "ahead of you"
   end if
   if abs(pDegrees) >= 150 then
      return "behind you"
   end if
   if pDegrees > 0 then
      return "to your right"
   end if
   return "to your left"
end adBearingWords

-- ==========================================================================
-- 3. Synth and fades. One tone of each shape plays the arpeggio in turn,
-- gliding between its notes; then a chord swells in and dies away.
-- ==========================================================================

command adSynthBegin
   local tI, tTone
   put "0,0,0,0" into sVoices
   repeat with tI = 1 to 4
      put auSoundTone(sEngine, item tI of kAdShapes, item 1 of kAdArpHertz, item tI of kAdShapeAmp) into tTone
      put tTone into item tI of sVoices
      adOwn tTone
   end repeat
   put "0,0,0,0" into sChordTones
   put 0 into sNoise
   put 0 into sVoiceNow
   put 0 into sHertzNow
   put empty into sLitKeys
   adLightKeys empty
   repeat with tI = 1 to 4
      set the visible of graphic ("yPan" & tI) to false
      set the visible of field ("yPanN" & tI) to false
   end repeat
   set the visible of field "yPanCap" to false
   set the visible of graphic "yPanTrack" to false
   repeat with tI = 1 to 4
      set the visible of button ("ySh" & tI) to true
      adLight "ySh" & tI, false
   end repeat
   put "arp" into sScenePhase
end adSynthBegin

command adSynthEnd
   put 0 into sVoiceNow
   put "0,0,0,0" into sVoices
   put "0,0,0,0" into sChordTones
   put 0 into sNoise
end adSynthEnd

command adSynthFrame
   local tT, tShape, tNote, tTarget, tTone, tI, tFrom
   put adSceneTime() into tT
   if tT < 8.8 then
      put min(4, trunc(tT / 2.2) + 1) into tShape
      put min(4, trunc((tT - (tShape - 1) * 2.2) / kAdNoteSeconds) + 1) into tNote
      put item tNote of kAdArpHertz into tTarget
      if tShape is not sVoiceNow then
         -- the shape that was playing fades out as the next fades in
         if sVoiceNow > 0 then
            auSoundStopWithFade item sVoiceNow of sVoices, 0.06
         end if
         put tShape into sVoiceNow
         repeat with tI = 1 to 4
            adLight "ySh" & tI, (tI is tShape)
         end repeat
         put tTarget into sHertzNow
         put item tShape of sVoices into tTone
         auSoundSetFrequency tTone, sHertzNow
         auSoundFade tTone, 0, 1, 0.05
         auSoundStart tTone
         adPaintShape tShape
      end if
      -- a glide: most of the way to the note each frame (portamento)
      put sHertzNow into tFrom
      put sHertzNow + (tTarget - sHertzNow) * 0.6 into sHertzNow
      if abs(tTarget - sHertzNow) < 0.5 then
         put tTarget into sHertzNow
      end if
      if sHertzNow is not tFrom then
         auSoundSetFrequency item sVoiceNow of sVoices, sHertzNow
      end if
      adLightKeys item tNote of kAdArpMidi
      put "A " & item tShape of kAdShapes & " tone, amplitude " & item tShape of kAdShapeAmp & ", now at " \
            & format("%.1f", sHertzNow) & " Hz: note " & tNote & " of the arpeggio C3, E3, G3, C4" into field "yNote"
      put "The " & item tShape of kAdShapes & " wave, as the device plays it: look at the line below" into field "Caption"
   else if tT < 13.6 then
      if sScenePhase is "arp" then
         adSynthChord
      end if
      -- a slow shimmer on the top note, by its pitch
      put item 4 of sChordTones into tTone
      if auSoundIsValid(tTone) then
         auSoundSetPitch tTone, round(1 + 0.004 * sin(tT * 31.4), 4)
      end if
      if tT >= 11.4 and sScenePhase is "chord" then
         repeat for each item tTone in sChordTones
            auSoundStopWithFade tTone, 1.8
         end repeat
         auSoundStopWithFade sNoise, 2
         put "fade" into sScenePhase
      end if
      repeat with tI = 1 to 4
         set the blendLevel of graphic ("yPan" & tI) to adChordBlend(tT)
      end repeat
      if sScenePhase is "chord" then
         put "Swelling in over 1.6 seconds (auSoundFade from 0 to 1), with pink noise under it" into field "yNote"
         put "A chord, spread from left to right" into field "Caption"
      else
         put "Dying away over 1.8 seconds (auSoundStopWithFade)" into field "yNote"
         put "And it dies away" into field "Caption"
      end if
   else
      adSceneDone
      exit adSynthFrame
   end if
   adSceneBar tT / 13.6
end adSynthFrame

-- The chord: four triangle tones spread across, faded in together, and
-- pink noise under them, quieter and slower.
command adSynthChord
   local tI, tTone
   if sVoiceNow > 0 then
      auSoundStopWithFade item sVoiceNow of sVoices, 0.1
   end if
   put 0 into sVoiceNow
   repeat with tI = 1 to 4
      put auSoundTone(sEngine, "triangle", item tI of kAdChordHertz, 0.2) into tTone
      put tTone into item tI of sChordTones
      adOwn tTone
      auSoundSetPan tTone, item tI of kAdChordPan
      auSoundFade tTone, 0, 1, 1.6
      auSoundStart tTone
   end repeat
   put auSoundNoise(sEngine, "pink", 0.06) into sNoise
   adOwn sNoise
   auSoundFade sNoise, 0, 1, 2
   auSoundStart sNoise
   put "chord" into sScenePhase
   adPaintShape 5
   adLightKeys kAdChordMidi
   repeat with tI = 1 to 4
      set the visible of button ("ySh" & tI) to false
   end repeat
   set the visible of field "yPanCap" to true
   set the visible of graphic "yPanTrack" to true
   repeat with tI = 1 to 4
      -- each voice's pan, as the library reads it back
      adPlaceDot "yPan" & tI, 336 + round(240 * auSoundPan(item tI of sChordTones)), 352, 7
      set the backgroundColor of graphic ("yPan" & tI) to item tI of kAdRowInk
      set the foregroundColor of graphic ("yPan" & tI) to item tI of kAdRowInk
      set the rect of field ("yPanN" & tI) to (the left of graphic ("yPan" & tI)) - 13, 360, (the right of graphic ("yPan" & tI)) + 13, 376
      set the visible of graphic ("yPan" & tI) to true
      set the visible of field ("yPanN" & tI) to true
   end repeat
end adSynthChord

function adChordBlend pT
   if pT < 8.8 then
      return 100
   end if
   if pT < 10.4 then
      return round(85 * (10.4 - pT) / 1.6)
   end if
   if pT < 11.4 then
      return 0
   end if
   return min(90, round(90 * (pT - 11.4) / 1.8))
end adChordBlend

-- The shape's name and its outline (two waves of it): 5 is the chord.
command adPaintShape pShape
   local tPts, tI, tX, tY
   put item pShape of "SINE,SQUARE,TRIANGLE,SAWTOOTH,CHORD" into field "yName"
   switch pShape
      case 1
         repeat with tI = 0 to 64
            put 316 + 5 * tI & "," & round(129 - 15 * sin(tI * pi / 16)) & return after tPts
         end repeat
         break
      case 2
         put "316,144" & return & "316,114" & return & "396,114" & return & "396,144" & return & "476,144" & return \
               & "476,114" & return & "556,114" & return & "556,144" & return & "636,144" & return into tPts
         break
      case 3
         put "316,129" & return & "356,114" & return & "436,144" & return & "516,114" & return & "596,144" & return \
               & "636,129" & return into tPts
         break
      case 4
         repeat with tI = 0 to 3
            put 316 + 80 * tI & ",144" & return & 396 + 80 * tI & ",114" & return & 396 + 80 * tI & ",144" & return after tPts
         end repeat
         break
      case 5
         repeat with tI = 0 to 96
            put tI / 96 * 4 * pi into tX
            put (sin(tX) + sin(tX * 1.5) + sin(tX * 2) + sin(tX * 2.52)) / 4 into tY
            put 316 + round(320 * tI / 96) & "," & round(129 - 16 * tY) & return after tPts
         end repeat
         break
   end switch
   delete the last char of tPts
   set the points of graphic "yIcon" to tPts
end adPaintShape

-- Lights the keys of the notes given (MIDI numbers, C3 = 48), white keys
-- only: every note here is one.
command adLightKeys pMidi
   local tWant, tNote, tKey, tI
   repeat for each item tNote in pMidi
      put adWhiteKey(tNote) into tKey
      if tKey > 0 then
         put tKey & comma after tWant
      end if
   end repeat
   if tWant is sLitKeys then
      exit adLightKeys
   end if
   repeat with tI = 1 to 15
      if tI is among the items of tWant then
         set the backgroundColor of graphic ("yW" & tI) to kAdAccent
         set the foregroundColor of graphic ("yW" & tI) to kAdAccent
      else
         set the backgroundColor of graphic ("yW" & tI) to kAdKeyWhite
         set the foregroundColor of graphic ("yW" & tI) to kAdKeyWhite
      end if
   end repeat
   put tWant into sLitKeys
end adLightKeys

-- The white key (1 to 15) of a MIDI note from C3, or 0 for a black one.
function adWhiteKey pMidi
   local tOctave, tPlace
   if pMidi is not an integer or pMidi < 48 or pMidi > 72 then
      return 0
   end if
   put (pMidi - 48) div 12 into tOctave
   put item ((pMidi - 48) mod 12) + 1 of "1,0,2,0,3,4,0,5,0,6,0,7" into tPlace
   if tPlace is 0 then
      return 0
   end if
   return tOctave * 7 + tPlace
end adWhiteKey

-- ==========================================================================
-- 4. A tape made here. An offline engine mixes two seconds of music a tenth
-- of a second a frame (it could do it all at once; here you can watch),
-- the samples become a WAV file, and the file is played three ways.
-- ==========================================================================

command adTapeBegin
   local tI
   if auEngineIsValid(sTapeOff) then
      auEngineFree sTapeOff
   end if
   put auEngineCreateOffline(44100, 2) into sTapeOff
   put 0 into sTapeFrames
   put empty into sTapeData
   put empty into sTapeTop
   put empty into sTapeBottom
   put empty into sTapeClones
   put empty into sTapeWav
   put 0 into sTape
   put 0 into sTapeStream
   put the milliseconds into sTapeMs
   repeat with tI = 1 to 3
      set the visible of graphic ("tHead" & tI) to false
      set the visible of field ("tLab" & tI) to false
   end repeat
   set the visible of graphic "tRange" to false
   set the visible of graphic "tWave" to false
   set the rect of graphic "tProg" to 24, 306, 25, 312
   put "MAKING THE TAPE" into field "tName"
   put empty into field "tStat"
   if sTapeOff is 0 then
      put "No tape: an offline engine was refused (" & auLastError() & ")." into field "tFacts"
      put "NO TAPE" into field "tName"
      put "none" into sScenePhase
      exit adTapeBegin
   end if
   adTuneNotes sTapeOff
   put "making" into sScenePhase
   put "An offline engine mixes the tape into memory, as fast as it is asked: here a tenth of a second a frame, " \
         & "so you can watch it being made." into field "tFacts"
end adTapeBegin

command adTapeEnd
   if auEngineIsValid(sTapeOff) then
      auEngineFree sTapeOff
   end if
   put 0 into sTapeOff
   put 0 into sTape
   put 0 into sTapeStream
   put empty into sTapeClones
end adTapeEnd

-- The four notes, placed on the offline engine's clock from left to right
-- (auSoundStartAt, auSoundStopAt, auSoundSetPan).
command adTuneNotes pOff
   local tI, tSound
   repeat with tI = 1 to 4
      put auSoundTone(pOff, "triangle", item tI of kAdTuneNotes, 0.3) into tSound
      auSoundSetPan tSound, (tI - 2.5) / 2
      auSoundStartAt tSound, (tI - 1) * 0.25
      auSoundStopAt tSound, (tI - 1) * 0.25 + 0.22
   end repeat
end adTuneNotes

-- Then, a second in, the same four as a chord that fades away.
command adTuneChord pOff
   local tI, tSound
   repeat with tI = 1 to 4
      put auSoundTone(pOff, "sine", item tI of kAdTuneNotes, 0.18) into tSound
      auSoundFade tSound, 1, 0, 0.95
      auSoundStart tSound
   end repeat
end adTuneChord

-- The same tape all at once, for the checks: the bytes of its WAV file.
function adMakeTune
   local tOff, tData
   put auEngineCreateOffline(44100, 2) into tOff
   if tOff is 0 then
      return empty
   end if
   adTuneNotes tOff
   put auEngineRender(tOff, 44100, "s16") into tData
   adTuneChord tOff
   put auEngineRender(tOff, 44100, "s16") after tData
   auEngineFree tOff
   return auWAVEncode(tData, "s16", 44100, 2)
end adMakeTune

command adTapeFrame
   local tT
   if sScenePhase is "making" then
      adTapeMakeStep
      exit adTapeFrame
   end if
   put adSceneTime() into tT
   switch sScenePhase
      case "none"
         if tT >= 3 then
            adSceneDone
            exit adTapeFrame
         end if
         break
      case "stream"
         if sTapeStream is not 0 then
            adTapeHead 1, sTapeStream, "streamed"
         else
            adTapeHead 1, sTape, "from memory"
         end if
         if tT >= 2.4 then
            adTapeClonesGo
         end if
         break
      case "clones"
         adTapeHead 1, item 1 of sTapeClones, "x1.00"
         adTapeHead 2, item 2 of sTapeClones, "x1.26"
         adTapeHead 3, item 3 of sTapeClones, "x1.50"
         if tT >= 2.4 then
            adTapeLoopGo
         end if
         break
      case "loop"
         auSoundSetPitch sTape, round(1 + 0.3 * sin((tT * 2 * pi) / 2.4), 3)
         adTapeHead 1, sTape, "x" & format("%.2f", auSoundPitch(sTape))
         if tT >= 6.5 then
            auSoundStopWithFade sTape, 0.8
            put "fading" into sScenePhase
         end if
         break
      case "fading"
         adTapeHead 1, sTape, "x" & format("%.2f", auSoundPitch(sTape))
         if tT >= 7.5 then
            adSceneDone
            exit adTapeFrame
         end if
         break
   end switch
   adSceneBar adTapeProgress(tT)
end adTapeFrame

-- How far through the whole show: making, stream, clones, loop.
function adTapeProgress pT
   switch sScenePhase
      case "stream"
         return 0.1 + 0.2 * pT / 2.4
      case "clones"
         return 0.3 + 0.2 * pT / 2.4
      case "loop"
      case "fading"
         return 0.5 + 0.5 * pT / 7.5
   end switch
   return 0
end adTapeProgress

-- One tenth of a second more of the tape, and its picture so far.
command adTapeMakeStep
   local tChunk
   put auEngineRender(sTapeOff, kAdTuneChunk, "s16") into tChunk
   put tChunk after sTapeData
   add kAdTuneChunk to sTapeFrames
   if sTapeFrames is 44100 then
      adTuneChord sTapeOff
   end if
   adTapePicture
   set the rect of graphic "tProg" to 24, 306, 24 + max(1, round(624 * sTapeFrames / kAdTuneFrames)), 312
   put "Mixing a tape in script, a tenth of a second a frame" into field "Caption"
   put format("%.1f", sTapeFrames / 44100) & " of 2.0 seconds mixed" into field "tStat"
   adSceneBar 0.1 * sTapeFrames / kAdTuneFrames
   if sTapeFrames >= kAdTuneFrames then
      adTapeFinish
   end if
end adTapeMakeStep

-- The picture: for each column the tape has reached, the loudest of 16
-- samples of each side, the left above the line and the right below it.
command adTapePicture
   local tC, tFrom, tTo, tProbe, tAt, tLeft, tRight, tMostL, tMostR, tX, tDone
   put the number of lines of sTapeTop into tDone
   repeat with tC = tDone to kAdTuneColumns - 1
      put (tC * kAdTuneFrames) div kAdTuneColumns into tFrom
      put ((tC + 1) * kAdTuneFrames) div kAdTuneColumns into tTo
      if tTo > sTapeFrames then
         exit repeat
      end if
      put 0 into tMostL
      put 0 into tMostR
      repeat with tProbe = 0 to 15
         put tFrom + ((tTo - tFrom - 1) * tProbe) div 15 into tAt
         get binaryDecode("ss", byte 4 * tAt + 1 to 4 * tAt + 4 of sTapeData, tLeft, tRight)
         put max(tMostL, abs(tLeft)) into tMostL
         put max(tMostR, abs(tRight)) into tMostR
      end repeat
      put 28 + round(616 * tC / (kAdTuneColumns - 1)) into tX
      put tX & "," & round(230 - min(66, 150 * tMostL / 32768)) & return after sTapeTop
      put tX & "," & round(230 + min(66, 150 * tMostR / 32768)) & return before sTapeBottom
   end repeat
   if the number of lines of sTapeTop >= 2 then
      set the points of graphic "tWave" to sTapeTop & sTapeBottom & line 1 of sTapeTop
      set the visible of graphic "tWave" to true
   end if
end adTapePicture

-- The tape is made: a WAV file in memory, written to disk, streamed back
-- from there; and the same bytes loaded whole, to be cloned and looped.
command adTapeFinish
   local tWords, tRefusal
   put the milliseconds - sTapeMs into sTapeMs
   auEngineFree sTapeOff
   put 0 into sTapeOff
   put auWAVEncode(sTapeData, "s16", 44100, 2) into sTapeWav
   put adTempFile("audioxt-demo-tape.wav") into sTapePath
   put sTapeWav into URL ("binfile:" & sTapePath)
   if the result is empty then
      put auSoundLoad(sEngine, sTapePath, true) into sTapeStream
      adOwn sTapeStream
   end if
   put auSoundLoadData(sEngine, sTapeWav, false) into sTape
   adOwn sTape
   put "A WAV file of " & adThousands(the number of bytes in sTapeWav) & " bytes, made in " & format("%.2f", sTapeMs / 1000) \
         & " s: two seconds at 44,100 Hz, stereo, 16-bit (auWAVEncode)." into tWords
   if sTapeStream is not 0 then
      put " Written to " & adFileName(sTapePath) & " and streamed back from there as it plays (auSoundLoad, streaming)." after tWords
      -- a stream has no samples to share, so it cannot be cloned; the
      -- library says so, in words
      if auSoundClone(sTapeStream) is 0 then
         put auLastError() into tRefusal
      end if
   else
      put " It could not be written to a file here, so it plays from memory (auSoundLoadData)." after tWords
   end if
   put tWords into field "tFacts"
   if sTapeStream is not 0 then
      put "STREAMED FROM DISK" into field "tName"
      put adThousands(the number of bytes in sTapeWav) & " bytes in " & adFileName(sTapePath) into field "tStat"
   else
      put "FROM MEMORY" into field "tName"
      put adThousands(the number of bytes in sTapeWav) & " bytes" into field "tStat"
   end if
   set the rect of graphic "tProg" to 24, 306, 648, 312
   put adClock() into sSceneT0
   put "stream" into sScenePhase
   put "The tape, streamed from its file" into field "Caption"
   if sTapeStream is not 0 then
      auSoundStart sTapeStream
   else
      auSoundStart sTape
   end if
   if tRefusal is not empty then
      put return & "Asked to clone the stream, the library refused: " & tRefusal & "." after field "tFacts"
   end if
end adTapeFinish

-- Three clones of the tape at once, started on the same sample: a major
-- chord of the whole tape (pitch 1, 1.26 and 1.5), each freed at its end.
command adTapeClonesGo
   local tPitch, tI, tClone, tWhen
   if sTapeStream is not 0 then
      auSoundStop sTapeStream
   end if
   put empty into sTapeClones
   put adClock() + 0.05 into tWhen
   put 0 into tI
   repeat for each item tPitch in kAdClonePitches
      add 1 to tI
      put auSoundClone(sTape) into tClone
      if tClone > 0 then
         auSoundSetPitch tClone, tPitch
         auSoundSetVolume tClone, 0.55
         auSoundSetAutoFree tClone, true
         auSoundStartAt tClone, tWhen
      end if
      put tClone into item tI of sTapeClones
   end repeat
   put adClock() into sSceneT0
   put "clones" into sScenePhase
   put "THREE AT ONCE" into field "tName"
   put "pitch 1, 1.26 and 1.5: a major chord" into field "tStat"
   put "Three clones at once: a chord of the whole tape" into field "Caption"
   put "Three clones of the tape (auSoundClone) share its samples and play together, each at its own pitch: 1, 1.26 " \
         & "and 1.5, a major chord, so the higher ones finish first. Each frees itself at its end (auSoundSetAutoFree)." \
         into field "tFacts"
end adTapeClonesGo

-- The tape loops its middle second while its pitch wobbles.
command adTapeLoopGo
   local tI, tFrom, tTo
   repeat with tI = 2 to 3
      set the visible of graphic ("tHead" & tI) to false
      set the visible of field ("tLab" & tI) to false
   end repeat
   auSoundSeek sTape, 0.5
   auSoundSetLooping sTape, true
   auSoundSetLoopRange sTape, 0.5, 1.5
   auSoundSetVolume sTape, 0.9
   auSoundStart sTape
   put 28 + round(616 * 0.5 / 2) into tFrom
   put 28 + round(616 * 1.5 / 2) into tTo
   set the rect of graphic "tRange" to tFrom, 162, tTo, 298
   set the visible of graphic "tRange" to true
   put adClock() into sSceneT0
   put "loop" into sScenePhase
   put "LOOPED" into field "tName"
   put "0.5 to 1.5 s, round and round" into field "tStat"
   put "Looping its middle second while it wobbles" into field "Caption"
   put "The tape loops from 0.5 to 1.5 seconds (auSoundSetLoopRange; auSoundIsLooping answers " & auSoundIsLooping(sTape) \
         & "), its pitch swaying like a stretched tape (auSoundSetPitch). The playhead goes slower and faster with it." \
         into field "tFacts"
end adTapeLoopGo

-- A playhead: where pSound is in the tape, or hidden when it is not
-- playing (a clone that ended is already freed).
command adTapeHead pHead, pSound, pLabel
   local tX
   if not auSoundIsValid(pSound) or not auSoundIsPlaying(pSound) then
      set the visible of graphic ("tHead" & pHead) to false
      set the visible of field ("tLab" & pHead) to false
      exit adTapeHead
   end if
   put 28 + round(616 * min(1, auSoundPosition(pSound) / 2)) into tX
   set the points of graphic ("tHead" & pHead) to tX & ",156" & return & tX & ",304"
   set the visible of graphic ("tHead" & pHead) to true
   put pLabel into field ("tLab" & pHead)
   set the rect of field ("tLab" & pHead) to tX - 40, 138, tX + 40, 156
   set the visible of field ("tLab" & pHead) to true
end adTapeHead

-- ==========================================================================
-- 5. Your microphone. Five seconds, kept in memory and written to a file at
-- the same time, then played back, and once more faster.
-- ==========================================================================

command adMicBegin
   local tWhy
   put empty into sMicData
   put empty into sMicTop
   put empty into sMicBottom
   put empty into sMicFile
   put 0 into sMicSound
   put empty into sMicFacts
   set the visible of graphic "mWave" to false
   set the visible of graphic "mHead" to false
   set the visible of graphic "mRec" to false
   set the rect of graphic "mLevel" to 24, 134, 25, 152
   put empty into field "mRecText"
   put empty into field "mFacts"
   -- s16 at 16,000 Hz mono, whatever the device itself uses; ten seconds
   -- of room for sound the timer has not read yet
   put auCaptureOpen(sMicDevice, "s16", kAdMicRate, 1, 10) into sMic
   if sMic is 0 then
      adMicNone "No microphone answered: " & auLastError()
      exit adMicBegin
   end if
   if not auCaptureStart(sMic) then
      put auLastError() into tWhy
      auCaptureClose sMic
      put 0 into sMic
      adMicNone "The microphone would not start: " & tWhy
      exit adMicBegin
   end if
   put adTempFile("audioxt-demo-microphone.wav") into sMicFile
   if not auCaptureRecordStart(sMic, sMicFile) then
      put "(No file is written alongside: " & auLastError() & ")" into sMicFacts
      put empty into sMicFile
   end if
   put the milliseconds into sMicMs
   put "listen" into sScenePhase
   set the visible of graphic "mRec" to true
   put "Say something: it is listening" into field "Caption"
end adMicBegin

command adMicEnd
   if auCaptureIsValid(sMic) then
      if auCaptureIsRecording(sMic) then
         get auCaptureRecordStop(sMic)
      end if
      auCaptureStop sMic
      auCaptureClose sMic
   end if
   put 0 into sMic
   put 0 into sMicSound
end adMicEnd

-- No microphone: said plainly, and the scene ends soon after.
command adMicNone pWhy
   put "none" into sScenePhase
   put pWhy & return & return & "Every other scene works without one." into field "mFacts"
   put "No microphone here" into field "Caption"
   set the visible of graphic "mRec" to false
   adStatus pWhy, "warn"
end adMicNone

command adMicFrame
   local tT, tGot, tSeconds, tLevel, tWaited
   put adSceneTime() into tT
   switch sScenePhase
      case "none"
         if tT >= 4 then
            adSceneDone
            exit adMicFrame
         end if
         break
      case "listen"
         put auCaptureRead(sMic) into tGot
         if tGot is not empty then
            put tGot after sMicData
         end if
         put auCapturePeak(sMic) into tLevel
         set the rect of graphic "mLevel" to 24, 134, 24 + max(1, round(624 * min(1, 2 * tLevel))), 152
         if tLevel > 0.5 then
            set the backgroundColor of graphic "mLevel" to kAdWarm
         else
            set the backgroundColor of graphic "mLevel" to kAdGood
         end if
         put (the number of bytes in sMicData) / (2 * kAdMicRate) into tSeconds
         put (the milliseconds - sMicMs) / 1000 into tWaited
         adMicPicture
         set the visible of graphic "mRec" to ((the milliseconds div 400) mod 2 is 0)
         put "LISTENING   " & format("%.1f", tSeconds) & " of " & kAdMicSeconds & ".0 seconds" into field "mRecText"
         adMicFactsListening tWaited, tSeconds
         adSceneBar 0.5 * tSeconds / kAdMicSeconds
         if tSeconds >= kAdMicSeconds or (tWaited > 9 and tSeconds < 0.2) then
            adMicStopListening
         end if
         break
      case "play"
         adMicHead sMicSound
         if tT > 0.3 and not auSoundIsPlaying(sMicSound) then
            adMicFaster
         end if
         adSceneBar 0.5 + 0.3 * min(1, tT / max(0.1, auSoundLength(sMicSound)))
         break
      case "faster"
         adMicHead item 1 of sOwned
         if tT > 0.3 and not auSoundIsValid(item 1 of sOwned) then
            adSceneDone
            exit adMicFrame
         end if
         adSceneBar 0.8 + 0.2 * min(1, tT / max(0.1, auSoundLength(sMicSound) / 1.6))
         break
   end switch
end adMicFrame

command adMicFactsListening pWaited, pSeconds
   local tOut
   put "Listening to " & auCaptureDeviceLabel(sMic) & ": " & auCaptureFormat(sMic) & ", " \
         & adThousands(auCaptureSampleRate(sMic)) & " Hz, " & auCaptureChannels(sMic) & " channel." & return into tOut
   put "Kept here: " & adThousands(the number of bytes in sMicData) & " bytes. Not read yet: " & auCaptureAvailable(sMic) \
         & " bytes. Dropped: " & auCaptureDropped(sMic) & " frames (only when the buffer is full)." & return after tOut
   if sMicFile is not empty and auCaptureIsRecording(sMic) then
      put "Also written, as it arrives, to " & adFileName(sMicFile) & " (auCaptureRecordStart)." after tOut
   else
      put sMicFacts after tOut
   end if
   if pSeconds < 0.2 and pWaited > 2.5 then
      put return & "Nothing has arrived yet. A browser asks you first; a page that may not use a microphone gets none." after tOut
   end if
   put tOut into field "mFacts"
end adMicFactsListening

-- The picture: 156 columns over the five seconds, the loudest of 16 samples
-- of each, drawn above and below the line as it arrives.
command adMicPicture
   local tC, tFrom, tTo, tProbe, tAt, tValue, tMost, tX, tDone, tHave, tSize
   put (the number of bytes in sMicData) div 2 into tHave
   put the number of lines of sMicTop into tDone
   put kAdMicRate * kAdMicSeconds into tSize
   repeat with tC = tDone to 155
      put (tC * tSize) div 156 into tFrom
      put ((tC + 1) * tSize) div 156 into tTo
      if tTo > tHave then
         exit repeat
      end if
      put 0 into tMost
      repeat with tProbe = 0 to 15
         put tFrom + ((tTo - tFrom - 1) * tProbe) div 15 into tAt
         get binaryDecode("s", byte 2 * tAt + 1 to 2 * tAt + 2 of sMicData, tValue)
         put max(tMost, abs(tValue)) into tMost
      end repeat
      put 28 + round(616 * tC / 155) into tX
      put round(min(64, 4 + 180 * tMost / 32768)) into tMost
      put tX & "," & (229 - tMost) & return after sMicTop
      put tX & "," & (229 + tMost) & return before sMicBottom
   end repeat
   if the number of lines of sMicTop >= 2 then
      set the points of graphic "mWave" to sMicTop & sMicBottom & line 1 of sMicTop
      set the visible of graphic "mWave" to true
   end if
end adMicPicture

-- Five seconds heard (or nothing, after a fair wait): the file finished
-- and read back to prove it, then played back from memory.
command adMicStopListening
   local tGot, tFileSeconds, tDropped, tLabel, tBack, tOut
   put auCaptureRead(sMic) into tGot
   if tGot is not empty then
      put tGot after sMicData
   end if
   put 0 into tFileSeconds
   if auCaptureIsRecording(sMic) then
      put auCaptureRecordStop(sMic) into tFileSeconds
   end if
   put auCaptureDropped(sMic) into tDropped
   put auCaptureDeviceLabel(sMic) into tLabel
   auCaptureStop sMic
   auCaptureClose sMic
   put 0 into sMic
   set the visible of graphic "mRec" to false
   set the rect of graphic "mLevel" to 24, 134, 25, 152
   if sMicData is empty then
      adMicNone "No sound arrived from " & tLabel & ". A browser asks you first, and one told no, or a page that may not " \
            & "use a microphone (the community gallery's), never gets any."
      exit adMicStopListening
   end if
   put "Heard " & format("%.1f", (the number of bytes in sMicData) / (2 * kAdMicRate)) & " s from " & tLabel \
         & " (s16, 16,000 Hz, mono); " & tDropped & " frames dropped." into tOut
   if sMicFile is not empty then
      put auDecodeFile(sMicFile, "s16", 0, 0) into tBack
      if tBack is empty then
         put return & "The file it wrote (" & format("%.2f", tFileSeconds) & " s) did not decode: " & auLastError() after tOut
      else
         put return & "The file it wrote at the same time, " & adFileName(sMicFile) & ", holds " & format("%.2f", tFileSeconds) \
               & " s and decodes back to " & format("%.2f", (the number of bytes in tBack) / (2 * auOutSampleRate() * auOutChannels())) \
               & " s (auCaptureRecordStop, auDecodeFile)." after tOut
      end if
   end if
   put tOut into sMicFacts
   put tOut into field "mFacts"
   put auSoundFromPCM(sEngine, sMicData, "s16", kAdMicRate, 1) into sMicSound
   if sMicSound is 0 then
      adMicNone "What it heard could not be played: " & auLastError()
      exit adMicStopListening
   end if
   adOwn sMicSound
   auSoundStart sMicSound
   put adClock() into sSceneT0
   put "play" into sScenePhase
   put "PLAYING IT BACK (auSoundFromPCM)" into field "mRecText"
   put "And here it is" into field "Caption"
end adMicStopListening

-- Once more, a clone at 1.6 times the pitch: faster and higher.
command adMicFaster
   local tClone
   put auSoundClone(sMicSound) into tClone
   if tClone is 0 then
      adSceneDone
      exit adMicFaster
   end if
   auSoundSetPitch tClone, 1.6
   auSoundSetAutoFree tClone, true
   auSoundStart tClone
   -- first in the list, so the frame can find it
   put tClone & comma before sOwned
   put adClock() into sSceneT0
   put "faster" into sScenePhase
   put "AND ONCE MORE, FASTER (a clone at pitch 1.6)" into field "mRecText"
   put "And once more, faster" into field "Caption"
end adMicFaster

command adMicHead pSound
   local tX
   if not auSoundIsValid(pSound) or not auSoundIsPlaying(pSound) then
      set the visible of graphic "mHead" to false
      exit adMicHead
   end if
   put 28 + round(616 * min(1, auSoundPosition(pSound) / max(0.1, auSoundLength(pSound)))) into tX
   set the points of graphic "mHead" to tX & ",158" & return & tX & ",300"
   set the visible of graphic "mHead" to true
end adMicHead

-- ==========================================================================
-- 6. The checks: every check of this window, a step a frame, so the stage
-- never stops while they run (the live ones wait for the silent device's
-- own thread between steps, by the clock, never with a `wait`). They make
-- and free engines of their own and never touch the scenes' sounds. Ended
-- sounds are polled for every engine at once, so a check asks whether ITS
-- sounds were reported, never how many were. The headless drive
-- (tests/demo-drive.livecodescript) presses the same button and reads the
-- same lines, so the window and the test cannot drift apart.
-- ==========================================================================

command adChecksBegin
   adCkLiveClose
   put 0 into sCkPass
   put 0 into sCkFail
   put empty into sCkLog
   put 1 into sCkStep
   put false into sCkDone
   put the milliseconds into sCkMs
   set the visible of button "cCopy" to false
   put "A step a frame, so the window keeps moving while they run. Each one makes and frees engines of its own." \
         into field "cNote"
   adChecksPaint
end adChecksBegin

-- Left part way (another scene was picked): the silent device's engine and
-- microphone are closed and their file deleted. The lines so far stay.
command adChecksEnd
   adCkLiveClose
end adChecksEnd

command adChecksFrame
   local tStep, tError
   if sCkDone then
      exit adChecksFrame
   end if
   if sCkStep < 1 or sCkStep > the number of items of kAdCheckSteps then
      put 1 into sCkStep
   end if
   -- the live steps give the silent device's thread time to run
   if sCkLive > 0 and the milliseconds - sCkMs < item sCkStep of kAdCheckWaits then
      exit adChecksFrame
   end if
   put item sCkStep of kAdCheckSteps into tStep
   try
      adCheckStep tStep
   catch tError
      adCk false, "the " & tStep & " checks ran to their end", line 1 of tError
      if tStep is "done" then
         put true into sCkDone
      end if
   end try
   add 1 to sCkStep
   put the milliseconds into sCkMs
   adChecksPaint
end adChecksFrame

command adCheckStep pStep
   switch pStep
      case "facts"
         adCkFacts
         break
      case "mixing"
         adCkMixing
         break
      case "wav"
         adCkWav
         break
      case "fourways"
         adCkFourWays
         break
      case "timing"
         adCkTiming
         break
      case "own"
         adCkOwn
         break
      case "refusals"
         adCkRefusals
         break
      case "liveA"
         adCkLiveA
         break
      case "liveB"
         adCkLiveB
         break
      case "liveC"
         adCkLiveC
         break
      case "done"
         put "SUMMARY" && sCkPass && sCkFail after sCkLog
         put true into sCkDone
         break
   end switch
end adCheckStep

private command adCk pOk, pLabel, pDetail
   if pOk is true then
      add 1 to sCkPass
      put "PASS  " & pLabel & return after sCkLog
   else
      add 1 to sCkFail
      put "FAIL  " & pLabel & "  [" & pDetail & "]" & return after sCkLog
   end if
end adCk

-- The newest lines that fit, coloured (and, once it is done, every failure
-- first), the progress, the count so far.
command adChecksPaint
   local tSteps, tCount, tShow, tFails, tLine, tI
   set the defaultStack to the short name of this stack
   put the number of items of kAdCheckSteps into tSteps
   put the number of lines of sCkLog into tCount
   put line max(1, tCount - 10) to tCount of sCkLog into tShow
   if sCkDone then
      repeat for each line tLine in sCkLog
         if word 1 of tLine is "FAIL" then
            put tLine & return after tFails
         end if
      end repeat
      if tFails is not empty then
         put line 1 to 7 of tFails & line max(1, tCount - 3) to tCount of sCkLog into tShow
      end if
   end if
   put tShow into field "cLog"
   repeat with tI = 1 to the number of lines of field "cLog"
      put word 1 of line tI of field "cLog" into tLine
      if tLine is "PASS" then
         set the foregroundColor of char 1 to 4 of line tI of field "cLog" to kAdGood
      else if tLine is "FAIL" then
         set the foregroundColor of line tI of field "cLog" to kAdHot
      else if tLine is "SKIP" then
         set the foregroundColor of line tI of field "cLog" to kAdWarm
      else if tLine is not "SUMMARY" then
         set the foregroundColor of line tI of field "cLog" to kAdSoft
      end if
   end repeat
   set the rect of graphic "cProg" to 24, 324, 24 + max(1, round(624 * min(1, (sCkStep - 1) / tSteps))), 332
   adSceneBar (sCkStep - 1) / tSteps
   if not sCkDone then
      put "Checking: step" && min(sCkStep, tSteps) && "of" && tSteps into field "Caption"
      put sCkPass && "passed so far" into field "cSum"
      if sCkFail > 0 then
         put "," && sCkFail && "failed" after field "cSum"
      end if
      set the foregroundColor of field "cSum" to kAdInk
      exit adChecksPaint
   end if
   set the visible of button "cCopy" to true
   put "Copy the results puts every line on the clipboard, ready to paste into a message." into field "cNote"
   if sCkFail is 0 then
      put "The checks: all" && sCkPass && "passed" into field "Caption"
      put sCkPass && "checks passed, none failed." into field "cSum"
      set the foregroundColor of field "cSum" to kAdGood
      adStatus "Every check passed.", empty
   else
      put "The checks:" && sCkFail && "failed" into field "Caption"
      put sCkPass && "passed," && sCkFail && "FAILED: the red lines say which." into field "cSum"
      set the foregroundColor of field "cSum" to kAdHot
      adStatus sCkFail && "check(s) failed.", "bad"
   end if
end adChecksPaint

-- The silent device's engine and microphone, closed; their file deleted.
command adCkLiveClose
   local tError
   try
      if sCkMic is an integer and sCkMic > 0 and auCaptureIsValid(sCkMic) then
         auCaptureClose sCkMic
      end if
      if sCkLive is an integer and sCkLive > 0 and auEngineIsValid(sCkLive) then
         auEngineFree sCkLive
      end if
   catch tError
   end try
   put 0 into sCkMic
   put 0 into sCkLive
   put 0 into sCkTone
   if sCkPath is not empty and there is a file sCkPath then
      delete file sCkPath
   end if
   if sCkFolder is not empty and there is a folder sCkFolder then
      delete folder sCkFolder
   end if
   put empty into sCkPath
   put empty into sCkFolder
end adCkLiveClose

-- What runs here: the engine, the library, the audio system it found.
private command adCkFacts
   put "Engine: " & the version & ", " & the platform & " (" & the processor & ")" & return after sCkLog
   put "Library: " & auLibraryVersion() & return after sCkLog
   put "Audio system: " & adOr(auBackendName(), "none found") & return after sCkLog
   adCk auABIVersion() is 1, "the library is at the ABI this binding wants", auABIVersion()
   adCk auLibraryVersion() begins with "audioxt ABI 1; miniaudio ", "the version names miniaudio", auLibraryVersion()
end adCkFacts

-- Mixing, measured: an offline engine mixes into memory, so what it makes
-- can be read back to the sample.
private command adCkMixing
   local tOff, tTone, tBlock, tPeak, tWave
   put auEngineCreateOffline(8000, 2) into tOff
   adCk tOff > 0 and auEngineIsValid(tOff) and auEngineIsOffline(tOff), "an offline engine opens", auLastError()
   adCk auEngineSampleRate(tOff) is 8000 and auEngineChannels(tOff) is 2 and auEngineDeviceName(tOff) is empty, \
         "at the rate and channels asked for, with no device", auEngineSampleRate(tOff) && auEngineChannels(tOff)
   put auSoundTone(tOff, "sine", 440, 0.5) into tTone
   adCk tTone > 0 and auSoundIsValid(tTone) and auSoundEngine(tTone) is tOff, "a tone is made on it", auLastError()
   put auEngineRender(tOff, 800, "s16") into tBlock
   adCk the number of bytes in tBlock is 3200 and adLoudest16(tBlock) is 0, "nothing started: 800 frames of silence", \
         the number of bytes in tBlock && adLoudest16(tBlock)
   auSoundStart tTone
   adCk auSoundIsPlaying(tTone), "started, it plays", auSoundIsPlaying(tTone)
   put auEngineRender(tOff, 800, "s16") into tBlock
   adCk adNear(adLoudest16(tBlock), 16384, 400), "a tone of amplitude 0.5 peaks at half of full scale", adLoudest16(tBlock)
   adCk adNear(auEngineTime(tOff), 0.2, 0.0001) and auOutSampleRate() is 8000 and auOutChannels() is 2, \
         "the clock counts what was mixed", auEngineTime(tOff)
   put auEnginePeak(tOff) into tPeak
   adCk adNear(item 1 of tPeak, 0.5, 0.02) and adNear(item 2 of tPeak, 0.5, 0.02), "the level meter reads it", tPeak
   put auEngineWaveform(tOff, 64) into tWave
   adCk the number of items of tWave is 64 and item 1 of tWave is a number, "the oscilloscope gets the points it asks for", \
         the number of items of tWave
   auSoundSetVolume tTone, 0.25
   put auEngineRender(tOff, 800, "s16") into tBlock
   adCk adNear(auSoundVolume(tTone), 0.25, 0.000001) and adNear(adLoudest16(tBlock), 4096, 200), \
         "a volume of 0.25 is a quarter of the level", adLoudest16(tBlock)
   auSoundSetPan tTone, -1
   adCk auSoundPan(tTone) is -1, "pan", auSoundPan(tTone)
   auSoundSetPan tTone, 7
   adCk auSoundPan(tTone) is -1 and auLastError() contains "pan", "a pan of 7 is refused, in words", auLastError()
   auSoundSetPan tTone, 0
   auSoundSetPitch tTone, 2
   auSoundSetFrequency tTone, 660
   auEngineSetVolume tOff, 0.5
   adCk auSoundPitch(tTone) is 2 and auEngineVolume(tOff) is 0.5, "pitch, and the engine's own volume", \
         auSoundPitch(tTone) && auEngineVolume(tOff)
   auSoundFade tTone, -1, 0, 0.05
   get auEngineRender(tOff, 400, "s16")
   put auEngineRender(tOff, 400, "s16") into tBlock
   adCk adLoudest16(tBlock) <= 2, "a fade to nothing over 0.05 s leaves silence after it", adLoudest16(tBlock)
   adCk auEngineRender(tOff, 100, "s99") is empty and auLastError() contains "format", "an unknown sample format is refused", \
         auLastError()
   adCk auSoundTone(tOff, "wobble", 440, 0.5) is 0 and auLastError() contains "sine", \
         "an unknown waveform is refused, naming the ones there are", auLastError()
   adCk auSoundNoise(tOff, "brown", 0.5) is 0 and auSoundNoise(tOff, "pink", 0.5) > 0, "pink noise, and no brown", auLastError()
   adCk auEngineSoundCount(tOff) is 2, "two sounds on the engine", auEngineSoundCount(tOff)
   auSoundFree tTone
   adCk auSoundIsValid(tTone) is false and auEngineSoundCount(tOff) is 1, "a freed sound is gone", auSoundIsValid(tTone)
   auSoundStart tTone
   adCk auSoundVolume(987654) is 0 and auSoundPositionXYZ(987654) is empty and auSoundIsValid(0) is false, \
         "a handle that names nothing is refused, harmlessly", auSoundVolume(987654)
   auEngineStopAll tOff
   auEngineFree tOff
   adCk auEngineIsValid(tOff) is false, "the offline engine is freed, and its sounds with it", auEngineIsValid(tOff)
end adCkMixing

-- WAV files: made from samples a script computed, and read back.
private command adCkWav
   local tSamples, tWav, tBack
   put adSine8k() into tSamples
   put auWAVEncode(tSamples, "s16", 8000, 1) into tWav
   adCk the number of bytes in tWav is 16044 and byte 1 to 4 of tWav is "RIFF" and byte 9 to 12 of tWav is "WAVE", \
         "a second of samples becomes a WAV file", the number of bytes in tWav
   put auDecodeData(tWav, "s16", 0, 0) into tBack
   adCk tBack is tSamples and auOutSampleRate() is 8000 and auOutChannels() is 1, "and decodes back bit for bit", \
         the number of bytes in tBack
   put auDecodeData(tWav, "f32", 16000, 2) into tBack
   adCk adNear(the number of bytes in tBack, 128000, 64) and auOutSampleRate() is 16000 and auOutChannels() is 2, \
         "converted while decoding: twice the rate, two channels, floats", the number of bytes in tBack
   adCk auDecodeData("this is not a sound file", "s16", 0, 0) is empty and auLastError() is not empty, \
         "bytes that are no sound are refused", auLastError()
end adCkWav

-- One sound four ways: a file whole, a stream, its bytes, its samples.
private command adCkFourWays
   local tSamples, tWav, tPath, tOff, tSound, tStream, tFromData, tFromPCM, tClone, tBlock
   put adSine8k() into tSamples
   put auWAVEncode(tSamples, "s16", 8000, 1) into tWav
   put adTempFile("audioxt-demo-check.wav") into tPath
   put tWav into URL ("binfile:" & tPath)
   adCk auDecodeFile(tPath, "s16", 0, 0) is tSamples, "a file decodes by its path", auLastError()
   put auEngineCreateOffline(8000, 1) into tOff
   put auSoundLoad(tOff, tPath, false) into tSound
   put auSoundLoad(tOff, tPath, true) into tStream
   put auSoundLoadData(tOff, tWav, false) into tFromData
   put auSoundFromPCM(tOff, tSamples, "s16", 8000, 1) into tFromPCM
   adCk tSound > 0 and tStream > 0 and tFromData > 0 and tFromPCM > 0, \
         "one sound four ways: a file whole, a stream, its bytes, its samples", auLastError()
   adCk adNear(auSoundLength(tSound), 1, 0.001) and adNear(auSoundLength(tStream), 1, 0.001) \
         and adNear(auSoundLength(tFromData), 1, 0.001) and adNear(auSoundLength(tFromPCM), 1, 0.001), \
         "each one second long", auSoundLength(tStream)
   put auSoundClone(tFromPCM) into tClone
   adCk tClone > 0 and tClone is not tFromPCM, "a clone shares the samples", auLastError()
   adCk auSoundClone(tStream) is 0 and auLastError() contains "clone", "a stream cannot be cloned, and says so", auLastError()
   auSoundStart tFromPCM
   put auEngineRender(tOff, 8000, "s16") into tBlock
   adCk adNear(adLoudest16(tBlock), 8000, 2), "the samples play as given (within a step: the mixer works in floats)", \
         adLoudest16(tBlock)
   auSoundStart tStream
   put auEngineRender(tOff, 4000, "s16") into tBlock
   adCk adNear(adLoudest16(tBlock), 8000, 2), "the stream plays the same sound", adLoudest16(tBlock)
   auSoundSeek tSound, 0.5
   adCk adNear(auSoundPosition(tSound), 0.5, 0.001), "seek, and the position", auSoundPosition(tSound)
   auSoundSetLooping tSound, true
   auSoundSetLoopRange tSound, 0.25, 0.75
   adCk auSoundIsLooping(tSound) is true, "looping", auSoundIsLooping(tSound)
   auSoundSetLooping tSound, false
   adCk auSoundIsLooping(tSound) is false, "and not", auSoundIsLooping(tSound)
   auEngineFree tOff
   delete file tPath
end adCkFourWays

-- Ends, auto-free and the clock; groups; a stop that fades; a place in 3D.
private command adCkTiming
   local tSamples, tOff, tShort, tKeep, tEnded, tWhen, tBlock, tGroup
   put adSine8k() into tSamples
   put auEngineCreateOffline(8000, 2) into tOff
   put auSoundFromPCM(tOff, byte 1 to 4000 of tSamples, "s16", 8000, 1) into tShort
   put auSoundClone(tShort) into tKeep
   auSoundSetAutoFree tShort, true
   auSoundStart tShort
   auSoundStart tKeep
   get auEngineRender(tOff, 4000, "s16")
   put adEndedList() into tEnded
   adCk tShort is among the items of tEnded and tKeep is among the items of tEnded, "both sounds are reported when they end", tEnded
   adCk auSoundIsValid(tShort) is false and auSoundIsValid(tKeep) and auSoundAtEnd(tKeep) and not auSoundIsPlaying(tKeep), \
         "the one marked auto-free was freed by that poll; the other waits at its end", auSoundIsValid(tShort) && auSoundAtEnd(tKeep)
   put adEndedList() into tEnded
   adCk tKeep is not among the items of tEnded, "an end is reported once", tEnded
   put auEngineTime(tOff) + 0.1 into tWhen
   auSoundStartAt tKeep, tWhen
   put auEngineRender(tOff, 800, "s16") into tBlock
   adCk adLoudest16(tBlock) is 0, "a sound started at a time is silent until then", adLoudest16(tBlock)
   put auEngineRender(tOff, 800, "s16") into tBlock
   adCk adLoudest16(tBlock) > 2000, "and heard from that sample on", adLoudest16(tBlock)
   auSoundStopAt tKeep, auEngineTime(tOff) + 0.05
   get auEngineRender(tOff, 800, "s16")
   put auEngineRender(tOff, 800, "s16") into tBlock
   adCk adLoudest16(tBlock) is 0, "and silent again after its stop time", adLoudest16(tBlock)

   -- groups
   put auGroupCreate(tOff) into tGroup
   adCk tGroup > 0 and auGroupIsValid(tGroup), "a group", auLastError()
   auSoundSetGroup tKeep, tGroup
   auGroupSetVolume tGroup, 0.5
   auGroupSetPan tGroup, 0.25
   auGroupSetPitch tGroup, 1.5
   adCk auSoundGroup(tKeep) is tGroup and auGroupVolume(tGroup) is 0.5 and auGroupPan(tGroup) is 0.25 \
         and auGroupPitch(tGroup) is 1.5, "a sound joins it; its volume, pan and pitch", \
         auGroupVolume(tGroup) && auGroupPan(tGroup) && auGroupPitch(tGroup)
   auSoundSeek tKeep, 0
   auSoundStart tKeep
   auGroupStop tGroup
   put auEngineRender(tOff, 400, "s16") into tBlock
   adCk adLoudest16(tBlock) is 0, "a stopped group is silent", adLoudest16(tBlock)
   auGroupStart tGroup
   put auEngineRender(tOff, 400, "s16") into tBlock
   adCk adLoudest16(tBlock) > 1000, "and heard again when started", adLoudest16(tBlock)
   auGroupFree tGroup
   adCk auGroupIsValid(tGroup) is false and auSoundGroup(tKeep) is 0 and auSoundIsValid(tKeep), \
         "a freed group lets its sound go, and the sound lives on", auSoundGroup(tKeep)

   -- a stop that fades: heard while it dies away, then stopped, though the
   -- sound has more to play
   auSoundSeek tKeep, 0
   auSoundStart tKeep
   auSoundStopWithFade tKeep, 0.1
   put auEngineRender(tOff, 400, "s16") into tBlock
   adCk adLoudest16(tBlock) > 1000, "a stop with a fade is heard while it fades", adLoudest16(tBlock)
   get auEngineRender(tOff, 800, "s16")
   put auEngineRender(tOff, 400, "s16") into tBlock
   adCk adLoudest16(tBlock) is 0 and auSoundIsPlaying(tKeep) is false, "and then stops, with sound still left in it", \
         adLoudest16(tBlock) && auSoundIsPlaying(tKeep)

   -- a place in 3D
   auSoundSetSpatial tKeep, true
   auSoundSetPosition tKeep, 1.5, 0, -2
   adCk auSoundIsSpatial(tKeep) and auSoundPositionXYZ(tKeep) is "1.5,0,-2", "a sound in 3D, and where it is", \
         auSoundPositionXYZ(tKeep)
   auEngineSetListenerPosition tOff, 0, 1, 0
   auEngineSetListenerDirection tOff, 1, 0, 0
   auEngineSetListenerUp tOff, 0, 1, 0
   auEngineSetListenerVelocity tOff, 0, 0, 0
   adCk auEngineListenerPosition(tOff) is "0,1,0" and auEngineListenerDirection(tOff) is "1,0,0", "the listener", \
         auEngineListenerPosition(tOff) && auEngineListenerDirection(tOff)
   auEngineSetListenerDirection tOff, 0, 0, 0
   adCk auLastError() contains "direction" and auEngineListenerDirection(tOff) is "1,0,0", \
         "a direction of all zeros is refused", auLastError()
   auSoundSetVelocity tKeep, 1, 0, 0
   auSoundSetDistanceRange tKeep, 1, 50
   auSoundSetRolloff tKeep, 1
   auSoundSetDoppler tKeep, 1
   auSoundSetDistanceRange tKeep, 5, 1
   adCk auLastError() contains "distance range", "a range whose far end is nearer than its near end is refused", auLastError()
   auEngineFree tOff
end adCkTiming

-- This window's own sounds: the instruments of the beat, and the tape.
private command adCkOwn
   local tVoice, tBlock, tTune, tBack
   repeat for each item tVoice in "kick,snare,hat,bell,crash"
      put adRenderVoice(tVoice) into tBlock
      adCk the number of bytes in tBlock > 4000 and adLoudestF32(tBlock, 0, 0.1) > 4 * adLoudestF32(tBlock, 0.9, 1), \
            "the " & tVoice & " is made, and dies away", the number of bytes in tBlock
   end repeat
   put adMakeTune() into tTune
   adCk the number of bytes in tTune is 352844 and byte 1 to 4 of tTune is "RIFF", "the tape: two seconds of stereo WAV", \
         the number of bytes in tTune
   put auDecodeData(tTune, "s16", 0, 0) into tBack
   adCk adLoudestChannel16(byte 1 to 22000 of tBack, 1) > 2 * adLoudestChannel16(byte 1 to 22000 of tBack, 2), \
         "its first note is panned left", adLoudestChannel16(byte 1 to 22000 of tBack, 1) && adLoudestChannel16(byte 1 to 22000 of tBack, 2)
end adCkOwn

-- Refusals that need no device, and the device lists.
private command adCkRefusals
   adCk auCaptureOpen(-1, "s99", 16000, 1, 1) is 0 and auLastError() is not empty, "a capture in an unknown format is refused", \
         auLastError()
   adCk auCaptureOpen(-1, "s16", 16000, 1, 0) is 0, "a capture with no buffer is refused", auLastError()
   adCk auEngineCreate(-2, 0, 0) is 0 and auEngineCreateOffline(1000, 2) is 0, "devices and rates that cannot be are refused", \
         auLastError()
   adCk auDeviceScan() >= -1 and auPlaybackDeviceCount() >= 0 and auCaptureDeviceCount() >= 0 \
         and auPlaybackDeviceName(9999) is empty and auPlaybackDeviceIsDefault(9999) is false \
         and auCaptureDeviceName(9999) is empty and auCaptureDeviceIsDefault(9999) is false, \
         "the device lists answer, whatever a scan found", auPlaybackDeviceCount() && auCaptureDeviceCount()
end adCkRefusals

-- The silent test device: the library's own threads, in real time. A
-- square tone starts here; the next step, a third of a second later, asks
-- what the device's thread has mixed by then.
private command adCkLiveA
   if the platform is "HTML5" then
      put "SKIP  the silent test device: a browser has none" & return after sCkLog
      exit adCkLiveA
   end if
   adCkLiveClose
   put auEngineCreate(-1, 0, 0) into sCkLive
   adCk sCkLive > 0 and auEngineIsOffline(sCkLive) is false and auEngineDeviceName(sCkLive) is not empty, \
         "the silent device opens", auLastError()
   if sCkLive is 0 then
      exit adCkLiveA
   end if
   put auSoundTone(sCkLive, "square", 220, 0.3) into sCkTone
   auSoundStart sCkTone
end adCkLiveA

-- Then a silent microphone, writing a file as it hears.
private command adCkLiveB
   local tStarted
   if sCkLive is 0 or not auEngineIsValid(sCkLive) then
      exit adCkLiveB
   end if
   adCk auEngineTime(sCkLive) > 0.05 and item 1 of auEnginePeak(sCkLive) > 0.2, \
         "its own thread mixes in real time, and the meter sees it", auEngineTime(sCkLive)
   adCk auEngineRender(sCkLive, 100, "s16") is empty, "a device's engine is not rendered by hand", auLastError()
   auEngineStop sCkLive
   auEngineStart sCkLive
   put auCaptureOpen(-1, "s16", 16000, 1, 2) into sCkMic
   adCk sCkMic > 0 and auCaptureIsValid(sCkMic) and auCaptureFormat(sCkMic) is "s16" and auCaptureSampleRate(sCkMic) is 16000 \
         and auCaptureChannels(sCkMic) is 1, "a silent microphone, in the format asked for", auLastError()
   if sCkMic is 0 then
      exit adCkLiveB
   end if
   put auCaptureStart(sCkMic) into tStarted
   put the tempName into sCkFolder
   create folder sCkFolder
   put sCkFolder & "/memo.wav" into sCkPath
   adCk tStarted and auCaptureIsRunning(sCkMic) and auCaptureRecordStart(sCkMic, sCkPath) and auCaptureIsRecording(sCkMic), \
         "it runs, and writes a file as it hears", auLastError()
end adCkLiveB

-- Half a second on: what it heard, read as data and kept in the file.
private command adCkLiveC
   local tHeard, tBack
   if sCkMic is 0 or not auCaptureIsValid(sCkMic) then
      adCkLiveClose
      exit adCkLiveC
   end if
   adCk auCaptureAvailable(sCkMic) > 1600, "sound arrives", auCaptureAvailable(sCkMic)
   put auCaptureRead(sCkMic) into tHeard
   adCk the number of bytes in tHeard > 1600 and auCaptureDropped(sCkMic) is 0 and auCapturePeak(sCkMic) >= 0 \
         and auCaptureDeviceLabel(sCkMic) is not empty, "read as data, none dropped", the number of bytes in tHeard
   put auCaptureRecordStop(sCkMic) into sCkSeconds
   auCaptureStop sCkMic
   auCaptureClose sCkMic
   adCk sCkSeconds > 0.1 and auCaptureIsValid(sCkMic) is false, "the file is finished and the microphone closed", sCkSeconds
   put auDecodeFile(sCkPath, "s16", 0, 0) into tBack
   adCk adNear((the number of bytes in tBack) / 32000, sCkSeconds, 0.01), "the file holds what it recorded", \
         the number of bytes in tBack
   adCkLiveClose
end adCkLiveC

-- One second of a 440 Hz sine, mono, 8000 Hz, 16-bit: 16000 bytes made by
-- script, so what crosses into the library is known to the last bit.
function adSine8k
   local tData, tI
   repeat with tI = 0 to 7999
      put binaryEncode("s", round(8000 * sin(2 * pi * 440 * tI / 8000))) after tData
   end repeat
   return tData
end adSine8k

-- The loudest 16-bit sample of a block, 0 to 32768.
function adLoudest16 pData
   local tI, tValue, tMost
   put 0 into tMost
   repeat with tI = 0 to (the number of bytes in pData) div 2 - 1
      get binaryDecode("s", byte 2 * tI + 1 to 2 * tI + 2 of pData, tValue)
      if abs(tValue) > tMost then
         put abs(tValue) into tMost
      end if
   end repeat
   return tMost
end adLoudest16

-- The loudest sample of one channel of stereo 16-bit samples.
function adLoudestChannel16 pData, pChannel
   local tI, tValue, tMost
   put 0 into tMost
   repeat with tI = 0 to (the number of bytes in pData) div 4 - 1
      get binaryDecode("s", byte 4 * tI + 2 * pChannel - 1 to 4 * tI + 2 * pChannel of pData, tValue)
      if abs(tValue) > tMost then
         put abs(tValue) into tMost
      end if
   end repeat
   return tMost
end adLoudestChannel16

-- The loudest float sample between two fractions of a block of f32 samples.
function adLoudestF32 pData, pFrom, pTo
   local tCount, tI, tValue, tMost
   put (the number of bytes in pData) div 4 into tCount
   put 0 into tMost
   repeat with tI = trunc(tCount * pFrom) to trunc(tCount * pTo) - 1
      get binaryDecode("f", byte 4 * tI + 1 to 4 * tI + 4 of pData, tValue)
      if abs(tValue) > tMost then
         put abs(tValue) into tMost
      end if
   end repeat
   return tMost
end adLoudestF32

-- Polls once and answers the sounds that ended, comma-separated.
function adEndedList
   local tCount, tI, tOut
   put auPollEnded() into tCount
   repeat with tI = 1 to tCount
      put auEndedSound(tI) & comma after tOut
   end repeat
   return tOut
end adEndedList
