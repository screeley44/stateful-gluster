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

  # Get Node running on
  PODS_API_CALL="https://kubernetes.default.svc.cluster.local/api/v1/namespaces/$NAMESPACE/pods"
  PODS_API_COMMAND="$CURL_COMMAND $K8_CERTS $K8_TOKEN $PODS_API_CALL"
  MY_PODS=`eval $PODS_API_COMMAND | grep 'pod.beta.kubernetes.io/hostname'|cut -f2 -d ":" | tr -d '[:space:]'`

  # Get Node running on
  PODS_API_CALL="https://kubernetes.default.svc.cluster.local/api/v1/namespaces/$NAMESPACE/pods?labelSelector=$SET_IDENTIFIER"
  PODS_API_COMMAND="$CURL_COMMAND $K8_CERTS $K8_TOKEN $PODS_API_CALL"
  MY_PODS=`eval $PODS_API_COMMAND | grep 'pod.beta.kubernetes.io/hostname'|cut -f2 -d ":" | tr -d '[:space:]' | tr -d '"'`

  # Get Host the pods are  running
  HOSTS_API_CALL="https://kubernetes.default.svc.cluster.local/api/v1/namespaces/$NAMESPACE/pods?labelSelector=$SET_IDENTIFIER"
  HOSTS_API_COMMAND="$CURL_COMMAND $K8_CERTS $K8_TOKEN $HOSTS_API_CALL"
  MY_HOSTS=`eval $HOSTS_API_COMMAND | grep 'nodeName'|cut -f2 -d ":" | tr -d '[:space:]' | tr -d '"'`

  # Find the pod running on this particular host
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

  #Figure State of Cluster
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

  if [ -e /usr/share/bin/gluster.log ]
  then
      echo " -----  Next Run   -----" >> /usr/share/bin/gluster.log
      INITIAL_RUN="no"
  else
      echo " -----  Initial Run   -----" > /usr/share/bin/gluster.log  
  fi
  echo "" >> /usr/share/bin/gluster.log
  echo "" >> /usr/share/bin/gluster.log
  echo "****** LOG   ******" >> /usr/share/bin/gluster.log
  echo "original_peer_count = $ORIGINAL_PEER_COUNT" >> /usr/share/bin/gluster.log
  echo "expected_peer_count = $EXPECTED_PEER_COUNT" >> /usr/share/bin/gluster.log
  echo "peer_count = $PEER_COUNT" >> /usr/share/bin/gluster.log
  echo "expected_replica_count = $EXPECTED_REPLICA_COUNT" >> /usr/share/bin/gluster.log
  echo "replica_count = $REPLICA_COUNT" >> /usr/share/bin/gluster.log
  echo "initial run? $INITIAL_RUN" >> /usr/share/bin/gluster.log
  echo "MY_HOSTS = $MY_HOSTS" >> /usr/share/bin/gluster.log 
  echo "MY_PODS = $MY_PODS" >> /usr/share/bin/gluster.log 
  echo "HOSTCOUNT = $HOSTCOUNT" >> /usr/share/bin/gluster.log
  echo "HOSTPOD = $HOSTPOD" >> /usr/share/bin/gluster.log
  echo "THIS_HOST = $THIS_HOST" >> /usr/share/bin/gluster.log
  echo "DNSHOSTPOD = $DNSHOSTPOD" >> /usr/share/bin/gluster.log   

  # TODO: Add "peer rejected" status and mitigation
  # TODO: think it comes from above todo state: 
  #              peer probe: failed: glusterfs-0.glusterfs.default.svc.cluster.local is either already part of another cluster or having volumes configured
  # TODO: test volume management  

  if [ "$INITIAL_RUN" == "yes" ]
  then
      echo "Initial Run on host" >> /usr/share/bin/gluster.log

      peerstart=-1
      until test $peerstart -eq $PEER_COUNT
      do
        peerstart=$(( $peerstart + 1 ))
        if (gluster peer status | grep -q "Hostname: $BASE_NAME-$peerstart.$SERVICE_NAME.$NAMESPACE.svc.cluster.local")
        then
            echo "...no need to peer probe already exists $BASE_NAME-$peerstart.$SERVICE_NAME.$NAMESPACE.svc.cluster.local" >> /usr/share/bin/gluster.log
        else
            echo "...probing - peer for $BASE_NAME-$peerstart.$SERVICE_NAME.$NAMESPACE.svc.cluster.local" >> /usr/share/bin/gluster.log
            result=`eval gluster peer probe $BASE_NAME-$peerstart.$SERVICE_NAME.$NAMESPACE.svc.cluster.local`
        fi           
      done
      echo "...Initial Run peer probe should be good" >> /usr/share/bin/gluster.log      

      echo "...Volume Setup" >> /usr/share/bin/gluster.log

      if [ "$CREATE_VOLUMES" -eq "1" ]
      then
          # Analyze and Create or Prepare to Create Volumes and Bricks if Needed!
          echo "" >> /usr/share/bin/gluster.log          
          echo " ... ... Analyzing Environment for Volumes and Bricks" >> /usr/share/bin/gluster.log 
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
                echo "... ... Looking for Brick: $BASE_NAME-$peerstart.$SERVICE_NAME.$NAMESPACE.svc.cluster.local:$MOUNT_BASE$VOLUME_BASE$volstart" >> /usr/share/bin/gluster.log
                echo "" >> /usr/share/bin/gluster.log

                # if (gluster volume status all | grep -q "Brick: $BASE_NAME-$peerstart.$SERVICE_NAME.$NAMESPACE")
                if (gluster volume info | grep -q ": $BASE_NAME-$peerstart.$SERVICE_NAME.$NAMESPACE.svc.cluster.local:$MOUNT_BASE$VOLUME_BASE$volstart/brick$volstart")
                then
                  echo "brick and volume already exist for $BASE_NAME-$peerstart.$SERVICE_NAME.$NAMESPACE.svc.cluster.local:$MOUNT_BASE$VOLUME_BASE$volstart" >> /usr/share/bin/gluster.log

                else
                  echo "Adding brick, Volume already exists" >> /usr/share/bin/gluster.log
                  result=`eval gluster volume add-brick brick$volstart replica $REPLICA_COUNT $BASE_NAME-$peerstart.$SERVICE_NAME.$NAMESPACE.svc.cluster.local:$MOUNT_BASE$VOLUME_BASE$volstart force || true`
                  wait
                fi
              else
                echo "Volume does not exist" >> /usr/share/bin/gluster.log
                VOLUME_LIST="$VOLUME_LIST $BASE_NAME-$peerstart.$SERVICE_NAME.$NAMESPACE.svc.cluster.local:$MOUNT_BASE$VOLUME_BASE$volstart/brick$volstart"
                echo " ... ... $VOLUME_LIST" >> /usr/share/bin/gluster.log
              fi
            done

            # Create our initial volumes and bricks, if they don't already exist
            echo "volumelist = $VOLUME_LIST" >> /usr/share/bin/gluster.log
            if [ "$VOLUME_LIST" == "" ]
            then
              echo "Nothing to do for volumes and bricks" >> /usr/share/bin/gluster.log
            else
              echo "No Volumes Exists - Let's Run our create volume command" >> /usr/share/bin/gluster.log
              result=`eval gluster volume create $VOLUME_BASE$volstart replica $REPLICA_COUNT $VOLUME_LIST force`
              wait
              result=`eval gluster volume start $VOLUME_BASE$volstart`
              wait
              echo " volume $VOLUME_BASE$volstart created and started" >> /usr/share/bin/gluster.log
            fi

            # need to check volume mount
            echo "" >> /usr/share/bin/gluster.log
            echo " ... Checking For Volume Mount Status for brick$volstart" >> /usr/share/bin/gluster.log
            if [ "$HOSTNAME" == "$THIS_HOST" ]
            then
              echo " ... ... Check to see if fuse mount exists?" >> /usr/share/bin/gluster.log
              # if grep -qs '$FUSE_BASE$VOLUME_BASE$volstart' /proc/mounts
              if (mount | grep -q "$FUSE_BASE$VOLUME_BASE$volstart")
              then
                echo " ... ... ... It does exist, so no action needed to mount brick$volstart" >> /usr/share/bin/gluster.log                     
              else
                if [ ! -d "$FUSE_BASE$VOLUME_BASE$volstart" ] 
                then
                  echo " ... ... ... Creating mount directory" >> /usr/share/bin/gluster.log
                  result=`eval mkdir -p $FUSE_BASE$VOLUME_BASE$volstart` 
                fi
                MOUNT_CMD="mount -t glusterfs  $DNSHOSTPOD:$VOLUME_BASE$volstart $FUSE_BASE$VOLUME_BASE$volstart"
                echo " ... ... ... It does not exist, so create mount CMD = $MOUNT_CMD" >> /usr/share/bin/gluster.log
                echo " ... ... ... Running Mount Command" >> /usr/share/bin/gluster.log 
                result=`eval $MOUNT_CMD`
                wait
                MOUNT_CMD=""
                echo " ... ... ... Mount Completed Successfully!!" >> /usr/share/bin/gluster.log
              fi
            fi
            echo "" >> /usr/share/bin/gluster.log
          done
      else
          echo "Volume SetUp turned off - to turn on change statefulset value to 1" >> /usr/share/bin/gluster.log
      fi
      echo "Probe ran - updated peers with pool now at $REPLICA_COUNT" >> /usr/share/bin/gluster.log

  elif (gluster peer status | grep -q "Peer Rejected")
  then
      echo "We have a rejected peer - need to handle" >> /usr/share/bin/gluster.log
      rejectedhost="$(gluster peer status | grep -B 2 'Peer Rejected' | grep 'Hostname:'|cut -f2 -d ':' | tr -d '[:space:]')"
      echo "... rejected host = $rejectedhost" >> /usr/share/bin/gluster.log
      if [ "$DNSHOSTPOD" == "$rejectedhost" ]
      then
         echo "... This is target rejected peer! - $HOSTPOD - $DNSHOSTPOD" >> /usr/share/bin/gluster.log
         echo "... stopping glusterd" >> /usr/share/bin/gluster.log
         systemctl stop glusterd
         echo "... stopped glusterd" >> /usr/share/bin/gluster.log
         echo "... deleting files" >> /usr/share/bin/gluster.log
         cp /var/lib/glusterd/glusterd.info /tmp
         rm -rf /var/lib/glusterd/*
         cp /tmp/glusterd.info /var/lib/glusterd/
         echo "... files deleted restarting glusterd" >> /usr/share/bin/gluster.log
         systemctl start glusterd

         # now recheck a few times
         echo "... recycling glusterd a few times" >> /usr/share/bin/gluster.log
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
          echo "... peer probing and restarting glusterd, not target rejected peer - $HOSTPOD" >> /usr/share/bin/gluster.log
          systemctl restart glusterd 
      fi

  elif [ "${ORIGINAL_PEER_COUNT}" -eq "0" ] && [ "$INITIAL_RUN" == "no" ]
  then
      echo "We have a recycled pod - need to handle" >> /usr/share/bin/gluster.log
      peerstart=-1
      until test $peerstart -eq $PEER_COUNT
      do
        peerstart=$(( $peerstart + 1 ))
        if (gluster peer status | grep -q "Hostname: $BASE_NAME-$peerstart.$SERVICE_NAME.$NAMESPACE.svc.cluster.local")
        then
            echo "no need to peer probe already exists" >> /usr/share/bin/gluster.log
        else
            echo "... ... peer probe for $BASE_NAME-$peerstart.$SERVICE_NAME.$NAMESPACE.svc.cluster.local" >> /usr/share/bin/gluster.log
            result=`eval gluster peer probe $BASE_NAME-$peerstart.$SERVICE_NAME.$NAMESPACE.svc.cluster.local`
        fi           
      done
      echo "... Probe Complete" >> /usr/share/bin/gluster.log

      if [ "$CREATE_VOLUMES" -eq "1" ]
      then
          # Analyze and Create or Prepare to Create Volumes and Bricks if Needed!
          echo "" >> /usr/share/bin/gluster.log          
          echo " ... ... Analyzing Environment for Volumes and Bricks" >> /usr/share/bin/gluster.log 
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
                echo "... ... Looking for Brick: $BASE_NAME-$peerstart.$SERVICE_NAME.$NAMESPACE.svc.cluster.local:$MOUNT_BASE$VOLUME_BASE$volstart" >> /usr/share/bin/gluster.log
                echo "" >> /usr/share/bin/gluster.log

                # if (gluster volume status all | grep -q "Brick: $BASE_NAME-$peerstart.$SERVICE_NAME.$NAMESPACE")
                if (gluster volume info | grep -q ": $BASE_NAME-$peerstart.$SERVICE_NAME.$NAMESPACE.svc.cluster.local:$MOUNT_BASE$VOLUME_BASE$volstart/brick$volstart")
                then
                  echo "brick and volume already exist for $BASE_NAME-$peerstart.$SERVICE_NAME.$NAMESPACE.svc.cluster.local:$MOUNT_BASE$VOLUME_BASE$volstart" >> /usr/share/bin/gluster.log

                else
                  echo "Adding brick, Volume already exists" >> /usr/share/bin/gluster.log
                  result=`eval gluster volume add-brick brick$volstart replica $REPLICA_COUNT $BASE_NAME-$peerstart.$SERVICE_NAME.$NAMESPACE.svc.cluster.local:$MOUNT_BASE$VOLUME_BASE$volstart force || true`
                  wait
                fi
              else
                echo "Volume does not exist" >> /usr/share/bin/gluster.log
                VOLUME_LIST="$VOLUME_LIST $BASE_NAME-$peerstart.$SERVICE_NAME.$NAMESPACE.svc.cluster.local:$MOUNT_BASE$VOLUME_BASE$volstart/brick$volstart"
                echo " ... ... $VOLUME_LIST" >> /usr/share/bin/gluster.log
              fi
            done

            # Create our initial volumes and bricks, if they don't already exist
            echo "volumelist = $VOLUME_LIST" >> /usr/share/bin/gluster.log
            if [ "$VOLUME_LIST" == "" ]
            then
              echo "Nothing to do for volumes and bricks" >> /usr/share/bin/gluster.log
            else
              echo "No Volumes Exists - Let's Run our create volume command" >> /usr/share/bin/gluster.log
              result=`eval gluster volume create $VOLUME_BASE$volstart replica $REPLICA_COUNT $VOLUME_LIST force`
              wait
              result=`eval gluster volume start $VOLUME_BASE$volstart`
              wait
              echo " volume $VOLUME_BASE$volstart created and started" >> /usr/share/bin/gluster.log
            fi

            # need to check volume mount
            echo "" >> /usr/share/bin/gluster.log
            echo " ... Checking For Volume Mount Status for brick$volstart" >> /usr/share/bin/gluster.log
            if [ "$HOSTNAME" == "$THIS_HOST" ]
            then
              echo " ... ... Check to see if fuse mount exists?" >> /usr/share/bin/gluster.log
              # if grep -qs '$FUSE_BASE$VOLUME_BASE$volstart' /proc/mounts
              if (mount | grep -q "$FUSE_BASE$VOLUME_BASE$volstart")
              then
                echo " ... ... ... It does exist, so no action needed to mount brick$volstart" >> /usr/share/bin/gluster.log                     
              else
                if [ ! -d "$FUSE_BASE$VOLUME_BASE$volstart" ] 
                then
                  echo " ... ... ... Creating mount directory" >> /usr/share/bin/gluster.log
                  result=`eval mkdir -p $FUSE_BASE$VOLUME_BASE$volstart` 
                fi
                MOUNT_CMD="mount -t glusterfs  $DNSHOSTPOD:$VOLUME_BASE$volstart $FUSE_BASE$VOLUME_BASE$volstart"
                echo " ... ... ... It does not exist, so create mount CMD = $MOUNT_CMD" >> /usr/share/bin/gluster.log
                echo " ... ... ... Running Mount Command" >> /usr/share/bin/gluster.log 
                result=`eval $MOUNT_CMD`
                wait
                MOUNT_CMD=""
                echo " ... ... ... Mount Completed Successfully!!" >> /usr/share/bin/gluster.log
              fi
            fi
            echo "" >> /usr/share/bin/gluster.log
          done
      else
          echo "Volume SetUp turned off - to turn on change statefulset value to 1" >> /usr/share/bin/gluster.log
      fi

      echo "Probe Ran - updated peers with pool now at $REPLICA_COUNT" >> /usr/share/bin/gluster.log

  elif [ "${ORIGINAL_PEER_COUNT}" -eq "${PEER_COUNT}" ] && [ "$INITIAL_RUN" == "no" ]
  then
      echo "No need to add peers, nothing has changed" >> /usr/share/bin/gluster.log
      echo " ...let's check for volumes???" >> /usr/share/bin/gluster.log

      if [ "$CREATE_VOLUMES" -eq "1" ]
      then
          # Analyze and Create or Prepare to Create Volumes and Bricks if Needed!
          echo "" >> /usr/share/bin/gluster.log          
          echo " ... ... Analyzing Environment for Volumes and Bricks" >> /usr/share/bin/gluster.log 
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
                echo "... ... Looking for Brick: $BASE_NAME-$peerstart.$SERVICE_NAME.$NAMESPACE.svc.cluster.local:$MOUNT_BASE$VOLUME_BASE$volstart" >> /usr/share/bin/gluster.log
                echo "" >> /usr/share/bin/gluster.log

                # if (gluster volume status all | grep -q "Brick: $BASE_NAME-$peerstart.$SERVICE_NAME.$NAMESPACE")
                if (gluster volume info | grep -q ": $BASE_NAME-$peerstart.$SERVICE_NAME.$NAMESPACE.svc.cluster.local:$MOUNT_BASE$VOLUME_BASE$volstart/brick$volstart")
                then
                  echo "brick and volume already exist for $BASE_NAME-$peerstart.$SERVICE_NAME.$NAMESPACE.svc.cluster.local:$MOUNT_BASE$VOLUME_BASE$volstart" >> /usr/share/bin/gluster.log

                else
                  echo "Adding brick, Volume already exists" >> /usr/share/bin/gluster.log
                  result=`eval gluster volume add-brick brick$volstart replica $REPLICA_COUNT $BASE_NAME-$peerstart.$SERVICE_NAME.$NAMESPACE.svc.cluster.local:$MOUNT_BASE$VOLUME_BASE$volstart force || true`
                  wait
                fi
              else
                echo "Volume does not exist" >> /usr/share/bin/gluster.log
                VOLUME_LIST="$VOLUME_LIST $BASE_NAME-$peerstart.$SERVICE_NAME.$NAMESPACE.svc.cluster.local:$MOUNT_BASE$VOLUME_BASE$volstart/brick$volstart"
                echo " ... ... $VOLUME_LIST" >> /usr/share/bin/gluster.log
              fi
            done

            # Create our initial volumes and bricks, if they don't already exist
            echo "volumelist = $VOLUME_LIST" >> /usr/share/bin/gluster.log
            if [ "$VOLUME_LIST" == "" ]
            then
              echo "Nothing to do for volumes and bricks" >> /usr/share/bin/gluster.log
            else
              echo "No Volumes Exists - Let's Run our create volume command" >> /usr/share/bin/gluster.log
              result=`eval gluster volume create $VOLUME_BASE$volstart replica $REPLICA_COUNT $VOLUME_LIST force`
              wait
              result=`eval gluster volume start $VOLUME_BASE$volstart`
              wait
              echo " volume $VOLUME_BASE$volstart created and started" >> /usr/share/bin/gluster.log
            fi

            # need to check volume mount
            echo "" >> /usr/share/bin/gluster.log
            echo " ... Checking For Volume Mount Status for brick$volstart" >> /usr/share/bin/gluster.log
            if [ "$HOSTNAME" == "$THIS_HOST" ]
            then
              echo " ... ... Check to see if fuse mount exists?" >> /usr/share/bin/gluster.log
              # if grep -qs '$FUSE_BASE$VOLUME_BASE$volstart' /proc/mounts
              if (mount | grep -q "$FUSE_BASE$VOLUME_BASE$volstart")
              then
                echo " ... ... ... It does exist, so no action needed to mount brick$volstart" >> /usr/share/bin/gluster.log                     
              else
                if [ ! -d "$FUSE_BASE$VOLUME_BASE$volstart" ] 
                then
                  echo " ... ... ... Creating mount directory" >> /usr/share/bin/gluster.log
                  result=`eval mkdir -p $FUSE_BASE$VOLUME_BASE$volstart` 
                fi
                MOUNT_CMD="mount -t glusterfs  $DNSHOSTPOD:$VOLUME_BASE$volstart $FUSE_BASE$VOLUME_BASE$volstart"
                echo " ... ... ... It does not exist, so create mount CMD = $MOUNT_CMD" >> /usr/share/bin/gluster.log
                echo " ... ... ... Running Mount Command" >> /usr/share/bin/gluster.log 
                result=`eval $MOUNT_CMD`
                wait
                MOUNT_CMD=""
                echo " ... ... ... Mount Completed Successfully!!" >> /usr/share/bin/gluster.log
              fi
            fi
            echo "" >> /usr/share/bin/gluster.log
          done
      else
          echo "Volume SetUp turned off - to turn on change statefulset value to 1" >> /usr/share/bin/gluster.log
      fi
      echo "Probe Ran - did not update peers, replica count at $REPLICA_COUNT" >> /usr/share/bin/gluster.log


  elif [ "${EXPECTED_REPLICA_COUNT}" -lt "$REPLICA_COUNT" ] && [ "$INITIAL_RUN" == "no" ]
  then
      echo "Cluster needs to scale up!" >> /usr/share/bin/gluster.log
      
      numup=$(( $REPLICA_COUNT - $CURRENT_NODE_COUNT ))          
      peerstart=$(( $CURRENT_NODE_COUNT - 1 ))
      peerlimit=$(( $peerstart + $numup ))
      echo "... ... numup = $numup" >> /usr/share/bin/gluster.log
      echo "... ... peerstart=$peerstart" >> /usr/share/bin/gluster.log
      echo "... ... peerlimit=$peerlimit" >> /usr/share/bin/gluster.log
      until test $peerstart -eq $peerlimit
      do
        peerstart=$(( $peerstart + 1 ))
        if (gluster peer status | grep -q "Hostname: $BASE_NAME-$peerstart.$SERVICE_NAME.$NAMESPACE.svc.cluster.local")
        then
           # Do nothing
           echo "... ...nothing to change" >> /usr/share/bin/gluster.log
        else
           # Add to TSP
           echo "...Adding to TSP $BASE_NAME-$peerstart.$SERVICE_NAME.$NAMESPACE.svc.cluster.local" >> /usr/share/bin/gluster.log
           result=`eval gluster peer probe $BASE_NAME-$peerstart.$SERVICE_NAME.$NAMESPACE.svc.cluster.local`

           # here we need to add new brick for new node
           # gluster volume add-brick $VOLUME_BASE$volstart replica "$REPLICA_COUNT$VOLUME_LIST"
           echo "...Check Volumes" >> /usr/share/bin/gluster.log
           if [ "$CREATE_VOLUMES" -eq "1" ]
           then
               echo "... ... Adding bricks if needed" >> /usr/share/bin/gluster.log
               volstart=-1
               until test $volstart -eq $VOLUME_COUNT
               do
                 volstart=$(( $volstart + 1 ))
                  echo "add-brick command: $VOLUME_BASE$volstart replica $REPLICA_COUNT $BASE_NAME-$peerstart.$SERVICE_NAME.$NAMESPACE.svc.cluster.local:$MOUNT_BASE$VOLUME_BASE$volstart" >> /usr/share/bin/gluster.log
                 # gluster volume create glusterfs-data0 glusterfs-0.glusterfs.default.svc.cluster.local:/mnt/storage/glusterfs-data0 glusterfs-1.glusterfs.default.svc.cluster.local:/mnt/storage/glusterfs-data0 force 
                 result=`eval gluster volume add-brick brick$volstart replica $REPLICA_COUNT $BASE_NAME-$peerstart.$SERVICE_NAME.$NAMESPACE.svc.cluster.local:$MOUNT_BASE$VOLUME_BASE$volstart force || true`
                 wait
               done
           fi
        fi
      done
      echo "Probe Ran - update peers, replica count at $REPLICA_COUNT" >> /usr/share/bin/gluster.log

  elif [ "${EXPECTED_REPLICA_COUNT}" -gt "$REPLICA_COUNT" ] && [ "$INITIAL_RUN" == "no" ]
  then
      echo "Cluster needs to scale down!" >> /usr/share/bin/gluster.log
      numdown=$(( $CURRENT_NODE_COUNT - $REPLICA_COUNT ))          
      peerstart1=$(( $CURRENT_NODE_COUNT - $numdown ))
      peerstart=$(( $peerstart1 - 1 ))
      limitdown=$(( $CURRENT_NODE_COUNT - 1 ))
      echo "... ... numdown = $numdown" >> /usr/share/bin/gluster.log
      echo "... ... peerstart=$peerstart" >> /usr/share/bin/gluster.log
      echo "... ... limitdown=$limitdown" >> /usr/share/bin/gluster.log
      until test $peerstart -eq $limitdown
      do
        # TODO: Need to remove any bricks that exist for these nodes
        peerstart=$(( $peerstart + 1 )) 

        if [ "$CREATE_VOLUMES" -eq "1" ]
        then
           echo "... ... Removing bricks if needed" >> /usr/share/bin/gluster.log
           volstart=-1
           until test $volstart -eq $VOLUME_COUNT
           do
             volstart=$(( $volstart + 1 ))
             echo "remove-brick command: $VOLUME_BASE$volstart replica $REPLICA_COUNT $BASE_NAME-$peerstart.$SERVICE_NAME.$NAMESPACE.svc.cluster.local:$MOUNT_BASE$VOLUME_BASE$volstart" >> /usr/share/bin/gluster.log
             result=`eval y | gluster volume remove-brick brick$volstart replica $REPLICA_COUNT $BASE_NAME-$peerstart.$SERVICE_NAME.$NAMESPACE.svc.cluster.local:$MOUNT_BASE$VOLUME_BASE$volstart`
             wait
           done
        fi

        # Remove from TSP
        if (gluster peer status | grep -q "Hostname: $BASE_NAME-$peerstart.$SERVICE_NAME.$NAMESPACE.svc.cluster.local")
        then
            result=`eval gluster peer detach $BASE_NAME-$peerstart.$SERVICE_NAME.$NAMESPACE.svc.cluster.local`
            wait
        else
            echo "...Nothing to do here" >> /usr/share/bin/gluster.log
        fi

      done
      echo "Probe Ran - Removed peers, replica count at $REPLICA_COUNT" >> /usr/share/bin/gluster.log

  else
      echo "This should be a catch all - but should never happen" >> /usr/share/bin/gluster.log
  fi
  echo "" >> /usr/share/bin/gluster.log
  exit 0
elif [ test -f /usr/share/bin/gluster.log ]
then
  exit 0
else 
  echo "" >> /usr/share/bin/gluster.log
  echo "Liveness Probe Failed" >> /usr/share/bin/gluster.log
  echo "Liveness Probe Failed" >> /usr/share/bin/gluster.log
  exit 1
fi

# checkVolumeAndBricks analyzes state of current glusterfs volumes
# and the corresponding bricks
# expects $VOLUME_LIST and $volstart params
function checkVolumesAndBricks () {
    # Create our initial volumes and bricks, if they don't already exist
    echo "volumelist = $VOLUME_LIST" >> /usr/share/bin/gluster.log
    if [ "$VOLUME_LIST" == "" ]
    then
       echo "Nothing to do for volumes and bricks" >> /usr/share/bin/gluster.log
    else
       echo "No Volumes Exists - Let's Run our create volume command" >> /usr/share/bin/gluster.log
       result=`eval gluster volume create $VOLUME_BASE$volstart replica $REPLICA_COUNT $VOLUME_LIST force`
       wait
       result=`eval gluster volume start $VOLUME_BASE$volstart`
       wait
       echo " volume $VOLUME_BASE$volstart created and started" >> /usr/share/bin/gluster.log
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
   echo " ... Checking For Volume Mount Status for brick$volstart" >> /usr/share/bin/gluster.log
   if [ "$HOSTNAME" == "$THIS_HOST" ]
   then
     echo " ... ... Check to see if fuse mount exists?" >> /usr/share/bin/gluster.log
     # if grep -qs '$FUSE_BASE$VOLUME_BASE$volnum' /proc/mounts
     if (mount | grep -q "$FUSE_BASE$VOLUME_BASE$volnum")
     then
        echo " ... ... ... It does exist, so no action needed to mount brick$volnum" >> /usr/share/bin/gluster.log                     
     else
        # make sure our mount dir exists
        if [ ! -d "$FUSE_BASE$VOLUME_BASE$volnum" ] 
        then
          echo " ... ... ... Creating mount directory" >> /usr/share/bin/gluster.log
          result=`eval mkdir -p $FUSE_BASE$VOLUME_BASE$volnum` 
        fi

        MOUNT_CMD="mount -t glusterfs  $DNSHOSTPOD:$VOLUME_BASE$volstart $FUSE_BASE$VOLUME_BASE$volnum"
        echo " ... ... ... It does not exist, so create mount CMD = $MOUNT_CMD" >> /usr/share/bin/gluster.log
        echo " ... ... ... Running Mount Command" >> /usr/share/bin/gluster.log
        result=`eval $MOUNT_CMD`
        wait
        MOUNT_CMD=""
        echo " ... ... ... Mount Completed Successfully!!" >> /usr/share/bin/gluster.log
     fi
   fi
}


