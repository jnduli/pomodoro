# Pomodoro

A bashscript project that provides a simple to use pomodoro.

[![asciicast](https://asciinema.org/a/291141.svg)](https://asciinema.org/a/291141)

## Installation

```bash
git clone https://github.com/jnduli/pomodoro.git
cd pomodoro
ln -sf $(pwd)/pomodoro.sh $HOME/.local/bin/pomodoro
```

## Quick Start Usage

To run a pomodoro where you work for 30 minutes and rest for 10 minutes do:

```bash
pomodoro -r 10 -w 30 # work for 30 minutes, rest for 10 seconds
pomodoro -h # detailed help instructions
```

## Debugging

```bash
pomodoro -r 2 -w 5 --debug-mode # runs for 5 seconds work and 2 seconds instead of minutes
```

You can also add: `set -x` and a `set +x` between sections to debug.
