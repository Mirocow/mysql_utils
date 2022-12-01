#!/bin/bash

# === CONFIG ===
CONFIG_CHUNK=1000000
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

  DATABASE=${RESTORE_DIR##*/}

  if [ $DATABASE ]; then

    f_log "Found backup files $RESTORE_DIR"

    if [ -f $RESTORE_DIR/__create.sql ]; then
      f_log "Create database $DATABASE"
      mysql --defaults-file=$CONFIG_FILE < $RESTORE_DIR/__create.sql 2>/dev/null
    fi

    tables=$(ls -1 $RESTORE_DIR | grep -v __ | grep .sql | awk -F. '{print $1}' | sort | uniq)

    f_log "Create tables in $DATABASE"
    for TABLE in $tables; do
      f_log "Create table: $DATABASE/$TABLE"
      if [ $CONVERT_INNODB -eq "y" ]; then
          sed -i 's/ENGINE=MyISAM/ENGINE=InnoDB/' $RESTORE_DIR/$TABLE.sql
      fi
      mysql --defaults-file=$CONFIG_FILE $DATABASE -e "
        SET foreign_key_checks = 0;
        DROP TABLE IF EXISTS $TABLE;
        SOURCE $RESTORE_DIR/$TABLE.sql;
        SET foreign_key_checks = 1;
        "
    done

    f_log "Import data into $DATABASE"
    for TABLE in $tables; do

        f_log "Import data into $DATABASE/$TABLE"

        if [ -f "$RESTORE_DIR/$TABLE.txt.bz2" ]; then
          f_log "< $TABLE"
          if [ -f "$RESTORE_DIR/$TABLE.txt" ]; then
            f_log "Delete source: $TABLE.txt"
            rm $RESTORE_DIR/$TABLE.txt
          fi
          bunzip2 -k $RESTORE_DIR/$TABLE.txt.bz2
        fi

        if [ -s "$RESTORE_DIR/$TABLE.txt" ]; then
          f_log "+ $TABLE"

          mysql --defaults-file=$CONFIG_FILE $DATABASE --local-infile -e "
          SET SESSION sql_mode='NO_AUTO_VALUE_ON_ZERO';
          SET foreign_key_checks = 0;
          SET unique_checks = 0;
          SET sql_log_bin = 0;
          SET autocommit = 0;
          LOAD DATA LOCAL INFILE '$RESTORE_DIR/$TABLE.txt' INTO TABLE $TABLE;
          COMMIT;
          SET autocommit=1;
          SET foreign_key_checks = 1;
          SET unique_checks = 1;
          SET sql_log_bin = 1;
          "
        fi

        if [ $DATABASES_TABLE_CHECK ]; then
          if [ -f "$RESTORE_DIR/$TABLE.ibd" ]; then
            if [ ! $(innochecksum $RESTORE_DIR/$TABLE.ibd) ]; then
              f_log "$TABLE [OK]"
            else
              f_log "$TABLE [ERR]"
            fi
          fi
        fi

    done

    if [ -f "$RESTORE_DIR/__routines.sql" ]; then
        f_log "Import routines into $DATABASE"
        mysql --force --defaults-file=$CONFIG_FILE $DATABASE < $RESTORE_DIR/__routines.sql 2>/dev/null
    fi

    if [ -f "$RESTORE_DIR/__views.sql" ]; then
        f_log "Import views into $DATABASE"
        mysql --force --defaults-file=$CONFIG_FILE $DATABASE < $RESTORE_DIR/__views.sql 2>/dev/null
    fi

    if [ -f "$RESTORE_DIR/__triggers.sql" ]; then
        f_log "Import triggers into $DATABASE"
        mysql --force --defaults-file=$CONFIG_FILE $DATABASE < $RESTORE_DIR/__triggers.sql 2>/dev/null
    fi

    if [ -f "$RESTORE_DIR/__events.sql" ]; then
        f_log "Import events into $DATABASE"
        mysql --force --defaults-file=$CONFIG_FILE $DATABASE < $RESTORE_DIR/__events.sql 2>/dev/null
    fi

    f_log "Flush privileges;"
    mysql --defaults-file=$CONFIG_FILE -e "flush privileges;"

    f_log "** END **"

  else

    f_log "Database not found"

  fi
}

usage()
{
cat << EOF
usage: $0 options

This script restore databases.

OPTIONS:
   -e      Exclude databases
   -s      Selected databases
   -c      Check innochecksum of table after import


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
    -c)
        DATABASES_TABLE_CHECK=1
        shift
    ;;
    --config=*)
        CONFIG_FILE=( "${i#*=}" )
        shift # past argument=value
    ;;
    --chunk=*)
        CONFIG_CHUNK=( "${i#*=}" )
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
f_log "Verbose: $VERBOSE"
f_log "============================================"
f_log ""

# === AUTORUN ===
restore $BACKUP_DIR
