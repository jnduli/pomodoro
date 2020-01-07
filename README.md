# Pomodoro

This is a bashscript project that provides a simple to use pomodoro.

[![asciicast](https://asciinema.org/a/291141.svg)](https://asciinema.org/a/291141)

To run a pomodoro where you work for 30 minutes and rest for 10 minutes
do:

```
pomodoro.sh -r 10 -p 30
```

To get more help and options, do:

```
pomodoro.sh -h
```

## Features

- Set up the working time and resting time e.g. to rest for 5 minutes
  and work for 30 minutes: `pomodoro.sh -r 10 -p 30`
- Debug mode, where the pomodoro runs for seconds instead of minutes:
  `pomodoro.sh -r 5 -p 5 -d`
- Retrospection mode, where the script outputs all the work logged
  during the day: `pomodoro.sh -l`
- Support for continuing to work when you are in the zone (Just press c
  when you're supposed to be on break)
