#!/bin/bash

export EKS_CLUSTER_NAME=tap-full
export TAP_VERSION=1.4.2
export OOTB_SUPPLY_CHAIN_VERSION=0.11.2

full_domain=full.tap.nycpivot.com
target_tbs_repo=tap-build-service
git_catalog_repository=tanzu-application-platform


#INSTALL TAP WITH OOTB TESTING
echo
echo "<<< UPDATE SUPPLY CHAIN TO OOTB TESTING >>>"
echo

rm tap-values-full-ootb-testing.yaml
cat <<EOF | tee tap-values-full-ootb-testing.yaml
registry:
  server: "964978768106.dkr.ecr.us-east-1.amazonaws.com"
  repository: "tanzu-application-platform"
grype:
  namespace: "default"
  targetImagePullSecret: "registry-credentials"
EOF

tanzu package installed update tap -v $OOTB_SUPPLY_CHAIN_VERSION --values-file tap-values-full-ootb-testing.yaml -n tap-install
#tanzu package installed get tap -n tap-install
#tanzu package installed list -A

#tanzu apps cluster-supply-chain list

tanzu package install ootb-supply-chain-testing \
  --package-name ootb-supply-chain-testing.tanzu.vmware.com \
  --version $OOTB_SUPPLY_CHAIN_VERSION \
  --namespace tap-install \
  --values-file tap-values-full-ootb-testing.yaml


#CONFIGURE DNS NAME WITH ELB IP
echo "CONFIGURING DNS"

ingress=$(kubectl get svc envoy -n tanzu-system-ingress -o json | jq -r .status.loadBalancer.ingress[].hostname)
ip_address=$(nslookup $ingress | awk '/^Address:/ {A=$2}; END {print A}')

rm change-batch.json
cat <<EOF | tee change-batch.json
{
    "Comment": "Update IP address.",
    "Changes": [
        {
            "Action": "UPSERT",
            "ResourceRecordSet": {
                "Name": "*.$full_domain",
                "Type": "A",
                "TTL": 60,
                "ResourceRecords": [
                    {
                        "Value": "$ip_address"
                    }
                ]
            }
        }
    ]
}
EOF

hosted_zone_id=$(aws route53 list-hosted-zones --query HostedZones[0].Id --output text | awk -F '/' '{print $3}')
aws route53 change-resource-record-sets --hosted-zone-id $hosted_zone_id --change-batch file:///$HOME/change-batch.json


#CREATE TEKTON PIPELINE
kubectl delete -f pipeline-testing.yaml

rm pipeline-testing.yaml
cat <<'EOF' | tee pipeline-testing.yaml
apiVersion: tekton.dev/v1beta1
kind: Pipeline
metadata:
  name: tanzu-java-web-app-pipeline
  labels:
    apps.tanzu.vmware.com/pipeline: test      # (!) required
spec:
  params:
    - name: source-url                        # (!) required
    - name: source-revision                   # (!) required
  tasks:
    - name: test
      params:
        - name: source-url
          value: $(params.source-url)
        - name: source-revision
          value: $(params.source-revision)
      taskSpec:
        params:
          - name: source-url
          - name: source-revision
        steps:
          - name: test
            image: gradle
            securityContext:
              runAsUser: 0
            script: |-
              cd `mktemp -d`
              wget -qO- \$(params.source-url) | tar xvz -m
              chmod +x ./mvnw
              ./mvnw test
EOF

kubectl apply -f pipeline-testing.yaml


echo
echo http://tap-gui.${full_domain}
echo
echo "HAPPY TAP'ING"
echo
