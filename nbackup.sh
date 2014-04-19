#!/bin/sh

self=`readlink -f "$0"`
scriptname=`basename "$self"`
scriptdir=${self%$scriptname}

. $scriptdir/config
. $nlogrotatepath/redirectlog.src.sh

if [ "$1" = "quiet" ]; then
	quietmode=1
	redirectlog
fi

if [ $rsync -eq 1 ] && [ $rdiffbackup -eq 1 ]; then
	echo "*** error: both rsync and rdiff-backup usage is turned on. can't do both."
	checklogsize
	exit 1
fi

if [ $rsync -eq 0 ] && [ $rdiffbackup -eq 0 ]; then
	echo "*** warning: both rsync and rdiff-backup usage is turned off." \
		"nbackup won't do anything this way."
fi

checkdstdirexists() {
	local dsthost=$1
	local dstdir=$2
	local sshport=$3

	echo "*** checking if $dst exists"
	if [ -z "$dsthost" ]; then
		mkdir -p $dstdir
	else
		ssh -p $sshport $dsthost "mkdir -p $dstdir"
	fi
}

backup() {
	local src=$1
	local dst=$2
	local sshport=$3
	local error=0

	if [ -z "$sshport" ]; then
		sshport=22
	fi

	echo "*** backing up $src to $dst"

	local dsthost
	local dstdir
	if [ -z "`echo $dst | grep ':'`" ]; then
		dstdir=$dst
	else
		dsthost=`echo $dst | cut -d':' -f1`
		dstdir=`echo $dst | cut -d':' -f2`
	fi

	if [ $rsync -eq 1 ]; then
		local dryrunparam
		if [ $dryrunrsync -eq 1 ]; then
			dryrunparam="--dry-run"
		fi

		checkdstdirexists "$dsthost" "$dstdir" "$sshport"

		echo "*** running rsync"
		if [ ! -z "$dsthost" ]; then
			rsync $dryrunparam --verbose --compress-level=9 --archive \
				--rsh "ssh -p $sshport" --ignore-errors --delete $src $dsthost:$dstdir
		else
			rsync $dryrunparam --verbose --compress-level=9 --archive \
				--ignore-errors --delete $src $dstdir
		fi
		if [ $? -ne 0 ]; then
			error=1
		fi
	fi

	if [ $rdiffbackup -eq 1 ]; then
		local remoteschema
		if [ ! -z "$dsthost" ]; then
			remoteschema="ssh -C -p $sshport %s rdiff-backup --server"
		fi

		local forceparam
		if [ $rdiffbackupforce -eq 1 ]; then
			forceparam="--force"
		fi

		checkdstdirexists "$dsthost" "$dstdir" "$sshport"

		echo "*** running rdiff-backup"
		if [ ! -z "$dsthost" ]; then
			rdiff-backup $forceparam --remote-schema "$remoteschema" $src $dsthost::$dstdir
		else
			rdiff-backup $forceparam $src $dstdir
		fi
		if [ $? -ne 0 ]; then
			error=1
		fi

		echo "*** running rdiff-backup, listing increments"
		if [ ! -z "$dsthost" ]; then
			rdiff-backup --remote-schema "$remoteschema" --list-increments $dsthost::$dstdir
		else
			rdiff-backup --list-increments $dstdir
		fi
		if [ $? -ne 0 ]; then
			error=1
		fi

		if [ ! -z "$removeoldertime" ]; then
			echo "*** running rdiff-backup, removing older increments than $removeoldertime"
			if [ ! -z "$dsthost" ]; then
				rdiff-backup --remote-schema "$remoteschema" --remove-older-than $removeoldertime --force $dsthost::$dstdir
			else
				rdiff-backup --remove-older-than $removeoldertime --force $dstdir
			fi
			if [ $? -ne 0 ]; then
				error=1
			fi
		fi
	fi

	echo "*** backing up $src to $dst finished."

	if [ $error != 0 ] && [ "$senderrormailcommand" != "" ] && [ "$quietmode" = "1" ]; then
		eval $senderrormailcommand
	fi

	checklogsize
}

. $scriptdir/config-paths
