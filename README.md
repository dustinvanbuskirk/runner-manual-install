# runner-manual-install

Installing the [Codefresh runner](https://codefresh.io/docs/docs/enterprise/codefresh-runner/) manually

## What you need 

1. A computer with Linux that has bash/openssl/base64 installed
1. [Codefresh CLI](https://codefresh-io.github.io/cli/) installed (v0.30.0+)
1. `kubectl` installed and with access to the Kubernetes cluster that will host the Codefresh runner

## Step 1 - Prepare your cluster

First create a token that the runner will use for authentication (use any name you want)

```
codefresh create token behind-the-firewall
```

Note down the value. And export it as a variable

```
export API_TOKEN=5d4005badbb93850c1db7dsg345fggdfgcd7f71c6a246666182d
```

Create a namespace in your cluster that will hold the Codefresh runner and give it the privilages you want. The easiest way is to use the `default` namespace and give admin access to Codefresh.

```
kubectl create clusterrolebinding default-admin --clusterrole cluster-admin --serviceaccount=default:default
```

```
export NAMESPACE=default
```

Add your cluster to Codefresh. Here we use the name `my-cluster` for the integration.

```
codefresh create cluster my-cluster --namespace default --serviceaccount default --behind-firewall --kube-context my-gke-cluster-project-name
```
Export your cluster as a variable

```
export CLUSTER_NAME=my-cluster
```

## Step 2 - Select Codefresh runner version

Export the variables used in the manifests. The manifests can be found in the `assets` folder.

```
export APP_NAME=venona
export NAMESPACE=default
export CLUSTER_NAME=my-cluster
export API_TOKEN=5d4005badbb93850c1db7dsg345fggdfgcd7f71c6a246666182d
export API_HOST=https://g.codefresh.io
export VOLUME_IMAGE_NAME=codefresh/dind-volume-provisioner
export VOLUME_IMAGE_TAG=v13
export VERSION=1.0.0
export MODE=InCluster
export IMAGE_NAME=codefresh/venona
export IMAGE_TAG=0.24.0
```

## Step 3 - Create certificates, sign them and apply manifests

Run the following

```
chmod +x ./template.sh
chmod +x ./install-runner.sh
./install-runner.sh
```

After installation is complete you will see your new runtime environment in Codefresh and can use it in your pipelines. Please wait until all pods have finished their startup.

You can use the command `kubectl get pods` to see the progress.

The rendered manifests as they were applied are in `./tmp/codefresh/manifests`.


