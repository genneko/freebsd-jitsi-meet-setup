#!/bin/sh
#
# freebsd-jitsi-meet-setup/setup.sh
#
# https://github.com/genneko/freebsd-jitsi-meet-setup
#
prog=$(basename "$0")
bindir=$(dirname "$(readlink -f "$0")")

echoerr() {
	echo "$@" >&2
}

err_exit() {
	if [ $# -gt 0 ]; then
		echoerr "$@"
	fi
	exit 1
}

usage_exit() {
	if [ $# -gt 0 ]; then
		echoerr "$@"
	fi
	echoerr "usage: $prog [-aBpr] [-n LOCAL:PUBLIC] [-e DAYS] FQDN CERT_PATH KEY_PATH"
	echoerr "       -a: use apache web server instead of nginx"
	echoerr "       -B: do not backup existing files"
	echoerr "       -p: install missing packages instead of exiting with an error."
	echoerr "       -r: require authentication for room creation"
	echoerr "           (without this flag, any user can create a room)"
	echoerr "       -N LOCAL:PUBLIC: specify local/public IPv4 addresses"
	echoerr "	                 when using jitsi-meet behind a NAT"
	echoerr "       -e DAYS: duration of self-signed certs used by prosody (default 365)."
	exit 1
}

gen_selfsigned_cert() {
	local fqdn expiry san certdir
	if [ -n "$CERTDIR" ]; then
		certdir=$CERTDIR
	else
		certdir=.
	fi
	if [ $# -ge 1 ]; then
		fqdn=$1
		san="DNS:$fqdn"
		shift
		expiry=$1
		[ "$expiry" -lt 1 ] && expiry=365
		shift
		for n in "$@"; do
			san="$san,DNS:$n"
		done
		openssl req -new -x509 -days $expiry -sha256 -keyout "$certdir/$fqdn.key" -nodes -out "$certdir/$fqdn.crt" -subj "/C=JP/O=Prosody/CN=$fqdn" -addext "subjectAltName = $san"
	fi
}

backup_file() {
	local file=$1 ts=$2
	[ "$dobackup" -eq 0 ] && return 1
	[ -f "$file" ] || return 1
	echoerr "NOTICE: backup $file.$ts"
	cp -p "$file" "$file.$ts"
}

webserver=nginx
dobackup=1
installpkg=0
mkroom=anon
nat=0
certexpiry=365
while getopts "aBprN:e:" opt
do
	case "$opt" in
		a) webserver=apache24 ;;
		B) dobackup=0 ;;
		p) installpkg=1 ;;
		r) mkroom=auth ;;
		N) nat=1
			SERVER_LOCAL_IP4ADDR=${OPTARG%%:*}
			SERVER_PUBLIC_IP4ADDR=${OPTARG##*:}
			;;
		e)
		        if [ "$OPTARG" -gt 0 ]; then
				certexpiry=$OPTARG
			fi
			;;
		*) usage_exit ;;
	esac
done
shift $(( OPTIND - 1 ))

PRE_CONFIG_LIST=$(cat <<EOB
usr/local/etc/pkg
usr/local/etc/pkg/repos
usr/local/etc/pkg/repos/FreeBSD.conf
EOB
)

PKG_LIST=$(cat <<EOB
jitsi-meet
jitsi-videobridge
jicofo
prosody
EOB
)

CONFIG_LIST=$(cat <<EOB
usr/local/etc/prosody/prosody.cfg.lua
usr/local/etc/prosody/conf.d
usr/local/etc/prosody/conf.d/jitsi.cfg.lua
usr/local/etc/jitsi/videobridge/jitsi-videobridge.conf
usr/local/etc/jitsi/jicofo/jicofo.conf
usr/local/www/jitsi-meet/config.js
usr/local/etc/newsyslog.conf.d
EOB
)

if [ $webserver = "apache24" ]; then
	CONFIG_LIST="$CONFIG_LIST
usr/local/etc/apache24/httpd.conf
usr/local/etc/apache24/extra/httpd-ssl.conf
usr/local/etc/newsyslog.conf.d
usr/local/etc/newsyslog.conf.d/apache24.conf"
	PKG_LIST="$PKG_LIST
apache24"
else
	CONFIG_LIST="$CONFIG_LIST
usr/local/etc/nginx/nginx.conf
usr/local/etc/newsyslog.conf.d
usr/local/etc/newsyslog.conf.d/nginx.conf"
	PKG_LIST="$PKG_LIST
nginx"
fi

if [ $mkroom = "auth" ]; then
	CONFIG_LIST="$CONFIG_LIST
usr/local/etc/jitsi/jicofo/sip-communicator.properties"
fi

if [ $nat -eq 1 ]; then
	if [ "$SERVER_LOCAL_IP4ADDR" = "" ] || [ "$SERVER_PUBLIC_IP4ADDR" = "" ]; then
		usage_exit "Please specify LOCAL:PUBLIC for NAT (e.g. -n 192.168.10.5/10.1.1.5)"
	fi
	CONFIG_LIST="$CONFIG_LIST
