#!/bin/bash

# === CONFIG ===
VERBOSE=0
LOAD_DATA_LOCAL_INFILE=0
CONVERT_INNODB=0
CONFIG_CHUNK=100000
BIN_DEPS="ls grep awk sort uniq bunzip2 bzip2 mysql"
RESTORE_INTO=''

# === DO NOT EDIT BELOW THIS LINE ===

if [ ! -n "$BASH" ] ;then echo Please run this script $0 with bash; exit 1; fi


# === FUNCTIONS ===
source $(dirname "$0")/functions.sh

restore_table()
{
    local TABLE=$1

    log "RESTORE: Import data into $DATABASE/$TABLE"

    if [ -f "$DATABASE_DIR/$TABLE.txt.bz2" ]; then
        log "RESTORE: < $TABLE"
        if [ -f "$DATABASE_DIR/$TABLE.txt" ]; then
            log "RESTORE: Delete source: $TABLE.txt"
            rm $DATABASE_DIR/$TABLE.txt
        fi
        bunzip2 -k $DATABASE_DIR/$TABLE.txt.bz2
    fi

    if [ -s "$DATABASE_DIR/$TABLE.txt" ]; then

        OPTIONS='--unbuffered --wait --reconnect --skip-column-names'
        OPERATOR='LOAD DATA LOW_PRIORITY INFILE'
        if [ $LOAD_DATA_LOCAL_INFILE -eq 1 ]; then
            OPERATOR='LOAD DATA LOW_PRIORITY LOCAL INFILE'
            OPTIONS='--unbuffered --local-infile --wait --reconnect --skip-column-names'
        fi

        local error=''

        error=$(mysql --defaults-file=$CONFIG_FILE $DATABASE $OPTIONS --execute="
        SET GLOBAL net_buffer_length=1000000; -- Set network buffer length to a large byte number
        SET GLOBAL max_allowed_packet=1000000000; -- Set maximum allowed packet size to a large byte number
        SET SESSION sql_mode='NO_AUTO_VALUE_ON_ZERO';
        SET SESSION wait_timeout=3600;
        SET foreign_key_checks = 0;
        SET unique_checks = 0;
        SET sql_log_bin = 0;
        SET autocommit = 0;
        LOCK TABLES $TABLE WRITE;
        $OPERATOR '$DATABASE_DIR/$TABLE.txt' IGNORE INTO TABLE $TABLE CHARACTER SET UTF8;
        UNLOCK TABLES;
        COMMIT;
        SET autocommit=1;
        SET foreign_key_checks = 1;
        SET unique_checks = 1;
        SET sql_log_bin = 1;
        " 2>&1)

        if [[ -z "$error" ]]; then
            log "RESTORE: + $TABLE"
        else
            log "RESTORE: - $TABLE"
            log "RESTORE: Rise error: $error"
        fi

    fi

	if [ $DATABASES_TABLE_CHECK ]; then
		if [ -f "$DATABASE_DIR/$TABLE.ibd" ]; then
			if [ ! $(innochecksum $DATABASE_DIR/$TABLE.ibd) ]; then
				f_log "$TABLE [OK]"
			else
				f_log "$TABLE [ERR]"
			fi
		fi
	fi
}

restore()
{
    DATABASE_DIR=$@

    log "RESTORE: Check path $DATABASE_DIR"

    log "RESTORE: ** START **"

    DATABASE=${DATABASE_DIR##*/}

    if [ $DATABASE ]; then

        log "RESTORE: Found restore files $DATABASE_DIR"

        if [ -f $DATABASE_DIR/__create.sql ]; then
            if [ ! -z "$RESTORE_INTO" ]; then
                sed -i -E 's/`'$DATABASE'`/`'$RESTORE_INTO'`/' $DATABASE_DIR/__create.sql
                DATABASE="$RESTORE_INTO"
            fi
            log "RESTORE: Create database $DATABASE if not exists"
            sed -i -E 's/^CREATE DATABASE `/CREATE DATABASE IF NOT EXISTS `/' $DATABASE_DIR/__create.sql
            mysql --defaults-file=$CONFIG_FILE < $DATABASE_DIR/__create.sql
        fi

        tables=$(ls -1 $DATABASE_DIR | grep --invert-match '^__' | grep .sql | awk -F. '{print $1}' | sort | uniq)

        log "RESTORE: Create tables in $DATABASE"
        for TABLE in $tables; do

            log "RESTORE: Create table: $DATABASE/$TABLE"
            if [ $CONVERT_INNODB -eq 1 ]; then
                sed -i -E 's/ENGINE=MyISAM/ENGINE=InnoDB/' $DATABASE_DIR/$TABLE.sql
            fi

            error=$(mysql --defaults-file=$CONFIG_FILE $DATABASE -e "
                  SET foreign_key_checks = 0;
                  DROP TABLE IF EXISTS $TABLE;
                  SOURCE $DATABASE_DIR/$TABLE.sql;
                  SET foreign_key_checks = 1;
                  " 2>&1)

            if [[ ! -z "$error" ]]; then
                log "Rise error: $error"
            fi

        done

        log "RESTORE: Import data into $DATABASE"
        for TABLE in $tables; do
            restore_table "$TABLE"
        done

        if [ -f "$DATABASE_DIR/__routines.sql" ]; then
            log "RESTORE: Import routines into $DATABASE"
            mysql --defaults-file=$CONFIG_FILE $DATABASE < $DATABASE_DIR/__routines.sql
        fi

        if [ -f "$DATABASE_DIR/__views.sql" ]; then
            log "RESTORE: Import views into $DATABASE"
            mysql --defaults-file=$CONFIG_FILE $DATABASE < $DATABASE_DIR/__views.sql
        fi

        if [ -f "$DATABASE_DIR/__triggers.sql" ]; then
            log "RESTORE: Import triggers into $DATABASE"
            mysql --defaults-file=$CONFIG_FILE $DATABASE < $DATABASE_DIR/__triggers.sql
        fi

        if [ -f "$DATABASE_DIR/__events.sql" ]; then
            log "RESTORE: Import events into $DATABASE"
            mysql --defaults-file=$CONFIG_FILE $DATABASE < $DATABASE_DIR/__events.sql
        fi

        log "RESTORE: Flush privileges;"
        mysql --defaults-file=$CONFIG_FILE -e "flush privileges;"
        log "RESTORE: ** END **"

    else

         log "RESTORE: Database not found"

    fi
}

usage()
{
cat << EOF
usage: $0 options

This script restore databases.

OPTIONS:
    --chunk=           Put NUMBER lines per output file
    --config=          Path to configfil
    --convert-innodb=1 Convert database into InnoDb
    --restore_into=    Special name for create database with new name
    --verbose
    -h | --help        Usage

Examples:
        restore_db.sh --verbose




EOF
}

# === CHECKS ===
DATABASE_DIR=$(pwd)

if [ -f '/etc/debian_version' ]; then
    CONFIG_FILE='/etc/mysql/debian.cnf'
else
    CONFIG_FILE='~/mysql_utils/etc/mysql/debian.cnf'
fi

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
    --config=*)
        CONFIG_FILE=( "${i#*=}" )
        shift # past argument=value
    ;;
    --chunk=*)
        CONFIG_CHUNK=( "${i#*=}" )
        shift # past argument=value
    ;;
    --convert-innodb)
         CONVERT_INNODB=1
         shift # past argument=value
    ;;
    --restore_into=*)
        RESTORE_INTO=( "${i#*=}" )
        shift # past argument=value
    ;;
    -l | --local)
         LOAD_DATA_LOCAL_INFILE=1
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

if check_connection; then
    # === SETTINGS ===
    log "RESTORE: ============================================"
    log "RESTORE: Restore from: $DATABASE_DIR"
    log "RESTORE: Restore into database: $RESTORE_INTO"
    log "RESTORE: Config file: $CONFIG_FILE"
    log "RESTORE: Load from local y/n (default n): $LOAD_DATA_LOCAL_INFILE"
    log "RESTORE: Convert into InnoDB y/n (default n): $CONVERT_INNODB"
    log "RESTORE: Verbose: $VERBOSE"
    log "RESTORE: ============================================"
    log "RESTORE: "

    lockfile "$DATABASE_DIR/lockfile.lock"

    # === AUTORUN ===
    restore $DATABASE_DIR
else
    loc "Failed to establish a connection to the database"
fi
