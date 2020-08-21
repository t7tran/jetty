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
	
	keytool -importkeystore \
	    -deststorepass $STORE_PASS -destkeypass $KEY_PASS -destkeystore /keystore.jks \
        -srckeystore /keystore.p12 -srcstoretype PKCS12 -srcstorepass $STORE_PASS
    echo > /keystore.p12
fi

if [[ ! -z "$WAITFOR_HOST" && ! -z "$WAITFOR_PORT" ]]; then
	for (( i=1; i<=${TIMEOUT}; i++ )); do nc -zw1 $WAITFOR_HOST $WAITFOR_PORT && break || sleep 1; done
fi

[[ -d $LIQUIBASE_CHANGESET_DIR ]] && migrate.sh $LIQUIBASE_CHANGESET_DIR $LIQUIBASE_TARGET_CHANGESET

exec "$@"
