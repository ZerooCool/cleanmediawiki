#!/bin/sh
: <<SCRIPTHEADER
Description: Users activity and accounts cleaner for MediaWiki
 Deletes specified user accounts ID and their pages, revisions,
 changes, and related indexes and cache.
 Tested with MediaWiki 1.16 to 1.19 but acts respectful with any version.
 Idea taken from
 http://stackoverflow.com/questions/4505210/mediawiki-rollback-bot-mass-undo-troll-actions
Version: 2014.04.08
Maintainer: Narcis Garcia <spam@actiu.net>
Depends: coreutils, grep, mysql-client
Recommends: bsd-mailx
Section: web
Architecture: all
Copyright: Narcis Garcia (2013)
Homepage: http://www.actiu.net/mediawiki/
License: GNU GPL
 This program is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.
 .
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
 .
 You should have received a copy of the GNU General Public License
 along with this program.  If not, see <http://www.gnu.org/licenses/>.
Changelog: 2013.10.15 Avoid errors with any MW version
  Detailed operations to see all the progress.
  Tables prefix support
 2013.10.13 First version for MediaWiki 1.19.2
SCRIPTHEADER


# Database structure described at https://www.mediawiki.org/wiki/Manual:Database_layout

# Desarrollo en: utilitats/instals.gnu/utilitats_sh/nomes-servidors/

# PENDIENTE:
#	- En tablas como revision o archive se marca como usuario 0 las
#	  contribuciones de anónimos y scripts de instalación/importación;
#	  Averiguar si ello vale para todas las tablas con IDs de usuario.
#	- Abordar todas las tablas posibles.

##### IMPORTED FUNCTIONS from ngl-funcions 2013.01.10 #####

ReturnScriptHeader ()
# Syntax as a command: ReturnScriptHeader $File $HeaderName
# Description: Returns (echo) the first line of a labeled header in a script file.
# Depends: coreutils, sed
# Depends on functions: (none)
# Notes:
#  - Is not sensitive capital or low case letters.
#  - If no $HeaderName is specified, returns the whole headers.
{
	local File="$1"
	local HeaderName="$2"
	local AllHeaders=""
	local Value=""
	local Result=0
	
	if [ -f "$File" ] ; then
		AllHeaders="$(cat "$File" | grep -e '^SCRIPTHEADER$' --before-context=100 | grep -e 'SCRIPTHEADER$' --after-context=100)"
		AllHeaders="$(echo  "$AllHeaders" | grep -ve '^SCRIPTHEADER$' | grep -ve 'SCRIPTHEADER$')"
		if [ "$HeaderName" != "" ] ; then
			Value="$(echo "$AllHeaders" | grep -ie "^${HeaderName}:" | cut -f 2- -d ':')"
			if [ "$(echo "$Value" | grep -e '^ ')" != "" ] ; then
				Value="$(echo "$Value" | cut --characters=2-)"
			fi
		else
			Value="$AllHeaders"
		fi
		if [ "$Value" != "" ] ; then
			echo "$Value"
		fi
	else
		Result=1
	fi
	return $Result
}

