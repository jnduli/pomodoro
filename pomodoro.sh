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
    for i in $(eval echo "{1..$WORK}")
    do
        echo "Time spent is $i minutes"
        sleep $SLEEP
        clear_line
    done
}

rest () {
    for i in $(eval echo "{1..$REST}")
    do
        echo "Rested for $i minutes"
        sleep $SLEEP
        clear_line
    done
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
    count_down
    chiming_with_input
    rest
    chiming_with_input
}

# Infinite loop
START=1
while true
do
    single_pomodoro_run $START
    START=$((START+1))
    clear_line
    clear_line
    clear_line
    clear_line
    clear_line
done
