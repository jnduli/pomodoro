#!/usr/bin/env bash
#
# Runs pomodoro with specified work duration and rest
#
# For countdown the SECONDS (see man bash) variable is used

# unofficial strict mode: http://redsymbol.net/articles/unofficial-bash-strict-mode/
set -euo pipefail
IFS=$'\t\n'

scriptDir=$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")
cd "$scriptDir"

readonly VERSION='0.2'
readonly SOUNDFILE='alarm.oga'
readonly CONFIG_FILE="$HOME/.config/pomodoro/config"

# these variables can be changed in a config file
WORK=25
REST=5
SECS_IN_MINUTE=60
NOTIFICATION_TYPE="sound" # can also be dunst
DISABLE_NOTIFICATIONS_WHILE_WORKING=0 # can be 0 or 1

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
# Set to 1 when tasks change so count_down redraws before the next second
VIEW_CHANGED=0
# Progress of the current work or rest in seconds, kept while paused or chiming
COUNT_START=0
COUNT_END=0
COUNT_NOW=0
POMODORO_NUMBER=0
COMPLETED_POMODOROS=0
# Last title set by set_title, so tmux is only called when it changes
SHOWN_TITLE=''

# Colors used in display
readonly red=$'\033[31m' # work
readonly green=$'\033[32m' # rest and done tasks
readonly yellow=$'\033[33m' # pause
readonly label=$'\033[1;7m' # bold and inverted, for the state label
readonly blink=$'\033[5m' # chiming
readonly dim=$'\033[2m' # hints and secondary text
readonly strikethrough=$'\033[9m' # strike through abandoned tasks
readonly clear=$'\033[0m' # clear formatting
readonly BAR_WIDTH=30

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

# Plays the sound or uses notify-send, depending on NOTIFICATION_TYPE
notify () {
    # TODO: look for more generic way to detect this
    local i3_lock_process
    i3_lock_process=$(pgrep -c i3lock || true) ## I use i3lock together with xautolock
    if [[ $i3_lock_process == "0" ]]; then
        if [[ $NOTIFICATION_TYPE == "sound" ]]; then
            local paplay_volume=${VOLUME:-20000}
            paplay --volume="${paplay_volume}" "$SOUNDFILE" & # in background so keys stay responsive
        else
            notify-send --app-name="pomodoro" "Check pomodoro, either break or work has ended"
        fi
    fi
}

# Draws content over the whole screen. It overwrites the previous frame, clearing
# the rest of each line, instead of clearing the screen first so it doesn't flicker
# Arguments:
#   content ($1): text to draw, can span multiple lines
render () {
    printf '\033[H%s\033[K\033[J' "${1//$'\n'/$'\033[K\n'}"
}

# Turns terminal echo on or off, echo is off outside prompts so stray keys aren't printed
# Arguments:
#   on|off ($1)
set_echo () {
    [[ -t 0 ]] || return 0
    [[ $1 == on ]] && stty echo || stty -echo
}

# Reads a line of input below the screen, the next render clears the prompt
# Arguments:
#   variable to store the answer in ($1)
#   prompt ($2)
ask () {
    local -n _answer=$1
    set_echo on
    printf '\033[?25h\033[?7h' # show cursor and wrap long input while typing
    read -r -p $'\n\n  '"$2" _answer
    printf '\033[?25l\033[?7l'
    set_echo off
    VIEW_CHANGED=1
}

# Counts time spent from start until end, redrawing the screen every second
# Globals:
#   SECONDS
#   COUNT_START, COUNT_END, COUNT_NOW
#   VIEW_CHANGED
# Arguments:
#   start ($1): seconds already spent
#   end ($2): seconds to stop at
# Returns
#   1 if quit before the end
count_down () {
    COUNT_START=$1
    COUNT_END=$2
    SECONDS=$1
    local shown=-1
    local icon='🍅'
    [[ $POMODORO_STATE == rest ]] && icon='☕'
    while (( SECONDS <= $2 )); do
        COUNT_NOW=$(( SECONDS < $2 ? SECONDS : $2 )) # SECONDS can tick past the end after the check
        if (( VIEW_CHANGED || shown != COUNT_NOW )); then
            render "$(screen_view)"
            set_title "$icon $(( (COUNT_END - COUNT_NOW + 59) / 60 ))m"
            shown=$COUNT_NOW
            VIEW_CHANGED=0
        fi
        handle_countdown_input || return 1
    done
}

