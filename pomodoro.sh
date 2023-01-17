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
        printf "\r" # go to the beginning of the line
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
    #
    
    local secs_to_count_down=$(($1*SECS_IN_MINUTE))
    local printed_minutes=0
    local changed='f'
    local pomodoro_lines=0
    if [[ $CURRENT_TASK = "work" ]]; then
        pomodoro=$(refresh_current_pomodoro_output)
        pomodoro_lines=$(echo -en "$pomodoro" | wc -l)
        printf "%b\t\ta-add task, d-complete task, c-cancel task Time spend %s minutes\n" "$pomodoro" "$printed_minutes"
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
        minutes=$((SECONDS/SECS_IN_MINUTE))
        if [[ $changed == 't' || $printed_minutes != "$minutes" ]]; then # updates screen after every minute, preventing stuttering
            printed_minutes=$minutes
            clear_line $(( pomodoro_lines + 1 ))
            pomodoro=$(refresh_current_pomodoro_output)
            if [[ $CURRENT_TASK == "work" ]]; then
                pomodoro_lines=$(echo -en "$pomodoro" | wc -l)
                printf "%b\t\ta-add task, d-complete task, c-cancel task Time spend %s minutes\n" "$pomodoro" "$printed_minutes"
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
#
STATIC_OUTPUT=""
DYNAMIC_OUTPUT=""

refresh_screen() {
    # I'm having a hard time figuring out how to manage the output of single pomodoros even when the screen changes
    # so I'll maintain a global list of what needs to change and add to it as pomodoros complete
    # I'll then use this to refresh the whole screen and call this on each action I get and work on
    tput clear # clear the whole screen
    printf "%b" "$STATIC_OUTPUT"
    printf "%b" "$DYNAMIC_OUTPUT"
}


refresh_current_pomodoro_output () {
    # set -x
    local prefix_chars=8 # assume 4 spaces for tabs
    local output=("") # assume four spaces for tabs
    local non_color_last_line=""

    for (( i=0; i < ${#TODO[@]}; i ++ )); do
        if [[ -v COMPLETED[$i] ]]; then
            local_output="$i: $green${TODO[i]}$clear"
        elif [[ -v ABANDONED[$i] ]]; then
            local_output="$i: $strikethrough${TODO[i]}$clear"
        else
            local_output="$i: ${TODO[i]}"
        fi
        local non_color_output="$non_color_last_line $i: ${TODO[i]}, "
        if [[ ${#non_color_output}+$prefix_chars+4 -gt $COLUMNS ]]; then
            output+=("$local_output, ")
            non_color_last_line="$i: ${TODO[i]}, "
        else
            local potential_output="${output[-1]} $local_output, "
            output[-1]=$potential_output
            non_color_last_line="$non_color_output"
        fi
    done

    pomodoro_content=""
    for (( i=0; i<${#output[@]}; i++)) do
        pomodoro_content="$pomodoro_content    ${output[i]}\n" # 4spaces for indent
    done
    echo "$pomodoro_content"
    # set +x
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
    echo -e "\tStarting work:\n"
    CURRENT_TASK="work"
    work_or_rest "$WORK"

    # add to STATIC CONTENT before we reset values
    # TODO: figure out if I want to add rest to this static output too
    pomodoro_content=$(refresh_current_pomodoro_output)
    STATIC_OUTPUT=$(printf "%b\nPomodoro %d\n%b" "$STATIC_OUTPUT" "$1" "$pomodoro_content")

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
    STATIC_OUTPUT=$(echo "Starting pomodoro, work=$WORK and rest=$REST minutes")
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
