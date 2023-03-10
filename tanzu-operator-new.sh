#!/bin/bash

read -p "AWS Region Code: " aws_region_code

aws cloudformation delete-stack --region $aws_region_code --stack-name tanzu-operator-stack

aws cloudformation create-stack --region $aws_region_code --stack-name tanzu-operator-stack --template-body file://config/tanzu-operator-stack.yaml

aws cloudformation wait stack-create-complete --stack-name tanzu-operator-stack --region $aws_region_code

aws cloudformation describe-stacks --stack-name tanzu-operator-stack --region $aws_region_code --query "Stacks[0].Outputs[?OutputKey=='PublicDnsName'].OutputValue" --output text
