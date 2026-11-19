# Tear everything down

Back to the [README](../README.md).

This page removes everything the guide creates, in an order that avoids leftovers: the AI Gateway first (which also deletes its load balancer), then AgentCore, DNS and the certificate, the Helm releases, the EKS cluster, and finally IAM. The EKS cluster and the AgentCore runtime are the main ongoing costs, so if you only have a few minutes, do sections 1 to 5.

> **Not yet run end to end.** These commands follow the resources the guide creates, but this teardown hasn't been tested as a whole. Read each block before running it, and check the output before moving on. Commands that look things up print `not found` instead of failing when something is already gone.

## 0. Set the names you used

Run everything in one terminal. Adjust these if you changed names or added suffixes in a shared account (for example `bedrock-policy-kong314`):

```bash
export AWS_REGION=us-west-2
export CLUSTER=kong314
export AWS_DOMAIN=<your domain>
export PAT=<your Konnect personal access token>

export LBC_POLICY=AWSLoadBalancerControllerIAMPolicy
export LBC_ROLE=AWSLoadBalancerControllerIAMRole-kong314
export KONG_POLICY=bedrock-policy
export KONG_ROLE=kaigateway-aws-podid-role

export HOSTED_ZONE_ID=$(aws route53 list-hosted-zones --query "HostedZones[?Name=='$AWS_DOMAIN.'].Id" --output text | cut -d'/' -f3)
export CERTIFICATE_ARN=$(aws acm list-certificates --region $AWS_REGION \
  --query "CertificateSummaryList[?DomainName=='*.$AWS_DOMAIN'].CertificateArn | [0]" --output text)
echo "zone=$HOSTED_ZONE_ID cert=$CERTIFICATE_ARN"
```

Both values should print. If `cert` shows `None`, the certificate is already gone.

These helpers delete one DNS record, one IAM role or one IAM policy by name. They look the resource up first, so you don't need its details:

```bash
del_record() {
  local rec
  rec=$(aws route53 list-resource-record-sets --hosted-zone-id "$HOSTED_ZONE_ID" \
    --query "ResourceRecordSets[?Name=='$1' && Type=='$2'] | [0]" --output json)
  if [ "$rec" = "null" ]; then echo "not found: $1 $2"; return; fi
  aws route53 change-resource-record-sets --hosted-zone-id "$HOSTED_ZONE_ID" \
    --change-batch "$(jq -n --argjson r "$rec" '{Changes:[{Action:"DELETE",ResourceRecordSet:$r}]}')" \
    --query ChangeInfo.Status --output text
}
del_role() {
  aws iam get-role --role-name "$1" >/dev/null 2>&1 || { echo "not found: $1"; return; }
  for arn in $(aws iam list-attached-role-policies --role-name "$1" --query 'AttachedPolicies[].PolicyArn' --output text); do
    aws iam detach-role-policy --role-name "$1" --policy-arn "$arn"
  done
  aws iam delete-role --role-name "$1" && echo "deleted role $1"
}
del_policy() {
  local arn
  arn=$(aws iam list-policies --scope Local --query "Policies[?PolicyName=='$1'].Arn" --output text)
  if [ -z "$arn" ]; then echo "not found: $1"; return; fi
  for v in $(aws iam list-policy-versions --policy-arn "$arn" --query 'Versions[?!IsDefaultVersion].VersionId' --output text); do
    aws iam delete-policy-version --policy-arn "$arn" --version-id "$v"
  done
  aws iam delete-policy --policy-arn "$arn" && echo "deleted policy $1"
}
```

## 1. AI Gateway, data plane and echo backend (Steps 2 and 4)

Delete the data plane first (this also deletes its NLB), then the AI Gateway. The Kong Operator removes the gateway from Konnect when its resource is deleted, which should remove its agents, MCP servers, models, providers and auth strategies with it. Do this while the operator is still running.

```bash
kubectl -n kong delete service,deployment httpbin --ignore-not-found
kubectl delete aigatewaydataplane kong-aws-ai-dp -n kong --wait=true
kubectl delete konnectaigateway kong-aws-ai -n kong --wait=true
kubectl delete konnectapiauthconfiguration konnect-api-auth-conf -n kong
del_record "ai-dp.$AWS_DOMAIN." A
```

Check in Konnect that **AI Gateway → Gateways** no longer lists **Kong AWS AI Gateway**. If it does, delete it there.

Then confirm that the load balancer is gone. This can take a minute or two after the service is deleted:

```bash
kubectl get svc -A | grep LoadBalancer
aws elbv2 describe-load-balancers --region $AWS_REGION --query "LoadBalancers[?starts_with(LoadBalancerName, 'k8s-kong')].LoadBalancerName" --output text
```

Both commands should print nothing. If an NLB is left over after a few minutes, delete it in the EC2 console (**Load Balancers**), otherwise it keeps billing after the cluster is gone.

## 2. Kong Operator

```bash
helm uninstall kong-operator -n kong-system
kubectl delete namespace kong kong-system --ignore-not-found
```