usr/local/etc/jitsi/videobridge/sip-communicator.properties"
fi

SERVER_FQDN=$1
SERVER_CERT_PATH=$2
SERVER_KEY_PATH=$3

if [ -z "$SERVER_FQDN" ]; then
	usage_exit "Please specify SERVER_FQDN (e.g. jitsi.example.com)."
fi
if [ -z "$SERVER_CERT_PATH" ]; then
	usage_exit "Please specify SERVER_CERT_PATH (e.g. /usr/local/etc/letsencrypt/live/jitsi.example.com/fullchain.pem)."
fi
if [ -z "$SERVER_KEY_PATH" ]; then
	usage_exit "Please specify SERVER_KEY_PATH (e.g. /usr/local/etc/letsencrypt/live/jitsi.example.com/privkey.pem)."
fi

JVB_COMPONENT_SECRET=$(openssl rand -hex 16)
FOCUS_COMPONENT_SECRET=$(openssl rand -hex 16)
FOCUS_USER_SECRET=$(openssl rand -hex 16)

TS=$(date '+%F_%T')

cd "$bindir" || err_exit "ERROR: cannot chdir to $bindir."

if [ $installpkg -eq 1 ]; then
echoerr
echoerr "###"
echoerr "### Preparing latest package set"
echoerr "###"
sleep 1
for file in $PRE_CONFIG_LIST; do
	echoerr ""
	echoerr "# $file"
	sleep 1
	srcfile="$file"
	if [ -d "$file" ]; then
		if [ ! -d "/$file" ]; then
			echoerr "NOTICE: mkdir /$file"
			mkdir -p "/$file"
		else
			echoerr "INFO: nothing to do for /$file"
		fi
		continue
	fi
	if [ -n "$file" ] && [ -e "/$file" ]; then
		if cmp -s "$file" "/$file"; then
			echoerr "INFO: already there /$file"
			continue
		fi
		backup_file "/$file" "$TS"
	fi

	echoerr "NOTICE: install /$file"
	cp -p "$srcfile" "/$file"
done
fi

echoerr
echoerr "###"
echoerr "### Checking if the required packages/ports have been installed."
echoerr "###"
sleep 1
missing=
[ $installpkg -eq 1 ] && pkg update
for pkg in $PKG_LIST; do
	if pkg_info=$(pkg query %n-%v "$pkg" 2>/dev/null); then
		echoerr "INFO: $pkg_info installed"
		continue
	fi
	if [ $installpkg -eq 0 ]; then
		echoerr "ERROR: $pkg not found."
		missing="$missing $pkg"
	else
		echoerr -n "NOTICE: $pkg not found. Installing..."
		if pkg install -y "$pkg" >/dev/null 2>&1; then
			echoerr "done"
		else
			echoerr "failed"
			exit 1
		fi
	fi
done
if [ -n "$missing" ]; then
	echoerr "ERROR: please install the missing packages."
	echoerr
	echoerr "    pkg install$missing"
	echoerr
	exit 1
fi


echoerr
echoerr "###"
echoerr "### Installing custom config files"
echoerr "###"
sleep 1
for file in $CONFIG_LIST; do
	echoerr ""
	echoerr "# $file"
	sleep 1
	srcfile="$file"
	if [ ! -f "$file" ] && [ -f "$file.$mkroom" ]; then
		srcfile="$file.$mkroom"
	elif [ "$(readlink -f "$file")" = "/$file" ]; then
		echoerr "WARNING: Source and destination files are the same. Skipping..."
		continue
	fi
	if [ -d "$file" ]; then
		if [ ! -d "/$file" ]; then
			echoerr "NOTICE: mkdir /$file"
			mkdir -p "/$file"
		else
			echoerr "INFO: nothing to do for /$file"
		fi
		continue
	fi
	if [ -n "$srcfile" ] && [ -f "$srcfile" ]; then
		m4 \
			-DSERVER_FQDN="$SERVER_FQDN" \
			-DSERVER_CERT_PATH="$SERVER_CERT_PATH" \
			-DSERVER_KEY_PATH="$SERVER_KEY_PATH" \
			-DJVB_COMPONENT_SECRET="$JVB_COMPONENT_SECRET" \
			-DFOCUS_COMPONENT_SECRET="$FOCUS_COMPONENT_SECRET" \
			-DFOCUS_USER_SECRET="$FOCUS_USER_SECRET" \
			-DSERVER_LOCAL_IP4ADDR="$SERVER_LOCAL_IP4ADDR" \
			-DSERVER_PUBLIC_IP4ADDR="$SERVER_PUBLIC_IP4ADDR" \
			"$srcfile" > "/$file.tmp"

		if [ -e "/$file" ]; then
			if cmp -s "/$file.tmp" "/$file"; then
				echoerr "INFO: already there /$file"
				rm -f "/$file.tmp"
				continue
			fi
			backup_file "/$file" "$ts"
		fi
		echoerr "NOTICE: install /$file"
		cp -p "/$file.tmp" "/$file"
		rm -f "/$file.tmp"
	fi
