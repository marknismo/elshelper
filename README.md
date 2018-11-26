# elshelper
Helper script to download Cloudflare Enterprise logs

# Purpose of ELS download helper
- download Cloudflare Enterprise logs despite the CF API limitations mentioned in the link below:
https://support.cloudflare.com/hc/en-us/articles/216672448-Enterprise-Log-Share-Logpull-REST-API


# Features
- help download logs for a time range exceeding the time range of 1 hour
- instead of hard-limiting requests to 1 minute at a time, a variable time range is used to download the logs more efficiently
- automatic handling of the API failure to stream more than 1 GB of data for time ranges greater than 1 minute


# Usage
- Optional: create a directory/folder to run the command in
- chmod u+x elsh.sh
- run "./elsh.sh"


# Pre-requsite
- install jq


Screenshot of what it looks like on Mac OS
![screenshot](https://raw.githubusercontent.com/marknismo/elshelper/master/screenshot.jpg)
