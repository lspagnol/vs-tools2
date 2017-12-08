#!/bin/bash

#       install-stage1.sh
#       
#       Copyright 2009 Laurent Spagnol <laurent.spagnol@univ-reims.fr>
#       
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



# Chargement de la configuration / initialisation variables
if [ ! -f install-stage2.cf ] ; then
	echo "Abandon: pas de fichier 'install-stage2.cf'"
	exit
else
	. install-stage2.cf
fi

# Verification noyau
result=$(grep "^CONFIG_VSERVER=y" /boot/config-$(uname -r) 2>/dev/null)
if [ $? -ne 0 ] ; then
	echo "Abandon: le noyau actuel ne supporte pas 'Linux-Vserver'"
	exit
fi



# Preparation de l'environnement
# ----------------------------------------------------------------------

# Installation des paquets Debian
result="$(dpkg -l |egrep "^ii[[:space:]]+" |awk '{print $2}')"
for deb in $DEBS_required $DEBS_usefull ; do
	echo "$result" |grep "^$deb$" >/dev/null
	if [ $? -ne 0 ] ; then
		apt-get -y -q install $deb
	fi
done

DEBOOTSTRAP=$(ncftpls ftp://ftp.debian.org/debian/pool/main/d/debootstrap/ |grep "^debootstrap_" |grep "_all.deb$" |cut -d_ -f2 |egrep -v "[a-z]" |sort -n |tail -1l)

# Telechargement et installation de 'debootstrap'
if ! dpkg -s debootstrap |grep "^Version: $DEBOOTSTRAP$" >/dev/null ; then
	if ! test -f /tmp/debootstrap_${DEBOOTSTRAP}_all.deb ] ; then
		wget -P /tmp ftp://ftp.debian.org/debian/pool/main/d/debootstrap/debootstrap_${DEBOOTSTRAP}_all.deb
	fi
	dpkg -i /tmp/debootstrap_${DEBOOTSTRAP}_all.deb
fi

# Telechargement et installation de 'yum'
#if ! dpkg -s debootstrap |grep "^Version: $YUM$" >/dev/null ; then
#	apt-get -y install yum
#	if ! test -f /tmp/yum_${YUM}_all.deb ] ; then
#		wget -P /tmp ftp://ftp.debian.org/debian/pool/main/y/yum/yum_${YUM}_all.deb
#	fi
#	dpkg -i /tmp/yum_${YUM}_all.deb
#fi

# Suppression des paquets inutiles
result="$(dpkg -l |egrep "^ii[[:space:]]+" |awk '{print $2}')"
for deb in $DEBS_remove ; do
	echo "$result" |grep "^$deb$" >/dev/null
	if [ $? -eq 0 ] ; then
		apt-get -y -q remove $deb
	fi
done

# Purge des paquets inutiles
result="$(dpkg -l |egrep "^rc[[:space:]]+" |awk '{print $2}')"
for deb in $DEBS_remove ; do
	echo "$result" |grep "^$deb$" >/dev/null
	if [ $? -eq 0 ] ; then
		dpkg -P $deb
	fi
done

# Purge des paquets orphelins
while [ "$(deborphan)" ] ; do
	apt-get -y -q --purge remove $(deborphan)
done

# Desactivation des services inutiles
if [ "$(netstat -npl |grep "/inetd")" ] ; then
	/etc/init.d/openbsd-inetd stop
	update-rc.d -f openbsd-inetd remove
fi

# Chargement de modules noyau au demarrage
for module in $MODULES ; do
	if [ ! "$(grep "^$module$" /etc/modules)" ]; then
		echo "$module">>/etc/modules
	fi
done

# Promotion automatique des adresses IPv4
if [ ! "$(grep "^net.ipv4.conf.all.promote_secondaries=1$" /etc/sysctl.conf)" ] ; then
	echo "net.ipv4.conf.all.promote_secondaries=1">>/etc/sysctl.conf
fi

if [ "$SELF_FENCING" == "1" ] ; then
	# "self-fencing" : Provoque un Kernel Panic en cas d'anomalie
	if [ ! "$(grep "^kernel.panic_on_oops=1$" /etc/sysctl.conf)" ] ; then
		echo "kernel.panic_on_oops=1">>/etc/sysctl.conf
	fi

	# "self-fencing" : Reboot automatique au bout de 60 secondes en cas de Kernel Panic
	if [ ! "$(grep "^kernel.panic=60$" /etc/sysctl.conf)" ] ; then
		echo "kernel.panic=60">>/etc/sysctl.conf
	fi
