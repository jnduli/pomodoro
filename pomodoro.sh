#!/bin/bash
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
LOG_DIR="$HOME/.pomodoro/"
FILENAME="$(date +"%F").log"
SHOULD_LOG=1 # can be 0 or 1
NOTIFICATION_TYPE="sound" # can also be dunst
DISABLE_NOTIFICATIONS_WHILE_WORKING=1 # can be 0 or 1

FORCE_QUIT_WORK_REST="false"

# Loading values from configuration file stored in ~/.config/pomodoro/config.sh
if [ -f "$CONFIG_FILE" ]; then
    # shellcheck source=/dev/null
    source "${CONFIG_FILE}"
fi

# Global variables
TODO=()
declare -A COMPLETED
declare -A ABANDONED
CURRENT_TASK="work" # temporary value to help determine child tasks, TODO: Drop this

# Colors used in display
green='\033[0;32m' # green for done tasks
strikethrough='\033[0;9m' # strike through abandoned tasks
clear='\033[0m' # clear formatting

PLAY="paplay"

if ! command -v "$PLAY" &> /dev/null; then
    PLAY="aplay"
fi

PREREQUISITES=("$PLAY" "notify-send" "dunstctl")

for command in "${PREREQUISITES[@]}"; do
    if ! command -v "$command" &> /dev/null; then
        printf "Command: %s is not found, please install it\n" "$command"
        exit 1
    fi
done

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
            paplay $SOUNDFILE
        else
            notify-send --app-name="pomodoro" "Check pomodoro, either break or work has ended"
        fi
    fi
}

# Deletes n lines and places cursor on previous line 
# Arguments
#   n (Optional, defaults to 1): No of lines to clear
# Returns
#   None
clear_line () {
    local lines=${1:-1} # defaults to 1
    while (( lines > 0 )); do 
        printf "\033[1A"  # move cursor one line up
        printf "\033[K"   # delete till end of line
        printf "\r" # go to the beginning of the line
        lines=$lines-1
    done
}