Which ()
# Syntax as a funcion: $(Which "$Program")
# Descripcion: Arranged copy of the debianutils' "which" to not depend of debianutils
# Depends: coreutils
# Depends on functions: (none)
# Notes: There is an alternative to check an executable with path;
#  Example:
#  if test -x /usr/bin/nano && ! test -d /usr/bin/nano ; then echo "TRUE" ; fi
{
	set -ef
	
        puts() {
                printf '%s\n' "$*"
        }
	
	ALLMATCHES=0
	
	while getopts a whichopts
	do
		case "$whichopts" in
			a) ALLMATCHES=1 ;;
			?) puts "Usage: $0 [-a] args"; exit 2 ;;
		esac
	done
	shift $(($OPTIND - 1))
	
	if [ "$#" -eq 0 ]; then
		ALLRET=1
	else
		ALLRET=0
	fi
	case $PATH in
		(*[!:]:) PATH="$PATH:" ;;
	esac
	for PROGRAM in "$@"; do
		RET=1
		IFS_SAVE="$IFS"
		IFS=:
		case $PROGRAM in
			*/*)
				if [ -f "$PROGRAM" ] && [ -x "$PROGRAM" ]; then
					puts "$PROGRAM"
					RET=0
				fi
				;;
			*)
				for ELEMENT in $PATH; do
					if [ -z "$ELEMENT" ]; then
						ELEMENT=.
					fi
					if [ -f "$ELEMENT/$PROGRAM" ] && [ -x "$ELEMENT/$PROGRAM" ]; then
						puts "$ELEMENT/$PROGRAM"
						RET=0
						[ "$ALLMATCHES" -eq 1 ] || break
					fi
				done
				;;
		esac
		IFS="$IFS_SAVE"
		if [ "$RET" -ne 0 ]; then
			ALLRET=1
		fi
	done
	
	return "$ALLRET"
}

DependenciasFaltan ()
# Sintaxis como función: $(DependenciasFaltan "$ListaDependencias")
# Descripción:
#	Comprueba la disponibilidad de los programas especificados y
#	devuelve (echo) una lista de los que faltan. Si se encuentra todo
#	no devuelve nada.
# Parámetros esperados:
#	$1	Lista separada por espacios de cada ejecutable y paquete respectivo,
#		separados entre si por "/"
#		Para varias opciones de ejecutable, separarlos entre ":"
# Depends on functions: Which
# Depends on other software: coreutils
# Ejemplo1:	$(DependenciasFaltan "cat/coreutils grep/grep dpkg-deb/dpkg")
#		puede devolver "grep dpkg[dpkg-deb]" si faltan grep y dpkg-deb
# Ejemplo2:	$(DependenciasFaltan "insserv:update-rc.d/sysv-rc cat/coreutils")
#		puede devolver "sysv-rc[update-rc.d]" si tanto falta insserv como update-rc.d
{
	local ListaDependencias="$1"
	local DependenciaActual=""
	local EjecutablesActuales=""
	local EjecutableActual=""
	local EncontradoActual=""
	local PaqueteActual=""
	local Valor=""
	
	for DependenciaActual in $ListaDependencias ; do
		EjecutablesActuales="$(echo "$DependenciaActual" | cut -f 1 -d "/")"
		PaqueteActual="$(echo "$DependenciaActual" | cut -f 2 -d "/")"
		EjecutablesActuales="$(echo "$EjecutablesActuales" | tr -s ":" " ")"
		EncontradoActual=""
		for EjecutableActual in $EjecutablesActuales ; do
			if [ "$(Which "$EjecutableActual")" != "" ] ; then
				EncontradoActual="1"
			fi
		done
		if [ "$EncontradoActual" = "" ] ; then
			if [ "$(echo " $Valor " | grep -e " $PaqueteActual\[")" = "" ] || [ "$(echo " $Valor " | grep -e " $PaqueteActual ")" = "" ] ; then
				if [ "$$EjecutableActual" = "$PaqueteActual" ] ; then
					Valor="$Valor $PaqueteActual"
				else
					Valor="$Valor $PaqueteActual[$EjecutableActual]"
				fi
			fi
		fi
	done
	if [ "$Valor" != "" ] ; then
		echo $Valor
	fi
}


##### SPECIFIC FUNCTIONS TO THIS SCRIPT #####

CleanMediaWiki()
{
	local DB_DbName=$1
	local FromUser=$2
	local ToUser=$3
	local DB_UserName="$4"
	local DB_Password="$5"
	local NotifyEmail="$6"
	local TablesPrefix="$7"
	local DB_Server="$8"
	local TempData=""
	local Result=0
	local ResultN=0
	
	if [ "$NotifyEmail" != "" ] && [ "$(which mail)" = "" ] ; then
		echo "ERROR: NotifyEmail specified but mail command not found."
		exit 1
	fi
	if [ "$DB_UserName" = "" ] ; then
		echo 'MySQL username to use:'
		read DB_UserName
	fi
	if [ "$DB_Password" = "" ] ; then
		echo 'MySQL password to use (visible):'
		read DB_Password
	fi
	if [ "$DB_Server" = "" ] ; then
		DB_Server="localhost"
	fi
	if [ $ResultN -eq 0 ] ; then
		# Check for SQL access and lookup database tables
		TablesList="$(mysql --batch --skip-column-names "--host=${DB_Server}" "--user=${DB_UserName}" "--password=${DB_Password}" -e "SELECT TABLE_NAME FROM information_schema.TABLES WHERE TABLE_SCHEMA = \"$DB_DbName\";")"
		Result=$? ; if [ $ResultN -eq 0 ] ; then ResultN=$Result ; fi
	fi
	if [ $ResultN -eq 0 ] ; then
		# Check if there are Mediawiki tables
		mysql "--host=${DB_Server}" "--user=${DB_UserName}" "--password=${DB_Password}" -e "SELECT ar_user FROM ${DB_DbName}.${TablesPrefix}archive WHERE 1 = 0;"
		Result=$? ; if [ $ResultN -eq 0 ] ; then ResultN=$Result ; fi
		if [ $Result -ne 0 ] ; then
			echo "PROBLEM: Mediawiki tables not found."
		fi
	fi
	if [ "$NotifyEmail" != "" ] ; then
		if [ $ResultN -eq 0 ] ; then
			echo "cleanmediawiki begins for database ${DB_DbName}" | mail -s "Wiki ${DB_DbName}: begin cleaning job" "$NotifyEmail"
		fi
	fi
	if [ $ResultN -eq 0 ] ; then
		echo '(1/9) Previous actions...'
		echo '	Making temporary backup, to restore in case of SQL error...'
		cat /dev/null > "/tmp/cleanmediawiki.${DB_DbName}.sql"
		chmod u=rw,go= "/tmp/cleanmediawiki.${DB_DbName}.sql"
		echo "DROP DATABASE IF EXISTS \"${DB_DbName}\";" >> "/tmp/cleanmediawiki.${DB_DbName}.sql"
		echo "CREATE DATABASE \"${DB_DbName}\";" >> "/tmp/cleanmediawiki.${DB_DbName}.sql"
		echo "USE \"${DB_DbName}\";" >> "/tmp/cleanmediawiki.${DB_DbName}.sql"
		echo "" >> "/tmp/cleanmediawiki.${DB_DbName}.sql"
		mysqldump "--host=${DB_Server}" --user=${DB_UserName} --password=${DB_Password} -f --hex-blob -q --add-drop-table --add-locks --create-options -K --single-transaction "${DB_DbName}" >> "/tmp/cleanmediawiki.${DB_DbName}.sql"
		Result=$? ; if [ $ResultN -eq 0 ] ; then ResultN=$Result ; fi
		if [ $Result -ne 0 ] ; then
			rm -f "/tmp/cleanmediawiki.${DB_DbName}.sql"
		fi
	fi
	
	if [ $ResultN -eq 0 ] && [ "$ToUser" = "+" ] ; then
		CurrentTable1="${TablesPrefix}mwuser"
		if [ "$(echo "$TablesList" | grep -e "^${CurrentTable1}$")" = "" ] ; then CurrentTable1="${TablesPrefix}user" ; fi
		if [ "$(echo "$TablesList" | grep -e "^${CurrentTable1}$")" != "" ] ; then
			echo '	Finding last user Id...'
			ToUser="$(mysql --batch --skip-column-names "--host=${DB_Server}" "--user=${DB_UserName}" "--password=${DB_Password}" -e "SELECT user_id FROM ${DB_DbName}.${CurrentTable1} ORDER BY user_id ASC;" | tail --lines=1)"
			if [ "$ToUser" != "" ] ; then
				[ "$ToUser" -eq "$ToUser" ] > /dev/null 2>&1
				Result=$? ; if [ $ResultN -eq 0 ] ; then ResultN=$Result ; fi
				if [ $Result -ne 0 ] ; then
					echo "ERROR: Bad user_id $ToUser"
				else
					if [ $ToUser -lt $FromUser ] ; then ToUser=$FromUser ; fi
					echo "	Users ID range for cleaning: from $FromUser to $ToUser"
				fi
			else
				Result=1 ; if [ $ResultN -eq 0 ] ; then ResultN=$Result ; fi
				echo "ERROR: user_id not found in ${DB_DbName}.${CurrentTable1}"
			fi
		else
			echo "Table \"${CurrentTable1}\" not found. Skipping from clean process."
		fi
	fi
	
	if [ $ResultN -eq 0 ] ; then
		if [ $FromUser -le 1 ] && [ $ToUser -ge 1 ] ; then
			CurrentTable1="${TablesPrefix}mwuser"
			if [ "$(echo "$TablesList" | grep -e "^${CurrentTable1}$")" = "" ] ; then CurrentTable1="${TablesPrefix}user" ; fi
			TempData="$(mysql --batch --skip-column-names "--host=${DB_Server}" "--user=${DB_UserName}" "--password=${DB_Password}" -e "SELECT user_name FROM ${DB_DbName}.${CurrentTable1} WHERE user_id = 1;")"
			echo "CAUTION: Selected users range include first adminitrator (${TempData})"
			echo "To really continue, Write: yes"
			read TempData
			if [ "$TempData" != "yes" ] && [ "$TempData" != "YES" ] ; then
				echo "Cleaning process aborted."
				Result=$? ; if [ $ResultN -eq 0 ] ; then ResultN=$Result ; fi
			fi
		fi
	fi

	if [ $ResultN -eq 0 ] ; then
		echo ''
		CurrentTable1="${TablesPrefix}mwuser"
		if [ "$(echo "$TablesList" | grep -e "^${CurrentTable1}")" = "" ] ; then CurrentTable1="${TablesPrefix}user" ; fi
		if [ "$(echo "$TablesList" | grep -e "^${CurrentTable1}$")" != "" ] ; then
			echo '(2/9) Locking selected accounts...'
			echo "	ressetting e-mail addresses..."
			mysql "--host=${DB_Server}" "--user=${DB_UserName}" "--password=${DB_Password}" -e "UPDATE ${DB_DbName}.${CurrentTable1} SET user_email = 'disabled@example.net' WHERE (user_id >= $FromUser AND user_id <= $ToUser);"
			Result=$? ; if [ $ResultN -eq 0 ] ; then ResultN=$Result ; fi
	#		printf "-"
	#		mysql "--host=${DB_Server}" "--user=${DB_UserName}" "--password=${DB_Password}" -e "UPDATE ${DB_DbName}.${CurrentTable1} SET user_password = \"$DB_Password\" WHERE (user_id >= $FromUser AND user_id <= $ToUser);"
	#		Result=$? ; if [ $ResultN -eq 0 ] ; then ResultN=$Result ; fi
			echo "	changing access passwords..."
			mysql "--host=${DB_Server}" "--user=${DB_UserName}" "--password=${DB_Password}" -e "UPDATE ${DB_DbName}.${CurrentTable1} SET user_password = CONCAT(':A:', MD5(\"${DB_Password}\")) WHERE (user_id >= $FromUser AND user_id <= $ToUser);"
			Result=$? ; if [ $ResultN -eq 0 ] ; then ResultN=$Result ; fi
		else
			echo "(2/9) Skipping table $CurrentTable1 from clean process (not found)."
		fi
	fi
	
	if [ $ResultN -eq 0 ] ; then
		echo ''
		CurrentTable1="${TablesPrefix}page"
		CurrentTable2="${TablesPrefix}revision"
		if [ "$(echo "$TablesList" | grep -e "^${CurrentTable1}$")" != "" ] && [ "$(echo "$TablesList" | grep -e "^${CurrentTable2}$")" != "" ] ; then
			echo "(3/9) For all pages (affected by EACH selected user) activities set last revision to the last untouched one..."
			CurrentUser=$ToUser
			while [ $CurrentUser -ge $FromUser ] && [ $ResultN -eq 0 ] ; do
				printf "3_${CurrentUser} "
				mysql "--host=${DB_Server}" "--user=${DB_UserName}" "--password=${DB_Password}" -e "UPDATE ${DB_DbName}.${CurrentTable1} p SET p.page_latest=( SELECT max(r.rev_id) FROM ${DB_DbName}.${CurrentTable2} r WHERE r.rev_page=p.page_id AND r.rev_user = $CurrentUser ) WHERE p.page_id IN (SELECT DISTINCT r2.rev_page FROM ${DB_DbName}.${CurrentTable2} r2 WHERE r2.rev_user = $CurrentUser)"
				Result=$? ; if [ $ResultN -eq 0 ] ; then ResultN=$Result ; fi
				CurrentUser=$(($CurrentUser - 1))
			done
			echo ""
		else
			echo "(3/9) Skipping tables ${CurrentTable1},${CurrentTable2} from clean process (some not found)."
		fi
	fi
	
	if [ $ResultN -eq 0 ] ; then
		echo ''
		CurrentTable1="${TablesPrefix}page"
		CurrentTable2="${TablesPrefix}revision"
		if [ "$(echo "$TablesList" | grep -e "^${CurrentTable1}$")" != "" ] && [ "$(echo "$TablesList" | grep -e "^${CurrentTable2}$")" != "" ] ; then
			echo '(4/9) For all pages make sure that page len is set equal to revision len...'
			mysql "--host=${DB_Server}" "--user=${DB_UserName}" "--password=${DB_Password}" -e "UPDATE ${DB_DbName}.${CurrentTable1} p SET p.page_len=( SELECT r.rev_len FROM ${DB_DbName}.${CurrentTable2} r WHERE r.rev_page=p.page_id AND r.rev_id=p.page_latest)"
			Result=$? ; if [ $ResultN -eq 0 ] ; then ResultN=$Result ; fi
		else
			echo "(4/9) Skipping tables ${CurrentTable1},${CurrentTable2} from clean process (some not found)."
		fi
	fi
	
	if [ $ResultN -eq 0 ] ; then
		echo ''
		CurrentTable1="${TablesPrefix}revision"
		CurrentTable2="${TablesPrefix}archive"
		if [ "$(echo "$TablesList" | grep -e "^${CurrentTable1}$")" != "" ] ; then
			echo '(5/9) Deleting revisions done by EACH selected user...'
			CurrentUser=$ToUser
			while [ $CurrentUser -ge $FromUser ] && [ $ResultN -eq 0 ] ; do
				printf "5_${CurrentUser}"
				mysql "--host=${DB_Server}" "--user=${DB_UserName}" "--password=${DB_Password}" -e "DELETE FROM ${DB_DbName}.${CurrentTable1} WHERE rev_user = $CurrentUser"
				Result=$? ; if [ $ResultN -eq 0 ] ; then ResultN=$Result ; fi
				if [ "$(echo "$TablesList" | grep -e "^${CurrentTable2}$")" != "" ] ; then
					printf "+"
					mysql "--host=${DB_Server}" "--user=${DB_UserName}" "--password=${DB_Password}" -e "DELETE FROM ${DB_DbName}.${CurrentTable2} WHERE ar_user = $CurrentUser"
					Result=$? ; if [ $ResultN -eq 0 ] ; then ResultN=$Result ; fi
				fi
				printf " "
				CurrentUser=$(($CurrentUser - 1))
			done
			echo ""
		else
			echo "(5/9) Skipping table $CurrentTable1 from clean process (not found)."
		fi
	fi
	
	if [ $ResultN -eq 0 ] ; then
		echo ''
		CurrentTable1="${TablesPrefix}recentchanges"
		if [ "$(echo "$TablesList" | grep -e "^${CurrentTable1}$")" != "" ] ; then
			echo "(6/9) Deleting EACH selected user's recent changes..."
			CurrentUser=$ToUser
			while [ $CurrentUser -ge $FromUser ] && [ $ResultN -eq 0 ] ; do
				printf "6_${CurrentUser} "
				mysql "--host=${DB_Server}" "--user=${DB_UserName}" "--password=${DB_Password}" -e "DELETE FROM ${DB_DbName}.${CurrentTable1} WHERE rc_user = $CurrentUser"
				Result=$? ; if [ $ResultN -eq 0 ] ; then ResultN=$Result ; fi
				CurrentUser=$(($CurrentUser - 1))
			done
			echo ""
		else
			echo "(6/9) Skipping table $CurrentTable1 from clean process (not found)."
		fi
	fi
	
	if [ $ResultN -eq 0 ] ; then
		echo ''
		echo '(7/9) Delete users own pages, properties and ACCOUNTS...'
		CurrentTable1="${TablesPrefix}user_newtalk"
		if [ "$(echo "$TablesList" | grep -e "^${CurrentTable1}$")" != "" ] ; then
			echo "	users talk notifications..."
			mysql "--host=${DB_Server}" "--user=${DB_UserName}" "--password=${DB_Password}" -e "DELETE FROM ${DB_DbName}.${CurrentTable1} WHERE (user_id >= $FromUser AND user_id <= $ToUser)"
			Result=$? ; if [ $ResultN -eq 0 ] ; then ResultN=$Result ; fi
		fi
		CurrentTable1="${TablesPrefix}user_properties"
		if [ "$(echo "$TablesList" | grep -e "^${CurrentTable1}$")" != "" ] ; then
			echo "	users preferences..."
			mysql "--host=${DB_Server}" "--user=${DB_UserName}" "--password=${DB_Password}" -e "DELETE FROM ${DB_DbName}.${CurrentTable1} WHERE (up_user >= $FromUser AND up_user <= $ToUser)"
			Result=$? ; if [ $ResultN -eq 0 ] ; then ResultN=$Result ; fi
		fi
		CurrentTable1="${TablesPrefix}mwuser"
		if [ "$(echo "$TablesList" | grep -e "^${CurrentTable1}$")" = "" ] ; then CurrentTable1="${TablesPrefix}user" ; fi
		if [ "$(echo "$TablesList" | grep -e "^${CurrentTable1}$")" != "" ] ; then
			echo "	users accounts..."
			mysql "--host=${DB_Server}" "--user=${DB_UserName}" "--password=${DB_Password}" -e "DELETE FROM ${DB_DbName}.${CurrentTable1} WHERE (user_id >= $FromUser AND user_id <= $ToUser)"
			Result=$? ; if [ $ResultN -eq 0 ] ; then ResultN=$Result ; fi
		fi
	fi
	
	if [ $ResultN -eq 0 ] ; then
		echo ''
		CurrentTable1="${TablesPrefix}revision"
		if [ "$(echo "$TablesList" | grep -e "^${CurrentTable1}$")" != "" ] ; then
			echo '(8/9) Near to end: Delete references and their pages that lack of revisions...'
			CurrentTable2="${TablesPrefix}pagelinks"
			if [ "$(echo "$TablesList" | grep -e "^${CurrentTable2}$")" != "" ] ; then
				echo "	internal links at pages..."
				mysql --batch --skip-column-names "--host=${DB_Server}" "--user=${DB_UserName}" "--password=${DB_Password}" -e "DELETE FROM ${DB_DbName}.${CurrentTable2} WHERE pl_from != 0 AND pl_from NOT IN (SELECT rev_page FROM ${DB_DbName}.${CurrentTable1});"
				Result=$? ; if [ $ResultN -eq 0 ] ; then ResultN=$Result ; fi
			fi
			CurrentTable2="${TablesPrefix}recentchanges"
			if [ "$(echo "$TablesList" | grep -e "^${CurrentTable2}$")" != "" ] ; then
				echo "	recent changes..."
				mysql --batch --skip-column-names "--host=${DB_Server}" "--user=${DB_UserName}" "--password=${DB_Password}" -e "DELETE FROM ${DB_DbName}.${CurrentTable2} WHERE rc_cur_id != 0 AND rc_cur_id NOT IN (SELECT rev_page FROM ${DB_DbName}.${CurrentTable1});"
				Result=$? ; if [ $ResultN -eq 0 ] ; then ResultN=$Result ; fi
			fi
			CurrentTable2="${TablesPrefix}searchindex"
			if [ "$(echo "$TablesList" | grep -e "^${CurrentTable2}$")" != "" ] ; then
				echo "	MyISAM text index for searches..."
				mysql --batch --skip-column-names "--host=${DB_Server}" "--user=${DB_UserName}" "--password=${DB_Password}" -e "DELETE FROM ${DB_DbName}.${CurrentTable2} WHERE si_page != 0 AND si_page NOT IN (SELECT rev_page FROM ${DB_DbName}.${CurrentTable1});"
				Result=$? ; if [ $ResultN -eq 0 ] ; then ResultN=$Result ; fi
			fi
			CurrentTable2="${TablesPrefix}logging"
			if [ "$(echo "$TablesList" | grep -e "^${CurrentTable2}$")" != "" ] ; then
				echo "	log actions..."
				mysql --batch --skip-column-names "--host=${DB_Server}" "--user=${DB_UserName}" "--password=${DB_Password}" -e "DELETE FROM ${DB_DbName}.${CurrentTable2} WHERE log_page != 0 AND log_page NOT IN (SELECT rev_page FROM ${DB_DbName}.${CurrentTable1});"
				Result=$? ; if [ $ResultN -eq 0 ] ; then ResultN=$Result ; fi
			fi
			CurrentTable2="${TablesPrefix}text"
			if [ "$(echo "$TablesList" | grep -e "^${CurrentTable2}$")" != "" ] ; then
				echo "	wikitext of revisions..."
				mysql --batch --skip-column-names "--host=${DB_Server}" "--user=${DB_UserName}" "--password=${DB_Password}" -e "DELETE FROM ${DB_DbName}.${CurrentTable2} WHERE old_id NOT IN (SELECT rev_text_id FROM ${DB_DbName}.${CurrentTable1});"
				Result=$? ; if [ $ResultN -eq 0 ] ; then ResultN=$Result ; fi
			fi
			CurrentTable2="${TablesPrefix}page"
			if [ "$(echo "$TablesList" | grep -e "^${CurrentTable2}$")" != "" ] ; then
				echo "	pages census..."
				mysql --batch --skip-column-names "--host=${DB_Server}" "--user=${DB_UserName}" "--password=${DB_Password}" -e "DELETE FROM ${DB_DbName}.${CurrentTable2} WHERE page_id NOT IN (SELECT rev_page FROM ${DB_DbName}.${CurrentTable1});"
				Result=$? ; if [ $ResultN -eq 0 ] ; then ResultN=$Result ; fi
			fi
		else
			echo "(8/9) Skipping 6 tables related to $CurrentTable1 from clean process (${CurrentTable1} not found)."
		fi
	fi
	
	if [ $ResultN -eq 0 ] ; then
		echo ''
		echo '(9/9) Finally, purging local content related cache tables...'
		CurrentTable1="${TablesPrefix}objectcache"
		if [ "$(echo "$TablesList" | grep -e "^${CurrentTable1}$")" != "" ] ; then
			echo "	non memcached operations..."
			mysql "--host=${DB_Server}" "--user=${DB_UserName}" "--password=${DB_Password}" -e "DELETE FROM ${DB_DbName}.${CurrentTable1}"
			Result=$? ; if [ $ResultN -eq 0 ] ; then ResultN=$Result ; fi
		fi
		CurrentTable1="${TablesPrefix}querycache"
		if [ "$(echo "$TablesList" | grep -e "^${CurrentTable1}$")" != "" ] ; then
			echo "	expensive grouped queries..."
			mysql "--host=${DB_Server}" "--user=${DB_UserName}" "--password=${DB_Password}" -e "DELETE FROM ${DB_DbName}.${CurrentTable1}"
			Result=$? ; if [ $ResultN -eq 0 ] ; then ResultN=$Result ; fi
		fi
		CurrentTable1="${TablesPrefix}querycachetwo"
		if [ "$(echo "$TablesList" | grep -e "^${CurrentTable1}$")" != "" ] ; then
			echo "	double link expensive grouped queries..."
			mysql "--host=${DB_Server}" "--user=${DB_UserName}" "--password=${DB_Password}" -e "DELETE FROM ${DB_DbName}.${CurrentTable1}"
			Result=$? ; if [ $ResultN -eq 0 ] ; then ResultN=$Result ; fi
		fi
	fi
	
	if [ $ResultN -eq 0 ] ; then
		echo "Deleting temporary backup..."
		rm -f "/tmp/cleanmediawiki.${DB_DbName}.sql"
		echo "All cleaning process completed."
	else
		echo "Process stopped due to some problem."
		if [ -f "/tmp/cleanmediawiki.${DB_DbName}.sql" ] ; then
			echo 'Restoring database to previous status...'
			mysql "--host=${DB_Server}" "--user=${DB_UserName}" "--password=${DB_Password}" < "/tmp/cleanmediawiki.${DB_DbName}.sql"
			Result=$?
			if [ $Result -eq 0 ] ; then
				rm -f "/tmp/cleanmediawiki.${DB_DbName}.sql"
				echo "Done."
			else
				echo "WARNING: Previous situation could not be restablished."
				echo "Database backup available at: /tmp/cleanmediawiki.${DB_DbName}.sql"
			fi
		fi
	fi
	if [ "$NotifyEmail" != "" ] ; then
		if [ $ResultN -eq 0 ] ; then
			echo "cleanmediawiki completed for database ${DB_DbName}" | mail -s "Wiki ${DB_DbName}: clean completed" "$NotifyEmail"
		else
			echo "cleanmediawiki finished for ${DB_DbName} with error result: $ResultN" | mail -s "Wiki ${DB_DbName}: unsuccessful clean" "$NotifyEmail"
		fi
	fi
	return $ResultN
}

Help ()
{
	local AvailableHeaders=""
	
	ReturnScriptHeader "$ScriptFile" "description" | tr '[:lower:]' '[:upper:]'
	echo ""
	echo 'Syntax:'
	echo "	$(basename "$0") DbName FromUser ToUser [DbUser [DbPassword [NotifyEmail [TablesPrefix]]]]"
	echo ''
	echo 'Required parameters:'
	echo '	DbName		Wiki database name'
	echo '	FromUser	Id. of the first user to select'
	echo '	ToUser		Id. of the last user to select'
	echo '			(specify "+" as last user, to delete up to'
	echo '			 last identifier)'
	echo ''
	AvailableHeaders="$(ReturnScriptHeader "$ScriptFile" | grep -ve '^ ' | cut -f 1 -d ':')"
	AvailableHeaders="$(echo "$AvailableHeaders" | tr '[:upper:]' '[:lower:]' | sed -e 's/^/--/g')"
	echo "Other syntaxes for first parameter:"
	echo $AvailableHeaders
	echo ''
	echo 'The cleaning process does the following basic steps:'
	echo '	1. Lock selected users accounts'
	echo '	2. Delete last edits in pages from these users'
	echo '	3. Delete same users accounts'
	echo '	4. Purge cache'
	echo ''
	echo 'Note: Does not support external users'
}


##### MAIN SCRIPT #####

Result=0
ResultN=0
ScriptFile="$0"
FunctionCalled="$1"

if [ "$FunctionCalled" != "" ] ; then
	if [ "$(echo "$FunctionCalled" | grep -e '^--')" = "" ] ; then
		LackDependencies="$(DependenciasFaltan "cut/coreutils grep/grep sed/sed mysql/mysql-client" 2>&1)"
		if [ "$LackDependencies" = "" ] ; then
			CleanMediaWiki "$@"
			Result=$? ; if [ $ResultN -eq 0 ] ; then ResultN=$Result ; fi
		else
			Result=1 ; if [ $ResultN -eq 0 ] ; then ResultN=$Result ; fi
			echo 'ERROR: Cannot find some tools:'
			echo "       $LackDependencies"
		fi
	else
		if [ "$FunctionCalled" = "--help" ] ; then
			Help
		else
			TempValue="$(ReturnScriptHeader "$ScriptFile" $(echo "$FunctionCalled" | cut --characters=3-))"
			if [ "$TempValue" != "" ] ; then
				echo "$TempValue"
			else
				Result=1 ; if [ $ResultN -eq 0 ] ; then ResultN=$Result ; fi
				echo "ERROR: Unknown parameter (${FunctionCalled})"
			fi
		fi
	fi
else
	Help
	Result=1 ; if [ $ResultN -eq 0 ] ; then ResultN=$Result ; fi
fi

exit $ResultN
