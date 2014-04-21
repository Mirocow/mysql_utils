mysql_utils
===========

Backup and Restore data from MySql tables

Automation backup with Cron
===========================

nano /etc/default/db_backup

    START=yes

nano /etc/cron.d/db_backup

    @daily      root . /etc/default/db_backup && if [ "$START" = "yes" ] && [ -x /var/www/mysql_utils/backup.sh ]; \
    then /bin/bash /var/www/mysql_utils/backup.sh; fi
