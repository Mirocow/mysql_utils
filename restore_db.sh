#!/bin/bash

# === CONFIG ===
VERBOSE=0
CONVERT_INNODB="n"

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
        if [ $CONVERT_INNODB == "y" ]; then
            sed -i 's/ENGINE=MyISAM/ENGINE=InnoDB/' $DATABASE_DIR/$TABLE.sql
        fi

        mysql --defaults-file=$CONFIG_FILE $DATABASE -e "
          SET foreign_key_checks = 0;
          DROP TABLE IF EXISTS $TABLE;
          SOURCE $DATABASE_DIR/$TABLE.sql;
          SET foreign_key_checks = 1;
          " 2>> $DATABASE_DIR/restore_error.log
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
            mysql --defaults-file=$CONFIG_FILE $DATABASE --local-infile -e "
            SET SESSION sql_mode='NO_AUTO_VALUE_ON_ZERO';
            SET foreign_key_checks = 0;
            SET unique_checks = 0;
            SET sql_log_bin = 0;
            SET autocommit = 0;
            LOAD DATA LOCAL INFILE '$DATABASE_DIR/$TABLE.txt' INTO TABLE $TABLE;
            COMMIT;
            SET autocommit=1;
            SET foreign_key_checks = 1;
            SET unique_checks = 1;
            SET sql_log_bin = 1;
            " 2>> $DATABASE_DIR/restore_error.log
            log "RESTORE: + $TABLE"
          fi

          if [ $DATABASES_TABLE_CHECK ]; then
            if [ -f "$DATABASE_DIR/$TABLE.ibd" ]; then
              if [ ! $(innochecksum $DATABASE_DIR/$TABLE.ibd) ]; then
                log "RESTORE: $TABLE [OK]"
              else
                log "RESTORE: $TABLE [ERR]"
              fi
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
   -c               Check innochecksum of table after import
   --config         Path to configfile
   --convert-innodb
   --verbose
   -h | --help      Usage

Examples:
        restore_db.sh --verbose




EOF
}

# === CHECKS ===
DATABASE_DIR=$(pwd)

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
    --convert-innodb=*)
         CONVERT_INNODB=( "${i#*=}" )
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
  log "RESTORE: Convert into InnoDB y/n: $CONVERT_INNODB"
  log "RESTORE: Verbose: $VERBOSE"
  log "RESTORE: ============================================"
  log "RESTORE: "

  lockfile "$DATABASE_DIR/lockfile.lock"

  # === AUTORUN ===
  restore $DATABASE_DIR
fi
