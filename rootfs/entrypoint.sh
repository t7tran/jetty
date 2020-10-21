#!/usr/bin/env bash
set -e

[[ -n "$DEBUG" ]] && set -x

[[ -w /etc/time || -w /etc/time/localtime ]] && cp /usr/share/zoneinfo/$TZ /etc/time/localtime
[[ -w /etc/time || -w /etc/time/timezone  ]] && echo $TZ > /etc/time/timezone

if [[ -f "$CA_CERTIFICATE" ]]; then
	cacerts=/usr/lib/jvm/java-1.8-openjdk/jre/lib/security/cacerts
	[[ ! -w $cacerts ]] && echo $CA_CERTIFICATE cannot be added && exit 1
	if keytool -list -keystore $cacerts -storepass changeit -alias custom-root-ca &>/dev/null; then
		keytool -delete -keystore $cacerts -storepass changeit -alias custom-root-ca
	fi
	keytool -import -keystore $cacerts -storepass changeit -alias custom-root-ca -file $CA_CERTIFICATE -noprompt >/dev/null
fi

if [[ -f "$CERTIFICATE" && -f "$CERTIFICATE_KEY" && -n "$STORE_PASS" && -n "$KEY_PASS" ]]; then
	[[ ! -w /opt/jetty/certs ]] && echo /opt/jetty/certs not writable && exit 1
	CMD="openssl pkcs12 -export -in $CERTIFICATE -inkey $CERTIFICATE_KEY -out /opt/jetty/certs/keystore.p12"
	if [[ -f "$CA_CERTIFICATE" ]]; then
		CMD="$CMD -CAfile $CA_CERTIFICATE -caname 'Root CA'"
	fi
	eval "$CMD -password pass:$STORE_PASS"

	rm -rf /opt/jetty/certs/keystore.jks
	keytool -importkeystore \
		-deststorepass $STORE_PASS -destkeypass $KEY_PASS -destkeystore /opt/jetty/certs/keystore.jks \
		-srckeystore /opt/jetty/certs/keystore.p12 -srcstoretype PKCS12 -srcstorepass $STORE_PASS
	rm -rf /opt/jetty/certs/keystore.p12
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
