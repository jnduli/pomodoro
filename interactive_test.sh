set -euo pipefail

Planned_List=("morning pages" "eat food" "make supper")
Done_List=()

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

output
clear_output
