#! /bin/bash
set -euo pipefail 
IFS=$'\n\t'

if systemctl status glusterd | grep -q '(running) since'
then

  # Run some api commands to figure out who we are and our state
  CURL_COMMAND="curl -v"
  K8_CERTS="--cacert /var/run/secrets/kubernetes.io/serviceaccount/ca.crt"
  GET_TOKEN="$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)"
  K8_TOKEN="-H \"Authorization: Bearer $GET_TOKEN\""

  # StatefulSet Calls
  STATEFULSET_API_CALL="https://kubernetes.default.svc.cluster.local/apis/apps/v1beta1/namespaces/$NAMESPACE/statefulsets/$BASE_NAME"
  STATEFULSET_API_COMMAND="$CURL_COMMAND $K8_CERTS $K8_TOKEN $STATEFULSET_API_CALL"
  REPLICA_COUNT=`eval $STATEFULSET_API_COMMAND | grep 'replicas'|cut -f2 -d ":" |cut -f2 -d "," | tr -d '[:space:]'`
  echo "replica count = $REPLICA_COUNT"

  # Get Node running on
  PODS_API_CALL="https://kubernetes.default.svc.cluster.local/api/v1/namespaces/default/pods"
  PODS_API_COMMAND="$CURL_COMMAND $K8_CERTS $K8_TOKEN $PODS_API_CALL"
  MY_PODS=`eval $PODS_API_COMMAND | grep 'pod.beta.kubernetes.io/hostname'|cut -f2 -d ":" | tr -d '[:space:]'`

  # Get Node running on
  PODS_API_CALL="https://kubernetes.default.svc.cluster.local/api/v1/namespaces/default/pods?labelSelector=app=glusterfs"
  PODS_API_COMMAND="$CURL_COMMAND $K8_CERTS $K8_TOKEN $PODS_API_CALL"
  MY_PODS=`eval $PODS_API_COMMAND | grep 'pod.beta.kubernetes.io/hostname'|cut -f2 -d ":" | tr -d '[:space:]' | tr -d '"'`

  # Get Host the pods are  running
  HOSTS_API_CALL="https://kubernetes.default.svc.cluster.local/api/v1/namespaces/default/pods?labelSelector=app=glusterfs"
  HOSTS_API_COMMAND="$CURL_COMMAND $K8_CERTS $K8_TOKEN $HOSTS_API_CALL"
  MY_HOSTS=`eval $HOSTS_API_COMMAND | grep 'nodeName'|cut -f2 -d ":" | tr -d '[:space:]' | tr -d '"'`

  echo "$MY_HOSTS"
  echo "$MY_PODS"

  # Find the pod running on this particular host
  HOSTCOUNT=0
  HOSTPOD=""
  mycount=0

  for host in $(echo $MY_HOSTS | tr ',' '\n')
  do
    # call your procedure/other scripts here below
    mycount=$(( $mycount + 1 ))
    echo $mycount
    if [ "$HOSTNAME" == "$host" ]
    then
      # get index
      echo "...$host"
      HOSTCOUNT=$mycount
    fi
  done
  echo "hostcount = $HOSTCOUNT"

  echo " --- NEXT ---"
  mycount=0
  for pod in $(echo $MY_PODS | tr ',' '\n')
  do
    # call your procedure/other scripts here below
    mycount=$(( $mycount + 1 ))
    echo $mycount
    if [ "$HOSTCOUNT" -eq "$mycount" ]
    then
      # get the pod
      echo "...$pod"
      HOSTPOD=$pod
    fi
  done
  echo "host pod = $HOSTPOD"

fi

