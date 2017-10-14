FROM anapsix/alpine-java:8_server-jre_unlimited

EXPOSE 8080

ADD http://central.maven.org/maven2/org/eclipse/jetty/jetty-distribution/9.4.6.v20170531/jetty-distribution-9.4.6.v20170531.tar.gz /opt/jetty.tar.gz

RUN tar -xvf /opt/jetty.tar.gz -C /opt/ \
 && rm -rf /opt/jetty.tar.gz \
 && mv /opt/jetty-distribution-* /opt/jetty \
 && rm -rf /opt/jetty/demo-base

WORKDIR /opt/jetty

CMD ["java", "-jar", "start.jar",  "jetty.home=/opt/jetty"]
