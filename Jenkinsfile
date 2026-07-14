pipeline {
    agent any

    tools {
        jdk 'JDK21'
    }

    parameters {
        choice(
            name: 'SERVICE',
            choices: [
                'all',
                'metaarch-eureka-server',
                'metaarch-config-server',
                'metaarch-api-gateway',
                'org-access',
                'booking-system',
                'alerts-service'
            ],
            description: 'Build and deploy all services or only one service.'
        )

        string(
            name: 'GIT_BRANCH',
            defaultValue: 'main',
            description: 'Branch to build in each service repository.'
        )

        string(
            name: 'IMAGE_TAG',
            defaultValue: '',
            description: 'Image tag. Empty uses Jenkins build number and Git commit.'
        )

        string(
            name: 'REGISTRY',
            defaultValue: '',
            description: 'Leave empty for local Docker images.'
        )

        booleanParam(
            name: 'PUSH_IMAGES',
            defaultValue: false,
            description: 'Keep false for local Docker Desktop images.'
        )
    }

    environment {
        KUBE_NAMESPACE = 'metaarch'
        KUBECONFIG_CREDENTIAL_ID = 'metaarch-kubeconfig'
        REGISTRY_CREDENTIAL_ID = 'metaarch-registry'
         JAVA_HOME = '/usr/lib/jvm/java-21-openjdk-amd64'
         PATH = "${JAVA_HOME}/bin:${env.PATH}"
    }

    options {
        disableConcurrentBuilds()
        timestamps()
        skipDefaultCheckout(true)
    }

    stages {
        stage('Validate') {
            steps {
                script {
                    if (params.PUSH_IMAGES && !params.REGISTRY?.trim()) {
                        error('REGISTRY is required when PUSH_IMAGES is enabled.')
                    }
                }
            }
        }

        stage('Checkout Deployment Configuration') {
            steps {
                dir('deployment-config') {
                    checkout scm
                }
            }
        }

        stage('Build Images') {
            steps {
                script {
                    def services = serviceCatalog()

                    def selectedServices = params.SERVICE == 'all'
                        ? services.keySet() as List
                        : [params.SERVICE]

                    def builtImages = [:]

                    if (params.PUSH_IMAGES) {
                        withCredentials([
                            usernamePassword(
                                credentialsId: env.REGISTRY_CREDENTIAL_ID,
                                usernameVariable: 'REGISTRY_USER',
                                passwordVariable: 'REGISTRY_PASSWORD'
                            )
                        ]) {
                            sh '''
                                echo "$REGISTRY_PASSWORD" |
                                docker login "$REGISTRY" \
                                --username "$REGISTRY_USER" \
                                --password-stdin
                            '''
                        }
                    }

                    selectedServices.each { serviceName ->
                        def config = services.get(serviceName)
                        def repositoryUrl = env.getProperty(config.repositoryVariable)

                        if (!repositoryUrl) {
                            error(
                                "Jenkins environment variable " +
                                "${config.repositoryVariable} is not configured."
                            )
                        }

                        dir("sources/${serviceName}") {
                            deleteDir()

                            checkout([
                                $class: 'GitSCM',
                                branches: [[
                                    name: "*/${params.GIT_BRANCH}"
                                ]],
                                userRemoteConfigs: [[
                                    url: repositoryUrl
                                ]]
                            ])

                            def revision = sh(
                                script: 'git rev-parse --short=8 HEAD',
                                returnStdout: true
                            ).trim()

                            def tag = params.IMAGE_TAG?.trim()
                                ? params.IMAGE_TAG.trim()
                                : "${env.BUILD_NUMBER}-${revision}"

                            def registry = params.REGISTRY?.trim()

                            def image = registry
                                ? "${registry}/${config.image}:${tag}"
                                : "${config.image}:${tag}"

                            echo "Building application JAR for ${serviceName}"

                            sh '''
                                if [ -x "./mvnw" ]; then
                                    ./mvnw clean package -DskipTests
                                else
                                    mvn clean package -DskipTests
                                fi
                            '''

                            echo "Building Docker image: ${image}"

                            sh """
                                if ! command -v docker >/dev/null 2>&1; then
                                    echo "Docker is not installed on this Jenkins agent."
                                    exit 1
                                fi

                                if [ ! -S /var/run/docker.sock ]; then
                                    echo "Docker daemon is not available."
                                    exit 1
                                fi

                                if [ ! -d target ]; then
                                    echo "Maven target directory was not created."
                                    exit 1
                                fi

                                if ! ls target/*.jar >/dev/null 2>&1; then
                                    echo "No JAR file found inside target directory."
                                    exit 1
                                fi

                                ls -la target

                                docker build --pull -t "${image}" .
                            """

                            if (params.PUSH_IMAGES) {
                                sh """
                                    docker push "${image}"
                                """
                            }

                            builtImages.put(serviceName, image)
                        }
                    }

                    env.DEPLOY_IMAGES =
                        groovy.json.JsonOutput.toJson(builtImages)
                }
            }
        }

        stage('Deploy to Kubernetes') {
            steps {
                withCredentials([
                    file(
                        credentialsId: env.KUBECONFIG_CREDENTIAL_ID,
                        variable: 'KUBECONFIG_FILE'
                    )
                ]) {
                    script {
                        echo 'Applying shared Kubernetes configuration'
                        sh '''
                            kubectl \
                              --kubeconfig "$KUBECONFIG_FILE" \
                              apply \
                              -f deployment-config/k8s/config.yaml
                        '''

                        def services = serviceCatalog()

                        def images = readJSON text: env.DEPLOY_IMAGES

                        images.each { serviceName, image ->
                            def config = services.get(serviceName)

                            echo "Deploying ${serviceName} with image ${image}"

                            withEnv([
                                "DEPLOYMENT_NAME=${config.deployment}",
                                "CONTAINER_NAME=${config.container}",
                                "DEPLOY_IMAGE=${image}",
                                "DEPLOY_IMAGE_BASE=${config.image}",
                                "MANIFEST_PATH=${config.manifest ?: ''}"
                            ]) {
                                sh '''
                                    if [ -n "$MANIFEST_PATH" ] && [ -f "$MANIFEST_PATH" ]; then
                                        echo "Applying resources for $DEPLOYMENT_NAME with image $DEPLOY_IMAGE"
                                        RENDERED_MANIFEST="$(mktemp)"
                                        sed \
                                          "s|image: $DEPLOY_IMAGE_BASE:local|image: $DEPLOY_IMAGE|" \
                                          "$MANIFEST_PATH" > "$RENDERED_MANIFEST"
                                        kubectl \
                                          --kubeconfig "$KUBECONFIG_FILE" \
                                          -n "$KUBE_NAMESPACE" \
                                          apply -f "$RENDERED_MANIFEST"
                                        rm -f "$RENDERED_MANIFEST"
                                    elif ! kubectl \
                                      --kubeconfig "$KUBECONFIG_FILE" \
                                      -n "$KUBE_NAMESPACE" \
                                      get "deployment/$DEPLOYMENT_NAME" \
                                      >/dev/null 2>&1; then
                                            echo "Deployment $DEPLOYMENT_NAME does not exist and no application manifest is available."
                                            exit 1
                                    fi

                                    kubectl \
                                      --kubeconfig "$KUBECONFIG_FILE" \
                                      -n "$KUBE_NAMESPACE" \
                                      set image \
                                      "deployment/$DEPLOYMENT_NAME" \
                                      "$CONTAINER_NAME=$DEPLOY_IMAGE"

                                    if ! kubectl \
                                      --kubeconfig "$KUBECONFIG_FILE" \
                                      -n "$KUBE_NAMESPACE" \
                                      rollout status \
                                      "deployment/$DEPLOYMENT_NAME" \
                                      --timeout=5m; then
                                        echo "Rollout failed. Collecting Kubernetes diagnostics."
                                        kubectl \
                                          --kubeconfig "$KUBECONFIG_FILE" \
                                          -n "$KUBE_NAMESPACE" \
                                          get pods \
                                          -l "app=$DEPLOYMENT_NAME" \
                                          -o wide || true
                                        kubectl \
                                          --kubeconfig "$KUBECONFIG_FILE" \
                                          -n "$KUBE_NAMESPACE" \
                                          describe "deployment/$DEPLOYMENT_NAME" || true
                                        kubectl \
                                          --kubeconfig "$KUBECONFIG_FILE" \
                                          -n "$KUBE_NAMESPACE" \
                                          describe pods \
                                          -l "app=$DEPLOYMENT_NAME" || true
                                        kubectl \
                                          --kubeconfig "$KUBECONFIG_FILE" \
                                          -n "$KUBE_NAMESPACE" \
                                          logs \
                                          -l "app=$DEPLOYMENT_NAME" \
                                          --all-containers=true \
                                          --tail=200 || true
                                        exit 1
                                    fi
                                '''
                            }
                        }
                    }
                }
            }
        }
    }

    post {
        always {
            script {
                if (params.PUSH_IMAGES && params.REGISTRY?.trim()) {
                    sh """
                        docker logout "${params.REGISTRY.trim()}" || true
                    """
                }
            }

            cleanWs(
                deleteDirs: true,
                notFailBuild: true
            )
        }
    }
}

