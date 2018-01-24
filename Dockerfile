FROM anapsix/alpine-java:8_server-jre_unlimited

MAINTAINER Tien Tran

ENV TZ Australia/Melbourne

COPY entrypoint.sh /

RUN addgroup alpine && adduser -G alpine -s /bin/bash -D alpine && \
    apk --no-cache add tar curl tzdata dpkg && \
    # install gosu
    dpkgArch="$(dpkg --print-architecture | awk -F- '{ print $NF }')" && \
    curl -fsSL "https://github.com/tianon/gosu/releases/download/1.10/gosu-$dpkgArch" -o /usr/local/bin/gosu && \
    chmod +x /usr/local/bin/gosu && \
    gosu nobody true && \
    # complete gosu
    chmod u+x entrypoint.sh && \
    curl -fsSL http://central.maven.org/maven2/org/eclipse/jetty/jetty-distribution/9.4.7.v20170914/jetty-distribution-9.4.7.v20170914.tar.gz -o /opt/jetty.tar.gz && \
    tar -xvf /opt/jetty.tar.gz -C /opt/ && \
    rm -rf /opt/jetty.tar.gz && \
    mv /opt/jetty-distribution-* /opt/jetty && \
    rm -rf /opt/jetty/demo-base && \
    chown -R alpine:alpine /opt/jetty && \
    apk del tar curl dpkg && \
    rm -rf /apk /tmp/* /var/cache/apk/*

WORKDIR /opt/jetty

EXPOSE 8080

ENTRYPOINT ["/entrypoint.sh"]
CMD ["gosu", "alpine", "bash", "-c", "java -jar start.jar jetty.home=$PWD"]
