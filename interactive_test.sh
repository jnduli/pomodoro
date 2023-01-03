#!/bin/bash
set -euo pipefail

# Plan:
# - [ ] add list of items separated by comma and list them as itemized
# - [ ] add extra items to this list
#

TODO_List=()
Done_Indices=(1 2)
# Set the color variable
green='\033[0;32m'
# Clear the color after that
clear='\033[0m'

# printf "The script was executed ${green}successfully${clear}!"

add_to_list() {
    # Demonstrates adding comma separated list to TODO List
    # and outputing done tasks in a different color
    # TODO: clean this up to make it more generic
    read -r -p "Plan: " tasks
    readarray -td', ' temp_arr <<< "$tasks"
    TODO_List=($TODO_List ${temp_arr[@]})
    local output=""
    for (( i=0; i < ${#TODO_List[@]}; i ++ )); do
        if [[ " ${Done_Indices[*]} " =~ " ${i} " ]]; then
            output="$output $i: $green${TODO_List[i]}$clear, "
        else
            output="$output $i: ${TODO_List[i]}, "
        fi
    done
    echo -e "$output"
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

