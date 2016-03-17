#!/bin/bash

# === CONFIG ===
CONFIG_CHUNK=1000000
VERBOSE=0

# === DO NOT EDIT BELOW THIS LINE ===

if [ ! -n "$BASH" ] ;then echo Please run this script $0 with bash; exit 1; fi

# === FUNCTIONS ===
database_exists()
{
	RESULT=`mysqlshow --defaults-extra-file=$CONFIG_FILE $@| grep -v Wildcard | grep -o $@`
	if [ "$RESULT" == "$@" ]; then
			echo YES
	else
			echo NO
	fi
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
  DIR=$@

  f_log "Check path $DIR"	
	
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
	if [ "$(ls -1 $DIR/*/__create.sql 2>/dev/null | wc -l)" -le "0" ]; then
			f_log "Your must run script from backup directory"
			exit 1
	fi

	for i in $(ls -1 -d $DIR/*); do

		BDD=$(basename $i)
		
		for skip in "${DATABASES_SKIP[@]}"; do
			if [ $BDD = $skip ]; then
				f_log "Skip database $BDD"
				unset BDD
				break
			fi								
		done
		
		for select in "${DATABASES_SELECTED[@]}"; do
			if [ $BDD != $select ]; then
				f_log "Skip database $BDD"
				unset BDD
				break
			fi								
		done
	
		if [ $BDD ]; then
		
			if [ -f $DIR/$BDD/__create.sql ]; then
				f_log "Create database $BDD"
				mysql --defaults-extra-file=$CONFIG_FILE < $DIR/$BDD/__create.sql 2>/dev/null
			fi
			
			if [ $(database_exists $BDD) != "YES" ]; then
				f_log "Error: Database $BDD dose not exists";
			else
			
				tables=$(ls -1 $DIR/$BDD | grep -v __ | grep .sql | awk -F. '{print $1}' | sort | uniq)
			
				f_log "Create tables in $BDD"
				for TABLE in $tables; do							
					f_log "Create table: $BDD/$TABLE"
					mysql --defaults-extra-file=$CONFIG_FILE $BDD -e "SET foreign_key_checks = 0;
						DROP TABLE IF EXISTS $TABLE;
						SOURCE $DIR/$BDD/$TABLE.sql;
						SET foreign_key_checks = 1;"
				done
				
				f_log "Import data into $BDD"		
				for TABLE in $tables; do									
					f_log "Import data into $BDD/$TABLE"
						
					if [ -f "$DIR/$BDD/$TABLE.txt.bz2" ]; then
						f_log "< $TABLE"
						if [ -f "$DIR/$BDD/$TABLE.txt" ]; then
							rm $DIR/$BDD/$TABLE.txt
						fi
						bunzip2 -k $DIR/$BDD/$TABLE.txt.bz2
					fi
					
					if [ -f "$DIR/$BDD/$TABLE.txt" ]; then
					
						f_log "+ $TABLE"
						
						split -l $CONFIG_CHUNK "$DIR/$BDD/$TABLE.txt" "$DIR/$BDD/${TABLE}_part_"
						for segment in "$DIR/$BDD/${TABLE}"_part_*; do
							f_log "Restore from $segment"
							time mysql --defaults-extra-file=$CONFIG_FILE $BDD --local-infile -e "SET foreign_key_checks = 0; SET unique_checks = 0; SET sql_log_bin = 0;
								LOAD DATA LOCAL INFILE '$segment'
								INTO TABLE $TABLE;
								SET foreign_key_checks = 1; SET unique_checks = 1; SET sql_log_bin = 1;"
								
							if [ -f "$segment" ]; then
								f_log "Delete segment $segment"
								rm "$segment"
							fi								
						done
						
						if [ -f "$DIR/$BDD/$TABLE.txt.bz2" ]; then
							f_log "Delete source: $TABLE.txt"
							rm $DIR/$BDD/$TABLE.txt
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
				
				if [ -f "$DIR/$BDD/__routines.sql" ]; then
						f_log "Import routines into $BDD"
						mysql --defaults-extra-file=$CONFIG_FILE $BDD < $DIR/$BDD/__routines.sql 2>/dev/null
				fi
				
				if [ -f "$DIR/$BDD/__views.sql" ]; then
						f_log "Import views into $BDD"
						mysql --defaults-extra-file=$CONFIG_FILE $BDD < $DIR/$BDD/__views.sql 2>/dev/null
				fi
				
			fi
		fi				
	done

	f_log "Flush privileges;"
	mysql --defaults-extra-file=$CONFIG_FILE -e "flush privileges;"

	f_log "** END **"
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
        --chunk=*)
            CONFIG_CHUNK=( "${i#*=}" )
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
f_log "Verbose: $VERBOSE"
f_log "Selected databases: $DATABASES_SELECTED"
f_log "============================================"
f_log ""

# === AUTORUN ===
restore $(pwd)

