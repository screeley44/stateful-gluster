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
TBD


#### Executing the GlusterFS StatefulSet
TBD


#### Verifying Functionality
See the scratch pad from initial verification, will be similar to that, checking TSP, checking volume info and verifying replication is working


#### Running a pod that uses the GlusterFS Trusted Storage Pool Volumes
TBD - but this won't be much different than how a pod connects to an existing pvc today

---
### Kubernetes Changes Needed

#### Change the version of the StatefulSet


