#!/bin/bash

export TARGET_TBS_REPO=tap-build-service
export EKS_CLUSTER_NAME=tap-full
export TAP_VERSION=1.4.2
export OOTB_SUPPLY_CHAIN_VERSION=0.11.2


#INSTALL TAP WITH OOTB TESTING
echo
echo "<<< UPDATE SUPPLY CHAIN TO OOTB TESTING >>>"
echo

rm tap-values-full-ootb-testing.yaml
cat <<EOF | tee tap-values-full-ootb-testing.yaml
profile: full
ceip_policy_disclosed: true
shared:
  ingress_domain: "$FULL_DOMAIN"
supply_chain: testing
ootb_supply_chain_testing:
  registry:
    server: $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com
    repository: "tanzu-application-platform"
buildservice:
  kp_default_repository: $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$TARGET_TBS_REPO
  kp_default_repository_aws_iam_role_arn: "arn:aws:iam::$AWS_ACCOUNT_ID:role/$TARGET_TBS_REPO"
contour:
  infrastructure_provider: aws
  envoy:
    service:
      aws:
        LBType: nlb
ootb_templates:
  iaas_auth: true
tap_gui:
  service_type: LoadBalancer
  app_config:
    catalog:
      locations:
        - type: url
          target: https://github.com/nycpivot/$TARGET_TBS_REPO/catalog-info.yaml
metadata_store:
  ns_for_export_app_cert: "default"
  app_service_type: LoadBalancer
scanning:
  metadataStore:
    url: ""
grype:
  namespace: "default"
  targetImagePullSecret: "registry-credentials"
cnrs:
  domain_name: $FULL_DOMAIN
excluded_packages:
  - policy.apps.tanzu.vmware.com
EOF

tanzu package installed update tap -v $TAP_VERSION --values-file tap-values-full-ootb-testing.yaml -n tap-install


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
                "Name": "*.$FULL_DOMAIN",
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
echo http://tap-gui.$FULL_DOMAIN
echo
echo "HAPPY TAP'ING"
echo
