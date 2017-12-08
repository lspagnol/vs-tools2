#       This program is free software; you can redistribute it and/or modify
#       it under the terms of the GNU General Public License as published by
#       the Free Software Foundation; either version 2 of the License, or
#       (at your option) any later version.
#       
#       This program is distributed in the hope that it will be useful,
#       but WITHOUT ANY WARRANTY; without even the implied warranty of
#       MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#       GNU General Public License for more details.
#       
#       You should have received a copy of the GNU General Public License
#       along with this program; if not, write to the Free Software
#       Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
#       MA 02110-1301, USA.

_VSTOOLS_CONF=/etc/vs-tools

# Chargement des fichiers de configuration
# ----------------------------------------------------------------------

. $_VSTOOLS_CONF/linux.cf || exit 1
. $_VSTOOLS_CONF/util-vserver.cf || exit 1
. $_VSTOOLS_CONF/vs-tools.cf || exit 1
. $_VSTOOLS_CONF/build.cf || exit 1

[ -f $_VSTOOLS_CONF/networks.cf ] && . $_VSTOOLS_CONF/networks.cf
[ -f $_VSTOOLS_CONF/cluster.cf ] && . $_VSTOOLS_CONF/cluster.cf

# Initialisation des variables globales (SYSLOG/DEBUG)
# ----------------------------------------------------------------------

_PTIMESTAMP=$(date +%s)	# timestamp -> debut d'execution (secondes)
_PPID=$$				# PID du script
_PCALL="$0 $@"			# Nom du script et arguments

LANG=C

# Fonctions LOG / DEBUG / DIALOG
# Tags:
# P: Programme + arguments
# F: Fonction + arguments
# C: Commande + arguments
# M: Message
# D: Temps ecoule depuis le debut du programme (secondes)
# ----------------------------------------------------------------------

function log
{

echo "$(date +"%F %T") - vs-tools[$_PPID] - P='$_PCALL';F='${FUNCNAME[@]}';M='$1'" >> $_VSTOOLS_LOGS/vs-tools.log

return 0

}

function error
{

echo "$(date +"%F %T") - vs-tools[$_PPID] - P='$_PCALL';F='${FUNCNAME[@]}';M='$1'" >> $_VSTOOLS_LOGS/vs-tools.log
echo "ERROR   : $1" >&2

return 1

}

function logexec
{

local result

echo "$(date +"%F %T") - vs-tools[$_PPID] - P='$_PCALL';F='${FUNCNAME[@]}';C='$@'" >> $_VSTOOLS_LOGS/vs-tools.log

$@ 2>/tmp/log >/tmp/log </dev/null ; result=$?

if [ -f /tmp/log ] ; then
	if [ -s /tmp/log ] ; then
		sed -e "s/^/#STDOUT: /g" < /tmp/log >> $_VSTOOLS_LOGS/vs-tools.log
		echo >> $_VSTOOLS_LOGS/vs-tools.log
	fi
	rm /tmp/log
fi

if [ $result -ne 0 ] ; then
	return 1
else
	return 0
fi

}

function notice
{ 

echo "$(date +"%F %T") - vs-tools[$_PPID] - P='$_PCALL';F='${FUNCNAME[@]}';M='$1'" >> $_VSTOOLS_LOGS/vs-tools.log

echo "NOTICE  : $1"

return 0

}

function warning
{

_WARNING=1

echo "$(date +"%F %T") - vs-tools[$_PPID] - P='$_PCALL';F='${FUNCNAME[@]}';M='$1'" >> $_VSTOOLS_LOGS/vs-tools.log

echo "WARNING : $1"

return 0

}

function confirm
{

local result

if [ -z $_WARNING ] ; then
	log "nothing to confirm"
	return 0
else
	log "_WARNING=1 -> ask for confirmation"
	if [ ! -z "${_ASSUME_YES}" ] ; then
		log "_ASSUME_YES=1 -> automatic answer = yes"
		result=y
	fi
	if [ ! -z "${_ASSUME_NO}" ] ; then
		log "_ASSUME_NO=1 -> automatic answer = no"
		result=n
	fi
	if [ -z "$result" ] ; then
		if [ -z "$1" ] ; then
			echo -en "CONFIRM : (y/N) ? "
		else
			echo -en "CONFIRM : $1 (y/N) ? "
		fi
		read result
	fi
	case $result in
		y|Y|o|O)
			log "confirmation request accepted"
			return 0
			;;
		n|N|*)
			log "confirmation request rejected"
			return 1
			;;
	esac
fi

}

function begin
{ 

echo "$(date +"%F %T") - vs-tools[$_PPID] - P='$_PCALL';F='${FUNCNAME[@]}'" >> $_VSTOOLS_LOGS/vs-tools.log

return 0

}

function end
{

local rc=$?

_PTIMESPENT=$(( $(date +%s) - ${_PTIMESTAMP} ))

echo "$(date +"%F %T") - vs-tools[$_PPID] - P='$_PCALL';F='${FUNCNAME[@]}';D='$_PTIMESPENT'" >> $_VSTOOLS_LOGS/vs-tools.log

exit $rc

}

function abort
{

_PTIMESPENT=$(( $(date +%s) - ${_PTIMESTAMP} ))

echo "$(date +"%F %T") - vs-tools[$_PPID] - P='$_PCALL';F='${FUNCNAME[@]}';M='$1';D='$_PTIMESPENT'" >> $_VSTOOLS_LOGS/vs-tools.log

echo "ABORTED : $1"

exit 1

}

# Chargement des modules principaux
# ----------------------------------------------------------------------

. ${_VSTOOLS_BIN}/errors.sh

for file in \
 $(ls ${_VSTOOLS_BIN}/functions/*.sh 2>/dev/null) ; do
	. $file
done

# Chargement des modules locaux
# Ils peuvent etre utilises pour ajouter des fonctionnalites sans
# modifier les outils existants. Ils sont ignores par 'install.sh'.
# ----------------------------------------------------------------------

if [ -d ${_VSTOOLS_BIN}/functions.local ] ; then
	for file in \
	 $(ls ${_VSTOOLS_BIN}/functions.local/*.sh 2>/dev/null) ; do
		. $file
	done
fi
