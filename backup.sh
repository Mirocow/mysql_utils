#!/bin/sh

# === CONFIG DEBIAN ===
BCKDIR='/var/backups/mysql'
MYCNF='/etc/mysql/debian.cnf'

# === CONFIG OTHER SERVERS ===
#BCKDIR='./backups'
#MYCNF='./etc/mysql/debian.cnf'

BIN_DEPS="mysql mysqldump $COMPRESS"
DATE=$(date '+%Y.%m.%d')
DATEOLD=$(date --date='1 week ago' +%Y.%m.%d)
DST=$BCKDIR/$DATE
DSTOLD=$BCKDIR/$DATEOLD

# === CHECKS ===
for BIN in $BIN_DEPS; do
    which $BIN 1>/dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "Error: Required file could not be found: $BIN"
        exit 1
    fi
done


if [ ! -d "$DST" ];  then mkdir -p $DST;   fi
if [ -d "$DSTOLD" ]; then rm -fr  $DSTOLD; fi

# === FUNCTION ===
f_log() {
    logger "BACKUP: $@"

    if [ $VERBOSE -ne 0 ]; then
	echo "BACKUP: $@"
    fi
}

usage()
{
cat << EOF
usage: $0 options

This script buckup all databases.

OPTIONS:
   -e      Exclude databases
EOF
}

array_join()
{
	local array_skip=("${@}")	
	for skip in "${array_skip[@]}"; do
		if [ -x $return ]; then
			local return="^$skip\$"
		else
			return="$return|^$skip\$"
		fi
	done
	echo ${return}
}

backup()
{
	f_log "** START **"

	query="SHOW databases;"
	local skip=(
		'information_schema'
		'performance_schema'
		)
	array_skip=( ${skip[@]} ${DATABASES_SKIP[@]} )
	skip_reg=`array_join "${array_skip[@]}"`
	f_log "Skip databases: $skip_reg"

	for BDD in $(mysql --defaults-extra-file=$MYCNF --skip-column-names -B -e "$query" | egrep -v "$skip_reg"); do

			mkdir -p $DST/$BDD 2>/dev/null 1>&2
			chown mysql:mysql $DST/$BDD

			query="SHOW CREATE DATABASE \`$BDD\`;"
			mysql --defaults-extra-file=$MYCNF --skip-column-names -B -e "$query" | \
						awk -F"\t" '{ print $2 }' > $DST/$BDD/__create.sql
			if [ -f $DST/$BDD/__create.sql ]; then
				f_log "  > Export create"
			fi

			query="SHOW FULL TABLES WHERE Table_type = 'VIEW';"
			for viewName in $(mysql --defaults-extra-file=$MYCNF $BDD -N -e "$query" | sed 's/|//' | awk '{print $1}'); do
				mysqldump --defaults-file=$MYCNF $BDD $viewName >> $DST/$BDD/__views.sql
			done
			if [ -f $DST/$BDD/__views.sql ]; then
				f_log "  > Exports views"
			fi

			mysqldump --defaults-file=$MYCNF --routines --no-create-info --no-data --no-create-db --skip-opt $BDD | \
								sed -e  's/DEFINER=[^*]*\*/\*/'  > $DST/$BDD/__routines.sql
			if [ -f $DST/$BDD/__routines.sql ]; then
				f_log "  > Exports Routines"
			fi

			query="SHOW TABLES;"
			for TABLE in $(mysql --defaults-extra-file=$MYCNF --skip-column-names -B $BDD -e "$query" | grep -v slow_log | grep -v general_log); do
					f_log "  ** Dump $BDD.$TABLE"

					mysqldump --defaults-file=$MYCNF -T $DST/$BDD/ $BDD $TABLE

					if [ -f "$DST/$BDD/$TABLE.sql" ]; then
							chmod 750 $DST/$BDD/$TABLE.sql
							chown root:root $DST/$BDD/$TABLE.sql
							f_log "  ** set perm on $BDD/$TABLE.sql"
					else
							f_log "  ** WARNING : $DST/$BDD/$TABLE.sql not found"
					fi

					if [ -f "$DST/$BDD/$TABLE.txt" ]; then
							f_log "  ** $COMPRESS $BDD/$TABLE.txt in background"

							if [ -f "$DST/$BDD/$TABLE.txt.bz2" ]; then
								rm $DST/$BDD/$TABLE.txt.bz2
							fi

							#bzip2 $DST/$BDD/$TABLE.txt &

							$COMPRESS $DST/$BDD/$TABLE.txt &
					else
							f_log "  ** WARNING : $DST/$BDD/$TABLE.txt not found"
					fi

			done

	done

	f_log "** END **"
}

OPTS=`getopt -o Vce: --long verbose,compress,exclude: -n 'parse-options' -- "$@"`

if [ $? != 0 ] ; then echo "Failed parsing options." >&2 ; exit 1 ; fi

echo "$OPTS"
eval set -- "$OPTS"

VERBOSE=0
COMPRESS='bzip2'
DATABASES_SKIP=''

while true; do
  case "$1" in
    -V | --verbose ) VERBOSE=1; shift ;;
    -c | --compress ) COMPRESS="$2"; shift ;;
    -e | --exclude ) DATABASES_SKIP="$2"; shift ;;
    -- ) shift; break ;;
    * ) break ;;
  esac
done

# === SETTINGS ===
echo "Verbose: $VERBOSE\n"
echo "Compress: $COMPRESS\n"
echo "Exclude: $DATABASES_SKIP\n"

# === AUTORUN ===
backup

