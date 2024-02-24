# 利用kube-vip搭建高可用k3s控制平面和服务负载均衡

> 2024.02.24

以下内容使用kube-vip的arp模式。bgp模式的使用请参考[这里](README-bgp.md)。

## arp的介绍

arp是Address Resolution Protocol的缩写，即地址解析协议。它的作用是将IP地址解析为MAC地址。

arp模式是kube-vip的默认模式。在这个模式下，kube-vip会进行选举，选出一个节点作为leader，并在leader的网卡上绑定虚拟IP(vip)。这样，在外部访问vip时，请求会被发送到leader节点上（因为arp解析会得到leader节点的mac地址）。leader节点再将流量转发到某个control plane实例（当vip绑定到control plane时）或者某个pod实例（当vip绑定到service时）。

## 准备工作

- 3台Ubuntu 20.04机器，作为k3s server节点，每一个都运行一个control plane实例，记做`k3s-server-1`，`k3s-server-2`和`k3s-server-3`
- 1台Ubuntu 20.04机器，作为k3s agent节点，记做`k3s-agent-1`
  
可以使用虚拟机或者云服务器。这里使用vmware虚拟机。每台虚拟机连接到同一个网关，都有192.168.1.x/24的IP地址，网关为192.168.1.1。

## 部署流程

以下部署需要都需要使用root用户。

### Step 0: 清理环境

```bash
rm -rf /var/lib/rancher /etc/rancher ~/.kube/*; \
ip addr flush dev lo; \
ip addr add 127.0.0.1/8 dev lo;
```

### Step 1: 创建k3s manifest文件夹

在`k3s-server-1`上创建`/var/lib/rancher/k3s/server/manifests/`文件夹。

```bash
mkdir -p /var/lib/rancher/k3s/server/manifests/
```

之后在搭建k3s集群时，k3s会自动加载这个文件夹下的yaml文件，并且apply到集群中。

### Step 2: 下载kube-vip RBAC配置文件

在`k3s-server-1`上下载kube-vip的RBAC配置文件，放到`/var/lib/rancher/k3s/server/manifests/`文件夹下。

```bash
curl https://kube-vip.io/manifests/rbac.yaml > /var/lib/rancher/k3s/server/manifests/kube-vip-rbac.yaml
```

### Step 3: 创建 kube-vip DaemonSet 配置文件

