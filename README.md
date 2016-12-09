# sensu-plugin-auto-resolve

**What it does**
This plugin is a Sensu handler that resolves a critical/warning in Sensu after a specified amount of time in seconds. The amount of time can be supplied in a tag. I used this source as the base for this script: https://github.com/sensu-plugin/sensu-plugins-time-to-live.

This script is extremely useful in situations where you fire one-off events to the Sensu platform, for instance from a central logging tool like Graylog using the Sensu Alarm Callback plugin. By using the auto_resolve handler, you don't need to acknowledge events by hand.


**Installation**
- Add the script to the Sensu extensions directory (e.g. /etc/sensu/extensions).
- Restart the Sensu server.

**Usage**
- Add the handler ```auto_resolve``` to the check
- Add the tag ```auto_resolve_time=X``` to the check, where ```X``` is the number of seconds after which the alert should be resolved.

