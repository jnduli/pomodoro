#!/bin/bash

set -euo pipefail

# Plan:
# - [ ] add list of items separated by comma and list them as itemized
# - [ ] add extra items to this list
#

# Global variables
# TODO_List=("this is really good", "them are really bad")
TODO_List=("this is really good", "them are really bad", "this is a really long sentence", "trying out more things", "another attempt this isnt really long enough though")

single_pomodoro_run () {
    echo "Pomodoro $1"
    tput sc
    while (( 1 > 0 )); do
        read -r -t 0.25 -N 1 input || true 
        if [[ ${input^^} == "A" ]]; then
            add_to_list
        elif [[ ${input^^} == "D" ]]; then
            complete_task
        elif [[ ${input^^} == "C" ]]; then
            cancel_task
        elif [[ ${input^^} == "Q" ]]; then
            break
        fi
        tput rc;tput ed # rc = restore cursor, el = erase to end of line
        # tput ed
        content=$(refresh_output)
        echo -e "$content"
    done

    # read -r -p 'Plan: ' work
    # echo -e '\tPlan: ' "$work"
    # local start_time
    # start_time=$(date +%R)

    # if [ $DISABLE_NOTIFICATIONS_WHILE_WORKING = 1 ]; then
    #     dunstctl set-paused true
    # fi
    # echo -e "\tStarting work:"
    # work_or_rest $WORK

    # local end_time
    # end_time=$(date +%R)
    # if [ $SHOULD_LOG = 1 ]; then
    #     log "$1" "$start_time - $end_time" "$LOG_DIR$FILENAME"
    # fi

    # if [ $DISABLE_NOTIFICATIONS_WHILE_WORKING = 1 ]; then
    #     dunstctl set-paused false
    # fi
    # echo -e "\tStarting rest:"
    # work_or_rest $REST
}

refresh_output () {
    local output=""
    for (( i=0; i < ${#TODO_List[@]}; i ++ )); do
        if [[ " ${Done_Indices[*]} " =~ " ${i} " ]]; then
            output="$output $i: $green${TODO_List[i]}$clear, "
        elif [[ " ${Abandonded_indices[*]} " =~ " ${i} " ]]; then
            output="$output $i: $strikethrough${TODO_List[i]}$clear, "
        else
            output="$output $i: ${TODO_List[i]}, "
        fi
    done
    echo "$output"
}


output() {
    printf "%s\n%s\n%s\n" "this" "that" "those"
}

clear_output() {
    clear_line 3
}


clear_line () {
    local lines=${1:-1} # defaults to 1
    while (( lines > 0 )); do 
        printf '\r' # go to beginning of line
        printf "\033[1A"  # move cursor one line up
        # printf "\r"
        printf "\033[K"   # delete till end of line
        lines=$lines-1
    done
}

# Clears the entire current line regardless of terminal size.
# See the magic by running:
# { sleep 1; clear_this_line ; }&
clear_this_line(){
        printf '\r'
        cols="$(tput cols)"
        for i in $(seq "$cols"); do
                printf ' '
        done
        printf '\r'
}

# Erases the amount of lines specified.
# Usage: erase_lines [AMOUNT]
# See the magic by running:
# { sleep 1; erase_lines 2; }&
erase_lines(){
        # Default line count to 1.
        test -z "$1" && lines="1" || lines="$1"

        # This is what we use to move the cursor to previous lines.
        UP='\033[1A'

        # Exit if erase count is zero.
        [ "$lines" = 0 ] && return

        # Erase.
        if [ "$lines" = 1 ]; then
                clear_this_line
        else
                lines=$((lines-1))
                clear_this_line
                for i in $(seq "$lines"); do
                        printf "$UP"
                        clear_this_line
                done
        fi
}


single_pomodoro_run 1
# tput sc # save cursor
# printf "Something that I made up for this string that is really long and will span multiple lines to see how this pands out and hopw that it all goes graet fome me and the random things don't pand out for me"
# sleep 1
# tput rc;tput ed # rc = restore cursor, el = erase to end of line
# printf "Another message for testing"
# sleep 1
# tput rc;tput ed
# printf "Yet another one"
# sleep 1
# tput rc;tput ed
