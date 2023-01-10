#!/bin/bash

set -euo pipefail

# Plan:
# - [ ] add list of items separated by comma and list them as itemized
# - [ ] add extra items to this list
#

# Global variables
TODO_List=()
Done_Indices=()
Abandonded_indices=()

# Colors used in display
# Set the color variable
green='\033[0;32m' # green for done tasks
strikethrough='\033[0;9m' # strike through abandoned tasks
clear='\033[0m' # clear formatting

single_pomodoro_run () {
    echo "Pomodoro $1"
    read -r -p "Plan: " tasks 
    readarray -td', ' TODO_List <<< "$tasks" # comma separated input
    clear_line 1
    refresh_output

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
    echo -e "$output"
}

add_to_list() {
    read -r -p "Additional Tasks: " tasks 
    readarray -td', ' temp_arr <<< "$tasks" # comma separated input
    TODO_List=(${TODO_List[@]} ${temp_arr[@]})
    clear_line 1
    refresh_output
}

complete_task() { # rename to complete task
    read -r -p "Tasks no: " task_no
    Done_Indices=(${Done_Indices[@]} $task_no)
    echo "${Done_Indices[@]}"
    clear_line 1
    refresh_output
}

cancel_task() {
    read -r -p "Tasks no: " task_no
    Abandonded_indices=(${Abandonded_indices[@]} $task_no)
    clear_line 1
    refresh_output
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
        printf "\033[1A"  # move cursor one line up
        printf "\033[K"   # delete till end of line
        lines=$lines-1
    done
}

single_pomodoro_run 1