fi

# Desactivation du support IPv6
if [ "$DISABLE_IPV6" == "1" ] ; then
	if [ "$(grep "^alias net-pf-10 ipv6$" /etc/modprobe.d/aliases)" ] ; then
		result="$(sed -e "s/^alias net-pf-10 ipv6/#alias net-pf-10 ipv6\nalias net-pf-10 off/g" /etc/modprobe.d/aliases)"
		echo "$result" > /etc/modprobe.d/aliases
	fi
fi

# Installation de la compatibilite x86_64
if [ "$IA32_COMPAT" == "1" ] ; then
	if [ "$(uname -m)" == "x86_64" ] ; then
		dpkg -l ia32-libs 2>/dev/null |grep "^ii" >/dev/null
		if [ $? -ne 0 ] ; then
			apt-get install -y -q ia32-libs
		fi
	fi
fi

# OpenSSH : forcer l'ecoute sur l'interface de service
if [ ! "$(egrep "^ListenAddress[[:space:]]+$(hostname -i)$" /etc/ssh/sshd_config)" ] ; then
	echo "ListenAddress $(hostname -i)" >> /etc/ssh/sshd_config
fi

# Modification demarrage du demon openntpd : forcer la synchro au demarrage du serveur
if [ "$(grep "^#DAEMON_OPTS=" /etc/default/openntpd)" ] ; then
	result="$(sed -e "s/^#DAEMON_OPTS=/DAEMON_OPTS=/g" /etc/default/openntpd)"
	echo "$result" > /etc/default/openntpd
fi

# Modification configuration update-db : ne pas indexer les vserveurs
if [ -f /etc/updatedb.conf ] ; then
	if [ ! "$(grep $_VSERVERS_BASE /etc/updatedb.conf)" ] ; then
		result="$(sed -e "s/\/media\"$/\/media \/var\/lib\/vs-tools \/var\/lib\/vservers \/vservers \/snapshots \/var\/run \/var\/cache\"/g" /etc/updatedb.conf)"
		echo "$result" > /etc/updatedb.conf
	fi
fi

# Modification /etc/default/rsync : activation
if [ ! "$(grep "^RSYNC_ENABLE=true" /etc/default/rsync)" ] ; then
	result="$(sed -e "s/^RSYNC_ENABLE=.*/RSYNC_ENABLE=true/g" /etc/default/rsync)"
	echo "$result" > /etc/default/rsync
fi

# Modification /etc/default/rsync : forcer l'ecoute sur l'interface de service
if [ ! "$(grep "^RSYNC_OPTS='--address=$(hostname -i)'" /etc/default/rsync)" ] ; then
	result="$(sed -e "s/^RSYNC_OPTS=.*/RSYNC_OPTS='--address=$(hostname -i)'/g" /etc/default/rsync)"
	echo "$result" > /etc/default/rsync
fi

# Modification /etc/default/rsync : reduire la priorite de rsyncd
if [ ! "$(grep "^RSYNC_NICE='10'" /etc/default/rsync)" ] ; then
	result="$(sed -e "s/^RSYNC_NICE=.*/RSYNC_NICE='10'/g" /etc/default/rsync)"
	echo "$result" > /etc/default/rsync
fi

# Modification /etc/lvm/lvm.conf : prise en charge des 'hosttags'
if [ ! "$(grep "^volume_list = \[ \"@\*\"" /etc/lvm/lvm.conf)" ] ; then
	result="$(sed -e "s/, \"@\*\" \]/, \"@\*\" \]\nvolume_list = \[ \"@\*\" \]/g" < /etc/lvm/lvm.conf)"
	echo "$result" > /etc/lvm/lvm.conf
fi
if [ ! "$(grep '^tags {' /etc/lvm/lvm.conf)" ] ; then
cat << EOF >>/etc/lvm/lvm.conf

tags {
        hosttags = 1
        local {}
        heartbeat {}
}
EOF
fi

