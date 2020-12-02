# Steps to recover Management Subsystem in the event of failed ManagementRestore

:warning: **NOT COMPATIBLE WITH v10.0.0.0** :warning:

The following are steps and a script to allow you to recover the Management Subsystem in the event ManagementRestore fails and ManagementCluster is NOT READY.

This is a workaround to a known issue and will be addressed in a future release.

**Note: This procedure is only compatible with Linux and Mac environments.**

## Scenarios when this procedure and script are needed

- ManagementRestore stuck in `Pending` state for an unreasonable amount of time (eg. 2hrs+)
- During restore, postgres bootstrap pod is in `Error` state:
    ```
    $ kubectl get pods -n <your-namespace> | grep postgres-bootstrap
    NAME                                                READY   STATUS             RESTARTS   AGE
    management-36857253-postgres-bootstrap-6h4mj        0/1     Error              0          1h
    management-36857253-postgres-bootstrap-4ad6n        0/1     Error              0          30m
    management-36857253-postgres-bootstrap-w43dl        0/1     Error              0          52m
    management-36857253-postgres-bootstrap-mns2p        0/1     Error              0          15m
    ```
- Bootstrap pod fails with error:
    ```
    WARN: unable to find backup set with stop time less than '2020-09-29 16:09:52+00', latest backup set will be used
    WARN: unknown group in backup manifest mapped to current group
    ERROR: [040]: unable to restore to path '/pgwal/prod-mgmt-972f00ed-postgres-wal' because it contains files
        HINT: try using --delta if this is what you intended.
    Tue Sep 29 16:51:19 UTC 2020 ERROR: pgBackRest primary Creation: pgBackRest restore failed when creating primary
    ```

## Procedure

1. Ensure that you have `kubectl` installed from the location where you will run the script
   - https://kubernetes.io/docs/tasks/tools/install-kubectl/
   - Follow your Kubernetes provider instructions on how to find and connect to your Kubernetes cluster with `kubectl`

2. Verify you are able to run kubectl commands against your Kubernetes cluster
  ```
    $ kubectl get nodes
    NAME                            STATUS   ROLES    AGE   VERSION
    devtest-master.fyre.ibm.com     Ready    master   30h   v1.17.6
    devtest-worker-1.fyre.ibm.com   Ready    <none>   30h   v1.17.6
    devtest-worker-2.fyre.ibm.com   Ready    <none>   30h   v1.17.6
  ```
3. Copy the script below to the location where you wish to run the script from.
4. In a terminal, make the script executable with `chmod +x`
5. In a terminal, run `<the-script>.sh <namespace> <apic_name>`
  - where `<namespace>` is the namespace where your APIConnect Cluster capability is deployed eg. `default`
  - and `<apic_name>` is the name of your APIConnect Cluster capability

# Script locations for platform:

- [Kubernetes](recover-failed-mgmt-restore-k8s.sh)

- [VMware](recover-failed-mgmt-restore-ova.sh)
  
- [OpenShift or CP4i](recover-failed-mgmt-restore-cp4i.sh)
