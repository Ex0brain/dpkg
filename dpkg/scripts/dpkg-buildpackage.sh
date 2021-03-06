#!/bin/sh

set -e

version="1.10.10"; # This line modified by Makefile

progname="`basename \"$0\"`"

showversion () {
	echo "Debian $progname version $version."

	echo "
Copyright (C) 1996 Ian Jackson.
Copyright (C) 2000 Wichert Akkerman
This is free software; see the GNU General Public Licence version 2 or
later for copying conditions. There is NO warranty."
}

usage () {
	cat <<END
Usage: $progname [<options> ...]

Options:
  -r<gain-root-command>
  -p<sign-command>
  -d             do not check build dependencies and conflicts.
  -D             check build dependencies and conflicts.
  -k<keyid>      the key to use for signing.
  -sgpg          the sign-command is called like GPG.
  -spgp          the sign-command is called like PGP.
  -us            unsigned source.
  -uc            unsigned changes.
  -a<arch>       Debian architecture we build for (implies -d).
  -b             binary-only, do not build source. } also passed to
  -B             binary-only, no arch-indep files. } dpkg-genchanges
  -S             source only, no binary files.     }
  -t<system>     set GNU system type.           } passed to dpkg-architecture
  -v<version>    changes since version <version>.      }
  -m<maint>      maintainer for package is <maint>.    }
  -e<maint>      maintainer for release is <maint>.    } only passed
  -C<descfile>   changes are described in <descfile>.  } to dpkg-genchangs
  -si (default)  src includes orig for rev. 0 or 1.    }
  -sa            uploaded src always includes orig.    }
  -sd            uploaded src is diff and .dsc only.   }
  -sn            force Debian native source format.      } only passed
  -s[sAkurKUR]   see dpkg-source for explanation.        } to dpkg-source
  -nc            do not clean source tree (implies -b).
  -tc            clean source tree when finished.
  -ap            add pause before starting signature process.
  -W             turn certain errors into warnings.       } passed to
  -E             when -W is turned on, -E turned it off.  } dpkg-source
  -i[<regex>]    ignore diffs of files matching regex.    } only passed
  -I<filename>   filter out files when building tarballs. } to dpkg-source
  -h, --help     show this help message.
      --version  show the version.
END
}

rootcommand=''
signcommand=""
if (( [ -n "$GNUPGHOME" ] && [ -e "$GNUPGHOME" ] ) || [ -e "$HOME/.gnupg" ] ) && \
		command -v gpg > /dev/null 2>&1; then
	signcommand=gpg
elif command -v pgp > /dev/null 2>&1 ; then
	signcommand=pgp
fi

signsource='withecho signfile'
signchanges='withecho signfile'
cleansource=false
checkbuilddep=true
checkbuilddep_args=''
binarytarget=binary
sourcestyle=''
changesversion=''
since=''
maint=''
desc=''
noclean=false
usepause=false
warnable_error=0
passopts=''

while [ $# != 0 ]
do
	value="`echo x\"$1\" | sed -e 's/^x-.//'`"
	case "$1" in
	-h|--help)
		usage; exit 0 ;;
	--version)
		showversion; exit 0 ;;
	-r*)	rootcommand="$value" ;;
	-p*)	signcommand="$value" ;;
	-k*)	signkey="$value" ;;
	-d)	checkbuilddep=false ;;
	-D)	checkbuilddep=true ;;
	-sgpg)  forcesigninterface=gpg ;;
	-spgp)  forcesigninterface=pgp ;;
	-us)	signsource=: ;;
	-uc)	signchanges=: ;;
	-ap)	usepause="true";;
	-a*)    targetarch="$value"; checkbuilddep=false ;;
	-si)	sourcestyle=-si ;;
	-sa)	sourcestyle=-sa ;;
	-sd)	sourcestyle=-sd ;;
	-s[nsAkurKUR])    passopts="$passopts $1";; # passed to dpkg-source
        -i*)    diffignore=$1;;
	-I*)	tarignore="$tarignore $1";;
	-tc)	cleansource=true ;;
	-t*)    targetgnusystem="$value" ;;          # Order DOES matter!
	-nc)	noclean=true; if [ -z "$binaryonly" ]; then binaryonly=-b; fi ;;
	-b)	binaryonly=-b; [ "$sourceonly" ] && \
			{ echo >&2 "$progname: cannot combine $1 and -S" ; exit 2 ; } ;;
	-B)	binaryonly=-B; checkbuilddep_args=-B; binarytarget=binary-arch; [ "$sourceonly" ] && \
			{ echo >&2 "$progname: cannot combine $1 and -S" ; exit 2 ; } ;;
	-S)	sourceonly=-S; checkbuilddep=false; [ "$binaryonly" ] && \
			{ echo >&2 "$progname: cannot combine $binaryonly and $1" ; exit 2 ; } ;;
	-v*)	since="$value" ;;
	-m*)	maint="$value" ;;
	-e*)	changedby="$value" ;;
	-C*)	desc="$value" ;;
	-W)	warnable_error=1; passopts="$passopts -W";;
	-E)	warnable_error=0; passopts="$passopts -E";;
	*)	echo >&2 "$progname: unknown option or argument $1"
		usage; exit 2 ;;
	esac
	shift
done

if [ -z "$signcommand"  ] ; then
	signsource=:
	signchanges=:
