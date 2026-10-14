# Cluster DNS (k3s CoreDNS), used to keep re-resolving api.amber.com.au. The name itself is looked up
# once at startup through the pod's /etc/resolv.conf.
resolver kube-dns.kube-system.svc.cluster.local valid=60s ipv6=off;
resolver_timeout 5s;
