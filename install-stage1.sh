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



# Verification du type de distribution
if [ ! -f /etc/debian_version ] ; then
	echo "Aborted: this script will work only on Debian."
	exit
fi

# Chargement de la configuration / initialisation variables
if [ ! -f install-stage1.cf ] ; then
	echo "Aborted: 'install-stage1.cf' was not found."
	exit
else
	. install-stage1.cf
fi

# Extraction donnees
if [ -z $KERNEL ] ; then
	KERNEL="linux-$(echo $PATCH |cut -d "-" -f2).tar.bz2"
fi
KERNEL_VER=$(echo $KERNEL |sed -e "s/\.tar\.bz2//g")
PATCH_VER=$(echo $PATCH |sed -e "s/^patch-//g ; s/\.diff//g")
UTIL_VER=$(echo $UTIL |sed -e "s/\.tar\.bz2//g")
HTOP_VER=$(echo $HTOP |sed -e "s/\.tar\.gz//g")
CPU=$(cat /proc/cpuinfo |grep -c ^processor)

# Verification et installation paquets Debian
for deb in $DEBS ; do
	dpkg -l $deb 2>/dev/null |grep "^ii" >/dev/null || apt-get install -y $deb
done

# Telechargement archives
cd /usr/src
[ -n "$KERNEL" ] && [ ! -f $KERNEL ] && wget $KERNEL_BASE_URL/$KERNEL
[ -n "$KERNEL" ] && [ -n "$PATCH" ] && [ ! -f $PATCH ] && wget $PATCH_BASE_URL/$PATCH
[ -n "$UTIL" ] && [ ! -f $UTIL ] && wget $UTIL_BASE_URL/$UTIL
[ -n "$HTOP" ] && [ ! -f $HTOP ] && wget $HTOP_BASE_URL/$HTOP

# Extraction archives
[ -f $KERNEL ] && [ ! -d $KERNEL_VER ] && tar -xjf $KERNEL
[ -f $UTIL ] && [ ! -d $UTIL_VER ] && tar -xjf $UTIL
[ -f $HTOP ] && [ ! -d $HTOP_VER ] && tar -xzf $HTOP

# Patch noyau
if [ -d $KERNEL_VER ] && [ ! -d linux-$PATCH_VER ] ; then
	cp -la $KERNEL_VER linux-$PATCH_VER
	cd linux-$PATCH_VER
	patch -p1 < ../$PATCH
	cd ..
fi

# KERNEL sans PATCH --> compilation noyau classique
if [ -n $KERNEL ] && [ -z $PATCH ] ; then
	PATCH_VER=$KERNEL_VER
fi

# Configuration sources
if [ -d linux-$PATCH_VER ] ; then
	cd linux-$PATCH_VER
	make menuconfig
	cd ..
fi
if [ -d $UTIL_VER ] ; then
	cd $UTIL_VER
	[ ! -f Makefile ] && ./configure $UTIL_CONFIGURE
	cd ..
fi
if [ -d $HTOP_VER ] ; then
	cd $HTOP_VER
	[ ! -f Makefile ] && ./configure $HTOP_CONFIGURE
	cd ..
fi

# Compilation noyau
if [ -d linux-$PATCH_VER ] ; then
	cd linux-$PATCH_VER
	if [ -f .config ] ; then
		make -j$CPU
		make install
		make modules_install
		mkinitramfs -o /boot/initrd.img-$PATCH_VER $PATCH_VER
		rm /boot/*.old
		rm /boot/*.bak
		find /boot/ -type l -exec rm {} \;
		update-grub
		ln -fs boot/initrd.img-$PATCH_VER /initrd.img
		ln -fs boot/vmlinuz-$PATCH_VER /vmlinuz
	fi
	cd ..
fi

# Compilation Util-Vserver
if [ -d $UTIL_VER ] ; then
	cd $UTIL_VER
	[ -f Makefile ] && make -j$CPU && make install && make install-distribution
	# Extraction des attributs Util-Vserver, uniquement si le script
	# "install-stage2.sh" est present (kit "vs-tools")
	if [ -f install-stage2.sh ] ; then
		cd lib ; vstools=/etc/vs-tools
		[ -d $vstools ] || mkdir $vstools
		cat ccaps-v*.c |grep "DECL(" |grep "VC_VXC_" |cut -d'"' -f2 > $vstools/ccaps
		cat bcaps-v*.c |grep "DECL(" |cut -d'(' -f2 |cut -d')' -f1 |awk '{print tolower ($1)}' > $vstools/bcaps
		cat cflags-v*.c |grep "DECL(" |grep "VC_VXF_" |cut -d'"' -f2 > /usr/lib/vs-tools/ccaps > $vstools/flags
		cd ..
	fi
	cd ..
fi

# Compilation Htop
if [ -d $HTOP_VER ] ; then
	cd $HTOP_VER
	[ -f Makefile ] && make -j$CPU && make install
	if [ ! -f /usr/sbin/vhtop ] ; then
	cat<<EOF>/usr/sbin/vhtop
#!/bin/bash
/usr/sbin/chcontext --xid 1 -- /usr/bin/htop

EOF
	chmod +x /usr/sbin/vhtop
	echo -e "fields=52 0 48 17 18 38 39 40 2 46 47 49 1\ntree_view=1" > /root/.htoprc
	fi
	cd ..
fi

# Configuration Util-Vserver
[ -f /etc/init.d/util-vserver ] && update-rc.d -f util-vserver remove 2>/dev/null >/dev/null
[ -f /etc/init.d/vprocunhide ] && update-rc.d -f vprocunhide start 89 2 3 4 5 . stop 11 0 1 6 . 2>/dev/null >/dev/null
[ -f /etc/init.d/vservers-default ] && update-rc.d -f vservers-default start 90 2 3 4 5 . stop 10 0 1 6 . 2>/dev/null >/dev/null

# Fini ! ;)
cat << EOF

*** end of Linux-Vserver 'scratch' installation ***

Reboot your server, then 'cd /usr/src/vs-tools ; sh install-stage2.sh' 

EOF
