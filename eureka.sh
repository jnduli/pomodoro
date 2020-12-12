#!/bin/bash

show_help() {
    cat <<EOF
Eureka v0.0.1 stores ideas I get on the fly

Requirements: sqlite3

Options are:
-v --version: show version
-h --help: show this help text
-a --add: add an idea
-v --view: view ideas
EOF
}


SOFTWARE_REQUIREMENTS=(git sqlite3)
SQLITE_DBASE="$HOME/projects/pomodoro/eureka.db"


# Check if software requirements defined in SOFTWARE_REQUIREMENTS array are installed
# If any is not installed, the whole program will exit
check_requirements_met() {
    requirement_not_found=0
    for requirement in "${SOFTWARE_REQUIREMENTS[@]}"
    do
        if ! [ -x "$(command -v "$requirement")" ]; then
            echo "Error: ${requirement} is not installed" >&2
            requirement_not_found=1
        fi
    done

    if [ $requirement_not_found == 1 ]; then
        exit 1
    fi
}


create_sqlite_table() {
    TABLE_QUERY="CREATE TABLE IF NOT EXISTS eureka (id INTEGER PRIMARY KEY, created_utc DATETIME DEFAULT (DATETIME('now')), modified_utc DATETIME DEFAULT (DATETIME('now')), summary TEXT, description TEXT)"
    sqlite3 "$SQLITE_DBASE" "$TABLE_QUERY"
}

add_idea() {
    # Process Flow
    echo "Summary of Idea"
    read -r idea_summary
    echo "Details of Idea"
    read -r idea_details
    INSERT_QUERY="INSERT INTO eureka (summary, description) VALUES (\"$idea_summary\", \"$idea_details\")"
    sqlite3 "$SQLITE_DBASE" "$INSERT_QUERY"
}

view_ideas() {
    SELECT_QUERY="SELECT * from eureka ORDER BY created_utc DESC"
    sqlite3 -header -column "$SQLITE_DBASE" "$SELECT_QUERY" | $PAGER
}

options_handling() {
    for i in "$@"
    do
        case $i in
            -h | --help) show_help; return;;
            -a | --add) add_idea; return;;
            -v | --view) view_ideas; return;;
            *) show_help; return ;;
        esac
    done
    # by default show_help
    show_help
}

check_requirements_met
create_sqlite_table
options_handling "$@"
