#!/usr/bin/env bash
set -e

[[ -n "$DEBUG" ]] && set -x

[[ -w /etc/time || -w /etc/time/localtime ]] && cp /usr/share/zoneinfo/$TZ /etc/time/localtime
[[ -w /etc/time || -w /etc/time/timezone  ]] && echo $TZ > /etc/time/timezone

if [[ -f "$CA_CERTIFICATE" ]]; then
	cacerts=${CA_STORE:-/etc/ssl/certs/java/cacerts}
	capass=${CA_PASS:-changeit}
	if [[ ! -f $cacerts ]]; then
		[[ ! -w `dirname $cacerts` ]] && echo `dirname $cacerts` is readonly && exit 1
		keytool -genkeypair -alias boguscert -storepass $capass -keypass $capass -keystore $cacerts -dname "CN=Developer, OU=Department, O=Company, L=City, ST=State, C=CA"
		keytool -delete -alias boguscert -storepass $capass -keystore $cacerts
	fi
	[[ ! -w $cacerts ]] && echo $CA_CERTIFICATE cannot be added && exit 1
	if keytool -list -keystore $cacerts -storepass $capass -alias custom-root-ca &>/dev/null; then
		keytool -delete -keystore $cacerts -storepass $capass -alias custom-root-ca
	fi
	keytool -import -keystore $cacerts -storepass $capass -alias custom-root-ca -file $CA_CERTIFICATE -noprompt >/dev/null
fi

if [[ -f "$CERTIFICATE" && -f "$CERTIFICATE_KEY" && -n "$STORE_PASS" && -n "$KEY_PASS" ]]; then
	keystore=${KEY_STORE:-/opt/jetty/certs/keystore.jks}
	[[ ! -w `dirname $keystore` ]] && echo `dirname $keystore` not writable && exit 1
	CMD="openssl pkcs12 -export -in $CERTIFICATE -inkey $CERTIFICATE_KEY -out ${keystore}.p12"
	if [[ -f "$CA_CERTIFICATE" ]]; then
		CMD="$CMD -CAfile $CA_CERTIFICATE -caname 'Root CA'"
	fi
	eval "$CMD -password pass:$STORE_PASS"

	rm -rf ${keystore}
	keytool -importkeystore \
		-deststorepass $STORE_PASS -destkeypass $KEY_PASS -destkeystore ${keystore} \
		-srckeystore ${keystore}.p12 -srcstoretype PKCS12 -srcstorepass $STORE_PASS
	rm -rf ${keystore}.p12
fi

if [[ ! -z "$WAITFOR_HOST" && ! -z "$WAITFOR_PORT" ]]; then
	for (( i=1; i<=${TIMEOUT}; i++ )); do nc -zw1 $WAITFOR_HOST $WAITFOR_PORT && break || sleep 1; done
fi

var_dir() {
  if [[ $1 -le 0 ]]; then
    echo $LIQUIBASE_CHANGESET_DIR
  else
    var="LIQUIBASE_CHANGESET_DIR_$1"
    echo ${!var}
  fi
}
var_cs() {
  if [[ $1 -le 0 ]]; then
    echo $LIQUIBASE_TARGET_CHANGESET
  else
    var="LIQUIBASE_TARGET_CHANGESET_$1"
    echo ${!var}
  fi
}

for i in {0..9}; do
  if [[ -d `var_dir $i` ]]; then
    # bypass KEEP_RUNNING logic inside migrate.sh
    keep_running=$keep_running$KEEP_RUNNING
    KEEP_RUNNING=
    migrate.sh `var_dir $i` `var_cs $i`
  fi
done

# only keep running when being told and command is empty
if [[ -n "$keep_running" ]]; then
  if [[ -z "$@" ]]; then
    trap : TERM INT; tail -f /dev/null & wait
  else
    KEEP_RUNNING=$keep_running
  fi
fi

exec "$@"
