read -p "AWS Region Code (us-west-1): " aws_region_code

if [[ -z $aws_region_code ]]
then
	aws_region_code=us-west-1
fi

kubectl config use-context tap-full

#INSTALL CROSSPLANE IN NAMESPACE
kubectl create namespace crossplane-system

helm repo add crossplane-stable https://charts.crossplane.io/stable
helm repo update

helm install crossplane --namespace crossplane-system crossplane-stable/crossplane \
  --set 'args={--enable-external-secret-stores}'