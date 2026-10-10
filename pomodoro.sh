#!/usr/bin/env bash
#
# Runs pomodoro with specified work duration and rest
#
# For countdown the SECONDS (see man bash) variable is used

# unofficial strict mode: http://redsymbol.net/articles/unofficial-bash-strict-mode/
set -euo pipefail
IFS=$'\t\n'

scriptDir=$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")
cd "$scriptDir" || exit

readonly VERSION='0.2'
readonly SOUNDFILE='alarm.oga'
readonly CONFIG_FILE="$HOME/.config/pomodoro/config"

# these variables can be changed in a config file
WORK=25
REST=5
SECS_IN_MINUTE=60
NOTIFICATION_TYPE="sound" # can also be dunst
DISABLE_NOTIFICATIONS_WHILE_WORKING=0 # can be 0 or 1
NO_TASKS=0 # can be 0 or 1, 1 skips entering and tracking tasks


# Loading values from configuration file stored in ~/.config/pomodoro/config
if [ -f "$CONFIG_FILE" ]; then
    # shellcheck source=/dev/null
    source "${CONFIG_FILE}"
fi

# Global variables
TODO=()
declare -A COMPLETED
declare -A ABANDONED

# Pipe that never receives data, reading from it with a timeout sleeps without
# forking or using cpu
exec {IDLE_FD}<> <(:)

# can be: work, rest, chime, pause
POMODORO_STATE="work"
PREVIOUS_POMODORO_STATE="rest"
# Set to 1 when tasks change so count_down redraws before the next minute
VIEW_CHANGED=0

# Colors used in display
readonly green='\033[0;32m' # green for done tasks
readonly strikethrough='\033[0;9m' # strike through abandoned tasks
readonly clear='\033[0m' # clear formatting

# Exits if a command needed by the current configuration isn't installed
check_prerequisites () {
    local -A install_hints=(
        [paplay]="Try to install pulseaudio"
        [notify-send]="Try to install libnotify"
        [dunstctl]="Try to install dunst"
        [tput]="Try to install ncurses"
    )
    local required=("tput")
    [[ $NOTIFICATION_TYPE == "sound" ]] && required+=("paplay") || required+=("notify-send")
    [[ $DISABLE_NOTIFICATIONS_WHILE_WORKING == 1 ]] && required+=("dunstctl")

    local command
    for command in "${required[@]}"; do
        if ! command -v "$command" &> /dev/null; then
            printf "Command: %s is not found, please install it. %s\n" "$command" "${install_hints[$command]}"
            exit 1
        fi
    done
}

# Plays or uses notify-send to send notification
# Arguments
#   notification_type
# Returns
#   None
notify () {
    local notify_type=$1
    # TODO: look for more generic way to detect this
    local i3_lock_process
    i3_lock_process=$(pgrep -c i3lock || true) ## I use i3lock together with xautolock
    if [[ $i3_lock_process == "0" ]]; then
        if [[ ${notify_type} == "sound" ]]; then
            local paplay_volume=${VOLUME:-20000}
            paplay --volume="${paplay_volume}" "$SOUNDFILE" & # in background so keys stay responsive
        else
            notify-send --app-name="pomodoro" "Check pomodoro, either break or work has ended"
        fi
    fi
}

# Text drawn by the last render, the next render replaces it
RENDERED_CONTENT=''
# Lines between the cursor and the first line of RENDERED_CONTENT
RENDERED_LINES=0

