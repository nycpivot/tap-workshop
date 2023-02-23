#!/bin/bash

read -p "AWS Region Code: " aws_region_code

aws_account_id=964978768106
tap_full_cluster=tap-full

arn=arn:aws:eks:${aws_region_code}:${aws_account_id}:cluster

aws eks update-kubeconfig --name $tap_full_cluster --region $aws_region_code

kubectl config rename-context ${arn}/${tap_full_cluster} $tap_full_cluster

kubectl config use-context $tap_full_cluster
