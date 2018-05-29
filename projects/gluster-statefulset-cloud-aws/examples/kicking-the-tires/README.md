# Kicking the Tires with GlusterFS StatefulSet prototype version on AWS

## Introduction

This tutorial will walk through the steps needed to try out this StatefulSet. This particular tutorial runs on
OpenShift 3.6 but can be easily modified to run directly on Kubernetes as well.

---
### Running This Example on Existing OpenShift Cluster on AWS

#### Prereqs

1.  Open the GlusterFS ports on each node that could potentially host a GlusterFS pod.

- Edit the /etc/sysconfig/iptables file and add in the following ports.

```
-A OS_FIREWALL_ALLOW -p tcp -m state --state NEW -m tcp --dport 24007 -j ACCEPT
-A OS_FIREWALL_ALLOW -p tcp -m state --state NEW -m tcp --dport 24008 -j ACCEPT
-A OS_FIREWALL_ALLOW -p tcp -m state --state NEW -m tcp --dport 2222 -j ACCEPT
-A OS_FIREWALL_ALLOW -p tcp -m state --state NEW -m multiport --dports 49152:49664 -j ACCEPT
-A OS_FIREWALL_ALLOW -p tcp -m state --state NEW -m tcp --dport 24010 -j ACCEPT
-A OS_FIREWALL_ALLOW -p tcp -m state --state NEW -m tcp --dport 3260 -j ACCEPT
-A OS_FIREWALL_ALLOW -p tcp -m state --state NEW -m tcp --dport 111 -j ACCEPT
```

- Save the file and reload iptables

```
  systemctl reload iptables
```


2.  Run the following OCP role changes

```
  # oadm policy add-cluster-role-to-user cluster-reader system:serviceaccount:default:default
```

3.  Make sure the default router is running, if you installed with openshift-ansible, it most likely is, if it's not, then run the following command:

```
  oadm router default-router --replicas=3
```

```
 # oc get pods -o wide | grep router
NAME                      READY     STATUS    RESTARTS   AGE       IP              NODE
router-1-6d2br            1/1       Running   5          15d       172.18.11.126   ip-172-18-11-126.ec2.internal
router-1-6g2vj            1/1       Running   5          15d       172.18.9.44     ip-172-18-9-44.ec2.internal
router-1-shkhn            1/1       Running   5          15d       172.18.7.178    ip-172-18-7-178.ec2.internal
```

After it is up and running add the following into the dnsmasq, where *cloudapps.example.com* is your subdomain

```
  address=/.cloudapps.example.com/<one of your router ip's>

  i.e.  address=/.cloudapps.example.com/172.18.7.178


  Then restart dnsmasq service
  
  systemctl restart dnsmasq

```

4.  Create your script directory on each node

- Since we are manually creating this script for this first version, you need to have it on each node and then
  in the statefulset we do a hostPath mount to the directory so the container can read and write to the working directory
  * Alternatively, the script could be incorporated into the image via the Dockerfile build file

```
  mkdir -p /usr/share/gluster-scripts
```

- clone this repo or copy the gluster-post.sh script into this directory

- Also copy or have available the glusterfs-statefulset.yaml


#### Understanding and Configuring the GlusterFS StatefulSet and Service

Each GlusterFS statefulset will need it's own dedicated service, this allows communication between the containers and nodes.

```
apiVersion: v1
kind: Service
metadata:
  name: glusterfs <1>
  labels:
    app: glusterfs <2>
    glusterfs: service
spec:
  ports:
  - port: 24007
    name: glusterd
  - port: 24008
    name: management
  clusterIP: None
  selector:
    app: glusterfs <3>

```
<1> Name of the service, this will be used in the statefulset definition as well.

<2> A lable identifying our application identifier.

<3> This is our application identifier for our StatefulSet, and let's the service know which pods it will manage.


The StatefulSet itself will have several benefits to help enable a functional GlusterFS cluster
- Persistent DNS based hostname (IP is not guaranteed, but hostname will remain between restarts, moving to new nodes, etc....)
- Ability to use Persistent Storage Model (i.e. keeping Gluster State and Data in a Persistent Volume)
- Ability to take advantage of Kube primitives such as livenessProbes and hooks
- Ability to create and run multiple GlusterFS clusters in a single Kube cluster
- Ability to dynamically provision data volumes on cloud

Below is an example statefulset and what parameters and settings are of particular importance