# Installation du Multipath
if [ "$MULTIPATH" == "1" ] ; then
	dpkg -l multipath-tools 2>/dev/null >/dev/null
	if [ $? -ne 0 ] ; then
		apt-get install -y multipath-tools
	fi
fi

# Parametrage du Multipath pour les SAN Datacore
if [ "$DATACORE" == "1" ] ; then
	if [ ! -f /etc/multipath.conf ] ; then
		# Changement de version et syntaxe de 'scsi_id' entre Etch et Lenny
		if [ "$(cat /etc/debian_version |grep "4.0")" ] ; then
			getuid_callout="/sbin/scsi_id -g -u -p 0x80 -s /block/%n"
		elif [ "$(cat /etc/debian_version |grep "5.0")" ] ; then
			getuid_callout="/lib/udev/scsi_id -g -u -p 0x80 --device=/dev/%n"
		fi
		if [ -n "$getuid_callout" ] ; then
			cat <<EOF > /etc/multipath.conf
defaults {
        user_friendly_names yes
}

devices {
        device {
                vendor "DataCore"
                product "SAN*"
                path_grouping_policy failover
                path_checker tur
                failback 10
                getuid_callout "$getuid_callout"
        }
}
EOF
		fi
	fi
fi

# Creation des repertoires
# ----------------------------------------------------------------------

# logs
mkdir -p $_VSTOOLS_LOGS

# configuration
mkdir -p $_VSTOOLS_CONF

# base lvs / vserveurs
mkdir -p $_VSTOOLS_BASE

# snapshots
mkdir -p $_VSTOOLS_SNAPSHOTS

# scripts
mkdir -p $_VSTOOLS_BIN						# commandes vs-tools
mkdir -p $_VSTOOLS_BIN/functions            # modules de la librairie vs-tools
mkdir -p $_VSTOOLS_BIN/scripts 				# scripts de demarrage, arret, snapshots ... des vserveurs
mkdir -p $_VSTOOLS_BIN/cron					# taches planifiees
mkdir -p $_VSTOOLS_BIN/misc					# scripts divers
mkdir -p $_VSTOOLS_BIN/contribs				# scripts divers (contributions)

# cache
#
# _VSTOOLS_CACHE/
# _VSTOOLS_CACHE/stats/
# _VSTOOLS_CACHE/stats/<host>				# statistiques hôte
# _VSTOOLS_CACHE/stats/vservers/			# statistiques vserveurs
#
# _VSTOOLS_CACHE/cluster/
# _VSTOOLS_CACHE/cluster/<host>/
# _VSTOOLS_CACHE/cluster/<host>/etc/
# _VSTOOLS_CACHE/cluster/<host>/cache/
# _VSTOOLS_CACHE/cluster/<host>/run/
# _VSTOOLS_CACHE/cluster/<host>/stats/
# _VSTOOLS_CACHE/cluster/<host>/stats/<host>
# _VSTOOLS_CACHE/cluster/<host>/stats/vservers/

mkdir -p $_VSTOOLS_CACHE
mkdir -p $_VSTOOLS_CACHE/stats
mkdir -p $_VSTOOLS_CACHE/stats/vservers
mkdir -p $_VSTOOLS_CACHE/cluster



# Fichiers de configuration
# ----------------------------------------------------------------------
# .cf   -> shell, inclus au demarrage des scripts
# .conf -> texte, parcourus et interpretes par la librairie



# Fichiers de configuration principaux
# Ils sont generes lors de chaque installation.
# Leur contenu depend de la compilation des differents composants.
# Ils ne DOIVENT PAS etre modifies !!
# ----------------------------------------------------------------------

# rsyncd.conf
# portee: hote
[ -f /etc/rsyncd.conf ] || touch /etc/rsyncd.conf
sed -i "/## VS-TOOLS AUTOMAGIC - BEGIN ##/{:z;N;/## VS-TOOLS AUTOMAGIC - END ##/!bz;//d}" /etc/rsyncd.conf
cat << EOF >> /etc/rsyncd.conf
## VS-TOOLS AUTOMAGIC - BEGIN ##

[conf]
path = $_VSERVERS_CONF
uid = root
use chroot = yes
read only = yes
hosts allow = $_LINUX_NETWORK,127.0.0.1

[base]
path = $_VSTOOLS_BASE
uid = root
use chroot = yes
read only = yes
hosts allow = $_LINUX_NETWORK,127.0.0.1

