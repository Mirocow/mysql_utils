mysql_utils for Debian or Other OS
=======================================

Russian documentation: http://docs.mirocow.com/doku.php?id=mysql:mysql_utils

Backup and Restore data from MySql tables

Install
======

    cd ~
    git clone https://github.com/Mirocow/mysql_utils.git
    cd mysql_utils

Backup all databases   
======

    cd ~
    cd mysql_utils
    bash backup.sh

Restore for selected date
=======

    cd /var/backups/mysql/[some date]
    bash ~/mysql_utils/restore.sh

Restore selected DB
=======

    cd /var/backups/mysql/[some date]/[some db name]
    bash ~/mysql_utils/restore_db.sh

Automation backup with Cron
===========================

nano /etc/default/db_backup

    START=yes

nano /etc/cron.daily/db_backup

    #!/bin/sh

    . /etc/default/db_backup
    
    if [ "$START" = "yes" ]; then
    	logger "Start databases backup system..."
    	/bin/bash /root/scripts/mysql_utils/backup.sh --e="some_exclude_database some_else_db"
    fi

Check work
==========

    # tail -f /var/log/syslog
        May 23 12:25:34 db1 logger: BACKUP:   ** Dump tecdoc.2013.ALI_COORD
        May 23 12:25:35 db1 logger: BACKUP:   ** set perm on tecdoc.2013/AL
        May 23 12:25:35 db1 logger: BACKUP:   ** bzip2 tecdoc.2013/ALI_COOR
        May 23 12:25:35 db1 logger: BACKUP:   ** Dump tecdoc.2013.ARTICLES
        May 23 12:25:43 db1 logger: BACKUP:   ** set perm on tecdoc.2013/AR
        May 23 12:25:43 db1 logger: BACKUP:   ** bzip2 tecdoc.2013/ARTICLES
        May 23 12:25:43 db1 logger: BACKUP:   ** Dump tecdoc.2013.ARTICLES_
        May 23 12:25:43 db1 logger: BACKUP:   ** set perm on tecdoc.2013/AR
        May 23 12:25:43 db1 logger: BACKUP:   ** bzip2 tecdoc.2013/ARTICLES
        May 23 12:25:43 db1 logger: BACKUP:   ** Dump tecdoc.2013.ARTICLE_C
        
Tested on
==========

    Debiad
    FreeBsd
    Ubuntu

Help
===========

``` sh
# bash backup.sh --help
usage: backup.sh options

This script buckup all databases.

Usage: backup.sh <[options]>

Options:
   -e= | --exclude=                     Exclude databases
   --exclude-tables=                    Exclude tables
   -c= | --compress=                    Compress with gzip or bzip2
   -v  | --verbose                      Add verbose into output
   -l  | --lifetime=                    Lifetime for dump files
   --config=                            Config file of Debian format
   --dir=                               Backup directory
   -h  | --help                         This text

Examples:
        backup.sh --verbose --compress=
        backup.sh --verbose --compress=zgip
        backup.sh --verbose --compress=bzip2
        backup.sh --verbose --compress= --exclude="mysql"
        backup.sh --verbose --compress= --exclude="mysql" --lifetime="3 day ago"
        backup.sh --verbose --config="/etc/mysql/debian.cnf" --exclude="mysql" --lifetime="1 day ago"
        backup.sh --verbose --dir="/var/backups/mysql" --config="/etc/mysql/debian.cnf" --exclude="mysql" --lifetime="1 day ago"
        backup.sh --verbose --dir="/home/backups/mysql" --exclude="mysql" --lifetime="1 day ago"
        backup.sh --verbose --dir="/home/backups/mysql" --exclude="mysql" --exclude-tables="tbl_template" --lifetime="1 day ago"
```
