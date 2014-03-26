#!/bin/sh

scriptname=`basename $0`
scriptdir=${0%$scriptname}

. $scriptdir/config
. $nlogrotatepath/redirectlog.src.sh

if [ "$1" = "quiet" ]; then
	quietmode=1
	redirectlog
fi

if [ $rsync -eq 1 ] && [ $rdiffbackup -eq 1 ]; then
	echo "*** error: both rsync and rdiff-backup usage is turned on. can't do both."
	exit 1
fi

if [ $rsync -eq 0 ] && [ $rdiffbackup -eq 0 ]; then
	echo "*** warning: both rsync and rdiff-backup usage is turned off." \
		"nbackup won't do anything this way."
fi

backup() {
	src=$1
	dst=$2

	echo "*** backing up $src to $dst"

	if [ $rsync -eq 1 ]; then
		dryrunparam=
		if [ $dryrunrsync -eq 1 ]; then
			dryrunparam="--dry-run"
		fi

		#ssh -p $sshport $dsthost "[ ! -d $dst ]"
		#direxists=$?
		#if [ "$direxists" = "0" ]; then
			echo "*** running rsync"
			rsync $dryrunparam --verbose --compress-level=9 --archive \
				--rsh "ssh -p $sshport" --progress --ignore-errors --delete $src $dsthost:$dst
		#fi
	fi

	if [ $rdiffbackup -eq 1 ]; then
		remoteschema="ssh -C -p $sshport %s rdiff-backup --server"

		forceparam=
		if [ $rdiffbackupforce -eq 1 ]; then
			forceparam="--force"
		fi

		echo "*** running rdiff-backup"
		rdiff-backup $forceparam --remote-schema "$remoteschema" $src $dsthost::$dst
		echo "*** running rdiff-backup, listing increments"
		rdiff-backup --remote-schema "$remoteschema" --list-increments $dsthost::$dst
		if [ ! -z "$removeoldertime" ]; then
			echo "*** running rdiff-backup, removing older increments"
			rdiff-backup --remote-schema "$remoteschema" --remove-older-than $removeoldertime --force $dsthost::$dst
		fi
	fi

	echo "*** backing up $src to $dst finished."

	checklogsize
}

. $scriptdir/config-paths
