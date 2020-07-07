#!/bin/bash

ns=$1
[[ -z "$ns" ]] && echo "./deploy-pgo-client.sh <namespace>" && exit 1

mgmt_name=$(kubectl get mgmt -n $ns -o yaml | grep name: | head -n1 | awk -F ": " '{print $2}')
cluster_name=$(kubectl get mgmt $mgmt_name -n $ns  -o yaml | grep db: | awk -F ": " '{print $2}')
image_registry=$(kubectl get mgmt $mgmt_name -n $ns  -o yaml | grep imageRegistry: | awk -F ": " '{print $2}')
image_pull_secret=$(kubectl get mgmt $mgmt_name -n $ns  -o yaml | grep -A1 imagePullSecrets | tail -n1 | awk -F "- " '{print $2}')

echo
echo "Management name:      $mgmt_name"
echo "Database name:        $cluster_name"
echo "Image Registry:       $image_registry"
echo "Image Pull Secret:    $image_pull_secret"
echo


cat <<EOF | kubectl create -f -
{
    "apiVersion": "apps/v1",
    "kind": "Deployment",
    "metadata": {
        "name": "pgo-client",
        "namespace": "$ns",
        "labels": {
            "vendor": "crunchydata"
        }
    },
    "spec": {
        "replicas": 1,
        "selector": {
                "matchLabels": {
                        "name": "pgo-client",
                        "vendor": "crunchydata"
                }
        },
        "template": {
            "metadata": {
                "labels": {
                    "name": "pgo-client",
                    "vendor": "crunchydata"
                }
            },
            "spec": {
                "imagePullSecrets": [
                    { "name": "$image_pull_secret" }
                ],
                "containers": [
                    {
                        "name": "pgo",
                                "image": "$image_registry/ibm-apiconnect-management-pgo-client:ubi7-4.3.1",
                        "imagePullPolicy": "IfNotPresent",
                        "env": [
                            {
                                "name": "PGO_APISERVER_URL",
                                "value": "https://postgres-operator.$ns.svc:8443"
                            },
                            {
                                "name": "PGOUSERNAME",
                                "valueFrom": {
                                    "secretKeyRef": {
                                        "name": "pgouser-admin",
                                        "key": "username"
                                    }
                                }
                            },
                            {
                                "name": "PGOUSERPASS",
                                "valueFrom": {
                                    "secretKeyRef": {
                                        "name": "pgouser-admin",
                                        "key": "password"
                                    }
                                }
                            },
                            {
                                "name": "PGO_CA_CERT",
                                "value": "pgo-tls/tls.crt"
                            },
                            {
                                "name": "PGO_CLIENT_CERT",
                                "value": "pgo-tls/tls.crt"
                            },
                            {
                                "name": "PGO_CLIENT_KEY",
                                "value": "pgo-tls/tls.key"
                            }
                        ],
                        "volumeMounts": [
                            {
                                "name": "pgo-tls-volume",
                                "mountPath": "pgo-tls"
                            }
                        ]
                    }
                ],
                "volumes": [
                    {
                        "name": "pgo-tls-volume",
                        "secret": {
                            "secretName": "$mgmt_name-client",
                            "items": [
                                {
                                    "key": "tls.crt",
                                    "path": "tls.crt"
                                },
                                {
                                    "key": "tls.key",
                                    "path": "tls.key"
                                }
                            ]
                        }
                    }
                ]
            }
        }
    }
}
EOF