[snapshots]
path = $_VSTOOLS_SNAPSHOTS
uid = root
use chroot = yes
read only = yes
hosts allow = $_LINUX_NETWORK,127.0.0.1

[run]
path = $_VSERVERS_RUN
uid = root
use chroot = yes
read only = yes
hosts allow = $_LINUX_NETWORK,127.0.0.1

[cache]
path = $_VSERVERS_CACHE
uid = root
use chroot = yes
read only = yes
hosts allow = $_LINUX_NETWORK,127.0.0.1

[stats]
path = $_VSTOOLS_CACHE/stats
uid = root
use chroot = yes
read only = yes
hosts allow = $_LINUX_NETWORK,127.0.0.1

## VS-TOOLS AUTOMAGIC - END ##
EOF

# xinetd.heartbeat
# portee: hote
sed -i "s/^heartbeat.*//g" /etc/services
if [ -n "$HEARTBEAT" ] ; then
	echo "heartbeat	${_VSTOOLS_HB_PORT}/tcp		# heartbeat backend for vs-tools" >> /etc/services
	cat << EOF > /etc/xinetd.d/heartbeat
# default: on
# description: heartbeat backend for vs-tools
service chk_backend
{
	type			= UNLISTED
	protocol		= tcp
	bind			= ${_LINUX_HOSTIP}
	socket_type		= stream
	port			= ${_VSTOOLS_HB_PORT}
	wait			= no
	user			= nobody
	server			= /bin/cat
	server_args		= /tmp/heartbeat
	log_on_failure		+= USERID
	disable			= no
	only_from		= ${_LINUX_NETWORK}
}
EOF
fi
/etc/init.d/xinetd restart > /dev/null

# linux.cf
# portee: hote
cat << EOF > $_VSTOOLS_CONF/linux.cf
## Do not change anything here ! ##
_LINUX_PAGESIZE="$_LINUX_PAGESIZE"
_LINUX_HOSTIP="$_LINUX_HOSTIP"
_LINUX_RSS="$(free -m |grep "^Mem:" |awk '{print $2}')"
EOF

# util-vserver.cf
# portee: hote
cat << EOF > $_VSTOOLS_CONF/util-vserver.cf
## Do not change anything here ! ##
_VSERVERS_CONF="$_VSERVERS_CONF"
_VSERVERS_BASE="$_VSERVERS_BASE"
_VSERVERS_RUN="$_VSERVERS_RUN"
_VSERVERS_CACHE="$_VSERVERS_CACHE"
_VSERVERS_BCAPS="$_VSERVERS_BCAPS"
_VSERVERS_CCAPS="$_VSERVERS_CCAPS"
_VSERVERS_FLAGS="$_VSERVERS_FLAGS"
EOF

# vs-tools.cf
# portee: hote
cat << EOF > $_VSTOOLS_CONF/vs-tools.cf
## Do not change anything here ! ##
_VSTOOLS_BIN="$_VSTOOLS_BIN"
_VSTOOLS_LOGS="$_VSTOOLS_LOGS"
_VSTOOLS_CONF="$_VSTOOLS_CONF"
_VSTOOLS_BASE="$_VSTOOLS_BASE"
_VSTOOLS_CACHE="$_VSTOOLS_CACHE"
_VSTOOLS_SNAPSHOTS="$_VSTOOLS_SNAPSHOTS"
_VSTOOLS_SNAPSHOTS_ATTEMPS="$_VSTOOLS_SNAPSHOTS_ATTEMPS"
_VSTOOLS_BUILD_CONF="$_VSTOOLS_BUILD_CONF"
_VSTOOLS_RSYNC_SRC="$_VSTOOLS_RSYNC_SRC"
_VSTOOLS_RSYNC_DST="$_VSTOOLS_RSYNC_DST"
_VSTOOLS_KNOWN_ARCHS="$_VSTOOLS_KNOWN_ARCHS"
_VSTOOLS_KNOWN_FS_TYPES="$_VSTOOLS_KNOWN_FS_TYPES"
_VSTOOLS_MOUNT_OPTS="$_VSTOOLS_MOUNT_OPTS"
_VSTOOLS_HB_PORT="$_VSTOOLS_HB_PORT"
EOF



