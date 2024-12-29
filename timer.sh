# SECONDS=0
# echo "seconds"
# echo $SECONDS

readonly SOUNDFILE='alarm.oga'

notify () {
    echo "Press q to stop sound"
    while true; do
        paplay $SOUNDFILE
        read -r -t 1.0 -N 1 input || true
        if [[ ${input^^} == "Q" ]]; then
            break
        fi
    done
}

show_help () {
    cat <<EOF
Copyright (C) 2022: John Nduli K.

timer.sh 
starts a timer from the terminal, ringing after time is done.

-t 5s/5m: sleep for 5 seconds/5minutes
-h: Show help
times: times passed to sleep
EOF
}

options () {
    while getopts "t:h" OPTION; do
        case $OPTION in
            h)  show_help
                exit 1
                ;;
            t) echo "Timer set for $OPTARG" && sleep $OPTARG && notify
                exit 1
                ;;
            \?) echo "Invalid option: -$OPTARG" >&2
                exit 1
                ;;
        esac
    done
}



options "$@"



# timer_seconds() {
#     echo "$@"
#     local seconds=$1
#     SECONDS=0

#     while [[ SECONDS -lt seconds ]]; do
#         echo "seconds passed: $SECONDS"
#         sleep 1s
#     done

#     echo "done counting"
# }

# timer_seconds 300
