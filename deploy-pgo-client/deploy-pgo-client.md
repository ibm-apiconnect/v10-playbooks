# Steps to deploy the Crunchy pgo-client in the Management Subsystem for Kubernetes Installations

The following are steps and a script  to allow you to deploy the Crunchy pgo-client in case it is needed for postgres operator or database debugging.  
The script requires one parameter, the `mgmt-namespace`. This will ensure that the pgo-client is deployed in the same namespace as the postgres cluster.  
This script should not be required after v10 FP1 as there will be a means to turn this on via the apiconnect-operator 

Once the script has been run get the name of the pgo-client pod by running the following command.  

```
kubectl get pods -l "name=pgo-client" -n <mgmt-namespace>
```

Using this name you can now exec onto this pods and use the pgo cli to interact with the postgres operator.  
For reference of what commands can be run using the pgo cli refer to the latest Crunchy Operator documentation   
https://access.crunchydata.com/documentation/postgres-operator/latest/pgo-client/reference/  

**Note:** These cli commands **must** only be run by a IBM support engineer as running some can be harmful to the deployed management subsystem  

To exec onto the pod and run the pgo version command for example do the following  

```
kubectl exec -it $pgo_client_pod_name -n $mgmt-namespace -- pgo version
```

______

## Script to create the pgo client

```
#!/bin/bash

ns=$1
[[ -z "$ns" ]] && echo "./deploy-pgo-client.sh <namespace>" && exit 1

mgmt_name=$(kubectl get mgmt -n $ns -o yaml | grep name: | head -n1 | awk -F ": " '{print $2}')
cluster_name=$(kubectl get mgmt $mgmt_name -n $ns  -o yaml | grep db: | awk -F ": " '{print $2}')
version=$(kubectl get mgmt $mgmt_name -n $ns  -o yaml | grep version: | awk -F ": " '{print $2}')
image_registry=$(kubectl get mgmt $mgmt_name -n $ns  -o yaml | grep imageRegistry: | awk -F ": " '{print $2}')
image_pull_secret=$(kubectl get mgmt $mgmt_name -n $ns  -o yaml | grep -A1 imagePullSecrets | tail -n1 | awk -F "- " '{print $2}')

echo
echo "Management name:      $mgmt_name"
echo "Database name:        $cluster_name"
echo "Product version:      $version"
echo "Image Registry:       $image_registry"
echo "Image Pull Secret:    $image_pull_secret"
echo

if [[ "$version" == "10.0.1.0"* ]]; then
    pgo_client_image_tag="sha256:c728dee3458e38efced0474f95cd84f168f065a47761e483cd3551cdde8c824b"
elif [[ "$version" == "10.0.0.0"* ]]; then
    pgo_client_image_tag="sha256:3295df5e00f11c072895627fdc5e84ca911c378b5ceb8b7c12ca55dfb7066891"
else
    echo "Unsupported product version ${version} for ManagementCluster" && exit 1
fi 

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
                        "image": "$image_registry/ibm-apiconnect-management-pgo-client@$pgo_client_image_tag",
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
```