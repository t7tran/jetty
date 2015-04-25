FROM jdgoldie/jdk7

EXPOSE 8080

ADD http://eclipse.org/downloads/download.php?file=/jetty/stable-9/dist/jetty-distribution-9.2.4.v20141103.tar.gz&r=1 /opt/jetty.tar.gz

RUN tar -xvf /opt/jetty.tar.gz -C /opt/
RUN rm /opt/jetty.tar.gz
RUN mv /opt/jetty-distribution-* /opt/jetty
RUN rm -rf /opt/jetty/webapps.demo

WORKDIR /opt/jetty

CMD ["java", "-jar", "start.jar",  "jetty.home=/opt/jetty"]