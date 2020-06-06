#!/bin/bash
#
# Runs pomodoro with specified work duration and rest
#
# For countdown the SECONDS (see man bash) variable is used

scriptDir=$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")
cd "$scriptDir" || exit

readonly SOUNDFILE='alarm.oga'

WORK=25
REST=5
SECS_IN_MINUTE=60
LOG_DIR="$HOME/.pomodoro/"
FILENAME="$(date +"%F").log"
LOG_FILENAME="$LOG_DIR$FILENAME"

play_notification () {
    paplay $SOUNDFILE
}

# Deletes n lines and places cursor on previous line 
# Arguments
#   n (Optional, defaults to 1): No of lines to clear
# Returns
#   None
clear_line () {
    local lines=1
    if [ -n "$1" ]; then
        lines=$1
    fi
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
#   message ($2)
#   b (Optional $3): the number of times break has been avoided
count_down () {
    local secs_to_count_down=$(($1*SECS_IN_MINUTE))
    local message=$2
    local printed_minutes=0
    echo -e "$message $printed_minutes minutes"
    SECONDS=0 
    if [ -n "$3" ]; then
        SECONDS=$(($1*SECS_IN_MINUTE*$3))
        secs_to_count_down=$((($3+1)*$1*SECS_IN_MINUTE))
    fi
    while (( SECONDS <= secs_to_count_down )); do    # Loop until interval has elapsed.
        minutes=$((SECONDS/SECS_IN_MINUTE))
        if [[ $printed_minutes != "$minutes" ]]; then # stops stuttering of screen by second by second update
            printed_minutes=$minutes
            clear_line
            echo -e "$message $printed_minutes minutes"
        fi
        read -r -t 0.25 -N 1 input
        if [[ ${input^^} = "P" ]]; then
            local pausedtime=$SECONDS
            pause_forever
            SECONDS=$pausedtime
        elif [[ ${input^^} = "Q" ]]; then
            break
        fi
    done
}

# Stops everything until p is pressed
pause_forever () {
    echo "PAUSED, press p to unpause"
    while true; do
        read -r -t 0.25 -N 1 input
        if [[ ${input^^} = 'P' ]]; then
            break
        fi
    done
    clear_line
}

# Calls count_down with work time 
# Globals:
#   WORK
# Arguments:
#   b (Optional $1): the number of times break has been avoided
work () {
    if [ -n "$1" ]; then
        count_down $WORK "\tTime spent:" "$1"
    else
        count_down $WORK "\tTime spent:"
    fi
}

# Calls count_down with rest time 
# Globals:
#   REST
rest () {
    if [ -n "$1" ]; then
        count_down $REST "\tRested for:" "$1"
    else
        count_down $REST "\tRested for:"
    fi
}

# Plays notification until key is pressed
# Globals:
#   SECONDS
# Returns
#   0 for True, 1 for False
chiming_with_input () {
    cat <<EOF
Press q to stop chiming and start break
Press c to continue with task
EOF
    echo ""
    SECONDS=0
    local should_continue
    while true; do
        play_notification
        read -r -t 0.25 -N 1 input
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
    return $should_continue
}

# Runs one complete pomodoro i.e. with work and rest
# Arguments:
#   n : The current pomodoro number
single_pomodoro_run () {
    echo "Pomodoro $1"
    local start_time=$(date +%R)
    local work_continue=0
    local work_no=0
    while ((work_continue == 0)); do
        work $work_no
        chiming_with_input
        work_continue=$? # result from previous command
        work_no=$((work_no+1))
    done
    local end_time=$(date +%R)
    log "$1" "$start_time - $end_time"
    local rest_continue=0
    local rest_no=0
    while ((rest_continue == 0));do
        rest $rest_no
        chiming_with_input
        rest_continue=$?
        rest_no=$((rest_no+1))
    done
}

rename_window_in_tmux () {
    if [[ -n $TMUX ]]; then
        tmux rename-window "pomodoro"
    fi
}

# Show the current day's work
# Globals:
#   LOG_FILENAME
view_logs () {
    # show the day's logs when called
    # should add support to view other days logs
    cat "$LOG_FILENAME"
}

# Add work done to day's logs
# Globals:
#   LOG_DIR
#   LOG_FILENAME
# Arguments:
#   n - pomodoro number
#   t - time string ie. (starttime - endtime)
log () {
    mkdir -p "$LOG_DIR"
    touch "$LOG_FILENAME"
    read -r -p 'Work done: ' work
    clear_line
    echo -e '\tWork done: ' "$work"
    echo 'Pomodoro' "$1" "($2):" "$work" >> "$LOG_FILENAME"
}

show_help () {
    cat <<EOF
Copyright (C) 2019: John Nduli K.                                                                                                      
pomodoro.sh:
 This runs pomodoro from your terminal
 During a count down, you can press p to pause/unpause the program
 You can also press q to quit the program

 -h: Show help file
 -p <arg>: Set time for actual work
 -r <arg>: Set time for rest
 -l: Daily retrospection (Show work done during the day)
 -d: debug mode (The time counter uses seconds instead of minutes)
EOF
}

# Deals with terminal options provided
# Globals:
#   WORK
#   REST
#   SECS_IN_MINUTE
#   LOG_DIF
#   LOG_FILENAME
options () {
    while getopts "p:r:dlh" OPTION; do
        case $OPTION in
            p)
                WORK=$OPTARG
                ;;
            r)
                REST=$OPTARG
                ;;
            d)
                SECS_IN_MINUTE=1
                LOG_DIR=".logs/"
                LOG_FILENAME="$LOG_DIR$FILENAME"
                ;;
            l)
                view_logs
                exit 1
                ;;
            h)
                show_help
                exit 1
                ;;
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
    # infinite loop
    local pomodoro_count=1
    if [ -f "$LOG_FILENAME" ]; then
        arr=($(tail -1 $LOG_FILENAME)) # create an array of words from the last line
        START=${arr[1]} # second item is the latest pomodoro
        pomodoro_count=$((START+1))
    fi
    while true; do
        single_pomodoro_run $pomodoro_count
        pomodoro_count=$((pomodoro_count+1))
    done
}

main "$@"