# Prints the whole screen for the current POMODORO_STATE, for render to draw
screen_view () {
    local timed_state=$POMODORO_STATE # the work or rest being counted, also while paused or chiming
    [[ $timed_state == pause || $timed_state == chime ]] && timed_state=$PREVIOUS_POMODORO_STATE

    local color title hints
    case $POMODORO_STATE:$timed_state in
        work:*)     color=$red    title="WORK"              hints="[p] pause  [q] end work" ;;
        rest:*)     color=$green  title="BREAK"             hints="[p] pause  [q] end break" ;;
        pause:*)    color=$yellow title="PAUSED"            hints="[p] resume" ;;
        chime:work) color=$red    title="WORK · TIME'S UP"  hints="[q] start break  [c] keep working" ;;
        chime:rest) color=$green  title="BREAK · TIME'S UP" hints="[q] start work  [c] keep resting" ;;
    esac
    [[ $POMODORO_STATE == work ]] && hints+="  [a] add  [d] done  [c] cancel"
    local label_style=$color$label
    [[ $POMODORO_STATE == chime ]] && label_style+=$blink

    local tally
    printf -v tally '%*s' "$COMPLETED_POMODOROS" ''
    printf '\n  🍅 Pomodoro %s  %s %s %s  %s%s%s\n\n' "$POMODORO_NUMBER" "$label_style" "$title" "$clear" "$green" "${tally// /●}" "$clear"
    progress_view "$color"
    if [[ $POMODORO_STATE == chime ]]; then
        printf '  ringing for %d:%02d\n' $(( SECONDS / 60 )) $(( SECONDS % 60 ))
    fi
    if [[ $timed_state == work ]]; then
        printf '\n'
        task_list_view
    fi
    printf '\n  %s%s%s' "$dim" "$hints" "$clear"
}

# Prints the progress bar and time left of the current work or rest
# Arguments:
#   color ($1): color of the filled part of the bar
progress_view () {
    local length=$(( COUNT_END - COUNT_START ))
    local filled=$BAR_WIDTH
    (( length > 0 )) && filled=$(( (COUNT_NOW - COUNT_START) * BAR_WIDTH / length ))
    local left=$(( COUNT_END - COUNT_NOW ))
    local bar empty
    printf -v bar '%*s' "$filled" ''
    printf -v empty '%*s' $(( BAR_WIDTH - filled )) ''
    printf '  %s%s%s%s%s' "$1" "${bar// /█}" "$dim" "${empty// /░}" "$clear"
    printf '  %02d:%02d left  %s%s min spent%s\n' $(( left / 60 )) $(( left % 60 )) "$dim" $(( COUNT_NOW / SECS_IN_MINUTE )) "$clear"
}

handle_countdown_input () {
    local input status=0
    read -r -t 0.25 -N 1 input || status=$? # >128 on timeout, 1 on EOF
    # on EOF (stdin not a terminal) read returns immediately, wait to avoid busy looping
    (( status > 0 && status <= 128 )) && { read -r -t 0.25 -u "$IDLE_FD" || true; }
    case "$POMODORO_STATE:${input^^}" in
        chime:Q) # stops chiming and moves to next state
            [[ $PREVIOUS_POMODORO_STATE == "work" ]] && POMODORO_STATE="rest" || POMODORO_STATE="work"
            ;;
        pause:P|chime:C) # unpauses, or stops chiming and continues previous state
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
        work:A) add_to_list ;;
        work:D) complete_task ;;
        work:C) cancel_task ;;
    esac
}

# Shows the paused screen until unpaused
pause_forever () {
    render "$(screen_view)"
    while [[ $POMODORO_STATE == "pause" ]]; do
        handle_countdown_input
    done
    VIEW_CHANGED=1
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
        if [[ $current_state == work && $spent == "$length" ]]; then
            COMPLETED_POMODOROS=$(( COMPLETED_POMODOROS + 1 ))
        fi
        PREVIOUS_POMODORO_STATE=$POMODORO_STATE
        POMODORO_STATE="chime"
        chiming_with_input
    done
}

