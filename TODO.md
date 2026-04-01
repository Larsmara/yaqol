# Features
- Incorporate the other addon i made "ClassColor Friends" into this one.

# Bugs
- Food reminder didnt dissapear after eating a food buff. Item ID: 255847
- Teleports should be hidden while in a raid
- Trying to turn in a quest on a mob that has a dialog option aswell, the auto turn in allways choose the dialog instead of the quest

Error:
1x [ADDON_ACTION_BLOCKED] AddOn 'yaqol' tried to call the protected function 'yaqolReminderFrame:Hide()'.
[!BugGrabber/BugGrabber.lua]:540: in function '?'
[!BugGrabber/BugGrabber.lua]:524: in function <!BugGrabber/BugGrabber.lua:524>
[C]: in function 'Hide'
[yaqol/Modules/AuraReminder/AuraReminder.lua]:163: in function 'Hide'
[yaqol/Modules/AuraReminder/AuraReminder.lua]:419: in function <...eyaqol/Modules/AuraReminder/AuraReminder.lua:394>


Locals:
self = <table> {
}
event = "ADDON_ACTION_BLOCKED"
addonName = "yaqol"
addonFunc = "yaqolReminderFrame:Hide()"
name = "yaqol"
badAddons = <table> {
 yaqol = true
}
L = <table> {
 NO_DISPLAY_2 = "|cffffff00The standard display is called BugSack, and can probably be found on the same site where you found !BugGrabber.|r"
 ERROR_DETECTED = "%s |cffffff00captured, click the link for more information.|r"
 BUGGRABBER_STOPPED = "|cffffff00There are too many errors in your UI. As a result, your game experience may be degraded. Disable or update the failing addons if you don't want to see this message again.|r"
 USAGE = "|cffffff00Usage: /buggrabber <1-%d>.|r"
 STOP_NAG = "|cffffff00!BugGrabber will not nag about missing a display addon again until next patch.|r"
 NO_DISPLAY_STOP = "|cffffff00If you don't want to be reminded about this again, run /stopnag.|r"
 NO_DISPLAY_1 = "|cffffff00You seem to be running !BugGrabber with no display addon to go along with it. Although a slash command is provided for accessing error reports, a display can help you manage these errors in a more convenient way.|r"
 ERROR_UNABLE = "|cffffff00!BugGrabber is unable to retrieve errors from other players by itself. Please install BugSack or a similar display addon that might give you this functionality.|r"
 ADDON_CALL_PROTECTED = "[%s] AddOn '%s' tried to call the protected function '%s'."
}
