#!/bin/bash

export EKS_CLUSTER_NAME=tap-full
export TAP_VERSION=1.4.2

full_domain=full.tap.nycpivot.com
target_tbs_repo=tap-build-service
git_catalog_repository=tanzu-application-platform


#INSTALL TAP WITH OOTB TESTING
echo
echo "<<< UPDATE SUPPLY CHAIN TO OOTB TESTING >>>"
echo

rm tap-values-full-ootb-testing.yaml
cat <<EOF | tee tap-values-full-ootb-testing.yaml
profile: full
ceip_policy_disclosed: true
shared:
  ingress_domain: "${full_domain}"
supply_chain: testing
ootb_supply_chain_testing:
  registry:
    server: ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com
    repository: "tanzu-application-platform"
buildservice:
  kp_default_repository: ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${target_tbs_repo}
  kp_default_repository_aws_iam_role_arn: "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${target_tbs_repo}"
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
          target: https://github.com/nycpivot/${git_catalog_repository}/catalog-info.yaml
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
  domain_name: $full_domain
excluded_packages:
  - policy.apps.tanzu.vmware.com
EOF

tanzu package installed update tap -v $TAP_VERSION --values-file tap-values-full-ootb-testing.yaml -n tap-install
#tanzu package installed get tap -n tap-install
#tanzu package installed list -A

#tanzu apps cluster-supply-chain list


#CONFIGURE DNS NAME WITH ELB IP
echo "CONFIGURING DNS"

kubectl get svc -n tanzu-system-ingress

read -p "Tanzu System Ingress IP: " external_ip

nslookup $external_ip
read -p "IP Address: " ip_address

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
