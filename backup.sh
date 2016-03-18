#!/bin/bash

if [ ! -n "$BASH" ] ;then echo Please run this script $0 with bash; exit 1; fi

function create_site()
{

    site_name=$HOST
	site_addr=$IP

	authpassword=$(date +%s | sha256sum | base64 | head -c 6 ; echo)
	sleep 1
	password=$(date +%s | sha256sum | base64 | head -c 16 ; echo)

	deluser ${site_name}
	rm -r /home/${site_name}
	mkdir /home/${site_name}
	mkdir /home/${site_name}/logs
	mkdir /home/${site_name}/httpdocs
	mkdir /home/${site_name}/httpdocs/web
	useradd -d /home/${site_name} ${site_name}
	usermod -G www-data ${site_name}
	echo ${site_name}:${password} | chpasswd
	mkdir /home/${site_name}/.ssh
	chmod 0700 /home/${site_name}/.ssh
	ssh-keygen -t rsa -N "${site_name}" -f /home/${site_name}/.ssh/id_rsa
	chmod 0600 /home/${site_name}/.ssh/id_rsa
	ssh-keygen -t dsa -N "${site_name}" -f /home/${site_name}/.ssh/id_dsa	
	chmod 0600 /home/${site_name}/.ssh/id_dsa
	echo  "<?php phpinfo();" > /home/${site_name}/httpdocs/web/index.php
	php -r 'echo "admin:" . crypt("${authpassword}", "salt") . ": Web auth for ${site_name}";' > /home/${site_name}/authfile
	chown ${site_name}:www-data -R /home/${site_name}

	#service php5-fpm stop
	#service apache2 stop

	if [ $APACHE -eq 1 ]; then
echo "
<VirtualHost 127.0.0.1:8080>
		ServerName ${site_name}
		ServerAlias www.${site_name}
		ServerAdmin info@reklamu.ru
		DocumentRoot /home/${site_name}/httpdocs/web
		<Directory /home/${site_name}/httpdocs/web>
				Options Indexes FollowSymLinks MultiViews
				Options FollowSymLinks
				AllowOverride All
				Options +ExecCGI -MultiViews +SymLinksIfOwnerMatch
				Order allow,deny
				Allow from all
		</Directory>

		ErrorLog \${APACHE_LOG_DIR}/${site_name}-error.log

		# Possible values include: debug, info, notice, warn, error, crit,
		# alert, emerg.
		LogLevel warn

		CustomLog \${APACHE_LOG_DIR}/${site_name}-access.log combined
</VirtualHost>
" > /etc/apache2/sites-enabled/${site_name}.conf

main="
				# Apache back-end
				location / {
						proxy_pass  http://127.0.0.1:8080;
						proxy_ignore_headers   Expires Cache-Control;
						proxy_set_header        Host            \$host;
						proxy_set_header        X-Real-IP       \$remote_addr;
						proxy_set_header        X-Forwarded-For \$proxy_add_x_forwarded_for;
				}				
				location ~* \.(js|css|png|jpg|jpeg|gif|ico|swf)\$ {
						expires 1y;
						log_not_found off;
						proxy_pass  http://127.0.0.1:8080;
						proxy_ignore_headers   Expires Cache-Control;
						proxy_set_header        Host            \$host;
						proxy_set_header        X-Real-IP       \$remote_addr;
						proxy_set_header        X-Forwarded-For \$proxy_add_x_forwarded_for;
				}
				location ~* \.(html|htm)\$ {
						expires 1h;
						proxy_pass  http://127.0.0.1:8080;
						proxy_ignore_headers   Expires Cache-Control;
						proxy_set_header        Host            \$host;
						proxy_set_header        X-Real-IP       \$remote_addr;
						proxy_set_header        X-Forwarded-For \$proxy_add_x_forwarded_for;
				}
"		
	else
echo "## php-fpm config for ${site_name}
[${site_name}]

user = ${site_name}
group = www-data

listen = /var/run/php-fpm-${site_name}.sock
listen.mode = 0666

pm = dynamic
pm.max_children = 250
pm.start_servers = 8
pm.min_spare_servers = 8
pm.max_spare_servers = 16

chdir = /
security.limit_extensions = false
php_flag[display_errors] = on
php_admin_value[error_log] = /home/${site_name}/logs/fpm-php.${site_name}.log
php_admin_flag[log_errors] = on
" > /etc/php5/fpm/pool.d/${site_name}.conf
		
main="
				# With PHP-FPM
				location / {
						index index.php;
						#auth_basic \"Website development\"; 
						#auth_basic_user_file /home/${site_name}/authfile;
						try_files \$uri \$uri/ /index.php?\$query_string;
				}
				
				# PHP fastcgi
				location ~ \.php {
						#try_files \$uri =404;
						include fastcgi_params;
						# Use your own port of fastcgi here
						#fastcgi_pass 127.0.0.1:9000;
						
						fastcgi_pass unix:/var/run/php-fpm-${site_name}.sock;
						fastcgi_index index.php;
						fastcgi_split_path_info ^(.+\.php)(/.+)$;
						fastcgi_param PATH_INFO \$fastcgi_path_info;
						fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
				}				
"
	fi

awstats="# Awstats
server {
				listen ${site_addr};
				server_name  awstats.${site_name};
				
				auth_basic            \"Restricted\";
				auth_basic_user_file  /home/${site_name}/authfile;

				access_log /var/log/nginx/access.awstats.${site_name}.log;
				error_log /var/log/nginx/error.awstats.${site_name}.log;                

				location / {
						root   /home/${site_name}/awstats/;
						index  awstats.html;
						access_log off;
				}

				location  /awstats-icon/ {
						alias  /usr/share/awstats/icon/;
						access_log off;
				}
				
				# apt-get install 
				location ~ ^/cgi-bin {
						access_log off;
						fastcgi_pass   unix:/var/run/fcgiwrap.socket;
						include /etc/nginx/fastcgi_params;
						fastcgi_param  SCRIPT_FILENAME  /usr/lib\$fastcgi_script_name;
				}
}
"

echo "
${awstats}

# Rerirect www.${site_name}
server {
				listen ${site_addr};
				server_name ${site_name};
				return 301 http://www.${site_name}\$request_uri;
}

# Site www.${site_name}
server {
				listen ${site_addr};
				server_name www.${site_name};
				root /home/${site_name}/httpdocs/web;
				index index.php;
				access_log /home/${site_name}/logs/access.log;
				error_log  /home/${site_name}/logs/error.log error;
				charset utf-8;
				#charset        windows-1251;
				location = /favicon.ico {
						log_not_found off;
						access_log off;
						break;
				}
				location = /robots.txt {
						allow all;
						log_not_found off;
						access_log off;
				}					
				${main}					
				location ~ /(protected|themes/\w+/views)/ {
						access_log off;
						log_not_found off;
						return 404;
				}
				#
				location ~ \.(xml)\$ {
						expires 24h;
						charset windows-1251;
						#log_not_found off;
						#try_files \$uri =404;
						#try_files \$uri \$uri/ /index.php?\$query_string;
				}
				# 
				location ~ \.(js|css|png|jpg|gif|swf|ico|pdf|mov|fla|zip|rar)\$ {
						expires 24h;
						#log_not_found off;
						#try_files \$uri =404;
						try_files \$uri \$uri/ /index.php?\$query_string;
				}

				# Hide all system files
				location  ~ /\. {
						deny  all;
						access_log off;
						log_not_found off;
				}
}
" > /etc/nginx/conf.d/${site_name}.conf

	service php5-fpm reload
	service apache2 reload
	service nginx reload
	
	echo ""
	echo "--------------------------------------------------------"
	echo "User:"
	echo "Login: ${site_name}"
	echo "Password: ${password}"
	echo "Path: /home/${site_name}/"
	echo "SSH Private file: /home/${site_name}/.ssh/id_rsa"
	echo "SSH Public file: /home/${site_name}/.ssh/id_rsa.pub"
	echo "Server:"
	echo "Site root: /home/${site_name}/httpdocs/web"
	echo "Site logs path: /home/${site_name}/logs"
	if [ $APACHE -eq 1 ]; then
		echo "Back-end server: Apache 2"
		echo "/etc/apache2/sites-enabled/${site_name}.conf"
	else
		echo "Back-end server: PHP-FPM"
	fi
	echo "Web auth: admin ${authpassword}"
	echo "Statistic:"
	echo "awstats.${site_name}"
	echo "Add crontab task: */20 * * * * /usr/lib/cgi-bin/awstats.pl -config=${site_name} -update > /dev/null"
	echo "--------------------------------------------------------"
	echo ""

}

usage()
{
cat << EOF
usage: $0 options

This script create settings files for nginx, php-fpm, apache2.

OPTIONS:
   -n | --host      Host name
   -i | --ip        IP address, default usage 80
   -a | --apache    Usage apache back-end
   -h | --help      Usage


EOF
}

if [ $# = 0 ]; then
    usage
    exit
fi

HOST=''
IP='80'
APACHE=0

for i in "$@"
do
    case $i in
	-n=* | --host=*)
	    HOST=( "${i#*=}" )
	    shift
	;;
	-i=* | --ip=*)
	    IP=( "${i#*=}" )
		$IP="${IP}:80"
	    shift
	;;	
	-a | --apache)
	    APACHE=1
	    shift
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

# === AUTORUN ===
create_site
