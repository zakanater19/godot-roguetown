
EXTREMELY WIP but currently playable without compilation errors or major gameplay bugs. (Content is currently thin, working on foundation first)


godot 4.7 (delete .godot folder in project to refresh shaders, you'll need to do that if you get any errors or weird visual bugs)

roguetown in godot, sprites/mechanics from here [https://github.com/Rotwood-Vale/Ratwood-Keep] (https://github.com/SS13-Special-Codebases-Archive/RogueTown)

just download godot 4.7 and open project.godot inside godot, no external tools needed. (for the smoke test you need to put the project files into a new folder, and in the folder above the project place the godot 4.7.exe



Multiplayer is one person hosts and others join via direct IP or the built-in server browser.
Patching is automatic - your client checks the host's game version and if it doesn't match, it downloads the host's current game files over the connection and restarts with them. 
Rejoining/disconnect/reconnect/latejoin all works

To check patching, run `pwsh -File ./run_patch_smoketest.ps1` (PowerShell 7); add `-HostMode Exported` to test an exported host. The test uses an isolated copy and exports the game with the installed standard templates.

Keybinds;
Q - drop item

Z - resist AND active hand item object interaction

X - swap hands

V - lay down / stand up

R - throw

hold left shift + left click - inspect

C - combat mode toggle - Right mouse shoves other players with empty hand in combat mode

hold SPACEBAR to run

Shift+F to look up

rest are UI buttons

Very out of date video, ill get around to recording a new one when the game actually looks good.




https://github.com/user-attachments/assets/a926e817-4305-4e13-8aa2-a9a2653f09d6


