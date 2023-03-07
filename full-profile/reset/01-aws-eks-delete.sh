#!/bin/bash

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




#aws elb describe-load-balancers
#aws elb delete-load-balancer --load-balancer-name ad09633adaf51437ab2ef70c6b07e476

aws ecr delete-repository --repository-name tap-images --region $AWS_REGION_CODE --force
aws ecr delete-repository --repository-name tap-build-service --region $AWS_REGION_CODE --force
aws ecr delete-repository --repository-name tanzu-application-platform/tanzu-java-web-app-default --region $AWS_REGION_CODE --force
aws ecr delete-repository --repository-name tanzu-application-platform/tanzu-java-web-app-default-bundle --region $AWS_REGION_CODE --force

aws cloudformation delete-stack --stack-name tap-workshop-singlecluster-stack --region $AWS_REGION_CODE
aws cloudformation wait stack-delete-complete --stack-name tap-workshop-singlecluster-stack --region $AWS_REGION_CODE

rm .kube/config
