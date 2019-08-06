# Helm Install

## [1] Run register-runner.sh

1. Set permission to execute registration script
`chmod +x ./register-runner.sh`
1. Run registration script 
`./register-runner.sh -h https://g.codefresh.io -t API_TOKEN -c CLUSTER_NAME -n KUBERNETES_NAMESPACE`

API_TOKEN is created here: https://g.codefresh.io/user/settings
Token Scope `Cluster - Full access of cluster resource`

Output contains values for values.yaml and example Helm command.

## [2] Deploy Chart

1. Update values.yaml with output from script above.
`token`
`ca`
`cert`
`key`
1. Run Helm Command
`helm upgrade --install --namespace codefresh-runtime codefresh-runner ./codefresh-runner`