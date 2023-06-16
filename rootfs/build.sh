#!/usr/bin/env bash

set -e

# build variables
LIQUIBASE_VERSION=4.2.2       # https://github.com/liquibase/liquibase/releases
DNSJAVA_VERSION=2.1.9         # https://repo1.maven.org/maven2/dnsjava/dnsjava
HAZELCAST_K8S_VERSION=1.5.5   # https://repo1.maven.org/maven2/com/hazelcast/hazelcast-kubernetes



#-------------------------------------------------------------------------
# create ordinary user ---------------------------------------------------
#-------------------------------------------------------------------------
addgroup alpine && adduser -S -D -G alpine alpine



#-------------------------------------------------------------------------
# install timezone data and crucial tools --------------------------------
#-------------------------------------------------------------------------
apk --no-cache add coreutils tar tzdata curl dpkg openssl



#-------------------------------------------------------------------------
# download and configure jetty -------------------------------------------
#-------------------------------------------------------------------------
curl -fsSL https://repo1.maven.org/maven2/org/eclipse/jetty/jetty-distribution/${JETTY_VERSION}/jetty-distribution-${JETTY_VERSION}.tar.gz -o /opt/jetty.tar.gz
mkdir -p /opt/jetty
tar -xvf /opt/jetty.tar.gz --strip-components=1 -C /opt/jetty
rm -rf /opt/jetty.tar.gz /opt/jetty/demo-base

# disable directory listing
sed -in '$!N;s@dirAllowed.*\n.*true@dirAllowed</param-name><param-value>false@;P;D' /opt/jetty/etc/webdefault.xml

# patch session-store-hazelcast configurations
for f in `grep -l 'jetty.session.hazelcast.configurationLocation' /opt/jetty/modules/*embedded*`; do
  sed -i 's|^#jetty.session.hazelcast.configurationLocation.*$|jetty.session.hazelcast.configurationLocation=/opt/jetty/etc/sessions/hazelcast/server-default.xml|g' $f
done
for f in `grep -l 'jetty.session.hazelcast.configurationLocation' /opt/jetty/modules/*remote*`; do
  sed -i 's|^#jetty.session.hazelcast.configurationLocation.*$|jetty.session.hazelcast.configurationLocation=/opt/jetty/etc/sessions/hazelcast/client-default.xml|g' $f
done

# add hazelcast kubernetes discovery plugin
# https://github.com/hazelcast/hazelcast-kubernetes
for f in /opt/jetty/modules/session-store-hazelcast-*.mod; do
  sed -ie "/\\[files\\]/a\\maven://dnsjava/dnsjava/${DNSJAVA_VERSION}/dnsjava-${DNSJAVA_VERSION}.jar|lib/hazelcast/dnsjava-${DNSJAVA_VERSION}.jar" $f
  sed -ie "/\\[files\\]/a\\maven://com.hazelcast/hazelcast-kubernetes/${HAZELCAST_K8S_VERSION}/hazelcast-kubernetes-${HAZELCAST_K8S_VERSION}.jar|lib/hazelcast/hazelcast-kubernetes-${HAZELCAST_K8S_VERSION}.jar" $f
done

# set all modules' properties under ini-template section to be overridable by system properties
# see syntax under Module Properties section at https://www.eclipse.org/jetty/documentation/9.4.x/custom-modules.html
for m in /opt/jetty/modules/*.mod; do sed -i '/ini-template/,${s/^\([^#][^=]\+[^?]\)=/\1?=/}' $m; done

# change default values of deploy module's properties
sed -i 's/name="jetty.deploy.scanInterval" default="1"/name="jetty.deploy.scanInterval" default="0"/g' /opt/jetty/etc/jetty-deploy.xml
sed -i 's/name="jetty.deploy.extractWars" default="true"/name="jetty.deploy.extractWars" default="false"/g' /opt/jetty/etc/jetty-deploy.xml



#-------------------------------------------------------------------------
# setup liquibase --------------------------------------------------------
#-------------------------------------------------------------------------
apk add --no-cache mariadb-connector-c-dev mysql-client xmlstarlet
wget https://github.com/liquibase/liquibase/releases/download/v${LIQUIBASE_VERSION}/liquibase-${LIQUIBASE_VERSION}.tar.gz -O /tmp/liquibase.tar.gz
mkdir /opt/liquibase && tar -C /opt/liquibase -xvf /tmp/liquibase.tar.gz
wget https://repo1.maven.org/maven2/mysql/mysql-connector-java/5.1.49/mysql-connector-java-5.1.49.jar -O /opt/liquibase/mysql-connector-java-5.jar
wget https://repo1.maven.org/maven2/com/mysql/mysql-connector-j/8.0.33/mysql-connector-j-8.0.33.jar   -O /opt/liquibase/mysql-connector-java-8.jar
ln -s /opt/liquibase/liquibase /usr/local/bin
rm -rf /tmp/liquibase.tar.gz



#-------------------------------------------------------------------------
# setup for non-root execution -------------------------------------------
#-------------------------------------------------------------------------
# note that Java default timezone relies on environment variable TZ
mkdir /etc/time
cp /usr/share/zoneinfo/$TZ /etc/time/localtime
echo $TZ > /etc/time/timezone
rm -rf /etc/{localtime,timezone}
ln -s /etc/time/localtime /etc/localtime
ln -s /etc/time/timezone /etc/timezone
chmod 666 /etc/time/* /opt/java/openjdk/lib/security/cacerts

# empty keystore: https://stackoverflow.com/a/60226695
#keytool -genkeypair -alias boguscert -storepass storePassword -keypass secretPassword -keystore /keystore.jks -dname "CN=Developer, OU=Department, O=Company, L=City, ST=State, C=CA"
#keytool -delete -alias boguscert -storepass storePassword -keystore /keystore.jks
#touch /keystore.p12
#chmod 666 /etc/time/* /usr/lib/jvm/java-1.8-openjdk/jre/lib/security/cacerts /keystore.jks /keystore.p12



#-------------------------------------------------------------------------
# finalise and cleanup ---------------------------------------------------
#-------------------------------------------------------------------------
chmod +x /entrypoint.sh
chown -R alpine:alpine /opt/jetty /opt/liquibase
apk del tar curl dpkg
rm -rf /apk /tmp/* /var/cache/apk/*