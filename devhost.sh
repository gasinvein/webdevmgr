#!/bin/bash -ex

templates_dir="$(dirname $0)/templates"

DOMAIN="dev.example.com"

function aa_profile {
	vhostname="$2"
	case $1 in
		create)
			echo "Creating apparmor profile"
			sed "s/_VHOSTNAME_/$vhostname/g" "$templates_dir/apparmor_profile" > "/etc/apparmor.d/apache2.d/$vhostname"
		;;
		delete)
			echo "Deleting apparmor profile"
			rm "/etc/apparmor.d/apache2.d/$vhostname"
		;;
	esac
	apparmor_parser -r "/etc/apparmor.d/usr.sbin.apache2"
}

function apache_vhost {
	vhostname="$2"
	case $1 in
		create)
			echo "Creating apache2 virtualhost"
			sed -e "s/_VHOSTNAME_/$vhostname/g" -e "s/_DOMAIN_/$DOMAIN/g" "$templates_dir/apache_vhost.conf" > "/etc/apache2/sites-available/$vhostname.conf"
			a2ensite "$vhostname.conf"
		;;
		delete)
			echo "Deleting apache2 virtualhost"
			a2dissite "$vhostname.conf"
			rm "/etc/apache2/sites-available/$vhostname.conf"
		;;
	esac
	systemctl reload apache2
}

function mysql_db {
	vhostname="$2"
	mysql_sys_user="root"
	mysql_socket="/var/run/mysqld/mysqld.sock"
	case $1 in
		create)
			echo "Creating mysql database and user"
			new_user_name="$vhostname"
			new_user_passwd="$(tr -dc 'a-zA-Z0-9' < /dev/urandom | fold -w 12 | head -n 1)"
			mysql --socket $mysql_socket -u $mysql_sys_user -e \
				"CREATE DATABASE \`$vhostname\` CHARACTER SET utf8 COLLATE utf8_general_ci;"
			mysql --socket $mysql_socket -u $mysql_sys_user -e \
				"GRANT ALL ON \`$vhostname\`.* TO \`$vhostname\`@localhost IDENTIFIED BY \"$new_user_passwd\";"
			export deleteme="Database: $vhostname User: $new_user_name Password: $new_user_passwd"
		;;
		delete)
			echo "Deleting mysql database and user"
			mysql --socket $mysql_socket -u $mysql_sys_user -e \
				"DROP DATABASE IF EXISTS \`$vhostname\`;"
			mysql --socket $mysql_socket -u $mysql_sys_user -e \
				"DROP USER IF EXISTS \`$vhostname\`;"
		;;
	esac
}

function snapper_subvol {
	vhostname="$2"
	case $1 in
		create)
			echo "Creating webroot subvolume"
			btrfs subvolume create "/var/www/$vhostname"
			snapper -c "www-$vhostname" create-config "/var/www/$vhostname"
			chown www-data:www-data "/var/www/$vhostname"
			setfacl -m 'u:www-data:r-x' "/var/www/$vhostname/.snapshots"
			setfacl -m 'g:www-data:r-x' "/var/www/$vhostname/.snapshots"
			sudo -u www-data mkdir "/var/www/$vhostname/tmp"
			echo "$deleteme" > "/var/www/$vhostname/DELETE_ME.txt"
			chown www-data:www-data "/var/www/$vhostname/DELETE_ME.txt"
		;;
		delete)
			echo "Deleting webroot subvolume"
			snapper -c "www-$vhostname" delete-config
			btrfs subvolume delete "/var/www/$vhostname"
		;;
	esac
}

vhostaction="$1"
vhostname="$2"

if [ -z "$vhostname" ]; then
	echo "Vhost name must contain at least one char."
	exit 1
fi

case $vhostaction in
	create)
		aa_profile create $vhostname
		apache_vhost create $vhostname
		mysql_db create $vhostname
		snapper_subvol create $vhostname
	;;
	delete)
		aa_profile delete $vhostname
		apache_vhost delete $vhostname
		mysql_db delete $vhostname
		snapper_subvol delete $vhostname
	;;
esac
