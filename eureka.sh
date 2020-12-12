# Check if its a git repo
# check if one can commit by checking for user.name user.email
# default folder location for this
# using $EDITOR for editting
# using $PAGER to view the file
# Formatting of the markdown file too

GIT_REPO_DIRECTORY="$HOME/projects/ideas"

if ! [ -x "$(command -v git)" ]; then
  echo 'Error: git is not installed.' >&2
  exit 1
fi


# mkdir -p "$GIT_REPO_DIRECTORY"
# cd "$GIT_REPO_DIRECTORY" || exit

# # TODO: Better set up flow
# if ! [ -d .git ]; then
#     echo "Setting up"
#     echo "What's your email"
#     read -r email
#     echo "Whats your user name"
#     read -r username
#     git init
#     git config user.name "$username"
#     git config user.email "$email"
#     echo "#IDEAS" >> README.md
#     echo "Done setting up"
#     exit 1
# fi;


show_help() {
    cat <<EOF
Eureka v0.0.1 stores ideas I get on the fly

Options are:
-v --version: show version
-h --help: show this help text
-a --add: add an idea
-v --view: view ideas
EOF
}

add_idea() {
    # Process Flow
    echo "Summary of Idea"
    read -r idea_summary
    { echo "idea: $idea_summary"
    "notes: you can edit this or remove it if there are no notes"
    ""
    } >> README.md
    $EDITOR README.md
    git add README.md
    git commit -m "$idea_summary"
}

view_ideas() {
    $PAGER README.md
}

create_sqlite_table() {
    TABLE_QUERY="CREATE TABLE IF NOT EXISTS eureka (id INTEGER PRIMARY KEY, created_utc DATETIME DEFAULT (DATETIME('now')), modified_utc DATETIME DEFAULT (DATETIME('now')), summary TEXT, description TEXT)"
    sqlite3 eureka.db "$TABLE_QUERY"
}

add_sqlite_idea() {
    # Process Flow
    echo "Summary of Idea"
    read -r idea_summary
    echo "Details of Idea"
    read -r idea_details
    INSERT_QUERY="INSERT INTO eureka (summary, description) VALUES (\"$idea_summary\", \"$idea_details\")"
    sqlite3 eureka.db "$INSERT_QUERY"
}

view_sqlite_ideas() {
    SELECT_QUERY="SELECT * from eureka ORDER BY created_utc DESC"
    sqlite3 -header -column eureka.db "$SELECT_QUERY"
}

options_handling() {
    for i in "$@"
    do
        case $i in
            -h | --help) show_help; return;;
            -a | --add) add_sqlite_idea; return;;
            -v | --view) view_sqlite_ideas; return;;
            *) show_help; return ;;
        esac
    done
    # by default show_help
    show_help
}

create_sqlite_table
options_handling "$@"
