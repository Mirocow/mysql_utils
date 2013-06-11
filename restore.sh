#!/usr/bin/env bash

# === CONFIG ===
DIR_PWD=$(pwd)
BIN_DEPS='bunzip2 bzip2 mysql'
MYCNF='/etc/mysql/debian.cnf'
MYDATA='/var/lib/mysql'

# === FUNCTIONS ===
f_log() 
{
	logger "$RESTORE: $@"
}

usage()
{
cat << EOF
usage: $0 options

This script restore databases.

OPTIONS:
   -e      Exclude databases
	 -c			 Check innochecksum of table after import
EOF
}

restore()
{
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
	if [ "$(ls -1 $DIR_PWD/*/__create.sql 2>/dev/null | wc -l)" -le "0" ]; then
			f_log "Your must run script from backup directory"
			exit 1
	fi

	f_log "Create databases"
	for i in $(ls -1 $DIR_PWD/*/__create.sql); do
			if [ -f "$i" ]; then			
					mysql --defaults-extra-file=$MYCNF < $i 2>/dev/null
			fi
	done

	for i in `ls -1 -d $DIR_PWD/*/`; do
					BDD=$(basename $i)
					
					for skip in "${DATABASES_SKIP[@]}"; do
						if [ $BDD = $skip ]; then
							f_log "Skip database $BDD"
							unset BDD
							break
						fi								
					done
					
					f_log "Import tables into $BDD"
					
					if [ $BDD ]; then						
						for TABLE in `ls -1 $i |  grep -v __ | awk -F. '{print $1}' | sort | uniq`; do
						
										f_log "Create table: $TABLE"
										mysql --defaults-extra-file=$MYCNF $BDD -e "SET foreign_key_checks = 0;
																		DROP TABLE IF EXISTS $TABLE;
																		SOURCE $DIR_PWD/$BDD/$TABLE.sql;
																		SET foreign_key_checks = 1;"					
															
										if [ -f "$DIR_PWD/$BDD/$TABLE.txt.bz2" ]; then
												f_log "< $TABLE"
												if [ -f "$DIR_PWD/$BDD/$TABLE.txt" ]; then
													rm $DIR_PWD/$BDD/$TABLE.txt
												fi
												bunzip2 $DIR_PWD/$BDD/$TABLE.txt.bz2
										fi
										
										if [ -f "$DIR_PWD/$BDD/$TABLE.txt" ]; then
											f_log "+ $TABLE"
											mysql --defaults-extra-file=$MYCNF $BDD -e "SET foreign_key_checks = 0;
																			LOAD DATA INFILE '$DIR_PWD/$BDD/$TABLE.txt'
																			INTO TABLE $TABLE;
																			SET foreign_key_checks = 1;"
																													
											if [ ! -f "$DIR_PWD/$BDD/$TABLE.txt.bz2" ]; then
												f_log "> $TABLE"
												bzip2 $DIR_PWD/$BDD/$TABLE.txt
											fi
										fi
										
										if [ $check ]; then
											# Check INNODB table
											if [ -f "$MYDATA/$BDD/$TABLE.ibd" ]; then
												if [ ! `innochecksum $MYDATA/$BDD/$TABLE.ibd` ]; then
													f_log "$TABLE [OK]"
												else
													f_log "$TABLE [ERR]"
												fi
											fi
										fi
										
						done						
						
						f_log "Import routines into $BDD"
						if [ -f "$DIR_PWD/$BDD/__routines.sql" ]; then
								mysql --defaults-extra-file=$MYCNF $BDD < $DIR_PWD/$BDD/__routines.sql 2>/dev/null
						fi

						f_log "Import views into $BDD"
						if [ -f "$DIR_PWD/$BDD/__views.sql" ]; then
								mysql --defaults-extra-file=$MYCNF $BDD < $DIR_PWD/$BDD/__views.sql 2>/dev/null
						fi					
						
					fi				
	done

	mysql --defaults-extra-file=$MYCNF -e "flush privileges;"

	f_log "** END **"
}

# === EXECUTE ===
while getopts ":e:c:" opt;
do
	case ${opt} in
		e) 
			exclude=${OPTARG}
			IFS=, read -r -a DATABASES_SKIP <<< "$exclude"
		;;
		c)
			check=1
		;;
		*) 
			usage			
			exit 1
		;;
	esac
done

shift "$((OPTIND - 1))"

# === AUTORUN ===
restore