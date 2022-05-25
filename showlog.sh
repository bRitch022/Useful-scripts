#!/bin/bash

# A POSIX variable to turn on options
OPTIND=1

# Initalize variables
user=""
follow=0
log_file="/var/log/auth.log"
#log_file="/var/log/alternatives.log"

show_help() {
    echo -e "Usage: showlog [OPTION]..."
    echo -e "\nOptional arguments"
    echo -e "-h \t see this help page"
    echo -e "-p \t persistent log following"
    echo -e "-f \t specify log file, default is $log_file"
    echo -e "-u \t focus on a specific user or target"

    echo -e "\nExamples:"
    echo -e "showlog -p -u root"
    echo -e "showlog -u root"
    echo -e "showlog -f /var/log/alternatives.log\n"
    exit 0

}

err() {
    echo "showlog: $*" >&2

}

while getopts "h?pu:f:" opt; do
    case "$opt" in
    h |/?)
        show_help
        exit 0
        ;;
    u) user=$OPTARG
        ;;
    p) persist=1
        ;;
    f) log_file=$OPTARG
        ;;
    :) echo "Option - "$OPTARG" requires an argument." >&2
        exit 1
        ;;
    esac

    shift $((OPTIND-1))

    if [ ! -f $log_file ]; then
        echo "showlog: cannot access '$log_file': No such file or directory"
        exit 1
    fi

    if [[ ! -z $user ]]; then
        if [[ $persist -eq 1 ]]; then
            echo "tail -f $log_file $user"
            tail -f $log_file | grep $user
            exit 0
        
        else
        echo "less $log_file $user"
            tail $log_file | grep $user
            exit 0
        fi

    elif [[ -z $user ]]; then
        if [[ $persist -eq 1 ]]; then
            echo "tail -f $log_file"
            tail -f $log_file
            exit 0
        else
            echo "less $log_file"
            tail $log_file
            exit 0
        fi
    fi

done
