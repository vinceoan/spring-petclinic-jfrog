// Compiles, tests and packages Spring PetClinic as a Docker image, with every
// dependency resolved through JFrog Artifactory, and publishes the jar, the image
// and build-info. JFrog servers, credentials and the jf tool: jenkins/casc.yaml.

pipeline {
  agent any

  parameters {
    choice(name: 'ARTIFACTORY_TARGET', choices: ['cloud', 'selfhosted'],
           description: 'Artifactory for Maven, the jar and build-info. Docker images always use JFrog Cloud.')
    choice(name: 'IMAGE_PLATFORM', choices: ['linux/amd64', 'linux/arm64'],
           description: 'Image architecture, one per build.')
    booleanParam(name: 'XRAY_SCAN', defaultValue: false,
                 description: 'Scan the build with Xray (JFrog Cloud only).')
  }

  tools {
    jfrog 'jfrog-cli'
  }

  options {
    timestamps()
    timeout(time: 45, unit: 'MINUTES')
    disableConcurrentBuilds()
    buildDiscarder(logRotator(numToKeepStr: '20'))
  }

  environment {
    JFROG_CLI_BUILD_NAME = 'spring-petclinic'
    MAVEN_VIRTUAL = 'petclinic-maven'
    MAVEN_RELEASE_LOCAL = 'petclinic-maven-release-local'
    MAVEN_SNAPSHOT_LOCAL = 'petclinic-maven-snapshot-local'
    DOCKER_VIRTUAL = 'petclinic-docker'
    DOCKER_LOCAL = 'petclinic-docker-local'
    IMAGE_NAME = 'spring-petclinic'
  }

  stages {
    stage('Configure JFrog') {
      steps {
        script {
          if (!env.JFROG_URL) {
            error('JFROG_URL is not set (jenkins/.env)')
          }
          def selfhosted = params.ARTIFACTORY_TARGET == 'selfhosted'
          def platformUrl = (selfhosted ? env.JFROG_SELFHOSTED_URL : env.JFROG_URL).replaceAll('/+$', '')
          env.JF_SERVER_ID = selfhosted ? 'jfrog-selfhosted' : 'jfrog-cloud'
          env.JF_CREDENTIALS_ID = selfhosted ? 'jfrog-selfhosted-creds' : 'jfrog-cloud-creds'

          env.MVNW_REPOURL = "${platformUrl}/artifactory/${env.MAVEN_VIRTUAL}"
          env.JFROG_CLI_RELEASES_REPO = "${env.JF_SERVER_ID}/petclinic-jfrog-releases-remote"
          env.MAVEN_REPO_LOCAL = sh(returnStdout: true, script: 'printf %s "$HOME/.m2/repository-$ARTIFACTORY_TARGET"')

          env.DOCKER_REGISTRY = env.JFROG_URL.replaceFirst('^https?://', '').replaceFirst('/.*$', '')
          env.BASE_REGISTRY = "${env.DOCKER_REGISTRY}/${env.DOCKER_VIRTUAL}"
          env.TESTCONTAINERS_HUB_IMAGE_NAME_PREFIX = "${env.BASE_REGISTRY}/"
          env.COMPOSE_IMAGE_PREFIX = "${env.BASE_REGISTRY}/"
          env.DOCKER_CONFIG = "${env.WORKSPACE}@tmp/docker-config"

          echo """Maven:  ${env.MVNW_REPOURL} (${env.JF_SERVER_ID})
                 |Docker: ${env.BASE_REGISTRY}
                 |Image:  ${params.IMAGE_PLATFORM}""".stripMargin()
        }
        jf "rt ping --server-id=${env.JF_SERVER_ID}"
        jf "mvn-config --use-wrapper=true --server-id-resolve=${env.JF_SERVER_ID} --repo-resolve-releases=${env.MAVEN_VIRTUAL} --repo-resolve-snapshots=${env.MAVEN_VIRTUAL} --server-id-deploy=${env.JF_SERVER_ID} --repo-deploy-releases=${env.MAVEN_RELEASE_LOCAL} --repo-deploy-snapshots=${env.MAVEN_SNAPSHOT_LOCAL}"
        withCredentials([usernamePassword(credentialsId: 'jfrog-cloud-creds',
                                          usernameVariable: 'DOCKER_USER', passwordVariable: 'DOCKER_TOKEN')]) {
          sh '''
            mkdir -p "$DOCKER_CONFIG"
            printf %s "$DOCKER_TOKEN" | docker login "$DOCKER_REGISTRY" --username "$DOCKER_USER" --password-stdin
          '''
        }
      }
    }

    stage('Compile') {
      steps {
        jfMaven 'clean compile'
      }
    }

    stage('Test') {
      steps {
        jfMaven 'test'
      }
      post {
        always {
          junit 'target/surefire-reports/TEST-*.xml'
        }
      }
    }

    stage('Package') {
      steps {
        jfMaven 'install -DskipTests'
        script {
          def jar = sh(returnStdout: true, script: 'ls target/spring-petclinic-*.jar').trim()
          env.APP_VERSION = jar.replaceFirst('^target/spring-petclinic-', '').replaceFirst('\\.jar$', '')
          env.IMAGE_TAG = "${env.APP_VERSION}-${env.BUILD_NUMBER}-${params.IMAGE_PLATFORM.replaceFirst('^linux/', '')}"
          env.IMAGE_REF = params.ARTIFACTORY_TARGET == 'cloud' ?
              "${env.DOCKER_REGISTRY}/${env.DOCKER_LOCAL}/${env.IMAGE_NAME}:${env.IMAGE_TAG}" :
              "${env.IMAGE_NAME}:${env.IMAGE_TAG}"
        }
      }
    }

    stage('Build image') {
      steps {
        sh '''
          docker build --pull --provenance=false --platform "$IMAGE_PLATFORM" \
            --build-arg BASE_REGISTRY="$BASE_REGISTRY" \
            --build-arg VERSION="$APP_VERSION" \
            --build-arg VCS_REF="$GIT_COMMIT" \
            --tag "$IMAGE_REF" .
        '''
      }
    }

    stage('Smoke test') {
      steps {
        sh 'scripts/smoke-test.sh "$IMAGE_REF"'
      }
    }

    stage('Push image') {
      when {
        expression { params.ARTIFACTORY_TARGET == 'cloud' }
      }
      steps {
        jf "docker push ${env.IMAGE_REF} --server-id=jfrog-cloud --skip-login"
      }
    }

    stage('Publish build-info') {
      steps {
        jf 'rt build-collect-env'
        jf 'rt build-add-git'
        jf "rt build-publish --server-id=${env.JF_SERVER_ID}"
      }
    }

    stage('Xray scan') {
      when {
        expression { params.XRAY_SCAN && params.ARTIFACTORY_TARGET == 'cloud' }
      }
      steps {
        jf "build-scan ${env.JFROG_CLI_BUILD_NAME} ${env.BUILD_NUMBER} --server-id=jfrog-cloud --vuln --fail=false"
      }
    }
  }

  post {
    always {
      sh 'if [ -n "$DOCKER_CONFIG" ]; then rm -rf "$DOCKER_CONFIG"; fi'
    }
  }
}

def jfMaven(String goals) {
  withCredentials([usernamePassword(credentialsId: env.JF_CREDENTIALS_ID,
                                    usernameVariable: 'MVNW_USERNAME', passwordVariable: 'MVNW_PASSWORD')]) {
    jf "mvn ${goals} -B -ntp -Dmaven.repo.local=${env.MAVEN_REPO_LOCAL}"
  }
}
