This plugin will simultaneously post an Announcement to all Survivors when another Survivor Breaks a Barricade, notify admins with a running total and warn the Survivor who Broke the Barricade, Hopefuly this should help Admins deal with griefers.   
This also includes punishment system, but its disabled by default.   
   

# Installation
Simply put the folders under your `addons/sourcemod` folder

# Convars
`zps_barricadekiller_version -- Checks the version of the plugin`   
`sm_barricadekiller_enabled <0|1> -- Turns Barricade Killer Off/On. (1/0)`   
`sm_barricadekiller_punish <0|1> -- Punish the person who broke it, 0=disabled, 1=enabled.`   
`sm_barricadekiller_punish_scale <0|99> -- Set the slap damage, 1=min, 99=max.`   
`sm_barricadekiller_punish_multiply <0|1> -- Set the slap damage multiplier, 1=min, 99=max.`   
`sm_barricadekiller_punish_total <0|1> -- How many times they need to break a barricade until punishment takes effect, 1=min, 15=max.`   
`sm_barricadekiller_punish_owner <0|1> -- Don't punish the owner, 0=disabled, 1=enabled.`   
`sm_barricadekiller_reset <0|1> -- When to reset Running Totals, 0=never, 1=map, 2=round.`   
`sm_barricadekiller_debug <0|1> -- Debugging mode, 0=disabled, 1=enabled.`   
   

This plugin will automatically create a config file under `cfg/sourcemod/`