#!/bin/bash

# === CONFIG ===
VERBOSE=0
LOAD_DATA_LOCAL_INFILE=0
CONVERT_INNODB=0
CONFIG_CHUNK=100000
BIN_DEPS="ls grep awk sort uniq bunzip2 bzip2 mysql"

# === DO NOT EDIT BELOW THIS LINE ===

if [ ! -n "$BASH" ] ;then echo Please run this script $0 with bash; exit 1; fi


# === FUNCTIONS ===
source $(dirname "$0")/functions.sh

restore()
{
    DATABASE_DIR=$@

    log "RESTORE: Check path $DATABASE_DIR"

    log "RESTORE: ** START **"

    DATABASE=${DATABASE_DIR##*/}

    if [ $DATABASE ]; then

        :> $DATABASE_DIR/restore_error.log

        log "RESTORE: Found restore files $DATABASE_DIR"

        if [ -f $DATABASE_DIR/__create.sql ]; then
            log "RESTORE: Create database $DATABASE if not exists"
            sed -i 's/^CREATE DATABASE `/CREATE DATABASE IF NOT EXISTS `/' $DATABASE_DIR/__create.sql
            mysql --defaults-file=$CONFIG_FILE < $DATABASE_DIR/__create.sql 2>> $DATABASE_DIR/restore_error.log
        fi

        tables=$(ls -1 $DATABASE_DIR | grep --invert-match '^__' | grep .sql | awk -F. '{print $1}' | sort | uniq)

        log "RESTORE: Create tables in $DATABASE"
        for TABLE in $tables; do

            log "RESTORE: Create table: $DATABASE/$TABLE"
            if [ $CONVERT_INNODB -eq 1 ]; then
                sed -i 's/ENGINE=MyISAM/ENGINE=InnoDB/' $DATABASE_DIR/$TABLE.sql
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

                split -l $CONFIG_CHUNK -d "$DATABASE_DIR/$TABLE.txt" "$DATABASE_DIR/${TABLE}_part_"
                local segments=$(ls -1 "$DATABASE_DIR/${TABLE}"_part_*|wc -l)
                for segment in "$DATABASE_DIR/${TABLE}"_part_*; do

                    wait_connection

                    error=$(mysql --defaults-file=$CONFIG_FILE $DATABASE $OPTIONS --execute="
                    SET SESSION sql_mode='NO_AUTO_VALUE_ON_ZERO';
                    SET SESSION wait_timeout=3600;
                    SET foreign_key_checks = 0;
                    SET unique_checks = 0;
                    SET sql_log_bin = 0;
                    SET autocommit = 0;
                    LOCK TABLES $TABLE WRITE;
                    $OPERATOR '$segment' INTO TABLE $TABLE CHARACTER SET UTF8;
                    UNLOCK TABLES;
                    COMMIT;
                    SET autocommit=1;
                    SET foreign_key_checks = 1;
                    SET unique_checks = 1;
                    SET sql_log_bin = 1;
                    " 2>&1)

                    if [[ -z "$error" ]]; then
                        log "+ $segment / $segments"
                    else
                        log "- $segment / $segments"
                        break
                    fi

                    if [ -f "$segment" ]; then
                        rm "$segment"
                    fi

                done

                if [[ -z "$error" ]]; then
                    log "RESTORE: + $TABLE"
                else
                    log "RESTORE: - $TABLE"
                    log "RESTORE: Rise error: $error"
                fi

            fi

        done

        if [ -f "$DATABASE_DIR/__routines.sql" ]; then
            log "RESTORE: Import routines into $DATABASE"
            mysql --defaults-file=$CONFIG_FILE $DATABASE < $DATABASE_DIR/__routines.sql 2>> $DATABASE_DIR/restore_error.log
        fi

        if [ -f "$DATABASE_DIR/__views.sql" ]; then
            log "RESTORE: Import views into $DATABASE"
            mysql --defaults-file=$CONFIG_FILE $DATABASE < $DATABASE_DIR/__views.sql 2>> $DATABASE_DIR/restore_error.log
        fi

        if [ -f "$DATABASE_DIR/__triggers.sql" ]; then
            log "RESTORE: Import triggers into $DATABASE"
            mysql --defaults-file=$CONFIG_FILE $DATABASE < $DATABASE_DIR/__triggers.sql 2>> $DATABASE_DIR/restore_error.log
        fi

        if [ -f "$DATABASE_DIR/__events.sql" ]; then
            log "RESTORE: Import events into $DATABASE"
            mysql --defaults-file=$CONFIG_FILE $DATABASE < $DATABASE_DIR/__events.sql 2>> $DATABASE_DIR/restore_error.log
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
    --convert-innodb   Convert database into InnoDb
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
    log "RESTORE: Config file: $CONFIG_FILE"
    log "RESTORE: Load from local y/n (default n): $LOAD_DATA_LOCAL_INFILE"
    log "RESTORE: Convert into InnoDB y/n (default n): $CONVERT_INNODB"
    log "RESTORE: Verbose: $VERBOSE"
    log "RESTORE: ============================================"
    log "RESTORE: "

    lockfile "$DATABASE_DIR/lockfile.lock"

    # === AUTORUN ===
    restore $DATABASE_DIR
fi
