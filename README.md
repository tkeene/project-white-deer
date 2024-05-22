# project-white-deer
An open source Godot Engine 4.2 action-adventure character controller in the style of Zelda 64.
Source: https://github.com/tkeene/project-white-deer
Playable demo here: https://koboldskeep.itch.io/project-white-deer
This is released under the MIT license. It would be nice if you credited this GitHub page or @koboldskeep.

Libraries Used:
* DebugDraw by https://github.com/DmitriySalnikov (currently disabled because it breaks Firefox builds, see debug_draw.gd)

Features:
* Awful programmer art
* Walks on ground and up/down slopes
* Camera can be rotated horizontally
* Camera detects walls and pulls in to avoid them
* Detects ledges/chasms and jumps off of them
* Can glide for air control and slower descent
* Detects knee-high ledges and hops up onto them
* Detects high ledges, jumps to grab the corner, then climbs up onto them
* Climbs vertically and horizontally on climbable surfaces using physics layers (they're green in the demo)
* A short dash
* Simple drop shadow
* Can stab things with a sword
* Can charge up a sword spin attack
* You can juggle boxes for a high score

Roadmap: Stuff I'd like to add. Please let me know if there's anything you'd like to see it do too.
* Slide down slopes that are too steep
* Refactor states to reside more within self-contained functions
* Determine whether it's worth switching to move_and_slide or spherecasts (currently it's all raycasts)
* Upgrade from Godot Engine 4.2 to Godot Engine 4.3
* Fix DebugDraw to only work in editor and not cause Firefox build problems
* Refactor drop shadows
* Refactor dust poofs from walking
* Add a component that handles placeholder animation states (currently only gliding does anything visible)
* Set it up to use GDQuest's 3D character assets
* Swimming and diving
* Reading signs with a dialogue system (or integrate an existing dialogue system)
* An animation for opening treasure chests
* Items that unlock new abilities on the character controller
* Obstacles that can only be destroyed by the charge up spin attack
* Camera lock-on for moving foes
* A ranged attack item
* Torches that can be lit and extinguished
* Better handling of climbing on floors and ceilings