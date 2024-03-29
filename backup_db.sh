#!/bin/bash

VERBOSE=0
COMPRESS='bzip2'
USER='mysql'
GROUP='mysql'
DIRECTORYATTRIBUTES=0770
FILEATTRIBUTES=640
TIME_REMOVED_DUMP_FILES='1 week ago'
BACKUP_DIR='/var/backups/mysql'
CONFIG_FILE='/etc/mysql/debian.cnf'
DATABASE=''
TABLES=''
INCLUDE_TABLES=''
INCLUDE_DATA_TABLES=''
EXCLUDE_TABLES=''
EXCLUDE_DATA_TABLES=''
BIN_DEPS="mysql mysqldump $COMPRESS"

# === DO NOT EDIT BELOW THIS LINE ===

if [ ! -n "$BASH" ] ;then echo Please run this script $0 with bash; exit 1; fi

# === FUNCTIONS ===
source $(dirname "$0")/functions.sh

if [ -f '/etc/debian_version' ]; then
    CONFIG_FILE='/etc/mysql/debian.cnf'
else
    CONFIG_FILE='~/mysql_utils/etc/mysql/debian.cnf'
fi

backup()
{
    log " START "

    query="SHOW databases;"

    #
    # Inlude tables
    #

    local default_databases_include=(
    )

    local default_tables_include=(
    )

    #
    # Exclude tables
    #

    local default_databases_exclude=(
        'information_schema'
        'performance_schema'
    )

    local array_views=()
    lockfile "$DST/$DATABASE/lockfile.lock"

	mkdir -p $DST/$DATABASE 2>/dev/null 1>&2
	chown $USER:$GROUP $DST/$DATABASE
	chmod $DIRECTORYATTRIBUTES $DST/$DATABASE

	query="SHOW CREATE DATABASE \`$DATABASE\`;"
	mysql --defaults-file=$CONFIG_FILE --skip-column-names -B -e "$query" | awk -F"\t" '{ print $2 }' | sed -E 's/^CREATE DATABASE `/CREATE DATABASE IF NOT EXISTS `/' > $DST/$DATABASE/__create.sql
	if [ -f $DST/$DATABASE/__create.sql ]; then
            log "  > Export create"
	fi

        local mysqlDumpVars="--single-transaction"

        if mysqldump --column-statistics=0 --version &>/dev/null; then
            mysqlDumpVars="$mysqlDumpVars --column-statistics=0"
        fi

	query="SHOW FULL TABLES WHERE Table_type = 'VIEW';"
	for viewName in $(mysql --defaults-file=$CONFIG_FILE $DATABASE -N -e "$query" | sed -E 's/|//' | awk '{print $1}'); do
            mysqldump --defaults-file=$CONFIG_FILE $mysqlDumpVars $DATABASE $viewName | sed -E 's/DEFINER=[^*]*\*/\*/' >> $DST/$DATABASE/__views.sql
            array_views+=($viewName)
	done
	if [ -f $DST/$DATABASE/__views.sql ]; then
            log "  > Exports views"
	fi

	mysqldump --defaults-file=$CONFIG_FILE $mysqlDumpVars --routines --skip-events --skip-triggers --no-create-info --no-data --no-create-db --skip-opt $DATABASE | sed -E 's/DEFINER=[^*]*\*/\*/' > $DST/$DATABASE/__routines.sql
	if [ -f $DST/$DATABASE/__routines.sql ]; then
            log "  > Exports Routines"
	fi

        mysqldump --defaults-file=$CONFIG_FILE $mysqlDumpVars --triggers --skip-events --skip-routines --no-create-info --no-data --no-create-db --skip-opt $DATABASE | sed -E 's/DEFINER=[^*]*\*/\*/' > $DST/$DATABASE/__triggers.sql
        if [ -f $DST/$DATABASE/__triggers.sql ]; then
            log "  > Exports Triggers"
        fi

        mysqldump --defaults-file=$CONFIG_FILE $mysqlDumpVars --events --skip-routines --skip-triggers --no-create-info --no-data --no-create-db --skip-opt $DATABASE | sed -E 's/DEFINER=[^*]*\*/\*/' > $DST/$DATABASE/__events.sql
        if [ -f $DST/$DATABASE/__events.sql ]; then
		log "  > Exporting Events"
        fi

	local default_tables_exclude=(
            'slow_log'
            'general_log'
	)

	tables_exclude=( ${default_tables_exclude[@]} ${array_views[@]} ${EXCLUDE_TABLES[@]} )
	tables_exclude_expression=$(prepaire_skip_expression "${tables_exclude[@]}")
	log "Exclude tables: $tables_exclude_expression"

	data_tables_exclude=( ${EXCLUDE_DATA_TABLES[@]} )
	data_tables_exclude_expression=$(prepaire_skip_expression "${data_tables_exclude[@]}")
	log "Exclude data tables: $data_tables_exclude_expression"

	tables=( ${TABLES[@]} )
	tables_expression=$(prepaire_skip_expression "${tables[@]}")
	log "Only tables: $tables_expression"

	#
	# Get list`s tables
	#

	query="SHOW TABLES;"
	command="mysql --defaults-file=$CONFIG_FILE --skip-column-names -B $DATABASE -e \"$query\""

	if [ $tables_exclude_expression ]; then
		command=" $command | egrep -v \"$tables_exclude_expression\""
	fi

	if [ $tables_expression ]; then
		command=" $command | egrep \"$tables_expression\""
	fi

	log "Command: $command"

	for TABLE in $(eval $command); do

		log " ** Dump $DATABASE.$TABLE"

		if [ $(echo $data_tables_exclude_expression| grep $TABLE) ]; then
			log "Exclude data from table $TABLE"
			mysqldump --defaults-file=$CONFIG_FILE $mysqlDumpVars --no-data --add-drop-table --skip-events --skip-routines --skip-triggers --tab=$DST/$DATABASE/ $DATABASE $TABLE
		else
			# If fields has geospatial types
			checkGeo="mysql --defaults-file=$CONFIG_FILE -B $DATABASE -e \"SHOW COLUMNS FROM $TABLE WHERE Type IN ('point', 'polygon', 'geometry', 'linestring')\""
			hasGeo=$(eval $checkGeo)
			if [ ! -z "$hasGeo" ]; then
				mysqldump --defaults-file=$CONFIG_FILE $mysqlDumpVars --flush-logs --default-character-set=utf8 --add-drop-table --quick --skip-events --skip-routines --skip-triggers --result-file=$DST/$DATABASE/$TABLE.sql $DATABASE $TABLE
			else
				mysqldump --defaults-file=$CONFIG_FILE $mysqlDumpVars --flush-logs --default-character-set=utf8 --add-drop-table --quick --skip-events --skip-routines --skip-triggers --tab=$DST/$DATABASE/ $DATABASE $TABLE
			fi
		fi

		sed -i -E 's/AUTO_INCREMENT=[0-9]*\b//' $DST/$DATABASE/$TABLE.sql

		if [ -f "$DST/$DATABASE/$TABLE.sql" ]; then
			chmod $FILEATTRIBUTES $DST/$DATABASE/$TABLE.sql
			chown $USER:$GROUP $DST/$DATABASE/$TABLE.sql
			log "  ** set permision to $DATABASE/$TABLE.sql"
		else
			log "  ** WARNING : $DST/$DATABASE/$TABLE.sql not found"
		fi

		if [ -f "$DST/$DATABASE/$TABLE.txt" ]; then

			if [ $COMPRESS ]; then

				log "  ** $COMPRESS $DATABASE/$TABLE.txt in background"

				if [ $COMPRESS == 'bzip2' ]; then

					if [ -f "$DST/$DATABASE/$TABLE.txt.bz2" ]; then
						rm $DST/$DATABASE/$TABLE.txt.bz2
					fi

					($COMPRESS $DST/$DATABASE/$TABLE.txt && chmod $FILEATTRIBUTES $DST/$DATABASE/$TABLE.txt.bz2 && chown $USER:$GROUP $DST/$DATABASE/$TABLE.txt.bz2) &

				elif [ $COMPRESS == 'gzip' ]; then

					if [ -f "$DST/$DATABASE/$TABLE.txt.gz" ]; then
						rm $DST/$DATABASE/$TABLE.txt.gz
					fi

					($COMPRESS $DST/$DATABASE/$TABLE.txt && chmod $FILEATTRIBUTES $DST/$DATABASE/$TABLE.txt.gz && chown $USER:$GROUP $DST/$DATABASE/$TABLE.txt.gz) &

				fi

			fi

		else
			log "  ** WARNING : $DST/$DATABASE/$TABLE.txt not found"
		fi

	done

    log " END "
}

