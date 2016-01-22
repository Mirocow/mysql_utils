#!/bin/bash

# === CONFIG ===
CONFIG_CHUNK=1000000

# === DO NOT EDIT BELOW THIS LINE ===

if [ ! -n "$BASH" ] ;then echo Please run this script $0 with bash; exit 1; fi

# === FUNCTIONS ===
f_log()
{
	echo "RESTORE: $@"
}

restore()
{
  DIR=$@

  f_log "Check path $DIR"
	
	f_log "** START **"

  BDD=${DIR##*/}

  if [ $BDD ]; then

    f_log "Found backup files $DIR"

    if [ -f $DIR/__create.sql ]; then
      f_log "Create database $BDD"
      time mysql --defaults-extra-file=$CONFIG_FILE < $DIR/__create.sql 2>/dev/null
    fi

    tables=$(ls -1 $DIR |  grep -v __ | awk -F. '{print $1}' | sort | uniq)

    f_log "Create tables in $BDD"
    for TABLE in $tables; do
      f_log "Create table: $BDD/$TABLE"
      time mysql --defaults-extra-file=$CONFIG_FILE $BDD -e "SET foreign_key_checks = 0;
                      DROP TABLE IF EXISTS $TABLE;
                      SOURCE $DIR/$TABLE.sql;
                      SET foreign_key_checks = 1;"
    done

    f_log "Import data into $BDD"
    for TABLE in $tables; do
			
      f_log "Import data into $BDD/$TABLE"
      if [ -f "$DIR/$TABLE.txt.bz2" ]; then
          f_log "< $TABLE"
          if [ -f "$DIR/$TABLE.txt" ]; then
            f_log "rm $DIR/$TABLE.txt"
            rm $DIR/$TABLE.txt
          fi
          bunzip2 $DIR/$TABLE.txt.bz2
      fi

      if [ -f "$DIR/$TABLE.txt" ]; then
        f_log "+ $TABLE"
				split -l $CONFIG_CHUNK "$DIR/$TABLE.txt" ${TABLE}_part_
				for segment in ${TABLE}_part_*; do 
          time mysql --defaults-extra-file=$CONFIG_FILE $BDD --local-infile -e "SET foreign_key_checks = 0; SET unique_checks = 0; SET sql_log_bin = 0;
                          LOAD DATA LOCAL INFILE '$segment'
                          INTO TABLE $TABLE;
                          SET foreign_key_checks = 1; SET unique_checks = 1; SET sql_log_bin = 1;"
					rm $segment  
        done
        if [ ! -f "$DIR/$TABLE.txt.bz2" ]; then
          f_log "> $TABLE"
          bzip2 $DIR/$TABLE.txt
        fi
      fi
			
			if [ $DATABASES_TABLE_CHECK ]; then
				if [ -f "$DIR/$BDD/$TABLE.ibd" ]; then
					if [ ! $(innochecksum $DIR/$BDD/$TABLE.ibd) ]; then
						f_log "$TABLE [OK]"
					else
						f_log "$TABLE [ERR]"
					fi
				fi
			fi
			
    done

    if [ -f "$DIR/__routines.sql" ]; then
      f_log "Import routines into $BDD"
      time mysql --defaults-extra-file=$CONFIG_FILE $BDD < $DIR/__routines.sql 2>/dev/null
    fi

    if [ -f "$DIR/__views.sql" ]; then
      f_log "Import views into $BDD"
      time mysql --defaults-extra-file=$CONFIG_FILE $BDD < $DIR/__views.sql 2>/dev/null
    fi

    f_log "Flush privileges;"
    time mysql --defaults-extra-file=$CONFIG_FILE -e "flush privileges;"

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
	 -s			 Selected databases
	 -c			 Check innochecksum of table after import
EOF
}

# === CHECKS ===
if [ $# = 0 ]; then
    usage;
    exit;
fi

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
        --config=*)
            CONFIG_FILE=( "${i#*=}" )
            shift # past argument=value
        ;;
        --chunk=*)
            CONFIG_CHUNK=( "${i#*=}" )
            shift # past argument=value
        ;;				
        -c)
						DATABASES_TABLE_CHECK=1
						shift
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

# === AUTORUN ===
restore $(pwd)

