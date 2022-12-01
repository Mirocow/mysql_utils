#!/bin/bash

# === CONFIG ===
VERBOSE=0
CONVERT_INNODB="n"

# === DO NOT EDIT BELOW THIS LINE ===

if [ ! -n "$BASH" ] ;then echo Please run this script $0 with bash; exit 1; fi

# === FUNCTIONS ===
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

f_log()
{
    local bold=$(tput bold)
    local yellow=$(tput setf 6)
    local red=$(tput setf 4)
    local green=$(tput setf 2)
    local reset=$(tput sgr0)
    local toend=$(tput hpa $(tput cols))$(tput cub 6)

    logger "RESTORE: $@"

    if [ $VERBOSE -eq 1 ]; then
        echo "RESTORE: $@"
    fi
}

restore()
{
  RESTORE_DIR=$@

  f_log "Check path $RESTORE_DIR"

    f_log "** START **"

    f_log "Check runtime"
    for BIN in $BIN_DEPS; do
            which $BIN 1>/dev/null 2>&1
            if [ $? -ne 0 ]; then
                    f_log "Error: Required file could not be found: $BIN"
                    exit 1
            fi
    done

    f_log "Check backups folder"
    if [ "$(ls -1 $RESTORE_DIR/*/__create.sql 2>/dev/null | wc -l)" -le "0" ]; then
            f_log "Your must run script from backup directory"
            exit 1
    fi

    IFS=' ' read -r -a DATABASES_SELECTED <<< "$DATABASES_SELECTED"
    IFS=' ' read -r -a DATABASES_SKIP <<< "$DATABASES_SKIP"

    for i in $(ls -1 -d $RESTORE_DIR/*); do

        DATABASE=$(basename $i)

        if [ ${#DATABASES_SELECTED[@]} -ne 0 ]; then
            if ! contains $DATABASE "${DATABASES_SELECTED[@]}"; then
                f_log "Skip database $DATABASE"
                unset DATABASE
            fi
        fi

        if [ ${#DATABASES_SKIP[@]} -ne 0 ]; then
            for skip in "${DATABASES_SKIP[@]}"; do
                if [ $DATABASE = $skip ]; then
                    f_log "Skip database $DATABASE"
                    unset DATABASE
                    break
                fi
            done
        fi

        if [ $DATABASE ]; then

            if [ -f $RESTORE_DIR/$DATABASE/__create.sql ]; then
                f_log "Create database $DATABASE"
                mysql --defaults-file=$CONFIG_FILE < $RESTORE_DIR/$DATABASE/__create.sql 2>/dev/null
            fi

            if [ $(database_exists $DATABASE) != "YES" ]; then
                f_log "Error: Database $DATABASE dose not exists";
            else

                tables=$(ls -1 $RESTORE_DIR/$DATABASE | grep -v __ | grep .sql | awk -F. '{print $1}' | sort | uniq)

                f_log "Create tables in $DATABASE"
                for TABLE in $tables; do
                    f_log "Create table: $DATABASE/$TABLE"
                    if [ $CONVERT_INNODB -eq "y" ]; then
                        sed -i 's/ENGINE=MyISAM/ENGINE=InnoDB/' $RESTORE_DIR/$DATABASE/$TABLE.sql
                    fi
                    mysql --defaults-file=$CONFIG_FILE $DATABASE -e "
                    SET foreign_key_checks = 0;
                    DROP TABLE IF EXISTS $TABLE;
                    SOURCE $RESTORE_DIR/$DATABASE/$TABLE.sql;
                    SET foreign_key_checks = 1;
                    "
                done

                f_log "Import data into $DATABASE"
                for TABLE in $tables; do
                    f_log "Import data into $DATABASE/$TABLE"

                    if [ -f "$RESTORE_DIR/$DATABASE/$TABLE.txt.bz2" ]; then
                        f_log "< $TABLE"
                        if [ -f "$RESTORE_DIR/$DATABASE/$TABLE.txt" ]; then
                            f_log "Delete source: $TABLE.txt"
                            rm $RESTORE_DIR/$DATABASE/$TABLE.txt
                        fi
                        bunzip2 -k $RESTORE_DIR/$DATABASE/$TABLE.txt.bz2
                    fi

                    if [ -s "$RESTORE_DIR/$DATABASE/$TABLE.txt" ]; then
                        f_log "+ $TABLE"

                        mysql --defaults-file=$CONFIG_FILE $DATABASE --local-infile -e "
                        SET SESSION sql_mode='NO_AUTO_VALUE_ON_ZERO';
                        SET foreign_key_checks = 0;
                        SET unique_checks = 0;
                        SET sql_log_bin = 0;
                        SET autocommit = 0;
                        LOAD DATA LOCAL INFILE '$RESTORE_DIR/$DATABASE/$TABLE.txt' INTO TABLE $TABLE;
                        COMMIT;
                        SET autocommit=1;
                        SET foreign_key_checks = 1;
                        SET unique_checks = 1;
                        SET sql_log_bin = 1;
                        "
                    fi

                    if [ $DATABASES_TABLE_CHECK ]; then
                        if [ -f "$RESTORE_DIR/$DATABASE/$TABLE.ibd" ]; then
                            if [ ! $(innochecksum $RESTORE_DIR/$DATABASE/$TABLE.ibd) ]; then
                                f_log "$TABLE [OK]"
                            else
                                f_log "$TABLE [ERR]"
                            fi
                        fi
                    fi
                done

                if [ -f "$RESTORE_DIR/$DATABASE/__routines.sql" ]; then
                        f_log "Import routines into $DATABASE"
                        mysql --force --defaults-file=$CONFIG_FILE $DATABASE < $RESTORE_DIR/$DATABASE/__routines.sql 2>/dev/null
                fi

                if [ -f "$RESTORE_DIR/$DATABASE/__views.sql" ]; then
                        f_log "Import views into $DATABASE"
                        mysql --force --defaults-file=$CONFIG_FILE $DATABASE < $RESTORE_DIR/$DATABASE/__views.sql 2>/dev/null
                fi

                if [ -f "$RESTORE_DIR/$DATABASE/__triggers.sql" ]; then
                        f_log "Import triggers into $DATABASE"
                        mysql --force --defaults-file=$CONFIG_FILE $DATABASE < $RESTORE_DIR/$DATABASE/__triggers.sql 2>/dev/null
                fi

                if [ -f "$RESTORE_DIR/$DATABASE/__events.sql" ]; then
                        f_log "Import events into $DATABASE"
                        mysql --force --defaults-file=$CONFIG_FILE $DATABASE < $RESTORE_DIR/$DATABASE/__events.sql 2>/dev/null
                fi

            fi
        fi
    done

    f_log "Flush privileges;"
    mysql --defaults-file=$CONFIG_FILE -e "flush privileges;"

    f_log "** END **"
}

usage()
{
cat << EOF
usage: $0 options

This script restore databases.

OPTIONS:
   -e               Exclude databases
   -s               Selected databases
   -c               Check innochecksum of table after import
   --config         Path to configfile
   --convert-innodb
   --verbose
   -h | --help      Usage

Examples:
        restore.sh --verbose



EOF
}

# === CHECKS ===
BACKUP_DIR=$(pwd)

BIN_DEPS="ls grep awk sort uniq bunzip2 bzip2 mysql"

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
    -e)
        DATABASES_SKIP=( "${i#*=}" )
        shift
    ;;
    -s)
        DATABASES_SELECTED=( "${i#*=}" )
        shift
    ;;
    -c)
        DATABASES_TABLE_CHECK=1
        shift
    ;;
    --config=*)
        CONFIG_FILE=( "${i#*=}" )
        shift # past argument=value
    ;;
    --convert-innodb)
         CONVERT_INNODB="yes"
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

# === SETTINGS ===
f_log "============================================"
f_log "Restore from: $BACKUP_DIR"
f_log "Config file: $CONFIG_FILE"
f_log "Convert into InnoDB y/n: $CONVERT_INNODB"
f_log "Databse skip: $DATABASES_SKIP"
f_log "Selected databases: $DATABASES_SELECTED"
f_log "Verbose: $VERBOSE"
f_log "============================================"
f_log ""

# === AUTORUN ===
restore $BACKUP_DIR
