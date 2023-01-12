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

readonly VERSION='0.1'
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
# Set the color variable
green='\033[0;32m' # green for done tasks
strikethrough='\033[0;9m' # strike through abandoned tasks
clear='\033[0m' # clear formatting



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
        lines=$lines-1
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
    
    local secs_to_count_down=$(($1*SECS_IN_MINUTE))
    local printed_minutes=0

    changed='f'
    pomodoro=$(refresh_current_pomodoro_output)
    printf "\t%b\n\t\tTime spend %s minutes\n" "$pomodoro" "$printed_minutes"

    SECONDS=0 
    if [ -n "$2" ]; then
        SECONDS=$(($1*SECS_IN_MINUTE*$2))
        secs_to_count_down=$((($2+1)*$1*SECS_IN_MINUTE))
    fi
    while (( SECONDS <= secs_to_count_down )); do    # Loop until interval has elapsed.
        minutes=$((SECONDS/SECS_IN_MINUTE))
        if [[ $changed == 't' || $printed_minutes != "$minutes" ]]; then # updates screen after every minute, preventing stuttering
            printed_minutes=$minutes
            clear_line 2
            pomodoro=$(refresh_current_pomodoro_output)
            printf "\t%b\n\t\tTime spend %s minutes\n" "$pomodoro" "$printed_minutes"
            changed='f'
            # echo -e "\t\tTime spent $printed_minutes minutes"
        fi
        read -r -t 0.25 -N 1 input || true # no input fails with non zero status
        if [[ ${input^^} = "P" ]]; then
            local pausedtime=$SECONDS
            pause_forever
            SECONDS=$pausedtime
        elif [[ ${input^^} == "A" ]]; then
            local pausedtime=$SECONDS
            add_to_list
            changed='t'
            SECONDS=$pausedtime
        elif [[ ${input^^} == "D" ]]; then
            local pausedtime=$SECONDS
            complete_task
            changed='t'
            SECONDS=$pausedtime
        elif [[ ${input^^} == "C" ]]; then
            local pausedtime=$SECONDS
            cancel_task
            changed='t'
            SECONDS=$pausedtime
        elif [[ ${input^^} == "Q" ]]; then
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
    clear_line 3
    eval "$1=$should_continue" # set first parameter to have the return type
}

############################################
# TODO: adding better output 
# ###########################################

refresh_current_pomodoro_output () {
    local output=""

    for (( i=0; i < ${#TODO[@]}; i ++ )); do
        if [[ -v COMPLETED[$i] ]]; then
            output="$output $i: $green${TODO[i]}$clear, "
        elif [[ -v ABANDONED[$i] ]]; then
            output="$output $i: $strikethrough${TODO[i]}$clear, "
        else
            output="$output $i: ${TODO[i]}, "
        fi
    done
    echo "$output"
}

add_to_list() {
    read -r -p "Additional Tasks: " tasks 
    readarray -td', ' temp_arr <<< "$tasks" # comma separated input
    TODO=(${TODO[@]} ${temp_arr[@]})
    clear_line 1
}

complete_task() { # rename to complete task
    read -r -p "Tasks no: " task_no
    COMPLETED["$task_no"]="this"
    clear_line 1
}

cancel_task() {
    read -r -p "Tasks no: " task_no
    ABANDONED["$task_no"]="this"
    clear_line 1
}




######################################################
# TODO: Better output 
######################################################

# Runs one complete pomodoro i.e. with work and rest
# Globals:
#   WORK
#   REST
# Arguments:
#   n : The current pomodoro number
single_pomodoro_run () {
    echo "Pomodoro $1"
    read -r -p 'Plan: ' work
    clear_line
    echo -e "\tPlan: $work"
    # TODO: add relevant comment from this shttps://unix.stackexchange.com/a/519917
    readarray -td', ' TODO < <(printf "%s" "$work") # comma separated input
    local start_time
    start_time=$(date +%R)

    if [ $DISABLE_NOTIFICATIONS_WHILE_WORKING = 1 ]; then
        dunstctl set-paused true
    fi
    echo -e "\tStarting work:"
    CURRENT_TASK="work"
    work_or_rest $WORK

    # reset global values
    TODO=()
    declare -gA COMPLETED
    declare -gA ABANDONED

    local end_time
    end_time=$(date +%R)
    if [ $SHOULD_LOG = 1 ]; then
        log "$1" "$start_time - $end_time" "$LOG_DIR$FILENAME"
    fi

    if [ $DISABLE_NOTIFICATIONS_WHILE_WORKING = 1 ]; then
        dunstctl set-paused false
    fi
    echo -e "\tStarting rest:"
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
    echo -e '\tWork done: ' "$work"
    echo 'Pomodoro' "$1" "($2):" "$work" >> "$log_filename"
}

show_help () {
    cat <<EOF
Copyright (C) 2019: John Nduli K.                                                                                                      
pomodoro.sh version $VERSION:
 This runs pomodoro from your terminal
 During a count down, you can press p to pause/unpause the program
 You can also press q to quit the program

 Customization can be done by setting up these variables in a ~/.config/pomodoro/config file:
 WORK, REST, LOG_DIR, SHOULD_LOG, NOTIFICATION_TYPE, DISABLE_NOTIFICATIONS_WHILE_WORKING

 -h: Show help file
 -w <arg>: Set time for actual work
 -p <arg>: Set time for actual work (Same as -w)
 -r <arg>: Set time for rest
 -l: Daily retrospection (Show work done during the day)
 -q: quiet (notify does not play sound)
 -d: debug mode (The time counter uses seconds instead of minutes)
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
    while getopts "w:p:r:dlhq" OPTION; do
        case $OPTION in
            w) WORK=$OPTARG ;;
            p) WORK=$OPTARG ;;
            r) REST=$OPTARG ;;
            d) # debug mode options
                SECS_IN_MINUTE=1
                LOG_DIR=".logs/"
                ;;
            l) cat "$LOG_DIR$FILENAME" # view daily logs
               exit 1
               ;;
            h) show_help
               exit 1
               ;;
            q) NOTIFICATION_TYPE="dunst" ;;
            \?)
                echo "Invalid option: -$OPTARG" >&2
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
