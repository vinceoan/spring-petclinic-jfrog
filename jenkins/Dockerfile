# Jenkins LTS controller for the petclinic pipeline: Docker CLI, JFrog CLI,
# pinned plugins and JCasC. Builds run on the built-in node.

ARG JENKINS_TAG=2.580.2-lts-jdk21
FROM jenkins/jenkins:${JENKINS_TAG}

USER root

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl \
 && install -m 0755 -d /etc/apt/keyrings \
 && curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc \
 && chmod a+r /etc/apt/keyrings/docker.asc \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
      > /etc/apt/sources.list.d/docker.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends docker-ce-cli docker-buildx-plugin docker-compose-plugin \
 && rm -rf /var/lib/apt/lists/*

ARG JF_VERSION=2.132.0
RUN arch="$(dpkg --print-architecture)" \
 && install -d -o jenkins -g jenkins /opt/jfrog-cli /opt/jfrog-cli/bin /opt/jfrog-cli/dependencies \
 && curl -fsSL -o /opt/jfrog-cli/bin/jf \
      "https://releases.jfrog.io/artifactory/jfrog-cli/v2-jf/${JF_VERSION}/jfrog-cli-linux-${arch}/jf" \
 && chmod 0755 /opt/jfrog-cli/bin/jf \
 && ln -s /opt/jfrog-cli/bin/jf /usr/local/bin/jf \
 && jf --version

RUN git config --system --add safe.directory /repo \
 && git config --system --add safe.directory /repo/.git

USER jenkins

ENV JAVA_OPTS="-Djenkins.install.runSetupWizard=false -Dhudson.plugins.git.GitSCM.ALLOW_LOCAL_CHECKOUT=true" \
    CASC_JENKINS_CONFIG=/var/jenkins_conf/casc.yaml \
    JFROG_CLI_OFFER_CONFIG=false \
    JFROG_CLI_REPORT_USAGE=false \
    JFROG_CLI_AVOID_NEW_VERSION_WARNING=true

COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt

COPY casc.yaml /var/jenkins_conf/casc.yaml
