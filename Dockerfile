# Runtime image for the packaged PetClinic jar in target/.
# CI passes BASE_REGISTRY=<name>.jfrog.io/petclinic-docker; the default is for local builds.

ARG BASE_REGISTRY=docker.io/library
ARG JRE_IMAGE=eclipse-temurin:21-jre-noble

FROM --platform=$BUILDPLATFORM ${BASE_REGISTRY}/${JRE_IMAGE} AS extract
WORKDIR /build
COPY target/spring-petclinic-*.jar application.jar
RUN java -Djarmode=tools -jar application.jar extract --layers --destination extracted

FROM ${BASE_REGISTRY}/${JRE_IMAGE}

ARG VERSION=unknown
ARG VCS_REF=unknown
LABEL org.opencontainers.image.title="spring-petclinic" \
      org.opencontainers.image.description="Spring PetClinic sample application" \
      org.opencontainers.image.licenses="Apache-2.0" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.revision="${VCS_REF}"

RUN groupadd --system --gid 10001 spring \
 && useradd --system --uid 10001 --gid spring --no-create-home --shell /usr/sbin/nologin spring

WORKDIR /application
COPY --from=extract /build/extracted/dependencies/ ./
COPY --from=extract /build/extracted/spring-boot-loader/ ./
COPY --from=extract /build/extracted/snapshot-dependencies/ ./
COPY --from=extract /build/extracted/application/ ./

USER 10001:10001

ENV MANAGEMENT_ENDPOINTS_WEB_EXPOSURE_INCLUDE=health,info

EXPOSE 8080

HEALTHCHECK --interval=15s --timeout=5s --start-period=60s --retries=3 \
  CMD curl -fsS http://localhost:8080/actuator/health || exit 1

ENTRYPOINT ["java", "-XX:MaxRAMPercentage=75.0", "-jar", "application.jar"]