If `kubectl delete namespace kong` hangs, a Kong resource still has a finalizer the operator didn't clear. Press Ctrl+C, list what's left with `kubectl api-resources --verbs=list --namespaced -o name | xargs -n1 kubectl get -n kong --ignore-not-found --show-kind`, and delete it in Konnect by hand.

## 3. Kong Identity (Step 5)

```bash
AUTHZ_SERVER_ID=$(curl -s "https://us.api.konghq.com/v1/auth-servers" -H "Authorization: Bearer $PAT" \
  | jq -r '.data[] | select(.name=="AuthZ_Server_1") | .id')
echo "auth server: $AUTHZ_SERVER_ID"
curl -s -o /dev/null -w "delete: %{http_code}\n" -X DELETE "https://us.api.konghq.com/v1/auth-servers/$AUTHZ_SERVER_ID" \
  -H "Authorization: Bearer $PAT"
```

You want a `204`. Its scope, claim and client should go with it, and tokens it issued stop validating. Check under **Identity** in Konnect.

## 4. AgentCore runtime (Step 3)

Run this in the AgentCore project folder (`agentcorekong`). Removing everything from the project and deploying again deletes the runtime and the project's CloudFormation stack:

```bash
agentcore remove all -y
agentcore deploy --region $AWS_REGION --yes
aws bedrock-agentcore-control list-agent-runtimes --region $AWS_REGION \
  --query "agentRuntimes[?starts_with(agentRuntimeName, 'agentcorekong')].agentRuntimeName" --output text
aws cloudformation list-stacks --region $AWS_REGION --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE \
  --query "StackSummaries[?starts_with(StackName, 'AgentCore-agentcorekong')].StackName" --output text
```

Both commands should print nothing. If a stack is still listed, delete it with `aws cloudformation delete-stack --region $AWS_REGION --stack-name <that name>`.

The CDK bootstrap stack (`CDKToolkit`) was created on the first deploy if your account didn't have one. Leave it unless you know nothing else in the account uses CDK. Deleting it also requires emptying its S3 bucket first.

## 5. EKS cluster and Load Balancer Controller (Step 1)

Uninstall the controller only after section 1 confirmed the NLB is gone, otherwise nothing is left to clean them up. Then delete the cluster, which takes about 10 to 15 minutes:

```bash
helm uninstall aws-load-balancer-controller -n kube-system
eksctl delete cluster --name $CLUSTER --region $AWS_REGION --wait
```

`eksctl` also deletes the node group, the Pod Identity add-on and associations, and the CloudFormation stacks it created, usually including the IAM roles it made for the Pod Identity associations.

## 6. Certificate and validation record (Step 1)

```bash
VALIDATION_NAME=$(aws acm describe-certificate --certificate-arn $CERTIFICATE_ARN --region $AWS_REGION \
  --query 'Certificate.DomainValidationOptions[0].ResourceRecord.Name' --output text)
aws acm delete-certificate --certificate-arn $CERTIFICATE_ARN --region $AWS_REGION && echo "certificate deleted"
del_record "$VALIDATION_NAME" CNAME
```

If `delete-certificate` says the certificate is in use, a load balancer still references it. Go back to section 1.

## 7. IAM roles and policies (Steps 1 and 2)

Roles first, then policies. A policy that's still attached to something won't delete, which protects anything else using it.

```bash
del_role $LBC_ROLE
del_role $KONG_ROLE
del_policy $LBC_POLICY
del_policy $KONG_POLICY
```

> **Shared account?** Only delete names you created. If `AWSLoadBalancerControllerIAMPolicy` already existed before you started and you used a suffixed name instead, set `LBC_POLICY` to your suffixed name.

## 8. Domain and hosted zone (optional)

Skip this if you used a domain you're keeping. A hosted zone costs a small monthly fee while it exists, and a domain registered in Step 1 renews automatically. To stop both:

```bash
aws route53 list-resource-record-sets --hosted-zone-id $HOSTED_ZONE_ID \
  --query "ResourceRecordSets[?Type!='NS' && Type!='SOA'].[Name,Type]" --output text
aws route53 delete-hosted-zone --id $HOSTED_ZONE_ID
aws route53domains disable-domain-auto-renew --domain-name $AWS_DOMAIN --region us-east-1
```

The first command must print nothing. A hosted zone can't be deleted while it still has records other than `NS` and `SOA`, so delete any it lists with `del_record`. Without the zone, the domain stops resolving.

## 9. Credentials and local files

- **Konnect personal access token:** revoke it in Konnect (your initials → **Personal Access Tokens**). It was also stored in the cluster, which is gone, and possibly in a kongctl profile (`~/.config/kongctl/config.yaml`).
- **Working folders:** the AgentCore project and `mcp-headers.txt` from the steps. None of them hold secrets, but you can delete them.

## Check that nothing is still running

```bash
eksctl get cluster --region $AWS_REGION
aws elbv2 describe-load-balancers --region $AWS_REGION --query 'LoadBalancers[].LoadBalancerName' --output text
aws bedrock-agentcore-control list-agent-runtimes --region $AWS_REGION --query 'agentRuntimes[].agentRuntimeName' --output text
```

None of these should list anything from this guide. Check the **Billing** console a day later as well.
