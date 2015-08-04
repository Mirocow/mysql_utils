#!/bin/sh

# === CONFIG ===
DIR_PWD=$(pwd)
BIN_DEPS='bunzip2 bzip2 mysql'
MYCNF='/etc/mysql/debian.cnf'
DATABASES_TABLE_CHECK=1

f_log()
{
	echo "RESTORE: $@"
}

restore()
{
  PATH=$@

  f_log "Check path $PATH"

  BDD=${PATH##*/}

  if [ $BDD ]; then

    f_log "Found backup files $PATH"

    if [ -f $PATH/__create.sql ]; then
      f_log "Create database $BDD"
      /usr/bin/mysql --defaults-extra-file=$MYCNF < $PATH/__create.sql 2>/dev/null
    fi

    tables=$(/bin/ls -1 $PATH |  /bin/grep -v __ | /usr/bin/awk -F. '{print $1}' | /usr/bin/sort | /usr/bin/uniq)

    f_log "Create tables in $BDD"
    for TABLE in $tables; do
            f_log "Create table: $BDD/$TABLE"
            /usr/bin/mysql --defaults-extra-file=$MYCNF $BDD -e "SET foreign_key_checks = 0;
                            DROP TABLE IF EXISTS $TABLE;
                            SOURCE $PATH/$TABLE.sql;
                            SET foreign_key_checks = 1;"
    done

    f_log "Import data into $BDD"
    for TABLE in $tables; do
            f_log "Import data into $BDD/$TABLE"
            if [ -f "$PATH/$TABLE.txt.bz2" ]; then
                f_log "< $TABLE"
                if [ -f "$PATH/$TABLE.txt" ]; then
                  f_log "rm $PATH/$TABLE.txt"
                  /bin/rm $PATH/$TABLE.txt
                fi
                /bin/bunzip2 $PATH/$TABLE.txt.bz2
            fi

            if [ -f "$PATH/$TABLE.txt" ]; then
              f_log "+ $TABLE"
              /usr/bin/mysql --local-infile --defaults-extra-file=$MYCNF $BDD -e "SET foreign_key_checks = 0;
                              LOAD DATA LOCAL INFILE '$PATH/$TABLE.txt'
                              INTO TABLE $TABLE;
                              SET foreign_key_checks = 1;"

              if [ ! -f "$PATH/$TABLE.txt.bz2" ]; then
                f_log "> $TABLE"
                /bin/bzip2 $PATH/$TABLE.txt
              fi
            fi
            if [ $DATABASES_TABLE_CHECK ]; then
              # Check INNODB table
              if [ -f "$PATH/$TABLE.ibd" ]; then
                if [ ! $(innochecksum $PATH/$TABLE.ibd) ]; then
                  f_log "$TABLE [OK]"
                else
                  f_log "$TABLE [ERR]"
                fi
              fi
            fi
    done

    if [ -f "$PATH/__routines.sql" ]; then
        f_log "Import routines into $BDD"
        /usr/bin/mysql --defaults-extra-file=$MYCNF $BDD < $PATH/__routines.sql 2>/dev/null
    fi

    if [ -f "$PATH/__views.sql" ]; then
        f_log "Import views into $BDD"
        /usr/bin/mysql --defaults-extra-file=$MYCNF $BDD < $PATH/__views.sql 2>/dev/null
    fi

    f_log "Flush privileges;"
    /usr/bin/mysql --defaults-extra-file=$MYCNF -e "flush privileges;"

    f_log "** END **"

  else

    f_log "Database not found"

  fi
}

restore $DIR_PWD