usage()
{
    cat << EOF

        This mysql backup engine.

        Usage:  $0 <[database-name]> <[options]> or bash $0 <[database-name]> <[options]>

Options:
   --tables=                            Dump only such tables
   --exclude-tables=                    Exclude tables
   --exclude-data-tables=               Exclude data tables
   -c= | --compress=                    Compress with gzip or bzip2
   -v  | --verbose                      Add verbose into output
   -l=  | --lifetime=                    Lifetime for dump files
   --config=                            Config file of Debian format
   --dir=                               Backup directory
   -h  | --help                         This text

Examples:
        backup.sh --verbose --compress=
        backup.sh --verbose --compress=gzip
        backup.sh --verbose --compress=bzip2
        backup.sh --verbose --compress=
        backup.sh --verbose --compress= --lifetime="3 day ago"
        backup.sh --verbose --config="/etc/mysql/debian.cnf" --lifetime="1 day ago"
        backup.sh --verbose --dir="/var/backups/mysql" --config="/etc/mysql/debian.cnf" --lifetime="1 day ago"
        backup.sh --verbose --dir="/home/backups/mysql" --lifetime="1 day ago"
        backup.sh --verbose --dir="/home/backups/mysql" --exclude-tables="tbl_template" --lifetime="1 day ago"
        backup.sh --verbose --dir="/home/backups/mysql" --tables="tbl_template tbl_template1 tbl_template2"
				
EOF
}

if [ $# = 0 ]; then
    usage;
    exit;
fi

DATABASE="$1"

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
        -t=* | --tables=*)
            TABLES=( "${i#*=}" )
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
        --include-tables=*)
            INCLUDE_TABLES=( "${i#*=}" )
            shift # past argument=value
        ;;
        --include-data-tables=*)
            INCLUDE_DATA_TABLES=( "${i#*=}" )
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

if check_connection; then
    if [ ! -d "$DST" ]; then
        mkdir -p $DST;
        chmod $DIRECTORYATTRIBUTES $DST;
        chown $USER:$GROUP $DST;
    fi

    if [ -d "$DSTOLD" ]; then
        rm -fr $DSTOLD;
    fi

    # === SETTINGS ===
    log "============================================"
    log "Dump into: $DST"
    log "Config file: $CONFIG_FILE"
    log "Verbose: $VERBOSE"
    log "Compress: $COMPRESS"
    log "Database: $DATABASE"
    log "Tables: $TABLES"
    log "Exclude tables: $EXCLUDE_TABLES"
    log "Life time: $TIME_REMOVED_DUMP_FILES"
    log "============================================"
    log ""

    # === AUTORUN ===
    backup
else
    log "Failed to establish a connection to the database"
fi