```
kind: StatefulSet
apiVersion: apps/v1beta2  # change this to v1beta1 for OCP 3.6
metadata:
  name: glusterfs                         <1>
  labels:
    glusterfs: statefulset
  annotations:
    description: GlusterFS StatefulSet
    tags: glusterfs
spec:
  selector:
    matchLabels:
      app: glusterfs                       <2>
  serviceName: glusterfs                   <3>
  replicas: 3                              <4>
  podManagementPolicy: Parallel
  updateStrategy:
    type: RollingUpdate
  template:
    metadata:
      name: glusterfs
      labels:
        app: glusterfs                     <2>
        glusterfs: pod
        glusterfs-node: pod
    spec:
      hostNetwork: false
      containers:
      - image: gluster/gluster-centos:latest
        imagePullPolicy: IfNotPresent
        name: glusterfs
        lifecycle:
          postStart:                      <5>    
            exec:
              command: 
              - "chmod"
              - "+x"
              - "/usr/share/bin/gluster-post.sh"  
        ports:
        - containerPort: 24007
        - containerPort: 24008
        env:
        - name: BASE_NAME                       <1>
          value: "glusterfs"
        - name: SERVICE_NAME                    <3>
          value: "glusterfs"
        - name: NAMESPACE                       <6>
          value: "default"
        - name: ORIGINAL_PEER_COUNT             <4>
          value: "3"
        - name: DNS_DOMAIN                      <7> 
          value: "svc.cluster.local"
        - name: MOUNT_BASE                       <8>
          value: "/mnt/glusterfs-volume/"
        - name: VOLUME_BASE                      <9>
          value: "glusterfs-data"
        - name: FUSE_BASE                        <10>
          value: "/mnt/glusterfs-storage/"
        - name: VOLUME_COUNT                     <11>
          value: "1"
        - name: CREATE_VOLUMES                   <12>
          value: "1"
        - name: SET_IDENTIFIER                   <2>
          value: "app=glusterfs"
        - name: LOG_NAME                         <13>
          value: "/usr/share/bin/glusterfs.log"
        resources:
          requests:
            memory: 100Mi
            cpu: 100m
        volumeMounts:
        - name: glusterfs-state
          mountPath: "/glusterfs"
        - name: glusterd-state
          mountPath: "/var/lib/glusterd"
        - name: glusterfs-cgroup
          mountPath: "/sys/fs/cgroup"
          readOnly: true
        - name: glusterfs-ssl
          mountPath: "/etc/ssl"
          readOnly: true
        - name: gluster-scripts
          mountPath: "/usr/share/bin"
        - name: glusterfs-data0
          mountPath: "/mnt/glusterfs-volume/glusterfs-data0"
        securityContext:
          capabilities: {}
          privileged: true
        readinessProbe:
          timeoutSeconds: 3
          initialDelaySeconds: 10
          tcpSocket:
            port: 24007
          periodSeconds: 15
          successThreshold: 1
          failureThreshold: 12
        livenessProbe:                           <5>
          exec:
            command:
            - "/bin/sh"
            - "-c"
            - "source ./usr/share/bin/gluster-post.sh"
          initialDelaySeconds: 180
          periodSeconds: 60
      volumes:
      - name: glusterfs-cgroup
        hostPath:
          path: "/sys/fs/cgroup"
      - name: glusterfs-ssl
        hostPath:
          path: "/etc/ssl"
      - name: gluster-scripts                    <14>
        hostPath:
          path: "/usr/share/gluster-scripts"
  volumeClaimTemplates:
  - metadata:
      name: glusterfs-state                      <15>
    spec:
      accessModes: [ "ReadWriteOnce" ]
      storageClassName: gluster
      resources:
        requests:
          storage: 5Gi
  - metadata:
      name: glusterd-state                       <16> 
    spec:
      accessModes: [ "ReadWriteOnce" ]
      storageClassName: gluster
      resources:
        requests:
          storage: 20Gi
  - metadata:
      name: glusterfs-data0                     <17>
    spec:
      accessModes: [ "ReadWriteOnce" ]
      storageClassName: gluster
      resources:
        requests:
          storage: 80Gi

```
<1> Name of the Statefulset and BASE_NAME, these should always match and this should be unique and consistent for other naming within the Statefulset.

<2> Application Identifier, a unique grouping of components, in this case our GlusterFS pods.

<3> Service Name and SERVICE_NAME, these should match and they define the service that will manage this Statefulset and it's components, it needs to match the actual service that was created in the previous step.

<4> Replicas and ORIGINAL_PEER_COUNT should always match and should be the number of GlusterFS pods you want to run, you must have at least that many nodes to be scheduled.

<5> The LifeCycle postStart hook and livenessProbes are the Kube primitives that will initialize and invoke the Management Script/Code/etc... used to manage the GlusterFS cluster.

<6> Kube Namespace where Set is deployed.

<7> The Kube domain, default is svc.cluster.local.

<8> MOUNT_BASE + VOLUME_BASE should match volumeMounts mountPath minus the numeric identifier i.e. glusterfs-data0, 1, 2, 3 etc...

<9> MOUNT_BASE + VOLUME_BASE should match volumeMounts mountPath minus the numeric identifier i.e. glusterfs-data0, 1, 2, 3 etc...

<10> FUSE_BASE is the base dirs where our fuse mount will live and where data will be accessed, etc. FUSE_BASE + VOLUME_BASE.

<11> Num of volumes to manage if CREATE_VOLUMES is turned on, This should always match the num of dynamic glusterfs-dataX volumes <17>.

<12> Boolean controlling whether volumes should be managed.

<13> Log Dir and Name for mgmt script log dir and name, accessible by hostPath volumeMount below.

<14> HostPath directory for where the management script will be housed, This can go away if script/code is delivered in another way.

<15> Dynamic volume that will store the GlusterFS state in a PV.

<16> Dynamic volume that will store the GlusterFS state in a PV.

<17> Dynamci volume that will store the actual GlusterFS Volumes, Bricks and Data. Can have as many as you want but follow the naming convention of <VOLUME_BASE> + counter (i.e. 0, 1, 2, 3, etc...)



#### Executing the GlusterFS StatefulSet
TBD


#### Verifying Functionality
See the scratch pad from initial verification, will be similar to that, checking TSP, checking volume info and verifying replication is working


#### Running a pod that uses the GlusterFS Trusted Storage Pool Volumes
TBD - but this won't be much different than how a pod connects to an existing pvc today

---
### Kubernetes Changes Needed

#### Change the version of the StatefulSet


