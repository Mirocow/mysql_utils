mysql_utils for Debian
=======================

Backup and Restore data from MySql tables

Install
======

    cd ~
    git clone https://github.com/Mirocow/mysql_utils.git
    cd mysql_utils

Backup (All Databases)    
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

nano /etc/cron.d/db_backup

    @daily      root . /etc/default/db_backup && if [ "$START" = "yes" ] && [ -x /root/mysql_utils/backup.sh ]; \
    then /bin/bash /root/mysql_utils/backup.sh; fi

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
        
