#cloud-config

---
coreos:

  units:
    - name: etcd-member.service
      drop-ins:
        - name: 1-override.conf
          content: |
            [Service]
            Environment="ETCD_DISCOVERY=${discovery_srv}/etcd-cluster-staging"
            Environment="ETCD_ADVERTISE_CLIENT_URLS=http://${node_name}.${discovery_srv}:2379"
            Environment="ETCD_INITIAL_ADVERTISE_PEER_URLS=https://${ip_address}:2380"
            Environment="ETCD_LISTEN_CLIENT_URLS=https://0.0.0.0:2379"
            Environment="ETCD_LISTEN_PEER_URLS=https://0.0.0.0:2380"
            Environment="ETCD_TRUSTED_CA_FILE=/var/lib/etcd/ssl/ca.cert.pem"
            Environment="ETCD_PEER_TRUSTED_CA_FILE=/var/lib/etcd/ssl/ca.cert.pem"
            Environment="ETCD_CERT_FILE=/var/lib/etcd/ssl/k8s-etcd.pem"
            Environment="ETCD_KEY_FILE=/var/lib/etcd/ssl/k8s-etcd-key.pem"
            Environment="ETCD_PEER_CERT_FILE=/var/lib/etcd/ssl/k8s-etcd.pem"
            Environment="ETCD_PEER_KEY_FILE=/var/lib/etcd/ssl/k8s-etcd-key.pem"
        - name: wait-for-certs.conf
          content: |
            [Unit]
            After=get-ssl.service
            Requires=get-ssl.service
      command: start

    - name: flanneld.service
      command: start
      drop-ins:
        - name: 50-network-config.conf
          content: |
            [Service]
            ExecStartPre=-/usr/bin/etcdctl mk /coreos.com/network/config \
              '{ "Network": "${flanneld_network}", "Backend": { "Type": "vxlan" } }'
            Restart=always
            RestartSec=10

    - name: docker.service
      command: start
      drop-ins:
        - name: 40-flannel.conf
          content: |
            [Unit]
            After=flanneld.service
            Requires=flanneld.service
            [Service]
            Restart=always
            RestartSec=10
        - name: overlay.conf
          content: |
            [Service]
            Environment="DOCKER_OPTS=--storage-driver=overlay"

    - name: s3-get-presigned-url.service
      command: start
      content: |
        [Unit]
        After=network-online.target
        Description=Install s3-get-presigned-url
        Requires=network-online.target
        [Service]
        ExecStartPre=-/usr/bin/mkdir -p /opt/bin
        ExecStart=/usr/bin/curl -L -o /opt/bin/s3-get-presigned-url \
          https://github.com/kz8s/s3-get-presigned-url/releases/download/v0.1/s3-get-presigned-url_linux_amd64
        ExecStart=/usr/bin/chmod +x /opt/bin/s3-get-presigned-url
        RemainAfterExit=yes
        Type=oneshot

    - name: get-ssl.service
      command: start
      content: |
        [Unit]
        After=s3-get-presigned-url.service
        Description=Get ssl artifacts from s3 bucket using IAM role
        Requires=s3-get-presigned-url.service
        [Service]
        ExecStartPre=-/usr/bin/mkdir -p /var/lib/etcd/ssl
        ExecStart=/bin/sh -c "/usr/bin/curl $(/opt/bin/s3-get-presigned-url \
          us-east-1 ${ssl_bucket} ssl/k8s-apiserver.tar) | tar xv -C /var/lib/etcd/ssl/"
        RemainAfterExit=yes
        Type=oneshot

    - name: logrotate.timer
      drop-ins:
        - name: 10-restart_60s.conf
          content: |
            [Unit]
            Description=Hourly Log Rotation

            [Timer]
            OnCalendar=hourly
      command: start

    - name: kubelet.service
      command: start
      content: |
        [Unit]
        ConditionFileIsExecutable=/usr/lib/coreos/kubelet-wrapper
        [Service]
        Environment="KUBELET_IMAGE_URL=quay.io/coreos/hyperkube"
        Environment="KUBELET_IMAGE_TAG=${kubernetes_version}"
        Environment="RKT_OPTS=\
          --volume dns,kind=host,source=/etc/resolv.conf \
          --mount volume=dns,target=/etc/resolv.conf \
          --volume rkt,kind=host,source=/opt/bin/host-rkt \
          --mount volume=rkt,target=/usr/bin/rkt \
          --volume var-lib-rkt,kind=host,source=/var/lib/rkt \
          --mount volume=var-lib-rkt,target=/var/lib/rkt \
          --volume stage,kind=host,source=/tmp \
          --mount volume=stage,target=/tmp \
          --volume var-log,kind=host,source=/var/log \
          --mount volume=var-log,target=/var/log"
        ExecStartPre=/usr/bin/mkdir -p /var/log/containers
        ExecStartPre=/usr/bin/mkdir -p /var/lib/kubelet
        ExecStartPre=/usr/bin/mount --bind /var/lib/kubelet /var/lib/kubelet
        ExecStartPre=/usr/bin/mount --make-shared /var/lib/kubelet
        ExecStart=/usr/lib/coreos/kubelet-wrapper \
          --allow-privileged=true \
          --api-servers=http://127.0.0.1:8080 \
          --cloud-provider=aws \
          --cluster-dns=${cluster_dns} \
          --cluster-domain=cluster.local \
          --config=/etc/kubernetes/manifests \
          --register-schedulable=false
        Restart=always
        RestartSec=5
        [Install]
        WantedBy=multi-user.target

  update:
    reboot-strategy: etcd-lock

