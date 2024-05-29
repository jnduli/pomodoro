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

# can be: work, rest, chime, pause
POMODORO_STATE="work"
PREVIOUS_POMODORO_STATE="rest"

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
    local task_no=$2
    local content
    content=$(view_content)
    pomodoro_lines=$(echo -en "$content" | wc -l)
    if [[ $task_no -gt 0 ]]; then
        clear_line $(( pomodoro_lines + 1 ))
    else
        SECONDS=0 
    fi
    secs_to_count_down=$(((task_no+1)*$1*SECS_IN_MINUTE))
    printf "%b Time spent is %s minutes\n" "$content" "$printed_minutes"
    while (( SECONDS <= secs_to_count_down )); do    # Loop until interval has elapsed.
        minutes=$(( SECONDS/SECS_IN_MINUTE ))
        if [[ ${changed^^} == 'T' || $printed_minutes != "$minutes" ]]; then # updates screen after every minute, preventing stuttering
            printed_minutes=$minutes
            # +1 because this is the contents of the pomodoro and the context line with time spent
            clear_line $(( pomodoro_lines + 1 ))
            content=$(view_content)
            pomodoro_lines=$(echo -en "$content" | wc -l)
            printf "%b Time spent is %s minutes\n" "$content" "$printed_minutes"
            changed='f'
        fi
        handle_countdown_input
        if [[ $FORCE_QUIT_WORK_REST = "true" ]]; then
            break
        fi
    done
}

view_content () {
    local content=""
    if [[ $POMODORO_STATE = "work" ]]; then
        pomodoro=$(refresh_current_pomodoro_output)
        pomodoro_lines=$(echo -en "$pomodoro" | wc -l)
        content=$(printf "%b  a-add task, d-do/undo task, c-cancel/uncancel task." "$pomodoro")
    elif [[ $POMODORO_STATE = "rest" ]]; then 
        pomodoro_lines=0
        content=$(printf "Resting: q-quit %s, , c-continue %s: " "$POMODORO_STATE" "$POMODORO_STATE") 
    elif [[ $POMODORO_STATE == "pause" ]]; then
        content="Paused: p to unpause"
    elif [[ $POMODORO_STATE == "chime" ]]; then
        content="Chiming: q-stop chiming, c-continue with previous state"
    fi
    echo "$content"
}

handle_countdown_input () {
    read -r -t 0.25 -N 1 input || true # no input fails with non zero status
    if [[ $POMODORO_STATE == "pause" ]]; then
        if [[ ${input^^} = 'P' ]]; then
            POMODORO_STATE=$PREVIOUS_POMODORO_STATE
        fi
    elif [[ $POMODORO_STATE == "chime" ]]; then
        # Q stops chiming and moves to next state
        # C stops chiming and continues previous state
        next_state=$PREVIOUS_POMODORO_STATE
        if [[ $PREVIOUS_POMODORO_STATE == "work" ]]; then
            next_state="rest"
        else
            next_state="work"
        fi

        if [[ ${input^^} = "Q" ]]; then
            POMODORO_STATE=$next_state
        elif [[ ${input^^} = "C" ]]; then
            POMODORO_STATE=$PREVIOUS_POMODORO_STATE
        fi

    else
        # Rest and work related inputs
        if [[ ${input^^} = "P" ]]; then
            local pausedtime=$SECONDS
            PREVIOUS_POMODORO_STATE=$POMODORO_STATE
            POMODORO_STATE="pause"
            pause_forever
            SECONDS=$pausedtime
        elif [[ ${input^^} == "Q" ]]; then
            FORCE_QUIT_WORK_REST="true"
        fi

        # Work related inputs
        if [[ ${input^^} == "A" && $POMODORO_STATE == "work" ]]; then
            # TODO: change inputs to have a time limit too so that it doesn't hang here
            add_to_list
            changed='t'
        elif [[ ${input^^} == "D" && $POMODORO_STATE == "work" ]]; then
            complete_task
            changed='t'
        elif [[ ${input^^} == "C" && $POMODORO_STATE == "work" ]]; then
            cancel_task
            changed='t'
        fi

    fi
}


pause_forever () {
    pause_instructions=$(view_content)
    pomodoro_lines=$(echo -en "$pause_instructions" | wc -l)
    printf "%b\n" "$pause_instructions"
    while [[ $POMODORO_STATE == "pause" ]]; do
        handle_countdown_input
    done
    clear_line $(( pomodoro_lines + 1))
}


# Countdowns to zero depending on whether working or resting
# Arguments:
#   time in minutes ($1)
work_or_rest () {
    local task_no=0
    local current_state=$POMODORO_STATE
    while [[ $POMODORO_STATE == "$current_state" ]]; do
        count_down "$1" "$task_no"
        PREVIOUS_POMODORO_STATE=$POMODORO_STATE
        POMODORO_STATE="chime"
        chiming_with_input
        task_no=$(( task_no + 1))
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
    chiming_instructions=$(view_content)
    pomodoro_lines=$(echo -en "$chiming_instructions" | wc -l)
    printf "%b\n" "$chiming_instructions"
    SECONDS=0

    if [[ $FORCE_QUIT_WORK_REST != "true" ]]; then
        while [[ $POMODORO_STATE == "chime" ]]; do
            notify $NOTIFICATION_TYPE
            duration=$SECONDS
            echo "Chiming duration: $((duration / 60)) min $((duration % 60)) sec"
            handle_countdown_input
            clear_line
        done
    fi
    clear_line "$(( pomodoro_lines + 1 ))"
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
    read -r -p "Add Tasks: " tasks 
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

# Arguments:
#   n : The current pomodoro number
single_pomodoro_run () {
    if [[ $1 == 1 ]]; then
        echo "Plan is a list separated by a comma i.e. task1, task2, task3"
    fi
    echo "Pomodoro $1"
    add_to_list
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
    in_tmux=${TMUX:-""}
    if [[ -n $in_tmux ]]; then
        tmux rename-window "pomodoro"
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
    # infinite loop
    while true; do
        single_pomodoro_run $pomodoro_count
        pomodoro_count=$((pomodoro_count+1))
    done
}

main "$@"
