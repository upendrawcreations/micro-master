pipeline {
    agent any

    parameters {
        choice(
            name: 'SERVICE',
            choices: [
                'all',
                'metaarch-eureka-server',
                'metaarch-config-server',
                'metaarch-api-gateway',
                'org-access',
                'booking-system'
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
                        def services = serviceCatalog()

                        def images =
                            new groovy.json.JsonSlurperClassic()
                                .parseText(env.DEPLOY_IMAGES)

                        images.each { serviceName, image ->
                            def config = services.get(serviceName)

                            echo "Deploying ${serviceName} with image ${image}"

                            sh """
                                kubectl \
                                --kubeconfig "${KUBECONFIG_FILE}" \
                                -n "${env.KUBE_NAMESPACE}" \
                                set image \
                                deployment/${config.deployment} \
                                ${config.container}="${image}"
                            """

                            sh """
                                kubectl \
                                --kubeconfig "${KUBECONFIG_FILE}" \
                                -n "${env.KUBE_NAMESPACE}" \
                                rollout status \
                                deployment/${config.deployment} \
                                --timeout=5m
                            """
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
        ]
    ]
}