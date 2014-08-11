mysql_utils for Debian or Other servers
=======================================

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

Restore selected table
=======

    cd /var/backups/mysql/[some date]/[some db name]
    bash ~/mysql_utils/restore_table.sh

Automation backup with Cron
===========================

nano /etc/default/db_backup

    START=yes

nano /etc/cron.daily/db_backup

    #!/bin/sh

    . /etc/default/db_backup
    
    if [ "$START" = "yes" ]; then
    	logger "Start databases backup system..."
    	/bin/bash /root/scripts/mysql_utils/backup.sh -e tecdoc.2013
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
