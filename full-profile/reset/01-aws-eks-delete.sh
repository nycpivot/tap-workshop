#!/bin/bash

#aws elb describe-load-balancers
#aws elb delete-load-balancer --load-balancer-name ad09633adaf51437ab2ef70c6b07e476

aws ecr delete-repository --repository-name tap-images --region $AWS_REGION_CODE
aws ecr delete-repository --repository-name tap-build-service --region $AWS_REGION_CODE

arn=arn:aws:eks:${AWS_REGION_CODE}:${AWS_ACCOUNT_ID}:cluster

aws cloudformation delete-stack --stack-name tap-workshop-singlecluster-stack --region $AWS_REGION_CODE
aws cloudformation wait stack-delete-complete --stack-name tap-workshop-singlecluster-stack --region $AWS_REGION_CODE

rm .kube/config
