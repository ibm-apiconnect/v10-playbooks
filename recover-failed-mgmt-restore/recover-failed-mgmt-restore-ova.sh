#!/bin/bash

fn=$(echo $(basename $0))

ns=$1
op_ns=$ns
[[ -z "$ns" ]] && echo "Usage: $fn <namespace> <mgmt_name>" && exit 1

mgmt_name=$2

abort() {
    echo "Answer was: $1"
    echo "Abort"
    exit 1
}

echo
echo "This script will walkthrough failed restore recovery procedure for your Management subsystem in your APIConnect Cluster"
echo

mgmt_out=$(kubectl get managementcluster ${mgmt_name} -n $ns)
if [ "$?" -eq 1 ]; then
    echo
    echo "Management Cluster \"$mgmt_name\" does not exist in namespace \"$ns\""
    echo
    abort
fi

echo
echo "Please update your ManagementCluster spec via the command-line with 'kubectl edit managementcluster $mgmt_name -n $ns'"
echo "Please add the following template section to your spec:"
cat << EOF
spec:
  template:
  - name: lur-schema
    enabled: false
EOF
echo
read -p "Proceed when the configuration is updated. Proceed? (y/n) " -n 1 -r
echo

if [[ ! $REPLY =~ ^[Yy]$ ]]
then
    abort $REPLY
fi

echo
read -p "ibm-apiconnect operator will need to be stopped temporarily. There will be no loss of data. Proceed? (y/n) " -n 1 -r
echo

if [[ ! $REPLY =~ ^[Yy]$ ]]
then
    abort $REPLY
fi

echo "Scaling down APIC Operator..."
kubectl scale deploy ibm-apiconnect --replicas=0 -n $op_ns
if [ "$?" -eq 1 ]; then
  echo "Error scaling down ibm-apiconnect deployment"
  kubectl get deploy ibm-apiconnect -n $op_ns
  if [ "$?" -eq 1 ]; then
    echo
    read -p "If running the APIC Operator locally, please manually stop the APIC Operator now. Proceed when stopped. Proceed? (y/n) " -n 1 -r
    echo

    if [[ ! $REPLY =~ ^[Yy]$ ]]
    then
        echo "Answer was: $REPLY"
        echo
        abort
    fi
  else
    exit 1
  fi
fi

out=$(kubectl get cm ${mgmt_name}-oplock -n $ns)

if [ "$?" -eq 0 ]; then
  #Halt script from running and ask user do they want to continue
  echo
  read -p "Script will now clean operator locks for Management subsystem. Proceed? (y/n) " -n 1 -r
  echo

  #If the user replies with anything other than Y or y stop the script
  if [[ ! $REPLY =~ ^[Yy]$ ]]
  then
      abort $REPLY
  fi

  kubectl delete cm ${mgmt_name}-oplock -n $ns
fi

out=$(kubectl get managementbackups -n $ns | grep -v Ready | tail -n+2)
num_backups=$(echo "$out" | wc -l)

if [ "$num_backups" -gt 0 ]; then
  #Halt script from running and ask user do they want to continue
  echo
  read -p "Script will now clean non-complete ManagementBackups custom resources. No actual backups are deleted, only custom resources. Proceed? (y/n) " -n 1 -r
  echo

  #If the user replies with anything other than Y or y stop the script
  if [[ ! $REPLY =~ ^[Yy]$ ]]
  then
      abort $REPLY
  fi

  if [ ! -z $out ]; then
    while IFS= read -r line; do
      name=$(echo $line | awk '{print $1}')
      kubectl delete managementbackup $name -n $ns
    done <<<"$out"
  else 
    echo "No ManagementBackups to clean"
  fi
fi

out=$(kubectl get managementrestore -n $ns | grep -v Ready | tail -n+2)
num_restores=$(echo "$out" | wc -l)

if [ "$num_restores" -gt 0 ]; then
  #Halt script from running and ask user do they want to continue
  echo
  read -p "Script will now clean non-complete ManagementRestores. Proceed? (y/n) " -n 1 -r
  echo

  #If the user replies with anything other than Y or y stop the script
  if [[ ! $REPLY =~ ^[Yy]$ ]]
  then
      abort $REPLY
  fi

  if [ ! -z $out ]; then
    while IFS= read -r line; do
      name=$(echo $line | awk '{print $1}')
      kubectl delete managementrestore $name -n $ns
    done <<<"$out"
  else 
    echo "No ManagementRestores to clean"
  fi
fi

out=$(kubectl get managementdbupgrade -n $ns | grep -v Complete | tail -n+2)
num_upgrades=$(echo "$out" | wc -l)

