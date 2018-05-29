#! /bin/bash
set -euo pipefail 
IFS=$'\n\t'

if systemctl status glusterd | grep -q '(running) since'
then

  # Initialize our log
  if [ -e $LOG_NAME ]
  then
      echo " ----------------------------------------------------------------------------------------" >> $LOG_NAME
      echo " ----------------------------  Next Run   -----------------------------------------------" >> $LOG_NAME
      echo " ----------------------------------------------------------------------------------------" >> $LOG_NAME
      echo "Last Run: [ $(date) ]" >> $LOG_NAME
      INITIAL_RUN="no"
  else
      echo " ----------------------------------------------------------------------------------------" > $LOG_NAME
      echo " ----------------------------  Initial Run   --------------------------------------------" >> $LOG_NAME
      echo " ----------------------------------------------------------------------------------------" >> $LOG_NAME
      echo "Last Run: [ $(date) ]" >> $LOG_NAME
  fi

  # Run some api commands to figure out who we are and our current state
  # CURL_COMMAND="curl -v"
  CURL_COMMAND="curl -k"
  K8_CERTS="--cacert /var/run/secrets/kubernetes.io/serviceaccount/ca.crt"
  GET_TOKEN="$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)"
  K8_TOKEN="-H \"Authorization: Bearer $GET_TOKEN\""

  # StatefulSet Calls
  STATEFULSET_API_CALL="https://kubernetes.default.svc.cluster.local/apis/apps/v1beta1/namespaces/$NAMESPACE/statefulsets/$BASE_NAME"
  # Version 3.6 and 3.7 - no good for 3.9
  # STATEFULSET_API_COMMAND="$CURL_COMMAND $K8_CERTS $K8_TOKEN $STATEFULSET_API_CALL"  
  STATEFULSET_API_COMMAND="$CURL_COMMAND $K8_TOKEN $STATEFULSET_API_CALL"
  REPLICA_COUNT=`eval $STATEFULSET_API_COMMAND | grep 'replicas'|cut -f2 -d ":" |cut -f2 -d "," | tr -d '[:space:]'`
  echo "command $STATEFULSET_API_COMMAND" >> $LOG_NAME

  # Get Node running on
  PODS_API_CALL="https://kubernetes.default.svc.cluster.local/api/v1/namespaces/$NAMESPACE/pods?labelSelector=$SET_IDENTIFIER"
  # PODS_API_COMMAND="$CURL_COMMAND $K8_CERTS $K8_TOKEN $PODS_API_CALL"
  PODS_API_COMMAND="$CURL_COMMAND $K8_TOKEN $PODS_API_CALL"
  MY_PODS=`eval $PODS_API_COMMAND | grep 'pod.beta.kubernetes.io/hostname'|cut -f2 -d ":" | tr -d '[:space:]' | tr -d '"'`
  echo "command $MY_PODS" >> $LOG_NAME

  # Get Host the pods are  running
  HOSTS_API_CALL="https://kubernetes.default.svc.cluster.local/api/v1/namespaces/$NAMESPACE/pods?labelSelector=$SET_IDENTIFIER"
  # HOSTS_API_COMMAND="$CURL_COMMAND $K8_CERTS $K8_TOKEN $HOSTS_API_CALL"
  HOSTS_API_COMMAND="$CURL_COMMAND $K8_TOKEN $HOSTS_API_CALL"
  MY_HOSTS=`eval $HOSTS_API_COMMAND | grep 'nodeName'|cut -f2 -d ":" | tr -d '[:space:]' | tr -d '"'`
  echo "command $MY_HOSTS" >> $LOG_NAME

  # Find the pod, node and hostname and reconcile
  HOSTCOUNT=0
  HOSTPOD=""
  THIS_HOST=""
  mycount=0

  for host in $(echo $MY_HOSTS | tr ',' '\n')
  do
    # call your procedure/other scripts here below
    mycount=$(( $mycount + 1 ))
    if [ "$HOSTNAME" == "$host" ]
    then
      # get index
      HOSTCOUNT=$mycount
      THIS_HOST=$host
    fi
  done
  # hostNetwork is turned off, so HOSTNAME env variable will produce
  # the pod name rather than the node name
  # this host expects something like ip-172-18-3-5.ec2.internal
  mycount=0
  if [ "$THIS_HOST" == "" ]
  then
    # find index of matching hostnames
    for pod in $(echo $MY_PODS | tr ',' '\n')
    do
      # call your procedure/other scripts here below
      mycount=$(( $mycount + 1 ))
      if [ "$HOSTNAME" == "$pod" ]
      then
        # get the pod
        HOSTCOUNT=$mycount
      fi
    done
    mycount=0
    for host in $(echo $MY_HOSTS | tr ',' '\n')
    do
      # call your procedure/other scripts here below
      mycount=$(( $mycount + 1 ))
      if [ "$HOSTCOUNT" == "$mycount" ]
      then
        # get index
        THIS_HOST=$host
      fi
    done
  fi

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
  # hostNetwork is turned off, so HOSTNAME env variable will produce
  # the pod name rather than the node name
  if [ "$HOSTPOD" == "" ]
  then
    HOSTPOD=$HOSTNAME
  fi

  # Some Common Variables used
  # Figure State of Cluster
  # Keeps track of initial peer count only run on original starting cluster
  numpeers="$(gluster peer status | grep -oP 'Peers:\s\K\w+')"
  EXPECTED_REPLICA_COUNT=$(( $numpeers + 1 ))  #should match REPLICA_COUNT after script runs
  ORIGINAL_PEER_COUNT=$numpeers
  CURRENT_NODE_COUNT=$(( $numpeers + 1 ))
  EXPECTED_PEER_COUNT=$(( $REPLICA_COUNT - 1 ))
  PEER_COUNT=$(( $REPLICA_COUNT - 1 ))
  VOLUME_LIST=""
  MOUNT_LIST=""
  MOUNT_CMD=""
  INITIAL_RUN="yes"
  DNSHOSTPOD="$HOSTPOD.$SERVICE_NAME.$NAMESPACE.svc.cluster.local"


  echo "" >> $LOG_NAME
  echo "" >> $LOG_NAME
  echo "****** LOG   ******" >> $LOG_NAME
  echo "original_peer_count = $ORIGINAL_PEER_COUNT" >> $LOG_NAME
  echo "expected_peer_count = $EXPECTED_PEER_COUNT" >> $LOG_NAME
  echo "peer_count = $PEER_COUNT" >> $LOG_NAME
  echo "expected_replica_count = $EXPECTED_REPLICA_COUNT" >> $LOG_NAME
  echo "replica_count = $REPLICA_COUNT" >> $LOG_NAME
  echo "initial run? $INITIAL_RUN" >> $LOG_NAME
  echo "MY_HOSTS = $MY_HOSTS" >> $LOG_NAME 
  echo "MY_PODS = $MY_PODS" >> $LOG_NAME 
  echo "HOSTCOUNT = $HOSTCOUNT" >> $LOG_NAME
  echo "HOSTPOD = $HOSTPOD" >> $LOG_NAME
  echo "THIS_HOST = $THIS_HOST" >> $LOG_NAME
  echo "DNSHOSTPOD = $DNSHOSTPOD" >> $LOG_NAME
  echo "VOLUME_COUNT = $VOLUME_COUNT" >> $LOG_NAME 


  if [ "$INITIAL_RUN" == "yes" ]
  then
      echo "" >> $LOG_NAME
      echo "!!! Cluster Initial Run on Host !!!" >> $LOG_NAME

      peerstart=-1
      until test $peerstart -eq $PEER_COUNT
      do
        peerstart=$(( $peerstart + 1 ))
        if (gluster peer status | grep -q "Hostname: $BASE_NAME-$peerstart.$SERVICE_NAME.$NAMESPACE.svc.cluster.local")
        then
            echo "...no need to peer probe already exists $BASE_NAME-$peerstart.$SERVICE_NAME.$NAMESPACE.svc.cluster.local" >> $LOG_NAME
        else
            echo "...probing - peer for $BASE_NAME-$peerstart.$SERVICE_NAME.$NAMESPACE.svc.cluster.local" >> $LOG_NAME
            result=`eval gluster peer probe $BASE_NAME-$peerstart.$SERVICE_NAME.$NAMESPACE.svc.cluster.local`
        fi           
      done
      echo "...Initial Run peer probe should be good" >> $LOG_NAME      
      echo "" >> $LOG_NAME 

      echo "...Volume Setup" >> $LOG_NAME

      if [ "$CREATE_VOLUMES" -eq "1" ]
      then
          # Analyze and Create or Prepare to Create Volumes and Bricks if Needed!
          echo "" >> $LOG_NAME          
          echo " ... ... Analyzing Environment for Volumes and Bricks" >> $LOG_NAME 
          volstart=-1
          volend=$(( $VOLUME_COUNT - 1 ))
          listcount=0
          until test $volstart -eq $volend
          do
            volstart=$(( $volstart + 1 ))
            peerstart=-1
            until test $peerstart -eq $PEER_COUNT
            do
              peerstart=$(( $peerstart + 1 ))
              if (gluster volume status all | grep -q "Status of volume: $VOLUME_BASE$volstart")
              then
                echo "... ... Looking for Brick: $BASE_NAME-$peerstart.$SERVICE_NAME.$NAMESPACE.svc.cluster.local:$MOUNT_BASE$VOLUME_BASE$volstart" >> $LOG_NAME
                echo "" >> $LOG_NAME

                # if (gluster volume status all | grep -q "Brick: $BASE_NAME-$peerstart.$SERVICE_NAME.$NAMESPACE")
                if (gluster volume info | grep -q ": $BASE_NAME-$peerstart.$SERVICE_NAME.$NAMESPACE.svc.cluster.local:$MOUNT_BASE$VOLUME_BASE$volstart/brick$volstart")
                then
                  echo "brick and volume already exist for $BASE_NAME-$peerstart.$SERVICE_NAME.$NAMESPACE.svc.cluster.local:$MOUNT_BASE$VOLUME_BASE$volstart" >> $LOG_NAME

                else
                  echo "Adding brick to Existing Volume $VOLUME_BASE$volstart" >> $LOG_NAME
                  result=`eval gluster volume add-brick $VOLUME_BASE$volstart replica $REPLICA_COUNT $BASE_NAME-$peerstart.$SERVICE_NAME.$NAMESPACE.svc.cluster.local:$MOUNT_BASE$VOLUME_BASE$volstart/brick$volstart force || true`
                  wait
                  echo "Brick Added" >> $LOG_NAME
                  # result=`gluster volume rebalance $VOLUME_BASE$volstart start`
                  # echo "Initiated Volume Rebalance" >> $LOG_NAME
                fi
              else
                echo "Volume does not exist" >> $LOG_NAME
                VOLUME_LIST="$VOLUME_LIST $BASE_NAME-$peerstart.$SERVICE_NAME.$NAMESPACE.svc.cluster.local:$MOUNT_BASE$VOLUME_BASE$volstart/brick$volstart"
                echo " ... ... $VOLUME_LIST" >> $LOG_NAME
              fi
            done

            # Create our initial volumes and bricks, if they don't already exist
            # based on the VOLUME_LIST analysis from above
            echo "volumelist = $VOLUME_LIST" >> $LOG_NAME
            if [ "$VOLUME_LIST" == "" ]
            then
              echo "Nothing to do for volumes and bricks" >> $LOG_NAME
            else
              echo "No Volumes Exists - Let's Run our create volume command" >> $LOG_NAME
              result=`eval gluster volume create $VOLUME_BASE$volstart replica $REPLICA_COUNT $VOLUME_LIST force`
              wait
              result=`eval gluster volume start $VOLUME_BASE$volstart`
              wait
              echo " volume $VOLUME_BASE$volstart created and started" >> $LOG_NAME
            fi

            # need to check volume mount
            echo "" >> $LOG_NAME
            echo " ... Checking For Volume Mount Status for brick$volstart" >> $LOG_NAME
            if [ "$HOSTNAME" == "$THIS_HOST" ] || [ "$HOSTNAME" == "$HOSTPOD" ]
            then
              echo " ... ... Check to see if fuse mount exists?" >> $LOG_NAME
              # if grep -qs '$FUSE_BASE$VOLUME_BASE$volstart' /proc/mounts
              if (mount | grep -q "$FUSE_BASE$VOLUME_BASE$volstart")
              then
                echo " ... ... ... It does exist, so no action needed to mount brick$volstart" >> $LOG_NAME                     
              else
                if [ ! -d "$FUSE_BASE$VOLUME_BASE$volstart" ] 
                then
                  echo " ... ... ... Creating mount directory" >> $LOG_NAME
                  result=`eval mkdir -p $FUSE_BASE$VOLUME_BASE$volstart` 
                fi
                MOUNT_CMD="mount -t glusterfs  $DNSHOSTPOD:$VOLUME_BASE$volstart $FUSE_BASE$VOLUME_BASE$volstart"
                echo " ... ... ... It does not exist, so create mount CMD = $MOUNT_CMD" >> $LOG_NAME
                echo " ... ... ... Running Mount Command" >> $LOG_NAME 
                result=`eval $MOUNT_CMD`
                wait
                MOUNT_CMD=""
                echo " ... ... ... Mount Completed Successfully!!" >> $LOG_NAME
              fi
            fi
            echo "" >> $LOG_NAME
          done
      else
          echo "Volume SetUp turned off - to turn on change statefulset value to 1" >> $LOG_NAME
      fi
      echo "Probe ran - updated peers with pool now at $REPLICA_COUNT" >> $LOG_NAME

  elif (gluster peer status | grep -q "Peer Rejected")
  then
      # TODO: This can probably be removed, I have not seen this status YET 
      echo "!!! We have a rejected peer - need to handle !!!" >> $LOG_NAME
      rejectedhost="$(gluster peer status | grep -B 2 'Peer Rejected' | grep 'Hostname:'|cut -f2 -d ':' | tr -d '[:space:]')"
      echo "... rejected host = $rejectedhost" >> $LOG_NAME
      if [ "$DNSHOSTPOD" == "$rejectedhost" ]
      then
         echo "... This is target rejected peer! - $HOSTPOD - $DNSHOSTPOD" >> $LOG_NAME
         echo "... stopping glusterd" >> $LOG_NAME
         systemctl stop glusterd
         echo "... stopped glusterd" >> $LOG_NAME
         echo "... deleting files" >> $LOG_NAME
         cp /var/lib/glusterd/glusterd.info /tmp
         rm -rf /var/lib/glusterd/*
         cp /tmp/glusterd.info /var/lib/glusterd/
         echo "... files deleted restarting glusterd" >> $LOG_NAME
         systemctl start glusterd

         # now recheck a few times
         echo "... recycling glusterd a few times" >> $LOG_NAME
         if (gluster peer status | grep -q "Peer Rejected")
         then
           systemctl restart glusterd
         fi
         sleep 5
         if (gluster peer status | grep -q "Peer Rejected")
         then
           systemctl restart glusterd
         fi
      else
          echo "... peer probing and restarting glusterd, not target rejected peer - $HOSTPOD" >> $LOG_NAME
          systemctl restart glusterd 
      fi

  elif [ "${ORIGINAL_PEER_COUNT}" -eq "0" ] && [ "$INITIAL_RUN" == "no" ]
  then
      # It's not our initial run but cluster/TSP was reset in someway, either Cluster was deleted by user, or PVCs were deleted or possibly we have a recycled pod, need to check state of the world
      # TODO: This could be combined with INITIAL run really, so can clean that up at sometime but for now trying to see what conditions I run into
      echo " !!! Cluster was Reset or Deleted and is Reinitializing, Need to Reevaluate State of World !!!" >> $LOG_NAME
      peerstart=-1
      until test $peerstart -eq $PEER_COUNT
      do
        peerstart=$(( $peerstart + 1 ))
        if (gluster peer status | grep -q "Hostname: $BASE_NAME-$peerstart.$SERVICE_NAME.$NAMESPACE.svc.cluster.local")
        then
            echo "no need to peer probe already exists" >> $LOG_NAME
        else
            echo "... ... peer probe for $BASE_NAME-$peerstart.$SERVICE_NAME.$NAMESPACE.svc.cluster.local" >> $LOG_NAME
            result=`eval gluster peer probe $BASE_NAME-$peerstart.$SERVICE_NAME.$NAMESPACE.svc.cluster.local`
        fi           
      done
      echo "... Probe Complete" >> $LOG_NAME

      if [ "$CREATE_VOLUMES" -eq "1" ]
      then
          # Analyze and Create or Prepare to Create Volumes and Bricks if Needed!
          echo "" >> $LOG_NAME          
          echo " ... ... Analyzing Environment for Volumes and Bricks" >> $LOG_NAME 
          volstart=-1
          volend=$(( $VOLUME_COUNT - 1 ))
          listcount=0
          until test $volstart -eq $volend
          do
            volstart=$(( $volstart + 1 ))
            peerstart=-1
            until test $peerstart -eq $PEER_COUNT
            do
              peerstart=$(( $peerstart + 1 ))
              if (gluster volume status all | grep -q "Status of volume: $VOLUME_BASE$volstart")
              then
                echo "... ... Looking for Brick: $BASE_NAME-$peerstart.$SERVICE_NAME.$NAMESPACE.svc.cluster.local:$MOUNT_BASE$VOLUME_BASE$volstart" >> $LOG_NAME
                echo "" >> $LOG_NAME

                # if (gluster volume status all | grep -q "Brick: $BASE_NAME-$peerstart.$SERVICE_NAME.$NAMESPACE")
                if (gluster volume info | grep -q ": $BASE_NAME-$peerstart.$SERVICE_NAME.$NAMESPACE.svc.cluster.local:$MOUNT_BASE$VOLUME_BASE$volstart/brick$volstart")
                then
                  echo "brick and volume already exist for $BASE_NAME-$peerstart.$SERVICE_NAME.$NAMESPACE.svc.cluster.local:$MOUNT_BASE$VOLUME_BASE$volstart" >> $LOG_NAME

                else
                  echo "Adding brick to Existing Volume $VOLUME_BASE$volstart" >> $LOG_NAME
                  result=`eval gluster volume add-brick $VOLUME_BASE$volstart replica $REPLICA_COUNT $BASE_NAME-$peerstart.$SERVICE_NAME.$NAMESPACE.svc.cluster.local:$MOUNT_BASE$VOLUME_BASE$volstart/brick$volstart force || true`
                  wait
                  echo "Brick Added" >> $LOG_NAME
                  # result=`gluster volume rebalance $VOLUME_BASE$volstart start`
                  # echo "Initiated Volume Rebalance" >> $LOG_NAME
                fi
              else
                echo "Volume does not exist" >> $LOG_NAME
                VOLUME_LIST="$VOLUME_LIST $BASE_NAME-$peerstart.$SERVICE_NAME.$NAMESPACE.svc.cluster.local:$MOUNT_BASE$VOLUME_BASE$volstart/brick$volstart"
                echo " ... ... $VOLUME_LIST" >> $LOG_NAME
              fi
            done

            # Create our initial volumes and bricks, if they don't already exist
            echo "volumelist = $VOLUME_LIST" >> $LOG_NAME
            if [ "$VOLUME_LIST" == "" ]
            then
              echo "Nothing to do for volumes and bricks" >> $LOG_NAME
            else
              echo "No Volumes Exists - Let's Run our create volume command" >> $LOG_NAME
              result=`eval gluster volume create $VOLUME_BASE$volstart replica $REPLICA_COUNT $VOLUME_LIST force`
              wait
              result=`eval gluster volume start $VOLUME_BASE$volstart`
              wait
              echo " volume $VOLUME_BASE$volstart created and started" >> $LOG_NAME
            fi

            # need to check volume mount
            echo "" >> $LOG_NAME
            echo " ... Checking For Volume Mount Status for brick$volstart" >> $LOG_NAME
            if [ "$HOSTNAME" == "$THIS_HOST" ] || [ "$HOSTNAME" == "$HOSTPOD" ]
            then
              echo " ... ... Check to see if fuse mount exists?" >> $LOG_NAME
              # if grep -qs '$FUSE_BASE$VOLUME_BASE$volstart' /proc/mounts
              if (mount | grep -q "$FUSE_BASE$VOLUME_BASE$volstart")
              then
                echo " ... ... ... It does exist, so no action needed to mount brick$volstart" >> $LOG_NAME                     
              else
                if [ ! -d "$FUSE_BASE$VOLUME_BASE$volstart" ] 
                then
                  echo " ... ... ... Creating mount directory" >> $LOG_NAME
                  result=`eval mkdir -p $FUSE_BASE$VOLUME_BASE$volstart` 
                fi
                MOUNT_CMD="mount -t glusterfs  $DNSHOSTPOD:$VOLUME_BASE$volstart $FUSE_BASE$VOLUME_BASE$volstart"
                echo " ... ... ... It does not exist, so create mount CMD = $MOUNT_CMD" >> $LOG_NAME
                echo " ... ... ... Running Mount Command" >> $LOG_NAME 
                result=`eval $MOUNT_CMD`
                wait
                MOUNT_CMD=""
                echo " ... ... ... Mount Completed Successfully!!" >> $LOG_NAME
              fi
            fi
            echo "" >> $LOG_NAME
          done
      else
          echo "Volume SetUp turned off - to turn on change statefulset value to 1" >> $LOG_NAME
      fi

      echo "Probe Ran - updated peers with pool now at $REPLICA_COUNT" >> $LOG_NAME

  elif [ "${ORIGINAL_PEER_COUNT}" -eq "${PEER_COUNT}" ] && [ "$INITIAL_RUN" == "no" ]
  then
      echo "!!! Cluster seems to have not changed since last run !!!" >> $LOG_NAME
      echo " ...let's check for volumes???" >> $LOG_NAME

      if [ "$CREATE_VOLUMES" -eq "1" ]
      then
          # Analyze and Create or Prepare to Create Volumes and Bricks if Needed!
          echo "" >> $LOG_NAME          
          echo " ... ... Analyzing Environment for Volumes and Bricks" >> $LOG_NAME 
          volstart=-1
          volend=$(( $VOLUME_COUNT - 1 ))
          listcount=0
          until test $volstart -eq $volend
          do
            volstart=$(( $volstart + 1 ))
            peerstart=-1
            until test $peerstart -eq $PEER_COUNT
            do
              peerstart=$(( $peerstart + 1 ))
              if (gluster volume status all | grep -q "Status of volume: $VOLUME_BASE$volstart")
              then
                echo "... ... Looking for Brick: $BASE_NAME-$peerstart.$SERVICE_NAME.$NAMESPACE.svc.cluster.local:$MOUNT_BASE$VOLUME_BASE$volstart" >> $LOG_NAME
                echo "" >> $LOG_NAME

                # if (gluster volume status all | grep -q "Brick: $BASE_NAME-$peerstart.$SERVICE_NAME.$NAMESPACE")
                if (gluster volume info | grep -q ": $BASE_NAME-$peerstart.$SERVICE_NAME.$NAMESPACE.svc.cluster.local:$MOUNT_BASE$VOLUME_BASE$volstart/brick$volstart")
                then
                  echo "brick and volume already exist for $BASE_NAME-$peerstart.$SERVICE_NAME.$NAMESPACE.svc.cluster.local:$MOUNT_BASE$VOLUME_BASE$volstart" >> $LOG_NAME

                else
                  echo "Adding brick to Existing Volume $VOLUME_BASE$volstart" >> $LOG_NAME
                  result=`eval gluster volume add-brick $VOLUME_BASE$volstart replica $REPLICA_COUNT $BASE_NAME-$peerstart.$SERVICE_NAME.$NAMESPACE.svc.cluster.local:$MOUNT_BASE$VOLUME_BASE$volstart/brick$volstart force || true`
                  wait
                  echo "Brick Added" >> $LOG_NAME
                  # result=`gluster volume rebalance $VOLUME_BASE$volstart start`
                  # echo "Initiated Volume Rebalance" >> $LOG_NAME
                fi
              else
                echo "Volume does not exist" >> $LOG_NAME
                VOLUME_LIST="$VOLUME_LIST $BASE_NAME-$peerstart.$SERVICE_NAME.$NAMESPACE.svc.cluster.local:$MOUNT_BASE$VOLUME_BASE$volstart/brick$volstart"
                echo " ... ... $VOLUME_LIST" >> $LOG_NAME
              fi
            done

            # Create our initial volumes and bricks, if they don't already exist
            echo "volumelist = $VOLUME_LIST" >> $LOG_NAME
            if [ "$VOLUME_LIST" == "" ]
            then
              echo "Nothing to do for volumes and bricks" >> $LOG_NAME
            else
              echo "No Volumes Exists - Let's Run our create volume command" >> $LOG_NAME
              result=`eval gluster volume create $VOLUME_BASE$volstart replica $REPLICA_COUNT $VOLUME_LIST force`
              wait
              result=`eval gluster volume start $VOLUME_BASE$volstart`
              wait
              echo " volume $VOLUME_BASE$volstart created and started" >> $LOG_NAME
            fi

            # need to check volume mount
            echo "" >> $LOG_NAME
            echo " ... Checking For Volume Mount Status for brick$volstart" >> $LOG_NAME
            if [ "$HOSTNAME" == "$THIS_HOST" ] || [ "$HOSTNAME" == "$HOSTPOD" ]
            then
              echo " ... ... Check to see if fuse mount exists?" >> $LOG_NAME
              # if grep -qs '$FUSE_BASE$VOLUME_BASE$volstart' /proc/mounts
              if (mount | grep -q "$FUSE_BASE$VOLUME_BASE$volstart")
              then
                echo " ... ... ... It does exist, so no action needed to mount brick$volstart" >> $LOG_NAME                     
              else
                if [ ! -d "$FUSE_BASE$VOLUME_BASE$volstart" ] 
                then
                  echo " ... ... ... Creating mount directory" >> $LOG_NAME
                  result=`eval mkdir -p $FUSE_BASE$VOLUME_BASE$volstart` 
                fi
                MOUNT_CMD="mount -t glusterfs  $DNSHOSTPOD:$VOLUME_BASE$volstart $FUSE_BASE$VOLUME_BASE$volstart"
                echo " ... ... ... It does not exist, so create mount CMD = $MOUNT_CMD" >> $LOG_NAME
                echo " ... ... ... Running Mount Command" >> $LOG_NAME 
                result=`eval $MOUNT_CMD`
                wait
                MOUNT_CMD=""
                echo " ... ... ... Mount Completed Successfully!!" >> $LOG_NAME
              fi
            fi
            echo "" >> $LOG_NAME
          done
      else
          echo "Volume SetUp turned off - to turn on change statefulset value to 1" >> $LOG_NAME
      fi
      echo "Probe Ran - did not update peers, replica count at $REPLICA_COUNT" >> $LOG_NAME


  elif [ "${EXPECTED_REPLICA_COUNT}" -lt "$REPLICA_COUNT" ] && [ "$INITIAL_RUN" == "no" ]
  then
      echo "!!! Cluster needs to scale up !!!" >> $LOG_NAME
      
      numup=$(( $REPLICA_COUNT - $CURRENT_NODE_COUNT ))          
      peerstart=$(( $CURRENT_NODE_COUNT - 1 ))
      peerlimit=$(( $peerstart + $numup ))
      echo "... ... numup = $numup" >> $LOG_NAME
      echo "... ... peerstart=$peerstart" >> $LOG_NAME
      echo "... ... peerlimit=$peerlimit" >> $LOG_NAME
      until test $peerstart -eq $peerlimit
      do
        peerstart=$(( $peerstart + 1 ))
        if (gluster peer status | grep -q "Hostname: $BASE_NAME-$peerstart.$SERVICE_NAME.$NAMESPACE.svc.cluster.local")
        then
           # Do nothing
           echo "... ...nothing to change" >> $LOG_NAME
        else
           # Add to TSP
           echo "...Adding to TSP $BASE_NAME-$peerstart.$SERVICE_NAME.$NAMESPACE.svc.cluster.local" >> $LOG_NAME
           result=`eval gluster peer probe $BASE_NAME-$peerstart.$SERVICE_NAME.$NAMESPACE.svc.cluster.local`

           # here we need to add new brick for new node
           # gluster volume add-brick $VOLUME_BASE$volstart replica "$REPLICA_COUNT$VOLUME_LIST"
           echo "...Check Volumes" >> $LOG_NAME
           if [ "$CREATE_VOLUMES" -eq "1" ]
           then
               echo "... ... Adding bricks if needed" >> $LOG_NAME
               volstart=-1
               until test $volstart -eq $VOLUME_COUNT
               do
                 volstart=$(( $volstart + 1 ))
                  echo "add-brick command: $VOLUME_BASE$volstart replica $REPLICA_COUNT $BASE_NAME-$peerstart.$SERVICE_NAME.$NAMESPACE.svc.cluster.local:$MOUNT_BASE$VOLUME_BASE$volstart" >> $LOG_NAME
                 # gluster volume create glusterfs-data0 glusterfs-0.glusterfs.default.svc.cluster.local:/mnt/storage/glusterfs-data0 glusterfs-1.glusterfs.default.svc.cluster.local:/mnt/storage/glusterfs-data0 force 
                 result=`eval gluster volume add-brick brick$volstart replica $REPLICA_COUNT $BASE_NAME-$peerstart.$SERVICE_NAME.$NAMESPACE.svc.cluster.local:$MOUNT_BASE$VOLUME_BASE$volstart force || true`
                 wait
               done
           fi
        fi
      done
      echo "Probe Ran - update peers, replica count at $REPLICA_COUNT" >> $LOG_NAME

  elif [ "${EXPECTED_REPLICA_COUNT}" -gt "$REPLICA_COUNT" ] && [ "$INITIAL_RUN" == "no" ]
  then
      echo "!!! Cluster needs to scale down !!!" >> $LOG_NAME
      numdown=$(( $CURRENT_NODE_COUNT - $REPLICA_COUNT ))          
      peerstart1=$(( $CURRENT_NODE_COUNT - $numdown ))
      peerstart=$(( $peerstart1 - 1 ))
      limitdown=$(( $CURRENT_NODE_COUNT - 1 ))
      echo "... ... numdown = $numdown" >> $LOG_NAME
      echo "... ... peerstart=$peerstart" >> $LOG_NAME
      echo "... ... limitdown=$limitdown" >> $LOG_NAME
      until test $peerstart -eq $limitdown
      do
        # TODO: Need to remove any bricks that exist for these nodes
        peerstart=$(( $peerstart + 1 )) 

        if [ "$CREATE_VOLUMES" -eq "1" ]
        then
           echo "... ... Removing bricks if needed" >> $LOG_NAME
           volstart=-1
           until test $volstart -eq $VOLUME_COUNT
           do
             volstart=$(( $volstart + 1 ))
             if (gluster peer status | grep -q "Hostname: $BASE_NAME-$peerstart.$SERVICE_NAME.$NAMESPACE.svc.cluster.local")
             then
               # I want to double check and make sure the brick actually exists
               if (gluster volume info | grep -q ": $BASE_NAME-$peerstart.$SERVICE_NAME.$NAMESPACE.svc.cluster.local:$MOUNT_BASE$VOLUME_BASE$volstart/brick$volstart")
               then               
                 echo "remove-brick command: gluster volume remove-brick $VOLUME_BASE$volstart replica $REPLICA_COUNT $BASE_NAME-$peerstart.$SERVICE_NAME.$NAMESPACE.svc.cluster.local:$MOUNT_BASE$VOLUME_BASE$volstart/brick$volstart force" >> $LOG_NAME
                 result=`eval yes | gluster volume remove-brick $VOLUME_BASE$volstart replica $REPLICA_COUNT $BASE_NAME-$peerstart.$SERVICE_NAME.$NAMESPACE.svc.cluster.local:$MOUNT_BASE$VOLUME_BASE$volstart/brick$volstart force`
                 wait
               fi
             fi
           done
        fi

        # Remove from TSP
        if (gluster peer status | grep -q "Hostname: $BASE_NAME-$peerstart.$SERVICE_NAME.$NAMESPACE.svc.cluster.local")
        then
            result=`eval gluster peer detach $BASE_NAME-$peerstart.$SERVICE_NAME.$NAMESPACE.svc.cluster.local`
            wait
        else
            echo "...Nothing to do here" >> $LOG_NAME
        fi

      done
      echo "Probe Ran - Removed peers, replica count at $REPLICA_COUNT" >> $LOG_NAME

  else
      echo "This should be a catch all - but should never happen" >> $LOG_NAME
  fi
  echo "" >> $LOG_NAME
  exit 0
elif [ test -f $LOG_NAME ]
then
  exit 0
else 
  echo "" >> $LOG_NAME
  echo "Liveness Probe Failed" >> $LOG_NAME
  exit 1
fi

# checkVolumeAndBricks analyzes state of current glusterfs volumes
# and the corresponding bricks
# expects $VOLUME_LIST and $volstart params
function checkVolumesAndBricks () {
    # Create our initial volumes and bricks, if they don't already exist
    echo "volumelist = $VOLUME_LIST" >> $LOG_NAME
    if [ "$VOLUME_LIST" == "" ]
    then
       echo "Nothing to do for volumes and bricks" >> $LOG_NAME
    else
       echo "No Volumes Exists - Let's Run our create volume command" >> $LOG_NAME
       result=`eval gluster volume create $VOLUME_BASE$volstart replica $REPLICA_COUNT $VOLUME_LIST force`
       wait
       result=`eval gluster volume start $VOLUME_BASE$volstart`
       wait
       echo " volume $VOLUME_BASE$volstart created and started" >> $LOG_NAME
    fi
}

# This function checks volume mounts for our fuse mount
# it expects an argument of volume number
function checkVolumeMounts () {
   volnum=0
   if [ $# -eq 0 ]
   then
     volnum=0
   else
     volnum=$1
   fi

   # need to check volume mount
   echo " ... Checking For Volume Mount Status for brick$volstart" >> $LOG_NAME
   if [ "$HOSTNAME" == "$THIS_HOST" ] || [ "$HOSTNAME" == "$HOSTPOD" ]
   then
     echo " ... ... Check to see if fuse mount exists?" >> $LOG_NAME
     # if grep -qs '$FUSE_BASE$VOLUME_BASE$volnum' /proc/mounts
     if (mount | grep -q "$FUSE_BASE$VOLUME_BASE$volnum")
     then
        echo " ... ... ... It does exist, so no action needed to mount brick$volnum" >> $LOG_NAME                     
     else
        # make sure our mount dir exists
        if [ ! -d "$FUSE_BASE$VOLUME_BASE$volnum" ] 
        then
          echo " ... ... ... Creating mount directory" >> $LOG_NAME
          result=`eval mkdir -p $FUSE_BASE$VOLUME_BASE$volnum` 
        fi

        MOUNT_CMD="mount -t glusterfs  $DNSHOSTPOD:$VOLUME_BASE$volstart $FUSE_BASE$VOLUME_BASE$volnum"
        echo " ... ... ... It does not exist, so create mount CMD = $MOUNT_CMD" >> $LOG_NAME
        echo " ... ... ... Running Mount Command" >> $LOG_NAME
        result=`eval $MOUNT_CMD`
        wait
        MOUNT_CMD=""
        echo " ... ... ... Mount Completed Successfully!!" >> $LOG_NAME
     fi
   fi
}