done

echoerr
echoerr "###"
echoerr "### Adding an XMPP user for internal use"
echoerr "###"
sleep 1
prosodyctl deluser "focus@auth.$SERVER_FQDN" >/dev/null 2>&1
prosodyctl register focus "auth.$SERVER_FQDN" "$FOCUS_USER_SECRET"

if [ "$mkroom" = "auth" ]; then
	echoerr
	echoerr "###"
	echoerr "### Adding an XMPP user to create conference rooms"
	echoerr "###"
	sleep 1
	prosodyctl adduser "admin@$SERVER_FQDN" 
fi

echoerr
echoerr "###"
echoerr "### Generating certificates used by internal processes"
echoerr "###"
sleep 1
#prosodyctl cert generate $SERVER_FQDN
#prosodyctl cert generate auth.$SERVER_FQDN

CERTDIR=/var/db/prosody
CRT1=$CERTDIR/$SERVER_FQDN.crt
KEY1=$CERTDIR/$SERVER_FQDN.key
CRT2=$CERTDIR/auth.$SERVER_FQDN.crt
KEY2=$CERTDIR/auth.$SERVER_FQDN.key
JKSDIR=/usr/local/etc/jitsi/jicofo
JKS=$JKSDIR/truststore.jks

backup_file "$KEY1" "$ts"
backup_file "$CRT1" "$ts"
gen_selfsigned_cert "$SERVER_FQDN" "$certexpiry" "jitsi-videobridge.$SERVER_FQDN" "conference.$SERVER_FQDN" "focus.$SERVER_FQDN" "auth.$SERVER_FQDN" && chown prosody:prosody "$KEY1" "$CRT1"

backup_file "$KEY2" "$ts"
backup_file "$CRT2" "$ts"
gen_selfsigned_cert "auth.$SERVER_FQDN" "$certexpiry" && chown prosody:prosody "$KEY2" "$CRT2"

backup_file "$JKS" "$ts"
[ -f "$JKS" ] && keytool -delete -noprompt -keystore $JKS -alias prosody -storepass changeit
keytool -importcert -noprompt -keystore "$JKS" -alias prosody -storepass changeit -file "$CRT2"

echoerr
echoerr "###"
echoerr "### Enabling services"
echoerr "###"
sleep 1
sysrc prosody_enable=YES
sysrc "${webserver}_enable=YES"
sysrc jitsi_videobridge_enable=YES
sysrc jicofo_enable=YES

echoerr
echoerr "###"
echoerr "### Finished!"
echoerr "###"
sleep 1
echoerr "Check your configs and run the following commands to start services."
echoerr ""
echoerr "    service prosody start"
echoerr "    service $webserver start"
echoerr "    service jitsi-videobridge start"
echoerr "    service jicofo start"
echoerr ""
echoerr "Some additional notes:"
echoerr
echoerr "*** Firewall/NAT ***"
echoerr "jitsi-meet requires the following ports are open."
echoerr "      443/tcp"
echoerr "     4443/tcp"
echoerr "    10000/udp"
if [ $nat -eq 1 ]; then
echoerr
echoerr "If you are using PF, add rules like below to /etc/pf.conf and"
echoerr "reload the PF by 'service pf reload'."
echoerr "(tighten those rules according to your needs)"
echoerr "    # \$ext_if is an interface name which has $SERVER_PUBLIC_IP4ADDR"
echoerr "    rdr pass inet proto tcp to (\$ext_if) port 443 -> $SERVER_LOCAL_IP4ADDR"
echoerr "    rdr pass inet proto tcp to (\$ext_if) port 4443 -> $SERVER_LOCAL_IP4ADDR"
echoerr "    rdr pass inet proto udp to (\$ext_if) port 10000 -> $SERVER_LOCAL_IP4ADDR"
else
echoerr
echoerr "If you are using PF, add rules like below to /etc/pf.conf and"
echoerr "reload the PF by 'service pf reload'."
echoerr "(tighten those rules according to your needs)"
echoerr "    pass in log proto tcp to port 443"
echoerr "    pass in log proto tcp to port 4443"
echoerr "    pass in log proto udp to port 10000"
fi
echoerr
echoerr "*** Certificates ***"
echoerr "If your server certificate in the following file:"
echoerr "    $SERVER_CERT_PATH"
echoerr "is selfsigned or issued by a private certificate authority (CA),"
echoerr "you have to isntall the server certificate itself or"
echoerr "the private CA certificate on your browser or operating system."
echoerr "Note that mobile jitsi apps doesn't seem to work with the private"
echoerr "certificate."
echoerr
echoerr "If the server certificate is issued by a public CA such as"
echoerr "Let's encrypt, it might be okay that you do nothing about it."
echoerr
echoerr
echoerr "If all set, launch your browser and access the following URL:"
echoerr "    https://$SERVER_FQDN/"
echoerr
echoerr "Enjoy!"


