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

  # Find the pod running on this particular host
  HOSTCOUNT=0
  HOSTPOD=""
  mycount=0

  for host in $(echo $MY_HOSTS | tr ',' '\n')
  do
    # call your procedure/other scripts here below
    mycount=$(( $mycount + 1 ))
    if [ "$HOSTNAME" == "$host" ]
    then
      # get index
      HOSTCOUNT=$mycount
    fi
  done

  echo " --- NEXT ---"
  mycount=0
  for pod in $(echo $MY_PODS | tr ',' '\n')
  do
    # call your procedure/other scripts here below
    mycount=$(( $mycount + 1 ))
    if [ "$HOSTCOUNT" -eq "$mycount" ]
    then
      # get the pod
      HOSTPOD=$pod
    fi
  done
  echo $HOSTPOD


  # For this to work we need to be able to determine what host we are on
  #  search on this pod.beta.kubernetes.io/hostname=

  #Figure State of Cluster
  # Keeps track of initial peer count only run on original starting cluster
  numpeers="$(gluster peer status | grep -oP 'Peers:\s\K\w+')"
  EXPECTED_REPLICA_COUNT=$(( $numpeers + 1 ))  #should match REPLICA_COUNT after script runs
  ORIGINAL_PEER_COUNT=$numpeers
  CURRENT_NODE_COUNT=$(( $numpeers + 1 ))
  EXPECTED_PEER_COUNT=$(( $REPLICA_COUNT - 1 ))
  PEER_COUNT=$(( $REPLICA_COUNT - 1 ))
  VOLUME_LIST=""
  INITIAL_RUN="no"

  echo "Pre Termination Script Executed" > /usr/share/bin/gluster-stop.log  
  echo "" >> /usr/share/bin/gluster-stop.log
  echo "" >> /usr/share/bin/gluster-stop.log
  echo "****** LOG   ******" >> /usr/share/bin/gluster-stop.log
  echo "original_peer_count = $ORIGINAL_PEER_COUNT" >> /usr/share/bin/gluster-stop.log
  echo "expected_peer_count = $EXPECTED_PEER_COUNT" >> /usr/share/bin/gluster-stop.log
  echo "peer_count = $PEER_COUNT" >> /usr/share/bin/gluster-stop.log
  echo "expected_replica_count = $EXPECTED_REPLICA_COUNT" >> /usr/share/bin/gluster-stop.log
  echo "replica_count = $REPLICA_COUNT" >> /usr/share/bin/gluster-stop.log
  echo "initial run? $INITIAL_RUN" >> /usr/share/bin/gluster-stop.log
  echo "MY_HOSTS = $MY_HOSTS" >> /usr/share/bin/gluster-stop.log 
  echo "MY_PODS = $MY_PODS" >> /usr/share/bin/gluster-stop.log 
  echo "HOSTCOUNT = $HOSTCOUNT" >> /usr/share/bin/gluster-stop.log
  echo "HOSTPOD = $HOSTPOD" >> /usr/share/bin/gluster-stop.log  
  
  

  if [ "${ORIGINAL_PEER_COUNT}" -eq "0" ] && [ "$INITIAL_RUN" == "no" ]
  then
      echo "nothing in the pool, probably should do nothing" >> /usr/share/bin/gluster-stop.log


  else
      echo "Someone is terminating our pod" >> /usr/share/bin/gluster-stop.log
      
      # Let's proactively remove the TSP??
      # Remove from TSP
      if (gluster peer status | grep -q "Hostname: $HOSTPOD.$SERVICE_NAME.$NAMESPACE.svc.cluster.local")
      then
          result=`eval gluster peer detach $HOSTPOD.$SERVICE_NAME.$NAMESPACE.svc.cluster.local`
          wait
          echo "... Removed $HOSTPOD from TSP" >> /usr/share/bin/gluster-stop.log
      else
          echo "...Nothing to do here" >> /usr/share/bin/gluster-stop.log
      fi      


  else
      echo "Why did we hit this, what is our state at this point" >> /usr/share/bin/gluster.log
  fi
  echo "pre-termination script executed" >> /usr/share/bin/gluster-stop.log
  exit 0
else
  echo "glusterd not running...fail" >> /usr/share/bin/gluster-stop.log
  exit 1
fi
