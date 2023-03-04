#!/bin/bash
#https://docs.vmware.com/en/Services-Toolkit-for-VMware-Tanzu-Application-Platform/0.9/svc-tlk/usecases-consuming_aws_rds_with_crossplane.html
#https://docs.crossplane.io/v1.9/getting-started/install-configure/#install-tab-helm3

read -p "AWS Region Code (us-west-1): " aws_region_code

if [[ -z $aws_region_code ]]
then
	aws_region_code=us-west-1
fi

#INSTALL AWS PROVIDER
cat <<EOF | tee provider-aws.yaml
apiVersion: pkg.crossplane.io/v1
kind: Provider
metadata:
 name: provider-aws
spec:
 package: xpkg.upbound.io/crossplane-contrib/provider-aws:v0.33.0
EOF

kubectl apply -f provider-aws.yaml

rm provider-aws.yaml

#EXTRACT AWS CREDS TO CREATE A FILE, USED TO CREATE A SECRET THAT PROVIDER CONFIG BELOW WILL BE ABLE TO USE TO CREATE RESOURCES
echo -e "[default]\naws_access_key_id = $(aws configure get aws_access_key_id)\naws_secret_access_key = $(aws configure get aws_secret_access_key)\naws_session_token = $(aws configure get aws_session_token)" > creds.conf

kubectl create secret generic aws-provider-creds -n crossplane-system --from-file=creds=./creds.conf

cat <<EOF | tee provider-config.yaml
apiVersion: aws.crossplane.io/v1beta1
kind: ProviderConfig
metadata:
 name: default
spec:
 credentials:
   source: Secret
   secretRef:
     namespace: crossplane-system
     name: aws-provider-creds
     key: creds
EOF

kubectl apply -f provider-config.yaml

rm -f creds.conf
rm provider-config.yaml

#CREATE POSTGRES COMPOSITE RESOURCE DEFINITION
cat <<EOF | tee xrd.yaml
apiVersion: apiextensions.crossplane.io/v1
kind: CompositeResourceDefinition
metadata:
 name: xpostgresqlinstances.bindable.database.example.org
spec:
 claimNames:
   kind: PostgreSQLInstance
   plural: postgresqlinstances
 connectionSecretKeys:
 - type
 - provider
 - host
 - port
 - database
 - username
 - password
 group: bindable.database.example.org
 names:
   kind: XPostgreSQLInstance
   plural: xpostgresqlinstances
 versions:
 - name: v1alpha1
   referenceable: true
   schema:
     openAPIV3Schema:
       properties:
         spec:
           properties:
             parameters:
               properties:
                 storageGB:
                   type: integer
               required:
               - storageGB
               type: object
           required:
           - parameters
           type: object
       type: object
   served: true
EOF

kubectl apply -f xrd.yaml

rm xrd.yaml


#CREATE POSTGRES COMPOSITION
cat <<EOF | tee composition.yaml
apiVersion: apiextensions.crossplane.io/v1
kind: Composition
metadata:
 labels:
   provider: "aws"
   vpc: "default"
 name: xpostgresqlinstances.bindable.aws.database.example.org
spec:
 compositeTypeRef:
   apiVersion: bindable.database.example.org/v1alpha1
   kind: XPostgreSQLInstance
 publishConnectionDetailsWithStoreConfigRef:
   name: default
 resources:
 - base:
     apiVersion: database.aws.crossplane.io/v1beta1
     kind: RDSInstance
     spec:
       forProvider:
         dbInstanceClass: db.t2.micro
         engine: postgres
         dbName: postgres
         engineVersion: "12"
         masterUsername: masteruser
         publiclyAccessible: true
         region: $aws_region_code
         skipFinalSnapshotBeforeDeletion: true
       writeConnectionSecretToRef:
         namespace: crossplane-system
   connectionDetails:
   - name: type
     value: postgresql
   - name: provider
     value: aws
   - name: database
     value: postgres
   - fromConnectionSecretKey: username
   - fromConnectionSecretKey: password
   - name: host
     fromConnectionSecretKey: endpoint
   - fromConnectionSecretKey: port
   name: rdsinstance
   patches:
   - fromFieldPath: metadata.uid
     toFieldPath: spec.writeConnectionSecretToRef.name
     transforms:
     - string:
         fmt: '%s-postgresql'
         type: Format
       type: string
     type: FromCompositeFieldPath
   - fromFieldPath: spec.parameters.storageGB
     toFieldPath: spec.forProvider.allocatedStorage
     type: FromCompositeFieldPath
EOF

kubectl apply -f composition.yaml

rm composition.yaml

#CREATE RDS DATABASE INSTANCE HERE (WILL BE VISIBLE IN CONSOLE)
cat <<EOF | tee postgres-instance.yaml
apiVersion: bindable.database.example.org/v1alpha1
kind: PostgreSQLInstance
metadata:
 name: rds-postgres-db
 namespace: default
spec:
 parameters:
   storageGB: 20
 compositionSelector:
   matchLabels:
     provider: aws
     vpc: default
 publishConnectionDetailsTo:
   name: rds-postgres-db
   metadata:
     labels:
       services.apps.tanzu.vmware.com/class: rds-postgres
EOF

kubectl apply -f postgres-instance.yaml

rm postgres-instance.yaml

#wait for rds-postgres-db secret to be created when database is finished creating
kubectl get secrets -w

#kubectl get secret rds-postgres-db -o yaml
#kubectl get secret rds-postgres-db -o jsonpath='{.data.host}' | base64 --decode

#aws rds describe-db-instances --region $aws_region_code | jq [.DBInstances[].Endpoint.Address]

#CREATE SERVICE INSTANCE CLASS, TO MAKE AVAILABLE TO MAKE CLAIM
cat <<EOF | tee cluster-instance.yaml
apiVersion: services.apps.tanzu.vmware.com/v1alpha1
kind: ClusterInstanceClass
metadata:
  name: rds-postgres
spec:
  description:
    short: AWS RDS Postgresql database instances
  pool:
    kind: Secret
    labelSelector:
      matchLabels:
        services.apps.tanzu.vmware.com/class: rds-postgres
    fieldSelector: type=connection.crossplane.io/v1alpha1
EOF

kubectl apply -f cluster-instance.yaml

rm cluster-instance.yaml

cat <<EOF | tee stk-role.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: stk-secret-reader
  labels:
    servicebinding.io/controller: "true"
rules:
- apiGroups:
  - ""
  resources:
  - secrets
  verbs:
  - get
  - list
  - watch
EOF

kubectl apply -f stk-role.yaml

rm stk-role.yaml

#tanzu service classes list

#THIS WILL THROW ERROR IF IT'S RUN FOR THE FIRST TIME
tanzu service resource-claim delete rds-claim --yes

#tanzu services claimable list --class rds-postgres

tanzu service resource-claim create rds-claim \
--resource-name rds-postgres-db \
--resource-kind Secret \
--resource-api-version v1

#tanzu services resource-claims get rds-claim --namespace default

tanzu services resource-claims list -o wide
