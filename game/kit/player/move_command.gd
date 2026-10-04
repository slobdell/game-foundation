class_name MoveCommand
extends RefCounted
## What the player character should do THIS physics tick. Something decides (the keyboard, a gamepad, the
## autopilot, a test) and fills one of these in; the character only does what it says.
##
## Keeping "deciding" apart from "doing" is why the same character can be driven by a person, by a script for
## screenshots, or by a test, without changing the character at all.

## Which way to move, in WORLD space, flat (y = 0), length 0..1 (0.5 = walk half speed).
var direction := Vector3.ZERO
var jump := false
var sprint := false
var interact := false
var attack := false
