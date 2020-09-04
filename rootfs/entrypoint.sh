#!/bin/bash
set -e

cp /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

if [[ -f "$CA_CERTIFICATE" ]]; then
	cacerts=/usr/lib/jvm/java-1.8-openjdk/jre/lib/security/cacerts
	keytool -import -keystore $cacerts -storepass changeit \
		-file $CA_CERTIFICATE -alias custom-root-ca -noprompt >/dev/null
fi

if [[ -f "$CERTIFICATE" && -f "$CERTIFICATE_KEY" && -n "$STORE_PASS" && -n "$KEY_PASS" ]]; then
	CMD="openssl pkcs12 -export -in $CERTIFICATE -inkey $CERTIFICATE_KEY -out /keystore.p12"
	if [[ -f "$CA_CERTIFICATE" ]]; then
		CMD="$CMD -CAfile $CA_CERTIFICATE -caname 'Root CA'"
	fi
	eval "$CMD -password pass:$STORE_PASS"

	keytool -storepasswd -new $STORE_PASS -keystore /keystore.jks -storepass storePassword &>/dev/null
	keytool -importkeystore \
		-deststorepass $STORE_PASS -destkeypass $KEY_PASS -destkeystore /keystore.jks \
		-srckeystore /keystore.p12 -srcstoretype PKCS12 -srcstorepass $STORE_PASS
	echo > /keystore.p12
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
  # bypass KEEP_RUNNING logic inside migrate.sh
  keep_running=$keep_running$KEEP_RUNNING
  KEEP_RUNNING=
  [[ -d `var_dir $i` ]] && migrate.sh `var_dir $i` `var_cs $i`
done

# only keep running when being told and command is empty
if [[ -n "$keep_running" && -z "$@" ]]; then
  trap : TERM INT; tail -f /dev/null & wait
fi

exec "$@"
