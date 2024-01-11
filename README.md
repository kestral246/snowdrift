Snowdrift
=========
Extensions to **snowdrift 0.6.4** by **paramat**

For Minetest 5.0.0 and later.

Depends: default

**Note:** To use this mod, Minetest Game's "Enable weather" option needs to be disabled.

Changes
-------
**new**

- Finally merged in paramat's 0.6.4 changes.
- Updated to use get_pos() and get_2d().
- Updated to use set_sky(sky_parameters).


I've tried to make the abrupt transitions in this mod a little smoother.

- Cloud cover gradually increases before rain starts, and gradually decreases after rain stops.
- Fully overcast skies gradually darken after dusk and lighten before dawn.
- Amount of rain and/or snow falling gradually increases or decreases.
- Crossing into or out of dry desert biomes gradually decreases or increases amount of precipitation.
- Crossing into or out of freezing biomes gradually shifts percentage of rain versus snow.
- Rain sound gradually changes volume based on amount of rain falling.


I've also included debug code, which can be enabled by setting debug = true.


David G (kestral246)

Licenses
--------
Source code:

- MIT by paramat and David G (kestral246@gmail.com)

Media:

- Textures CC BY-SA (3.0) by paramat
- Sounds CC BY (3.0) by inchadney (http://freesound.org/people/inchadney/sounds/58835/)