write-files:
  - path: /opt/bin/host-rkt
    permissions: 0755
    owner: root:root
    content: |
      #!/bin/sh
      exec nsenter -m -u -i -n -p -t 1 -- /usr/bin/rkt "$@"

  - path: /etc/kubernetes/manifests/kube-apiserver.yml
    content: |
      apiVersion: v1
      kind: Pod
      metadata:
        name: kube-apiserver
        namespace: kube-system
      spec:
        hostNetwork: true
        containers:
        - name: kube-apiserver
          image: quay.io/coreos/hyperkube:${kubernetes_version}
          command:
          - /hyperkube
          - apiserver
          - --admission-control=LimitRanger
          - --admission-control=NamespaceExists
          - --admission-control=NamespaceLifecycle
          - --admission-control=ResourceQuota
          - --admission-control=SecurityContextDeny
          - --admission-control=ServiceAccount
          - --allow-privileged=true
          - --client-ca-file=/var/lib/etcd/ssl/ca.cert.pem
          - --cloud-provider=aws
          - --etcd-servers=http://etcd.${discovery_srv}:2379
          - --insecure-bind-address=0.0.0.0
          - --runtime-config=batch/v2alpha1
          - --secure-port=443
          - --service-account-key-file=/var/lib/etcd/ssl/k8s-apiserver-key.pem
          - --service-cluster-ip-range=${cluster_ip_range}
          - --tls-cert-file=/var/lib/etcd/ssl/k8s-apiserver.pem
          - --tls-private-key-file=/var/lib/etcd/ssl/k8s-apiserver-key.pem
          - --v=2
          livenessProbe:
            httpGet:
              host: 127.0.0.1
              port: 8080
              path: /healthz
            initialDelaySeconds: 15
            timeoutSeconds: 15
          ports:
          - containerPort: 443
            hostPort: 443
            name: https
          - containerPort: 8080
            hostPort: 8080
            name: local
          volumeMounts:
          - mountPath: /var/lib/etcd/ssl
            name: ssl-certs-kubernetes
            readOnly: true
          - mountPath: /etc/ssl/certs
            name: ssl-certs-host
            readOnly: true
        volumes:
        - hostPath:
            path: /var/lib/etcd/ssl
          name: ssl-certs-kubernetes
        - hostPath:
            path: /usr/share/ca-certificates
          name: ssl-certs-host

  - path: /etc/kubernetes/manifests/kube-controller-manager.yml
    content: |
      apiVersion: v1
      kind: Pod
      metadata:
        name: kube-controller-manager
        namespace: kube-system
      spec:
        hostNetwork: true
        containers:
        - name: kube-controller-manager
          image: quay.io/coreos/hyperkube:${kubernetes_version}
          command:
          - /hyperkube
          - controller-manager
          - --cloud-provider=aws
          - --leader-elect=true
          - --master=http://127.0.0.1:8080
          - --root-ca-file=/var/lib/etcd/ssl/ca.cert.pem
          - --service-account-private-key-file=/var/lib/etcd/ssl/k8s-apiserver-key.pem
          resources:
            requests:
              cpu: 200m
          livenessProbe:
            httpGet:
              host: 127.0.0.1
              path: /healthz
              port: 10252
            initialDelaySeconds: 15
            timeoutSeconds: 1
          volumeMounts:
          - mountPath: /var/lib/etcd/ssl
            name: ssl-certs-kubernetes
            readOnly: true
          - mountPath: /etc/ssl/certs
            name: ssl-certs-host
            readOnly: true
        volumes:
        - hostPath:
            path: /var/lib/etcd/ssl
          name: ssl-certs-kubernetes
        - hostPath:
            path: /usr/share/ca-certificates
          name: ssl-certs-host

  - path: /etc/kubernetes/manifests/kube-proxy.yml
    content: |
      apiVersion: v1
      kind: Pod
      metadata:
        name: kube-proxy
        namespace: kube-system
      spec:
        hostNetwork: true
        containers:
        - name: kube-proxy
          image: quay.io/coreos/hyperkube:${kubernetes_version}
          command:
          - /hyperkube
          - proxy
          - --master=http://127.0.0.1:8080
          - --proxy-mode=iptables
          securityContext:
            privileged: true
          volumeMounts:
          - mountPath: /etc/ssl/certs
            name: ssl-certs-host
            readOnly: true
        volumes:
        - hostPath:
            path: /usr/share/ca-certificates
          name: ssl-certs-host

  - path: /etc/kubernetes/manifests/kube-scheduler.yml
    content: |
      apiVersion: v1
      kind: Pod
      metadata:
        name: kube-scheduler
        namespace: kube-system
      spec:
        hostNetwork: true
        containers:
        - name: kube-scheduler
          image: quay.io/coreos/hyperkube:${kubernetes_version}
          command:
          - /hyperkube
          - scheduler
          - --leader-elect=true
          - --master=http://127.0.0.1:8080
          resources:
            requests:
              cpu: 100m
          livenessProbe:
            httpGet:
              host: 127.0.0.1
              path: /healthz
              port: 10251
            initialDelaySeconds: 15
            timeoutSeconds: 1

  - path: /etc/logrotate.d/docker-containers
    content: |
      /var/lib/docker/containers/*/*.log {
        rotate 7
        hourly
        compress
        size 100M
        missingok
        delaycompress
        copytruncate
        dateext
        dateformat -%Y%m%d%H
      }