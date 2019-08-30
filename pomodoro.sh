#!/bin/bash

SOUNDFILE='/usr/share/sounds/freedesktop/stereo/complete.oga'

WORK=25
REST=5
SLEEP=1m

play_notification () {
    paplay $SOUNDFILE
}

clear_line () {
    printf "\033[1A"  # move cursor one line up
    printf "\033[K"   # delete till end of line
}

count_down () { 
    # Takes to parameters
    # $1 is time
    # $2 is messages to prepend
    echo "$2 0 minutes"
    for i in $(eval echo "{1..$1}")
    do
        sleep $SLEEP
        clear_line
        echo "$2 $i minutes"
    done
}

count_down_with_pause () {
    # Takes to parameters
    # $1 is time in minutes
    # $2 is messages to prepend
    secs_to_count_down=$(($1*60))
    SECONDS=0 
    PRINTED_MINUTES=0
    echo "$2 0 minutes"
    while (( SECONDS <= secs_to_count_down )); do    # Loop until interval has elapsed.
        minutes=$((SECONDS/60))
        if [[ $PRINTED_MINUTES != $minutes ]];then
            PRINTED_MINUTES=$minutes
            clear_line
            echo "$2 $PRINTED_MINUTES minutes"
        fi
        read -t 0.25 -N 1 input
        if [[ $input = 'p' || $input = 'P' ]];then
            PAUSEDTIME=$SECONDS
            pause_forever
            SECONDS=$PAUSEDTIME
        fi
    done
}

pause_forever () {
    echo "PAUSED, press p to unpause"
    while true
    do
        read -t 0.25 -N 1 input
        if [[ $input = 'p' || $input = 'P' ]];then
            break
        fi
    done
    clear_line
}

work () {
    count_down $WORK "Time spend:"
}

rest () {
    count_down $REST "Rested for"
}

chiming_with_input () {
    echo "Press q to stop chiming, and start break"
    echo ""
    SECONDS=0
    while true
    do
        play_notification
        read -t 0.25 -N 1 input
        duration=$SECONDS
        clear_line
        echo "Chiming duration: $(($duration / 60)) min $(($duration % 60)) sec"
        if [[ $input = "q" ]] || [[ $input = "Q" ]]; then
            echo
            break
        fi
    done
    clear_line
}
single_pomodoro_run () {
    echo "Starting pomodoro $1"
    work
    chiming_with_input
    rest
    chiming_with_input
}

show_help () {
    echo "pomodoro: "
    echo " -h: Show this help file"
    echo " -p <arg>: Set time for actual work"
    echo " -r <arg>: Set time for rest"
}

rename_window_in_tmux () {
    if [[ -n $TMUX ]]; then
        tmux rename-window "pomodoro"
    fi
}
options () {
    while getopts ":p:r:h" OPTION; do
        case $OPTION in
            p)
                WORK=$OPTARG
                ;;
            r)
                REST=$OPTARG
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

options "$@"
rename_window_in_tmux
count_down_with_pause 5 "THIS IS:"
# Infinite loop
# START=1
# while true
# do
    # single_pomodoro_run $START
    # START=$((START+1))
    # clear_line
    # clear_line
    # clear_line
    # clear_line
    # clear_line
# done