# Modeles de fichiers de configuration
# Les fichiers '.conf.sample' sont ecrases lors de chaque installation.
# Ils peuvent etre copies et edites. Certains servirons ensuite de
# modele lors de la creation des vserveurs.
# ----------------------------------------------------------------------

# build.cf.sample -> build.cf
# portee: hote
cat << EOF > $_VSTOOLS_CONF/build.cf.sample
## ---------------------------------------------------------------------
## Default values used by 'vs-build'
##
## Copy '$_VSTOOLS_CONF/build.cf.sample'
##   to '$_VSTOOLS_CONF/build.cf', then edit the file
## ---------------------------------------------------------------------

## Don't forget to create VG !
## Allowed 'fs types' are '${_VSTOOLS_KNOWN_FS_TYPES}'
_DEFAULT_FS_TYPE=ext3
_DEFAULT_LV_SIZE=10G

## Default pool (LV) is hostname/vservers
_DEFAULT_POOL="$(hostname -s)/vservers"

## Default limits:
_DEFAULT_LIMITS="rss=128,disk=1024,tmpfs=16,nproc=400"

## Default POSIX capabilities to be added/removed in configuration
_DEFAULT_BCAPS="${_DEFAULT_BCAPS}"

## Default context capabilities to be added/removed in configuration
_DEFAULT_CCAPS="${_DEFAULT_CCAPS}"

## Default context flags to be added/removed in configuration
_DEFAULT_FLAGS="${_DEFAULT_FLAGS}"

## Provision method ('debootstrap' or 'template')
_DEFAULT_METHOD=debootstrap

## If '_DEFAULT_BUILD_METHOD=debootstrap', use these values:
## (Allowed 'arch' are '${_VSTOOLS_KNOWN_ARCHS}')
_DEFAULT_ARCH=i386
_DEFAULT_DEBOOTSTRAP=etch

## If '_DEFAULT_BUILD_METHOD=template', use these values:
#_DEFAULT_TEMPLATE=/vservers/TEMPLATES/template.tgz

## Start vservers after provisionning
#_DEFAULT_START=yes

## Enable vservers after provisioning
## An 'enabled' vserver will automaticaly start on host's startup
#_DEFAULT_ENABLE=yes

EOF

# networks.cf.sample -> networks.cf
# portee: hote
cat << EOF > $_VSTOOLS_CONF/networks.cf.sample
## ---------------------------------------------------------------------
## Definition of vservers networks
##
## Copy '$_VSTOOLS_CONF/networks.cf.sample'
##   to '$_VSTOOLS_CONF/networks.cf', then edit the file
## ---------------------------------------------------------------------

## This file will be used by modules 'net.sh/netIpSet' and
## 'net.sh/netVlanSelect'. So it is usefull only for create / change
## vservers configuration.

## It may use two parts.
## The first one describes global/defaults values, and the second use
## the same variables with arrays. Indexes are vlans IDs.
## The tip is to fall back to default values that use index '0' when
## nothing other was matching in arrays.

## _KNOWN_VLANS   - vlans IDs ('GLOBAL/DEFAULT configuration' only)
## _VLAN          - vlan ID   ('GLOBAL/DEFAULT configuration' only)

## _LABEL         - Informational
## _NET_DEV       - network device
## _NET           - network address
## _CIDR          - network mask
## _GATEWAY       - network gateway
## _DOMAIN        - domain name for this network
## _SEARCHDOMAINS - search domain(s) for this network
## _NAMESERVERS   - name server(s) for this network

## WARNING: use only CIDR notation without "/".
## CIDR - NETMASK         - SIZE / USABLE
## 24   - 255.255.255.0	  -  256 / 253
## 25   - 255.255.255.128 -  128 / 125
## 26   - 255.255.255.192 -   64 / 61
## 27   - 255.255.255.224 -   32 / 29
## 28   - 255.255.255.240 -   16 / 13
## 29   - 255.255.255.248 -    8 / 5
## 30   - 255.255.255.252 -    4 / 1

## ---------------------------------------------------------------------
## GLOBAL/DEFAULT configuration
## ---------------------------------------------------------------------

## You can use this section lonely when you use only one network, so
## '_VLAN' is usefull in this case only.

## Network configuration MUST contain at least the five following
## parameters.

