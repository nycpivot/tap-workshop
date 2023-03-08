#!/bin/bash

classic_lb=$(aws elb describe-load-balancers | jq -r .LoadBalancerDescriptions[].LoadBalancerName)
network_lb=$(aws elbv2 describe-load-balancers | jq -r .LoadBalancers[].LoadBalancerName)

aws elb delete-load-balancer --load-balancer-name $classic_lb
aws elbv2 delete-load-balancer --load-balancer-name $network_lb

aws ecr delete-repository --repository-name tap-images --region $AWS_REGION_CODE --force
aws ecr delete-repository --repository-name tap-build-service --region $AWS_REGION_CODE --force
aws ecr delete-repository --repository-name tanzu-application-platform/tanzu-java-web-app-default --region $AWS_REGION_CODE --force
aws ecr delete-repository --repository-name tanzu-application-platform/tanzu-java-web-app-default-bundle --region $AWS_REGION_CODE --force

aws cloudformation delete-stack --stack-name tap-workshop-singlecluster-stack --region $AWS_REGION_CODE
aws cloudformation wait stack-delete-complete --stack-name tap-workshop-singlecluster-stack --region $AWS_REGION_CODE

rm .kube/config


#hosted_zones_count=$(aws route53 get-hosted-zone-count | jq .HostedZoneCount)
#hosted_zones=$(aws route53 list-hosted-zones | jq -r .HostedZones)
#hosted_zones_count=$(echo $hosted_zones | jq length)

#index=0
#while [ $index -lt ${hosted_zones_count} ]
#do
#  hosted_zone_name=$(aws route53 list-hosted-zones | jq -r .HostedZones[$index].Name)
#  counter=`expr $index + 1`
#  index=`expr $index + 1`
  
#  echo "$counter) $hosted_zone_name"
#done