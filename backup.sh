#!/bin/bash

# === FUNCTION ===
f_log() {
    logger "BACKUP: $@"

    if [ $VERBOSE -eq 1 ]; then
        echo "BACKUP: $@"
    fi
}

usage()
{
    cat << EOF

This mysql backup engine.

Usage:  $0 <[options]>

Options:
   -e= | --exclude=                     Exclude databases
   -c= | --compress=                    Compress with gzip or bzip2
   -v  | --verbose                      Add verbose into output
   -l  | --lifetime=                    Lifetime for dump files
   --config=                            Config file of Debian format
   --dir=                               Backup directory
   -h  | --help                         This text

Example:
        backup.sh --verbose --compress=
        backup.sh --verbose --compress=zgip
        backup.sh --verbose --compress=bzip2
        backup.sh --verbose --compress= --exclude="mysql"
        backup.sh --verbose --compress= --exclude="mysql" --lifetime="3 day ago"
        backup.sh --verbose --config="/etc/mysql/debian.cnf" --exclude="mysql" --lifetime="1 day ago"
        backup.sh --verbose --dir="/var/backups/mysql" --config="/etc/mysql/debian.cnf" --exclude="mysql" --lifetime="1 day ago"
        backup.sh --verbose --dir="/home/backups/mysql" --exclude="mysql" --lifetime="1 day ago"
EOF
}

prepaire_skip_expression()
{
    local array_skip=("${@}")
    for skip in "${array_skip[@]}"; do
        if [ -x $return ]; then
            local return="^$skip\$"
        else
            return="$return|^$skip\$"
        fi
    done
    echo ${return}
}

backup()
{
    f_log " START "

    query="SHOW databases;"

    local default_databases_exclude=(
        'information_schema'
        'performance_schema'
    )

    local array_views=()

    database_exclude=( ${default_databases_exclude[@]} ${EXCLUDE_DATABASES[@]} )
    database_exclude_expression=`prepaire_skip_expression "${database_exclude[@]}"`
    f_log "Skip databases: $database_exclude_expression"

    for BDD in $(mysql --defaults-extra-file=$CONFIG_FILE --skip-column-names -B -e "$query" | egrep -v "$database_exclude_expression"); do

        mkdir -p $DST/$BDD 2>/dev/null 1>&2
        chown mysql:mysql $DST/$BDD

        query="SHOW CREATE DATABASE \`$BDD\`;"
        mysql --defaults-extra-file=$CONFIG_FILE --skip-column-names -B -e "$query" | awk -F"\t" '{ print $2 }' > $DST/$BDD/__create.sql
        if [ -f $DST/$BDD/__create.sql ]; then
            f_log "  > Export create"
        fi

        query="SHOW FULL TABLES WHERE Table_type = 'VIEW';"
        for viewName in $(mysql --defaults-extra-file=$CONFIG_FILE $BDD -N -e "$query" | sed 's/|//' | awk '{print $1}'); do
            mysqldump --defaults-file=$CONFIG_FILE $BDD $viewName >> $DST/$BDD/__views.sql
            array_views+=($viewName)
        done
        if [ -f $DST/$BDD/__views.sql ]; then
            f_log "  > Exports views"
        fi

        mysqldump --defaults-file=$CONFIG_FILE --routines --no-create-info --no-data --no-create-db --skip-opt $BDD | sed -e 's/DEFINER=[^*]*\*/\*/' > $DST/$BDD/__routines.sql
        if [ -f $DST/$BDD/__routines.sql ]; then
            f_log "  > Exports Routines"
        fi

        local default_tables_exclude=(
            'slow_log'
            'general_log'
        )

        tables_exclude=( ${default_tables_exclude[@]} ${array_views[@]} )
        views_exclude_expression=`prepaire_skip_expression "${tables_exclude[@]}"`
        f_log "  - Exclude views: $views_exclude_expression"

        query="SHOW TABLES;"
        for TABLE in $(mysql --defaults-extra-file=$CONFIG_FILE --skip-column-names -B $BDD -e "$query" | egrep -v "$views_exclude_expression"); do
            f_log "  ** Dump $BDD.$TABLE"

            mysqldump --defaults-file=$CONFIG_FILE -T $DST/$BDD/ $BDD $TABLE

            if [ -f "$DST/$BDD/$TABLE.sql" ]; then
                chmod 750 $DST/$BDD/$TABLE.sql
                chown root:root $DST/$BDD/$TABLE.sql
                f_log "  ** set perm on $BDD/$TABLE.sql"
            else
                f_log "  ** WARNING : $DST/$BDD/$TABLE.sql not found"
            fi

            if [ -f "$DST/$BDD/$TABLE.txt" ]; then

                if [ $COMPRESS ]; then

                    f_log "  ** $COMPRESS $BDD/$TABLE.txt in background"

                    if [ -f "$DST/$BDD/$TABLE.txt.bz2" ]; then
                        rm $DST/$BDD/$TABLE.txt.bz2
                    fi

                    if [ -f "$DST/$BDD/$TABLE.txt.gz" ]; then
                        rm $DST/$BDD/$TABLE.txt.gz
                    fi

                    $COMPRESS $DST/$BDD/$TABLE.txt &

                fi

            else
                f_log "  ** WARNING : $DST/$BDD/$TABLE.txt not found"
            fi

        done

    done

    f_log " END "
}

if [ $# = 0 ]; then
    usage;
    exit;
fi

VERBOSE=0
COMPRESS='bzip2'
EXCLUDE_DATABASES=''
TIME_REMOVED_DUMP_FILES='1 week ago'
BACKUP_DIR='/var/backups/mysql'
CONFIG_FILE='/etc/mysql/debian.cnf'
BIN_DEPS="mysql mysqldump $COMPRESS"

# === CHECKS ===
for BIN in $BIN_DEPS; do
    which $BIN 1>/dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "Error: Required commad file not be found: $BIN"
        exit 1
    fi
done

for i in "$@"
do
    case $i in
        -e=* | --exclude=*)
            EXCLUDE_DATABASES=( "${i#*=}" )
            shift # past argument=value
        ;;
        -c=* | --compress=*)
            COMPRESS=( "${i#*=}" )
            shift # past argument=value
        ;;
        -l=* | --lifetime=*)
            TIME_REMOVED_DUMP_FILES=( "${i#*=}" )
            shift # past argument=value
        ;;
        --dir=*)
            BACKUP_DIR=( "${i#*=}" )
            shift # past argument=value
        ;;
        --config=*)
            CONFIG_FILE=( "${i#*=}" )
            shift # past argument=value
        ;;
        -v | --verbose)
            VERBOSE=1
            shift # past argument=value
        ;;
        -h | --help)
            usage
            exit
        ;;
        *)
        # unknown option
        ;;
    esac
done

DATE=`date '+%Y.%m.%d'`
DATEOLD=`date --date="$TIME_REMOVED_DUMP_FILES" +%Y.%m.%d`
DST=$BACKUP_DIR/$DATE
DSTOLD=$BACKUP_DIR/$DATEOLD

if [ ! -d "$DST" ]; then
    mkdir -p $DST;
fi

if [ -d "$DSTOLD" ]; then
    rm -fr $DSTOLD;
fi

# === SETTINGS ===
f_log "============================================"
f_log "Dump into: $BACKUP_DIR"
f_log "Config file: $CONFIG_FILE"
f_log "Verbose: $VERBOSE"
f_log "Compress: $COMPRESS"
f_log "Exclude: $DATABASES_SKIP"
f_log "Life time: $TIME_REMOVED_DUMP_FILES"
f_log "============================================"
f_log ""

# === AUTORUN ===
backup
