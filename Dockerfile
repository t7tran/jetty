FROM amazoncorretto:8u392-alpine-jre

MAINTAINER Tien Tran

ENV JETTY_VERSION=9.4.53.v20231009 \
    TZ=Australia/Melbourne \
    STORE_PASS=changme \
    KEY_PASS=changme \
    WAITFOR_HOST= \
    WAITFOR_PORT= \
    TIMEOUT=120

COPY rootfs /

RUN apk --no-cache add coreutils bash && \
    chmod +x /build.sh && /build.sh && rm -rf /build.sh

WORKDIR /opt/jetty

EXPOSE 8080

USER alpine

ENTRYPOINT ["/entrypoint.sh"]
CMD ["java", "-jar", "start.jar", "jetty.home=/opt/jetty"]
