# sinab
Sinab Is Not A Backup

sinab creates and maintains btrfs snapshots.


# Usage:
1. Edit sinab_example.conf
2. Copy the config file to /usr/local/etc/ 
3. Run /path/to/sinab name_of_config
4. Add a line to cron like this:
*/15 * * * * /path/to/sinab sinab_example 1> /dev/null