strip_TODO_tasks () {
    for (( i=0; i < ${#TODO[@]}; i ++ )); do
        stripped_task=$(echo "${TODO[i]}" | xargs)
        TODO[i]="$stripped_task"
    done
}

# Counts down from time t until 0 minutes
# Globals:
#   SECS_IN_MINUTE
#   SECONDS
# Arguments:
#   time in minutes ($1)
#   break_avoided (Optional $2): the number of times break has been avoided
count_down () {
    # TODO: this should behave differently depending of its work or rest
    # changes in refactor
    #   removing messages
    #
    local secs_to_count_down=$(($1*SECS_IN_MINUTE))
    local printed_minutes=0
    local changed='f'
    local pomodoro_lines=0
    FORCE_QUIT_WORK_REST="false"
    if [[ $CURRENT_TASK = "work" ]]; then
        pomodoro=$(refresh_current_pomodoro_output)
        pomodoro_lines=$(echo -en "$pomodoro" | wc -l)
        printf "%b  a-add task, d-do/undo task, c-cancel/uncancel task. Time spend %s minutes\n" "$pomodoro" "$printed_minutes"
    else 
        pomodoro_lines=0
        printf "q-quit %s, , c-continue %s: Time spent is %s minutes\n" "$CURRENT_TASK" "$CURRENT_TASK" "$printed_minutes"
    fi

    SECONDS=0 
    if [ -n "$2" ]; then
        SECONDS=$(($1*SECS_IN_MINUTE*$2))
        secs_to_count_down=$((($2+1)*$1*SECS_IN_MINUTE))
    fi
    while (( SECONDS <= secs_to_count_down )); do    # Loop until interval has elapsed.
        minutes=$(( SECONDS/SECS_IN_MINUTE ))
        if [[ ${changed^^} == 'T' || $printed_minutes != "$minutes" ]]; then # updates screen after every minute, preventing stuttering
            printed_minutes=$minutes
            # +1 because this is the contents of the pomodoro and the context line with time spent
            clear_line $(( pomodoro_lines + 1 ))
            if [[ $CURRENT_TASK == "work" ]]; then
                pomodoro=$(refresh_current_pomodoro_output)
                pomodoro_lines=$(echo -en "$pomodoro" | wc -l)
                printf "%bHelp: a-add task, d-do/undo task, c-cancel/uncancel task. Time spend %s minutes\n" "$pomodoro" "$printed_minutes"
            else 
                pomodoro_lines=0
                printf "q-quit %s, , c-continue %s: Time spent is %s minutes\n" "$CURRENT_TASK" "$CURRENT_TASK" "$printed_minutes"
            fi
            changed='f'
        fi
        read -r -t 0.25 -N 1 input || true # no input fails with non zero status
        if [[ ${input^^} = "P" ]]; then
            local pausedtime=$SECONDS
            pause_forever
            SECONDS=$pausedtime
        elif [[ ${input^^} == "A" ]]; then
            # TODO: change inputs to have a time limit too so that it doesn't hang here
            add_to_list
            changed='t'
        elif [[ ${input^^} == "D" ]]; then
            complete_task
            changed='t'
        elif [[ ${input^^} == "C" ]]; then
            cancel_task
            changed='t'
        elif [[ ${input^^} == "Q" ]]; then
            FORCE_QUIT_WORK_REST="true"
            break
        fi
    done
}


# Stops everything until p is pressed
pause_forever () {
    echo "PAUSED, press p to unpause"
    while true; do
        read -r -t 0.25 -N 1 input || true
        if [[ ${input^^} = 'P' ]]; then
            break
        fi
    done
    clear_line
}


# Countdowns to zero depending on whether working or resting
# Arguments:
#   time in minutes ($1)
work_or_rest () {
    task_continue=0
    local task_no=0
    while ((task_continue == 0)); do
        count_down "$1" "$task_no"
        chiming_with_input task_continue # task_continue is set in the called function
        task_no=$((task_no+1))
    done
}

# Plays notification until key is pressed
# Globals:
#   SECONDS
# Argumenets
# $1 variable to set to return type
# Returns
#   0 for True, 1 for False
chiming_with_input () {
    cat <<EOF
Press q to stop chiming and start next session
Press c to continue with rest/work
EOF
    echo ""
    SECONDS=0
    local should_continue
    should_continue=1

    if [[ $FORCE_QUIT_WORK_REST != "true" ]]; then
        while true; do
            notify $NOTIFICATION_TYPE
            read -r -t 1.0 -N 1 input || true
            input=${input:-R}
            duration=$SECONDS
            clear_line
            echo "Chiming duration: $((duration / 60)) min $((duration % 60)) sec"
            if [[ ${input^^} = "Q" ]]; then
                should_continue=1
                break
            fi
            if [[ ${input^^} = "C" ]]; then
                should_continue=0
                break
            fi
        done
    fi
    clear_line 3
    eval "$1=$should_continue" # set first parameter to have the return type
}

refresh_current_pomodoro_output () {
    local output=("")
    local non_color_last_line=""
    local columns=$(tput cols)

    for (( i=0; i < ${#TODO[@]}; i ++ )); do
        if [[ -v COMPLETED[$i] ]]; then
            local_output="$i: $green${TODO[i]}$clear"
        elif [[ -v ABANDONED[$i] ]]; then
            local_output="$i: $strikethrough${TODO[i]}$clear"
        else
            local_output="$i: ${TODO[i]}"
        fi
        local non_color_output="$non_color_last_line, $i: ${TODO[i]}"
        if [[ ${#non_color_output}+2 -gt $columns ]]; then # +2 since this is the number of spaces we indent with
            output+=("$local_output")
            non_color_last_line="$i: ${TODO[i]}"
        else
            if [[ ${output[-1]} == "" ]]; then
                output[-1]="$local_output"
            else
                output[-1]="${output[-1]}, $local_output"
            fi
            non_color_last_line="$non_color_output"
        fi
    done

    pomodoro_content=""
    for (( i=0; i<${#output[@]}; i++)) do
        pomodoro_content="$pomodoro_content  ${output[i]}\n" # 4spaces for indent
    done
    echo "$pomodoro_content"
}

add_to_list() {
    read -r -p "Additional Tasks: " tasks 
    if [[ -n $tasks ]]; then
        readarray -td',' temp_arr <<< "$tasks" # comma separated input
        TODO=(${TODO[@]} ${temp_arr[@]})
        strip_TODO_tasks
    fi
    clear_line 1
}

complete_task() { # rename to complete task
    read -r -p "Tasks no: " task_index
    if [[ -n $task_index ]]; then
        [[ ${COMPLETED["$task_index"]+Y} ]] && unset 'COMPLETED["$task_index"]' || COMPLETED["$task_index"]="DONE"
    fi
    clear_line 1
}

cancel_task() {
    read -r -p "Tasks no: " task_index
    if [[ -n $task_index ]]; then
        [[ ${ABANDONED["$task_index"]+Y} ]] && unset 'ABANDONED["$task_index"]' || ABANDONED["$task_index"]="ABANDONED"
    fi
    clear_line 1
}

# Runs one complete pomodoro i.e. with work and rest
# Globals:
#   WORK
#   REST
# Arguments:
#   n : The current pomodoro number
single_pomodoro_run () {
    if [[ $1 == 1 ]]; then
        echo "Plan is a list separated by a comma i.e. task1, task2, task3"
    fi
    echo "Pomodoro $1"
    read -r -p 'Plan: ' work
    clear_line
    echo -e "  Plan: $work"
    # passing in $work using <<<< adds a new line to the input, so we use substitution, see: https://unix.stackexchange.com/a/519917
    readarray -td',' TODO < <(printf "%s" "$work") # comma separated input
    strip_TODO_tasks
    local start_time
    start_time=$(date +%R)

    if [ $DISABLE_NOTIFICATIONS_WHILE_WORKING = 1 ]; then
        dunstctl set-paused true
    fi
    echo -e "  Working:"
    CURRENT_TASK="work"
    # TODO: confirm if removing quotes from $WORK fixes the counter problem
    work_or_rest $WORK

    # reset global values
    TODO=()
    COMPLETED=()
    ABANDONED=()

    local end_time
    end_time=$(date +%R)
    if [ $SHOULD_LOG = 1 ]; then
        log "$1" "$start_time - $end_time" "$LOG_DIR$FILENAME"
    fi

    if [ $DISABLE_NOTIFICATIONS_WHILE_WORKING = 1 ]; then
        dunstctl set-paused false
    fi
    echo -e "  Resting:"
    CURRENT_TASK="rest"
    work_or_rest $REST
}

rename_window_in_tmux () {
    in_tmux=${TMUX:-""}
    if [[ -n $in_tmux ]]; then
        tmux rename-window "pomodoro"
    fi
}

# Add work done to day's logs
# Globals:
#   LOG_DIR
# Arguments:
#   n - pomodoro number
#   t - time string ie. (starttime - endtime)
#   file_name
log () {
    log_filename="$LOG_DIR$FILENAME"
    mkdir -p "$LOG_DIR"
    touch "$log_filename"
    read -r -p 'Work done: ' work
    clear_line
    echo -e '  Work done: ' "$work"
    echo 'Pomodoro' "$1" "($2):" "$work" >> "$log_filename"
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
LOG_DIR="$HOME/.pomodoro/" # deprecated logs folder
SHOULD_LOG=1 # deprecated, whether to log what I've done, can be 0 or 1
NOTIFICATION_TYPE="sound" # can also be dunst
DISABLE_NOTIFICATIONS_WHILE_WORKING=1 # can be 0 or 1
EOF
}

# Deals with terminal options provided
# Globals:
#   WORK
#   REST
#   SECS_IN_MINUTE
#   LOG_DIF
#   SHOULD_LOG
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
                LOG_DIR=".logs/"
                shift
                ;;
            -h|--help)
                show_help
                exit 1
                ;;
            *)
                echo "Invalid option: $1" >&2
                show_help
                exit 1
                ;;
        esac
    done
}

main () {
    options "$@"
    rename_window_in_tmux
    echo "Starting pomodoro, work=$WORK and rest=$REST minutes"
    local pomodoro_count=1
    if [ -f "$LOG_DIR$FILENAME" ]; then
        mapfile -td' ' arr < <(tail -1 $LOG_DIR$FILENAME) # create array of words from last line in logs
        START=${arr[1]:-0} # second item is the latest pomodoro
        pomodoro_count=$((START+1))
    fi
    # infinite loop
    while true; do
        single_pomodoro_run $pomodoro_count
        pomodoro_count=$((pomodoro_count+1))
    done
}

main "$@"
