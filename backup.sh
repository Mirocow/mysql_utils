#!/bin/bash

# === CONFIG ===
VERBOSE=0
COMPRESS='bzip2'
USER='mysql'
GROUP='mysql'
DIRECTORYATTRIBUTES=0770
FILEATTRIBUTES=640
TIME_REMOVED_DUMP_FILES='1 week ago'
DATABASE_DIR='/var/backups/mysql'
CONFIG_FILE='/etc/mysql/debian.cnf'
EXCLUDE_DATABASES=''
EXCLUDE_TABLES=''
EXCLUDE_DATA_TABLES=''
BIN_DEPS="mysql mysqldump $COMPRESS"

# === DO NOT EDIT BELOW THIS LINE ===

if [ ! -n "$BASH" ] ;then echo Please run this script $0 with bash; exit 1; fi

if [ -f '/etc/debian_version' ]; then
    CONFIG_FILE='/etc/mysql/debian.cnf'
else
    CONFIG_FILE='~/mysql_utils/etc/mysql/debian.cnf'
fi

# === FUNCTIONS ===
source $(dirname "$0")/functions.sh

backup()
{
    log "BACKUP: START "

    local default_databases_exclude=(
        'information_schema'
        'performance_schema'
    )

    local array_views=()

    database_exclude=( ${default_databases_exclude[@]} ${EXCLUDE_DATABASES[@]} )
    database_exclude_expression=`prepaire_skip_expression "${database_exclude[@]}"`

    log "BACKUP: Exclude databases: $database_exclude_expression"

    if [ ${#DATABASES[@]} -eq 0 ]; then
        query="SHOW databases;"
        DATABASES=$(mysql --defaults-file=$CONFIG_FILE --skip-column-names -B -e "$query" | egrep -v "$database_exclude_expression");
    fi

    for DATABASE in $DATABASES; do

        if ! database_exists "$DATABASE"; then
            log "BACKUP: Unknown database '$DATABASE'"
            continue
        fi

        lockfile "$DATABASE_DIR/$DATABASE/lockfile.lock"

        mkdir -p $DATABASE_DIR/$DATABASE 2>/dev/null 1>&2
        chown $USER:$GROUP $DATABASE_DIR/$DATABASE
        chmod $DIRECTORYATTRIBUTES $DATABASE_DIR/$DATABASE

        query="SHOW CREATE DATABASE \`$DATABASE\`;"
        mysql --defaults-file=$CONFIG_FILE --skip-column-names -B -e "$query" | awk -F"\t" '{ print $2 }' | sed 's/^CREATE DATABASE `/CREATE DATABASE IF NOT EXISTS `/' > $DATABASE_DIR/$DATABASE/__create.sql
        if [ -f $DATABASE_DIR/$DATABASE/__create.sql ]; then
            log "BACKUP: > Export create"
        fi

        local mysqlDumpVars="--single-transaction=TRUE"

        if mysqldump --column-statistics=0 --version &>/dev/null; then
            mysqlDumpVars="$mysqlDumpVars --column-statistics=0"
        fi

        query="SHOW FULL TABLES WHERE Table_type = 'VIEW';"
        for viewName in $(mysql --defaults-file=$CONFIG_FILE $DATABASE -N -e "$query" | sed 's/|//' | awk '{print $1}'); do
            mysqldump --defaults-file=$CONFIG_FILE $mysqlDumpVars $DATABASE $viewName | sed -e 's/DEFINER=[^*]*\*/\*/' >> $DATABASE_DIR/$DATABASE/__views.sql
            array_views+=($viewName)
        done
        if [ -f $DATABASE_DIR/$DATABASE/__views.sql ]; then
            log "BACKUP: > Exports views"
        fi

        mysqldump --defaults-file=$CONFIG_FILE $mysqlDumpVars --routines --skip-events --skip-triggers --no-create-info --no-data --no-create-db --skip-opt $DATABASE | sed -e 's/DEFINER=[^*]*\*/\*/' > $DATABASE_DIR/$DATABASE/__routines.sql
        if [ -f $DATABASE_DIR/$DATABASE/__routines.sql ]; then
            log "BACKUP: > Exporting Routines"
        fi

        mysqldump --defaults-file=$CONFIG_FILE $mysqlDumpVars --triggers --skip-events --skip-routines --no-create-info --no-data --no-create-db --skip-opt $DATABASE | sed -e 's/DEFINER=[^*]*\*/\*/' > $DATABASE_DIR/$DATABASE/__triggers.sql
        if [ -f $DATABASE_DIR/$DATABASE/__triggers.sql ]; then
            log "BACKUP: > Exporting Triggers"
        fi

        mysqldump --defaults-file=$CONFIG_FILE $mysqlDumpVars --events --skip-routines --skip-triggers --no-create-info --no-data --no-create-db --skip-opt $DATABASE | sed -e 's/DEFINER=[^*]*\*/\*/' > $DATABASE_DIR/$DATABASE/__events.sql
        if [ -f $DATABASE_DIR/$DATABASE/__events.sql ]; then
            log "BACKUP: > Exporting Events"
        fi

        local default_tables_exclude=(
            'slow_log'
            'general_log'
        )

        tables_exclude=( ${default_tables_exclude[@]} ${array_views[@]} ${EXCLUDE_TABLES[@]} )
        tables_exclude_expression=$(prepaire_skip_expression "${tables_exclude[@]}")
        log "BACKUP: Exclude tables: $tables_exclude_expression"

        data_tables_exclude=( ${EXCLUDE_DATA_TABLES[@]} )
        data_tables_exclude_expression=$(prepaire_skip_expression "${data_tables_exclude[@]}")
        log "BACKUP: Exclude data tables: $data_tables_exclude_expression"

        query="SHOW TABLES;"
        for TABLE in $(mysql --defaults-file=$CONFIG_FILE --skip-column-names -B $DATABASE -e "$query" | egrep -v "$tables_exclude_expression"); do

            log "BACKUP: ** Dump $DATABASE.$TABLE"

            if [ $(echo $data_tables_exclude_expression| grep $TABLE) ]; then
                log "BACKUP: Exclude data from table $TABLE"
                mysqldump --defaults-file=$CONFIG_FILE $mysqlDumpVars --no-data --add-drop-table --skip-events --skip-routines --skip-triggers --tab=$DATABASE_DIR/$DATABASE/ $DATABASE $TABLE
            else
                # If fields has geospatial types
                checkGeo="mysql --defaults-file=$CONFIG_FILE -B $DATABASE -e \"SHOW COLUMNS FROM $TABLE WHERE Type IN ('point', 'polygon', 'geometry', 'linestring')\""
                hasGeo=$(eval $checkGeo)
                if [ ! -z "$hasGeo" ]; then
                    mysqldump --defaults-file=$CONFIG_FILE $mysqlDumpVars --flush-logs --default-character-set=utf8 --add-drop-table --quick --skip-events --skip-routines --skip-triggers --result-file=$DATABASE_DIR/$DATABASE/$TABLE.sql $DATABASE $TABLE
                else
                    mysqldump --defaults-file=$CONFIG_FILE $mysqlDumpVars --flush-logs --default-character-set=utf8 --add-drop-table --quick --skip-events --skip-routines --skip-triggers --tab=$DATABASE_DIR/$DATABASE/ $DATABASE $TABLE
                fi
            fi

            sed 's/AUTO_INCREMENT=[0-9]*\b//' $DATABASE_DIR/$DATABASE/$TABLE.sql

            if [ -f "$DATABASE_DIR/$DATABASE/$TABLE.sql" ]; then
                chmod $FILEATTRIBUTES $DATABASE_DIR/$DATABASE/$TABLE.sql
                chown $USER:$GROUP $DATABASE_DIR/$DATABASE/$TABLE.sql
                log "BACKUP: ** set perm on $DATABASE/$TABLE.sql"
            else
                log "BACKUP: ** WARNING : $DATABASE_DIR/$DATABASE/$TABLE.sql not found"
            fi

            if [ -f "$DATABASE_DIR/$DATABASE/$TABLE.txt" ]; then

                if [ $COMPRESS ]; then

                    log "BACKUP: ** $COMPRESS $DATABASE/$TABLE.txt"

                    if [ $COMPRESS == 'bzip2' ]; then

                        if [ -f "$DATABASE_DIR/$DATABASE/$TABLE.txt.bz2" ]; then
                            rm $DATABASE_DIR/$DATABASE/$TABLE.txt.bz2
                        fi

                    ($COMPRESS $DATABASE_DIR/$DATABASE/$TABLE.txt && chmod $FILEATTRIBUTES $DATABASE_DIR/$DATABASE/$TABLE.txt.bz2 && chown $USER:$GROUP $DATABASE_DIR/$DATABASE/$TABLE.txt.bz2) &

                    elif [ $COMPRESS == 'gzip' ]; then

                        if [ -f "$DATABASE_DIR/$DATABASE/$TABLE.txt.gz" ]; then
                            rm $DATABASE_DIR/$DATABASE/$TABLE.txt.gz
                        fi

                    ($COMPRESS $DATABASE_DIR/$DATABASE/$TABLE.txt && chmod $FILEATTRIBUTES $DATABASE_DIR/$DATABASE/$TABLE.txt.gz && chown $USER:$GROUP $DATABASE_DIR/$DATABASE/$TABLE.txt.gz) &

                    fi

                fi

            else
                log "BACKUP: ** WARNING : $DATABASE_DIR/$DATABASE/$TABLE.txt not found"
            fi

        done

    done

    log "BACKUP: END "
}

usage()
{
    cat << EOF

        This mysql backup engine.

        Usage:  $0 <[options]> or bash $0 <[options]>

Options:
   -e= | --exclude=                     Exclude databases
   --exclude-tables=                    Exclude tables
   --exclude-data-tables=               Exclude data tables
   -c= | --compress=                    Compress with gzip or bzip2
   -v  | --verbose                      Add verbose into output
   -l  | --lifetime=                    Lifetime for dump files
   --config=                            Config file of Debian format
   --dir=                               Backup directory
   -h  | --help                         This text

Examples:
        backup.sh --verbose --compress=
        backup.sh --verbose --compress=gzip
        backup.sh --verbose --compress=bzip2
        backup.sh --verbose --compress= --include="mydb"
        backup.sh --verbose --compress= --exclude="mysql sys"
        backup.sh --verbose --compress= --exclude="mysql" --lifetime="3 day ago"
        backup.sh --verbose --config="/etc/mysql/debian.cnf" --exclude="mysql" --lifetime="1 day ago"
        backup.sh --verbose --dir="/var/backups/mysql" --config="/etc/mysql/debian.cnf" --exclude="mysql" --lifetime="1 day ago"
        backup.sh --verbose --dir="/home/backups/mysql" --exclude="mysql" --lifetime="1 day ago"
        backup.sh --verbose --dir="/home/backups/mysql" --exclude="mysql" --exclude-tables="tbl_template" --lifetime="1 day ago"


EOF
}

if [ $# = 0 ]; then
    usage;
    exit;
fi

# === CHECKS ===
for BIN in $BIN_DEPS; do
    which $BIN 1>/dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "Error: Required command file not be found: $BIN"
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
        -i=* | --include=*)
            DATABASES=( "${i#*=}" )
            shift # past argument=value
        ;;
        --exclude-tables=*)
            EXCLUDE_TABLES=( "${i#*=}" )
            shift # past argument=value
        ;;
        --exclude-data-tables=*)
            EXCLUDE_DATA_TABLES=( "${i#*=}" )
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
            DATABASE_DIR=( "${i#*=}" )
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
DATABASE_DIR=$DATABASE_DIR/$DATE
DSTOLD=$DATABASE_DIR/$DATEOLD

if check_connection; then
    if [ ! -d "$DATABASE_DIR" ]; then
        mkdir -p $DATABASE_DIR;
        chmod $DIRECTORYATTRIBUTES $DATABASE_DIR;
        chown $USER:$GROUP $DATABASE_DIR;
    fi

    if [ -d "$DSTOLD" ]; then
        rm -fr $DSTOLD;
    fi

    # === SETTINGS ===
    log "BACKUP: ============================================"
    log "BACKUP: Dump into: $DATABASE_DIR"
    log "BACKUP: Config file: $CONFIG_FILE"
    log "BACKUP: Verbose: $VERBOSE"
    log "BACKUP: Compress: $COMPRESS"
    log "BACKUP: Only include databases: $DATABASES"
    log "BACKUP: Exclude databases: $EXCLUDE_DATABASES"
    log "BACKUP: Exclude tables: $EXCLUDE_TABLES"
    log "BACKUP: Life time: $TIME_REMOVED_DUMP_FILES"
    log "BACKUP: ============================================"
    log "BACKUP: "

    # === AUTORUN ===
    backup
else
    log "Failed to establish a connection to the database"
fi