# Plays notification until key is pressed, redrawing the screen every second
# Globals:
#   SECONDS
chiming_with_input () {
    SECONDS=0
    set_title "⏰ time's up"

    local last_chime=-1
    local shown_duration=-1
    while [[ $POMODORO_STATE == "chime" ]]; do
        local duration=$SECONDS
        if (( duration != shown_duration )); then # drawn before notify since playing sound blocks
            render "$(screen_view)"
            shown_duration=$duration
        fi
        if (( duration % 3 == 0 && duration != last_chime )); then # chime every 3 seconds
            notify
            last_chime=$duration
        fi
        handle_countdown_input
    done
}

# Prints the tasks one per line, marking done ones green and abandoned ones struck through
task_list_view () {
    if (( ${#TODO[@]} == 0 )); then
        printf '  %sno tasks yet, press [a] to add%s\n' "$dim" "$clear"
        return
    fi
    local i
    for i in "${!TODO[@]}"; do
        if [[ -v COMPLETED[$i] ]]; then
            printf '  %s %s✓ %s%s\n' "$i" "$green" "${TODO[i]}" "$clear"
        elif [[ -v ABANDONED[$i] ]]; then
            printf '  %s %s✗ %s%s%s\n' "$i" "$dim" "$strikethrough" "${TODO[i]}" "$clear"
        else
            printf '  %s • %s\n' "$i" "${TODO[i]}"
        fi
    done
}

add_to_list() {
    local tasks task
    local -a new_tasks
    ask tasks 'Add tasks, separated by commas: '
    IFS=',' read -r -a new_tasks <<< "$tasks" # comma separated input
    for task in "${new_tasks[@]}"; do
        task=${task#"${task%%[![:space:]]*}"} # trim leading whitespace
        task=${task%"${task##*[![:space:]]}"} # trim trailing whitespace
        if [[ -n $task ]]; then
            TODO+=("$task")
        fi
    done
}

# Marks the task number entered in the given set, or unmarks it if already there
# Arguments:
#   name of the COMPLETED or ABANDONED set ($1)
toggle_task() {
    local -n _arr=$1
    local task_index
    ask task_index 'Task number: '
    if [[ -n $task_index ]]; then
        [[ ${_arr[$task_index]+Y} ]] && unset "_arr[$task_index]" || _arr[$task_index]=1
    fi
}

complete_task() { toggle_task COMPLETED; }
cancel_task()   { toggle_task ABANDONED; }

# Runs the next pomodoro's work and then its rest
single_pomodoro_run () {
    POMODORO_NUMBER=$(( POMODORO_NUMBER + 1 ))
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

# Shows text in the terminal title and tmux window name, only when it changes
# Arguments:
#   title ($1)
set_title () {
    [[ $1 == "$SHOWN_TITLE" ]] && return 0
    SHOWN_TITLE=$1
    printf '\033]2;%s\007' "$1"
    if [[ -n ${TMUX_PANE:-} ]]; then
        tmux rename-window -t "$TMUX_PANE" "$1"
    fi
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
--debug-mode: debug mode (The time counter uses seconds instead of minutes)

Advanced configuration:
You can provide advanced configuration by having a file in ~/.config/pomodoro/config.
Here's an example with comments:

WORK=25 # time to work in minutes
REST=5 # time to rest in minutes
NOTIFICATION_TYPE="sound" # can also be dunst
DISABLE_NOTIFICATIONS_WHILE_WORKING=1 # can be 0 or 1
VOLUME=20000 # sound volume passed to paplay, 65536 is 100%
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

# Uses the alternate screen, like less or htop, so the terminal is left as it was on exit
setup_terminal () {
    tput smcup
    printf '\033[22;0t' # save the terminal title so it can be restored
    printf '\033[?25l\033[?7l' # hide cursor, don't wrap lines
    set_echo off
}

restore_terminal () {
    printf '\033[?25h\033[?7h'
    printf '\033[23;0t' # restore the terminal title
    tput rmcup
    set_echo on
    if [[ -n ${TMUX_PANE:-} ]]; then
        tmux set-window-option -t "$TMUX_PANE" -u automatic-rename || true
    fi
    printf "Pomodoros completed: %s\n" "$COMPLETED_POMODOROS"
}

main () {
    options "$@"
    check_prerequisites
    # Ensure clean terminal state however the script exits, even mid-render
    trap restore_terminal EXIT
    trap 'exit 0' INT TERM
    setup_terminal
    while true; do
        single_pomodoro_run
    done
}

main "$@"
