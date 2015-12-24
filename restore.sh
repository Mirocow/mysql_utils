#!/bin/sh

# === CONFIG ===
DIR_PWD=$(pwd)
BIN_DEPS='bunzip2 bzip2 mysql'
MYCNF='/etc/mysql/debian.cnf'
MYDATA='/var/lib/mysql'

# === DO NOT EDIT BELOW THIS LINE ===

if [ ! -n "$BASH" ] ;then echo Please run this script $0 with bash; exit 1; fi

# === FUNCTIONS ===
if [ -f '/etc/debian_version' ]; then
    CONFIG_FILE='/etc/mysql/debian.cnf'
else
    CONFIG_FILE='~/mysql_utils/etc/mysql/debian.cnf'
fi

database_exists()
{
	RESULT=`mysqlshow --defaults-extra-file=$MYCNF $@| grep -v Wildcard | grep -o $@`
	if [ "$RESULT" == "$@" ]; then
			echo YES
	else
			echo NO
	fi
}

f_log() 
{
	logger "RESTORE: $@"
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

	for i in $(ls -1 -d $DIR_PWD/*); do
	
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
					
						if [ -f $DIR_PWD/$BDD/__create.sql ]; then
							f_log "Create database $BDD"
							mysql --defaults-extra-file=$MYCNF < $DIR_PWD/$BDD/__create.sql 2>/dev/null
						fi
						
						if [ $(database_exists $BDD) != "YES" ]; then
							f_log "Error: Database $BDD dose not exists";
						else
						
							tables=$(ls -1 $i |  grep -v __ | awk -F. '{print $1}' | sort | uniq)
						
							f_log "Create tables in $BDD"
							for TABLE in $tables; do							
											f_log "Create table: $BDD/$TABLE"
											mysql --defaults-extra-file=$MYCNF $BDD -e "SET foreign_key_checks = 0;
																			DROP TABLE IF EXISTS $TABLE;
																			SOURCE $DIR_PWD/$BDD/$TABLE.sql;
																			SET foreign_key_checks = 1;"
							done
							
							f_log "Import data into $BDD"		
							for TABLE in $tables; do									
											f_log "Import data into $BDD/$TABLE"
												
											if [ -f "$DIR_PWD/$BDD/$TABLE.txt.bz2" ]; then
													f_log "< $TABLE"
													if [ -f "$DIR_PWD/$BDD/$TABLE.txt" ]; then
														rm $DIR_PWD/$BDD/$TABLE.txt
													fi
													bunzip2 $DIR_PWD/$BDD/$TABLE.txt.bz2
											fi
											
											if [ -f "$DIR_PWD/$BDD/$TABLE.txt" ]; then
												f_log "+ $TABLE"
												mysql --defaults-extra-file=$MYCNF $BDD --local-infile -e "SET foreign_key_checks = 0;
																				LOAD DATA LOCAL INFILE '$DIR_PWD/$BDD/$TABLE.txt'
																				INTO TABLE $TABLE;
																				SET foreign_key_checks = 1;"
																														
												if [ ! -f "$DIR_PWD/$BDD/$TABLE.txt.bz2" ]; then
													f_log "> $TABLE"
													bzip2 $DIR_PWD/$BDD/$TABLE.txt
												fi
											fi
											
											if [ $DATABASES_TABLE_CHECK ]; then
												# Check INNODB table
												if [ -f "$MYDATA/$BDD/$TABLE.ibd" ]; then
													if [ ! $(innochecksum $MYDATA/$BDD/$TABLE.ibd) ]; then
														f_log "$TABLE [OK]"
													else
														f_log "$TABLE [ERR]"
													fi
												fi
											fi	
							done						
							
							if [ -f "$DIR_PWD/$BDD/__routines.sql" ]; then
									f_log "Import routines into $BDD"
									mysql --defaults-extra-file=$MYCNF $BDD < $DIR_PWD/$BDD/__routines.sql 2>/dev/null
							fi
							
							if [ -f "$DIR_PWD/$BDD/__views.sql" ]; then
									f_log "Import views into $BDD"
									mysql --defaults-extra-file=$MYCNF $BDD < $DIR_PWD/$BDD/__views.sql 2>/dev/null
							fi
							
						fi
					fi				
	done

	f_log "Flush privileges;"
	mysql --defaults-extra-file=$MYCNF -e "flush privileges;"

	f_log "** END **"
}

# === EXECUTE ===
while getopts ":e:c:s:" opt;
do
	case ${opt} in
		e) 
			exclude=${OPTARG}
			IFS=, read -r -a DATABASES_SKIP <<< "$exclude"
		;;
		s)
			selected=${OPTARG}
			IFS=, read -r -a DATABASES_SELECTED <<< "$selected"		
		;;
		c)
			DATABASES_TABLE_CHECK=1
		;;
		*) 
			usage			
			exit 1
		;;
	esac
done
#shift "$((OPTIND - 1))"

# === AUTORUN ===
restore
