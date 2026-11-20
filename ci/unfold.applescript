-- Usage: osascript ci/unfold.applescript "Device Hub"
-- Finds and clicks the simulator app's menu item that unfolds the device.
-- Prints every menu item mentioning fold/posture/open so the name can be
-- pinned once seen in a CI log.
on run argv
set appName to item 1 of argv
tell application appName to activate
delay 1
tell application "System Events"
	log "processes: " & ((name of every process whose background only is false) as text)
	tell process appName
		set found to {}
		set target to missing value
		repeat with m in menu bar items of menu bar 1
			try
				repeat with i in menu items of menu 1 of m
					set n to name of i as text
					if n contains "Fold" or n contains "fold" or n contains "Posture" or n contains "Open" then
						set end of found to (name of m as text) & " > " & n
						if (n contains "Unfold" or n is "Open") and target is missing value then set target to i
					end if
					try
						repeat with j in menu items of menu 1 of i
							set n2 to name of j as text
							if n2 contains "Fold" or n2 contains "fold" or n2 contains "Open" or n2 contains "Flat" then
								set end of found to (name of m as text) & " > " & n & " > " & n2
								if (n2 contains "Unfold" or n2 is "Open" or n2 contains "Flat") and target is missing value then set target to j
							end if
						end repeat
					end try
				end repeat
			end try
		end repeat
		set AppleScript's text item delimiters to linefeed
		log (found as text)
		if target is not missing value then
			click target
			log "clicked " & (name of target as text)
		else
			log "no unfold item found"
		end if
	end tell
end tell
end run
