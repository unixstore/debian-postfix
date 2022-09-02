#! /bin/sh -e

# This helper script is used by the postfix init scripts,
# upstart jobs, systemd services, openrc scripts, etc. in
# prepping the instance of postfix to be started.

# It was originally part of the postfix init script, which
# was written by LaMont Jones <lamont@debian.org>, and based
# off of the sendmail init script.

chroot_extra_files=
chroot_extra_CAdir=

INSTANCE="$1"

SYNC_CHROOT="y"

if test -r /etc/default/postfix; then
	. /etc/default/postfix
fi

# Sigh.  Because reasons, files is relative, CAdir not
[ "$chroot_extra_CAdir" != '' ] && [ ! "${chroot_extra_CAdir%${chroot_extra_CAdir#?}}"x = '/x' ] && chroot_extra_CAdir=/$chroot_extra_CAdir
if [ "$chroot_extra_files" != '' ]; then
	files=''
	for file in $chroot_extra_files
	do
		[ "${file%${file#?}}"x = '/x' ] && file=${file#?}
		files="$files $file"
	done
	chroot_extra_files=$files
fi

if [ "X$INSTANCE" = X ] || [ "X$INSTANCE" = "X-" ]; then
	POSTCONF="postconf -o inet_interfaces="
else
	POSTCONF="postmulti -i $INSTANCE -x postconf -o inet_interfaces="
fi

# if you set myorigin to 'ubuntu.com' or 'debian.org', it's wrong, and annoys the admins of
# those domains.  See also sender_canonical_maps.

MYORIGIN=$($POSTCONF -hx myorigin | tr 'A-Z' 'a-z')
if [ "X${MYORIGIN#/}" != "X${MYORIGIN}" ]; then
	MYORIGIN=$(tr 'A-Z' 'a-z' < $MYORIGIN)
fi
if [ "X$MYORIGIN" = Xubuntu.com ] || [ "X$MYORIGIN" = Xdebian.org ]; then
	echo "Invalid \$myorigin ($MYORIGIN), refusing to start"
	exit 1
fi

config_dir=$($POSTCONF -hx config_directory)
MAJOR_VER=$($POSTCONF -hx mail_version|cut -d. -f1)
COMPAT=$($POSTCONF -xh compatibility_level|cut -d. -f1)
[ $MAJOR_VER -ge 3 ] && [ $COMPAT -ge 1 ] && CHROOT_TEST="[yY]" || CHROOT_TEST="[-yY]"
# see if anything is running chrooted.
NEED_CHROOT=$(awk '/^[0-9a-z]/ && ($5 ~ "'"$CHROOT_TEST"'") { print "y"; exit}' ${config_dir}/master.cf)

# Functions for chroot setup

copyCAdir() {
	# Copy/update CA directory in chroot
	ca_path=$1
	case "$ca_path" in
	    '') :;; # no ca_path
	    $queue_dir/*) :;;  # skip stuff already in chroot
	    *)
		if test -d "$ca_path"; then
		    dest_dir="$queue_dir/${ca_path#/}"
		    # strip any/all trailing /
		    while [ "${dest_dir%/}" != "${dest_dir}" ]; do
			dest_dir="${dest_dir%/}"
		    done
		    new=0
		    if test -d "$dest_dir"; then
			# write to a new directory ...
			dest_dir="${dest_dir}.NEW"
			new=1
		    fi
		    mkdir --parent ${dest_dir}
		    # handle files in subdirectories
		    (cd "$ca_path" && find . -name '*.pem' -not -xtype l -print0 | cpio -0pdL --quiet "$dest_dir") 2>/dev/null ||
		        (echo failure copying certificates; exit 1)
		    c_rehash "$dest_dir" >/dev/null 2>&1
		    if [ "$new" = 1 ]; then
			# and replace the old directory
			rm -rf "${dest_dir%.NEW}"
			mv "$dest_dir" "${dest_dir%.NEW}"
		    fi
		fi
		;;
	esac
}

if [ -n "$NEED_CHROOT" ] && [ -n "$SYNC_CHROOT" ]; then
	# Make sure that the chroot environment is set up correctly.
	umask 022
	queue_dir=$($POSTCONF -hx queue_directory)
	cd "$queue_dir"

	# Set the smtp CA path to be copied, if specified
	sca_path=$($POSTCONF -hx smtp_tls_CApath)

	# Set the smtpd CA path to be copied, if specified
	dca_path=$($POSTCONF -hx smtpd_tls_CApath)

	# Copy or update each defined CA directory
	for CA in $sca_path $dca_path $chroot_extra_CAdir
		do
			copyCAdir $CA
		done

	# if we're using unix:passwd.byname, then we need to add etc/passwd.
	local_maps=$($POSTCONF -hx local_recipient_maps)
	if [ "X$local_maps" != "X${local_maps#*unix:passwd.byname}" ]; then
	    if [ "X$local_maps" = "X${local_maps#*proxy:unix:passwd.byname}" ]; then
		sed 's/^\([^:]*\):[^:]*/\1:x/' /etc/passwd > etc/passwd
		chmod a+r etc/passwd
	    fi
	fi

	FILES="etc/localtime etc/services etc/resolv.conf etc/hosts \
	    etc/host.conf etc/nsswitch.conf etc/nss_mdns.config  \
	    $chroot_extra_files"
	for file in $FILES; do
	    [ -d ${file%/*} ] || mkdir -p ${file%/*}
	    if [ -f /${file} ]; then rm -f ${file} && cp /${file} ${file}; fi
	    if [ -f  ${file} ]; then chmod a+rX ${file}; fi
	done
	# ldaps needs this. debian bug 572841
	(echo /dev/random; echo /dev/urandom) | cpio -pdL --quiet . 2>/dev/null || true
	rm -f usr/lib/zoneinfo/localtime
	mkdir -p usr/lib/zoneinfo
	ln -sf /etc/localtime usr/lib/zoneinfo/localtime

	LIBLIST=$(for name in gcc_s nss resolv; do
	    for f in /lib/*/lib${name}*.so* /lib/lib${name}*.so*; do
	       if [ -f "$f" ]; then  echo ${f#/}; fi;
	    done;
	done)

	if [ -n "$LIBLIST" ]; then
	    for f in $LIBLIST; do
		rm -f "$f"
	    done
	    tar cf - -C / $LIBLIST 2>/dev/null |tar xf -
	fi
fi