#_NET=192.168.1.0
#_NET_DEV=eth0
#_CIDR=24
#_DOMAIN=mydomain.tld
#_NAMESERVERS=10.1.57.3

#_VLAN=6
#_TABLE=1
#_GATEWAY=192.168.1.254
#_SEARCHDOMAINS=mydomain.tld

## ---------------------------------------------------------------------
## OTHERS networks configuration
## ---------------------------------------------------------------------

## First declare 802.1q vlan IDs in array variable '_VLANS'
#_KNOWN_VLANS=25,93,54

## Later, if you need to disable network '25' , the short way is to 
## change '_KNOWN_VLANS' instead of suppress matching arrays:
#_KNOWN_VLANS=25,93

## Arrays for vlan ID '25':
#_LABEL[25]="Dummy network, for tests"
#_TABLE[25]=2
#_NET[25]=10.78.31.32
#_NET_DEV[25]=eth0
#_CIDR[25]=27
#_GATEWAY[25]=10.78.31.37
#_DOMAIN[25]=mydomain1.mytld
#_SEARCHDOMAINS[25]=otherdomain.tld,another.tld
#_NAMESERVERS[25]=10.52.1.27

## Arrays for vlan ID '93':
## Note that '_CIDR' is not specified: it will be repalced by default
## value.
#_LABEL[93]="Another dummy network"
#_TABLE[93]=3
#_NET[93]=192.168.0.0
#_GATEWAY[93]=192.168.0.254
#_DOMAIN[93]=mydomain1.mytld
#_NAMESERVERS[93]=10.52.1.27,192.168.1.65

## Arrays for vlan ID '54':
#_TABLE[54]=...
#_NET[54]=...
#_CIDR[54]=...
#_GATEWAY[54]=...
#_DOMAIN[54]=...
#_NAMESERVERS[54]=...,...,...

## ---------------------------------------------------------------------

EOF

# cluster.cf.sample -> cluster.cf
# portee: hote
cat << EOF > $_VSTOOLS_CONF/cluster.cf.sample
## ---------------------------------------------------------------------
## Configuration example for cluster / group of hosts
##
## Copy '$_VSTOOLS_CONF/cluster.cf.sample'
##   to '$_VSTOOLS_CONF/cluster.cf', then edit the file
## ---------------------------------------------------------------------

# Members of this cluster. Be carrefull with name resolution.
#_NODES="node1,node2,..."

# 'lvm' Heartbeat:
# It use direct read/write on dedicated logical volume. This method
# permits to avoid concurent access on shared data. Each node use its
# own segment. Hearbeat will use 1K on segment that must be a least the
# extent size of volume group:
# extent_size (Bytes) -> vgs --units b --noheadings --nosuffix -o vg_extent_size <vg_name>
# block_size = extent_size / 1024
# In most cases, block_size = 4096

_HB_BLOCK_SIZE=4096
#_HB_BLOCK_DEV=/dev/cluster/heartbeat

# Use these values extremely carefully to avoid data crushing !
# Index MUST start at '1', and order MUST be unchanged
#_HB_BLOCK_IDX[1]=node1
#_HB_BLOCK_IDX[2]=node2
# ....

# How to check health on this node:
# hb_pools_rw    -> RW access to all enabled pools
#                   -1:no pool, 0:RW error, 1:good
# hb_ifs_carrier -> carrier detected on all enabled nics
#                   0:no carrier, 1:good
# hb_gws_alive   -> gateway available on all networks shown on this node (host + Vservers)
#                   0:unreachable, 1:good
# (WARNING: always use simple quotes)
# Check carrier, gateways and pools:
_HEALTH='[ $hb_pools_rw -ne 0 ] && [ $hb_ifs_carrier -eq 1 ] && [ $hb_gws_alive -eq 1 ]'
# Check gateways and pools only (usefull with bonding)
#_HEALTH='[ $hb_pools_rw -ne 0 ] && [ $hb_gws_alive -eq 1 ]'

# Stop all Vservers and and disable all pools on any error detected with
# 'clusterHeartbeatWrite'.
#_FENCE=1

# This will suspend fencing during start/stop sequences
#_FENCE_SUSPEND="/usr/lib/util-vserver/start-vservers"

# Grace period (in seconds) before starting fence procedure:
#_GRACEFULL=30

EOF