if [ "$num_upgrades" -gt 0 ]; then
  #Halt script from running and ask user do they want to continue
  echo
  read -p "Script will now clean non-complete ManagementDBUpgrades. Proceed? (y/n) " -n 1 -r
  echo

  #If the user replies with anything other than Y or y stop the script
  if [[ ! $REPLY =~ ^[Yy]$ ]]
  then
      abort $REPLY
  fi

  if [ ! -z $out ]; then
    while IFS= read -r line; do
      name=$(echo $line | awk '{print $1}')
      kubectl delete managementdbupgrade $name -n $ns
    done <<<"$out"
  fi
fi

echo "Scaling up APIC Operator..."
echo

#Scaling the apiconnect operator back up. When the operator has scaled back up it will see that it is missing postgres deployments and will recreate them
kubectl scale deploy ibm-apiconnect --replicas=1 -n $op_ns
if [ "$?" -eq 1 ]; then
  echo "Error scaling up ibm-apiconnect deployment"
  kubectl get deploy ibm-apiconnect -n $op_ns
  if [ "$?" -eq 1 ]; then
    read -p "If running the APIC Operator locally, please manually start the APIC Operator. Proceed when started. Proceed? (y/n) " -n 1 -r
    echo

    if [[ ! $REPLY =~ ^[Yy]$ ]]
    then
        abort $REPLY
    fi
  else
    exit 1
  fi
fi

kubectl get pods -n $op_ns | grep ibm-apiconnect | grep -q Running > /dev/null 2>&1 
while [ "$?" -eq 1 ]; do
  echo "Waiting for ibm-apiconnect operator in $ns to be Ready..."
  sleep 60
  kubectl get pods -n $op_ns | grep ibm-apiconnect | grep -q Running > /dev/null 2>&1 
done
echo "Waiting for ibm-apiconnect operator in $ns to be Ready..."
sleep 60
echo "ibm-apiconnect operator in $ns ready"

backup_name=""
REPLY=""
ec=1
while [[ "$ec" -eq 1 ]]; do
  echo
  echo "Please select a ManagementBackup to restore:"
  echo
  kubectl get managementbackup -n $ns

  echo 
  echo "Enter the ManagementBackup name and press [ENTER]:"
  read backup_name
  echo

  if [ ! -z $backup_name ]; then
    kubectl get managementbackup $backup_name -n $ns
    ec="$?"
  fi
done

rangeEnd=$(kubectl get managementbackup $backup_name -n $ns -o jsonpath="{..status.info.rangeEnd}")
let "rangeEnd=rangeEnd+1" 
pitr_target=""

if [[ "$OSTYPE" == "darwin"* ]]; then
  pitr_target=$(date -r $rangeEnd '+%F %T%z')
  pitr_target=${pitr_target::${#pitr_target}-2}
else
  pitr_target=$(date -d @$rangeEnd '+%F %T%z')
  pitr_target=${pitr_target::-2}
fi

echo "Backup to restore: $backup_name"
echo "PITR Target:       $pitr_target"

echo
read -p "Please ensure the above two values are populated before proceeded. Proceed? (y/n) " -n 1 -r
echo

if [[ ! $REPLY =~ ^[Yy]$ ]]
then
    abort $REPLY
fi

ec=1
while [ "$ec" -eq 1 ]; do
  echo "Creating ManagemenRestore in namespace $ns..."
cat <<EOF | kubectl create -f -
apiVersion: management.apiconnect.ibm.com/v1beta1
kind: ManagementRestore
metadata:
  generateName: management-
  namespace: $ns
spec:
  backupName: $backup_name
  pitrTarget: '$pitr_target'
EOF
  
  if [ "$?" -eq 1 ]; then
    echo "Error creating ManagementRestore. Retrying in 30 seconds..."
    echo
  else 
    ec=0
  fi
done

sleep 5

kubectl get managementrestore -n $ns | grep -q Pending > /dev/null 2>&1 
while [ "$?" -eq 0 ]; do
  echo "Waiting for Management Restore to be Ready..."
  kubectl get managementrestore -n $ns
  sleep 5
  kubectl get managementrestore -n $ns | grep -q Pending > /dev/null 2>&1 
done
echo "ManagementRestore ready"
echo

kubectl get managementcluster $mgmt_name -n $ns | grep -q Running > /dev/null 2>&1 
while [ "$?" -eq 1 ]; do
  echo "Waiting for Management Subsystem $mgmt_name to be Ready..."
  sleep 5
  kubectl get managementcluster $mgmt_name -n $ns | grep -q Running > /dev/null 2>&1 
done
echo "ManagementCluster $mgmt_name ready"
echo

echo
echo "Please now remove your change to the ManagementCluster spec via the command-line with 'kubectl edit managementcluster $mgmt_name -n $ns'"
echo "Please remove the template section from your spec:"
cat << EOF
spec:
  template:
  - name: lur-schema
    enabled: false
EOF
echo
read -p "Proceed when the configuration is updated. Proceed? (y/n) " -n 1 -r
echo

echo "Success"
exit 0