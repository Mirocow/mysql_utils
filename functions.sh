#!/bin/bash

check_connection()
{
    log "Checking MySQL connection..."
    mysql --defaults-file=$CONFIG_FILE -e ";" 2>/dev/null
    dbstatus=`echo $?`
    if [ $dbstatus -ne 0 ]; then
        log "Fail!"
        exit 1
    fi

    log "Success!"
    return 0
}

log()
{
    # local bold=$(tput bold)
    # local yellow=$(tput setf 6)
    # local red=$(tput setf 4)
    # local green=$(tput setf 2)
    # local reset=$(tput sgr0)
    # local toend=$(tput hpa $(tput cols))$(tput cub 6)

    logger "$@"

    if [ $VERBOSE -eq 1 ]; then
        echo "$@"
    fi
}

prepaire_skip_expression()
{
    local array_skip=( "${@}" )
    for skip in "${array_skip[@]}"; do
        if [ -x $return ]; then
            local return="^$skip\$"
        else
            return="$return|^$skip\$"
        fi
    done
    echo ${return}
}

check_connection()
{
    log "Checking MySQL connection..."
    mysql --defaults-file=$CONFIG_FILE -e exit 2>/dev/null
    dbstatus=`echo $?`
    if [ $dbstatus -ne 0 ]; then
        log "Fail!"
        exit 1
    fi

    log "Success!"
    return 0
}

database_exists()
{
    query="SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME = '$@'"
    RESULT=$(mysql --defaults-file=$CONFIG_FILE --skip-column-names -e "$query")
    if [ "$RESULT" == "$@" ]; then
        echo YES
    else
        echo NO
    fi
}

contains ()
{
    param=$1;
    shift;
    for elem in "$@";
    do
        [[ "$param" = "$elem" ]] && return 0;
    done;
    return 1
}

mutex() {
    local file=$1 pid pids

    exec 9>>"$file"
    { pids=$(fuser -f "$file"); } 2>&- 9>&-
    for pid in $pids; do
        [[ $pid = $$ ]] && continue

        exec 9>&-
        return 1 # Locked by a pid.
    done
}

lockfile()
{
    local lockfile="$1"
    mutex "${lockfile}" || { echo "Already running." >&2; exit 1; }
    trap "rm -rf ${lockfile}" QUIT INT TERM EXIT
}