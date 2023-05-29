# Pomodoro

A bashscript project that provides a simple to use pomodoro.

[![asciicast](https://asciinema.org/a/291141.svg)](https://asciinema.org/a/291141)

## Installation
Get the pomodoro script using either git:

```bash
git clone https://github.com/jnduli/pomodoro.git
cd pomodoro
```

or curl:

```bash
curl https://github.com/jnduli/pomodoro/blob/master/pomodoro.sh > pomodoro.sh
```

You can install it globally (i.e. accessed by different logged in users) by:

```bash
cp pomodoro.sh /usr/local/bin
```

or accessed by your user alone using:

```bash
cp pomodoro.sh $HOME/.local/bin
```

## Quick Start Usage

To run a pomodoro where you work for 30 minutes and rest for 10 minutes do:

```
pomodoro.sh -r 10 -p 30
```

To get more help and options, do:

```
pomodoro.sh -h
```

## Features

- Set up the working time and resting time e.g. to rest for 5 minutes and work
  for 30 minutes: `pomodoro.sh -r 5 -p 30`
- Debug mode, where the pomodoro runs for seconds instead of minutes:
  `pomodoro.sh -r 5 -p 5 -d`
- Retrospection mode, where the script outputs all the work logged during the
  day: `pomodoro.sh -l`

## Reading the code
The script starts running from the `main` function, so you can start here
as you try to understand it.

## Debugging bash
To debug a function/section add: `set -x` before the place to debug and a `set
+x` at the end.
