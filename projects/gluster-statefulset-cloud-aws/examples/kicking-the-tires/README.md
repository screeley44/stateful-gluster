# Kicking the Tires with GlusterFS StatefulSet prototype version

## Introduction

This tutorial will walk through the steps needed to try out this StatefulSet. This particular tutorial runs on
OpenShift 3.6 but can be easily modified to run directly on Kubernetes as well.

---
### Running This Example on Existing OpenShift Cluster

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


#### Understanding and Configuring the GlusterFS StatefulSet



#### Executing the GlusterFS StatefulSet



#### Verifying Functionality



#### Running a pod that uses the GlusterFS Trusted Storage Pool Volumes

---
### Kubernetes Changes Needed

#### Change the version of the StatefulSet