# Redraws the live area of the screen, replacing what the previous render drew.
# Line wrapping is off while drawing so each line takes exactly one row
# Arguments:
#   content ($1): text to draw, can span multiple lines
render () {
    (( RENDERED_LINES > 0 )) && printf '\033[%dA' "$RENDERED_LINES"
    printf '\r\033[J\033[?7l%s\033[?7h' "$1"
    local newlines=${1//[!$'\n']/}
    RENDERED_LINES=${#newlines}
    RENDERED_CONTENT=$1
}

# Leaves what was rendered on screen, the next render starts below it
render_commit () {
    [[ -n $RENDERED_CONTENT ]] && printf '\n'
    RENDERED_CONTENT=''
    RENDERED_LINES=0
}

# Turns terminal echo on or off, echo is off outside prompts so stray keys aren't printed
# Arguments:
#   on|off ($1)
set_echo () {
    [[ -t 0 ]] || return 0
    [[ $1 == on ]] && stty echo || stty -echo
}

# Reads a line of input below the rendered area, the next render clears the prompt
# Arguments:
#   variable to store the answer in ($1)
#   prompt ($2)
ask () {
    local -n _answer=$1
    set_echo on
    if [[ -n $RENDERED_CONTENT ]]; then
        read -r -p $'\n'"$2" _answer
        RENDERED_LINES=$(( RENDERED_LINES + 2 ))
    else
        read -r -p "$2" _answer
        RENDERED_LINES=$(( RENDERED_LINES + 1 ))
    fi
    set_echo off
}

strip_TODO_tasks () {
    for (( i=0; i < ${#TODO[@]}; i ++ )); do
        local stripped_task=$(echo "${TODO[i]}" | xargs -I _ printf '%s' _ )
        TODO[i]="$stripped_task"
    done
}

# Counts time spent from start until end, showing it in minutes
# Globals:
#   SECS_IN_MINUTE
#   SECONDS
#   VIEW_CHANGED
# Arguments:
#   start ($1): seconds already spent
#   end ($2): seconds to stop at
# Returns
#   1 if quit before the end
count_down () {
    # TODO: this should behave differently depending of its work or rest
    local printed_minutes=-1
    SECONDS=$1
    while (( SECONDS <= $2 )); do
        local minutes=$(( SECONDS/SECS_IN_MINUTE ))
        if (( VIEW_CHANGED || printed_minutes != minutes )); then # updates screen after every minute, preventing stuttering
            printed_minutes=$minutes
            render "$(state_view) Time spent is $printed_minutes minutes"
            VIEW_CHANGED=0
        fi
        handle_countdown_input || return 1
    done
}

# Prints the text for the current POMODORO_STATE, for render to draw
state_view () {
    if [[ $POMODORO_STATE = "work" && $NO_TASKS == 1 ]]; then
        printf "Working: q-quit %s, p-pause:" "$POMODORO_STATE"
    elif [[ $POMODORO_STATE = "work" ]]; then
        printf "%s\n  a-add task, d-do/undo task, c-cancel/uncancel task." "$(task_list_view)"
    elif [[ $POMODORO_STATE = "rest" ]]; then
        printf "Resting: q-quit %s, p-pause:" "$POMODORO_STATE"
    elif [[ $POMODORO_STATE == "pause" ]]; then
        printf "Paused: p to unpause"
    elif [[ $POMODORO_STATE == "chime" ]]; then
        printf "Chiming: q-stop chiming, c-continue with previous state"
    fi
}

handle_countdown_input () {
    local input status=0
    read -r -t 0.25 -N 1 input || status=$? # >128 on timeout, 1 on EOF
    # on EOF (stdin not a terminal) read returns immediately, wait to avoid busy looping
    (( status > 0 && status <= 128 )) && { read -r -t 0.25 -u "$IDLE_FD" || true; }
    case "$POMODORO_STATE:${input^^}" in
        pause:P)
            POMODORO_STATE=$PREVIOUS_POMODORO_STATE
            ;;
        chime:Q) # stops chiming and moves to next state
            [[ $PREVIOUS_POMODORO_STATE == "work" ]] && POMODORO_STATE="rest" || POMODORO_STATE="work"
            ;;
        chime:C) # stops chiming and continues previous state
            POMODORO_STATE=$PREVIOUS_POMODORO_STATE
            ;;
        work:P|rest:P)
            local paused_time=$SECONDS
            PREVIOUS_POMODORO_STATE=$POMODORO_STATE
            POMODORO_STATE="pause"
            pause_forever
            SECONDS=$paused_time
            ;;
        work:Q|rest:Q)
            return 1
            ;;
        # TODO: change inputs to have a time limit too so that it doesn't hang here
        work:A) (( NO_TASKS )) || add_to_list ;;
        work:D) (( NO_TASKS )) || complete_task ;;
        work:C) (( NO_TASKS )) || cancel_task ;;
    esac
}


# Shows pause instructions below the current view until unpaused
pause_forever () {
    local base=$RENDERED_CONTENT
    render "$base"$'\n'"$(state_view)"
    while [[ $POMODORO_STATE == "pause" ]]; do
        handle_countdown_input
    done
    render "$base"
}


# Countdowns to zero depending on whether working or resting
# Arguments:
#   time in minutes ($1)
work_or_rest () {
    local length=$(( $1 * SECS_IN_MINUTE ))
    local spent=0
    local current_state=$POMODORO_STATE
    while [[ $POMODORO_STATE == "$current_state" ]]; do # continuing after the chime adds another length
        count_down "$spent" $(( spent + length )) || break
        spent=$(( spent + length ))
        PREVIOUS_POMODORO_STATE=$POMODORO_STATE
        POMODORO_STATE="chime"
        chiming_with_input
    done
    render_commit
}

# Plays notification until key is pressed, showing chime instructions below
# the current view
# Globals:
#   SECONDS
chiming_with_input () {
    local base=$RENDERED_CONTENT
    local instructions
    instructions=$(state_view)
    SECONDS=0

    local last_chime=-1
    local shown_duration=-1
    while [[ $POMODORO_STATE == "chime" ]]; do
        local duration=$SECONDS
        if (( duration != shown_duration )); then # drawn before notify since playing sound blocks
            render "$base"$'\n'"$instructions"$'\n'"Chiming duration: $((duration / 60)) min $((duration % 60)) sec"
            shown_duration=$duration
        fi
        if (( duration % 3 == 0 && duration != last_chime )); then # chime every 3 seconds
            notify "$NOTIFICATION_TYPE"
            last_chime=$duration
        fi
        handle_countdown_input
    done
    render "$base"
}

