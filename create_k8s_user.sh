#!/usr/bin/env bash
# args1 cluster name
# args2 namespace 
# args3 user name
# args4 certificate name 
# args5 configfile

#pip install shyaml

set -e
set -o pipefail
if [ ! -f ca.crt ] && [ ! -f ca.key ];then
	echo "no ca files"
	exit 1
fi

if [ -f role.yaml ] || [ -f rolebinding.yaml ];then
	echo "found role.yaml"
	exit 3
fi

args_num=$#
if [ ! ${args_num} -eq 5 ];then
	echo "lack args"
	exit 2
fi

cluster_name=$1
namespace=$2
user_name=$3
certificate_name=$4
configfile=$5

if [ ! -f ${configfile} ];then
    echo "no kubectl config file"
fi

kubectl create namespace ${namespace}
openssl genrsa -out ${certificate_name}.key 2048
# CN组名
openssl req -new -key "${certificate_name}.key" -out ${certificate_name}.csr -subj "/CN=${user_name}/O=bitnami"
openssl x509 -req -in ${certificate_name}.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out ${certificate_name}.crt -days 500
kubectl config set-credentials ${user_name} --embed-certs=true --client-certificate=${certificate_name}.crt  --client-key=${certificate_name}.key
kubectl config set-context ${user_name}-context --cluster=${cluster_name} --namespace=${namespace} --user=${user}

cluster_n=$(cat $configfile |shyaml get-length clusters)
for i in `seq 1 $cluster_n`
do
  n=$((i-1))
  if cat $configfile |shyaml get-value clusters.${n}|grep -q "name: ${cluster_name}";then
      clusters_certificate_authority_data=$(cat $configfile |shyaml get-value clusters.${n}.cluster.certificate-authority-data)
      server=$(cat $configfile |shyaml get-value clusters.${n}.cluster.server)
  fi
done

users_n=$(cat $configfile |shyaml get-length users)
for i in `seq 1 $users_n`
do
  n=$((i-1))
    if cat $configfile |shyaml get-value users.${n}|grep -q "name: ${user_name}";then
        user_certificate_authority_data=$(cat $configfile |shyaml get-value users.${n}.user.client-certificate-data)
        client_key_data=$(cat $configfile |shyaml get-value users.${n}.user.client-key-data)
  fi
done

cat << EOF > config.result
apiVersion: v1
clusters:
- cluster:
    certificate-authority-data: ${clusters_certificate_authority_data}
    server: ${server} 
  name: ${cluster_name}
contexts:
- context:
    cluster: ${cluster_name}
    namespace: ${namespace}
    user: ${user_name}
  name: ${user_name}-context
current-context: ${user_name}-context
kind: Config
preferences: {}
users:
- name: ${user_name}
  user:
    as-user-extra: {}
    client-certificate-data: ${user_certificate_authority_data}
    client-key-data: ${client_key_data}
EOF
cat << EOF > role.yaml
kind: Role
apiVersion: rbac.authorization.k8s.io/v1beta1
metadata:
  namespace: ${namespace}
  name: deployment-manager
rules:
- apiGroups: ["", "extensions", "apps"]
  resources: ["*"]
  verbs: ["*"]
EOF

cat << EOF > rolebinding.yaml 
kind: RoleBinding
apiVersion: rbac.authorization.k8s.io/v1beta1
metadata:
  name: deployment-manager-binding
  namespace: ${namespace}
subjects:
- kind: User
  name: ${user_name}
  apiGroup: ""
roleRef:
  kind: Role
  name: deployment-manager
  apiGroup: ""
EOF

kubectl create -f ./role.yaml
kubectl create -f ./rolebinding.yaml
echo "please follow the bellow command to use the new configfile\n"
echo "unset KUBECONFIG && export KUBECONFIG=$KUBECONFIG:./config.result"