fi

if test -n "$forcesigninterface" ; then
  signinterface=$forcesigninterface
else
  signinterface=$signcommand
fi
if [ -n "$signcommand" ] && [ "$signinterface" != "gpg" ] && [ "$signinterface" != "pgp" ] ; then
    echo >&2 "$progname: unknown sign command, assuming pgp style interface"
fi

mustsetvar () {
	if [ "x$2" = x ]; then
		echo >&2 "$progname: unable to determine $3" ; \
		exit 1
	else
		echo "$progname: $3 $2" ; \
		eval "$1=\"\$2\""
	fi
}

curd="`pwd`"
dirn="`basename \"$curd\"`"
mustsetvar package "`dpkg-parsechangelog | sed -n 's/^Source: //p'`" "source package is"
mustsetvar changesversion "`dpkg-parsechangelog | sed -n 's/^Version: //p'`" "source version is"
if [ -n "$changedby" ]; then maintainer="$changedby";
elif [ -n "$maint" ]; then maintainer="$maint";
else mustsetvar maintainer "`dpkg-parsechangelog | sed -n 's/^Maintainer: //p'`" "source changed by"; fi
eval `dpkg-architecture -a${targetarch} -t${targetgnusystem} -s -f`

if [ x$sourceonly = x ]; then
	mustsetvar arch "`dpkg-architecture -a${targetarch} -t${targetgnusystem} -qDEB_HOST_ARCH`" "host architecture"
else
	arch=source
fi
mustsetvar sversion "`echo \"$changesversion\" | perl -pe 's/^\d+://'`" "source version without epoch"
pv="${package}_${sversion}"
pva="${package}_${sversion}_${arch}"

signfile () {
	if test "$signinterface" = "gpg" ; then
		(cat "../$1" ; echo "") | \
		$signcommand --local-user "${signkey:-$maintainer}" --clearsign --armor \
			--textmode  > "../$1.asc" 
	else
		$signcommand -u "${signkey:-$maintainer}" +clearsig=on -fast <"../$1" \
			>"../$1.asc"
	fi
	status=$?
	if [ $status -eq 0 ]; then
		mv -- "../$1.asc" "../$1"
	else
		/bin/rm -f "../$1.asc"
	fi
	echo
	return $status
}

withecho () {
        echo " $@" >&2
	"$@"
}

if [ "$checkbuilddep" = "true" ]; then
	if ! dpkg-checkbuilddeps $checkbuilddep_args; then
		echo >&2 "$progname: Build dependencies/conflicts unsatisfied; aborting."
		echo >&2 "$progname: (Use -d flag to override.)"
		exit 3
	fi
fi

set -- $binaryonly $sourceonly $sourcestyle
if [ -n "$maint"	]; then set -- "$@" "-m$maint"		; fi
if [ -n "$changedby"	]; then set -- "$@" "-e$changedby"	; fi
if [ -n "$since"	]; then set -- "$@" "-v$since"		; fi
if [ -n "$desc"		]; then set -- "$@" "-C$desc"		; fi

if [ x$noclean != xtrue ]; then
	withecho $rootcommand debian/rules clean
fi
if [ x$binaryonly = x ]; then
	cd ..; withecho dpkg-source $passopts $diffignore $tarignore -b "$dirn"; cd "$dirn"
fi
if [ x$sourceonly = x ]; then
	withecho debian/rules build 
	withecho $rootcommand debian/rules $binarytarget
fi
if [ "$usepause" = "true" ] && \
   ( [ "$signchanges" != ":" ] || ( [ -z "$binaryonly" ] && [ "$signsource" != ":" ] ) ) ; then
    echo Press the return key to start signing process
    read dummy_stuff
fi

signerrors=
if [ x$binaryonly = x ]; then
	if ! $signsource "$pv.dsc"; then
		signerrors="(WARNING: Failed to sign .dsc and .changes file)"
		signchanges=:
	fi
fi
chg=../"$pva.changes"
withecho dpkg-genchanges "$@" >"$chg"

fileomitted () {
	set +e
	test -z "`sed -n '/^Files:/,/^[^ ]/ s/'$1'$//p' <$chg`"
	fir=$?
	set -e
	return $fir
}	


if fileomitted '\.deb'; then
	# source only upload
	if fileomitted '\.diff\.gz'; then
		srcmsg='source only upload: Debian-native package'
	elif fileomitted '\.orig\.tar\.gz'; then
		srcmsg='source only, diff-only upload (original source NOT included)'
	else
		srcmsg='source only upload (original source is included)'
	fi
else
	srcmsg='full upload (original source is included)'
	if fileomitted '\.dsc'; then
		srcmsg='binary only upload (no source included)'
	elif fileomitted '\.diff\.gz'; then
		srcmsg='full upload; Debian-native package (full source is included)'
	elif fileomitted '\.orig\.tar\.gz'; then
		srcmsg='binary and diff upload (original source NOT included)'
	else
		srcmsg='full upload (original source is included)'
	fi
fi

if ! $signchanges "$pva.changes"; then
	signerrors="(WARNING: Failed to sign .changes file)"
fi

if $cleansource; then
	withecho $rootcommand debian/rules clean
fi

echo "dpkg-buildpackage: $srcmsg"
if [ -n "$signerrors" ]; then
	echo >&2 $signerrors
	exit 1
fi
