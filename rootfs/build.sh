#!/usr/bin/env bash

# build variables
GOSU_VERSION=1.12             # https://github.com/tianon/gosu/releases
LIQUIBASE_VERSION=4.1.1       # https://github.com/liquibase/liquibase/releases
HAZELCAST_VERSION=3.12.6      # https://repo1.maven.org/maven2/com/hazelcast/hazelcast
DNSJAVA_VERSION=2.1.9         # https://repo1.maven.org/maven2/dnsjava/dnsjava
HAZELCAST_K8S_VERSION=1.5.4   # https://repo1.maven.org/maven2/com/hazelcast/hazelcast-kubernetes



#-------------------------------------------------------------------------
# create ordinary user ---------------------------------------------------
#-------------------------------------------------------------------------
addgroup alpine && adduser -S -D -G alpine alpine



#-------------------------------------------------------------------------
# install timezone data and crucial tools --------------------------------
#-------------------------------------------------------------------------
apk --no-cache add coreutils tar tzdata curl dpkg openssl



#-------------------------------------------------------------------------
# install gosu -----------------------------------------------------------
#-------------------------------------------------------------------------
dpkgArch="$(dpkg --print-architecture | awk -F- '{ print $NF }')"
curl -fsSL "https://github.com/tianon/gosu/releases/download/${GOSU_VERSION}/gosu-$dpkgArch" -o /usr/local/bin/gosu
chmod +x /usr/local/bin/gosu
gosu nobody true



#-------------------------------------------------------------------------
# download and configure jetty -------------------------------------------
#-------------------------------------------------------------------------
curl -fsSL https://repo1.maven.org/maven2/org/eclipse/jetty/jetty-distribution/${JETTY_VERSION}/jetty-distribution-${JETTY_VERSION}.tar.gz -o /opt/jetty.tar.gz
mkdir -p /opt/jetty
tar -xvf /opt/jetty.tar.gz --strip-components=1 -C /opt/jetty
rm -rf /opt/jetty.tar.gz /opt/jetty/demo-base

# fix gibberish in module file
sed -i 's|jar.*$|jar|g' /opt/jetty/modules/gcloud-datastore.mod

# disable directory listing
sed -in '$!N;s@dirAllowed.*\n.*true@dirAllowed</param-name><param-value>false@;P;D' /opt/jetty/etc/webdefault.xml

# fix maven urls resolved to outdated central.maven.org
for f in `ls -1 /opt/jetty/modules/*.mod`; do
  for u in `grep -oE 'maven://[^|]+' $f`; do
    path=`echo $u | cut -d '/' -f 3`
    path=${path//./\/}
    artifact=`echo $u | cut -d '/' -f 4`
    version=`echo $u | cut -d '/' -f 5`
    regex="s|$u|https://repo1.maven.org/maven2/$path/$artifact/$version/$artifact-$version.jar|g"
    sed -i $regex $f
  done
done

# patch session-store-hazelcast configurations
sed -i 's|</New>|<Set name="configurationLocation"><Property name="jetty.session.hazelcast.configurationLocation" /></Set></New>|g' /opt/jetty/etc/sessions/hazelcast/default.xml
sed -i 's|</New>|<Set name="configurationLocation"><Property name="jetty.session.hazelcast.configurationLocation" /></Set></New>|g' /opt/jetty/etc/sessions/hazelcast/remote.xml
for f in `grep -l 'jetty.session.hazelcast.configurationLocation' /opt/jetty/modules/*embedded*`; do
  sed -i 's|^#jetty.session.hazelcast.configurationLocation=$|jetty.session.hazelcast.configurationLocation=/opt/jetty/etc/sessions/hazelcast/server-default.xml|g' $f
done
for f in `grep -l 'jetty.session.hazelcast.configurationLocation' /opt/jetty/modules/*remote*`; do
  sed -i 's|^#jetty.session.hazelcast.configurationLocation=$|jetty.session.hazelcast.configurationLocation=/opt/jetty/etc/sessions/hazelcast/client-default.xml|g' $f
done

# add hazelcast kubernetes discovery plugin
# https://github.com/hazelcast/hazelcast-kubernetes
for f in /opt/jetty/modules/session-store-hazelcast-*.mod; do
  sed -ie '/hazelcast-[0-9.]\+.jar/a\\https://repo1.maven.org/maven2/dnsjava/dnsjava/${DNSJAVA_VERSION}/dnsjava-${DNSJAVA_VERSION}.jar|lib/hazelcast/dnsjava-${DNSJAVA_VERSION}.jar' $f
  sed -ie '/hazelcast-[0-9.]\+.jar/a\\https://repo1.maven.org/maven2/com/hazelcast/hazelcast-kubernetes/${HAZELCAST_K8S_VERSION}/hazelcast-kubernetes-${HAZELCAST_K8S_VERSION}.jar|lib/hazelcast/hazelcast-kubernetes-${HAZELCAST_K8S_VERSION}.jar' $f
done

# upgrade hazelcast
for m in `grep -l hazelcast /opt/jetty/modules/*`; do
  sed -i 's;/hazelcast/[0-9.]\+/;/hazelcast/${HAZELCAST_VERSION}/;g' $m
  sed -i 's;/hazelcast-[0-9.]\+.jar;/hazelcast-${HAZELCAST_VERSION}.jar;g' $m
  sed -i 's;/hazelcast-client/[0-9.]\+/;/hazelcast-client/${HAZELCAST_VERSION}/;g' $m
  sed -i 's;/hazelcast-client-[0-9.]\+.jar;/hazelcast-client-${HAZELCAST_VERSION}.jar;g' $m
  sed -i 's;/hazelcast-all/[0-9.]\+/;/hazelcast-all/${HAZELCAST_VERSION}/;g' $m
  sed -i 's;/hazelcast-all-[0-9.]\+.jar;/hazelcast-all-${HAZELCAST_VERSION}.jar;g' $m
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
wget https://repo1.maven.org/maven2/mysql/mysql-connector-java/8.0.22/mysql-connector-java-8.0.22.jar -O /opt/liquibase/mysql-connector-java-8.jar
ln -s /opt/liquibase/liquibase /usr/local/bin
rm -rf /tmp/liquibase.tar.gz



#-------------------------------------------------------------------------
# setup for non-root execution -------------------------------------------
#-------------------------------------------------------------------------
cp /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone
# empty keystore: https://stackoverflow.com/a/60226695
keytool -genkeypair -alias boguscert -storepass storePassword -keypass secretPassword -keystore /keystore.jks -dname "CN=Developer, OU=Department, O=Company, L=City, ST=State, C=CA"
keytool -delete -alias boguscert -storepass storePassword -keystore /keystore.jks
touch /keystore.p12
chmod 666 /etc/localtime /etc/timezone /usr/lib/jvm/java-1.8-openjdk/jre/lib/security/cacerts /keystore.jks /keystore.p12



#-------------------------------------------------------------------------
# finalise and cleanup ---------------------------------------------------
#-------------------------------------------------------------------------
chmod +x entrypoint.sh
chown -R alpine:alpine /opt/jetty /opt/liquibase
apk del tar curl dpkg
rm -rf /apk /tmp/* /var/cache/apk/*