# Installation des scripts
# ----------------------------------------------------------------------

# Librairie
cp errors.sh $_VSTOOLS_BIN
cp functions.sh $_VSTOOLS_BIN
cp functions/*.sh $_VSTOOLS_BIN/functions
cp scripts/*.sh $_VSTOOLS_BIN/scripts

# Listes attributs Util-Vserver
for file in bcaps ccaps flags ressources ; do
	cp -f $file $_VSTOOLS_BIN
done

# Commandes principales
for file in vs-tools ; do
	cp -f $file $_VSTOOLS_BIN ; ln -fs $_VSTOOLS_BIN/$file /usr/sbin
done

# Modification sequence demarrage
dpkg -l util-vserver 2>/dev/null |grep "^ii" >/dev/null
if [ $? -eq 0 ] ; then # Paquet Debian "util-vserver" installe
	update-rc.d -f util-vserver remove 2>/dev/null >/dev/null
	update-rc.d -f util-vserver start 90 2 3 4 5 . stop 10 0 1 6 . 2>/dev/null >/dev/null
fi

# Mise en place controle LVM
cp -f init.d/vs-mount /etc/init.d
update-rc.d -f vs-mount remove 2>/dev/null >/dev/null
update-rc.d -f vs-mount start 89 2 3 4 5 . stop 11 0 1 6 . 2>/dev/null >/dev/null

# Demon: heartbeat
cp -f vs-heartbeat.daemon $_VSTOOLS_BIN
cp -f init.d/vs-heartbeat /etc/init.d
if [ "$HEARTBEAT" == "1" ] ; then
	update-rc.d -f vs-heartbeat remove 2>/dev/null >/dev/null
	update-rc.d -f vs-heartbeat start 88 2 3 4 5 . stop 12 0 1 6 . 2>/dev/null >/dev/null
	/etc/init.d/vs-heartbeat restart 2>/dev/null >/dev/null
else
	/etc/init.d/vs-heartbeat stop 2>/dev/null >/dev/null
	update-rc.d -f vs-heartbeat remove 2>/dev/null >/dev/null
fi

# Cron: collecte des donnees du cluster
if [ "$CLUSTER_COLLECTOR" == "1" ] ; then
	cat << EOF > /etc/cron.d/cluster-collector
# Retreive informations about all vservers running on all nodes
${CLUSTER_COLLECTOR} * * * * root [ -x $_VSTOOLS_BIN/vs-tools ] && $_VSTOOLS_BIN/vs-tools clusterCollector
EOF
else
	[ -f /etc/cron.d/cluster-collector ] && rm /etc/cron.d/cluster-collector
fi

# Cron: scan des bus SCSI
if [ "$RESCAN_SCSI" ] ; then
	cat << EOF > /etc/cron.d/rescan-scsi
# Force rescan of SCSI buses
*/${RESCAN_SCSI} * * * * root for host in \$(ls /sys/class/scsi_host/) ; do echo "- - -" > /sys/class/scsi_host/\${host}/scan ; done
EOF
else
	[ -f /etc/cron.d/rescan-scsi ] && rm /etc/cron.d/rescan-scsi
fi

# Logrotate: rotation des logs vs-tools
if [ ! -f /etc/logrotate.d/vs-tools ] ; then
	cat << EOF > /etc/logrotate.d/vs-tools
/var/log/vs-tools/vs-tools.log {
        daily
        dateext
        missingok
        rotate 30
        compress
        copytruncate
        notifempty
        create 640 root adm
}
EOF
fi

# 'Shell' vs-tools (mode interactif)
cat /root/.bashrc > /root/.vs-shellrc
echo "alias help='vs-tools help'" >> /root/.vs-shellrc
cat $_VSTOOLS_BIN/functions/*.sh |grep "^function" |awk '{print "alias "$2"=vs-tools "$2}' |sed -e "s/=/=\'/g ; s/$/\'/g">> /root/.vs-shellrc
echo "PS1='[vs-tools] \h:\w\$ '" >> /root/.vs-shellrc
cat << EOF >> /root/.vs-shellrc
cat << EOT

** interactive mode **

Available modules:
$(cd $_VSTOOLS_BIN/functions ; echo $(ls *.sh) |sed -e "s/\.sh//g")

Help........: help
Quit........: <ctrl D>

EOT
EOF