# Prints the tasks one per line, done ones green and abandoned ones struck through
task_list_view () {
    local i style
    for i in "${!TODO[@]}"; do
        style=''
        [[ -v ABANDONED[$i] ]] && style=$strikethrough
        [[ -v COMPLETED[$i] ]] && style=$green
        printf '  %s: %b%s%b\n' "$i" "$style" "${TODO[i]}" "$clear"
    done
}

add_to_list() {
    local tasks
    ask tasks 'Add Tasks: '
    if [[ -n $tasks ]]; then
        local temp_arr
        readarray -td',' temp_arr <<< "$tasks" # comma separated input
        TODO+=("${temp_arr[@]}")
        strip_TODO_tasks
        VIEW_CHANGED=1
    fi
}

toggle_task() {
    local -n _arr=$1
    local _val=$2
    local task_index
    ask task_index 'Tasks no: '
    if [[ -n $task_index ]]; then
        [[ ${_arr[$task_index]+Y} ]] && unset "_arr[$task_index]" || _arr[$task_index]="$_val"
        VIEW_CHANGED=1
    fi
}

complete_task() { toggle_task COMPLETED "DONE"; }
cancel_task()   { toggle_task ABANDONED "ABANDONED"; }

# Arguments:
#   n : The current pomodoro number
single_pomodoro_run () {
    printf "Pomodoro %s\n" "$1"
    if [[ $NO_TASKS == 0 ]]; then
        [[ $1 == 1 ]] && printf "Plan is a list separated by a comma i.e. task1,task2,task3\n"
        add_to_list
    fi
    if [ $DISABLE_NOTIFICATIONS_WHILE_WORKING = 1 ]; then
        dunstctl set-paused true
    fi
    POMODORO_STATE="work"
    work_or_rest "$WORK"

    # reset global values
    TODO=()
    COMPLETED=()
    ABANDONED=()

    if [ $DISABLE_NOTIFICATIONS_WHILE_WORKING = 1 ]; then
        dunstctl set-paused false
    fi
    POMODORO_STATE="rest"
    work_or_rest "$REST"
}

rename_window_in_tmux () {
    [[ -n ${TMUX:-} ]] && tmux rename-window "pomodoro"
}


show_help () {
    cat <<EOF
Copyright (C) 2023: John Nduli K.                                                                                                      
pomodoro.sh version $VERSION:

Pomodoro (https://en.wikipedia.org/wiki/Pomodoro_Technique) allows regular
work and break cycles during your day.

This script provides a terminal interface for doing pomodoro.

Example usage:
pomodoro --rest 5 --work 25

Flags:

-h, --help: Show help file
-w, --work <arg>: Set time for work in minutes
-r, --rest <arg>: Set time for rest in minutes
--no-sound: don't play the sound to notify
--no-tasks: don't prompt for or track tasks, only run the timer
--debug-mode: debug mode (The time counter uses seconds instead of minutes)

Advanced configuration:
You can provide advanced configuration by having a file in ~/.config/pomodoro/config.
Here's an example with comments:

WORK=25 # time to work in minutes
REST=5 # time to rest in minutes
NOTIFICATION_TYPE="sound" # can also be dunst
DISABLE_NOTIFICATIONS_WHILE_WORKING=1 # can be 0 or 1
NO_TASKS=0 # can be 0 or 1, 1 skips entering and tracking tasks
EOF
}

# Deals with terminal options provided
# Globals:
#   WORK
#   REST
#   SECS_IN_MINUTE
options () {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -w|--work)
                WORK=$2
                shift
                shift
                ;;
            -r|--rest)
                REST=$2
                shift
                shift
                ;;
            --no-sound)
                NOTIFICATION_TYPE="dunst"
                shift
                ;;
            --no-tasks)
                NO_TASKS=1
                shift
                ;;
            --debug-mode)
                SECS_IN_MINUTE=1
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                echo "Invalid option: $1" >&2
                show_help
                exit 1
                ;;
        esac
    done
}

restore_terminal () {
    printf "\n\033[?7h"
    tput cnorm
    set_echo on
}

main () {
    options "$@"
    check_prerequisites
    # Ensure clean terminal state however the script exits, even mid-render
    trap restore_terminal EXIT
    trap 'exit 0' INT TERM
    set_echo off
    rename_window_in_tmux
    printf "Starting pomodoro, work=%s and rest=%s minutes\n" "$WORK" "$REST"
    local pomodoro_count=1
    while true; do
        single_pomodoro_run $pomodoro_count
        pomodoro_count=$((pomodoro_count+1))
    done
}

main "$@"
