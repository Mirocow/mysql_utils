
mysql_utils for Debian
=======================

Backup and Restore data from MySql tables

Install
======

    cd ~
    git clone https://github.com/Mirocow/mysql_utils.git
    cd mysql_utils
    bash ./backup.sh

Backup    
======

    cd ~
    cd mysql_utils
    bash backup.sh

Restore
=======

    cd /var/backups/mysql
    bash ~/mysql_utils/restore.sh

Automation backup with Cron
===========================

nano /etc/default/db_backup

    START=yes

nano /etc/cron.d/db_backup

    @daily      root . /etc/default/db_backup && if [ "$START" = "yes" ] && [ -x /var/www/mysql_utils/backup.sh ]; \
    then /bin/bash /var/www/mysql_utils/backup.sh; fi
