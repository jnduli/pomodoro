#!/bin/bash

set -euo pipefail

# Plan:
# - [ ] add list of items separated by comma and list them as itemized
# - [ ] add extra items to this list
#

TODO_List=()
Done_Indices=(1 2)
Abandonded_indices=(3)
# Set the color variable
green='\033[0;32m'
# Clear the color after that
clear='\033[0m'

strikethrough='\033[0;9m'

# printf "The script was executed ${green}successfully${clear}!"

get_tasks_message () {
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

add_to_list() {
    # Demonstrates adding comma separated list to TODO List
    # and outputing done tasks in a different color
    # TODO: clean this up to make it more generic
    # read -r -p "Plan: " tasks
    # readarray -td', ' temp_arr <<< "$tasks"
    temp_arr=("this" "is" "noone" "good")
    TODO_List=(${TODO_List[@]} ${temp_arr[@]})
    message=$(get_tasks_message)
    echo -e "$message"
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

add_to_list