Step3主要参考[DaemonSet | kube-vip](https://kube-vip.io/docs/installation/daemonset/#generating-a-manifest)。

#### Step 3.1：环境变量设置

在`k3s-server-1`上设置环境变量。

```bash
export VIP=192.168.1.233 # 想要给control plane绑定的vip
export INTERFACE=ens33 # 网卡名，可以根据ip addr查看。之后其他主机arp解析vip时，会得到这个网卡的mac地址
export KVVERSION=v0.7.0 # kube-vip版本，可以在https://github.com/kube-vip/kube-vip/releases查看最新版本
```

#### Step 3.2：创建kube-vip DaemonSet配置文件

使用以下命令创建kube-vip DaemonSet配置文件。需要找一台有containerd的机器。不一定要在`k3s-server-1`上执行。

```bash
alias kube-vip="ctr image pull ghcr.io/kube-vip/kube-vip:$KVVERSION; ctr run --rm --net-host ghcr.io/kube-vip/kube-vip:$KVVERSION vip /kube-vip"

kube-vip manifest daemonset \
    --interface $INTERFACE \
    --address $VIP \
    --inCluster \
    --taint \
    --controlplane \
    --services \
    --arp \
    --leaderElection
```

以上命令来自官网上的[DaemonSet | kube-vip](https://kube-vip.io/docs/installation/daemonset/#creating-the-manifest)。但是我自己没有运行成功。我把以上两个命令结合(把1代入2，不要用alias)，得到了以下命令，可以成功运行。

```bash
ctr image pull ghcr.io/kube-vip/kube-vip:$KVVERSION; 
ctr run --rm --net-host ghcr.io/kube-vip/kube-vip:$KVVERSION vip /kube-vip manifest daemonset \
    --interface $INTERFACE \
    --address $VIP \
    --inCluster \
    --taint \
    --controlplane \
    --services \
    --arp \
    --leaderElection
```

得到的kube-vip DaemonSet配置文件位于[kube-vip-daemonset-arp.yaml](kube-vip/kube-vip-daemonset-arp.yaml)。

最后，将这个配置文件放到`k3s-server-1`的`/var/lib/rancher/k3s/server/manifests/`文件夹下。

```bash
mv kube-vip-daemonset-arp.yaml /var/lib/rancher/k3s/server/manifests/
```

### Step 4: 部署k3s server

首先，在`k3s-server-1`上运行以下命令，启动k3s server（控制平面）。

```bash
# 启动一个k3s-server
curl -sfL https://get.k3s.io | K3S_TOKEN=W8Zt4xAnaJYNdPh0rBZx sh -s - server \
    --cluster-init \
    --tls-san=192.168.1.233 \ # 之前设置的vip
    --disable servicelb # 禁用k3s自带的servicelb，因为我们使用kube-vip
```

随后，在`k3s-server-2`和`k3s-server-3`上运行以下命令，启动k3s server（控制平面），并加入`k3s-server-1`。这样，三个控制平面节点组成了高可用集群。

```bash
# 另两个k3s-server加入 组成高可用controlplane
curl -sfL https://get.k3s.io | K3S_TOKEN=W8Zt4xAnaJYNdPh0rBZx sh -s - server \
    --server https://192.168.1.233:6443 \
    --tls-san=192.168.1.233 \
    --disable servicelb
```

### Step 5: 部署k3s agent

在`k3s-agent-1`上运行以下命令，作为k3s agent加入集群。

```bash
# 启动一个k3s-agent
curl -sfL https://get.k3s.io | K3S_TOKEN=W8Zt4xAnaJYNdPh0rBZx sh -s - agent --server https://192.168.1.233:6443
```

### Step 6: 查看集群状态

在`k3s-server-1`上运行以下命令，查看集群状态。

```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl get nodes
```

可以看到，三个k3s server节点和一个k3s agent节点都加入了集群。

```
root@k3s-server-2:/home/osboxes/software-install/k3s-server/kube-vip-cloud-controller# kubectl get nodes
NAME           STATUS   ROLES                       AGE   VERSION
k3s-agent-1    Ready    <none>                      22h   v1.28.6+k3s2
k3s-server-1   Ready    control-plane,etcd,master   23h   v1.28.6+k3s2
k3s-server-2   Ready    control-plane,etcd,master   22h   v1.28.6+k3s2
k3s-server-3   Ready    control-plane,etcd,master   22h   v1.28.6+k3s2
```

可以尝试ping一下控制平面的vip，看看是否能ping通。能ping通说明控制平面的vip已经绑定到了某个节点上并且可以正常工作。

```bash
PING 192.168.1.233 (192.168.1.233) 56(84) bytes of data.
64 bytes from 192.168.1.233: icmp_seq=1 ttl=64 time=0.274 ms
64 bytes from 192.168.1.233: icmp_seq=2 ttl=64 time=0.239 ms
64 bytes from 192.168.1.233: icmp_seq=3 ttl=64 time=0.217 ms
```

### Step 7: 部署kube-vip-cloud-controller

Step7主要参考[kube-vip官网上的On-Premises (kube-vip-cloud-controller) | kube-vip](https://kube-vip.io/docs/usage/cloud-provider/on-premises/)。

#### Step 7.1：安装kube-vip Cloud Provider

kube-vip Cloud Provider是一个controller，它会监听k3s集群中的service的变化。当新的service被创建时，kube-vip Cloud Provider会从配置好的vip池中选取一个vip，并绑定到service的spec.loadBalancerIP字段上。

之前以daemonset形式部署的kube-vip读取到某个service的spec.loadBalancerIP字段后，会进行一次选举选出一个节点作为该服务的leader，并在leader的网卡上绑定vip。leader接收到来自外部的流量后，会将流量转发到对应的pod上。

使用以下命令在刚刚搭建好的k3s集群中部署kube-vip Cloud Provider。

```bash
kubectl apply -f https://raw.githubusercontent.com/kube-vip/kube-vip-cloud-provider/main/manifest/kube-vip-cloud-controller.yaml
```

#### Step 7.2：创建kube-vip Cloud Provider配置文件（配置vip池）

其实就是创建一个ConfigMap，指定vip池。

以下是官网上的命令，将vip池设定为192.168.1.10-192.168.1.80

```bash
kubectl create configmap -n kube-system kubevip --from-literal range-global=192.168.1.10-192.168.1.80
```

但我实际操作的过程中，名字叫kubevip的configmap其实已经存在了，因此create会报错。因此直接patch。

```bash
kubectl patch configmap kubevip -n kube-system --type merge -p '{"data":{"range-global":"192.168.1.10-192.168.1.80"}}'
```

vip池的更多配置选项可以参考：https://kube-vip.io/docs/usage/cloud-provider/#the-kube-vip-cloud-provider-configmap

### Step 8: 部署测试应用程序

测试应用程序的yaml文件位于[sys-info-web.yaml](kube-vip-cloud-controller/sys-info-web.yaml)。其中包括了一个deployment和两个service。

```bash
kubectl apply -f sys-info-web.yaml
```

查看service。可以看到，两个service都获得了vip（EXTERNAL-IP字段）。
    
```bash
root@k3s-server-2:/home/osboxes/software-install/k3s-server/kube-vip-cloud-controller# kubectl get svc
NAME                TYPE           CLUSTER-IP      EXTERNAL-IP     PORT(S)        AGE
kubernetes          ClusterIP      10.43.0.1       <none>          443/TCP        23h
sys-info-web        LoadBalancer   10.43.212.241   192.168.1.11    80:31393/TCP   18h
sys-info-web-dhcp   LoadBalancer   10.43.19.105    192.168.1.188   80:31296/TCP   75m
```

其中，`sys-info-web`的vip是从之前设置的vip池中选取的，而`sys-info-web-dhcp`的vip是局域网内的一个dhcp服务器分配的。关于如何让dhcp服务器分配vip，可以参考：https://kube-vip.io/docs/usage/kubernetes-services/#using-dhcp-for-load-balancers-experimental-kube-vip-v021

多次通过vip访问`sys-info-web`，发现可以正常访问，说明kube-vip工作正常。并且，每次访问都会答应出不同的hostname（其实就是pod的名字），说明流量被转发到了不同的pod上。说明实现了服务负载均衡。

```
root@k3s-server-2:/home/osboxes/software-install/k3s-server/kube-vip-cloud-controller# curl 192.168.1.11/sysInfo
{"hostname":"sys-info-web-6fb996cd5b-d22x2","osVersion":"5.4.0-169-generic","cpuCores":"2","javaVersion":"17.0.8","userWorkingDirectory":"/app","userHomeDirectory":"/root","javaVendor":"Oracle Corporation","osName":"Linux","javaHomeDirectory":null}
```

```
root@k3s-server-2:/home/osboxes/software-install/k3s-server/kube-vip-cloud-controller# curl 192.168.1.11/sysInfo
{"hostname":"sys-info-web-6fb996cd5b-kjk6b","osVersion":"5.4.0-169-generic","cpuCores":"2","javaVersion":"17.0.8","userWorkingDirectory":"/app","userHomeDirectory":"/root","javaVendor":"Oracle Corporation","osName":"Linux","javaHomeDirectory":null}
```


## 参考

1. [k3s | kube-vip](https://kube-vip.io/docs/usage/k3s/): kube-vip官网上的与k3s集成的文档
2. [DaemonSet | kube-vip](https://kube-vip.io/docs/installation/daemonset/#generating-a-manifest): kube-vip官网上的使用DaemonSet部署kube-vip的文档
3. [On-Premises (kube-vip-cloud-controller) | kube-vip](https://kube-vip.io/docs/usage/cloud-provider/on-premises/): kube-vip官网上的使用kube-vip-cloud-controller的文档
4. [High Availability Embedded etcd | K3s](https://docs.k3s.io/datastore/ha-embedded): k3s官网上的高可用集群的文档(使用嵌入式etcd)