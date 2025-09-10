

FFXIWatch - This addon is designed to forward chats to your Discord server.

1) Install
   - Copy the folder "ffxiwatch" into: Ashita 4\addons\
   - Load the addon initially to create the settings file.

2) In Discord, copy your webhook URL (Server Settings → Integrations → Webhooks).
 - Make sure your Discord role has permission to see the channel bound to the webhook.
 
3) In config\addons\ffxiwatch\
   Paste your personalized webhook in your settings file. Example:

    
    settings["webhooks"][4] = "https://discord.com/api/webhooks/....."; ---→ This would forward all party chat (excluding yourself).
    
   Numbers will correspond to the chat mode: (keep this handy for future reference)   
   
    [1]  = 'Say',   
    [2]  = 'Shout',   
    [3]  = 'Tell',    
    [4]  = 'Party',    
    [5]  = 'Linkshell 1',   
    [6]  = 'Linkshell 2 (legacy)',   
    [7]  = 'Emote',   
    [9]  = 'Yell',   
    [10] = 'Unity',   
    [27] = 'Linkshell 2',  

4) If you have the addon loaded, reload it.

5) Type /ffw test 4 or /ffw test 27 to verify.

6) In-game commands
   /ffw                 → shows status + help
   /ffw party on|off    → toggle party
   /ffw ls1 on|off      → toggle Linkshell 1
   /ffw ls2 on|off      → toggle Linkshell 2
   /ffw test <mode>     → send a test ping to that webhook
   /ffw save            → write config\settings.lua

7) Security
   - Webhooks can post to your channel if leaked. Keep settings.lua private.
   - To rotate, delete the webhook in Discord and make a new one; then /ffw set + /ffw save.
   - Be aware that this can make your discord channel full of chatter, use Say, SHout, Yell, and       Linkshell modes with caution.
  