def serviceCatalog() {
    return [
        'metaarch-eureka-server': [
            repositoryVariable: 'EUREKA_REPO_URL',
            image: 'metaarch-eureka-server',
            deployment: 'metaarch-eureka-server',
            container: 'metaarch-eureka-server'
        ],

        'metaarch-config-server': [
            repositoryVariable: 'CONFIG_SERVER_REPO_URL',
            image: 'metaarch-config-server',
            deployment: 'metaarch-config-server',
            container: 'metaarch-config-server'
        ],

        'metaarch-api-gateway': [
            repositoryVariable: 'API_GATEWAY_REPO_URL',
            image: 'metaarch-api-gateway',
            deployment: 'metaarch-api-gateway',
            container: 'metaarch-api-gateway'
        ],

        'org-access': [
            repositoryVariable: 'ORG_ACCESS_REPO_URL',
            image: 'org-access',
            deployment: 'org-access',
            container: 'org-access'
        ],

        'booking-system': [
            repositoryVariable: 'BOOKING_SYSTEM_REPO_URL',
            image: 'booking-system',
            deployment: 'booking-system',
            container: 'booking-system'
        ],

        'alerts-service': [
            repositoryVariable: 'ALERTS_SERVICE_REPO_URL',
            image: 'alerts-service',
            deployment: 'alerts-service',
            container: 'alerts-service',
            manifest: 'deployment-config/k8s/alerts-service.yaml'
        ]
    ]
}
