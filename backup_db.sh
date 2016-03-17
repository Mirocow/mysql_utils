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

# === DO NOT EDIT BELOW THIS LINE ===

if [ ! -n "$BASH" ] ;then echo Please run this script $0 with bash; exit 1; fi

# === FUNCTIONS ===
if [ -f '/etc/debian_version' ]; then
    CONFIG_FILE='/etc/mysql/debian.cnf'
else
    CONFIG_FILE='~/mysql_utils/etc/mysql/debian.cnf'
fi

# === FUNCTION ===
f_log()
{
    local bold=$(tput bold)
    local yellow=$(tput setf 6)
    local red=$(tput setf 4)
    local green=$(tput setf 2)
    local reset=$(tput sgr0)
    local toend=$(tput hpa $(tput cols))$(tput cub 6)	
    
    logger "BACKUP: $@"

    if [ $VERBOSE -eq 1 ]; then
        echo "BACKUP: $@"
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

backup()
{
    f_log " START "

    query="SHOW databases;"

    local default_databases_exclude=(
	'information_schema'
	'performance_schema'
    )

    local array_views=()

	touch $DST/$DATABASE/error.log

	mkdir -p $DST/$DATABASE 2>/dev/null 1>&2
	chown $USER:$GROUP $DST/$DATABASE
	chmod $DIRECTORYATTRIBUTES $DST/$DATABASE

	query="SHOW CREATE DATABASE \`$DATABASE\`;"
	mysql --defaults-extra-file=$CONFIG_FILE --skip-column-names -B -e "$query" | awk -F"\t" '{ print $2 }' > $DST/$DATABASE/__create.sql
	if [ -f $DST/$DATABASE/__create.sql ]; then
		f_log "  > Export create"
	fi

	query="SHOW FULL TABLES WHERE Table_type = 'VIEW';"
	for viewName in $(mysql --defaults-extra-file=$CONFIG_FILE $DATABASE -N -e "$query" | sed 's/|//' | awk '{print $1}'); do
		mysqldump --defaults-file=$CONFIG_FILE $DATABASE $viewName >> $DST/$DATABASE/__views.sql 2>> $DST/$DATABASE/error.log
		array_views+=($viewName)
	done		
	if [ -f $DST/$DATABASE/__views.sql ]; then
		f_log "  > Exports views"
	fi

	mysqldump --defaults-file=$CONFIG_FILE --routines --no-create-info --no-data --no-create-db --skip-opt $DATABASE 2>> $DST/$DATABASE/error.log  | sed -e 's/DEFINER=[^*]*\*/\*/' > $DST/$DATABASE/__routines.sql
	if [ -f $DST/$DATABASE/__routines.sql ]; then
		f_log "  > Exports Routines"
	fi

	local default_tables_exclude=(
	'slow_log'
	'general_log'
	)

	tables_exclude=( ${default_tables_exclude[@]} ${array_views[@]} ${EXCLUDE_TABLES[@]} )
	tables_exclude_expression=`prepaire_skip_expression "${tables_exclude[@]}"`
	f_log "Exclude tables: $tables_exclude_expression"		

	data_tables_exclude=( ${EXCLUDE_DATA_TABLES[@]} )
	data_tables_exclude_expression=`prepaire_skip_expression "${data_tables_exclude[@]}"`
	f_log "Exclude data tables: $data_tables_exclude_expression"
	
	query="SHOW TABLES;"
	for TABLE in $(mysql --defaults-extra-file=$CONFIG_FILE --skip-column-names -B $DATABASE -e "$query" | egrep -v "$tables_exclude_expression"); do
		f_log "  ** Dump $DATABASE.$TABLE"

		if [ $(echo $data_tables_exclude_expression| grep $TABLE) ]; then
			f_log "Exclude data from table $TABLE"
			mysqldump --defaults-file=$CONFIG_FILE --no-data --add-drop-table  --tab=$DST/$DATABASE/ $DATABASE $TABLE 2>> $DST/$DATABASE/error.log
		else
			mysqldump --defaults-file=$CONFIG_FILE --add-drop-table --quick  --tab=$DST/$DATABASE/ $DATABASE $TABLE 2>> $DST/$DATABASE/error.log
		fi            

		if [ -f "$DST/$DATABASE/$TABLE.sql" ]; then
			chmod $FILEATTRIBUTES $DST/$DATABASE/$TABLE.sql
			chown $USER:$GROUP $DST/$DATABASE/$TABLE.sql
			f_log "  ** set perm on $DATABASE/$TABLE.sql"
		else
			f_log "  ** WARNING : $DST/$DATABASE/$TABLE.sql not found"
		fi

		if [ -f "$DST/$DATABASE/$TABLE.txt" ]; then

			if [ $COMPRESS ]; then

				f_log "  ** $COMPRESS $DATABASE/$TABLE.txt in background"

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
			f_log "  ** WARNING : $DST/$DATABASE/$TABLE.txt not found"
		fi

	done

    f_log " END "
}

usage()
{
    cat << EOF
    
        This mysql backup engine.
    
        Usage:  $0 <[database-name]> <[options]> or bash $0 <[database-name]> <[options]>

Options:
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
        backup.sh --verbose --compress=
        backup.sh --verbose --compress= --lifetime="3 day ago"
        backup.sh --verbose --config="/etc/mysql/debian.cnf" --lifetime="1 day ago"
        backup.sh --verbose --dir="/var/backups/mysql" --config="/etc/mysql/debian.cnf" --lifetime="1 day ago"
        backup.sh --verbose --dir="/home/backups/mysql" --lifetime="1 day ago"
        backup.sh --verbose --dir="/home/backups/mysql" --exclude-tables="tbl_template" --lifetime="1 day ago"
				
				
EOF
}

if [ $# = 0 ]; then
    usage;
    exit;
fi

DATABASE=''
EXCLUDE_TABLES=''
EXCLUDE_DATA_TABLES=''
BIN_DEPS="mysql mysqldump $COMPRESS"

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
    chmod $DIRECTORYATTRIBUTES $DST;
    chown $USER:$GROUP $DST;    
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
f_log "Database: $DATABASE"
f_log "Exclude tables: $EXCLUDE_TABLES"
f_log "Life time: $TIME_REMOVED_DUMP_FILES"
f_log "============================================"
f_log ""

# === AUTORUN ===
backup
