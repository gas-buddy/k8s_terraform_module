#cloud-config

---
coreos:

  etcd2:
    discovery-srv: ${discovery_srv}
    peer-trusted-ca-file: /etc/kubernetes/ssl/ca.cert.pem
    peer-client-cert-auth: true
    peer-cert-file: /etc/kubernetes/ssl/k8s-etcd.pem
    peer-key-file: /etc/kubernetes/ssl/k8s-etcd-key.pem
    proxy: on

  units:
    - name: format-ephemeral.service
      command: start
      content: |
        [Unit]
        Description=Formats the ephemeral drive
        After=dev-xvdf.device
        Requires=dev-xvdf.device
        [Service]
        ExecStart=/usr/sbin/wipefs -f /dev/xvdf
        ExecStart=/usr/sbin/mkfs.ext4 -F /dev/xvdf
        RemainAfterExit=yes
        Type=oneshot

    - name: var-lib-docker.mount
      command: start
      content: |
        [Unit]
        Description=Mount ephemeral to /var/lib/docker
        Requires=format-ephemeral.service
        After=format-ephemeral.service
        Before=docker.service
        [Mount]
        What=/dev/xvdf
        Where=/var/lib/docker
        Type=ext4

    - name: etcd2.service
      command: start

    - name: flanneld.service
      command: start
      drop-ins:
        - name: 50-network-config.conf
          content: |
            [Service]
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
        ExecStartPre=-/usr/bin/mkdir -p /etc/kubernetes/ssl
        ExecStart=/bin/sh -c "/usr/bin/curl $(/opt/bin/s3-get-presigned-url \
          us-east-1 ${ssl_bucket} /ssl/k8s-worker.tar) | tar xv -C /etc/kubernetes/ssl/"
        RemainAfterExit=yes
        Type=oneshot

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
          --api-servers=http://master.${discovery_srv}:8080 \
          --cloud-provider=aws \
          --cluster-dns=${cluster_dns} \
          --cluster-domain=cluster.local \
          --config=/etc/kubernetes/manifests \
          --kubeconfig=/etc/kubernetes/kubeconfig.yml \
          --register-node=true \
          --tls-cert-file=/etc/kubernetes/ssl/k8s-worker.pem \
          --tls-private-key-file=/etc/kubernetes/ssl/k8s-worker-key.pem
        Restart=always
        RestartSec=5
        [Install]
        WantedBy=multi-user.target

    - name: docker-monitor.service
      command: start
      content: |
        [Unit]
        Description=Kubernetes health monitoring for docker
        After=docker.service
        [Service]
        Restart=always
        RestartSec=10
        RemainAfterExit=yes
        ExecStart=/opt/bin/health-monitor.sh docker
        [Install]
        WantedBy=multi-user.target

    - name: kubelet-monitor.service
      command: start
      content: |
        [Unit]
        Description=Kubernetes health monitoring for kubelet
        After=kubelet.service
        [Service]
        Restart=always
        RestartSec=10
        RemainAfterExit=yes
        ExecStart=/opt/bin/health-monitor.sh kubelet
        [Install]
        WantedBy=multi-user.target

  update:
    reboot-strategy: etcd-lock

write-files:
  - path: /opt/bin/health-monitor.sh
    permissions: 0544
    owner: root:root
    content: |
      #!/bin/bash

      # Copyright 2016 The Kubernetes Authors.
      #
      # Licensed under the Apache License, Version 2.0 (the "License");
      # you may not use this file except in compliance with the License.
      # You may obtain a copy of the License at
      #
      #     http://www.apache.org/licenses/LICENSE-2.0
      #
      # Unless required by applicable law or agreed to in writing, software
      # distributed under the License is distributed on an "AS IS" BASIS,
      # WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
      # See the License for the specific language governing permissions and
      # limitations under the License.

      # This script is for master and node instance health monitoring, which is
      # packed in kube-manifest tarball. It is executed through a systemd service
      # in cluster/gce/gci/<master/node>.yaml. The env variables come from an env
      # file provided by the systemd service.

      set -o nounset
      set -o pipefail

      # We simply kill the process when there is a failure. Another systemd service will
      # automatically restart the process.
      function docker_monitoring {
        while [ 1 ]; do
          if ! timeout 60 docker ps > /dev/null; then
            echo "Docker daemon failed!"
            pkill docker
            # Wait for a while, as we don't want to kill it again before it is really up.
            sleep 30
          else
            sleep "$${SLEEP_SECONDS}"
          fi
        done
      }

      function kubelet_monitoring {
        echo "Wait for 2 minutes for kubelet to be functional"
        # TODO(andyzheng0831): replace it with a more reliable method if possible.
        sleep 120
        local -r max_seconds=10
        local output=""
        while [ 1 ]; do
          if ! output=$(curl -m "$${max_seconds}" -f -s -S http://127.0.0.1:10255/healthz 2>&1); then
            # Print the response and/or errors.
            echo $output
            echo "Kubelet is unhealthy!"
            pkill kubelet
            # Wait for a while, as we don't want to kill it again before it is really up.
            sleep 60
          else
            sleep "$${SLEEP_SECONDS}"
          fi
        done
      }


      ############## Main Function ################
      if [[ "$#" -ne 1 ]]; then
        echo "Usage: health-monitor.sh <docker/kubelet>"
        exit 1
      fi

      SLEEP_SECONDS=10
      component=$1
      echo "Start kubernetes health monitoring for $${component}"
      if [[ "$${component}" == "docker" ]]; then
        docker_monitoring
      elif [[ "$${component}" == "kubelet" ]]; then
        kubelet_monitoring
      else
        echo "Health monitoring for component "$${component}" is not supported!"
      fi

  - path: /opt/bin/host-rkt
    permissions: 0755
    owner: root:root
    content: |
      #!/bin/sh
      exec nsenter -m -u -i -n -p -t 1 -- /usr/bin/rkt "$@"

  - path: /etc/kubernetes/kubeconfig.yml
    content: |
      apiVersion: v1
      kind: Config
      clusters:
        - name: local
          cluster:
            certificate-authority: /etc/kubernetes/ssl/ca.cert.pem
      users:
        - name: kubelet
          user:
            client-certificate: /etc/kubernetes/ssl/k8s-worker.pem
            client-key: /etc/kubernetes/ssl/k8s-worker-key.pem
      contexts:
        - context:
            cluster: local
            user: kubelet
          name: kubelet-context
      current-context: kubelet-context

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
          - --kubeconfig=/etc/kubernetes/kubeconfig.yml
          - --master=https://master.${discovery_srv}
          - --proxy-mode=iptables
          securityContext:
            privileged: true
          volumeMounts:
            - mountPath: /etc/ssl/certs
              name: "ssl-certs"
            - mountPath: /etc/kubernetes/kubeconfig.yml
              name: "kubeconfig"
              readOnly: true
            - mountPath: /etc/kubernetes/ssl
              name: "etc-kube-ssl"
              readOnly: true
        volumes:
          - name: "ssl-certs"
            hostPath:
              path: "/usr/share/ca-certificates"
          - name: "kubeconfig"
            hostPath:
              path: "/etc/kubernetes/kubeconfig.yml"
          - name: "etc-kube-ssl"
            hostPath:
              path: "/etc/kubernetes/ssl"

  - path: /etc/logrotate.d/docker-containers
    content: |
      /var/lib/docker/containers/*/*.log {
        rotate 7
        daily
        compress
        size=1M
        missingok
        delaycompress
        copytruncate
      }
